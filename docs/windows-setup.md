# Windows 端部署手册(ESP32-S3-DevKitC-1 N16R8)

零 Mac、零 WSL 的完整路线:Windows 原生刷固件 + GitHub Actions 云 Mac 构建 App + Windows 侧载。
适用:Windows 10 22H2+(本手册在 22H2 验证)、iPhone iOS 18+(带蜂窝数据)、DevKitC-1 **N16R8**(16MB flash + 8MB octal PSRAM)。

> 依赖版本(与 CI 一致):arduino-cli 1.5.x、esp32 core **3.3.12**、NimBLE-Arduino **2.5.1**。

## 1. 刷固件(Windows 原生)

```powershell
# 1) 安装 arduino-cli 与工具链(一次性)
winget install -e --id ArduinoSA.CLI
& "arduino-cli" core update-index --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
& "arduino-cli" core install esp32:esp32@3.3.12 --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
& "arduino-cli" lib install "NimBLE-Arduino@2.5.1"

# 2) 编译+烧录(UART 口插电脑)
powershell -ExecutionPolicy Bypass -File hardware\flash-windows.ps1 -Port COM5
# 只想看编译产物占用: 加 -BuildOnly
# 需要 USB 串口日志(命令与 AirPlay 握手): 加 -DebugSerial
```

要点与坑:
- **刷机用 UART 口**(板载 USB-UART 桥,自动进 boot);**运行时给 iPhone 必须用另一个"USB"口**(S3 原生 USB,HID 就出在这个口)。
- FQBN 已按 N16R8 定制:`FlashSize=16M, PSRAM=opi, PartitionScheme=app3M_fat9M_16MB`(固件 1.46MB,必须 3MB APP 分区;3.3.12 无 `default_16MB` 档位)。其他 SKU:N8R8 用 `FlashSize=8M/default_8MB`;N8R2 把 `PSRAM=opi` 改成 quad(`default`)——R2 只有 2MB PSRAM,固件按 8MB 调试,可能跑不动。
- **仓库路径不能含空格**(固件用 `-include` 绝对路径强制注入 NimBLE 配置,空格会被编译器拆参)。本仓库建议放 `D:\esp32-iphone-agent`。
- Windows PowerShell 5.x 需要脚本带 UTF-8 BOM(本仓库的 flash-windows.ps1 已带);执行策略用 `-ExecutionPolicy Bypass`。
- 烧录时若一直卡 Connecting:按住 **BOOT** 再点一下 **RST**(进 boot 模式)后重试。
- 国内网络下 GitHub Releases 大文件常超时:重跑即可(断点续传);或把 zip 手动放进
  `%LOCALAPPDATA%\Arduino15\staging\packages\`,arduino-cli 安装时会校验官方索引里的 sha256,合法缓存直接跳过下载。

## 2. 构建 App(零 Mac)

推送本仓库到你的 GitHub **公开**仓库后,`.github/workflows/build-ipa.yml` 会自动跑(也可手动触发):
macos-26 runner 上无签名构建真机版并打出 `IPhoneAgent-unsigned.ipa` Artifact。

- 公开仓库的 Actions 免费额度足够;
- workflow 里 bundle id 默认 `com.<你的GitHub用户名>.esp32agent`,想改就改那行 printf;
- 免费账号不配 Hotspot 能力(`IA_ENTITLEMENTS` 留空),App 首次设置时会显示热点密码让你手动加入。
- 若要正式签名(付费开发者账号),在 `ios/Config/Local.xcconfig` 填 `DEVELOPMENT_TEAM` 并自建签名 workflow,以后每 7 天无需重签。

## 3. 侧载到 iPhone(Windows)

驱动准备:微软商店装 **Apple Devices**(或 iTunes 旧版),提供 Apple Mobile Device Service。

- **SideStore(推荐)**:官网下载安装器,用你的 Apple ID 装 SideStore 后,在 SideStore 里导入 ipa 并签名安装。之后**设备端自动 7 天续签,完全不再依赖电脑**。免费账号限制:每 7 天最多 3 个自签应用。
- **Sideloadly / AltServer**:Windows 图形化签名侧载,重签需要手机连电脑。
- 爱思助手等第三方也能签,但闭源,自担风险。

## 4. 首次设置与运行

1. 板子 **USB 口**(不是 UART 口)接 iPhone(Lightning 机型需要相机转换器;板子由手机供电)。
2. 打开 ESP32 Agent App,四步引导:蓝牙配对 → 加入热点 + 屏幕镜像选 *ESP32 Agent* → 辅助触控指针自动校准 → 填模型 API(存钥匙串)。
3. 注意:运行时手机 Wi-Fi 被**板子热点**占用,模型请求走**蜂窝数据**——确认你的 API 域名在蜂窝下可达;手机锁屏会停止镜像。
4. 任务下达后可回灵动岛/快捷指令/ Siri 触发,见 README。

## 5. 故障排查速查

| 现象 | 处理 |
|---|---|
| 设备管理器 UART 口带感叹号 | 装 Silicon Labs CP210x 驱动 |
| 编译报 `-include` 路径错 | 检查路径是否含空格 |
| 编译内存不足报错 | 确认 FQBN 的 PSRAM 档位与实际板子一致(opi=8MB octal) |
| App 找不到板子热点 | 板子插手机 USB 口后才开热点;或手动输入ssid/密码 |
| 镜像画面卡住 | BLE 300-500 kbps 是设计上限;靠近板子/避开 2.4G 干扰 |
| 免费签名 7 天失效 | SideStore 自动续签;或连电脑重签 |
