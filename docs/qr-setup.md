# 扫码连接

Mac 桥接保持原来的 Access / JWT 鉴权方式。二维码只是本地导入连接信息，不会新增公网配对接口、放宽 Access 策略或修改 DSH 桌面程序。

## 显示二维码

仓库根目录执行：

```bash
python3 scripts/store-secret.py client  # 已有私有 client.json 时跳过
npm run pair --prefix bridge
```

默认读取 `~/.config/dsh-remote/client.json`，也可用绝对路径环境变量 `DSH_REMOTE_CONFIG_DIR` 指定其他仓库外的私有目录。目录需为当前用户所有、权限 `0700`，文件需为当前用户所有、权限 `0600`。内容使用 `server_url`、`client_id`、`client_secret` 三个字段；不要把真实内容写进仓库、命令参数或聊天。

首次运行会用 Xcode 命令行工具编译本机原生窗口，后续复用私有目录下的缓存程序。Core Image 在内存生成二维码，通过标准输入把配置交给窗口程序；凭证不写到应用缓存、网页、命令参数或日志。窗口显示服务器地址，5 分钟后自动关闭。

## iPhone 扫码

打开 **连接设置 → 扫描 Mac 连接二维码**，首次允许相机权限，对准 Mac 上的二维码。也可以用系统相机识别链接并打开 dsh link。App 自动填入服务器、Client ID 和 Client Secret，先确认服务器，再点“保存”。如已有配置，扫描本身不会覆盖钥匙串；取消即可保留原配置。

相机权限被拒绝或设备不支持 App 内识别时，可以使用系统相机或手动填写。App 拒绝错误格式、其他应用的二维码、HTTP 服务器、带用户信息的 URL、重复参数、超长数据，以及过期或不支持的协议版本。

二维码内包含完整 Service Token，等同凭证，只用于可信设备之间。不要截图、分享或提交到 Git。5 分钟过期限制的是此 App 的导入流程，不会让 Cloudflare Token 本身失效；泄漏后需在 Cloudflare 撤销该 Token。

## 验证

```bash
npm run pair --prefix bridge -- --check
swift test
npm test --prefix bridge
```

`--check` 在本机生成并用 Apple Vision 回读二维码，核对完整数据，不显示或输出二维码和凭证。Swift 与 Node 测试共享虚构的协议样例，覆盖正常导入、过期、错误版本、URL / 头字段注入和私有文件权限。

2026-10-23 在 iPhone 13 Pro 实测：欢迎页黑色鲸鱼、配置链接冷启动自动填入、过期链接拒绝、相机权限与扫码取景器启动；使用虚构凭证，没有保存覆盖真实配置。Mac 原生窗口和二维码生成 / 回读已验证。手机实际对准 Mac 屏幕的光学扫描及保存新真实连接，仍需使用者完成；上述测试不代表已经验证这两步。
