# 可选：审批与提问推送（APNs）

聊天、图片、会话同步不依赖 APNs，仓库默认关闭推送。推送需要你自己的 Apple 开发者 Team、App ID、推送签名配置和 APNs Auth Key；普通个人自用安装可先跳过。

## iOS

1. 在 Apple Developer 中为你自己的唯一 Bundle ID 启用 Push Notifications，更新对应 provisioning profile。
2. `config/Local.xcconfig` 的 `PRODUCT_BUNDLE_IDENTIFIER` 需与该 App ID 一致；设置：

```xcconfig
CODE_SIGN_ENTITLEMENTS = config/Push.entitlements
DSH_ENABLE_PUSH = YES
```

3. 检查最终签名 App 的 `aps-environment`。仓库的 entitlements 示例是 `development`；使用归档/分发配置时，以最终签名结果为准，服务端的 `APNS_ENV` 必须与它匹配。
4. 重新签名安装，在 App 连接设置里开启“审批与提问通知”，保存并允许系统通知。注册令牌只发往当前已保存的服务器。

## Mac

创建 APNs Auth Key，将 `.p8` 文件保存在仓库外，目录 `0700`、文件 `0600`。在私有 `bridge.env` 设置：

```dotenv
APNS_ENABLED=1
APNS_KEY_ID=YOUR_KEY_ID
APNS_TEAM_ID=YOUR_TEAM_ID
APNS_TOPIC=com.example.yourname.dshremote
APNS_KEY_FILE=/absolute/private/path/to/apns.p8
APNS_ENV=development
```

使用绝对路径，env 文件中的 `~` 和 `$HOME` 不会自动展开。发布环境设置 `APNS_ENV=production`；不能随意混用 sandbox 与 production token。

重启 bridge，手机在对应服务器保存连接后重新开启通知。bridge 在 `device.json` 记录最新注册的设备（单设备设计，新注册会替换旧设备），文件不会进入仓库。监听 DSH 的审批/提问事件后向 APNs 发送通用提示，不包含问题、命令或会话正文。Mac 与 bridge 停止时无法推送，手机仍需连回 Mac 才能处理请求。

## 检查

- 手机系统通知权限是否打开，签名是否包含 Push entitlement。
- APNS_TOPIC 是否等于手机的 Bundle ID；Team / Key ID 是否与 `.p8` 一致。
- `APNS_ENV` 是否匹配最终签名环境。
- 认证请求 `/push/status` 是否显示 `enabled: true`；它不代表 APNs 已成功送达。
- 触发一次你自己的真实审批或提问，锁屏确认通知抵达并能进入对应会话。未经此步骤不能宣称推送端到端验证成功。

APNs 私钥、签名证书、provisioning profile、设备 token 和真实通知截图均不可提交 Git。
