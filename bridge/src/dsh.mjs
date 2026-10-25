import fs from 'node:fs';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { parse } from 'yaml';

export function readSecret(file) {
  let document;
  try { document = parse(fs.readFileSync(file, 'utf8')); }
  catch { throw new Error('Cannot read or parse DSH credential file; leave it managed by DSH.'); }
  // DSH's browser-session entry is a top-level credential record, not an API key from this project.
  const record = document?.records?.['client-connection/browser-session'];
  const secret = record?.payload?.secret;
  if (typeof secret !== 'string' || !/^[A-Za-z0-9_-]{32,}={0,2}$/.test(secret)) {
    throw new Error('DSH browser-session credential not found; start and sign in to the desktop app.');
  }
  return secret;
}

export function mintCookie(authority, secretB64, now = Date.now()) {
  const payload = { version: 1, authority, issuedAt: now, expiresAt: now + 3600_000 };
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const sig = crypto.createHmac('sha256', Buffer.from(secretB64, 'base64url')).update(body).digest('base64url');
  const name = `dsh-auth-${crypto.createHash('sha256').update(authority).digest('base64url')}`;
  return `${name}=v1.${body}.${sig}`;
}

export function findDshPorts(platform = process.platform, run = execFileSync) {
  if (platform === 'win32') {
    // Keep process command lines inside PowerShell: emit only loopback ports.
    const script = `$ErrorActionPreference='Stop'; $ids=@(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'dsh-desktop-host[\\\\/]lib[\\\\/]index\\.js' } | ForEach-Object { $_.ProcessId }); if ($ids.Count) { Get-NetTCPConnection -State Listen | Where-Object { $_.LocalAddress -eq '127.0.0.1' -and $ids -contains $_.OwningProcess } | Select-Object -ExpandProperty LocalPort }`;
    const output = run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], {encoding:'utf8', timeout:15000, windowsHide:true});
    return [...new Set(output.trim().split(/\s+/).filter(p => /^\d+$/.test(p)).map(Number))].filter(p => p > 0 && p <= 65535);
  }
  if (platform !== 'darwin') throw new Error('Automatic discovery supports macOS and Windows. Set DSH_UPSTREAM_PORT for another host.');
  const processes = run('/bin/ps', ['-axo', 'pid=,command='], { encoding: 'utf8', timeout: 3000 });
  const pids = processes.split('\n').filter(line => line.includes('dsh-desktop-host/lib/index.js'))
    .map(line => line.trim().split(/\s+/)[0]).filter(pid => /^\d+$/.test(pid));
  const ports = new Set();
  for (const pid of pids) {
    try {
      const listeners = run('/usr/sbin/lsof', ['-nP', '-a', '-p', pid, '-iTCP', '-sTCP:LISTEN', '-Fn'], { encoding: 'utf8', timeout: 3000 });
      for (const line of listeners.split('\n')) {
        const match = /^n127\.0\.0\.1:(\d+)$/.exec(line);
        if (match) ports.add(Number(match[1]));
      }
    } catch { /* A process may exit during discovery. */ }
  }
  return [...ports];
}

export function targetResolver(config) {
  let cached;
  function target() {
    if (cached && Date.now() - cached.at < 30_000) return cached;
    const ports = config.upstreamPort ? [config.upstreamPort] : findDshPorts();
    if (ports.length !== 1) throw new Error('Expected one DSH desktop host; open the app or set DSH_UPSTREAM_PORT.');
    const port = ports[0];
    cached = { port, cookie: mintCookie(`127.0.0.1:${port}`, readSecret(config.credentialsFile)), at: Date.now() };
    return cached;
  }
  target.invalidate = () => { cached = undefined; };
  return target;
}
