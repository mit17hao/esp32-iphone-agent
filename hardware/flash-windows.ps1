#!/usr/bin/env pwsh
# Windows 版刷机脚本(等价 hardware/flash.sh),按 ESP32-S3-DevKitC-1 N16R8 定制:
#   16MB flash + 8MB octal PSRAM  ->  FlashSize=16M, PSRAM=opi, PartitionScheme=app3M_fat9M_16MB (3.3.12 无 default_16MB 档位)
# 建议用板子的 UART 口刷机(板载 USB-UART 桥自动进 boot);运行时与 iPhone 通信必须用 USB 原生口。
#
# Usage: powershell -ExecutionPolicy Bypass -File flash-windows.ps1 [-Port COM5] [-DebugSerial] [-Sta] [-BuildOnly] [-ApTune] [-Fqbn <str>]
#   -DebugSerial  USB 串口输出命令与 AirPlay 握手日志
#   -Sta          测试构建:连 secrets.h 里的 Wi-Fi,而不是开热点
#   -BuildOnly    只编译(输出 flash/RAM 占用)
#   -ApTune       A/B 构建参数:热点 20 MHz 信道 + 300 TU beacon(给 BLE 腾空口)
param(
  [string]$Port = "",
  [switch]$DebugSerial,
  [switch]$Sta,
  [switch]$BuildOnly,
  [switch]$ApTune,
  [string]$Fqbn = ""
)
$ErrorActionPreference = "Stop"
$hwDir = $PSScriptRoot
Set-Location $hwDir

if ($PSScriptRoot -match " ") {
  throw "路径不能含空格(固件强制 -include 限制): $PSScriptRoot"
}

# 引导 arduino-cli:先找 PATH,再到 winget Links 与 MSI 安装目录找
$cli = (Get-Command arduino-cli -ErrorAction SilentlyContinue).Source
if (-not $cli) { $cli = "$env:LOCALAPPDATA\Microsoft\WinGet\Links\arduino-cli.exe" }
if (-not $cli -or -not (Test-Path $cli)) { $cli = "C:\Program Files\Arduino CLI\arduino-cli.exe" }
if (-not (Test-Path $cli)) { throw "找不到 arduino-cli(winget install -e --id ArduinoSA.CLI)" }
Write-Host "arduino-cli: $cli"

# DevKitC-1 N16R8 默认 FQBN(XIAO 用法见 README 的 FlashSize=8M/default_8MB;3.3.12 无 default_16MB档位,取 app3M_fat9M_16MB)
if (-not $Fqbn) { $Fqbn = "esp32:esp32:esp32s3:USBMode=default,CDCOnBoot=cdc,FlashSize=16M,PSRAM=opi,PartitionScheme=app3M_fat9M_16MB" }
Write-Host "FQBN:        $Fqbn"

$defs = @()
if ($DebugSerial) { $defs += "-DDEBUG_SERIAL=1" }
if ($ApTune)      { $defs += "-DAP_TUNE=1" }
if ($Sta) {
  if (-not (Test-Path "hid_bridge\secrets.h")) { throw "--Sta 需要 hidBridge\secrets.h(参考 secrets.example.h)" }
  $defs += "-DSTA_FROM_SECRETS=1"
}
# 强制 include NimBLE 缓冲区配置(对应 flash.sh 的 -include 参数;必须是绝对路径,正斜杠)
$inc = (Join-Path $hwDir "hid_bridge\nimble_cfg.h").Replace("\", "/")
$extra = (($defs -join " ") + " -include $inc").Trim()
$props = @(
  "--build-property", "compiler.cpp.extra_flags=$extra",
  "--build-property", "compiler.c.extra_flags=$extra"
)

Write-Host "编译中..."
& $cli compile -b $Fqbn @props --output-dir build hid_bridge
if ($LASTEXITCODE -ne 0) { throw "编译失败(exit $LASTEXITCODE)" }
if ($BuildOnly) { exit 0 }

# 选串口:未指定则枚举 COM,唯一可用才自动选,多个请用 -Port 指定
if (-not $Port) {
  $ports = [System.IO.Ports.SerialPort]::GetPortNames()
  if ($ports.Count -eq 0) { throw "没有检测到 COM 串口:插上 DevKitC-1(UART 口)后重试;设备管理器看端口号" }
  if ($ports.Count -gt 1) { throw ("多个串口: " + ($ports -join ", ") + "  ->  用 -Port COMx 指定") }
  $Port = $ports[0]
}
Write-Host "串口:        $Port"

Write-Host "烧录中... (若卡在 Connecting,按住 BOOT 键再点一下 RST 后重试)"
& $cli upload -b $Fqbn -p $Port --input-dir build hid_bridge
if ($LASTEXITCODE -ne 0) { throw "烧录失败(exit $LASTEXITCODE)" }
Write-Host "完成。运行时请把板子 USB 口接 iPhone。"
