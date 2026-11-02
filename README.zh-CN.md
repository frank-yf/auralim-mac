[English](README.md) | [简体中文](README.zh-CN.md) | [官网](https://frank-yf.github.io/auralim-site/)

# 晦明 · Auralim

**晦明变化者，山间之朝暮也。**

晦明是一款 Swift + SwiftUI 构建的 macOS 菜单栏应用，根据当地日出日落切换系统深浅外观。天文计算与时区查询在本机完成，独立于 macOS 自带的自动外观计划。

名称出自 **欧阳修《醉翁亭记》**：“**晦明**变化者，山间之朝暮也。”

> 本文说明当前 **0.5.4 功能**。可下载安装包以 [GitHub Releases](https://github.com/frank-yf/auralim-mac/releases/latest) 为准。参见[更新记录](CHANGELOG.md)。

## 产品功能

- **浅色／自动／深色**：托盘与设置同步选择；应用「自动」使用日出日落计划，与系统自动区分。
- **独立时间偏移**：日出、日落分别支持 ±120 分钟，滑块与精确输入同步。
- **选择城市或自动定位**：位置缓存在本机，刷新失败沿用缓存，无有效缓存时回退到保存的城市。
- **启动恢复**：自动模式等待桌面就绪并有限重试检查系统外观，手动选择优先接管。
- **唤醒补偿**：立即校正外观；已启用的动画等待桌面恢复或解锁后播放。
- **可选切换动画、切换倒计时**：均默认关闭；设置支持登录时启动。
- **手动／自动更新**：默认手动，并保留已有明确偏好。
- **十二种应用语言**：英语、简体中文、日语、繁体中文、德语、法语、西班牙语、巴西葡萄牙语、韩语、意大利语、俄语、荷兰语。官网仅提供简中与英文。

无需 WebView，也不持续定位；通过单次定时器和系统事件驱动调度。

## 安装与开始使用

要求 **macOS 13 或更高版本**。公开通用包包含 Intel 与 Apple 芯片架构；最低系统版本及具体硬件兼容性仍需实机验收。

1. 从 [Releases](https://github.com/frank-yf/auralim-mac/releases/latest) 下载 DMG 或 ZIP，将 `Auralim.app` 放入「应用程序」。
2. 打开菜单栏图标，进入「设置」，选择「选择城市」或「自动定位」。没有历史城市时按系统时区匹配，无法匹配时使用上海。
3. 选择「自动」启用日出日落计划；「浅色／深色」使用指定外观并暂停应用计划。

当前公开包采用 ad-hoc 签名，未经 Apple 公证。若首次打开被拦截，请确认下载来源并参考 [Apple 官方说明](https://support.apple.com/zh-cn/102445)；Release 提供校验文件。首次实际切换系统外观需要允许应用控制 System Events；只有启用自动定位才会申请位置权限。

未启用应用自动计划时，每次启动读取系统外观：系统固定深浅色对应高亮；系统自动时三段不高亮，设置中说明为「系统自动」，避免与应用计划混淆。使用应用「自动」时，建议关闭 macOS 自带的自动外观计划，避免两套计划相互覆盖。

### 日出与日落偏移

| 事件 | 负数／向左 | 正数／向右 |
| --- | --- | --- |
| 日出 → 浅色 | 提前转为浅色 | 延后转为浅色 |
| 日落 → 深色 | 提前转为深色 | 延后转为深色 |

范围均为 −120～+120 分钟。松开滑块、回车或离开输入框时提交；点击空白处会失焦并提交，Tab 切换焦点，「归零」恢复准时切换。位置区块显示**不含偏移的真实日出日落** `HH:mm`，托盘显示下一次偏移后的切换日期与时间，均按生效地点时区计算。

极昼保持浅色，极夜保持深色；越过相邻昼夜边界的偏移会裁剪或跳过。计算不包含地形遮挡、海拔和实时天气。

### 动画与倒计时

| 触发方式 | 倒计时 | 外观切换 |
| --- | --- | --- |
| 手动选择浅色／自动／深色 | 跳过 | 需要改变时播放已开启的动画 |
| 日出日落计划到点 | 遵循开关设置 | 已开启动画时先播放，再申请切换 |
| 唤醒校正 | 跳过 | 立即校正，已启用的动画稍后补播 |

动画运动结束时申请系统切换，末帧继续显示 1 秒；系统开启「减少动态效果」时跳过动画。可选倒计时默认 **10 秒**，支持 1～120 秒：

- **跳过本次切换**：跳过当前目标，直到计划进入下一个目标或再次主动选择模式。
- **知道了**：只收起面板，倒计时继续。
- **立即切换**：结束等待，继续执行已开启的动画流程。

无需系统通知权限。退出应用会停止计划，并保留当前系统外观。

### 定位、隐私与软件更新

手动城市模式完全离线。自动定位使用 macOS 定位服务，可能依赖 Wi-Fi 或网络；应用自身不上传经纬度。位置、时区和定位时间仅缓存在本机，时间用于内部刷新判断，不在界面显示。

每 **3 小时**、主动刷新或系统时区变化时请求新位置，每轮获取总时限为 **5 秒**，不含等待系统权限弹窗的时间。刷新中或失败后继续使用缓存，无有效缓存时使用保存的城市。暂时失败后，路由／DNS 变化可触发最多两轮恢复，两轮至少间隔 60 秒；不能绕过阻断系统定位的 VPN 策略。

更新使用 Sparkle 2。「手动更新」在点击检查后检查并下载；「自动更新」每天检查并后台下载兼容更新。准备好后可「重启以更新」，也可在正常退出时由 Sparkle 安装已准备好的更新。更新包与清单在解压前验签，更新请求不含位置坐标，并关闭系统信息统计。

## 开发指南

需要 macOS、Swift 6 工具链与 macOS SDK，可安装 Xcode 或 Command Line Tools。

```sh
git clone https://github.com/frank-yf/auralim-mac.git
cd auralim-mac
make run          # 退出项目内旧实例，编译、签名并启动正式版
make run-debug    # 退出项目内旧实例，编译、签名并启动调试版
```

`make build`／`make build-debug` 仅构建，输出为 `dist/Auralim.app`／`dist/debug/Auralim Debug.app`。运行命令会等待旧实例退出，退出或编译失败时停止；不影响「应用程序」中的安装副本。

调试入口仅在使用 `AURALIM_DEBUG_TOOLS` 编译时出现。调试版有独立标识、偏好与权限，关闭正式版自动更新，可预览倒计时、动画和完整流程。「预览结束后切换系统外观」每次启动默认关闭；开启后在动画运动结束时进入指定手动外观，仅倒计时预览则在倒计时结束时应用。

调试区另提供可取消的系统外观只读检查；检查同样需要 System Events 自动化权限，不会修改外观。

### 构建与定向验证

```sh
make help
make test FILTER=AppearanceCountdownTests
make test FILTER=LocationControllerTests
make test-ui             # 原生滑块、输入框交互
make test-ui-debug       # 调试设置与预览操作
make test-update-ui      # 更新区域操作
make clean              # 清理 dist/ 与 artifacts/ 内生成的 .app 副本
```

普通测试必须指定范围，仅运行受影响的检查；完整记录与限制见 [VALIDATION.md](VALIDATION.md)。原生界面检查使用隔离偏好及替身系统服务，需要登录会话、辅助功能和屏幕录制权限。真实权限连续性、VPN 恢复、旅行与系统／硬件兼容性需实机验证。部分 Swift Testing 框架要求 macOS 14+，不改变应用的 macOS 13 部署目标。

### 分发

```sh
AURALIM_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" make build
make prepare-release    # 仅在本地准备通用正式版／调试版发布附件
```

Developer ID 分发仍需 Apple 公证；未指定签名身份时使用 ad-hoc 签名。`make icon` 从 `Resources/Icons/Auralim.png` 生成 `.icns` 与面板共用图标。

`make prepare-release` 准备正式版通用 DMG、签名更新 ZIP／清单／校验文件及独立调试版 ZIP／校验文件，不发布、不覆盖已有同版本附件。应用内更新要求同时上传正式 ZIP、签名 `appcast.xml` 和校验文件，不能仅上传 DMG；调试版不进入正式更新清单。

更新签名私钥保存在登录钥匙串的 Sparkle 账户 `app.duskshift.mac`。迁移发布机器时需安全备份和导入原密钥，不能替换现有用户使用的签名链；私钥不进入 Git 或发布附件。

### 代码结构

| 路径 | 内容 |
| --- | --- |
| `Sources/Auralim/` | 原生界面、外观协调、定位与更新 |
| `Sources/AuralimCore/` | 天文计算、偏移、调度与离线时区 |
| `Sources/CZoneDetect/` | 时区边界解析器 |
| `Resources/` | 应用元数据、本地化名称与权限 |
| `Tests/`、`scripts/`、`Makefile` | 定向验证、构建与开发工具 |

天文计算采用 Meeus / NOAA 方程及标准视地平线 `−0.833°`。经纬度时区查询使用内置边界数据库，夏令时与 UTC 偏移由 macOS Foundation 提供。

## 许可与数据来源

项目采用 [MIT License](LICENSE)。第三方组件与数据保留各自许可：

- [ZoneDetect](https://github.com/BertoldVdb/ZoneDetect)：BSD-3-Clause，许可见 [ZoneDetect-LICENSE.txt](Sources/AuralimCore/Resources/ZoneDetect-LICENSE.txt)。
- 时区边界数据包含 [timezone-boundary-builder](https://github.com/evansiroky/timezone-boundary-builder) 的信息，以 ODbL 1.0 提供，许可见 [TimezoneData-LICENSE.txt](Sources/AuralimCore/Resources/TimezoneData-LICENSE.txt)。
- 内置数据库版本为 2024a，不在运行时更新；时区偏移与夏令时规则由 macOS Foundation 提供。固定来源与完整声明见 [TimezoneData-NOTICE.txt](Sources/AuralimCore/Resources/TimezoneData-NOTICE.txt)，也可从应用设置固定底部查看。

Sparkle 使用 MIT 许可，完整声明随应用的「许可与数据来源」提供。
