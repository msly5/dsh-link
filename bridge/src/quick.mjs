import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { devNull } from 'node:os';
import { setTimeout as delay } from 'node:timers/promises';
import { loadConfig } from './config.mjs';
import { targetResolver } from './dsh.mjs';
import { createBridge } from './server.mjs';
import { connectionKeyVerifier } from './connection-key.mjs';
import { pairingInvitation } from './pairing.mjs';
import { openPairingWindow } from './pair-window.mjs';
import { probeConnection } from './probe.mjs';

let server, tunnel, qrWindow, startTimer;
let stopping = false, openingWindow = false, verifying = false, client;
const controller = new AbortController();

function stop(code = 0) {
  if (stopping) return;
  stopping = true;
  process.exitCode = code;
  controller.abort();
  clearTimeout(startTimer);
  qrWindow?.kill('SIGTERM');
  tunnel?.kill('SIGTERM');
  server?.shutdown();
  process.stdin.pause();
}

async function showPairing() {
  if (!client || openingWindow || stopping) return;
  openingWindow = true;
  try {
    qrWindow?.kill('SIGTERM');
    const child = await openPairingWindow(pairingInvitation(client));
    if (stopping) { child.kill('SIGTERM'); return; }
    qrWindow = child;
    child.on('error', () => console.error('Could not open the QR window. Enter p to retry.'));
    child.on('exit', code => { if (code && !stopping) console.error('QR window closed with an error. Enter p to retry.'); });
  } catch { console.error('Could not prepare the QR window. Check Swift on macOS or Windows PowerShell, then enter p.'); }
  finally { openingWindow = false; }
}

async function verifyPublicConnection() {
  if (verifying || !client || stopping) return;
  verifying = true;
  try {
    let lastFailure = 'Public connection check did not pass.';
    for (let attempt = 0; attempt < 8 && !stopping; attempt++) {
      try {
        await probeConnection(client, {signal:controller.signal, log:() => {}});
        console.log('PASS: missing/wrong keys rejected; authenticated HTTP and WebSocket reached DSH.');
        return;
      } catch (error) {
        lastFailure = error.message;
        if (stopping) return;
        try { await delay(3_000, undefined, {signal:controller.signal}); } catch { return; }
      }
    }
    if (!stopping) console.error(`${lastFailure} Check DSH, DNS and network access, then enter r to retry.`);
  } finally { verifying = false; }
}

try {
  if (!['darwin','win32'].includes(process.platform)) throw new Error('Quick Tunnel setup supports macOS and Windows.');
  if (process.argv.length > 2) throw new Error('Run npm run quick --prefix bridge without credential arguments.');
  const config = loadConfig({authMode:'quick_tunnel'});
  const target = targetResolver(config);
  target(); // Fail before opening a tunnel if the desktop cannot be discovered.
  const key = randomBytes(32).toString('hex');
  server = createBridge({verify:connectionKeyVerifier(key), target});
  await new Promise((resolve, reject) => {
    server.once('error', () => reject(new Error('Quick bridge port is unavailable. Choose DSH_QUICK_PORT; no existing service was stopped.')));
    server.listen(config.port, config.host, resolve);
  });
  console.log(`Quick bridge listening on 127.0.0.1:${config.port}; connection key required.`);
  // Ignore existing named-tunnel configuration without editing it.
  tunnel = spawn(process.env.CLOUDFLARED_BIN || 'cloudflared', ['tunnel', '--config', devNull, '--no-autoupdate', '--url', `http://127.0.0.1:${config.port}`], {stdio:['ignore','pipe','pipe'], windowsHide:true});
  tunnel.on('error', () => { console.error('Cannot start cloudflared. Install it or set CLOUDFLARED_BIN.'); stop(1); });
  tunnel.on('exit', () => { if (!stopping) { console.error('cloudflared exited. Restart Quick Tunnel to get a new address and key.'); stop(1); } });
  let output = '';
  const read = chunk => {
    if (client || stopping) return;
    output = (output + chunk.toString()).slice(-16_384);
    const match = output.match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com\b/);
    if (!match) return;
    clearTimeout(startTimer);
    client = {server_url:match[0], auth_mode:'quick_tunnel', connection_key:key};
    output = '';
    console.log(`Temporary server: ${client.server_url}`);
    console.log('Scan the computer QR code in dsh link (iOS or Android). Enter p then Return to reopen it, r to recheck the connection; Ctrl+C stops the bridge and tunnel.');
    void showPairing();
    void verifyPublicConnection();
  };
  tunnel.stdout.on('data', read);
  tunnel.stderr.on('data', read);
  startTimer = setTimeout(() => { console.error('No Quick Tunnel URL received. Check network access and cloudflared configuration.'); stop(1); }, 90_000);
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', value => {
    if (value.trim().toLowerCase() === 'p') void showPairing();
    if (value.trim().toLowerCase() === 'r') void verifyPublicConnection();
  });
  for (const signal of ['SIGINT','SIGTERM','SIGHUP']) process.on(signal, () => stop());
} catch (error) { console.error(error.message); stop(1); }
