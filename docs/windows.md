# Windows 连接指南 / Windows setup

[简体中文 README](../README.md) · [English README](../README.en.md)

## 支持范围

DSH 官方桌面端提供 Windows 版本，与 macOS 使用同一套桌面 Host、RPC 和 WebSocket 协议。dsh link 的桥接现支持 Windows 10/11：自动发现当前 DSH Host 的 loopback 端口、读取当前用户的本地 DSH 凭证，并用原生窗口显示二维码。**手机可以是 iOS 或 Android，电脑可以是 Mac 或 Windows。**

Windows 适配通过自动化桥接测试；当前未在用户的真实 Windows DSH 安装上完成端到端验收。请先运行本机 doctor，再以公网 HTTP/WS 和手机实际连接结果为准。依赖 DSH 内部接口，后续 DSH 更新仍可能需要适配。[DSH 官方桌面说明](https://github.com/deepseek-ai/deepseek-harness/blob/master/apps/desktop/README.md)。

## 1. 安装工具

安装并登录官方 DSH，打开至少一个工作区。安装 Node.js 22+、Python 3 和 cloudflared；可用官方安装程序，也可在 PowerShell 中使用 winget：

```powershell
winget install --id OpenJS.NodeJS.LTS -e
winget install --id Python.Python.3.12 -e
winget install --id Cloudflare.cloudflared -e
```

安装后新开 PowerShell，确认 `node --version`、`python --version`、`cloudflared --version` 可用。不需要 Xcode、Homebrew 或管理员常驻服务。PowerShell 若阻止 `npm.ps1`，使用 `npm.cmd`，不要全局放宽执行策略。

```powershell
git clone https://github.com/msly5/dsh-link.git
cd dsh-link
npm.cmd ci --ignore-scripts --prefix bridge
```

## 2A. 没有域名：Quick Tunnel

```powershell
npm.cmd run quick --prefix bridge
```

自动打开本地二维码窗口。在手机连接设置里扫码，测试并保存。二维码也可显示临时地址和连接密钥供手动填写。成功连接需要终端明确报告 **PASS：未授权请求被拒绝，已认证 HTTP / WebSocket 到达 DSH**；只有窗口出现还不代表公网连通。

- 终端保持开启；`p` 回车重开二维码，`r` 回车重试连接，`Ctrl+C` 停止本次桥接和隧道。
- 每次启动生成新地址与密钥；重启后所有手机重新扫码。多个手机可共用本次运行的连接。
- 默认端口 3080。被占用时先设置 `$env:DSH_QUICK_PORT = '3081'`；不要关闭不明进程。
- 凭证只经进程管道传给本机原生窗口，不写文件、不打印、不调用在线二维码服务。

## 2B. 有域名：Tunnel + Access（长期使用推荐）

按 [Cloudflare 详细指南](cloudflare.md) 配置 **Service Token → 整个域名的 Service Auth → Tunnel → DNS**，这些云端步骤不区分 Mac/Windows。

```powershell
python scripts/bootstrap.py
```

默认私有目录是 `$HOME\.config\dsh-remote`。脚本会为目录设置当前 Windows 账户专用 ACL。私有 `bridge.env` 填入 Team Domain 与应用 AUD；不要放入手机 Client Secret。

```powershell
python scripts/store-secret.py tunnel
python scripts/store-secret.py client
npm.cmd run doctor --prefix bridge
npm.cmd start --prefix bridge
# 另开终端，在同一仓库目录：
npm.cmd run tunnel --prefix bridge
# 再开终端显示二维码：
npm.cmd run pair --prefix bridge
```

输入脚本会隐藏密钥，令牌通过 `--token-file` 读取，避免放入命令历史。不要在 Windows 执行 `sh scripts/run-tunnel.sh` 或 `scripts/service.py`：后者是 macOS LaunchAgent 管理器。

需要登录后自动运行时，可自行用 Windows 任务计划程序分别启动 `node <仓库绝对路径>\bridge\src\index.mjs` 和 `node <仓库绝对路径>\bridge\src\tunnel.mjs`，选择**当前已登录用户**、不提升权限、设置仓库为起始目录。不要把令牌放在任务参数里；DSH 必须在同一 Windows 用户下运行。默认不自动创建计划任务。

## 3. DSH 发现与故障排查

- 自动发现通过 PowerShell `Get-CimInstance Win32_Process` 找到 `dsh-desktop-host/lib/index.js`，再读取这些进程的 `127.0.0.1` 监听端口；不会把进程命令行打印到终端。
- 默认凭证文件：`$HOME\.dsh\.credentials.yaml`。设置了 `DSH_HOME` 时跟随该目录；自定义安装可设置 `DSH_CREDENTIALS_FILE` 为准确的绝对路径。不要复制、编辑或上传这个文件。
- 多个 DSH 实例时，在私有 `bridge.env` 设置 `DSH_UPSTREAM_PORT` 选择目标。不要猜端口，也不要关闭别人的实例。桌面重启后指定的随机端口可能变化。
- 二维码需要 Windows PowerShell 和 .NET Windows Forms，适用于本机交互式桌面，不是无界面的 Windows Server 会话。
- 403：检查连接模式、Service Token 或本次 Quick 密钥。502/503：检查 DSH 登录、Host 和端口。网络故障：先检查 DNS、cloudflared 以及防火墙出站连接。
- 不需要打开 Windows 入站 3079/3080 端口，也不要把 bridge 监听地址改为 `0.0.0.0`。

## English

The official DSH desktop app supports Windows and shares its Host/RPC/WebSocket protocol with macOS. The bridge now supports Windows 10/11 process discovery and native QR pairing. Both iOS and Android clients can connect to either desktop OS. Windows bridge automation is covered by CI; end-to-end validation against a real, signed-in Windows DSH installation is still required.

1. Install and sign in to DSH; install Node.js 22+, Python 3 and cloudflared. Use the `winget` commands above or official installers. Open a fresh PowerShell. Use `npm.cmd` if PowerShell blocks `npm.ps1`; no global execution-policy change is needed.
2. Clone the repository and run `npm.cmd ci --ignore-scripts --prefix bridge`.
3. **Without a domain:** `npm.cmd run quick --prefix bridge`. Scan the native window in the mobile app, test and save. Wait for the public HTTP/WS success message. Keep the terminal running; `p` reopens pairing, `r` retries the probe, Ctrl+C stops the session. Every restart requires a fresh scan on every phone. Use `$env:DSH_QUICK_PORT = '3081'` only if the default port is occupied.
4. **Recommended for daily use:** follow [Cloudflare setup](cloudflare.md) for a domain, a whole-hostname Service Auth application, Service Token and Tunnel. Run `python scripts/bootstrap.py`, configure Team Domain/AUD in private `bridge.env`, and use the hidden-input `store-secret.py` commands above. Start the bridge, `npm.cmd run tunnel --prefix bridge`, and `npm.cmd run pair --prefix bridge` in separate terminals.
5. Private configuration defaults to `$HOME\.config\dsh-remote`; bootstrap applies a user-only ACL before storing secrets. DSH credentials stay in `$HOME\.dsh\.credentials.yaml`, or `DSH_HOME` / an explicit `DSH_CREDENTIALS_FILE`. Multiple hosts require an explicit `DSH_UPSTREAM_PORT`.
6. macOS LaunchAgent and shell scripts are not Windows installers. Optional persistence can use Task Scheduler under the same signed-in user, invoking `index.mjs` and `tunnel.mjs` with absolute paths and no secrets in arguments. Keep DSH open; never expose the loopback bridge via a firewall inbound rule.
