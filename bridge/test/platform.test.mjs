import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawn, execFileSync} from 'node:child_process';
import {once} from 'node:events';
import {fileURLToPath} from 'node:url';
import {findDshPorts} from '../src/dsh.mjs';
import {openPairingWindow} from '../src/pair-window.mjs';
import {pairingInvitation} from '../src/pairing.mjs';
import {assertPrivate} from '../src/private-files.mjs';

test('Windows discovery emits ports only and deduplicates loopback listeners', () => {
  let args;
  assert.deepEqual(findDshPorts('win32',(command,argv,options) => {
    assert.equal(command,'powershell.exe'); assert.equal(options.windowsHide,true); args=argv;
    return '42100\r\n42100\r\n65536\r\n';
  }), [42100]);
  assert.match(args.at(-1),/LocalAddress -eq '127.0.0.1'/);
  assert.match(args.at(-1),/OwningProcess/);
  assert.throws(()=>findDshPorts('unknown'),/DSH_UPSTREAM_PORT/);
});

test('Windows discovers a real host process and renders a local QR image', {skip:process.platform!=='win32'}, async () => {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'dsh-link-platform-'));
  const host=path.join(dir,'dsh-desktop-host','lib','index.js');fs.mkdirSync(path.dirname(host),{recursive:true});
  fs.writeFileSync(host,"const http=require('node:http');const s=http.createServer();s.listen(0,'127.0.0.1',()=>console.log(s.address().port));");
  const child=spawn(process.execPath,[host],{stdio:['ignore','pipe','ignore']});
  try {
    const [port]=await once(child.stdout,'data');
    assert.ok(findDshPorts().includes(Number(port.toString().trim())));
    const qr=await openPairingWindow(pairingInvitation({server_url:'https://fixture.trycloudflare.com',auth_mode:'quick_tunnel',connection_key:'a'.repeat(64)}),{check:true});
    const [code]=await once(qr,'exit');assert.equal(code,0);
    execFileSync('python',['-c',
      "import os, sys; from pathlib import Path; sys.path.insert(0, os.environ['DSH_TEST_SCRIPTS']); from private_config import protect_directory; protect_directory(Path(os.environ['DSH_PRIVATE_PATH']))"],
      {env:{...process.env,DSH_PRIVATE_PATH:dir,DSH_TEST_SCRIPTS:fileURLToPath(new URL('../../scripts/',import.meta.url))},stdio:['ignore','ignore','inherit']});
    assert.doesNotThrow(()=>assertPrivate(dir));
    const config=path.join(dir,'fixture.json');fs.writeFileSync(config,'{}');
    assert.doesNotThrow(()=>assertPrivate(config));
    execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',
      "$ErrorActionPreference='Stop'; $acl=[IO.File]::GetAccessControl($env:DSH_PRIVATE_PATH); $everyone=[Security.Principal.SecurityIdentifier]::new('S-1-1-0'); $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($everyone,'Read','Allow')); [IO.File]::SetAccessControl($env:DSH_PRIVATE_PATH,$acl)"],
      {env:{...process.env,DSH_PRIVATE_PATH:config},stdio:['ignore','ignore','inherit']});
    assert.throws(()=>assertPrivate(config),/Private configuration ACL/);
  } finally {child.kill();await once(child,'exit');fs.rmSync(dir,{recursive:true,force:true});}
});
