# 首版验证记录

## 0.3.3 唤醒动画延后播放（2026-10-23）

- 版本 0.3.3（build 28）。收到睡眠通知时同步记录系统外观，唤醒时立即重新计算并校正主题；动画等待桌面恢复或解锁后，经一次性 0.6 秒稳定延迟再播放。
- 只保存本轮唤醒的最新成功校验结果。即使 macOS 已先完成切换，也按睡眠前后外观决定是否播放；外观相同、系统托管而非应用控制、校正失败不会播放。重复唤醒、显示器与会话通知合并为一次效果。
- 重新锁屏、显示器休眠、再次睡眠、退出应用、关闭动画及过期请求均不会播放旧效果。延后播放仍遵循「减少动态效果」，没有持续轮询。
- `make test FILTER='WakeAppearanceTransitionTests|AppearanceTransitionTests|UpdateControllerTests/distributionConfigUsesSignedGitHubFeedAndDailyAutomaticDownloads'`：32 项定向测试通过。覆盖立即校正与显示就绪分离、锁屏解锁、系统提前切换、日出和日落方向、无变化、重复事件、动画开关、目标变更、失败与重试、慢请求与过期回调、退出/再次睡眠、就绪状态延迟更新以及减少动态效果。日志：`artifacts/wake-0.3.3/tests.log`。
- `AURALIM_WAKE_UI_TESTS=1 make test FILTER=WakeTransitionPresenterTests`：1 项通过。在真实登录桌面创建日出和日落动画面板，验证就绪前不创建、就绪后可见且不抢焦点、重复事件不替换面板，以及结束后释放面板与视图。使用注入的唤醒状态，未修改系统深浅模式。日志：`artifacts/wake-0.3.3/presenter.log`。
- `make build` 成功，构建脚本中的 `codesign --verify --deep --strict` 通过。本次产物为本机 x86_64 的 `dist/Auralim.app`，Info.plist 版本与构建号检查通过。日志：`artifacts/wake-0.3.3/build.log`。
- 未执行全量回归，未实际触发系统睡眠、合盖或锁屏；真实休眠跨日及解锁的端到端时序仍需实机验收。未替换正在运行的已安装应用，未推送或发布 Release。

## 0.3.2 彩色托盘与月亮残边修复（2026-10-22）

- 版本 0.3.2（build 27）。托盘改用无外圈的 SF Symbols：浅色 `sun.max.fill`、#F5A623；深色 `moon.fill`、#A7B7F5。生成 18pt 的 1x/2x 非模板位图并保留原始颜色。
- 自动、手动与暂停模式均从系统实际外观读取图标状态；系统通知、唤醒与请求完成时同步，等待及失败不会提前显示目标外观。
- 动画月亮由两圆奇偶填充再裁切改为两段相交圆弧组成的连续轮廓，消除镂空一侧的整圆抗锯齿残边，保留柔和光晕。
- `make test FILTER='MenuBarIconTests|AppearanceSyncTests|AppearanceTransitionTests|SettingsPresentationTests/offsetOnlyPublishesEditedSectionAndTimeTextDuringAndAfterVerification|UpdateControllerTests/distributionConfigUsesSignedGitHubFeedAndDailyAutomaticDownloads'`：23 项通过。覆盖 1x/2x 图标的实际颜色、月亮镂空像素透明度、待完成/失败及系统通知的外观同步、原有动画协调与版本配置。
- 人工查看渲染输出 `artifacts/menu-bar-0.3.2/` 的太阳、月亮与弯月轮廓，镂空处没有整圆细线。
- `make build`、`codesign --verify --deep --strict dist/Auralim.app`、打包 Info.plist 的 `plutil -lint` 均通过。本次构建为本机 x86_64；没有执行全量回归或重新发布 GitHub Release，也未替换当前运行的应用。

## 0.3.1 十二语本地化（2026-10-22）

- 版本为 0.3.1（build 26）。英语为开发基准；支持 en、zh-Hans、ja、zh-Hant、de、fr、es、pt-BR、ko、it、ru、nl。设置中的语言以母语名称显示，保持已有语言偏好；跟随系统按偏好顺序匹配地区变体，中文显式脚本优先，葡萄牙语使用巴西版本，不支持的语言回退英语。
- 每种语言包含完整的 143 条界面、城市、帮助、状态和更新文案，统一使用 Localizable.strings。补齐对应 macOS 自动化与定位权限说明；打包脚本自动收集语言目录。权限弹窗的实际语言由 macOS 决定。
- `make test FILTER='LocalizationTests|MenuLayoutTests|UpdateControllerTests/distributionConfigUsesSignedGitHubFeedAndDailyAutomaticDownloads|SettingsPresentationTests/languageAndLocationStillUpdateTheSettings'`：8 项通过（0.186 秒）。覆盖实际资源目录、键集合、格式占位符、系统语言与地区匹配、原有偏好标识、权限目录、设置发布、菜单尺寸及版本配置。
- `make test-localization-ui`：1 项通过（26.041 秒），用隔离偏好与外观/定位/登录替身，逐个通过原生菜单项选择 12 种语言，验证偏好持久化、设置窗口标题、菜单与设置三段标签同步、控件宽度，以及跟随系统恢复。保存 48 张深浅色设置/菜单截图；人工检查日语、韩语、德语、法语、巴西葡萄牙语、俄语及荷兰语代表布局。俄语菜单使用较宽的原生分段控件和简洁模式标题，避免重叠与省略。
- `AURALIM_UNIVERSAL=1 make build` 构建通过。最终包为 0.3.1（build 26），同时包含 arm64/x86_64；12 套界面目录与 12 套顶层权限目录全部存在。`codesign --verify --deep --strict`、25 个源 plist/strings 及 24 个打包 strings 语法检查通过。
- 未执行全量回归、真实系统权限弹窗或更新安装回归；原生语言测试未修改用户真实偏好及系统外观。本次未发布 GitHub Release，现有 v0.3 发布内容不变。

证据：[十二语界面截图](artifacts/localization-0.3.1/)。


## 0.3 Sparkle 后台更新与设置底部重启入口（2026-10-22）

- 版本为 0.3（build 25），固定 Sparkle 2.10.0，并提交 Package.resolved。应用启动时创建唯一更新器，默认每天检查并后台下载；更新器独立于设置窗口存活，不依赖打开菜单或设置才启动。
- 更新源为 `https://github.com/frank-yf/auralim-mac/releases/latest/download/appcast.xml`。设置底部显示检查、下载、准备、失败与就绪状态；就绪后才显示「重启以更新」。点击后调用 Sparkle 安装回调，正常使用过程中不强制重启；按用户明确接受的标准行为，正常退出时也允许安装已准备好的更新。
- 检查/下载错误支持重试和固定 GitHub latest 发布页回退；简体中文、繁体中文、英文文案齐全。系统信息统计关闭，更新代码不读取或发送定位数据。
- 新建独立 EdDSA 更新签名密钥，私钥仅在登录钥匙串的 `app.duskshift.mac` 账户中；应用携带公钥。清单与安装包均签名，解压前验证更新包；清单签名失败不随时间放宽校验。测试发现清单签名错误可能被外层 appcast 错误包装，已按底层校验错误正确分类，并增加回归测试。
- `make test-updates`：9 项定向测试通过，包含下载/准备不主动调用重启、点击一次只安装一次、失效回调清理、终止取消后的主动重试、无更新/断网提示、嵌套签名错误和三语目录一致性。
- `make test-update-ui` 对应的原生测试通过：通过实际鼠标事件点击底部重启按钮，确认只调用一次安装动作；检查下载、就绪、失败状态。简/繁/英三语的浅色与深色就绪截图已检查，底部状态和按钮完整可见。证据：[UI 截图目录](artifacts/update-ui-0.3/)。
- `make test-update-install` 使用与生产相同的 UpdateController、独立 bundle ID、临时应用与本地签名源，实际完成 build 25 → 下载 → 校验/准备 → 等待操作 → 主动重启动作 → 安装 → build 26 重新启动。最终配置复验通过，未替换用户运行的应用。证据：[最终安装与重启事件](artifacts/update-install-0.3/3f2a65d6fd4245598e93af51b390ae68/events.log)。
- `make test-update-quit` 实际确认正常退出后替换到 build 26，但不会自动重新拉起应用。证据：[正常退出事件](artifacts/update-install-0.3/7f53dae59a7e404680d98cac5476deb8/events.log)。
- `make test-update-signature` 对已签名清单进行篡改，真实 Sparkle 拒绝该清单，界面报告校验失败；没有进入下载/就绪/安装，临时应用仍为 build 25。证据：[拒绝篡改清单事件](artifacts/update-install-0.3/4f4951b6b51e4ad99122b2abd85d97de/events.log)。
- `AURALIM_UNIVERSAL=1 make build` 成功；主程序含 x86_64 / arm64，两个架构的最低系统版本均为 macOS 13.0。Sparkle 框架和安装助手正确嵌入，`codesign --verify --deep --strict` 通过。ad-hoc 本地构建保留上游框架签名，仅对 ad-hoc 主程序关闭库验证；Developer ID 路径保留库验证并从内向外重签。
- `make prepare-update` 生成通用 ZIP、签名 appcast.xml 和 SHA256SUMS.txt；校验公钥匹配、版本/构建号、固定标签下载 URL、包大小、清单及安装包 EdDSA 签名通过。最终 ZIP 为 7,640,186 字节（约 7.6 MB），包内元数据与本机构建一致，Sparkle 完整许可随应用分发。
- 本次未执行全量功能回归。Apple 芯片和 macOS 13 真机运行、Developer ID 签名/公证、需要管理员授权的安装、真实系统权限连续性，以及 GitHub 公网下载更新尚未验收。本次只准备本地产物，未创建或发布 GitHub Release；上线需将三个更新文件一起上传到 v0.3 正式 Release 并设为 Latest。


