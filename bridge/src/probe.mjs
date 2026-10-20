import fs from 'node:fs';
import path from 'node:path';
import WebSocket from 'ws';
import { configDir } from './config.mjs';
import { streamValue } from './protocol.mjs';

try {
  let config;
  try { config = JSON.parse(fs.readFileSync(path.join(configDir(), 'client.json'), 'utf8')); }
  catch { throw new Error('Cannot read private client.json; run scripts/store-secret.py client.'); }
  const url = new URL(config.server_url);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || !config.client_id || !config.client_secret) throw new Error();
  const base = url.href.replace(/\/$/, '');
  const headers = { 'CF-Access-Client-Id':config.client_id, 'CF-Access-Client-Secret':config.client_secret };
  const denied = await fetch(base+'/health', {redirect:'manual', signal:AbortSignal.timeout(15_000)});
  if (![401,403].includes(denied.status)) throw new Error('Unauthenticated requests are not blocked with 401/403; review Access Service Auth.');
  const response = await fetch(base+'/api/session/list', { method:'POST', headers:{...headers,'content-type':'application/json'}, redirect:'manual',
    body:JSON.stringify({type:'client-request',rpcId:'probe',method:'session/list',payload:{args:{_request:{}}}}), signal:AbortSignal.timeout(20_000) });
  if (!response.ok) throw new Error(`Authenticated HTTP probe failed (${response.status}).`);
  const result = await response.json();
  if (result.result?.ok !== true || !Array.isArray(result.result?.value?.items)) throw new Error('Unexpected DSH RPC response.');
  console.log('PASS: unauthenticated HTTP blocked; authenticated DSH RPC succeeded.');
  await new Promise((resolve,reject) => {
    const socket = new WebSocket(base.replace(/^https:/,'wss:')+'/api/remote.mux', { headers, followRedirects:false, handshakeTimeout:15_000, maxPayload:32*1024*1024 });
    const timer = setTimeout(() => { socket.terminate(); reject(new Error('WebSocket probe timed out.')); },20_000);
    const finish = (error) => { clearTimeout(timer); socket.terminate(); error ? reject(error) : resolve(); };
    socket.on('open',()=>socket.send(JSON.stringify({type:'open',streamId:'probe',endpoint:'$events',payload:{args:{}}})));
    socket.on('message',data=>{ try { const frame=streamValue(data); if(frame.type==='ready' && frame.clientId) finish(); } catch {} });
    socket.on('error',()=>finish(new Error('WebSocket probe failed; check Access policy and tunnel routing.')));
  });
  console.log('PASS: authenticated WebSocket received DSH ready frame. No session content or credentials printed.');
} catch (error) { console.error('FAIL:', error.message || 'Check private client.json.'); process.exitCode=1; }
