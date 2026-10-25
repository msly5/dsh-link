import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const configDir = () => process.env.DSH_REMOTE_CONFIG_DIR || path.join(os.homedir(), '.config', 'dsh-remote');
export function loadConfig({ authMode = 'access' } = {}) {
  if (!['access', 'quick_tunnel'].includes(authMode)) throw new Error('Unsupported bridge authentication mode.');
  const file = path.join(configDir(), 'bridge.env');
  if (fs.existsSync(file)) process.loadEnvFile(file);
  const team = (process.env.CF_ACCESS_TEAM_DOMAIN || '').replace(/\/$/, '');
  const aud = process.env.CF_ACCESS_AUD || '';
  if (authMode === 'access' && (!/^https:\/\/[a-zA-Z0-9-]+\.cloudflareaccess\.com$/.test(team) || team.includes('your-team') || !/^[a-fA-F0-9]{64}$/.test(aud))) {
    throw new Error('Set CF_ACCESS_TEAM_DOMAIN and the 64-character application CF_ACCESS_AUD in bridge.env.');
  }
  const port = Number(authMode === 'quick_tunnel' ? process.env.DSH_QUICK_PORT || 3080 : process.env.DSH_PROXY_PORT || 3079);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid DSH_PROXY_PORT.');
  const upstreamPort = process.env.DSH_UPSTREAM_PORT ? Number(process.env.DSH_UPSTREAM_PORT) : undefined;
  if (upstreamPort !== undefined && (!Number.isInteger(upstreamPort) || upstreamPort < 1 || upstreamPort > 65535 || upstreamPort === port)) {
    throw new Error('Invalid DSH_UPSTREAM_PORT.');
  }
  return {
    host: '127.0.0.1', port, team, aud, upstreamPort, authMode,
    credentialsFile: process.env.DSH_CREDENTIALS_FILE || path.join(process.env.DSH_HOME || path.join(os.homedir(), '.dsh'), '.credentials.yaml'),
    configDir: configDir(),
    pushEnabled: process.env.APNS_ENABLED === '1',
  };
}