## 0.2.5 系统时区初始城市与固定 3 小时定位缓存策略（2026-10-22）

- 版本升级为 0.2.5（build 24），定位策略、三语文案、测试及说明作为同一版本提交。托盘「设置」按钮移除省略号，三语及相关验证脚本同步更新。
- 首次没有城市记录时，按系统时区匹配内置城市并保存。已有手动城市不被覆盖；没有启用自动定位时不创建 Core Location 会话。
- 首次启用自动定位、授权尚未决定时请求系统权限；授权后使用单次 requestLocation。坐标、精度、当地时区和定位时间保存在本机 cachedLocation，不上传坐标；时区和日出日落继续本地计算。
- 固定每 3 小时单次刷新，移除设置面板中的间隔选项及旧偏好。启动、激活和唤醒复用未过期缓存；主动更新或系统时区变化立即请求新位置。成功或失败后释放定位会话，切回手动或退出取消所有定时器和请求，不使用持续定位、显著位置变化或网络变化监听。
- 已过期缓存仍可在等待新位置和刷新失败时继续用于坐标、当地时区和日出日落计划；只有没有有效缓存时才回退手动城市。失败不覆盖磁盘缓存及原定位时间，界面明确标示正在沿用缓存。下一次自动尝试在 3 小时后，用户仍可主动更新。
- 临时位置未知、网络错误或无效快照按 2 / 5 / 10 秒有限重试，最多 4 次尝试，总时限 30 秒；日志仅记录授权状态、尝试和错误码，不含坐标。
- 使用临时偏好和替身服务定向运行 LocationTests、LocationControllerTests、LocationSettingsInteractionTests 与 LocalizationTests/catalogsAreCompleteAndFormatsMatch：31 项测试通过。覆盖首次授权、固定三小时及旧偏好停用、缓存写入/重启恢复、过期缓存与五类错误回退、手动/时区强制更新和唤醒复用、停止及过期回调。
- 设置面板通过原生分段控件切换位置模式，确认两种模式都只有城市和语言下拉框；刷新失败后缓存坐标和时区保持。浅色、深色截图已检查，缓存说明可见，未保留刷新间隔选项。未执行全量回归。
- 0.2.5（build 24）本地 Release 构建、严格签名、plist / 三语 strings 以及包内版本和资源一致性校验通过；三语权限提示同步说明本地缓存、不上传和失败回退行为。并行共享代码更新后，仅复验 LocationTests / LocationControllerTests，29 项通过。
- 真实系统定位在此前验证中仍返回 kCLErrorDomain code=0 并超时，未获得有效坐标。本次没有重置权限或把替身测试报告为真实定位成功；首次权限弹窗与真实位置获取仍需在可用的系统定位环境下验收。

证据：[定向测试](artifacts/location-3h-tests.log)、[0.2.5 构建](artifacts/auralim-025-build.log)、[浅色设置](artifacts/location-3h-ui/location-light.png)、[深色设置](artifacts/location-3h-ui/location-dark.png)。此前实机结果保留在 artifacts/location-cache-live.json。

## 0.2.3 设置与托盘面板共用应用图标（2026-10-22）

- 设置标题 40pt、托盘标题 30pt 的 DuskMark 统一使用新应用图标，去掉旧太阳符号和渐变底板；版本升级为 0.2.3（build 22）。
- 从与 ICNS 相同的 256px 图像生成 Sources/Auralim/Resources/AppIcon.png（73,102 字节），随 SwiftPM 资源包分发；make icon 同时更新 ICNS 与面板缩略图，中英文开发说明同步更新。
- 显式从运行时资源包读取 PNG，并缓存 NSImage，避免已安装包中 SwiftUI 命名图片查找未显示松散资源的问题；原色渲染、等比缩放，沿用两个标题的原有布局。
- make icon、Release 构建、严格签名与 plist 校验通过。面板 PNG 与 ICNS 的 256px 表示逐像素一致，包内 PNG 与源码资源逐字节一致，版本 / build 为 0.2.3 / 22。
- 仅打开新版本实际托盘和设置面板，截图人工确认两处图标及设置版本文字；启动参数关闭应用自动计划、定位和动画，未操作相关功能控件。当前系统外观下的完整面板已验证；共享生产组件另以 30pt / 40pt、浅色 / 深色环境离屏渲染，四种组合均检查通过。没有将启动参数视为完整面板深色外观的验收。
- 验证前后对比应用自身的语言、城市、偏移、自动计划、手动外观、定位模式和动画设置，均未改变；验证实例已退出。未执行语言 / 定位 / 登录启动 / 外观切换等功能测试或全量回归。

证据：[构建](artifacts/panel-icon-0.2.3-build.log)、[资源及签名](artifacts/panel-icon-0.2.3-resources.json)、[实际面板](artifacts/panel-icon-0.2.3-actual.log)、[托盘](artifacts/panel-icon-0.2.3/menu-current.png)、[设置](artifacts/panel-icon-0.2.3/settings-current.png)、[深浅渲染](artifacts/panel-icon-0.2.3-render.log)。

## 0.2.2 应用图标（2026-10-22）

- 接入已确认的暖金日轮 / 蓝灰月弧图标，保留生成的 PNG 原稿 `Resources/Icons/Auralim.png`，提供 `Resources/Auralim.icns`。版本升级为 0.2.2（build 21）。
- 新增 `make icon` 与 `scripts/generate-app-icon.sh`，使用 macOS 自带 sips / iconutil 生成 16、32、128、256、512 点各自的 1x / 2x 图标。临时 iconset 自动清理；原稿与正式 ICNS 作为应用资源纳入 Git。
- `CFBundleIconFile` 指向 Auralim.icns，构建脚本将其复制到应用包 Contents/Resources 后统一签名；中英文开发说明和现有品牌校验脚本的版本期望同步更新。
- `make icon` 成功；反解 ICNS 核对十个标准条目的 RGBA 尺寸（16～1024 像素）。纳入仓库的 PNG 原稿与用户确认的生成文件逐字节一致。
- `make build` 成功，应用版本 / build / 图标配置、包内 ICNS 与资源文件一致性、严格签名校验均通过。macOS NSWorkspace 实际解析到的新应用图标与直接读取 ICNS 的 256 像素渲染完全一致，平均通道差为 0；深浅背景预览人工检查通过。
- 本次仅验证图标生成、资源配置和打包结果；未启动应用或执行语言切换 / 外观切换 / 定位等功能交互，也未执行全量回归。核查时已有 0.2.1 发布包进程在运行，本次未操作该进程；新版应用包位于 dist/Auralim.app。

证据：[构建](artifacts/icon-0.2.2-build.log)、[包与系统图标解析](artifacts/icon-0.2.2-verify.log)、[浅色背景](artifacts/icon-0.2.2/icon-light.png)、[深色背景](artifacts/icon-0.2.2/icon-dark.png)。

## 本地目录迁移到 auralim-mac（2026-10-22）

