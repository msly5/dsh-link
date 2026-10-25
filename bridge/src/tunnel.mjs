import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {configDir} from './config.mjs';
import {assertPrivate} from './private-files.mjs';
try {
  const file = path.join(configDir(), 'tunnel.token');
  assertPrivate(path.dirname(file)); assertPrivate(file);
  if (!fs.statSync(file).size) throw new Error('Missing private tunnel.token.');
  const child = spawn(process.env.CLOUDFLARED_BIN || 'cloudflared', ['tunnel','--no-autoupdate','run','--token-file',file], {stdio:'inherit',windowsHide:true});
  child.on('error', () => { console.error('Cannot start cloudflared.'); process.exitCode=1; });
  child.on('exit', code => { process.exitCode = code ?? 1; });
  for (const signal of ['SIGINT','SIGTERM']) process.on(signal,()=>child.kill());
} catch { console.error('Cannot read private tunnel.token. See docs/windows.md or docs/cloudflare.md.'); process.exitCode=1; }
