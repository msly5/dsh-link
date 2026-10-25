import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { once } from 'node:events';
import { generateKeyPair, exportJWK, SignJWT, createLocalJWKSet } from 'jose';
import WebSocket, { WebSocketServer } from 'ws';
import { accessVerifier } from '../src/access.mjs';
import { createBridge } from '../src/server.mjs';
import { mintCookie, readSecret } from '../src/dsh.mjs';

const config = { team: 'https://test.cloudflareaccess.com', aud: 'test-audience' };
const { publicKey, privateKey } = await generateKeyPair('RS256');
const jwk = await exportJWK(publicKey); jwk.kid = 'test';
const verify = accessVerifier(config, createLocalJWKSet({ keys: [jwk] }));
const sign = (issuer = config.team, audience = config.aud, expiration = '1h', key = privateKey) => new SignJWT({ type: 'app' })
  .setProtectedHeader({ alg: 'RS256', kid: 'test' }).setIssuedAt().setIssuer(issuer).setAudience(audience).setExpirationTime(expiration).sign(key);
const listen = async server => { server.listen(0, '127.0.0.1'); await once(server, 'listening'); return server.address().port; };

test('Access validates signatures, issuer, audience and expiry; forged internal header fails', async () => {
  const { privateKey: other } = await generateKeyPair('RS256');
  for (const token of [undefined, 'internal', await sign('https://other.cloudflareaccess.com'), await sign(config.team, 'other'),
    await sign(config.team, config.aud, Math.floor(Date.now()/1000) - 60), await sign(config.team, config.aud, '1h', other)]) {
    await assert.rejects(() => verify({ headers: { 'cf-access-jwt-assertion': token } }));
  }
  assert.equal((await verify({ headers: { 'cf-access-jwt-assertion': await sign() } })).iss, config.team);
});

test('authenticated HTTP and WS forward DSH cookie, strip Access secrets and reject all unauthenticated routes', async t => {
  let received;
  const upstream = http.createServer((req,res) => {
    received = req.headers;
    res.setHeader('set-cookie', 'private=hidden');
    res.end(JSON.stringify({ result: { ok:true, value:{items:[]} } }));
  });
  const wss = new WebSocketServer({ server: upstream });
  wss.on('connection', (ws, req) => { received = req.headers; ws.on('message', data => ws.send(data)); });
  const upstreamPort = await listen(upstream);
  const bridge = createBridge({ verify, target: () => ({ port: upstreamPort, cookie: 'dsh-auth-test=private' }) });
  const port = await listen(bridge), base = `http://127.0.0.1:${port}`;
  t.after(() => { bridge.shutdown(); for(const ws of wss.clients) ws.terminate(); wss.close(); upstream.closeAllConnections(); upstream.close(); });
  for (const route of ['/health', '/push/status', '/api/session/list']) {
    assert.equal((await fetch(base + route)).status, 403);
    assert.equal((await fetch(base + route, { headers: {'cf-access-jwt-assertion':'internal'} })).status,403);
  }
  const auth = { 'cf-access-jwt-assertion':await sign(), 'cf-access-client-id':'test-id', 'cf-access-client-secret':'test-secret', cookie:'external=bad' };
  const reply = await fetch(base+'/api/session/list', {method:'POST',headers:auth,body:'{}'});
  assert.equal(reply.status,200); assert.equal(reply.headers.get('set-cookie'),null);
  assert.deepEqual((await reply.json()).result.value.items,[]);
  assert.equal(received.cookie,'dsh-auth-test=private');
  assert.equal((await fetch(base+'/api/$events/result',{method:'POST',headers:auth,body:'{}'})).status,200);
  assert.equal((await fetch(base+'/api/$events/result',{method:'POST',body:'{}'})).status,403);
  assert.equal((await fetch(base+'/api/$events/other',{method:'POST',headers:auth,body:'{}'})).status,404);
  for(const header of ['cf-access-jwt-assertion','cf-access-client-id','cf-access-client-secret']) assert.equal(received[header],undefined);
  assert.equal((await fetch(base+'/',{headers:auth})).status,404);
  assert.equal((await fetch(base+'/push/register',{method:'POST',headers:auth,body:'{}'})).status,503);
  const ws = new WebSocket(`ws://127.0.0.1:${port}/api/remote.mux`,{headers:auth});
  await once(ws,'open'); ws.send('test-frame');
  assert.equal((await once(ws,'message'))[0].toString(),'test-frame');
  assert.equal(received['cf-access-client-secret'],undefined); ws.terminate();
  const denied = new WebSocket(`ws://127.0.0.1:${port}/api/remote.mux`, {headers:{'cf-access-jwt-assertion':'internal'}});
  denied.on('error',()=>{});
  const [, response] = await once(denied,'unexpected-response'); assert.equal(response.statusCode,403); denied.terminate();
});

test('DSH credentials parser and scoped HMAC cookie', () => {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'dsh-remote-fixture-'));
  const file=path.join(dir,'fixture.yaml');
  try {
    const secret=Buffer.alloc(32,7).toString('base64url');
    fs.writeFileSync(file,`version: 1\nrecords:\n  client-connection/browser-session:\n    payload:\n      secret: ${secret}\n`);
    assert.equal(readSecret(file),secret);
    const cookie=mintCookie('127.0.0.1:1234',secret,1000);
    const [body]=cookie.split('=v1.')[1].split('.');
    const payload=JSON.parse(Buffer.from(body,'base64url'));
    assert.equal(payload.authority,'127.0.0.1:1234');
    assert.equal(payload.expiresAt,3601000);
    assert.notEqual(cookie,mintCookie('127.0.0.1:5678',secret,1000));
    fs.writeFileSync(file,'records: {}'); assert.throws(()=>readSecret(file));
  } finally { fs.rmSync(dir,{recursive:true,force:true}); }
});


test('DSH mux ready frames may be wrapped or direct', async () => {
  const { streamValue } = await import('../src/protocol.mjs');
  for (const frame of [{type:'ready',clientId:'fixture'}, {type:'next',streamId:'events',value:{type:'ready',clientId:'fixture'}}]) {
    assert.equal(streamValue(Buffer.from(JSON.stringify(frame))).clientId, 'fixture');
  }
});