- 将实际项目目录移动为 `/Users/frank/Code/my_proj/auralim-mac`，旧目录不再存在；Git 仓库、历史和版本标签完整保留，`git rev-parse --show-toplevel` / `git worktree list --porcelain` 均指向新位置。仅整理目录和开发配置，应用版本保持 0.2.1（build 20）。
- README 构建入口与路径说明更新，4 个原生交互测试的默认临时输出路径改用 `auralim-`。Makefile / 构建 / 测试脚本原本使用相对根目录，不含旧项目绝对路径。历史验证记录和原截图保留。
- 旧 `.build` 先隔离到 `/private/tmp/auralim-directory-migration-8rtqscz6/previous-build`，从新路径重新生成 SwiftPM 配置、编译缓存和资源访问器。Debug 生成的两个资源访问器已确认指向新目录。
- `make test FILTER='LocalizationTests/catalogsAreCompleteAndFormatsMatch|OfflineTimeZoneTests/builtInCitiesMatchOfflineBoundaries'`：2 项通过（0.080 秒），验证移动后的三语资源和离线数据库读取。编译了测试目标，未执行全量回归或其他功能套件。
- `make build` 从干净缓存完成 Release 构建（141.08 秒），Debug / Release 生成的资源访问器均使用新路径；严格签名校验及打包 Info.plist 校验通过。离线数据库 SHA-256 仍为 `678ab5e795975ff3f6226d3103833d984d83861b45ac7a472da9bf97de5d5e79`。
- `make run` 从新目录启动成功。仅在临时验证脚本中补充运行包路径 / 可执行路径 / 两个资源包断言，再使用已有 `verify-menu-bar.swift --settings` 检查实际托盘打开设置、关闭和重新打开，全部通过；截图确认名称、Slogan、时间和设置控件正常显示。未操作外观模式、动画、语言、定位、登录启动或偏移开关。
- Codex 用户配置中的项目路径信任条目已迁移，校验其余 TOML 内容与备份一致。尝试更新桌面端保存的项目根目录后，运行中的窗口会回写旧值；现有工具不提供修改该项目根目录的入口，因此桌面项目关联仍需在 Codex 中重新关联新目录。未将外部文件的临时改写报告为完成；全局配置不提交 Git。

证据：[定向资源测试](artifacts/directory-rename-tests.log)、[干净 Release 构建](artifacts/directory-rename-build.log)、[新路径实际运行](artifacts/directory-rename-actual.log)、[设置截图](artifacts/directory-rename-settings.png)。

## 0.2.1 晨昏 / Auralim 更名与模块迁移（2026-10-22）

- 中文名称改为「晨昏」，英文及其他语言回退为「Auralim」。中文 Slogan 为「日升而明，日落而暗」（末尾无句号），英文为「Between light and dark.」。托盘、设置抬头 / 窗口名、版本文字、帮助 / 用途说明和 macOS 本地化显示名同步更新。
- Swift package / 可执行模块改为 `Auralim`，计算模块为 `AuralimCore`；源码 / 测试目录、导入、安装包资源查找与许可入口一起迁移。Makefile 构建 / 运行入口使用 `dist/Auralim.app`，构建脚本迁移旧包目录并删除旧可执行文件和旧资源包。保留 Bundle ID `app.duskshift.mac`、偏好域与原测试环境变量；签名身份新增 `AURALIM_SIGN_IDENTITY`，兼容旧变量。
- `make test FILTER='LocalizationTests|OfflineTimeZoneTests/builtInCitiesMatchOfflineBoundaries'`：4 项通过（0.089 秒），验证三语目录 / 回退与改名后的离线数据库读取。随后按最终文案去掉中文句号，仅复验 `make test FILTER=LocalizationTests`：3 项通过（0.023 秒）。测试目标均完成编译，未执行全量回归。
- 最终 `swift scripts/verify-languages.swift --brand-only`：实际运行应用的英文 / 繁体 / 简体名称、Slogan、窗口标题、托盘与设置抬头、0.2.1 版本文字同步通过；校验包名、可执行名、两个资源包与三语 CFBundleName / CFBundleDisplayName，输出 6 张截图。验证后恢复原来的「跟随系统」，未操作外观模式、动画、登录启动、定位或偏移控件。
- 最终 Release 0.2.1（build 20）构建、严格签名、Info.plist / 三语 strings 与 bash 语法检查通过；数据库 SHA-256 与原版一致：`678ab5e795975ff3f6226d3103833d984d83861b45ac7a472da9bf97de5d5e79`。本次未重新验证系统授权弹窗或登录后启动；保留身份不代表已验证系统授权策略。
- 当前无 Git remote；`auralim-mac` 记录为仓库名称，未创建 / 改名 GitHub 远程仓库，本地工作目录保持原路径。

证据：[定向测试](artifacts/branding-0.2.1-tests.log)、[最终 Slogan 测试](artifacts/branding-0.2.1-slogan-tests.log)、[实际三语展示](artifacts/branding-0.2.1-actual.log)、[中文设置](artifacts/branding-0.2.1/settings-zh-Hans.png)、[英文托盘](artifacts/branding-0.2.1/menu-en.png)、[最终构建](artifacts/build-0.2.1.log)。

## 0.2 中文名称「日暮」、其他语言 DuskShift（2026-10-22）

- 简体 / 繁体中文统一「日暮」，英文与不支持语言的回退为「DuskShift」。托盘名称、设置抬头 / 窗口标题、版本行及权限 / 帮助文案同步替换；新增 app.name 本地化键。macOS 包的 CFBundleName 和 CFBundleDisplayName 同时提供三语值，默认 plist / development region 使用英文回退。
- 版本 0.2，build 19。输出改为 `dist/DuskShift.app`；构建迁移原有包目录，bundle identifier、可执行文件名及偏好域保持。实际构建后 dist 中只有新的应用包。
- `make test FILTER=LocalizationTests`：3 项通过（0.025 秒），包含三语名称、不支持语言的英文回退、文案目录与占位符完整性。未运行其他功能套件；已有原生交互测试只更新窗口标题预期并完成编译。
- `swift scripts/verify-languages.swift --brand-only`：实际打包应用的英文 / 繁体 / 简体名称交互全部通过，校验托盘抬头、设置抬头、窗口标题、带名称的 0.2 版本行，保存 6 张截图。校验包中三语 CFBundleName / CFBundleDisplayName、默认名、版本和 build；系统运行进程显示名为「日暮」。命令行文件显示名为 DuskShift，未将文件系统名与应用内语言即时同步混为一谈。验证后恢复原来的「跟随系统」，未操作深浅模式、动画、登录启动、定位或偏移控件。
- Release 构建、严格签名验证、Info.plist / 三套 InfoPlist.strings / 三套 Localizable.strings 语法及构建脚本 bash 语法检查通过。0.2 已启动，未执行全量回归，未重新申请权限验证系统授权弹窗文字。

证据：[本地化测试](artifacts/branding-0.2-tests.log)、[实际三语名称与版本](artifacts/branding-0.2-actual.log)、[中文设置](artifacts/branding-0.2/settings-zh-Hans.png)、[英文托盘](artifacts/branding-0.2/menu-en.png)、[构建](artifacts/build-0.2.log)。

## 0.1.17 居中半屏日月轮转、动画默认关闭（2026-10-22）

