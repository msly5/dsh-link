import { loadConfig } from './config.mjs';
import { accessVerifier } from './access.mjs';
import { targetResolver } from './dsh.mjs';
import { createBridge } from './server.mjs';
import { createPush } from './push.mjs';

try {
  const config = loadConfig();
  const target = targetResolver(config);
  const push = createPush(config, target);
  const server = createBridge({ verify: accessVerifier(config), target, push });
  server.on('error', error => { console.error(`Bridge could not listen (${error.code || 'error'}).`); process.exitCode = 1; });
  server.listen(config.port, config.host, () => { console.log(`dsh remote bridge listening on 127.0.0.1:${config.port}; Access JWT validation required.`); push?.start(); });
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { push?.stop(); server.shutdown(); });
} catch (error) { console.error(error.message); process.exitCode = 1; }
