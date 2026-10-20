import fs from 'node:fs';
import path from 'node:path';
import http2 from 'node:http2';
import crypto from 'node:crypto';
import WebSocket from 'ws';

export function createPush(config, target) {
  if (!config.pushEnabled) return undefined;
  const { APNS_KEY_ID: keyId, APNS_TEAM_ID: teamId, APNS_TOPIC: topic, APNS_KEY_FILE: keyFile, APNS_ENV: environment } = process.env;
  if (!keyId || !teamId || !topic || !keyFile || !['development', 'production'].includes(environment)) {
    throw new Error('APNs enabled but configuration is incomplete; see docs/push.md.');
  }
  const key = fs.readFileSync(keyFile, 'utf8');
  crypto.createPrivateKey(key); // Fail early without logging key material.
  const deviceFile = path.join(config.configDir, 'device.json');
  let socket, timer, stopped = false, retry = 0, jwtCache;
  function jwt() {
    const now = Math.floor(Date.now() / 1000);
    if (jwtCache && now - jwtCache.at < 3000) return jwtCache.token;
    const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
    const input = `${b64({ alg: 'ES256', kid: keyId })}.${b64({ iss: teamId, iat: now })}`;
    const sig = crypto.sign('sha256', Buffer.from(input), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
    jwtCache = { at: now, token: `${input}.${sig}` }; return jwtCache.token;
  }
  function send(sessionId, kind) {
    let device;
    try { device = JSON.parse(fs.readFileSync(deviceFile, 'utf8')); } catch { return; }
    if (!/^[a-f0-9]{64,200}$/.test(device.token)) return;
    // Do not put command arguments, questions, source code or results onto the lock screen.
    const payload = JSON.stringify({ aps: { alert: { title: 'dsh remote', body: kind === 'approval' ? '有一项操作需要确认。' : '有一个问题等待回答。' }, sound: 'default' }, sessionId, kind });
    const client = http2.connect(environment === 'production' ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com');
    client.on('error', () => client.destroy());
    client.setTimeout(15_000, () => client.destroy());
    const req = client.request({ ':method': 'POST', ':path': `/3/device/${device.token}`, authorization: `bearer ${jwt()}`,
      'apns-topic': topic, 'apns-push-type': 'alert', 'apns-priority': '10', 'content-type': 'application/json' });
    req.on('response', headers => { if (headers[':status'] !== 200) console.error('APNs delivery failed, status', headers[':status']); });
    req.on('data', () => {});
    req.on('end', () => client.close());
    req.on('error', () => client.destroy());
    req.end(payload);
  }
  const seen = new Set();
  function connect() {
    if (stopped) return;
    try {
      const t = target();
      socket = new WebSocket(`ws://127.0.0.1:${t.port}/api/remote.mux`, { headers: { cookie: t.cookie }, handshakeTimeout: 10_000, maxPayload: 32 * 1024 * 1024 });
      socket.on('open', () => { retry = 0; socket.send(JSON.stringify({ type: 'open', streamId: 'push', endpoint: '$events', payload: { args: {} } })); });
      socket.on('message', data => {
        try {
          const frame = JSON.parse(data.toString()), event = frame?.value;
          if (event?.type !== 'waterfall' || !['approval/request', 'user-questions/request'].includes(event.event)) return;
          const id = event.request?.requestId ?? event.requestId;
          if (id && seen.has(id)) return;
          if (id) { seen.add(id); if (seen.size > 500) seen.delete(seen.values().next().value); }
          const sessionId = event.agentId?.replace(/^session-/, '');
          if (sessionId) send(sessionId, event.event === 'approval/request' ? 'approval' : 'question');
        } catch { /* Ignore unrelated or malformed events; no payload logging. */ }
      });
      socket.on('error', () => socket.terminate());
      socket.on('close', schedule);
    } catch { schedule(); }
  }
  function schedule() { if (!stopped) { target.invalidate?.(); timer = setTimeout(connect, Math.min(2 ** retry++, 30) * 1000); } }
  return {
    register(token) {
      fs.mkdirSync(config.configDir, { recursive: true, mode: 0o700 });
      fs.writeFileSync(deviceFile, JSON.stringify({ token, updatedAt: Date.now() }), { mode: 0o600 });
      fs.chmodSync(deviceFile, 0o600);
    },
    start: connect,
    stop() { stopped = true; clearTimeout(timer); socket?.terminate(); },
  };
}