- 最终效果为显示器中央半屏面积（宽 80%、高 62.5%），四边透明渐隐，不使用上 / 下半屏或中央小卡片。太阳、月亮沿椭圆弧线交替左升右落，日出 / 日落的昼夜色温与光晕随进度变化，约 3.2 秒。日月轨迹与月相为视觉示意，未新增月出月落计算。
- 设置的外观卡片增加三语「日出日落动画」开关。新安装 / 升级默认关闭，独立持久化；启用不重播或请求外观，关闭立即撤除效果，切换请求尚未完成时关闭也不会播放。系统开启减少动态效果时省略半屏动画。动画状态不驱动整个设置面板更新，关闭后无动画窗口或持续轮询。
- 最终 `make test-transitions`：15 项通过（0.328 秒）。包含实际改变 / 无变化 / 失败 / 过期请求的原有触发检查，新增默认关闭、开关持久化、只发布外观卡片、请求中关闭、播放中关闭、居中半屏几何、东西方向和轨迹边界检查，另含 1 项偏移局部发布测试。
- 最终 `make test-ui-transitions`：1 项通过（14.808 秒）。实际原生开关与两处控件验证默认关闭仍可切换、启用不发请求、托盘日落 / 设置日出、居中半屏 frame、无文字 / 不抢焦点 / 鼠标穿透、连续切换替换、关闭立即停止、内容与窗口清理、减少动态效果跳过；系统外观控制使用替身。只对新增开关做三语位置及可见性检查。
- 检查最终截图：设置开 / 关三语、日出 / 日落过程，以及生产 Canvas 两方向的起点 / 中点 / 终点，共 12 张。色温和日月轨迹正确；居中后四周均采用整体 alpha 遮罩，避免光晕在边界被硬切。透明浮层原始 PNG 的低 alpha 区域会呈现量化条纹，画面检查使用中性背景合成的生产场景，未把原始透明 PNG 当作桌面合成效果。
- 真实打包应用：`swift scripts/verify-appearance-mode.swift --apply --animations --adopt-current` 通过。先验证动画关闭时系统外观确实切换；再经设置临时启用，从托盘切深色检出居中半屏日落、从设置切浅色检出居中半屏日出，外观未改变时不播放，并确认关闭与焦点。恢复原来的浅色选项及动画 false，重启后只读核验托盘 / 设置同为「系统管理 · 当前浅色」。仅为验证临时采用已有浅色，未改动城市、定位、偏移或登录启动。
- Release 0.1.17（build 18）构建、严格签名及 Info.plist / 三套 strings 语法校验通过，最终版本已重新启动，动画关闭。一次性渐出 / 关闭 Timer 使用 common mode，退出或关开关时均注销。
- 本次最终共 16 项定向测试及真实应用检查通过，未执行全量回归，未重新验证定位、登录启动、天文算法或滑块输入。已有布局测试仅适配新增开关数量 / 登录开关位置并完成编译，未执行其完整矩阵。其他显示器原点 / 尺寸用几何样本验证，未声称多显示器硬件实测；未进行 CPU / 内存基准。

证据：[最终逻辑](artifacts/centered-transition-tests.log)、[最终原生交互](artifacts/centered-transition-ui.log)、[真实应用与重启](artifacts/centered-transition-actual.log)、[设置开关](artifacts/appearance-transition-0.1.17/settings-animation-on.png)、[日出示意中点](artifacts/appearance-transition-0.1.17/scene-sunrise-middle.png)、[日落示意中点](artifacts/appearance-transition-0.1.17/scene-sunset-middle.png)、[构建](artifacts/build-0.1.17.log)。

## 0.1.16 系统外观切换时播放日出日落（2026-10-22）

- 转浅色播放日出，转深色播放日落；两面板共用系统应用结果。System Events 在同一次请求中返回最终外观及是否改变，最终外观验证成功且请求未过期才播放。重复核验、失败和无变化不播放；快速切换替换旧浮层。Canvas 绘制短动画，独立不可激活浮层不拦截鼠标，不驱动设置布局刷新。
- 定向逻辑：`make test FILTER='AppearanceTransitionTests|AppearanceModeTests|SettingsPresentationTests/offsetOnlyPublishesEditedSectionAndTimeTextDuringAndAfterVerification'` 20 项通过（0.550 秒）。覆盖 7 项新动画结果 / 触发 / 失败 / 过期请求 / 自动计划 / 关闭测试，以及 12 项已有模式测试和 1 项局部发布检查。
- 原生动画：`make test-ui-transitions` 1 项通过（10.073 秒）。从菜单切深色播放日落、从设置切浅色播放日出，两处选择同步；检查不抢键盘焦点、不接收鼠标、快速替换、无变化不重播、静态减少动态效果、窗口与 contentView 清理。初次检查发现 AppKit 嵌套事件循环下异步关闭未及时执行，已改为 common-mode 一次性 Timer，并通过上述复验。
- 检查 7 张画面：日出 / 日落过程、减少动态效果的深浅两帧，以及同一生产 Canvas 的夜间 / 地平线 / 日间三帧；太阳位置与天空方向一致，简中文案及英文静态提示可见。系统外观控制在原生交互测试中使用替身。
- 真实打包应用：`swift scripts/verify-appearance-mode.swift --apply --animations` 通过。从托盘切深色，读取实际系统为深色并检出「日落 · 切换至深色」；从设置切浅色，读取系统为浅色并检出「日出 · 切换至浅色」；切回应用自动且外观无变化时不播放。验证浮层关闭、未获取焦点及两处同步，最后恢复原来的应用自动模式。浮层使用 Core Graphics 可见窗口列表检测，因不可激活浮层不会稳定出现在辅助功能窗口列表中。
- Release 0.1.16（build 17）构建、严格签名以及 Info.plist / 三套 strings 语法检查通过，已启动。
- 本次共 21 项不同的定向测试及真实应用检查通过；未执行全量回归，未重新验证定位、登录启动、天文算法或滑块输入。已有其他测试仅适配外观控制成功结果类型并完成编译，未执行无关交互；动画结束后的低占用由窗口 / 内容清理与无持续轮询实现验证，未做 CPU 或内存基准。减少动态效果由注入系统选项验证，未修改用户辅助功能偏好。

证据：[定向逻辑](artifacts/transition-tests.log)、[原生动画](artifacts/transition-ui.log)、[真实切换与动画](artifacts/transition-actual.log)、[日落过程](artifacts/appearance-transition-0.1.16/sunset-middle.png)、[日出过程](artifacts/appearance-transition-0.1.16/sunrise-middle.png)、[减少动态效果](artifacts/appearance-transition-0.1.16/reduced-motion-dark.png)、[Release 构建](artifacts/build-0.1.16.log)。

## 0.1.15 启动时区分系统自动与应用自动（2026-10-22）

- 每次启动读取系统外观；未启用应用自动计划时固定浅 / 深高亮对应段，系统自动及无法确认时三段无高亮。启动不重新应用旧手动记录；已启用的应用日出日落计划继续保留。托盘与设置共用状态，新增三语来源文案及自动段提示。
- `make test-appearance-mode`：18 项通过，覆盖系统固定 / 自动 / 未知、每次启动重新读取、旧手动记录不覆盖系统、应用自动保留、显式点击接管、唤醒后的系统状态刷新、两处同步、相关布局及偏移局部发布。
- 随后仅对系统读取补充只读实机比对与同步失败回退，执行 `make test FILTER=SystemAppearanceSettingsTests`：4 项通过，其中 3 项为前述解析测试，新增 1 项将生产读取结果与 `/usr/bin/defaults read -g` 比较。本机结果固定浅色，与独立读取一致。
- `make test-ui-mode`：1 项原生交互测试通过（11.045 秒）；两面板系统固定高亮 / 自动与未知无高亮、点击当前固定段接管、手动与自动双向同步、自动提示均通过。新增系统自动文案在三语 × 深浅面板共 12 张截图中检查可见，无截断；系统服务使用替身，不改真实系统自动设置。
- 共 20 项不同的定向测试通过，未执行全量回归；未重新验证定位、登录启动、日出日落算法及滑块输入。编译了整个测试目标，实际执行范围由 FILTER 限定。
- Release 0.1.15（build 16）构建及严格签名、Info.plist 和三套 strings 语法检查通过。真实打包应用的辅助功能验证：启动保留原先应用自动，状态明确为「应用自动 · 按日出日落切换 · 当前浅色」；从托盘切深色、从设置切浅色、再从托盘切自动，两处一致，读取实际系统深浅结果分别 true / false，最后恢复原先应用自动。
- 系统自动开关解析及无高亮启动状态通过注入偏好和原生控件验证；未为验证展示而修改本机 macOS 自动计划。本机偏好键缺失按系统固定默认值解释；未知值或同步失败采用系统管理展示。系统全局偏好键不属于稳定公开契约，未声明其他 macOS 版本已验证。

证据：[定向逻辑](artifacts/startup-presentation-tests.log)、[只读系统比对](artifacts/startup-system-reader.log)、[原生交互](artifacts/startup-presentation-ui.log)、[真实应用](artifacts/startup-presentation-actual.log)、[简中托盘](artifacts/appearance-mode-0.1.15/menu-zh-Hans-light-system-auto.png)、[英文设置](artifacts/appearance-mode-0.1.15/settings-en-light-system-auto.png)、[Release 构建](artifacts/build-0.1.15.log)。

## 0.1.14 托盘与设置共享三段外观模式（2026-10-22）

