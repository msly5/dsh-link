import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { configDir } from './config.mjs';
import { pairingInvitation, readPairingClient } from './pairing.mjs';

try {
  if (process.platform !== 'darwin') throw new Error('The local QR window requires macOS and Xcode command-line tools.');
  if (process.argv.slice(2).some(arg => arg !== '--check')) throw new Error('Supported option: --check (verify QR locally without opening a window).');
  const invitation = pairingInvitation(readPairingClient(configDir()));
  const script = fileURLToPath(new URL('../../scripts/pair-window.swift', import.meta.url));
  const revision = createHash('sha256').update(script).update(fs.readFileSync(script)).digest('hex').slice(0,16);
  const app = path.join(configDir(), 'cache', `pairing-${revision}.app`);
  const executable = path.join(app, 'Contents', 'MacOS', 'PairingWindow');
  if (!fs.existsSync(executable)) {
    fs.mkdirSync(path.dirname(executable), {recursive:true, mode:0o700});
    fs.writeFileSync(path.join(app, 'Contents', 'Info.plist'), `<?xml version="1.0"?><plist version="1.0"><dict>
      <key>CFBundleIdentifier</key><string>app.dshremote.pairing</string>
      <key>CFBundleName</key><string>dsh link pairing</string>
      <key>CFBundleExecutable</key><string>PairingWindow</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>NSHighResolutionCapable</key><true/>
      </dict></plist>`, {mode:0o600});
    console.log('Preparing the local QR window…');
    const compiler = spawn('/usr/bin/xcrun', ['swiftc', script, '-o', executable], {stdio:'inherit'});
    await new Promise((resolve,reject) => {
      compiler.on('error', () => reject(new Error('Could not start Swift. Check Xcode command-line tools.')));
      compiler.on('exit', code => code === 0 ? resolve() : reject(new Error('Could not build the local QR window.')));
    });
  }
  const child = spawn(executable, process.argv.slice(2), {stdio: ['pipe', 'inherit', 'inherit']});
  child.stdin.on('error', () => {});
  child.stdin.end(JSON.stringify(invitation)); // Credentials stay in memory; never argv, logs or a web page.
  child.on('error', () => { console.error('Could not start the local QR window. Check Xcode command-line tools.'); process.exitCode = 1; });
  child.on('exit', code => { process.exitCode = code === 0 ? 0 : 1; });
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => child.kill(signal));
} catch (error) { console.error(error.message); process.exitCode = 1; }
