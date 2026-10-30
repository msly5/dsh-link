# 安装包与发布 / Packages and releases

[GitHub Releases](https://github.com/msly5/dsh-link/releases) 提供源码、Android APK 和 iOS IPA。安装后仍需配置自己的电脑桥接；安装包没有任何个人服务器凭证。

`v1.0.2` 加入 DSH 原生斜杠指令：`/compact` 等指令交给电脑执行，并显示执行记录；未知指令不会再发给模型。iOS 为 1.0 (10)，Android 为 1.0.1 (2)。

| 文件 / 入口 | 使用方式 |
| --- | --- |
| `dsh-link-android-1.0.1.apk` | 已签名的 Android Release 包，Android 8.0+ 可安装 |
| [iOS / iPadOS TestFlight](https://testflight.apple.com/join/KqMhXcHS) | 推荐普通用户安装；不需要自行签名，测试名额和构建有效期由 Apple 管理 |
| `dsh-link-ios-1.0-build10.ipa` | iOS 1.0 (10) 的 App Store Connect 导出包。**不能直接下载后安装到任意 iPhone**；需要 Apple 分发流程，或具备条件者用自己的签名重新签署后安装 |
| Source code | 自己构建和签名，配置自己的桥接 |

IPA 和 APK 的安装机制不同。GitHub 提供 IPA 下载不会绕过 Apple 签名、设备授权或 App Store / TestFlight 的分发要求；不要承诺“任何 iPhone 直接装 IPA”。若需要 Xcode 安装，用自己的 Apple Team 和 Bundle ID 构建源码。Apple 官方：[分发到已注册设备](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)。

首个跨平台 Release（`v1.0.0`）包含 iOS 1.0 (8) 与 Android 1.0.0 (1)，两者版本号独立。该版本新增 Windows 桥接，当时复用了已有 iOS build 8；`v1.0.1` 则提供修复后的 iOS build 9。

## English

[Releases](https://github.com/msly5/dsh-link/releases) contain source, a signed Android APK, and an iOS IPA. No personal connection credentials are bundled. Configure your own Mac or Windows bridge after installation.

`v1.0.2` adds native slash commands: `/compact` and other registered commands execute on the desktop and appear in execution history. Unknown commands are never sent to the model. iOS is 1.0 (10), and Android is 1.0.1 (2).

- **Android APK:** install on Android 8.0+; future updates retain the release signing identity.
- **iPhone/iPad:** [TestFlight](https://testflight.apple.com/join/KqMhXcHS) is the recommended installation path.
- **IPA:** `dsh-link-ios-1.0-build10.ipa`, the App Store Connect export for iOS 1.0 (10). It is **not an unrestricted sideload installer**. Installation requires the appropriate Apple distribution process or re-signing with your own eligible credentials. GitHub downloads do not bypass Apple signing/device restrictions.
- **Source:** build with your own Apple Team/Bundle ID or Android signing key.

The first cross-platform Release (`v1.0.0`) combined iOS 1.0 (8), Android 1.0.0 (1), and the Windows-capable bridge, reusing the existing iOS build. `v1.0.1` provides the fixed iOS build 9.
