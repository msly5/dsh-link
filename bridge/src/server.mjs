import http from 'node:http';

export function outboundHeaders(req, target) {
  const headers = {};
  // An allowlist keeps service tokens, JWTs, forwarded IPs and client cookies out of DSH.
  for (const name of ['content-type', 'content-length', 'accept', 'sec-websocket-key', 'sec-websocket-version', 'sec-websocket-protocol', 'sec-websocket-extensions']) {
    if (req.headers[name] !== undefined) headers[name] = req.headers[name];
  }
  headers.host = `127.0.0.1:${target.port}`;
  headers.cookie = target.cookie;
  return headers;
}

const json = (res, code, value) => {
  res.writeHead(code, { 'content-type': 'application/json', 'cache-control': 'no-store' });
  res.end(JSON.stringify(value));
};

export function createBridge({ verify, target, push }) {
  const sockets = new Set();
  const server = http.createServer(async (req, res) => {
    // No unauthenticated health or push endpoint, and no header-presence bypass.
    try { await verify(req); } catch { json(res, 403, { error: 'Access denied' }); return; }
    if (req.method === 'GET' && req.url === '/health') {
      try { target(); json(res, 200, { ok: true, dsh: true }); }
      catch { json(res, 503, { ok: false, dsh: false }); }
      return;
    }
    if (req.url === '/push/register' && req.method === 'POST') {
      if (!push) { json(res, 503, { error: 'Push is disabled' }); return; }
      try {
        let body = '';
        for await (const chunk of req) {
          body += chunk;
          if (body.length > 4096) { json(res, 413, { error: 'Request too large' }); req.resume(); return; }
        }
        const { token } = JSON.parse(body);
        if (typeof token !== 'string' || !/^[a-fA-F0-9]{64,200}$/.test(token) || token.length % 2) throw new Error();
        push.register(token.toLowerCase());
        json(res, 200, { ok: true });
      } catch { if (!res.headersSent) json(res, 400, { error: 'Invalid device registration' }); }
      return;
    }
    if (req.url === '/push/status' && req.method === 'GET') { json(res, 200, { enabled: Boolean(push) }); return; }
    if (req.method !== 'POST' || !(/^\/api\/[a-zA-Z0-9_/-]+$/.test(req.url || '') || req.url === '/api/$events/result')) {
      json(res, 404, { error: 'Not found' }); return;
    }
    const length = Number(req.headers['content-length']);
    if (Number.isFinite(length) && length > 32 * 1024 * 1024) { json(res, 413, { error: 'Request too large' }); return; }
    let destination;
    try { destination = target(); } catch { json(res, 503, { error: 'DSH desktop is unavailable' }); return; }
    const upstream = http.request({ hostname: '127.0.0.1', port: destination.port, path: req.url, method: req.method,
      headers: outboundHeaders(req, destination) }, up => {
      const headers = { ...up.headers, 'cache-control': 'no-store' };
      delete headers['set-cookie'];
      delete headers.location;
      res.writeHead(up.statusCode || 502, headers);
      up.pipe(res);
    });
    // Do not retry mutating RPCs: a disconnected request may already have been accepted.
    upstream.on('error', () => {
      target.invalidate?.();
      if (!res.headersSent) json(res, 502, { error: 'DSH upstream connection failed' });
      else res.destroy();
    });
    upstream.setTimeout(180_000, () => upstream.destroy());
    req.on('aborted', () => upstream.destroy());
    res.on('close', () => { if (!res.writableEnded) upstream.destroy(); });
    req.pipe(upstream);
  });
  server.on('upgrade', async (req, socket, head) => {
    socket.on('error', () => {});
    socket.pause();
    try { await verify(req); } catch { socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n'); return; }
    if (req.method !== 'GET' || req.url !== '/api/remote.mux' || req.headers.upgrade?.toLowerCase() !== 'websocket') {
      socket.end('HTTP/1.1 404 Not Found\r\n\r\n'); return;
    }
    let destination;
    try { destination = target(); } catch { socket.end('HTTP/1.1 503 Service Unavailable\r\n\r\n'); return; }
    const headers = outboundHeaders(req, destination);
    headers.connection = 'Upgrade'; headers.upgrade = 'websocket';
    const upstream = http.request({ hostname: '127.0.0.1', port: destination.port, method: 'GET', path: req.url, headers });
    upstream.setTimeout(15_000, () => upstream.destroy());
    upstream.on('upgrade', (up, upSocket, upHead) => {
      upstream.setTimeout(0);
      const lines = [`HTTP/1.1 ${up.statusCode} ${up.statusMessage}`];
      for (let i = 0; i < up.rawHeaders.length; i += 2) {
        if (up.rawHeaders[i].toLowerCase() !== 'set-cookie') lines.push(`${up.rawHeaders[i]}: ${up.rawHeaders[i + 1]}`);
      }
      socket.write(lines.join('\r\n') + '\r\n\r\n');
      if (upHead.length) socket.write(upHead);
      if (head.length) upSocket.write(head);
      socket.pipe(upSocket).pipe(socket);
      socket.resume();
      upSocket.on('error', () => socket.destroy());
      socket.on('close', () => upSocket.destroy());
      upSocket.on('close', () => socket.destroy());
    });
    upstream.on('response', () => { socket.end('HTTP/1.1 502 Bad Gateway\r\n\r\n'); upstream.destroy(); });
    upstream.on('error', () => { target.invalidate?.(); socket.end('HTTP/1.1 502 Bad Gateway\r\n\r\n'); });
    socket.on('close', () => upstream.destroy());
    upstream.end();
  });
  server.on('connection', socket => { sockets.add(socket); socket.on('close', () => sockets.delete(socket)); });
  server.shutdown = () => { for (const socket of sockets) socket.destroy(); server.close(); };
  server.requestTimeout = 180_000;
  server.headersTimeout = 15_000;
  return server;
}
