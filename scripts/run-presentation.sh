#!/bin/bash
set -euo pipefail
JR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$JR_ROOT"
mkdir -p build
if [ ! -f .env ] || ! command -v node >/dev/null 2>&1; then
  printf '%s\n' 'Presentation mode needs Node.js and the local .env with APP_TOKEN and provider credentials.' >&2
  exit 1
fi

# Reuse a healthy backend or start a detached copy that survives this terminal.
# Credentials are read locally and never printed or written into the app bundle.
node --env-file=.env --input-type=module <<'JS'
import {spawn} from 'node:child_process';
import {openSync, closeSync, writeFileSync} from 'node:fs';
const port = Number(process.env.PORT || 8787);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid backend PORT');
if ((process.env.APP_TOKEN ?? '').length < 24) throw new Error('APP_TOKEN must contain at least 24 characters');
const base = `http://127.0.0.1:${port}`;
async function status() {
  let response;
  try {
    response = await fetch(`${base}/v1/status`, {
      headers: {Authorization: `Bearer ${process.env.APP_TOKEN}`}, signal: AbortSignal.timeout(1500)
    });
  } catch { return null; }
  if (!response.ok) throw new Error('The running backend rejected pairing. Check APP_TOKEN and the process using the configured port.');
  return response.json();
}
let current = await status();
if (!current) {
  const log = openSync('build/backend.log', 'a', 0o600);
  const child = spawn(process.execPath, ['--env-file=.env', 'server/index.mjs'], {
    cwd: process.cwd(), detached: true, stdio: ['ignore', log, log],
    env: {...process.env, HOST: '127.0.0.1'}
  });
  child.on('error', () => { console.error('Backend could not start; inspect build/backend.log.'); process.exit(1); });
  writeFileSync('build/backend.pid', `${child.pid}\n`, {mode: 0o600});
  child.unref(); closeSync(log);
  for (let attempt = 0; attempt < 20 && !current; attempt++) {
    await new Promise(resolve => setTimeout(resolve, 250));
    current = await status();
  }
}
if (!current) throw new Error('Backend did not become ready; inspect build/backend.log.');
console.log(`Backend ready at ${base}; conversation: ${current.conversationConfigured}, speech: ${current.speechConfigured}`);
JS

./scripts/bootstrap.sh
SAARTHI_GRANT_PERMISSIONS=1 ./scripts/run-simulator.sh
