.DEFAULT_GOAL := help
.PHONY: help build run test test-sliders test-ui test-ui-layout test-appearance-mode test-ui-mode test-transitions test-ui-transitions

help:
	@printf '%s\n' 'make build                     构建并签名 dist/Dusk Shift.app（请先退出运行中的旧版）' 'make run                       打开已构建的应用' 'make test FILTER=SuiteOrTest    只运行指定套件或测试；必须提供 FILTER' 'make test-sliders              只验证滑块渐变渲染（深浅模式）' 'make test-ui                   只验证滑块与输入框交互并截图（需要辅助功能及屏幕录制权限）' 'make test-ui-layout            只验证菜单栏和设置的深浅外观、语言与滚动布局并截图' 'make test-appearance-mode      只验证外观模式、请求协调及相关布局' 'make test-ui-mode              只验证托盘与设置三段切换及同步' 'make test-transitions          只验证切换动画触发、实际外观结果与请求协调' 'make test-ui-transitions       只验证居中半屏日月过渡、动画开关及释放'

build:
	bash scripts/build-app.sh

run:
	@test -d "dist/Dusk Shift.app" || { printf '%s\n' '请先执行 make build'; exit 1; }
	open "dist/Dusk Shift.app"

test:
	@test -n "$(strip $(FILTER))" || { printf '%s\n' '必须指定测试范围，例如 make test FILTER=GradientSliderTests'; exit 1; }
	bash scripts/test.sh --filter "$(FILTER)"

test-sliders:
	$(MAKE) test FILTER=GradientSliderTests

test-ui:
	@mkdir -p artifacts
	DUSK_SHIFT_UI_TESTS=1 DUSK_SHIFT_SLIDER_TESTS_ONLY=1 DUSK_SHIFT_UI_OUTPUT="$(CURDIR)/artifacts/slider-interaction.png" bash scripts/test.sh --filter NativeInteractionTests

test-ui-layout:
	@mkdir -p artifacts/ui-0.1.13
	DUSK_SHIFT_VISUAL_TESTS=1 DUSK_SHIFT_VISUAL_OUTPUT="$(CURDIR)/artifacts/ui-0.1.13" bash scripts/test.sh --filter UIAppearanceTests

test-appearance-mode:
	$(MAKE) test FILTER='AppearanceModeTests|SystemAppearanceSettingsTests|SettingsPresentationTests/offsetOnlyPublishesEditedSectionAndTimeTextDuringAndAfterVerification|MenuLayoutTests'

test-ui-mode:
	@mkdir -p artifacts/appearance-mode-0.1.15
	DUSK_SHIFT_MODE_UI_TESTS=1 DUSK_SHIFT_MODE_UI_OUTPUT="$(CURDIR)/artifacts/appearance-mode-0.1.15" bash scripts/test.sh --filter AppearanceModeInteractionTests


test-transitions:
	$(MAKE) test FILTER='AppearanceTransitionTests|SettingsPresentationTests/offsetOnlyPublishesEditedSectionAndTimeTextDuringAndAfterVerification'

test-ui-transitions:
	@mkdir -p artifacts/appearance-transition-0.1.17
	DUSK_SHIFT_TRANSITION_UI_TESTS=1 DUSK_SHIFT_TRANSITION_UI_OUTPUT="$(CURDIR)/artifacts/appearance-transition-0.1.17" bash scripts/test.sh --filter AppearanceTransitionInteractionTests