- 托盘与设置均改为复用同一个「浅色｜自动｜深色」原生分段组件，选中项双向同步。浅色/深色会保存手动目标、关闭自动开关并立即请求及验证系统外观；自动会清除手动目标并立即恢复日出日落计划。菜单栏图标随模式显示太阳/月亮。
- 手动模式启动、唤醒与配置检查均保持所选外观，正常情况下不安排日出日落/午夜定时器；仍保留计划预览。旧版暂停且没有明确手动目标时不改系统外观，按当前外观高亮；旧版自动设置继续生效。权限拒绝保留提示并抑制自动重复请求，短暂错误仍最多安排两次单次重试。
- 统一自动与手动的串行请求及版本校验。切换进行中再次选择时，等待旧请求完成后按最后选择纠正，旧自动请求不会成为最终手动状态，反向切换同样适用。
- 定向单元/协调/布局验证：21 项通过，包含新增 9 项模式测试、原有 AppModel 请求协调与初始化测试、偏移局部更新检查和菜单尺寸检查。覆盖即时切换、恢复自动、持久化与旧配置、唤醒/偏移不覆盖手动选择、错误/重试和交错请求。未执行天文、离线时区、定位和登录项等无关全量套件。
- `make test-ui-mode`：1 项原生控件测试通过（23.751 秒），从托盘和设置分别派发原生分段动作，核对两处真实控件的选中项与目标请求，并验证旧版暂停时点击已高亮项也会保存明确选择；覆盖三语、两种面板外观和三种模式，共 36 张截图。窗口尺寸保持托盘 320 × 264、设置内容 600 × 720。原生测试使用临时偏好及替身服务。
- 初次原生检查把自适应控件的 141 宽与人为设定的 150 比较，导致断言失败；改为核对其原生固有尺寸及完整可见性后通过，截图确认文字完整。
- Release 0.1.14（build 15）构建、严格签名及 Info.plist / 三套语言资源语法校验通过，已启动。真实应用通过辅助功能分别从托盘选深色、从设置选浅色、再从托盘选自动；读取系统 AppleInterfaceStyle 验证深色 true / 浅色 false，两处选中项及系统确认状态一致，最后恢复原先自动模式。
- 真实验收脚本首次在切换后未找到托盘窗口，异常清理恢复了原模式；将系统确认等待与托盘窗口获取分开并增加短时重试后，三种模式实际验收通过。运行时功能未新增轮询；仅验收脚本在有界等待中读取 UI 与系统状态。

证据：[模式相关测试](artifacts/appearance-mode-tests.log)、[原生模式交互](artifacts/appearance-mode-ui.log)、[实际系统切换](artifacts/appearance-mode-actual.log)、[英语托盘](artifacts/appearance-mode-0.1.14/menu-en-light-automatic.png)、[深色设置](artifacts/appearance-mode-0.1.14/settings-en-dark-dark.png)、[Release 构建](artifacts/build-0.1.14.log)。

## 0.1.13 统一菜单栏与设置 UI（2026-10-22）

- 新增共享的深浅模式背景、卡片、图标和提示样式。菜单栏为 320 × 264，突出自动开关、位置和下次切换时间；设置内容为 600 × 720（小屏幕自动缩短），以双时间卡片、位置卡片和独立偏移卡片组织内容。语言、登录时启动和许可入口固定在底部，长状态和小窗口使用正文滚动。
- 保留 0.1.12 的滑块渲染和偏移提交方式；AppModel、SettingsPresentation、天文/时区模块未修改。设置区域独立订阅，输入焦点和另一控件不因偏移提交而重建。打开新窗口时清除自动文本焦点，继续支持已有窗口复用。
- `make test FILTER=MenuLayoutTests`：2 项通过，验证菜单在普通及压缩尺寸建议下均为 320 × 264，小屏幕设置高度规则保持。
- 原生 `NativeInteractionTests`：1 项通过（22.813 秒），仅覆盖本次界面相关的四向拖动、双向同步、回车/失焦/边界/非法输入/归零、显示时间、窗口复用、三语标题、位置模式及后台校验时的焦点/滚动/控件稳定性。定位和外观、登录项使用替身，不改用户设置。
- 新增 `make test-ui-layout`：1 项通过（16.631 秒）。通过原生开关动作验证自动切换绑定、登录项开关请求；截图核对三语 × 深浅模式的设置、开关状态 × 三语 × 深浅模式的菜单、自动定位成功/失败、登录待批准及 400 高小窗口滚动，共 22 张截图；补充检查初始焦点、自动定位时两条滑块完整可见和小窗口输入框不被遮挡。没有请求真实定位、注册真实登录项或切换系统主题。
- 首次截图 OCR 将较细小的「日落转暗」识别错误，时间数字正确；将时间标签提高到 13 号后，文字及两项时间识别均通过。原生 SwiftUI 开关桥接虽执行动作却返回 false，测试改为核对实际绑定及替身服务调用，不把该返回值当作功能失败。
- Release 0.1.13（build 14）构建、严格签名及 plist 校验通过，已运行。真实菜单栏连续三次打开均为 320 × 264；通过真实设置入口打开/关闭/重开，确认仅有一个 600 × 752（含标题栏）的设置窗口。已检查最终实际菜单及自动定位设置截图。
- 本次只运行以上 4 项 UI/交互测试及构建检查，没有运行天文、时区、调度和其他业务的全量测试。

证据：[布局测试](artifacts/ui-layout-tests.log)、[原生交互](artifacts/ui-redesign-interaction.log)、[UI 外观与开关](artifacts/ui-appearance-test.log)、[浅色设置](artifacts/ui-0.1.13/settings-zh-Hans-light.png)、[深色设置](artifacts/ui-0.1.13/settings-en-dark.png)、[小窗口滚动](artifacts/ui-0.1.13/settings-small-screen.png)、[实际菜单检查](artifacts/ui-menu-verification.log)、[实际设置检查](artifacts/ui-settings-verification.log)、[Release 构建](artifacts/build-0.1.13.log)。

## Git 初始化与逐版本补录（2026-10-22）

- 使用 `git init -b main` 初始化本地仓库。按会话日志恢复 0.1.0～0.1.12 各轮结束时的源码状态，逐版独立提交并设置对应版本标签；提交明确说明属于历史补录，没有倒填提交时间。
- 逐版本核对 Info.plist 的应用版本号、构建号，以及暂存文件内容和可执行权限与恢复快照一致。恢复后的最终 53 个文件与初始化前的当前工作区逐文件 SHA-256 和权限一致。
- 版本提交之后，另行提交 Git 使用说明、忽略生成文件及后续逐版本提交规则；本次不提高应用版本号。
- 本次仅验证 Git 历史、版本映射、文件一致性和仓库状态，不重跑应用交互或全量测试。各版本已有测试结论仍以对应历史记录为准。

## 0.1.12 恢复上一版渐变与限定测试范围（2026-10-22）

- 仅撤回 0.1.11 的蓝灰色、非零偏移的强显色下限和快速三段渐变，恢复 0.1.10 的蓝色 / 暖金色、平方根强度与连续渐变。柔和底轨、单组件以及设置局部更新保留。
- 新增 Makefile：`build`、`run`、`test FILTER=...`、`test-sliders`、`test-ui`；默认显示帮助，缺少 FILTER 时拒绝执行测试。按变更限定验证范围的要求写入 AGENTS.md。
- `make test-sliders`：仅执行 2 项渐变像素测试，全部通过；覆盖两条滑块、四方向、浅色/深色底轨、选区显色、未选中轨道与无中心接缝。
- `make test-ui`：仅执行滑块相关原生交互分支，1 项通过（22.352 秒）。四向鼠标拖动、输入预览/回车/失焦、键盘和辅助功能增减、边界/非法输入、归零和偏移后的两项时间显示均通过；随后立即结束，不执行语言、定位、窗口复用等无关场景。
- 已检查浅色/深色下蓝色、暖色、10 分钟及零偏移的 8 张测试窗口截图。原生测试使用临时偏好及替身服务，不更改用户设置和系统外观。
- `make help`、目标命令预览和缺少 FILTER 的防误执行检查通过；Info.plist 语法通过。本次没有运行全量测试，也没有重新验证语言、定位、登录启动或天文算法。
- `make build` 完成 Release 0.1.12（build 13）打包及严格签名校验；`make run` 已启动新版，并确认对应进程保持运行。

证据：[渐变测试](artifacts/slider-tests.log)、[滑块交互测试](artifacts/slider-ui-test.log)、[浅色蓝色渐变](artifacts/slider-cool-light.png)、[深色蓝色渐变](artifacts/slider-cool-dark.png)、[浅色暖色渐变](artifacts/slider-warm-light.png)、[深色暖色渐变](artifacts/slider-warm-dark.png)、[显示时间](artifacts/slider-interaction.png)。

## 0.1.11 小偏移蓝灰色与设置局部更新（2026-10-22）

