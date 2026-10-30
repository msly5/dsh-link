# Android 客户端 / Android client

[简体中文 README](../README.md) · [English README](../README.en.md)

## 安装与连接

1. 从 [GitHub Releases](https://github.com/msly5/dsh-link/releases/latest) 下载 `dsh-link-android-1.0.1.apk`。支持 Android 8.0+（API 26）。这是签名的 Release 包，不需要 Android Studio。
2. 打开 APK，按系统提示仅为当前浏览器或文件管理器允许安装；安装完成后可关闭该权限。后续版本用同一签名覆盖安装。
3. 在 Mac 或 Windows 配好桥接。长期使用推荐**域名 + Cloudflare Tunnel + Access**；无域名可用 Quick Tunnel。
4. 手机进入「连接设置」，扫描电脑二维码或手动填写。Access 填 HTTPS 地址、Client ID、Client Secret；Quick Tunnel 填临时 HTTPS 地址、连接密钥。
5. 点「测试连接」，成功后点「保存」。测试本身不会保存；更换地址会清除旧地址的凭证。二维码会在 5 分钟后失效，仅限制新导入，不撤销已经保存的连接。

Android 使用同一个 `dshremote://configure` 配置协议。凭证通过 Android Keystore 生成的 AES-GCM 密钥加密保存，不进入云备份。应用内无内置服务器和密钥。

## 首版功能

- 简洁浅色 / 深色界面，宽屏侧栏与聊天双栏。
- 桌面工作区分组、已有会话、新建会话、归档与恢复。
- WebSocket 流式回复、断线重连、历史分页、按当前连接与会话隔离的内存缓存及草稿。
- 图片选择、压缩、发送和点按加载历史附件。
- Markdown、可横向滚动的完整表格、折叠执行过程。
- 模型 / 推理强度 / 权限选择、工具审批、问题回答。

**边界：** 首版暂无 Android 系统推送通知；进程退出后会话历史需从电脑重新读取，不提供离线磁盘会话缓存。系统后台可能暂停连接，返回前台会重连。桌面必须保持开机、联网且 DSH 在运行。

## 从源码构建

Android Studio 或 JDK 17、Android SDK 35（Build Tools 35.0.0）。仓库包含 Gradle Wrapper，依赖从 Google Maven / Maven Central 下载。

```bash
cd android
# macOS / Linux
./gradlew :app:testDebugUnitTest :app:assembleDebug
# Windows PowerShell
.\gradlew.bat :app:testDebugUnitTest :app:assembleDebug
```

Debug 包位于 `app/build/outputs/apk/debug/app-debug.apk`，包名带 `.debug`，可与 Release 共存。Release 包名为 `com.duloveni.dshlink`。

```bash
./gradlew :app:assembleRelease
```

此命令只生成 unsigned APK。公开安装包由维护者使用独立 Android 发布签名签署；签名私钥和密码不在仓库、Gradle 配置或 CI 中。自行分发必须使用自己的长期签名，不能用 debug key 代替正式发布密钥。`scripts/sign-android.py` 提供 macOS Keychain 保存发布密钥的本地签名流程，详见脚本帮助。

## 开发验证

JVM 测试覆盖连接鉴权、重定向不携带凭证、配对版本与过期、内部上下文过滤和执行消息合并。设备测试覆盖 Keystore 保存、解密、清除。可用 `./gradlew :app:connectedDebugAndroidTest` 在自己的测试设备上运行。

虚构数据 UI 入口仅存在于 Debug 行为路径：先 `node android/tools/fixture.mjs`，再 `adb reverse tcp:38081 tcp:38081`，最后启动：

```bash
adb shell am start -n com.duloveni.dshlink.debug/com.duloveni.dshlink.MainActivity --ez fixture true
```

Release 不接受 fixture 配置，禁止明文 HTTP，且不会自动加载远程 Markdown 图片。

## English

Download the signed `dsh-link-android-1.0.1.apk` from [GitHub Releases](https://github.com/msly5/dsh-link/releases/latest) on Android 8.0+. Allow installation for the app opening the APK, install, and optionally revoke that permission afterward. Future releases use the same signing key.

Set up the bridge on **Mac or Windows**. A domain with Cloudflare Tunnel + Access is recommended for everyday use; Quick Tunnel is available without a domain. Open connection settings, scan the computer's QR code or enter the HTTPS server and Access Service Token / Quick Tunnel key, then test and save. Tests do not save credentials. Changing the server clears its old credentials. Pairing codes expire after five minutes; this limits importing only.

The Kotlin/Compose client includes light/dark themes, wide-screen navigation, desktop workspaces, chat creation, archive/restore, streaming and reconnection, paged history, image upload/viewing, Markdown tables, collapsed execution activity, model/effort/permission selection, approvals and question replies. Credentials are encrypted using Android Keystore; backups are disabled. No server or credentials are bundled.

The first version has **no Android push notifications and no offline disk conversation cache**. In-memory drafts/history are isolated per connection and session. After process termination, history reloads from the desktop. Background connections may pause and reconnect when foregrounded.

Build with JDK 17 and Android SDK 35 using the Gradle commands above. Debug uses a separate `.debug` application ID. `assembleRelease` creates an unsigned APK; distribution requires your own long-lived signing key. The maintainer's signing material is kept outside Git in macOS Keychain. Debug fixture mode uses synthetic data only and is disabled in Release.
