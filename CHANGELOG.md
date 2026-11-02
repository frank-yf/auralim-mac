# Changelog

## 0.5.4 — 2026-11-02

- Run appearance scripts in a cancellable process with a deadline, and independently schedule animation cleanup to prevent a stalled startup switch from blocking later controls.
- In Auto, wait for desktop readiness and probe system appearance with bounded retries before the initial switch. Manual Light/Auto/Dark selections take priority; wake recovery still corrects appearance immediately.
- Add a debug-only read-only system appearance check with cancellation, retry and localized results/errors. It uses the existing System Events Automation permission and never starts a transition or changes appearance.
- Replace Japanese and Korean slogans with sourced excerpts from Ouyang Xiu’s text and retain attribution. Visual verification of the Japanese source scan remains pending.

### 中文

- 外观脚本改为可取消、有超时限制的独立进程；动画独立计时收尾，避免启动切换卡住后阻塞手动操作。
- 自动模式启动时等待桌面就绪并有限重试查询系统外观；手动选择浅色／自动／深色优先，唤醒仍立即校正外观。
- 调试版增加系统外观只读检查，支持取消、重试及多语言结果／错误提示；沿用既有 System Events 自动化权限，不播放动画或修改外观。
- 日语、韩语 slogan 更新为带出处的《醉翁亭记》对应摘句，保留来源说明；日语原始扫描页仍待视觉核对。

## 0.5.3 — 2026-10-30

- Unify menu, settings, countdown and debug layouts, typography and control alignment. Keep branding and version/license information fixed in settings; support minimization and a Dock icon while settings is open.
- Show actual sunrise/sunset in location settings. Simplify offset controls and submit numeric edits when clicking blank space, with Return and Tab support.
- Request the system appearance change when animation motion ends, then hold the final frame for one second. Manual Light/Auto/Dark selections skip the countdown; scheduled switches retain it.
- Add manual/automatic software updates, defaulting to manual while preserving an existing explicit preference.
- Keep cached coordinates active while refreshing or after a failed fix, with manual city fallback. Limit each acquisition to five seconds and add bounded, event-driven recovery after network configuration changes.
- Make `make run` and `make run-debug` quit local development instances, rebuild and launch. Keep build-only targets and installed copies separate.
- Update all twelve UI languages and use Ouyang Xiu’s original sentence for the Chinese slogan.

### 中文

- 统一托盘、设置、倒计时与调试区的组件布局、字级及对齐；品牌区和版本／许可信息固定，设置支持最小化及 Dock 图标。
- 位置区块展示真实日出日落；精简偏移控件，数值支持点击空白提交、回车与 Tab。
- 动画运动结束即申请系统外观切换，末帧停留 1 秒；手动选择浅色／自动／深色均跳过倒计时，计划切换仍保留倒计时。
- 新增手动／自动软件更新，默认手动，保留用户已明确选择的偏好。
- 刷新中或失败后沿用缓存位置，无缓存时回退手动城市；单次获取总时限 5 秒，网络配置变化后有限恢复。
- `make run` 与 `make run-debug` 自动退出项目内旧实例、重新编译并启动，保留仅构建命令。
- 同步十二语文案，中文 slogan 使用欧阳修原句。
