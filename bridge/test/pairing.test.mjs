import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pairingInvitation, readPairingClient } from '../src/pairing.mjs';

const client = {server_url:'https://EXAMPLE.com:443/dsh///', client_id:'test-client-id', client_secret:'test-client-secret'};
test('pairing payload matches the shared Swift protocol fixture', () => {
  const fixture = JSON.parse(fs.readFileSync(new URL('./fixtures/pairing-v1.json', import.meta.url)));
  assert.deepEqual(pairingInvitation(client, 1_700_000_000_000), fixture);
});
test('Quick Tunnel pairing uses version 2 without Access credentials', () => {
  const fixture = JSON.parse(fs.readFileSync(new URL('./fixtures/pairing-v2.json', import.meta.url)));
  const key = 'a'.repeat(64);
  const invitation = pairingInvitation({server_url:'https://fixture.trycloudflare.com', auth_mode:'quick_tunnel', connection_key:key}, 1_700_000_000_000);
  assert.deepEqual(invitation, {...fixture, connectionKey:key});
  const payload = JSON.parse(Buffer.from(invitation.link.split('data=')[1], 'base64url'));
  assert.equal(payload.client_secret, undefined);
  assert.equal(payload.auth_mode, 'quick_tunnel');
  assert.throws(() => pairingInvitation({server_url:client.server_url, auth_mode:'quick_tunnel', connection_key:'short'}));
  assert.throws(() => pairingInvitation({...client, auth_mode:'unknown'}));
});
test('rejects insecure, ambiguous or credential-bearing server URLs and header injection', () => {
  for (const server_url of ['http://example.com','https://user:pass@example.com','https://example.com?secret=x','https://example.com#x','invalid']) {
    assert.throws(() => pairingInvitation({...client, server_url}));
  }
  for (const client_secret of ['', 'test\nheader', '你好', 'a'.repeat(4097)]) {
    assert.throws(() => pairingInvitation({...client, client_secret}));
  }
  assert.throws(() => pairingInvitation({...client, client_secret:'test'.repeat(600)}));
});
test('reads only private configuration outside the repository and redacts parse errors', {skip:process.platform==='win32'}, () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-pairing-test-'));
  try {
    const file = path.join(directory, 'client.json');
    fs.writeFileSync(file, JSON.stringify(client), {mode:0o600});
    assert.deepEqual(readPairingClient(directory), client);
    fs.chmodSync(directory, 0o755);
    assert.throws(() => readPairingClient(directory), /0700/);
    fs.chmodSync(directory, 0o700);
    fs.chmodSync(file, 0o644);
    assert.throws(() => readPairingClient(directory), /0600/);
    fs.chmodSync(file, 0o600);
    fs.writeFileSync(file, 'private-value-that-must-not-appear-in-errors');
    assert.throws(() => readPairingClient(directory), {message:'Private client.json is not valid JSON.'});
    assert.throws(() => readPairingClient('./relative'));
  } finally { fs.rmSync(directory, {recursive:true, force:true}); }
});
