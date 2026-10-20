# Cloudflare 配置：从零到 iPhone 可连接

本文使用独立公网子域名、**远程管理的 Cloudflare Tunnel** 和 **Access Service Auth**。示例域名统一为 `dsh.example.com`，实际配置时全部替换成你自己的域名。不要复用陌生人的服务器或凭证。

界面名称可能调整：Tunnel 可在 Cloudflare Dashboard 的 **Networking → Tunnels** 找到，部分账户也会显示在 Zero Trust 的 Networks / Connectors 下；Access 在 **Zero Trust → Access controls → Applications**。以下最终配置值比菜单位置更重要。

## 1. 准备账户、域名与工具

- 域名的 DNS 已托管到你的 Cloudflare 账户。选择一个未被其他服务使用的子域名，例如 `dsh.example.com`。
- 初始化 Cloudflare Zero Trust 团队，记下 Team Domain，例如 `https://my-team.cloudflareaccess.com`。它不是你的公网服务域名。
- Mac 上安装 Node.js 22+、Python 3、Xcode 和 cloudflared。若已安装 Homebrew，可安装缺少的工具：

```bash
brew install node cloudflared
cloudflared --version
node --version
```

`--token-file` 需要 cloudflared `2025.4.0` 或更新版本。Tunnel 使用出站连接；防火墙需允许 Cloudflare 所需网络流量（尤其 7844 TCP/UDP），无需在路由器映射 3079 或 DSH 随机端口。

