[English](README.md) | [简体中文](README.zh-CN.md) | [官网](https://frank-yf.github.io/auralim-site/)

# 晨昏 · Auralim

**日升而明，日落而暗**

*Between light and dark.*

晨昏是一款 Swift + SwiftUI 原生 macOS 菜单栏应用，根据当地日出、日落切换系统浅色与深色外观。日出日落和时区查询均在本地完成，不依赖在线 API 或 macOS 自动外观计划。

## 产品说明

### 功能

- **日出日落自动切换**：独立计算太阳事件，支持日出转亮、日落转暗。
- **独立时间偏移**：日出、日落分别支持 ±120 分钟，滑块与分钟输入框同步，显示偏移后的切换时间。
- **三种外观模式**：托盘和设置同步提供「浅色｜自动｜深色」，明确区分系统自动与应用自动。
- **旅行适配**：自动定位后按当前位置和当地时区计算；也可选择内置城市，刷新失败时沿用缓存位置，无有效缓存时使用备用手动城市。
- **唤醒恢复**：启动、唤醒、会话恢复和系统时间变化时重新检查外观与计划。
- **菜单栏常驻**：浅色显示暖金色太阳，深色显示淡蓝紫色月亮，始终跟随系统实际外观。没有 Dock 图标或 WebView，按事件与单次定时器调度，无后台持续轮询。
- **应用内更新**：通过 GitHub Releases 自动检查和下载更新，准备好后在设置底部点击「重启以更新」。
- **常用设置**：登录时启动、12 种界面语言切换，以及默认关闭的日月过渡动画。

### 语言

以英语为开发基准，设置中可选「跟随系统」及 12 种语言：英语（`en`）、简体中文（`zh-Hans`）、日语（`ja`）、繁体中文（`zh-Hant`）、德语（`de`）、法语（`fr`）、西班牙语（`es`）、葡萄牙语（巴西，`pt-BR`）、韩语（`ko`）、意大利语（`it`）、俄语（`ru`）、荷兰语（`nl`）。

切换后即时生效并保存在本机。「跟随系统」按 macOS 语言偏好顺序匹配，不支持时回退英语；中文优先匹配脚本，再匹配地区，葡萄牙语变体使用巴西版本。界面、帮助、城市名、日期格式、更新状态及系统权限说明统一使用本地化资源；系统权限弹窗的语言由 macOS 决定。

### 下载与安装

系统要求：**macOS 13 或更高版本**。发布包包含 Intel 与 Apple 芯片架构。

1. 从 [GitHub Releases](https://github.com/frank-yf/auralim-mac/releases) 下载 DMG 安装包，或使用 ZIP 解压包。
2. 将 `Auralim.app` 拖入「应用程序」，然后打开。应用入口位于菜单栏。
3. 点击菜单栏图标，再打开「设置…」。

v0.2.1 使用 ad-hoc 签名，未经 Apple 公证。首次打开可能被系统拦截；确认下载来源后，可按 [Apple 官方说明](https://support.apple.com/zh-cn/102445) 处理。下载校验文件随 Release 提供。

### 应用内更新

从 0.3 起，应用使用 Sparkle 2，默认每天检查并后台下载兼容的正式更新。设置底部显示检查、下载和校验状态；准备好后显示「重启以更新」，点击后安装并重新打开应用，不会强制中断使用。按 Sparkle 标准行为，正常退出应用时也允许安装已准备好的更新。设置底部保留「检查更新」，失败时可重试或打开 GitHub 发布页手动下载。

更新清单地址为 `https://github.com/frank-yf/auralim-mac/releases/latest/download/appcast.xml`；具体安装包使用不可变的 Release 标签地址。更新包和清单均使用 EdDSA 签名，应用在解压前校验；清单签名失败不会随时间自动放宽校验。更新请求连接 GitHub，不包含定位坐标；系统信息统计默认关闭。0.3 之前的版本需要先手动下载安装一次 0.3 或更高版本。

### 使用

在设置中选择「手动城市」或「自动定位」，再从托盘或设置中选择外观模式：

首次没有城市记录时，按系统时区匹配内置城市；同一时区有多个城市时取列表中的首项，匹配不到时使用上海。选择后保存，下次启动沿用。

| 模式 | 行为 |
| --- | --- |
| 浅色 | 立即切换为浅色，暂停应用自动计划 |
| 自动 | 按当地日出、日落及偏移切换外观 |
| 深色 | 立即切换为深色，暂停应用自动计划 |

未启用应用自动计划时，每次启动读取系统设置：系统固定浅色 / 深色对应高亮；系统自动时不高亮三段中的任意一项，并显示「系统自动」。用户启用应用的「自动」后，界面会明确显示「应用自动」。

使用应用自动计划时，建议关闭 macOS 系统设置中的自动外观，避免两套计划相互覆盖。首次实际切换外观需允许应用控制 System Events；自动定位需要位置权限。

#### 日出与日落偏移

两条滑块以中点为零，向两侧调整切换时刻：

| 事件 | 向左滑动 | 向右滑动 |
| --- | --- | --- |
| 日出 | 延后转亮，延长深色时段 | 提前转亮，提前进入浅色 |
| 日落 | 延后转暗，延长浅色时段 | 提前转暗，提前进入深色 |

输入框中，负数表示提前，正数表示延后，范围均为 −120～+120 分钟。松开滑块、输入后按回车或离开输入框时提交；「归零」恢复准时切换。设置显示偏移后的「日出转亮」「日落转暗」时间，日期与时间均按当前生效位置的时区显示。

自动计划在极昼保持浅色、极夜保持深色；偏移越过相邻昼夜边界时会裁剪或跳过对应时段，并在界面提示。计算不包含地形遮挡、海拔和实时天气修正。

#### 离线、隐私与退出

手动城市模式可完全离线使用。首次启用自动定位时，应用请求系统定位权限。自动定位使用 macOS 定位服务，可能需要 Wi-Fi 或网络；经纬度、对应时区和定位时间仅缓存在本机，不上传位置数据。应用每 3 小时单次刷新，不持续定位，也不提供刷新间隔设置。启动或唤醒时复用未过期缓存；用户主动刷新或系统时区变化时立即请求新位置。刷新失败时继续使用缓存位置，没有有效缓存时才使用已保存的手动城市。城市、偏移和语言等设置同样保存在本机。

关闭设置窗口后应用继续运行；从菜单栏选择「退出」会停止后续调度，并保留当前系统外观。「登录时启动」可在设置中开启。日月过渡动画默认关闭，开启后也会遵循系统「减少动态效果」设置。唤醒后立即校正外观；如果睡眠前后外观不同，等待桌面恢复或解锁后再播放一次动画。

## 开发指南

### 环境与构建

需要 macOS、Swift 6 工具链及 macOS SDK，可使用 Xcode 或 Command Line Tools。应用部署目标为 macOS 13，测试使用 Swift Testing。

```sh
git clone https://github.com/frank-yf/auralim-mac.git
cd auralim-mac
make help
make build
make run
```

构建前请退出运行中的应用。`make build` 生成并签名 `dist/Auralim.app`，默认只构建当前主机架构；`make run` 打开该应用包。应运行打包后的 `.app`，以便系统读取权限用途说明和资源。

修改图标原稿 `Resources/Icons/Auralim.png` 后，运行 `make icon`，通过 macOS 自带的 `sips` 和 `iconutil` 重新生成 `Resources/Auralim.icns`。该命令也会更新 `Sources/Auralim/Resources/AppIcon.png`，供设置和托盘面板共用 256 像素缩略图。原稿与生成的图标资源均纳入 Git，`make build` 将其打包到应用中。

运行 `make clean` 可删除 `dist/`、`artifacts/` 内生成的 `.app` 副本，包括发布暂存和验证解压副本；保留源码、DMG / ZIP 安装包、构建缓存与其他验证文件。

默认使用 ad-hoc 签名。指定 Developer ID 身份可使用：

```sh
AURALIM_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" make build
```

正式分发还需完成 Apple 公证。通用包需要分别编译 Intel 与 Apple 芯片版本，合并后重新签名。构建产物、缓存和验证输出分别位于 `dist/`、`.build/`、`artifacts/`，均不纳入 Git。

### 准备 GitHub 更新发布

```sh
AURALIM_UNIVERSAL=1 make build
make prepare-update
```

该流程生成 `dist/updates/<版本>/` 下的通用 ZIP、签名 `appcast.xml` 和 `SHA256SUMS.txt`。将三个文件一起上传到 GitHub Release `v<版本>`，并将该正式 Release 设为 Latest。清单或安装包缺失会导致客户端检查/下载失败；不能只上传 DMG。脚本不会创建或发布 GitHub Release，也不会覆盖已生成的同版本文件。

更新签名私钥保存在 macOS 登录钥匙串的 Sparkle 账户 `app.duskshift.mac`，公钥随应用分发，私钥不进入源码或发布包。迁移发布机器前使用 Sparkle `generate_keys` 工具安全备份/导入该账户密钥；新机器不能生成另一个密钥替代，否则现有用户将拒绝更新。生成脚本会检查公私钥是否匹配，并验证更新包与清单的签名。

默认 ad-hoc 本地构建保留上游 Sparkle 框架签名，并只对 ad-hoc 主程序关闭库验证，以便加载不同签名身份的框架。指定 `AURALIM_SIGN_IDENTITY` 后使用 Developer ID 从内向外重签框架和安装助手，并保持库验证；正式分发仍需 Apple 公证。应用 bundle ID 保持不变以沿用偏好，真实系统权限连续性需要用正式签名链验收。

### 项目结构

```text
Sources/Auralim/       菜单栏、设置、本地化、系统外观与定位服务
Sources/AuralimCore/   天文计算、偏移、调度与离线时区查询
Sources/CZoneDetect/   时区边界数据解析器
Resources/            应用元数据、本地化显示名与签名权限
Tests/                核心逻辑和原生界面测试
scripts/              构建、测试与实机验证工具
Makefile              开发命令入口
```

天文计算采用 Meeus / NOAA 太阳坐标方程与标准视地平线 `−0.833°`，在当地日期区间计算日出、日落。调度通过单次定时器和系统事件触发重算，外观请求串行执行；位置服务仅使用单次请求和周期性单次定时器，不启用持续定位或位置变化监听；临时失败在一次请求内有限重试，总时限为 30 秒。

### 按变更范围测试

每次修改仅运行受影响的测试。普通测试必须指定 `FILTER`，未指定时不会执行：

```sh
make test FILTER=SolarTests
make test FILTER=LocalizationTests
```

| 命令 | 验证范围 |
| --- | --- |
| `make test-updates` | 更新状态、点击安装与多语文案 |
| `make test-update-ui` | 底部更新控件原生点击与三语深浅截图 |
| `make test-update-install` | 隔离应用的真实后台下载、安装和重启 |
| `make test-update-quit` | 隔离应用正常退出时安装且不重启 |
| `make test-update-signature` | 篡改签名清单被拒绝且不安装 |
| `make test-sliders` | 滑块渐变渲染 |
| `make test-ui` | 滑块与输入框交互、同步和时间显示 |
| `make test-localization-ui` | 十二语原生选择、偏好持久化、设置和菜单同步、深浅截图 |
| `make test-ui-layout` | 设置与菜单栏布局、语言、深浅外观和滚动 |
| `make test-appearance-mode` | 外观模式、系统状态读取与请求协调 |
| `make test-ui-mode` | 托盘与设置的模式切换和同步 |
| `make test-transitions` | 动画触发、系统结果与请求协调 |
| `make test-ui-transitions` | 半屏日月过渡、动画开关与资源释放 |

原生界面测试需要 macOS 登录会话、辅助功能和屏幕录制权限，使用临时偏好与替身系统服务。真实外观授权、睡眠唤醒、登录启动、定位权限和跨时区旅行需另行实机验收。

部分 Command Line Tools 自带的 Swift Testing 框架要求 macOS 14+ 才能运行测试；这不改变应用的 macOS 13 部署目标。具体架构与系统版本的实机验证范围见对应 Release。

## 许可与数据来源

项目采用 [MIT License](LICENSE)。第三方组件与数据保留各自许可：

- [ZoneDetect](https://github.com/BertoldVdb/ZoneDetect)：BSD-3-Clause，许可见 [ZoneDetect-LICENSE.txt](Sources/AuralimCore/Resources/ZoneDetect-LICENSE.txt)。
- 时区边界数据包含 [timezone-boundary-builder](https://github.com/evansiroky/timezone-boundary-builder) 的信息，以 ODbL 1.0 提供，许可见 [TimezoneData-LICENSE.txt](Sources/AuralimCore/Resources/TimezoneData-LICENSE.txt)。
- 内置数据库版本为 2024a，不在运行时更新；时区偏移与夏令时规则由 macOS Foundation 提供。固定来源与完整声明见 [TimezoneData-NOTICE.txt](Sources/AuralimCore/Resources/TimezoneData-NOTICE.txt)，也可从应用设置底部查看。

Sparkle 使用 MIT 许可，完整声明随应用的「许可与数据来源」提供。
