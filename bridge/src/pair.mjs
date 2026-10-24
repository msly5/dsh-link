import { configDir } from './config.mjs';
import { pairingInvitation, readPairingClient } from './pairing.mjs';
import { openPairingWindow } from './pair-window.mjs';

try {
  if (process.argv.slice(2).some(arg => arg !== '--check')) throw new Error('Supported option: --check (verify QR locally without opening a window).');
  const child = await openPairingWindow(pairingInvitation(readPairingClient(configDir())), {check: process.argv.includes('--check')});
  child.on('error', () => { console.error('Could not start the local QR window.'); process.exitCode = 1; });
  child.on('exit', code => { process.exitCode = code === 0 ? 0 : 1; });
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => child.kill(signal));
} catch (error) { console.error(error.message); process.exitCode = 1; }
