import http from 'node:http';
import { loadConfig } from './config.mjs';
import { targetResolver } from './dsh.mjs';

try {
  const config = loadConfig();
  console.log('PASS: Cloudflare Access team domain and AUD configured.');
  const target = targetResolver(config)();
  await new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port: target.port, path: '/api/session/list', method: 'POST',
      headers: { 'content-type': 'application/json', cookie: target.cookie }, timeout: 10_000 }, res => {
      let body = ''; res.on('data', chunk => { body += chunk; if (body.length > 8 * 1024 * 1024) req.destroy(); });
      res.on('end', () => {
        try { if (res.statusCode !== 200 || JSON.parse(body).result?.ok !== true) throw new Error(); resolve(); }
        catch { reject(new Error('Desktop RPC authentication failed; DSH may have changed its protocol.')); }
      });
    });
    req.on('error', () => reject(new Error('Cannot reach the local DSH desktop host.')));
    req.on('timeout', () => req.destroy());
    req.end(JSON.stringify({ type: 'client-request', rpcId: 'doctor', method: 'session/list', payload: { args: { _request: {} } } }));
  });
  console.log('PASS: Local DSH session/list RPC authenticated (session contents not displayed).');
  console.log('Next: start the bridge and verify Cloudflare /health plus the iOS connection test.');
} catch (error) { console.error('FAIL:', error.message); process.exitCode = 1; }