- 未选中轨道配色保持不变；偏暗方向改为低饱和蓝灰色，深色窗口另有更亮的蓝灰色。选区快速过渡到明显颜色，非零小偏移圆点也直接显色；偏亮方向保留暖金色。
- 新增 SettingsPresentation 和独立的区域状态发布器。只有显示值变化的区域发布更新，根面板仅在语言变化时发布；偏移编辑不再让整页订阅失效。取消后台校验时所有设置控件的禁用与临时检查文字，保留必要的真实状态/错误更新。
- 普通测试 60 项通过，原生交互 1 项默认跳过，汇总 61 项。新增测试在延迟外观响应的替身下逐个统计区域通知：日出偏移只发布 sunrise + times，日落只发布 sunset + times，完成校验后没有多余通知。另覆盖重复提交、保留授权错误与不重复请求、语言/位置变化仍能更新，以及 5/10/15 分钟在两种外观、两条滑块四个方向的显色。
- 独立原生交互回归通过（24.379 秒）。延迟后台校验期间，两条滑块与输入框均保持启用，另一控件原生实例和值不变，输入焦点和实际 NSScrollView 滚动位置保留；时间文本截图识别正确。原有四向拖动、精确输入、边界/非法输入、归零、键盘、辅助功能、语言和定位模式回归通过。
- 初次原生回归发现主队列合并通知在同步测试/嵌套 AppKit 循环中延后，导致时间文本及归零读值滞后。改为主运行循环 common modes 派发，并让控件绑定直接读取真实模型后通过。普通与原生测试均在该修复后重跑通过。
- 已检查 5 分钟蓝灰圆点、10 分钟蓝灰选区及 10 分钟暖色选区在 Aqua / Dark Aqua 面板的截图；深色外观仅设置到临时测试窗口，没有更改系统外观。实际系统主题变化仍会按系统通知重绘面板，不将其视为应抑制的刷新。
- Release 0.1.11 编译、严格签名及 plist 校验通过，已运行。实际设置打开/重开及 560 × 752 尺寸验证通过；三语实际切换、控件标签和菜单栏验证通过，结束恢复原语言。

证据：[实际设置窗口](artifacts/settings-local-update-actual.png)、[实际窗口验证](artifacts/settings-verification.log)、[实际语言切换](artifacts/language-verification.log)、[10 分钟蓝灰（浅色）](artifacts/settings-gradient-dark-offsets.png)、[10 分钟蓝灰（深色）](artifacts/settings-gradient-dark-offsets-dark-appearance.png)、[5 分钟偏移](artifacts/settings-gradient-five-minutes.png)、[10 分钟暖色（浅色）](artifacts/settings-gradient-small-warm.png)、[10 分钟暖色（深色）](artifacts/settings-gradient-small-warm-dark-appearance.png)、[普通测试](artifacts/unit-test.log)、[原生交互回归](artifacts/native-ui-test.log)。

## 0.1.10 柔和底轨与日出/日落显色（2026-10-22）

- 两条滑块同步调整：浅色窗口底轨改为柔和浅灰，深色窗口底轨只比卡片背景略亮；不再使用接近黑色的固定底色。
- 日出左移与日落右移的偏暗渐变改为可辨识蓝色，深色窗口使用更亮的蓝色；偏亮方向保留暖金色。颜色强度随偏移使用平方根曲线，小幅偏移也能看出颜色；零位、未选中区间及连续单轨结构保持。
- 普通测试 55 项通过，原生交互 1 项默认跳过，汇总 56 项。像素测试覆盖两种窗口外观、两条滑块、四个方向及 30/84 分钟偏移，确认底轨亮度范围、蓝色/金色色相差异、未选中区间不变色和中心无接缝。
- 独立原生交互回归通过（18.702 秒），包含四向拖动、输入同步、边界、归零、键盘与辅助功能；额外截取日出延后 30 分钟 / 日落提前 30 分钟在 Aqua、Dark Aqua 下的实际测试窗口，已检查两组蓝色渐变均可见。测试使用临时偏好和替身外观服务，没有改变系统外观。
- Release 0.1.10 构建、严格签名及 plist 校验通过，已运行。实际菜单栏打开设置、关闭重开和 560 × 752 尺寸验证通过，已检查打包后实际窗口截图。

证据：[打包后实际窗口](artifacts/settings-soft-track-actual.png)、[两条偏暗渐变（浅色窗口）](artifacts/settings-gradient-dark-offsets.png)、[两条偏暗渐变（深色窗口）](artifacts/settings-gradient-dark-offsets-dark-appearance.png)、[偏亮方向](artifacts/settings-gradient-lighter.png)、[普通测试](artifacts/unit-test.log)、[原生交互回归](artifacts/native-ui-test.log)。

## 0.1.9 连续灰色轨道与选中区间染色（2026-10-22）

- 零偏移时使用统一深灰色轨道及灰色圆点；只有中心到圆点的区间显示渐变，圆点以外及另一侧保持灰色。渐变从同一个灰色开始，移除轨道中的分界标记，消除两段拼接感。
- 每条轨道使用一个 NSSlider / NSSliderCell；日出和日落复用同一个组件，仅用方向配置选择深蓝或浅金色。圆点颜色随偏移程度改变，归零清除颜色。未改动鼠标、键盘、辅助功能、输入同步或提交逻辑。
- 普通测试 55 项通过，原生交互 1 项默认跳过，汇总 56 项。像素测试改为验证零位颜色一致、中心无接缝，以及日出/日落四方向上只有选中区间变色、超出圆点及另一侧不变色。
- 独立原生交互回归通过（16.812 秒），覆盖四向拖动、输入/失焦、边界、归零、1/10 分钟键盘步进、辅助功能增减、时间显示及窗口复用。已检查部分偏移、最深/最浅端点及深色窗口截图，未改变系统外观。
- Release 0.1.9 编译、严格签名及 plist 校验通过，已运行。真实菜单栏打开设置与关闭重开通过，窗口仍为 560 × 752；已检查实际窗口：日落零位整轨灰色，日出提前 90 分钟时仅中心到圆点的区间染色。首次启动后脚本未找到设置入口，随后读取状态并重试通过；未据此推断具体原因。

证据：[实际灰色轨道与选中区间](artifacts/settings-gray-track-actual.png)、[真实设置窗口验证](artifacts/settings-verification.log)、[部分偏移](artifacts/settings-gradient.png)、[偏暗端点](artifacts/settings-gradient-deeper.png)、[偏亮端点](artifacts/settings-gradient-lighter.png)、[深色窗口](artifacts/settings-gradient-dark-appearance.png)、[普通测试](artifacts/unit-test.log)、[原生交互回归](artifacts/native-ui-test.log)。

## 0.1.8 精简设置与明暗渐变滑块（2026-10-22）

- 设置移除整页使用说明、常驻输入教程、语言和登录启动的重复说明。保留控件与必要状态/错误，语言和许可入口固定底部；时间区域只展示偏移后的转亮/转暗时间，原始日出日落可悬停查看。
- 日出/日落采用 NSViewRepresentable 包装原生 NSSlider，自绘 NSSliderCell 渐变轨道、零位标记、中心到圆点的选中区间和随位置变色的圆点。日出左深右浅，日落左浅右深；太阳/月亮图标与方向标签保留。
- 保留原生鼠标跟踪、键盘焦点、辅助功能、精确输入与提交时机，1 分钟步进，Option + 方向键 10 分钟；范围仍为 ±120 分钟。没有为渐变添加动画或定时器。
- 普通测试 55 项通过，原生交互 1 项默认跳过，汇总 56 项。新增两个像素渲染测试确认相反的渐变方向和选中区间会随位置改变。
- 独立原生交互回归通过（16.738 秒）：四向拖动、数字预览/提交、失焦、越界/非法输入、归零、键盘 1/10 分钟、VoiceOver 增减、显示时间、窗口重开与定位模式回归均通过。最深/最浅端点及 Dark Aqua 窗口截图已检查，深色外观仅设在临时测试窗口，未更改系统外观。
- Release 0.1.8 构建、严格签名和 plist 校验通过，已运行。实际菜单栏打开设置与窗口重开通过，仍为 560 × 752，真实辅助功能树确认无使用说明页、两组滑块/输入和切换时间存在。实际设置依次切换 English / 繁體中文 / 简体中文，标题、控件和菜单即时更新，结束恢复原来的「跟随系统」。
- 首次原生测试中，旧脚本把新增的右对齐「立即检查」按钮当作第一个归零按钮，导致点击目标距离断言失败。改为按各滑块对应标题行定位归零按钮后通过；未将该脚本定位失败当作应用功能故障。

