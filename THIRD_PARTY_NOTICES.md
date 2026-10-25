# 第三方说明

本项目是社区独立开发的非官方客户端，与 DeepSeek 无隶属或赞助关系。DeepSeek、DSH 及其商标和桌面软件归其各自权利人所有，不属于本仓库 MIT 许可范围。

仓库包含自行编写的 iOS / Android 客户端和 Mac / Windows 桥接代码，不分发 DSH 桌面程序、app.asar、DSH 依赖包或登录凭证。用户需要自行安装并登录桌面软件，遵守其适用条款。

当前版本按用户要求使用取自本机 DeepSeek Harness 的黑色鲸鱼图标，文件见 `DSHRemote/Assets.xcassets/AppIcon.appiconset/AppIcon.png`。该图标及相关商标归原权利人所有，不属于本项目 MIT 许可范围；此处不授予其再分发或商标使用权。原自绘终端图标保留在 `docs/icon.svg`。

桥接通过 npm 安装以下依赖（精确版本及完整依赖关系见 `bridge/package-lock.json`）：

| 依赖 | 用途 | 许可证 | 源码 |
| --- | --- | --- | --- |
| jose | Cloudflare Access JWT 验签 | MIT | https://github.com/panva/jose |
| ws | WebSocket 推送监听及诊断 | MIT | https://github.com/websockets/ws |
| qrcode | Windows 本地二维码生成 | MIT | https://github.com/soldair/node-qrcode |
| yaml | 读取本机 DSH 凭证结构 | ISC | https://github.com/eemeli/yaml |

依赖的许可证随 npm 包提供；分发包含依赖的制品时需保留其相应声明。iOS 客户端没有第三方 Swift 包依赖。

Android 使用 Kotlin、AndroidX / Jetpack Compose、OkHttp、ZXing Android Embedded 与 commonmark-java（及表格扩展），主要以 Apache-2.0 / BSD 许可证分发。完整版本见 `android/app/build.gradle.kts`；安装包保留依赖附带的 NOTICE / LICENSE 资源。Android 图标复用上述鲸鱼资源，同样不属于 MIT 许可范围。

- Kotlin: https://github.com/JetBrains/kotlin (Apache-2.0)
- AndroidX: https://android.googlesource.com/platform/frameworks/support (Apache-2.0)
- OkHttp: https://github.com/square/okhttp (Apache-2.0)
- ZXing Android Embedded: https://github.com/journeyapps/zxing-android-embedded (Apache-2.0)
- commonmark-java: https://github.com/commonmark/commonmark-java (BSD-2-Clause)
