# dsh remote: instructions for AI assistants

Read `README.md`, `docs/ai-setup.md`, and `docs/cloudflare.md` before deployment. This repository contains an unofficial iOS client and a local macOS DSH bridge. It does not contain DSH itself or any working credentials.

## Scope and credentials

- Make only the changes the user requested; preserve existing DSH installations and unrelated Cloudflare resources.
- Never commit secrets, user data, real conversation screenshots, signing profiles, private keys, device tokens, or logs. `.gitignore` alone is not a security audit.
- Put runtime configuration in an absolute path outside this repository, default `~/.config/dsh-remote/`. Files containing secrets must be `0600`, private directories `0700`.
- Never print a secret or embed it in command arguments. Read credentials from private files, OS secure storage or hidden input. Do not ask the user to paste secrets into chat.
- The iOS client stores a single URL-bound connection profile in Keychain. Do not restore compiled `Secrets.swift`, default personal servers, or UserDefaults-based credential storage.
- Keep the bridge bound to `127.0.0.1`. Require signed Cloudflare JWTs for HTTP and WebSocket upgrades. Do not introduce header-presence or `NO_ACCESS` bypasses.
- Cloudflare API Token, Tunnel Token, Service Token, DSH local credentials, and APNs signing key are different credentials. Use each only at its intended layer.

## Deployment workflow

1. Inspect installed tools and running DSH. Run `python3 scripts/bootstrap.py`, then `npm ci --ignore-scripts --prefix bridge`.
2. Determine the user's intended Cloudflare account, Zone, unused hostname, and Team Domain. Read existing resources before any mutation. Do not choose an account based only on a familiar name.
3. Follow `docs/cloudflare.md`: Service Token, entire-hostname Access application with Service Auth, Tunnel loopback route and DNS. Cloud modifications require user authorization; a request to configure this project authorizes its own necessary resources, not unrelated replacements.
4. Store Cloudflare results privately; never copy DSH's `.credentials.yaml` into this repo. Write only Team Domain/AUD and optional settings into private `bridge.env`.
5. Run `npm run doctor --prefix bridge`, then test bridge and tunnel in foreground. Install LaunchAgents only if the user wants persistent operation. Never restart unknown existing services to free a port.
6. Configure `config/Local.xcconfig` using the user's Apple Team and unique Bundle ID. APNs is optional and disabled by default. Build, then guide user-controlled Apple/phone trust steps if necessary.
7. Verify unauthorized denial, authenticated RPC, authenticated WebSocket, and iPhone connection. Do not claim cloud or device delivery from local tests alone.

## Checks

```bash
swift test
npm test --prefix bridge
python3 -m unittest discover -s scripts/tests
python3 scripts/check-secrets.py
xcodebuild -project DSHRemote.xcodeproj -scheme DSHRemote \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Before publication, initialize Git if needed, inspect the explicit file list, stage deliberately, run `python3 scripts/check-secrets.py --staged`, and inspect `git diff --cached --stat`. The scanner reports file/line and rule only, never matching values. It cannot prove absence of every possible secret, so also examine new binary assets and examples manually. Publishing/pushing requires the user's authorization. Never force-push or rewrite an existing repository without a specific request.
