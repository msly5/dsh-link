import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { randomBytes } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import WebSocket, { WebSocketServer } from 'ws';
import { connectionKeyVerifier, connectionHeaders } from '../src/connection-key.mjs';
import { createBridge } from '../src/server.mjs';
import { probeConnection } from '../src/probe.mjs';

const listen = async server => { server.listen(0,'127.0.0.1'); await once(server,'listening'); return server.address().port; };

test('connection diagnostics never echo invalid credentials or URL input', async () => {
  await assert.rejects(() => probeConnection({server_url:'https://private-user:private-value@example.com',auth_mode:'quick_tunnel',connection_key:'invalid'}),
    {message:'Connection check failed during connection configuration.'});
});

test('Quick Tunnel needs no Access configuration and does not change the default Access requirement', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(),'dsh-quick-config-'));
  const configModule = new URL('../src/config.mjs',import.meta.url).href;
  const run = (options, extra = {}) => spawnSync(process.execPath, ['--input-type=module','-e',
    `import {loadConfig} from ${JSON.stringify(configModule)}; const c=loadConfig(${JSON.stringify(options)}); console.log(JSON.stringify({host:c.host,port:c.port,mode:c.authMode}));`],
    {encoding:'utf8',env:{PATH:process.env.PATH,HOME:directory,DSH_REMOTE_CONFIG_DIR:directory,...extra}});
  try {
    const quick=run({authMode:'quick_tunnel'});
    assert.equal(quick.status,0);
    assert.deepEqual(JSON.parse(quick.stdout),{host:'127.0.0.1',port:3080,mode:'quick_tunnel'});
    assert.equal(run({}).status,1);
    assert.equal(run({authMode:'none'}).status,1);
    assert.equal(run({authMode:'quick_tunnel'},{DSH_QUICK_PORT:'invalid'}).status,1);
    const access=run({},{CF_ACCESS_TEAM_DOMAIN:'https://test.cloudflareaccess.com',CF_ACCESS_AUD:'a'.repeat(64)});
    assert.equal(access.status,0);
    assert.equal(JSON.parse(access.stdout).port,3079);
  } finally {fs.rmSync(directory,{recursive:true,force:true});}
});

test('Quick Tunnel requires the exact generated key; Access headers cannot authorize it', async () => {
  const key = randomBytes(32).toString('hex'), verify = connectionKeyVerifier(key);
  await verify({headers:{authorization:`Bearer ${key}`}});
  for (const authorization of [undefined, '', 'Bearer short', `Bearer ${'0'.repeat(64)}`, `Basic ${key}`, `Bearer ${key}, Bearer ${key}`]) {
    await assert.rejects(() => verify({headers:{authorization,'cf-access-jwt-assertion':'internal'}}));
  }
  assert.throws(() => connectionKeyVerifier('short'));
  assert.deepEqual(connectionHeaders({auth_mode:'quick_tunnel',connection_key:key}), {authorization:`Bearer ${key}`});
});

test('HTTP and WebSocket both enforce Quick Tunnel authentication and strip the key before DSH', async t => {
  let received;
  const upstream = http.createServer((req,res) => { received=req.headers; res.end('{"result":{"ok":true,"value":{"items":[]}}}'); });
  const wss = new WebSocketServer({server:upstream});
  wss.on('connection',(ws,req) => { received=req.headers; ws.on('message',data => ws.send(data)); });
  const upstreamPort = await listen(upstream), key = randomBytes(32).toString('hex');
  const bridge = createBridge({verify:connectionKeyVerifier(key),target:()=>({port:upstreamPort,cookie:'fixture-cookie'})});
  const port = await listen(bridge), base = `http://127.0.0.1:${port}`;
  t.after(() => { bridge.shutdown(); for (const ws of wss.clients) ws.terminate(); wss.close(); upstream.closeAllConnections(); upstream.close(); });
  for (const headers of [{}, {authorization:`Bearer ${'0'.repeat(64)}`}, {'cf-access-jwt-assertion':'internal'}]) {
    for (const route of ['/health','/push/status','/api/session/list']) assert.equal((await fetch(base+route,{headers})).status,403);
    const denied = new WebSocket(`ws://127.0.0.1:${port}/api/remote.mux`,{headers});
    denied.on('error',()=>{});
    const [,response] = await once(denied,'unexpected-response');
    assert.equal(response.statusCode,403); denied.terminate();
  }
  const headers = {authorization:`Bearer ${key}`};
  assert.equal((await fetch(base+'/health',{headers})).status,200);
  assert.equal((await fetch(base+'/api/session/list',{method:'POST',headers,body:'{}'})).status,200);
  assert.equal(received.authorization,undefined); assert.equal(received.cookie,'fixture-cookie');
  const ws = new WebSocket(`ws://127.0.0.1:${port}/api/remote.mux`,{headers});
  await once(ws,'open'); ws.send('fixture');
  assert.equal((await once(ws,'message'))[0].toString(),'fixture');
  assert.equal(received.authorization,undefined); ws.terminate();
  const rotated = createBridge({verify:connectionKeyVerifier(randomBytes(32).toString('hex')),target:()=>({port:upstreamPort,cookie:'fixture-cookie'})});
  const rotatedPort = await listen(rotated);
  t.after(()=>rotated.shutdown());
  assert.equal((await fetch(`http://127.0.0.1:${rotatedPort}/health`,{headers})).status,403);
});
