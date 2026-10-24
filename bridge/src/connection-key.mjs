import { timingSafeEqual } from 'node:crypto';

export const validConnectionKey = key => typeof key === 'string' && /^[a-f0-9]{64}$/.test(key);

export function connectionKeyVerifier(key) {
  if (!validConnectionKey(key)) throw new Error('A generated 256-bit connection key is required.');
  const expected = Buffer.from(key, 'ascii');
  return async req => {
    const header = req.headers.authorization;
    if (typeof header !== 'string' || !/^Bearer [a-f0-9]{64}$/.test(header) ||
        !timingSafeEqual(Buffer.from(header.slice(7), 'ascii'), expected)) throw new Error('Unauthorized');
  };
}

export function connectionHeaders(client) {
  if (client.auth_mode === 'quick_tunnel') {
    if (!validConnectionKey(client.connection_key)) throw new Error('Invalid Quick Tunnel connection key.');
    return { authorization: `Bearer ${client.connection_key}` };
  }
  if (client.auth_mode !== undefined && client.auth_mode !== 'access') throw new Error('Unsupported connection mode.');
  for (const key of ['client_id', 'client_secret']) {
    if (typeof client[key] !== 'string' || !/^[\x21-\x7e]{1,4096}$/.test(client[key])) {
      throw new Error('Valid Service Token credentials are required.');
    }
  }
  return { 'CF-Access-Client-Id': client.client_id, 'CF-Access-Client-Secret': client.client_secret };
}
