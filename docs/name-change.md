# dsh link 改名记录

2026-10-24，构建 1.0 (7)。

- GitHub 仓库改为 `msly5/dsh-link`，保持私有；README、AI 配置说明、Cloudflare 示例名称及 Mac 扫码窗口同步更新。
- App 桌面显示名称、首页、侧栏、连接设置页脚、扫码提示统一为 dsh link；黑色鲸鱼图标保持不变。
- 保留已有 Bundle ID、Keychain service、缓存目录、`dshremote://` 协议及 Mac 私有配置目录，更新时继续使用已有凭证和会话数据。
- iPhone 13 Pro / iOS 27.0.1 真机上的独立 Debug 预览：已检查首页、侧栏、聊天和设置页脚；使用虚构数据，不读写真实连接配置。当前 README 截图来自此次验证。
- Swift 核心测试 68 项、Mac 桥接测试 7 项、Python 脚本测试 4 项通过；签名 Debug 构建、Release 归档和导出通过。

`DSHRemote` 工程 / 模块等内部名称和历史验证记录保留原有标识。用户自己命名的真实工作区、会话标题也保持原样。
