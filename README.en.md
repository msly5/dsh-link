# dsh link

[简体中文](README.md) · **English**

Continue your Mac's DSH conversations on iPhone and iPad.

**An unofficial iOS client and macOS bridge for personal, self-hosted use.** Tasks, model calls, and file operations run on your Mac. Use your phone to send messages and images, follow progress, approve actions, and answer questions. DeepSeek Harness must be installed and signed in on your Mac. This repository does not include the DSH desktop app.

<img src="DSHRemote/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="96" alt="dsh link black whale icon">

**Public beta: [Install dsh link with TestFlight](https://testflight.apple.com/join/KqMhXcHS)**

Install TestFlight on your iPhone or iPad, then open the link to join. You still need to set up the Mac bridge and connection as described below.

- A minimal SwiftUI interface that follows the system's light or dark appearance. Switch between conversations and workspaces in the sidebar, using the same DSH backend as the desktop app.
- An adaptive iPad layout with a workspace/conversation sidebar and chat pane on wide windows. Narrow windows use a drawer. Rotation preserves the active chat and unsent draft.
- Expand or collapse conversations by desktop workspace. Group the conversation list by workspace or date. Archive conversations from their menu and restore them from **Archived**; changes sync with the desktop app.
- Streaming replies, collapsible thinking and tool activity, Markdown, and horizontally scrollable tables.
- Image uploads and previews. Conversation history is cached locally, separated by server and conversation.
- Action approvals, questions, permission selection, and optional APNs notifications.
- Enter your server and Cloudflare Service Token manually, or scan a QR code on your Mac. Credentials stay in the device's Keychain; neither the source nor the app contains preconfigured credentials.
- Includes the Mac bridge, installation and diagnostic scripts, and an AI-assisted setup guide.

<img src="docs/screens/dsh-link/iphone-home.jpg" width="220" alt="dsh link home screen and black whale"> <img src="docs/screens/dsh-link/iphone-sidebar.jpg" width="220" alt="dsh link workspace and conversation sidebar"> <img src="docs/screens/dsh-link/iphone-chat.jpg" width="220" alt="dsh link chat and table">

## How it connects

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/connection-dark-en.svg">
  <img src="docs/images/connection-light-en.svg" width="900" alt="iPhone or iPad → Cloudflare Access and Tunnel → Mac bridge and DSH">
</picture>

Cloudflare Access validates the phone's Service Token at the edge. The Mac bridge then validates the JWT signature, issuer, application audience (AUD), and expiry before using the **current Mac user's** local DSH browser-session credentials to reach the desktop app. The bridge discovers DSH's random port automatically.

The `bridge/` directory is the companion DSH "plugin." It runs as a separate process: **you do not need to place files in the DSH installation or modify `app.asar`**. It relies on internal DSH RPC, event, and authentication formats, so DSH updates may require changes to this project. There is no official compatibility guarantee. The desktop version checked for this project is `0.2.1-rc.2` on macOS.

## Requirements

| Component | Requirement |
| --- | --- |
| Mac | DeepSeek Harness installed, running, signed in, with at least one usable conversation |
| iPhone / iPad | iOS / iPadOS 17 or later |
| Xcode | Version 16 or later; the current project was built with Xcode 27.1 |
| Node.js | Version 22 or later; current LTS recommended, including npm |
| Python | Python 3 for setup, service management, and security scripts |
| cloudflared | A version supporting `--token-file`, at least `2025.4.0` |
| Cloudflare | Your own account, a domain managed by Cloudflare, and Zero Trust / Access |
| Apple signing | Your own Apple account/Team for source builds on a device; APNs is optional and needs the appropriate signing capability |

Your Mac must stay awake, online, and running DSH. The phone does not need cloudflared, and no inbound port needs to be exposed on the Mac.

## Let an AI help you set up

Clone this repository on your Mac and open it with an AI assistant that can access local files and a terminal. Give it this prompt:

> Read this repository's AGENTS.md, docs/ai-setup.md, and docs/cloudflare.md, and help me set up dsh link. First inspect DSH, Node.js, Xcode, and cloudflared on this Mac. My target hostname is `<your hostname>`. Create a dedicated Tunnel, Access application, and Service Auth policy using the Cloudflare account and domain I explicitly select. Read sensitive credentials from private files outside the repository or secure input. Do not print them, put them in source code, or commit them to Git. Configure the bridge, tunnel, and iOS build settings. Then verify that unauthenticated requests are rejected and authenticated RPC and WebSocket connections work. Finally, tell me which fields to fill in on the phone and where the private configuration files are stored.

The AI can handle local installation, file generation, diagnostics, and authorized Cloudflare changes. Cloudflare/Apple sign-in, account selection, payments, and trusting a developer on the phone may still require you to act. **A successful build alone does not prove the connection works.** The detailed deployment guides linked below are currently in Chinese; the AI can read them as part of this workflow.

## Quick start

Clone the project if you have access to the repository, or after it becomes public. Run subsequent commands from the repository root:

```bash
git clone https://github.com/msly5/dsh-link.git
cd dsh-link
python3 scripts/bootstrap.py
npm ci --ignore-scripts --prefix bridge
```

`bootstrap.py` only checks tools and creates a template at `~/.config/dsh-remote/bridge.env`. It does not create cloud resources, start services, or overwrite existing configuration. To use another private directory, set `DSH_REMOTE_CONFIG_DIR=/absolute/path`; the other scripts use the same variable.

The project is now called **dsh link**. To keep existing clients and Mac services working, it retains the `DSHRemote` Xcode project, existing Bundle ID, `dshremote://` pairing links, `DSH_REMOTE_CONFIG_DIR`, and private configuration directory. The name change does not require you to re-enter connection credentials.

1. **Configure Cloudflare:** Follow the [Cloudflare setup guide](docs/cloudflare.md) to create a dedicated Service Token, Access application, Tunnel, and hostname route.
2. **Configure the Mac bridge:** Set the Team Domain and application AUD in `bridge.env` outside the repository.
3. **Check and start the local services:**

```bash
npm run doctor --prefix bridge
npm start --prefix bridge
# In another terminal, still from the repository root:
sh scripts/run-tunnel.sh
```

4. **Build the iOS client from source:**

```bash
cp config/Local.example.xcconfig config/Local.xcconfig
open DSHRemote.xcodeproj
```

Set your unique Bundle ID and `DEVELOPMENT_TEAM` in `config/Local.xcconfig`, or select your Team in Xcode's Signing & Capabilities settings. Choose the `DSHRemote` scheme and your iPhone or iPad, then click Run. APNs is disabled by default; push notifications are not required for ordinary use. If you installed through TestFlight, skip this source-build step.

5. **Configure the phone:** Enter your HTTPS server address, such as `https://dsh.example.com`, and the Service Token's Client ID and Client Secret. Tap **Test connection** (测试连接), then **Save** (保存). Testing does not save the draft; saving or clearing the connection updates the local Keychain. Keychain data may survive uninstalling the app. To remove it, first use **Clear saved connection** (清除已保存的连接) in settings.

You can also **scan a QR code**. On the Mac, first save the phone's Service Token using hidden input, then display the local pairing code:

```bash
python3 scripts/store-secret.py client  # Skip if client.json already exists
npm run pair --prefix bridge
```

On the phone, open **Connection settings → Scan Mac connection QR code** (连接设置 → 扫描 Mac 连接二维码), or scan it with the system Camera app. The server and credentials are filled in automatically. Confirm the server, then tap **Save**. Manual entry remains available if camera permission is denied. The Mac window closes after five minutes, and the app rejects expired pairing codes.

The QR code is generated locally in memory using macOS Core Image. It does not open a web page, call an external QR service, or print credentials. It contains the complete Service Token and must be treated as a credential: **do not screenshot, share, or commit it**. Expiry only prevents importing the code; it does not revoke the token. Revoke a leaked token in Cloudflare. To check local generation and recognition without displaying the code, run `npm run pair --prefix bridge -- --check`.

Do not enter a Cloudflare API Token, Tunnel Token, or DSH sign-in secret on the phone. The phone only needs the two **Service Token** credentials.

## Run at login and check connectivity

After confirming that manual startup works, stop the foreground bridge and cloudflared processes, then run:

```bash
python3 scripts/service.py install
```

This installs two LaunchAgents for the current user: `app.dshremote.bridge` and `app.dshremote.tunnel`. They reference this repository's absolute path. Uninstall and reinstall them if you move the checkout. They start when you sign in to your Mac; connectivity is not guaranteed while the Mac is asleep or you are signed out. Logs stay in the private configuration directory and do not contain request content or credentials. DSH's own login items are not modified.

```bash
python3 scripts/service.py uninstall
```

For an automated public-endpoint connection check, first save optional local probe credentials using hidden input:

```bash
python3 scripts/store-secret.py client
node bridge/src/probe.mjs
```

The probe checks that unauthenticated requests are denied, authenticated HTTP RPC succeeds, and the WebSocket receives a DSH ready frame. It does not print conversation content or credentials. Enter the credentials manually on the phone, or generate a pairing code from this private `client.json`. You can delete the private file when you no longer need probing or pairing; this does not affect credentials already saved in the phone's Keychain.

## Development and verification

```bash
swift test
npm ci --ignore-scripts --prefix bridge
npm test --prefix bridge
python3 -m unittest discover -s scripts/tests
python3 scripts/check-secrets.py
xcodebuild -project DSHRemote.xcodeproj -scheme DSHRemote \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The Swift package runs macOS unit tests for the protocol, conversation cache, images, execution history, and connection profiles. iOS UI behavior requires Xcode builds and simulator or device testing. Bridge tests cover JWT rejection, HTTP/WS forwarding, and authentication-header isolation. CI checks and builds the source; it does not deploy your Cloudflare resources.

| Path | Contents |
| --- | --- |
| `DSHRemote/` | Native SwiftUI client, Keychain storage, RPC, and conversation cache |
| `DSHRemote.xcodeproj/` | iOS project and shared scheme |
| `bridge/` | Mac bridge, Access JWT validation, and optional APNs listener |
| `config/` | Generic signing configuration and example push entitlements |
| `scripts/` | Private configuration setup, hidden input, LaunchAgents, and release checks |
| `docs/cloudflare.md` | Step-by-step Cloudflare setup and troubleshooting |
| `docs/ai-setup.md` | AI-assisted deployment workflow and acceptance criteria |
| `docs/push.md` | Optional APNs setup |
| `SECURITY.md` | Trust boundaries, credential handling, and vulnerability reporting |

## Security and intended use

A connected phone can operate your DSH sessions, which may execute commands or access files on the Mac. Only configure Service Tokens on devices you trust. Issue separate tokens per device, renew them periodically, and revoke tokens for lost devices. This project is intended for personal self-hosting; it is not a service with isolated user accounts.

The client sends credentials only to the configured HTTPS server and rejects automatic redirects. The bridge listens only on loopback, and both HTTP and WebSocket requests require a valid Access JWT. There is no unauthenticated mode. Protect the remote hostname with a correctly configured Access application; do not use a Bypass or Everyone policy.

Local conversation and image caches contain conversation content. They stay in the app sandbox and are separated by server and conversation. They are not a cloud backup; if the cache is lost, the app reloads data from the same DSH backend. Push notifications are disabled by default. When enabled, lock-screen notifications show only generic approval or question prompts. See [SECURITY.md](SECURITY.md) for more information.

This repository uses the MIT license. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for information about DSH software, trademarks, and third-party dependencies.
