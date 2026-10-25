# 安装包与发布 / Packages and releases

[GitHub Releases](https://github.com/msly5/dsh-link/releases) 提供源码、Android APK 和 iOS IPA。安装后仍需配置自己的电脑桥接；安装包没有任何个人服务器凭证。

| 文件 / 入口 | 使用方式 |
| --- | --- |
| `dsh-link-android-1.0.0.apk` | 已签名的 Android Release 包，Android 8.0+ 可安装 |
| [iOS / iPadOS TestFlight](https://testflight.apple.com/join/KqMhXcHS) | 推荐普通用户安装；不需要自行签名，测试名额和构建有效期由 Apple 管理 |
| `dsh-link-ios-1.0-build8.ipa` | 对应已上传 TestFlight 的 App Store Connect 导出包。**不能直接下载后安装到任意 iPhone**；需要 Apple 分发流程，或具备条件者用自己的签名重新签署后安装 |
| Source code | 自己构建和签名，配置自己的桥接 |

IPA 和 APK 的安装机制不同。GitHub 提供 IPA 下载不会绕过 Apple 签名、设备授权或 App Store / TestFlight 的分发要求；不要承诺“任何 iPhone 直接装 IPA”。若需要 Xcode 安装，用自己的 Apple Team 和 Bundle ID 构建源码。Apple 官方：[分发到已注册设备](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)。

首个跨平台 Release 包含 iOS 1.0 (8) 与 Android 1.0.0 (1)，两者版本号独立。桥接源码增加 Windows 支持；iOS 包复用已通过外部测试审核的 build 8，不代表又提交了一个新的 Apple 构建。

## English

[Releases](https://github.com/msly5/dsh-link/releases) contain source, a signed Android APK, and an iOS IPA. No personal connection credentials are bundled. Configure your own Mac or Windows bridge after installation.

- **Android APK:** install on Android 8.0+; future updates retain the release signing identity.
- **iPhone/iPad:** [TestFlight](https://testflight.apple.com/join/KqMhXcHS) is the recommended installation path.
- **IPA:** the App Store Connect export for iOS 1.0 (8), already distributed through TestFlight. It is **not an unrestricted sideload installer**. Installation requires the appropriate Apple distribution process or re-signing with your own eligible credentials. GitHub downloads do not bypass Apple signing/device restrictions.
- **Source:** build with your own Apple Team/Bundle ID or Android signing key.

The first cross-platform Release combines iOS 1.0 (8), Android 1.0.0 (1), and the Windows-capable bridge. The iOS artifact reuses the existing approved build; this release does not imply a new App Store Connect upload.
