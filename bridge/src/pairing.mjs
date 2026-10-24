import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = path.resolve(fileURLToPath(new URL('../..', import.meta.url)));

export function pairingInvitation(client, now = Date.now()) {
  let server;
  try { server = new URL(client.server_url); } catch { throw new Error('Invalid HTTPS server URL in private client.json.'); }
  if (server.protocol !== 'https:' || !server.hostname || server.username || server.password || server.search || server.hash) {
    throw new Error('Use an HTTPS server URL without user info, query or fragment.');
  }
  for (const key of ['client_id', 'client_secret']) {
    if (typeof client[key] !== 'string' || !/^[\x21-\x7e]{1,4096}$/.test(client[key])) {
      throw new Error('Private client.json must contain valid Service Token credentials.');
    }
  }
  const serverURL = server.href.replace(/\/+$/, '');
  const expiresAt = Math.floor(now / 1000) + 300;
  const payload = {version: 1, expires_at: expiresAt, server_url: serverURL,
    client_id: client.client_id, client_secret: client.client_secret};
  const link = 'dshremote://configure?data=' + Buffer.from(JSON.stringify(payload)).toString('base64url');
  if (Buffer.byteLength(link) > 2000) throw new Error('Connection configuration is too long for a scannable QR code.');
  return {link, server: serverURL, expiresAt};
}

export function readPairingClient(directory) {
  if (!path.isAbsolute(directory)) throw new Error('DSH_REMOTE_CONFIG_DIR must be an absolute private directory.');
  let file, stat, directoryStat, realDirectory;
  try {
    realDirectory = fs.realpathSync(directory);
    directoryStat = fs.statSync(realDirectory);
    file = fs.realpathSync(path.join(directory, 'client.json'));
    stat = fs.statSync(file);
  } catch { throw new Error('Cannot read private client.json; run python3 scripts/store-secret.py client first.'); }
  const relative = path.relative(repository, file);
  const relativeDirectory = path.relative(repository, realDirectory);
  if (!relative.startsWith('..' + path.sep) || !relativeDirectory.startsWith('..' + path.sep) ||
      (directoryStat.mode & 0o077) !== 0 || !directoryStat.isDirectory() || directoryStat.uid !== process.getuid() ||
      (stat.mode & 0o077) !== 0 || stat.uid !== process.getuid() || !stat.isFile() || stat.size > 32_768) {
    throw new Error('Use an owned 0700 directory and a private 0600 client.json outside the repository.');
  }
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch { throw new Error('Private client.json is not valid JSON.'); }
}