官方：[Tunnel 入门](https://developers.cloudflare.com/tunnel/get-started/)、[连接与防火墙要求](https://developers.cloudflare.com/tunnel/configuration/)。

## 2. 创建手机专用的 Service Token

在 Zero Trust 的 **Access controls → Service credentials → Service Tokens** 创建 Service Token：

- 名称：例如 `dsh-remote-iphone`。
- 到期时间：选择你能管理的期限，并记下续期日期。
- 安全保存返回的 **Client ID** 和 **Client Secret**；Secret 通常仅在创建时展示，丢失后应轮换，不能从仓库找回。

这两项供 iPhone 填写。**不要**使用全局 API Key 或 Cloudflare API Token 替代它们。

可选：在 Mac 用 `python3 scripts/store-secret.py client` 隐藏输入保存探测凭证，文件位于私有配置目录，不在 Git 中。避免把 secret 粘贴进 `curl -H` 命令历史或 AI 聊天记录。

官方：[Service Tokens](https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/)。

## 3. 先创建 Access 应用保护整个域名

新建 **Self-hosted application**：

| 字段 | 填写 |
| --- | --- |
| Application name | `dsh remote` |
| Public hostname / Domain | `dsh.example.com` |
| Path | 留空，覆盖整个域名的所有路径 |
| Policy name | `dsh remote iPhone` |
| Policy action | **Service Auth** |
| Include selector | **Service Token** |
| Include value | 第 2 步创建的特定 token |

不要选择 Allow 代替 Service Auth，否则原生客户端可能收到交互式登录跳转。不要使用 Bypass、Everyone 或 Any Service Token；避免给 `/api`、`/push` 或 `/health` 建立更具体的弱保护应用。

保存后在应用的 **Additional settings** 找到 **Application Audience (AUD) Tag**，复制完整的 64 位十六进制字符串。AUD 不是 Client ID，也不是 Tunnel ID。

在 `~/.config/dsh-remote/bridge.env` 填入：

```dotenv
CF_ACCESS_TEAM_DOMAIN=https://my-team.cloudflareaccess.com
CF_ACCESS_AUD=REPLACE_WITH_APPLICATION_AUD_64_HEX_CHARACTERS
DSH_PROXY_PORT=3079
APNS_ENABLED=0
```

这里 Team Domain / AUD 是验签参数，不是手机 Secret。桥接从团队的 `/cdn-cgi/access/certs` 获取公钥，并验证 RS256 签名、issuer、audience 和过期时间。只检查某个请求头存在不足以验证身份。

```bash
chmod 700 ~/.config/dsh-remote
chmod 600 ~/.config/dsh-remote/bridge.env
```

官方：[验证 Access JWT](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/)。

## 4. 创建 Tunnel，但先不要暴露未受保护的域名

在 Tunnels 创建 **Cloudflared** 类型的远程管理 Tunnel：

1. 名称建议 `dsh-remote`。每个自托管用户创建自己的 Tunnel。
2. 安装页会显示带 `--token ...` 的运行命令。只提取其中的 **Tunnel Token**，不要将整条含 token 的命令贴到终端或仓库。
3. 在仓库根目录执行下面的隐藏输入脚本，粘贴 token，按回车：

```bash
python3 scripts/store-secret.py tunnel
```

它会以权限 `0600` 写入 `~/.config/dsh-remote/tunnel.token`。脚本不会覆盖已有文件。

4. 在 **Public Hostname / Published application route** 添加路由：

| 项目 | 值 |
| --- | --- |
| Subdomain | `dsh` |
| Domain | `example.com` |
| Path | 留空 |
| Service type | **HTTP** |
| URL | **127.0.0.1:3079** |

注意服务地址是桥接端口，不是 DSH 自动变化的桌面端口。公网手机仍使用 HTTPS/WSS；HTTP 仅用于同一台 Mac 的 loopback 链路。不要开启 `noTLSVerify` 来规避配置错误。

Cloudflare 通常自动为该主机名创建指向 `<tunnel-id>.cfargotunnel.com` 的代理 DNS 记录。若 DNS 已有同名记录，不要直接覆盖，先确认归属。用 API 配置时，应添加兜底 ingress：`{"service":"http_status:404"}`，避免匹配其他主机名。

官方：[Tunnel Token](https://developers.cloudflare.com/tunnel/reference/tunnel-tokens/)、[`--token-file` 参数](https://developers.cloudflare.com/tunnel/reference/run-parameters/)。

## 5. Mac 本地验证与启动

先打开并登录 DSH 桌面端。在仓库根目录：

```bash
npm ci --ignore-scripts --prefix bridge
npm run doctor --prefix bridge
```

doctor 只验证验签参数配置、本地端口发现和 DSH `session/list` RPC，不打印会话。若发现多个桌面 host，关闭额外实例，或在 `bridge.env` 用 `DSH_UPSTREAM_PORT` 明确指定。普通情况下不要固定端口。

分别在两个终端运行：

```bash
npm start --prefix bridge
```

```bash
sh scripts/run-tunnel.sh
```

Tunnel 显示 Healthy 后，再检查公网：

```bash
python3 scripts/store-secret.py client
node bridge/src/probe.mjs
```

验收应包含：无凭证 HTTP 被 401/403 拒绝；携带该 Service Token 的 DSH RPC 成功；认证 WebSocket 收到 ready 帧。脚本拒绝 HTTP 重定向，不会把凭证交给跳转目标。不要把日志中没有报错当成全部验证通过。

手机中填入公网 URL、Service Token Client ID / Secret，点“测试连接”再“保存”。尝试打开桌面已有会话、发送一条消息，再在手机选择桌面工作区创建会话，确认桌面端可见。

## 6. 常驻与运维

确认前台连接可用后，停止两个前台进程，运行 `python3 scripts/service.py install`。服务名、移除方法及路径说明见根目录 README。脚本不会开启 Mac 唤醒、远程登录或修改 DSH 本身。

- 手机 token 到期：在 Cloudflare 续期或轮换，更新手机设置；不同设备用不同 token。
- 手机丢失：撤销对应 Service Token。已建立的 WebSocket 连接不会靠客户端重新发送 token 来自动完成撤销，必要时重启桥接以断开已有连接。
- Tunnel token 泄漏：按 Cloudflare 文档轮换并更新私有 `tunnel.token`，重启 tunnel；不要只改手机 Secret。
- 变更 Access 应用：对应 AUD 可能改变，更新 `bridge.env` 后重启 bridge。
- 公网域名应保持“不缓存会话 API”的配置，不给该域名设置 Cache Everything；桥接也会返回 `Cache-Control: no-store`。

## 故障排查

| 现象 | 优先检查 |
| --- | --- |
| 401 / 403 | Service Token 是否过期、是否包含在 Service Auth 策略中；Team Domain 和 AUD 是否对应同一个 Access 应用 |
| 302 或登录 HTML | 策略是否误用 Allow；应用的 hostname/path 是否覆盖请求；不要让客户端跟随登录跳转 |
| 502 / 503 | DSH 是否运行、doctor 是否成功、bridge 是否监听正确端口、Tunnel service URL 是否指向 bridge |
| Tunnel offline / 1033 | cloudflared 是否运行、token 是否正确、Mac 出站网络是否受限 |
| HTTP 成功但 WS 失败 | `/api/remote.mux` 是否受同一 Access 保护、是否额外设置了路径规则或 WAF 阻断 |
| 推送失败 | 这是独立的可选 APNs 功能，见 `push.md`；不影响聊天连接 |
| DSH 更新后解析失败 | 内部 RPC/认证格式可能改变；不要上传 `.credentials.yaml`，只提供脱敏错误和版本 |
| 3079 被占用 | 先检查现有桥接实例；不要杀死未知进程。改用自己的端口时同步修改 Tunnel route |

## AI 使用 Cloudflare API 的约定

可使用 Cloudflare 官方 API代替控制台，但必须先确认账户、Zone 与目标域名，读取现有资源避免覆盖他人服务。使用限定账户/Zone 的 API Token，权限按实际操作授予：Tunnel 编辑、Access 应用与策略编辑、Service Token 编辑，以及该 Zone 的 DNS 编辑。界面权限名称可能变化，以对应接口的 Accepted Permissions 为准。

API Token 保存在仓库外的权限 `0600` 文件，由程序读入 `Authorization` 请求头；不要出现在 shell 参数、源码、输出或 Git 中。Service Token 创建响应中的 Secret 只写入私有配置文件；Tunnel token 同样只写入私有文件。资源 ID、配置和回滚清单也放私有目录。

推荐顺序：查明账户/域名 → 新建特定 Service Token → 创建全域名 Access 应用与 Service Auth 策略 → 创建 Tunnel 与 ingress → 配置 DNS → 写 Mac 私有配置 → 验证 HTTP/WS。失败时记录已创建资源的 ID，停止扩大更改；不要为了“修复”而删除无关资源。

参考：[创建 Tunnel API](https://developers.cloudflare.com/api/resources/zero_trust/subresources/tunnels/subresources/cloudflared/methods/create/)、[创建 Service Token API](https://developers.cloudflare.com/api/resources/zero_trust/subresources/access/subresources/service_tokens/methods/create/)。