证据：[实际设置窗口](artifacts/settings-gradient-actual.png)、[实际设置验证](artifacts/settings-verification.log)、[实际语言切换](artifacts/language-verification.log)、[精简设置与中间偏移](artifacts/settings-gradient.png)、[偏暗端点](artifacts/settings-gradient-deeper.png)、[偏亮端点](artifacts/settings-gradient-lighter.png)、[深色窗口](artifacts/settings-gradient-dark-appearance.png)、[普通测试](artifacts/unit-test.log)、[原生交互回归](artifacts/native-ui-test.log)。

## 0.1.7 自动定位与离线时区（2026-10-22）

- 设置新增「位置模式」分段控件：自动定位 / 手动城市，默认沿用手动模式。自动模式保留可编辑的备用手动城市，显示坐标、当前生效时区、进度、失败原因和更新位置按钮；三语资源与权限用途说明齐全。
- 使用 Core Location 单次公里级定位、系统显著位置变化、NWPathMonitor 网络事件及现有唤醒/会话/时区/激活通知。没有持续高精度定位或后台轮询；单次定位 30 秒超时、并发合并，网络事件请求限频。切回手动时移除定位 delegate、停止位置/网络监听并取消超时。
- 离线时区库随包分发，使用固定版本 ZoneDetect BSD C 解析器和 4,697,896 字节 timezone21.bin，包含完整许可/来源；数据版本 2024a、边界量化约 20 m，时区规则使用 Foundation。查询不依赖系统时区、不调用在线地址服务。缺失或重叠边界不猜测时区，回退手动城市。
- 53 项普通测试通过，原生交互 1 项默认跳过，汇总 54 项。新增 13 项测试覆盖全部内置城市、额外旅行城市、美国相邻州边界及夏令时、非法/重叠坐标、位置模式持久化但不存坐标、真实通知注入、跨时区调度/显示、五类失败回退/恢复、并发过期外观回调、拒绝自动化权限后不重复请求，以及定位样本过滤。
- 原生交互测试独立通过（12.813 秒）：生产 NSSegmentedControl 动作触发自动模式，替身纽约坐标切到 America/New_York，失败回退上海，切回手动停止服务；原有滑块四向拖动、文本编辑、显示时间、语言切换和窗口复用回归通过。此测试使用替身定位与外观服务，不代表真实定位授权已通过。
- Release 0.1.7 编译及严格签名校验通过，已运行。真实菜单栏打开设置、说明页和关闭重开正常，尺寸仍为 560 × 752。定位用途说明三语 plist 与定位 entitlement 已校验；打包库 SHA-256 与源码一致，应用约 5.4 MB。
- 本机只读能力检查：Location Services enabled = true，significantLocationChangeMonitoringAvailable = true。未申请应用的真实定位授权、未读取真实当前位置；首次授权/拒绝/恢复、真实旅行通知、断网获取定位及长期功耗仍需用户登录会话验收。系统定位可依赖 Wi-Fi/网络，不把离线时区计算等同于离线一定能定位。

证据：[原生自动定位视图（替身坐标）](artifacts/settings-location.png)、[实际手动模式窗口](artifacts/settings-location-manual.png)、[普通测试](artifacts/unit-test.log)、[原生交互测试](artifacts/native-ui-test.log)、[实际窗口验证](artifacts/settings-verification.log)、[Release 构建](artifacts/build-app.log)。

## 0.1.6 登录时启动（2026-10-22）

- 设置 → 自动切换页底部新增「登录时启动」开关，采用 macOS 13+ `SMAppService.mainApp`；中文简体、繁体和英语提示及帮助均已补齐。菜单栏保持精简。
- 系统状态是唯一来源，启动时不自动注册；支持未注册、已启用、等待批准、未找到和未知状态。待批准时提供系统登录项设置入口，并允许取消注册；注册/注销失败后仍回读实际状态。打开设置和应用重新激活时刷新，无持续轮询。
- 登录项设置独立于外观开关、城市和偏移；不触发外观请求或重新安排天文调度。5 项新增测试覆盖注册/取消与重复请求、待批准/取消、注册和注销错误、错误提示即时翻译、外部状态变更和激活刷新。
- 普通测试 40 项通过，原生交互测试 1 项默认跳过，汇总显示 41 项。独立原生交互回归 1 项通过（11.560 秒），包含四向拖动、输入/失焦/归零、实际显示时间和三语窗口复用。
- Release 0.1.6 构建及严格签名校验通过，已启动。通过真实菜单栏打开设置，尺寸 560 × 752，帮助页和窗口重开均正常；已检查实际设置底部截图。
- 真实应用中通过辅助功能按下自启动开关：未启用 → 系统返回已启用 → 关闭并重开设置仍显示已启用 → 再次按下回到未启用。两个滑块和两个输入框值前后一致，结束恢复原来的关闭状态。
- 验证脚本首次用关闭前的窗口辅助功能句柄比较编辑器，导致误报控件列表为空；改为读取重开后的窗口句柄后通过。没有将此脚本误报当作应用偏移变化。
- 未实际注销、重启系统或执行需系统批准的真实拒绝/恢复流程；待批准和错误分支由替身验证。当前 ad-hoc 签名构建的注册成功不能替代正式签名分发或其他 macOS 版本验收。

证据：[登录项设置截图](artifacts/settings-login.png)、[真实注册/取消日志](artifacts/login-item-verification.log)、[设置窗口验证](artifacts/settings-verification.log)、[普通测试](artifacts/unit-test.log)、[原生交互回归](artifacts/native-ui-test.log)、[Release 构建](artifacts/build-app.log)。

## 0.1.5 多语言与即时切换（2026-10-22）

- 设置 → 自动切换新增语言选项：跟随系统、简体中文、繁體中文、English。选择保存在本机，立即作用于菜单栏、设置窗口标题、城市名称、日期格式、偏移提示、状态/错误提示和完整使用说明。
- 使用三套 `.lproj/Localizable.strings` 资源，完整性与格式占位符测试通过；系统匹配覆盖 zh-CN/SG、zh-TW/HK、Hans/Hant 脚本、英语和不支持语言的英语回退。
- 状态与应用错误以语义状态保存，显示时按当前语言生成；切换语言不会重算调度、重置城市/偏移或重新执行外观请求。普通测试和启用自动模式的原生窗口测试均验证了这一点。
- 普通测试 35 项通过，原生交互测试 1 项按默认配置跳过，汇总显示 36 项。独立执行原生交互测试通过（11.151 秒），回归了滑块/输入、窗口复用、三语标题和已编辑偏移保留。
- 通过实际设置窗口的语言下拉框依次选择 English、繁體中文、简体中文，确认即时更新设置标题、时间/城市表示、菜单栏和说明页，已保存各语言实际截图。结束后恢复原来的「跟随系统」选择。
- 暂时移开 Release 构建目录中的资源 bundle 后启动并完成上述实际验证，证明 `.app` 从自身 Contents/Resources 读取翻译资源；随后已恢复构建目录。应用包含三套系统隐私用途说明资源，系统授权弹窗语言仍由 macOS 选择。
- Release 0.1.5 构建与严格签名校验通过，已运行。真实自动化授权、实际睡眠唤醒及其他 macOS 版本的先前验收边界仍适用。

证据：[英语设置](artifacts/settings-en.png)、[英语菜单栏](artifacts/menu-bar-en.png)、[繁体中文设置](artifacts/settings-zh-Hant.png)、[简体中文设置](artifacts/settings-zh-Hans.png)、[英语说明页](artifacts/settings-en-help.png)、[实际语言切换日志](artifacts/language-verification.log)、[普通测试](artifacts/unit-test.log)、[原生交互测试](artifacts/native-ui-test.log)。

## 0.1.4 独立设置窗口与精简菜单栏（2026-10-22）

- 菜单栏缩减为 320 × 240，保留自动切换开关、城市/下次切换摘要、状态、设置与退出。
- 独立设置窗口包含「自动切换」「使用说明」两页，集中城市、两个偏移控件、原始/偏移后时间、检查/权限重试，以及完整说明。窗口按需创建并复用，与菜单栏共享同一个 AppModel 和已有偏好。
- 普通测试 30 项通过，1 项原生交互测试默认跳过；汇总 31 项。菜单栏普通和压缩尺寸建议下均为 320 × 240。
- 原生交互测试独立执行通过（10.437 秒）：通过生产窗口控制器打开设置，验证四向拖动、数值输入、失焦、边界、归零、截图中的切换时间，以及关闭后重开同一窗口和模型共享。
- 实际菜单栏连续打开/关闭三次均为 320 × 240，确认没有城市选择器、滑块或输入框，保留设置入口。
- 通过真实菜单栏的「设置…」按钮打开设置窗口，确认菜单自动收起、设置为 560 × 752（含系统标题栏）、两组偏移控件和切换时间可访问；成功切换说明页并读取使用和隐私说明。
- 关闭真实设置窗口后从菜单重新打开，确认只有一个设置窗口，并正常返回自动切换页。
- Release 0.1.4 构建、签名严格校验通过，已启动；已检查菜单栏与设置窗口实际截图。

