import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm, readdir, readFile} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {once} from 'node:events';
import {randomUUID} from 'node:crypto';
import {createApp} from './index.mjs';
import {conversation, voice, ProviderError} from './providers.mjs';
const token = 'test-token-for-local-validation-only';
async function fixture(t, overrides = {}) {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'raho-test-'));
  const server = await createApp({token, dataDir: dir, ...overrides});
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(async () => { server.closeAllConnections(); await new Promise(r => server.close(r)); await rm(dir, {recursive:true, force:true}); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const req = (route, data, auth = true) => fetch(base + route, {method: data ? 'POST' : 'GET',
    headers: {...(auth ? {Authorization: `Bearer ${token}`} : {}), 'Content-Type':'application/json'},
    ...(data ? {body:JSON.stringify(data)} : {})});
  return {req, dir, base};
}
async function eventually(check, timeout = 1500) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const value = await check();
    if (value) return value;
    await new Promise(r => setTimeout(r, 10));
  }
  assert.fail('Expected asynchronous state before timeout');
}
test('provider routes require authentication', async t => {
  const {req} = await fixture(t);
  assert.equal((await req('/v1/status', null, false)).status, 401);
  assert.equal((await req('/v1/status')).status, 200);
});
test('events are durable and deduplicated, without pretending to notify the owner', async t => {
  const {req, dir} = await fixture(t);
  const event = {id:randomUUID(),timestamp:new Date().toISOString(),trigger:'prolongedClosure',simulated:false};
  assert.equal((await req('/v1/events', event)).status, 202);
  const replay = await req('/v1/events', event);
  assert.equal(replay.status, 200); assert.equal((await replay.json()).delivery, 'stored');
  assert.equal((await readdir(dir)).length, 1);
  assert.equal((await (await req(`/v1/events/${event.id}`)).json()).delivery, 'stored');
});
test('invalid IDs and missing simulated flag cannot enter the outbox', async t => {
  const {req, dir} = await fixture(t);
  assert.equal((await req('/v1/events', {id:'../../secret',trigger:'noResponse'})).status, 400);
  assert.equal((await req('/v1/events', {id:randomUUID(),trigger:'noResponse',timestamp:new Date().toISOString()})).status, 400);
  assert.equal((await readdir(dir)).length, 0);
});
test('demo alerts never reach the fleet webhook', async t => {
  let calls = 0;
  const {req} = await fixture(t, {fleetURL:'https://example.com/webhook',fetcher:async () => { calls++; return new Response('{}'); }});
  const event = {id:randomUUID(),timestamp:new Date().toISOString(),trigger:'noResponse',simulated:true};
  await req('/v1/events', event);
  await new Promise(r => setTimeout(r, 50));
  assert.equal(calls, 0);
});
test('cloud failures return a local fallback with no leaked credentials', async t => {
  const {req} = await fixture(t, {openAIKey:'secret-test-value', fetcher:async () => new Response('{}',{status:401})});
  const response = await req('/v1/conversation', {transcript:'हाँ',language:'hi'});
  assert.equal(response.status,503); assert.ok(!(await response.text()).includes('secret-test-value'));
});
test('conversation uses the permitted model and disables storage', async () => {
  let payload;
  const text = await conversation({key:'fake', transcript:'हाँ',language:'hi',fetcher:async (url, init) => {
    payload = JSON.parse(init.body);
    return new Response(JSON.stringify({status:'completed',output:[{type:'message',content:[{type:'output_text',text:'सुरक्षित जगह पर रुक कर आराम करो।'}]}]}));
  }});
  assert.equal(payload.model,'gpt-5-nano'); assert.equal(payload.store,false);
  assert.equal(payload.reasoning.effort,'minimal'); assert.ok(text.length > 0);
});
test('simultaneous duplicate alerts are atomic and deduplicated', async t => {
  const {req, dir} = await fixture(t);
  const event = {id:randomUUID(),timestamp:new Date().toISOString(),trigger:'noResponse',simulated:false};
  const responses = await Promise.all(Array.from({length:12}, () => req('/v1/events',event)));
  assert.equal(responses.filter(r => r.status === 202).length,1);
  assert.equal(responses.filter(r => r.status === 200).length,11);
  assert.equal((await readdir(dir)).length,1);
  const saved = JSON.parse(await readFile(path.join(dir,`${event.id}.json`),'utf8'));
  assert.equal(saved.id,event.id); assert.equal(saved.trigger,event.trigger);
});
test('replays cannot replace the original event or simulated status', async t => {
  const {req, dir} = await fixture(t);
  const event = {id:randomUUID(),timestamp:new Date().toISOString(),trigger:'noResponse',simulated:true};
  assert.equal((await req('/v1/events',event)).status,202);
  assert.equal((await req('/v1/events',{...event,simulated:false,trigger:'repeatedYawns'})).status,200);
  const saved = JSON.parse(await readFile(path.join(dir,`${event.id}.json`),'utf8'));
  assert.equal(saved.trigger,'noResponse'); assert.equal(saved.simulated,true);
});
test('saved receipts survive a new backend instance', async t => {
  const {req, dir} = await fixture(t);
  const event = {id:randomUUID(),timestamp:new Date().toISOString(),trigger:'noResponse',simulated:false};
  await req('/v1/events',event);
  const second = await createApp({token,dataDir:dir});
  second.listen(0,'127.0.0.1'); await once(second,'listening');
  t.after(async () => { second.closeAllConnections(); await new Promise(r => second.close(r)); });
  const response = await fetch(`http://127.0.0.1:${second.address().port}/v1/events/${event.id.toUpperCase()}`, {
    headers: {Authorization:`Bearer ${token}`}
  });
  assert.equal(response.status,200);
  const receipt = await response.json();
  assert.equal(receipt.delivery,'stored'); assert.equal(receipt.simulated,false);
});
test('live fleet delivery records acceptance and an idempotency key', async t => {
  let forwarded;
  const {req, dir} = await fixture(t, {fleetURL:'https://example.com/webhook',fleetToken:'fake-fleet-token',
    fetcher:async (url, init) => { forwarded={url,init}; return new Response('{}',{status:202}); }});
  const event = {id:randomUUID(),timestamp:new Date().toISOString(),trigger:'noResponse',simulated:false};
  assert.equal((await req('/v1/events',event)).status,202);
  const saved = await eventually(async () => {
    const record = JSON.parse(await readFile(path.join(dir,`${event.id}.json`),'utf8'));
    return record.delivery === 'delivered' ? record : null;
  });
  assert.equal(forwarded.url,'https://example.com/webhook');
  assert.equal(forwarded.init.headers['Idempotency-Key'],event.id);
  assert.equal(forwarded.init.headers.Authorization,'Bearer fake-fleet-token');
  assert.ok(saved.deliveredAt);
});
test('a rejected fleet webhook persists a retry instead of reporting delivery', async t => {
  const {req, dir} = await fixture(t, {fleetURL:'https://example.com/webhook',
    fetcher:async () => new Response('{}',{status:503})});
  const event = {id:randomUUID(),timestamp:new Date().toISOString(),trigger:'noResponse',simulated:false};
  await req('/v1/events',event);
  const saved = await eventually(async () => {
    const record = JSON.parse(await readFile(path.join(dir,`${event.id}.json`),'utf8'));
    return record.delivery === 'failed' ? record : null;
  });
  assert.equal(saved.attempts,1); assert.ok(saved.nextAttempt > Date.now());
  assert.equal((await (await req(`/v1/events/${event.id}`)).json()).delivery,'failed');
});
test('provider validation rejects unsupported languages and oversized transcripts before calling upstream', async t => {
  let calls = 0;
  const {req} = await fixture(t,{openAIKey:'fake',smallestKey:'fake',fetcher:async () => { calls++; throw new Error('Must not call upstream'); }});
  assert.equal((await req('/v1/conversation',{transcript:'hello',language:'de'})).status,400);
  assert.equal((await req('/v1/conversation',{transcript:'x'.repeat(501),language:'hi'})).status,400);
  assert.equal((await req('/v1/voice',{text:'x'.repeat(601),language:'pa'})).status,400);
  assert.equal(calls,0);
});
test('malformed JSON and oversized request bodies return validation errors', async t => {
  const {base} = await fixture(t);
  for (const body of ['{bad json','x'.repeat(9000)]) {
    const response = await fetch(base+'/v1/events',{method:'POST',
      headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body});
    assert.equal(response.status,400);
  }
});
test('non-object JSON is rejected as invalid input', async t => {
  const {base} = await fixture(t);
  const response = await fetch(base+'/v1/events',{method:'POST',
    headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:'null'});
  assert.equal(response.status,400);
});
test('events require a timestamp string', async t => {
  const {req, dir} = await fixture(t);
  const event = {id:randomUUID(),timestamp:2026,trigger:'noResponse',simulated:false};
  assert.equal((await req('/v1/events',event)).status,400);
  assert.equal((await readdir(dir)).length,0);
});
test('unknown event receipts return 404 and provider errors do not expose details', async t => {
  const {req} = await fixture(t,{openAIKey:'dummy-provider-secret',fetcher:async () => { throw new Error('sensitive upstream detail'); }});
  assert.equal((await req(`/v1/events/${randomUUID()}`)).status,404);
  const response = await req('/v1/conversation',{transcript:'हाँ',language:'hi'});
  assert.equal(response.status,503);
  const text = await response.text();
  assert.ok(!text.includes('dummy-provider-secret')); assert.ok(!text.includes('sensitive upstream detail'));
});
test('unsafe backend configurations fail before accepting traffic', async t => {
  const dir = await mkdtemp(path.join(os.tmpdir(),'raho-config-test-'));
  t.after(() => rm(dir,{recursive:true,force:true}));
  await assert.rejects(createApp({token:'short',dataDir:dir}),/at least 24/);
  await assert.rejects(createApp({token,dataDir:dir,fleetURL:'http://example.com'}),/HTTPS/);
});
test('speech provider rejects JSON and invalid audio payloads', async () => {
  await assert.rejects(voice({key:'fake',text:'hello',language:'en',fetcher:async () => new Response('{}'.repeat(40))}),ProviderError);
});
test('incomplete or empty conversation outputs cannot be spoken as valid responses', async () => {
  for (const body of [{status:'incomplete',output:[]},{status:'completed',output:[]}]) {
    await assert.rejects(conversation({key:'fake',transcript:'yes',language:'en',
      fetcher:async () => new Response(JSON.stringify(body))}),ProviderError);
  }
});
