.DEFAULT_GOAL := help
.PHONY: help build run test test-sliders test-ui test-ui-layout

help:
	@printf '%s\n' 'make build                     构建并签名 dist/Dusk Shift.app（请先退出运行中的旧版）' 'make run                       打开已构建的应用' 'make test FILTER=SuiteOrTest    只运行指定套件或测试；必须提供 FILTER' 'make test-sliders              只验证滑块渐变渲染（深浅模式）' 'make test-ui                   只验证滑块与输入框交互并截图（需要辅助功能及屏幕录制权限）' 'make test-ui-layout            只验证菜单栏和设置的深浅外观、语言与滚动布局并截图'

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