证据：[精简菜单栏截图](artifacts/menu-bar-compact.png)、[实际设置窗口截图](artifacts/settings-panel.png)、[设置控件交互截图](artifacts/settings-interaction.png)、[菜单验证日志](artifacts/menu-bar-verification.log)、[设置入口/说明页验证日志](artifacts/settings-verification.log)、[原生控件测试日志](artifacts/native-ui-test.log)。

## 0.1.3 菜单栏面板高度修复（2026-10-22）

- 用户报告真实菜单栏弹出后只剩一条横条。修复前通过本应用的菜单栏辅助功能项目实际打开，测得弹出面板为 390 × 10。
- 原因：ScrollView 根视图只有最大高度，没有明确的视口高度。普通 NSHostingView 的理想高度是 670，但压缩高度建议下 NSHostingController 返回 390 × 1；之前固定 720 高的测试窗口掩盖了这一问题。
- 修复：给面板明确的宽度和高度。标准高度为 720，根据所在屏幕可用高度缩减，内容保留滚动。新增未指定父高度、压缩高度建议和小屏幕高度回归检查。
- 普通测试 30 项通过，原生窗口交互测试 1 项按默认配置跳过；汇总显示 31 项。
- 已构建、签名校验并启动 0.1.3。通过真实菜单栏项目反复打开面板三次，每次测得 390 × 720，均找到两个滑块、两个输入框及两项偏移后切换时间标签。
- 已检查实际菜单栏弹出面板截图，内容、控件和底部按钮完整显示。本轮实际弹出层检查补充了 0.1.2 测试窗口未覆盖的菜单栏尺寸场景。

证据：[真实菜单栏面板截图](artifacts/menu-bar-fixed.png)、[实际弹出层验证日志](artifacts/menu-bar-verification.log)、[含布局回归的测试日志](artifacts/unit-test.log)。

## 0.1.2 实际控件验收与偏移后时间（2026-10-22）

- 界面新增「日出转亮」「日落转暗」，显示调度器给出的实际切换日期/时间；被边界规则跳过时显示「本次已跳过」，无天文事件时显示无日出/无日落。
- 有效文本输入会立即更新滑块预览，回车或失焦后才应用调度；滑块松开后更新输入框和已保存偏移。
- 普通测试：28 项通过，1 项原生 UI 测试按默认配置跳过。Swift Testing 汇总显示 29 项，不能将跳过项计作已执行。
- 单独执行 `DUSK_SHIFT_UI_TESTS=1 bash scripts/test.sh --filter NativeInteractionTests`：1 项完整原生交互测试通过（14.005 秒），包括真实鼠标事件、原生文本编辑/回车、控件增减动作和自身窗口截图核对。
- 实际观察到日出左拖 +72、右拖 −72，日落左拖 +72、右拖 −72，输入框与已保存偏移一致。配合方向调度测试，分别对应日出左暗右亮、日落左亮右暗。
- 输入 −37 / +42、有效输入未提交时预览、失焦提交 +25、999 限制到 +120、abc 不改变计划，以及鼠标点击两个归零按钮均通过。归零后两个输入框为 0，两个滑块均回到正中。
- 截图与本地 Vision 识别确认上海 2026-10-22：日出 06:01，提前 37 分钟后转亮 05:24；日落 17:15，延后 42 分钟后转暗 17:57。
- 验收宿主是临时原生窗口，加载与菜单栏相同的生产 `MenuContent` 视图，使用临时偏好并保持自动切换关闭。未修改用户偏移或系统外观；结束后清理临时偏好并恢复光标。
- 仍未覆盖菜单栏弹出层的打开/定位、真实系统自动化授权、实际合盖唤醒及其他 macOS 版本。以下旧版本的视觉/控件未验收记录已由本轮对应项目补充。

证据：[窗口截图](artifacts/ui-verification.png)、[原生交互完整日志](artifacts/native-ui-test.log)、[普通测试日志](artifacts/unit-test.log)。

## 0.1.1 双偏移更新（2026-10-22）

- 日出、日落独立 ±120 分钟偏移；居中零位滑块与精确整数输入框。
- 方向验证：日出左暗右亮，日落左亮右暗。两条滑块向左均延后对应切换，向右均提前；输入框保留负数提前、正数延后的时间语义。
- `bash scripts/test.sh`：4 个套件、28 项测试全部通过。新增双偏移组合边界、四个方向的外观结果、短夜使用调整后日出边界、241 个分钟值的滑块往返映射、输入校验与截断、旧日落配置兼容和日出配置恢复。
- Release 构建、打包、签名严格校验及 plist 检查通过；版本号 0.1.1。
- 已关闭本项目旧进程并启动新版，确认新版进程保持运行。
- 本轮未进行人工拖动、键盘输入和布局的视觉验收；系统真实授权、实际睡眠唤醒等先前列出的实机限制仍适用。

## 0.1.0 初始记录

日期：2026-10-22。

环境：macOS 26.5.1（25F80）、x86_64、Apple Swift 6.3.2、Command Line Tools。应用部署目标 macOS 13。

## 已通过

- `bash scripts/test.sh`：3 个测试套件、22 项测试全部通过。
- 天文计算：赤道春分与北京夏至的分钟级参考值；全部 14 个城市全年逐月交点前后昼夜变化；特罗姆瑟全年逐日扫描；南半球季节；极昼极夜；日期变更线、闰日、夏令时和跨年日期归属。
- 调度：−120～+120 分钟边界、日出不偏移、跨当地午夜、延后越过下一日出时跳过短夜、城市变更、睡过多个事件后的目标状态、极昼极夜的后续重算。
- 应用协调：注入时钟与替身外观控制器，验证实际唤醒通知回调、默认关闭时无写入和定时任务、权限拒绝后的抑制及重试、短暂错误的有限重试、并发请求串行化和过期配置纠正、本地偏好读写。
- `bash scripts/build-app.sh`：Release 编译、`.app` 打包和 ad-hoc 签名通过。
- `codesign --verify --deep --strict`：应用签名结构有效；确认包含 Apple Events entitlement。
- `plutil -lint`：Info.plist 与 entitlements 有效；`bash -n`：构建和测试脚本语法有效。
- 从外观控制器源码提取 AppleScript，以 true/false 两个目标分别使用 `osacompile` 编译通过；未执行系统外观更改。
- 使用 `open` 启动 `dist/Dusk Shift.app` 成功，随后确认对应进程仍在运行。
- 本机构建包约 324 KB，为 x86_64 架构。

## 修复的回归

初始日出日落迭代公式在特罗姆瑟进入和离开极昼附近漏掉两次交点。改为对太阳高度求根，并加入日内极值点分隔；全年扫描测试通过。

## 环境适配

编译缓存改到项目 `.build` 目录，避开用户目录写权限限制。当前 CLT 不提供 XCTest，改用随工具链附带的 Swift Testing，并为该 CLT 布局补充 framework 与运行库查找路径。

当前 Testing 框架最低版本是 macOS 14，测试链接时有最低版本提示；不影响应用的独立 Release 构建。macOS 13 真机兼容性尚未验证。

## 尚未验证

- 用户授权后的全局外观实际变化、真实 TCC 拒绝/撤销/重新授权；自动化测试使用替身，不代表真实授权流程已通过。
- 实际睡眠/合盖、跨日唤醒的端到端恢复；目前通过通知注入与时间跳转测试验证协调逻辑。
- 菜单栏视觉布局的人工验收。
- 断网实机操作、长时间运行及 Energy Impact/CPU/内存稳定性。运行代码没有外部 API 请求路径，但没有把这一静态事实当作断网实测。
- Apple Silicon、其他 macOS 版本，以及 Developer ID 签名、公证与正式分发。

应用已启动，默认自动切换关闭。真实系统验收步骤见 README；请先关闭 macOS 自带的自动外观计划，再在 Dusk Shift 中启用并授权。
