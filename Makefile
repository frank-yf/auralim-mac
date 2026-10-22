.DEFAULT_GOAL := help
.PHONY: help build icon run clean test test-sliders test-ui test-ui-layout test-appearance-mode test-ui-mode test-transitions test-ui-transitions prepare-update test-updates test-update-install test-update-ui test-update-quit test-update-signature test-localization-ui

help:
	@printf '%s\n' 'make build                     构建并签名 dist/Auralim.app（请先退出运行中的旧版）' 'make prepare-update            为通用版应用生成 GitHub Release 更新包和签名 appcast' 'make test-updates              只验证更新状态、重启入口和多语文案' 'make test-update-ui            验证设置底部真实点击并截图' 'make test-update-install       使用隔离应用验证真实安装与重启' 'make test-update-quit          验证正常退出时安装且不重启' 'make test-update-signature     验证篡改签名清单被拒绝' 'make icon                      从 Resources/Icons/Auralim.png 重新生成应用图标' 'make run                       打开已构建的应用' 'make clean                     删除 dist/、artifacts/ 内的 .app 副本，保留安装包和其他文件' 'make test FILTER=SuiteOrTest    只运行指定套件或测试；必须提供 FILTER' 'make test-sliders              只验证滑块渐变渲染（深浅模式）' 'make test-ui                   只验证滑块与输入框交互并截图（需要辅助功能及屏幕录制权限）' 'make test-localization-ui      验证十二语原生选择、持久化、设置与菜单并截图' 'make test-ui-layout            只验证菜单栏和设置的深浅外观、语言与滚动布局并截图' 'make test-appearance-mode      只验证外观模式、请求协调及相关布局' 'make test-ui-mode              只验证托盘与设置三段切换及同步' 'make test-transitions          只验证切换动画触发、实际外观结果与请求协调' 'make test-ui-transitions       只验证居中半屏日月过渡、动画开关及释放'

build:
	bash scripts/build-app.sh

icon:
	bash scripts/generate-app-icon.sh

run:
	@test -d "dist/Auralim.app" || { printf '%s\n' '请先执行 make build'; exit 1; }
	open "dist/Auralim.app"

clean:
	@set -e; for directory in dist artifacts; do \
		if [ -d "$$directory" ] && [ ! -L "$$directory" ]; then \
			find "$$directory" \( -type d -o -type l \) -name '*.app' -prune -print -exec rm -rf {} +; \
		fi; \
	done

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

prepare-update:
	bash scripts/prepare-update.sh

test-updates:
	$(MAKE) test FILTER='UpdateControllerTests|LocalizationTests/catalogsAreCompleteAndFormatsMatch'

test-update-install:
	python3 scripts/verify-update-install.py

test-update-ui:
	AURALIM_UPDATE_UI_TESTS=1 AURALIM_UPDATE_UI_OUTPUT="$(CURDIR)/artifacts/update-ui-0.3" $(MAKE) test FILTER=UpdateSettingsInteractionTests

test-update-quit:
	python3 scripts/verify-update-install.py --normal-quit

test-update-signature:
	python3 scripts/verify-update-install.py --invalid-feed

test-localization-ui:
	AURALIM_LOCALIZATION_UI_TESTS=1 AURALIM_LOCALIZATION_UI_OUTPUT="$(CURDIR)/artifacts/localization-0.3.1" $(MAKE) test FILTER=LocalizationInteractionTests
