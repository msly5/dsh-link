import { createRemoteJWKSet, jwtVerify } from 'jose';

export function accessVerifier({ team, aud }, keySet = createRemoteJWKSet(new URL(`${team}/cdn-cgi/access/certs`), { timeoutDuration: 5000 })) {
  if (!team || !aud) throw new Error('Cloudflare Access configuration is required.');
  return async (req) => {
    const token = req.headers['cf-access-jwt-assertion'];
    if (typeof token !== 'string' || token.length > 16384) throw new Error('Unauthorized');
    const { payload } = await jwtVerify(token, keySet, {
      algorithms: ['RS256'], issuer: team, audience: aud,
      requiredClaims: ['exp', 'iat', 'iss', 'aud'], clockTolerance: 5,
    });
    return payload;
  };
}
