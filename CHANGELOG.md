# Changelog

## 0.5.3 — Unreleased

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

This version is committed locally and has not been pushed or published.
此版本仅在本地提交，尚未推送或发布。
