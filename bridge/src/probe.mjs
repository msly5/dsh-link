import fs from 'node:fs';
import path from 'node:path';
import WebSocket from 'ws';
import { configDir } from './config.mjs';
import { streamValue } from './protocol.mjs';
import { connectionHeaders } from './connection-key.mjs';
import { pathToFileURL } from 'node:url';

export async function probeConnection(client, {signal, log = console.log} = {}) {
  let phase = 'connection configuration';
  try {
    const url = new URL(client.server_url);
    if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) throw new Error('Invalid HTTPS server URL.');
    const base = url.href.replace(/\/$/, '');
    const headers = connectionHeaders(client);
    const timeout = ms => signal ? AbortSignal.any([signal, AbortSignal.timeout(ms)]) : AbortSignal.timeout(ms);
    phase = 'unauthenticated HTTP';
    const denied = await fetch(base+'/health', {redirect:'manual', signal:timeout(15_000)});
    if (![401,403].includes(denied.status)) throw new Error('Unauthenticated requests are not blocked with 401/403; review bridge authentication and routing.');
    if (client.auth_mode === 'quick_tunnel') {
      phase = 'incorrect-key rejection';
      const wrong = (client.connection_key[0] === '0' ? '1' : '0') + client.connection_key.slice(1);
      const rejected = await fetch(base+'/health', {headers:{authorization:`Bearer ${wrong}`}, redirect:'manual', signal:timeout(15_000)});
      if (rejected.status !== 403) throw new Error('An incorrect connection key was not rejected.');
    }
    phase = 'authenticated HTTP RPC';
    const response = await fetch(base+'/api/session/list', { method:'POST', headers:{...headers,'content-type':'application/json'}, redirect:'manual',
      body:JSON.stringify({type:'client-request',rpcId:'probe',method:'session/list',payload:{args:{_request:{}}}}), signal:timeout(20_000) });
    if (!response.ok) throw new Error(`Authenticated HTTP probe failed (${response.status}).`);
    const result = await response.json();
    if (result.result?.ok !== true || !Array.isArray(result.result?.value?.items)) throw new Error('Unexpected DSH RPC response.');
    log('PASS: unauthenticated HTTP blocked; authenticated DSH RPC succeeded.');
    phase = 'authenticated WebSocket';
    await new Promise((resolve,reject) => {
      const socket = new WebSocket(base.replace(/^https:/,'wss:')+'/api/remote.mux', { headers, followRedirects:false, handshakeTimeout:15_000, maxPayload:32*1024*1024 });
      const timer = setTimeout(() => finish(new Error('WebSocket probe timed out.')),20_000);
      let settled = false;
      const cancel = () => finish(new Error('Connection probe cancelled.'));
      const finish = (error) => {
        if (settled) return;
        settled = true; clearTimeout(timer); signal?.removeEventListener('abort', cancel); socket.terminate();
        error ? reject(error) : resolve();
      };
      socket.on('error',()=>finish(new Error('WebSocket probe failed; check authentication and tunnel routing.')));
      socket.on('close',()=>finish(new Error('WebSocket closed before DSH was ready.')));
      signal?.addEventListener('abort', cancel, {once:true});
      if (signal?.aborted) { cancel(); return; }
      socket.on('open',()=>socket.send(JSON.stringify({type:'open',streamId:'probe',endpoint:'$events',payload:{args:{}}})));
      socket.on('message',data=>{ try { const frame=streamValue(data); if(frame.type==='ready' && frame.clientId) finish(); } catch {} });
    });
    log('PASS: authenticated WebSocket received DSH ready frame. No session content or credentials printed.');
  } catch (error) {
    const code = error.cause?.code || error.code;
    const suffix = typeof code === 'string' && /^[A-Z0-9_]+$/.test(code) ? ` (${code})` : '';
    // Never include response JSON, credentials, or URL-parser input in diagnostics.
    throw new Error(`Connection check failed during ${phase}${suffix}.`);
  }

}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    let client;
    try { client = JSON.parse(fs.readFileSync(path.join(configDir(), 'client.json'), 'utf8')); }
    catch { throw new Error('Cannot read private client.json; run scripts/store-secret.py client.'); }
    await probeConnection(client);
  } catch (error) { console.error('FAIL:', error.message || 'Check private client.json.'); process.exitCode = 1; }
}
