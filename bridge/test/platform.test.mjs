import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawn, execFileSync} from 'node:child_process';
import {once} from 'node:events';
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
    execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',
      "$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User; $acl=[Security.AccessControl.DirectorySecurity]::new(); $acl.SetOwner($sid); $acl.SetAccessRuleProtection($true,$false); $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')); Set-Acl -LiteralPath $env:DSH_PRIVATE_PATH -AclObject $acl"],{env:{...process.env,DSH_PRIVATE_PATH:dir},stdio:'ignore'});
    assert.doesNotThrow(()=>assertPrivate(dir));
  } finally {child.kill();await once(child,'exit');fs.rmSync(dir,{recursive:true,force:true});}
});
