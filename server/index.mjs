import http from 'node:http';
import {timingSafeEqual} from 'node:crypto';
import {mkdir, readdir, readFile, rename, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {conversation, voice} from './providers.mjs';

function send(res, status, payload) {
  res.writeHead(status, {'Content-Type': 'application/json', 'Cache-Control': 'no-store'});
  res.end(JSON.stringify(payload));
}
function authorized(req, token) {
  const actual = Buffer.from(req.headers.authorization ?? '');
  const expected = Buffer.from(`Bearer ${token}`);
  return token.length >= 24 && actual.length === expected.length && timingSafeEqual(actual, expected);
}
async function body(req) {
  let bytes = 0, parts = [];
  for await (const part of req) {
    bytes += part.length;
    if (bytes > 8192) throw new Error('Request too large');
    parts.push(part);
  }
  return JSON.parse(Buffer.concat(parts).toString('utf8'));
}
const languages = new Set(['hi', 'pa', 'en']);
const triggers = new Set(['prolongedClosure', 'closureTrend', 'repeatedYawns', 'repeatedNods', 'noResponse']);
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;

export async function createApp(config) {
  const {token, dataDir, openAIKey, smallestKey, fleetURL = '', fleetToken = '', model = 'gpt-5-nano', fetcher = fetch} = config;
  if (!token || token.length < 24) throw new Error('APP_TOKEN must contain at least 24 characters');
  if (fleetURL && !fleetURL.startsWith('https://')) throw new Error('Fleet webhook must use HTTPS');
  await mkdir(dataDir, {recursive: true, mode: 0o700});
  const limits = new Map();
  let flushing = false;
  const eventLocks = new Map();
  async function withEventLock(id, operation) {
    const key = id.toLowerCase();
    const next = (eventLocks.get(key) ?? Promise.resolve()).catch(() => {}).then(operation);
    eventLocks.set(key, next);
    try { return await next; } finally { if (eventLocks.get(key) === next) eventLocks.delete(key); }
  }
  const fileFor = id => path.join(dataDir, `${id.toLowerCase()}.json`);
  async function save(event) {
    const file = fileFor(event.id), temp = `${file}.tmp`;
    await writeFile(temp, JSON.stringify(event), {mode: 0o600}); await rename(temp, file);
  }
  async function load(id) {
    try { return JSON.parse(await readFile(fileFor(id), 'utf8')); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
  }
  async function flush() {
    if (!fleetURL || flushing) return;
    flushing = true;
    try {
      for (const file of await readdir(dataDir)) {
        if (!file.endsWith('.json')) continue;
        const event = JSON.parse(await readFile(path.join(dataDir, file), 'utf8'));
        if (event.delivery === 'delivered' || event.simulated || event.nextAttempt > Date.now()) continue;
        try {
          const reply = await fetcher(fleetURL, {method: 'POST', signal: AbortSignal.timeout(5000),
            headers: {'Content-Type': 'application/json', 'Idempotency-Key': event.id,
              ...(fleetToken ? {'Authorization': `Bearer ${fleetToken}`} : {})},
            body: JSON.stringify(event)});
          if (!reply.ok) throw new Error('Fleet endpoint rejected event');
          event.delivery = 'delivered'; event.deliveredAt = new Date().toISOString();
        } catch {
          event.delivery = 'failed'; event.attempts = (event.attempts ?? 0) + 1;
          event.nextAttempt = Date.now() + Math.min(300000, 5000 * 2 ** Math.min(6, event.attempts));
        }
        await save(event);
      }
    } finally { flushing = false; }
  }
  const retry = setInterval(() => { flush().catch(() => {}); }, 5000); retry.unref();
  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://localhost');
      if (req.method === 'GET' && url.pathname === '/health') return send(res, 200, {ok: true});
      if (!authorized(req, token)) return send(res, 401, {error: 'Unauthorized'});
      if (req.method === 'GET' && url.pathname === '/v1/status') return send(res, 200, {
        conversationConfigured: Boolean(openAIKey), speechConfigured: Boolean(smallestKey),
        fleetConfigured: Boolean(fleetURL), model});
      const ip = req.socket.remoteAddress, now = Date.now();
      const bucket = limits.get(ip);
      if (!bucket || now - bucket.start > 60000) limits.set(ip, {start: now, count: 1});
      else if (++bucket.count > 40) return send(res, 429, {error: 'Please retry shortly'});
      if (limits.size > 1000) for (const [address, limit] of limits) if (now - limit.start > 60000) limits.delete(address);
      if (req.method === 'GET' && url.pathname.startsWith('/v1/events/')) {
        const id = url.pathname.split('/').pop();
        if (!uuid.test(id)) return send(res, 400, {error: 'Invalid event ID'});
        const event = await load(id);
        return send(res, event ? 200 : 404, event ? {id, delivery: event.delivery, simulated: event.simulated} : {error: 'Event not found'});
      }
      if (req.method !== 'POST') return send(res, 404, {error: 'Not found'});
      if (!['/v1/conversation', '/v1/voice', '/v1/events'].includes(url.pathname)) return send(res, 404, {error: 'Not found'});
      const input = await body(req);
      if (!input || typeof input !== 'object' || Array.isArray(input)) return send(res, 400, {error: 'Request must be an object'});
      if (url.pathname === '/v1/events') {
        if (!uuid.test(input.id ?? '') || !triggers.has(input.trigger) ||
            typeof input.simulated !== 'boolean' || typeof input.timestamp !== 'string' || !Number.isFinite(Date.parse(input.timestamp)))
          return send(res, 400, {error: 'Invalid event'});
        const result = await withEventLock(input.id, async () => {
          const existing = await load(input.id);
          if (existing) return {status: 200, event: existing};
          const event = {id: input.id, timestamp: input.timestamp, trigger: input.trigger,
            simulated: input.simulated, delivery: 'stored', attempts: 0,
            receivedAt: new Date().toISOString()};
          await save(event); return {status: 202, event};
        });
        flush().catch(() => {});
        return send(res, result.status, {id: result.event.id, delivery: result.event.delivery, simulated: result.event.simulated});
      }
      if (!languages.has(input.language)) return send(res, 400, {error: 'Unsupported language'});
      if (url.pathname === '/v1/conversation') {
        if (typeof input.transcript !== 'string' || !input.transcript.trim() || input.transcript.length > 500)
          return send(res, 400, {error: 'Invalid transcript'});
        const text = await conversation({key: openAIKey, model, transcript: input.transcript, language: input.language, fetcher});
        return send(res, 200, {text});
      }
      if (typeof input.text !== 'string' || !input.text.trim() || input.text.length > 600)
        return send(res, 400, {error: 'Invalid speech text'});
      const audio = await voice({key: smallestKey, text: input.text, language: input.language, fetcher});
      res.writeHead(200, {'Content-Type': 'audio/wav', 'Cache-Control': 'no-store'}); res.end(audio);
    } catch (error) {
      // Never log request bodies, provider payloads, Authorization headers, or secrets.
      send(res, error instanceof SyntaxError || error.message === 'Request too large' ? 400 : 503,
        {error: 'Service unavailable; use the local voice prompts'});
    }
  });
  server.headersTimeout = 10000; server.requestTimeout = 15000;
  server.on('close', () => clearInterval(retry));
  flush().catch(() => {});
  return server;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const server = await createApp({token: process.env.APP_TOKEN,
    dataDir: path.join(path.dirname(fileURLToPath(import.meta.url)), 'data'),
    openAIKey: process.env.OPENAI_API_KEY, smallestKey: process.env.SMALLEST_API_KEY,
    model: process.env.OPENAI_MODEL || 'gpt-5-nano', fleetURL: process.env.FLEET_WEBHOOK_URL,
    fleetToken: process.env.FLEET_WEBHOOK_TOKEN});
  server.listen(Number(process.env.PORT || 8787), process.env.HOST || '127.0.0.1', () => {
    console.log(`Jaagte Raho backend listening on port ${process.env.PORT || 8787}. Credentials are server-side only.`);
  });
}
