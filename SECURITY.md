# 安全说明

## 信任边界

dsh remote 面向同一用户的可信手机与 Mac。已授权客户端能够使用 DSH 远程接口，可能执行命令或访问 Mac 文件；它不是按用户隔离的公共代理。不要把一个实例的 Service Token 发给不信任的人。

Cloudflare Tunnel 将连接带到 Mac，不独立承担用户鉴权。需要整个主机名的 Access Service Auth 策略；bridge 同时对 HTTP 和 WebSocket 验证 Cloudflare JWT 的签名、issuer、audience、有效期。bridge 固定监听 loopback，不能直接暴露到公网或局域网。公钥验证不是防御本机已被攻陷的边界：同一 Mac 用户本来就能读取 DSH 本地凭证。

JWT 有效期内的重放和已建立的长连接属于需要管理的风险。撤销手机 Service Token 后，新认证请求会由 Access 拒绝；必要时重启 bridge 断开已有连接。不要在不可信机器上运行 bridge。

## 凭证与数据

| 类型 | 保存位置 | 用途 |
| --- | --- | --- |
| Service Token Client ID / Secret | 手机 Keychain；可选 Mac 私有 `client.json` 仅用于探测 | iPhone → Access |
| Tunnel Token | 仓库外 `tunnel.token` | cloudflared → Cloudflare |
| Cloudflare API Token | 用户自己的安全存储 | 管理云资源；不是运行时手机凭证 |
| DSH 浏览器会话密钥 | DSH 自己的 `.credentials.yaml`，只在内存读取 | bridge → DSH |
| APNs 私钥 | 仓库外 `.p8` 文件，默认不配置 | bridge → Apple Push |
| APNs device token | 仓库外 `device.json` | 单设备通知目标 |

手机连接配置作为一个原子 Keychain 条目存储，使用 `AfterFirstUnlockThisDeviceOnly`，不同步到 iCloud Keychain，不通过设备备份迁移。凭证与精确服务器 URL 绑定；远程传输使用 HTTPS/WSS，客户端不自动跟随重定向，不保存网络 Cookie/URL 缓存。测试连接使用草稿，不会更改保存的连接。

本地会话与图片缓存包含用户内容，位于 App 沙盒；清除连接不等于清除所有会话缓存。不要导出整个 App 容器或把真实聊天截图用于公开演示。代理不记录 RPC 正文、Access 头、DSH Cookie 或图片；诊断工具只打印成功/失败。

桥接会把 Cloudflare 认证头从转发请求中剥离，只向 DSH 注入自身生成的本地认证 Cookie；上游 Set-Cookie 不返回手机。错误信息保持通用，避免将本地文件内容或内部异常作为响应输出。

## 发布检查

- 新仓库必须从源码白名单整理，不能继承含旧 Secrets.swift 的历史。
- 不提交 `.env`、私钥、Tunnel token、签名资料、设备 token、日志、旧安全报告和含真实会话/账户的截图。
- `python3 scripts/check-secrets.py` 检查当前文件；暂存后再运行 `python3 scripts/check-secrets.py --staged`。
- 扫描只是防误提交措施，不能保证发现所有格式的秘密。检查暂存文件清单和二进制资源；公开后若发现泄漏，**先撤销/轮换凭证，再处理 Git 历史**。
- 此仓库不分发已签名 IPA，也不包含任何能连接作者服务器的默认配置。

## 漏洞报告

不要在公开 issue 中粘贴可用凭证、会话内容或密钥。请先撤销可能泄漏的 token；使用仓库维护者提供的私密渠道（若 GitHub 启用了 Private vulnerability reporting，可使用该入口）报告最小复现、受影响版本和脱敏日志。当前未提供独立安全邮箱，不要自行将报告发给无关的 DSH 官方渠道。
