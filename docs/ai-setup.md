# 给 AI 的配置执行手册

目标是让一个新用户从干净 clone 得到自己可用的 dsh link。先读根目录 AGENTS.md；仅通过公开源码无法获得任何人的凭证。

## 先识别电脑与手机平台

先确认电脑是 macOS 还是 Windows、手机是 iOS 还是 Android。两种手机都可以连接两种电脑。

- Windows 执行 [Windows 指南](windows.md)，用 `npm.cmd`、PowerShell 和当前用户 ACL；不运行 Homebrew、Xcode、macOS shell / LaunchAgent 安装脚本。
- Android 安装 [Release APK](https://github.com/msly5/dsh-link/releases/latest) 或按 [Android 构建说明](android.md) 使用 JDK 17 / SDK 35；无需 Apple Team。Android 凭证经 Keystore 加密，默认无系统推送。
- iOS 推荐 TestFlight。IPA 是 Apple 分发导出包，不是任意 iPhone 都能直接安装的包；自行构建才需要 Xcode 和自己的签名。
- Windows 桥接自动化测试不等同于真实 Windows DSH 已连通；最终仍需验证用户电脑上的 HTTP / WS 和手机连接。

## 先选择连接方式

没有域名时，按根目录中英文 README 的 **Quick Tunnel** 步骤：安装 Node 22+、cloudflared（仅 Mac 原生二维码还需要 Xcode 命令行工具），运行 `npm ci --ignore-scripts --prefix bridge` 和 `npm run quick --prefix bridge`。无需 Cloudflare 账户、域名、Team/AUD、Service Token 或 Tunnel Token。不要执行下面的 Cloudflare 配置和 LaunchAgent 安装。二维码自动填入 iOS / Android 的 Quick Tunnel 模式、临时 URL 和连接密钥；请使用 TestFlight 1.0 (8) 或更新构建，或从源码构建；1.0 (7) 及更早版本不支持。

启动命令独立使用 3080 端口，不替换现有 Access 服务。密钥仅在进程内存和本地二维码窗口中，严禁记录到文件、命令参数、日志或 AI 回复。终端报告无密钥/错误密钥拒绝和认证 HTTP/WS 成功后，再验证手机扫码、测试、保存及聊天。输入 `p` 回车可重开二维码，`r` 回车可重新检查公网连接；Ctrl+C 停止，重启后重新扫码。若端口占用，选择新的 `DSH_QUICK_PORT`，不结束已有进程。启动失败不等于已连通，不把旧 TestFlight 构建当成支持新模式。

需要固定地址、按设备发放 Service Token 时，使用下方 Access 部署流程。

## 需要从本地确认或向用户获取的信息

| 信息 | 取得方式 | 是否可放 Git |
| --- | --- | --- |
| DSH 安装、登录状态、版本 | 本地检查；doctor 仅报告成功/失败 | 可记录版本，不放账号或会话 |
| Node / Xcode / cloudflared 路径与版本 | `command -v`、`--version`、`xcodebuild -version` | 文档只写通用命令 |
| Cloudflare Account / Zone / 目标 hostname | 用户指定或授权后只读查询 | 个人部署记录留私有目录 |
| Team Domain / 应用 AUD | Cloudflare Zero Trust | 模板放占位符；真实值留本地 |
| Cloudflare API Token | 用户私有文件或已有安全凭证存储 | 禁止 |
| Tunnel Token | 控制台/已授权 API | 禁止；`tunnel.token` |
| Service Token Client ID / Secret | 用户新建或已授权 API | 禁止；手机 Keychain / 可选私有 `client.json` |
| Apple Team / Bundle ID | 用户自己的开发者账户 | 真实个人配置留 `config/Local.xcconfig` |
| APNs key / device token | 仅当用户明确需要推送 | 禁止 |

不要把生产服务目录整包复制到仓库。它们可能同时包含 `.env`、设备 token、日志和私钥。不要上传 DSH 的 `.credentials.yaml`，也不要输出它的完整内容。

## 阶段 A：只读环境检查与本地准备

1. 确认电脑操作系统、DSH 正在运行并已登录；不要替用户退出登录、修改桌面端或关闭其他实例。
2. 检查 Node 22+、npm、Python 3、cloudflared `2025.4.0`+ 与 Xcode。
3. `python3 scripts/bootstrap.py` 创建仓库外的配置模板；已存在的文件会保留。
4. `npm ci --ignore-scripts --prefix bridge` 安装锁定依赖。不要把 `node_modules` 加入 Git。
5. 检查目标本机端口是否已有监听。已有服务归属不清时不要杀进程；可选新端口并同步 Tunnel route。

## 阶段 B：Cloudflare

按 `cloudflare.md` 完成；可以使用控制台或官方 API。优先新建本项目专用的资源，先 Access 保护，再连接域名到 Tunnel。为每个手机单独发放 Service Token。

使用 API 时从私有文件读取 API Token，在进程内构造请求头。只输出状态、资源类型和脱敏错误。创建 Service Token 的响应含 Secret，必须先以 `0600` 写到私有文件，不能直接将 API 返回值打印到工具输出。发生部分失败时保留已创建资源 ID 和进度，供用户恢复或删除本次创建的资源；不要反复新建重复资源。

如果无法执行某项需要本人登录的步骤，列出具体页面和所需字段，让用户完成该交互，再继续其余工作。不要为绕过登录而降低 Access 策略。

## 阶段 C：电脑桥接和隧道

- 私有 `bridge.env` 配置正确的 Team Domain 和 AUD；仅需这个验签配置，不需要把手机 Secret 给 bridge。
- `npm run doctor --prefix bridge` 验证本机 DSH。该步骤不证明公网可用。
- 前台启动 `npm start --prefix bridge` 与 `npm run tunnel --prefix bridge`，确认 Tunnel Healthy。
- 可选 `python3 scripts/store-secret.py client` 保存探测配置，然后 `node bridge/src/probe.mjs`。AI 若用私有 API 结果创建此 JSON，字段必须是 `server_url`、`client_id`、`client_secret`，模式 `0600`；不要把 JSON 输出到对话。
- 不持久运行时交代前台进程会随终端退出；需要常驻时用 `python3 scripts/service.py install`，不要手写带 token 的 LaunchAgent。
- `service.py uninstall` 仅移除此项目的两个用户启动项，保留 DSH 和私有配置。

## 阶段 D：手机（以下签名步骤仅 iOS 源码构建）

- 复制 `config/Local.example.xcconfig` 为被 Git 忽略的 `Local.xcconfig`，填用户自己的 Team / Bundle ID。
- 默认不开启推送。需要时另读 `push.md`。
- 先模拟器/无签名构建，再按用户授权在自己的设备签名安装。不要把无签名构建称为真机已安装。
- 手机填写 **公网 HTTPS URL、Service Token Client ID、Client Secret**，或在 Mac 运行 `npm run pair --prefix bridge` 显示二维码。它读取仓库外 `0600` 的 `client.json`，不向网页或日志输出凭证。iOS 连接设置可扫码填入，用户确认服务器后保存；系统相机也可打开 `dshremote://configure` 配置链接。不要将真实二维码截图、链接或凭证粘贴进 AI 回复。
- 验证“测试”不保存、保存后重启可读取、修改服务器不会自动携带旧服务器凭证、清除后回到未配置状态。

## 最终验收

- 无凭证请求被拒绝，而不是返回会话或桌面页面。
- 填入错误/过期 token 被拒绝；HTTP 与 WS 保护一致。
- 正确凭证的 HTTP `session/list` 与 WS `/api/remote.mux` 可用。
- 手机能打开已有桌面会话；选择桌面工作区新建的会话在桌面端可见。
- 日志、提交列表和构建产物没有凭证；`check-secrets.py` 通过。
- 交付写清哪些实际验证过、哪些仍需用户完成；未接入 APNs 时明确其为可选未验证功能。

如果用户只要求整理源码/文档，就停在本地可构建、可审阅的成果，不替其开通云资源或推送 GitHub。
