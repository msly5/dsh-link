import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { configDir } from './config.mjs';
import QRCode from 'qrcode';

export async function openPairingWindow(invitation, { check = false } = {}) {
  if (process.platform === 'win32') {
    const script = fileURLToPath(new URL('../../scripts/pair-window.ps1', import.meta.url));
    const png = await QRCode.toBuffer(invitation.link, {type:'png', width:640, margin:4, errorCorrectionLevel:'M'});
    const child = spawn('powershell.exe', ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', script, ...(check ? ['-Check'] : [])], {stdio:['pipe','inherit','inherit'], windowsHide:true});
    child.stdin.on('error', () => {});
    child.stdin.end(JSON.stringify({...invitation, png:png.toString('base64')}));
    return child;
  }
  if (process.platform !== 'darwin') throw new Error('The local QR window requires macOS and Xcode command-line tools.');
  const script = fileURLToPath(new URL('../../scripts/pair-window.swift', import.meta.url));
  const directory = configDir();
  const repository = fileURLToPath(new URL('../..', import.meta.url));
  if (!path.isAbsolute(directory) || !path.relative(repository, directory).startsWith('..' + path.sep)) {
    throw new Error('Use an absolute private configuration directory outside the repository.');
  }
  fs.mkdirSync(directory, {recursive:true, mode:0o700});
  const stat = fs.statSync(directory);
  if ((stat.mode & 0o077) !== 0 || stat.uid !== process.getuid()) throw new Error('Use an owned 0700 private configuration directory.');
  const app = path.join(directory, 'cache', 'pairing-window.app');
  const executable = path.join(app, 'Contents', 'MacOS', 'PairingWindow');
  if (!fs.existsSync(executable) || fs.statSync(executable).mtimeMs < fs.statSync(script).mtimeMs) {
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
    await new Promise((resolve, reject) => {
      compiler.on('error', () => reject(new Error('Could not start Swift. Check Xcode command-line tools.')));
      compiler.on('exit', code => code === 0 ? resolve() : reject(new Error('Could not build the local QR window.')));
    });
  }
  const child = spawn(executable, check ? ['--check'] : [], {stdio: ['pipe', 'inherit', 'inherit']});
  child.stdin.on('error', () => {});
  child.stdin.end(JSON.stringify(invitation)); // Credentials only cross a local pipe.
  return child;
}
