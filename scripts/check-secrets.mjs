import {readFile, readdir} from 'node:fs/promises';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const base = path.dirname(fileURLToPath(import.meta.url));
const workspace = path.resolve(base, '..');
const ignored = new Set(['.git','Pods','.build','build','node_modules','DerivedData','data']);
let failures = [];
async function visit(dir) {
  for (const entry of await readdir(dir,{withFileTypes:true})) {
    if (ignored.has(entry.name) || entry.name.startsWith('.env') && entry.name !== '.env.example') continue;
    const file = path.join(dir,entry.name);
    if (entry.isDirectory()) await visit(file);
    else if (/\.(swift|mjs|json|md|txt|py|yml|yaml|sh|plist|xcconfig|pbxproj|example)$/.test(entry.name)) {
      const text = await readFile(file,'utf8');
      if (/sk-(?:proj-)?[A-Za-z0-9_-]{28,}/.test(text)) failures.push(path.relative(workspace,file));
    }
  }
}
await visit(workspace);
try { execFileSync('git',['check-ignore','--quiet','.env'],{cwd:workspace}); }
catch { failures.push('.env is not ignored'); }
try {
 const tracked = execFileSync('git',['ls-files'],{cwd:workspace,encoding:'utf8'}).split('\n');
 if (tracked.some(x=>/(^|\/)\.env(?:$|\.)/.test(x) && !x.endsWith('.env.example'))) failures.push('A credential file is tracked');
} catch { failures.push('Git tracking check failed'); }
if (failures.length) { console.error('Secret checks failed for: '+failures.join(', ')); process.exitCode=1; }
else console.log('Secret checks passed: credential files ignored, no provider keys in source or tracked files.');
