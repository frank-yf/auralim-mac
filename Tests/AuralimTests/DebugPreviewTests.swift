import AppKit
import SwiftUI
import Testing
import AuralimCore
@testable import Auralim

@MainActor
private final class PreviewCountdown: CountdownPresenting {
    var seconds: Int?
    var finish: (@MainActor () -> Void)?
    var cancel: (@MainActor () -> Void)?
    var tick: (@MainActor (Int) -> Void)?
    func start(seconds: Int, target: Appearance, localizer: Localizer, tick: @escaping @MainActor (Int) -> Void,
               finish: @escaping @MainActor () -> Void, cancel: @escaping @MainActor () -> Void) {
        self.seconds = seconds; self.finish = finish; self.cancel = cancel; self.tick = tick
    }
    func stop() { seconds = nil; finish = nil; cancel = nil; tick = nil }
}
@MainActor
private final class PreviewAnimation: AppearanceTransitionPlaying {
    var targets: [Appearance] = []
    var completion: (@MainActor () -> Void)?
    var beforePlay: (() -> Void)?
    func play(_ appearance: Appearance, title: String, completion: @escaping @MainActor () -> Void) {
        beforePlay?(); targets.append(appearance); self.completion = completion
    }
    func stop() { completion = nil }
}
private final class PreviewAppearance: AppearanceApplying {
    var current: Appearance = .light
    var targets: [Appearance] = []
    var failure: AppearanceFailure?
    var beforeApply: (() -> Void)?
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        beforeApply?(); targets.append(appearance)
        if let failure { completion(.failure(failure)); return }
        let changed = current != appearance; current = appearance
        completion(.success(.init(changed: changed)))
    }
}
@MainActor
private final class PreviewFixture {
    let suite = "Auralim.Debug.\(UUID().uuidString)"
    let defaults: UserDefaults
    let countdown = PreviewCountdown()
    let animation = PreviewAnimation()
    let appearance = PreviewAppearance()
    let workspace = NotificationCenter()
    let realCountdown = PreviewCountdown()
    let realAnimation = PreviewAnimation()
    let debug: DebugPreviewController
    var model: AppModel!
    init(countdown: CountdownPresenting? = nil, animation: AppearanceTransitionPlaying? = nil) {
        defaults = UserDefaults(suiteName: suite)!
        defaults.set("zh-Hans", forKey: "language")
        defaults.set("Asia/Shanghai", forKey: "city")
        debug = DebugPreviewController(defaults: defaults, countdown: countdown ?? self.countdown,
            animation: animation ?? self.animation)
        model = AppModel(defaults: defaults, controller: appearance, clock: { ISO8601DateFormatter().date(from: "2026-10-22T04:00:00Z")! }, enableTimers: false,
            workspaceNotifications: workspace, systemNotifications: NotificationCenter(), appearanceNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(),
            systemSettings: { [appearance] in .init(mode: appearance.current == .light ? .light : .dark, appearance: appearance.current) },
            transitionPlayer: realAnimation, desktopReady: { true },
            countdownPresenter: realCountdown, debugPreview: debug)
    }
    func close() { model.shutdown(); defaults.removePersistentDomain(forName: suite) }
}

@MainActor
@Suite(.serialized, .enabled(if: BuildFeatures.debugToolsEnabled))
struct DebugPreviewTests {
    @Test func defaultsOffAndEnablingOnlyPersistsPreference() {
        let f = PreviewFixture(); defer { f.close() }
        #expect(!f.debug.enabled)
        f.model.previewDebug(.sequence, target: .dark)
        #expect(f.debug.phase == .idle)
        f.debug.enabled = true
        #expect(f.defaults.bool(forKey: "debugModeEnabled") && f.debug.phase == .idle)
        let restored = DebugPreviewController(defaults: f.defaults)
        #expect(restored.enabled && restored.phase == .idle)
        #expect(f.appearance.targets.isEmpty)
    }
    @Test func countdownOnlyUsesConfiguredSecondsAndNeverChangesAppearance() {
        let f = PreviewFixture(); defer { f.close() }; f.debug.enabled = true
        f.model.countdownSeconds = 23
        f.model.previewDebug(.countdown, target: .dark)
        #expect(f.countdown.seconds == 23 && f.debug.phase == .countdown(.dark))
        f.countdown.tick?(12); #expect(f.debug.remaining == 12)
        f.countdown.finish?()
        #expect(f.debug.phase == .idle && f.animation.targets.isEmpty)
        #expect(f.appearance.targets.isEmpty && f.model.currentSystemAppearance == .light)
        #expect(!f.model.countdownEnabled && !f.model.transitionAnimationEnabled)
    }
    @Test func directAnimationSupportsBothDirectionsRegardlessOfNormalAnimationPreference() {
        let f = PreviewFixture(); defer { f.close() }; f.debug.enabled = true
        f.model.previewDebug(.animation, target: .light)
        #expect(f.debug.phase == .animation(.light) && f.animation.targets == [.light])
        f.animation.completion?(); #expect(f.debug.phase == .idle)
        f.model.previewDebug(.animation, target: .dark)
        f.animation.completion?()
        #expect(f.animation.targets == [.light, .dark] && f.appearance.targets.isEmpty)
    }
    @Test func fullSequenceReleasesCountdownBeforeAnimationAndDoesNotApply() {
        let f = PreviewFixture(); defer { f.close() }; f.debug.enabled = true
        f.animation.beforePlay = { #expect(f.countdown.seconds == nil) }
        f.model.previewDebug(.sequence, target: .dark)
        #expect(f.animation.targets.isEmpty)
        f.countdown.finish?()
        #expect(f.debug.phase == .animation(.dark) && f.debug.remaining == nil)
        f.animation.completion?()
        #expect(f.debug.phase == .idle && f.appearance.targets.isEmpty)
    }
    @Test func stopDisableAndReplacementIgnoreStaleCallbacks() throws {
        let f = PreviewFixture(); defer { f.close() }; f.debug.enabled = true
        f.model.previewDebug(.sequence, target: .dark)
        let old = try #require(f.countdown.finish), tick = try #require(f.countdown.tick)
        f.model.previewDebug(.animation, target: .light)
        old(); tick(1)
        #expect(f.debug.phase == .animation(.light) && f.animation.targets == [.light] && f.debug.remaining == nil)
        let animationDone = try #require(f.animation.completion)
        f.debug.enabled = false; animationDone()
        #expect(f.debug.phase == .idle && f.animation.completion == nil)
        f.debug.enabled = true; f.model.previewDebug(.sequence, target: .dark)
        f.countdown.cancel?()
        #expect(f.debug.phase == .idle && f.appearance.targets.isEmpty)
    }
    @Test func normalReconciliationKeepsPreviewButRealSwitchTakesPriority() {
        let f = PreviewFixture(); defer { f.close() }; f.debug.enabled = true
        f.model.previewDebug(.sequence, target: .dark)
        f.model.reconcile()
        #expect(f.debug.phase == .countdown(.dark))
        f.appearance.beforeApply = { #expect(f.debug.phase == .idle && f.countdown.seconds == nil) }
        f.model.selectAppearanceMode(.dark)
        #expect(f.debug.phase == .idle && f.appearance.targets == [.dark])
    }
    @Test func sleepLockWakeAndShutdownStopPreviews() throws {
        let f = PreviewFixture(); defer { f.close() }; f.debug.enabled = true
        for event in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                      NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification] {
            f.debug.preview(.sequence, target: .dark, seconds: 10, localizer: f.model.localizer)
            let stale = try #require(f.countdown.finish)
            f.workspace.post(name: event, object: nil); stale()
            #expect(f.debug.phase == .idle && f.countdown.seconds == nil)
        }
        f.debug.preview(.animation, target: .dark, seconds: 10, localizer: f.model.localizer)
        let old = f.animation.completion
        f.model.shutdown(); old?()
        #expect(f.debug.phase == .idle && f.appearance.targets.isEmpty)
    }
    @Test func inFlightSystemRequestRejectsDebugPreview() {
        let f = PreviewFixture(); defer { f.close() }; f.debug.enabled = true
        // Model gating is also checked during a real request by the apply hook.
        f.appearance.beforeApply = {
            f.model.previewDebug(.animation, target: .light)
            #expect(f.debug.phase == .idle)
        }
        f.model.selectAppearanceMode(.dark)
        #expect(f.animation.targets.isEmpty)
    }

    @Test func realCountdownAndAnimationRejectPreviewUntilCompletion() {
        let f = PreviewFixture(); defer { f.close() }; f.debug.enabled = true
        f.model.countdownEnabled = true
        f.appearance.current = .dark
        f.model.selectAppearanceMode(.automatic)
        #expect(!f.model.canPreviewDebug && f.realCountdown.seconds == 10)
        f.model.previewDebug(.sequence, target: .light)
        #expect(f.countdown.seconds == nil && f.debug.phase == .idle)
        f.realCountdown.finish?()
        #expect(f.appearance.current == .light && f.model.canPreviewDebug)
        f.model.countdownEnabled = false; f.model.transitionAnimationEnabled = true
        f.model.selectAppearanceMode(.dark)
        #expect(!f.model.canPreviewDebug && f.realAnimation.targets == [.dark])
        f.model.previewDebug(.animation, target: .dark)
        #expect(f.animation.targets.isEmpty)
        f.realAnimation.completion?()
        #expect(f.model.canPreviewDebug && f.appearance.current == .dark)
    }

    @Test func previewDoesNotAlterAutomaticScheduleOrAppearancePreferences() {
        let f = PreviewFixture(); defer { f.close() }; f.debug.enabled = true
        f.model.selectAppearanceMode(.automatic)
        let check = f.model.scheduledCheck, requests = f.appearance.targets
        f.model.previewDebug(.sequence, target: .dark)
        f.countdown.finish?(); f.animation.completion?()
        #expect(f.model.enabled && f.model.manualAppearance == nil && f.model.scheduledCheck == check)
        #expect(f.appearance.targets == requests && !f.model.countdownEnabled && !f.model.transitionAnimationEnabled)
    }

    @Test func reducedMotionPreviewFinishesWithoutSystemRequest() {
        let animation = AppearanceTransitionController(reduceMotion: { true })
        let f = PreviewFixture(animation: animation); defer { f.close() }; f.debug.enabled = true
        f.model.previewDebug(.animation, target: .dark)
        #expect(f.debug.phase == .idle && animation.panel == nil && f.appearance.targets.isEmpty)
    }

    @Test func optInDefaultsOffAndResetsOnRestartOrDisable() {
        let f = PreviewFixture(); defer { f.close() }; f.debug.enabled = true
        #expect(!f.debug.applyAppearanceAfterPreview)
        f.debug.applyAppearanceAfterPreview = true
        let restored = DebugPreviewController(defaults: f.defaults)
        #expect(!restored.applyAppearanceAfterPreview)
        f.debug.enabled = false
        #expect(!f.debug.applyAppearanceAfterPreview)
    }

    @Test func enabledFullPreviewAppliesOnceAfterReleaseAndEntersManualMode() {
        let f = PreviewFixture(); defer { f.close() }; f.debug.enabled = true
        f.model.selectAppearanceMode(.automatic)
        f.model.countdownEnabled = true; f.model.transitionAnimationEnabled = true
        f.debug.applyAppearanceAfterPreview = true
        let initialRequests = f.appearance.targets
        f.appearance.beforeApply = {
            #expect(f.debug.phase == .idle && f.countdown.seconds == nil && f.animation.completion == nil)
        }
        f.model.previewDebug(.sequence, target: .dark)
        #expect(f.appearance.targets == initialRequests)
        f.countdown.finish?()
        #expect(f.appearance.targets == initialRequests)
        f.animation.completion?()
        #expect(f.appearance.targets == initialRequests + [.dark] && f.appearance.current == .dark)
        #expect(f.model.appearanceMode == .dark && !f.model.enabled && f.model.currentSystemAppearance == .dark)
        #expect(f.realCountdown.seconds == nil && f.realAnimation.targets.isEmpty)
    }

    @Test func directAnimationAndCountdownCanApplyBothDirections() {
        let f = PreviewFixture(); defer { f.close() }; f.debug.enabled = true
        f.debug.applyAppearanceAfterPreview = true
        f.model.previewDebug(.animation, target: .dark); f.animation.completion?()
        #expect(f.appearance.targets == [.dark])
        f.model.previewDebug(.countdown, target: .light); f.countdown.finish?()
        #expect(f.appearance.targets == [.dark, .light] && f.model.appearanceMode == .light)
    }

    @Test func cancellationAndTurningOptInOffPreventSystemChange() throws {
        let f = PreviewFixture(); defer { f.close() }; f.debug.enabled = true
        f.debug.applyAppearanceAfterPreview = true
        f.model.previewDebug(.sequence, target: .dark)
        let stale = try #require(f.countdown.finish)
        f.debug.stop(); stale()
        #expect(f.appearance.targets.isEmpty)
        f.model.previewDebug(.animation, target: .dark)
        f.debug.applyAppearanceAfterPreview = false
        f.animation.completion?()
        #expect(f.appearance.targets.isEmpty)
    }

    @Test func failedDebugApplyUsesExistingErrorAndRetryState() {
        let f = PreviewFixture(); defer { f.close() }; f.debug.enabled = true
        f.debug.applyAppearanceAfterPreview = true
        f.appearance.failure = .init(message: "Denied", permissionDenied: true)
        f.model.previewDebug(.sequence, target: .dark)
        f.countdown.finish?(); f.animation.completion?()
        #expect(f.model.errorMessage != nil && f.model.currentSystemAppearance == .light)
        f.model.reconcile()
        #expect(f.appearance.targets == [.dark] && f.debug.phase == .idle)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_DEBUG_UI_TESTS"] == "1"))
    func nativeOptInAppliesOnlyAfterBothPanelsAreReleased() async throws {
        _ = NSApplication.shared
        let countdown = CountdownController(preview: true)
        let animation = AppearanceTransitionController(reduceMotion: { false }, duration: 0.15)
        let f = PreviewFixture(countdown: countdown, animation: animation); defer { f.close() }; f.debug.enabled = true
        f.debug.applyAppearanceAfterPreview = true
        f.appearance.beforeApply = { #expect(countdown.panel == nil && animation.panel == nil) }
        f.model.previewDebug(.sequence, target: .dark)
        #expect(countdown.panel?.isVisible == true && f.appearance.targets.isEmpty)
        countdown.complete()
        #expect(animation.panel?.isVisible == true && f.appearance.targets.isEmpty)
        try await Task.sleep(for: .milliseconds(300))
        #expect(f.appearance.targets == [.dark] && f.model.currentSystemAppearance == .dark)
        #expect(countdown.panel == nil && animation.panel == nil && f.debug.phase == .idle)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_DEBUG_UI_TESTS"] == "1"))
    func nativeFullSequenceReleasesPanelsWithoutChangingAppearance() async throws {
        _ = NSApplication.shared
        let countdown = CountdownController(preview: true)
        let animation = AppearanceTransitionController(reduceMotion: { false }, duration: 0.15)
        let f = PreviewFixture(countdown: countdown, animation: animation); defer { f.close() }; f.debug.enabled = true
        f.model.previewDebug(.sequence, target: .light)
        let panel = try #require(countdown.panel)
        #expect(panel.title == f.model.t("debug.countdown") && animation.panel == nil)
        countdown.complete()
        #expect(countdown.panel == nil && panel.contentView == nil && animation.panel?.isVisible == true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(animation.panel == nil && f.debug.phase == .idle && f.appearance.targets.isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_DEBUG_UI_TESTS"] == "1"))
    func settingsButtonsAndNativePreviewSequence() throws {
        let app = NSApplication.shared; app.setActivationPolicy(.regular); app.finishLaunching()
        let countdown = CountdownController(preview: true)
        let animation = PreviewAnimation()
        let f = PreviewFixture(countdown: countdown, animation: animation); defer { f.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: DebugSettingsView(model: f.model, preview: f.debug)
            .frame(width: 552).padding(14).frame(width: 580, height: 270, alignment: .topLeading).background(DuskStyle.background)))
        window.isReleasedWhenClosed = false; window.setContentSize(NSSize(width: 580, height: 270))
        window.center(); window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        defer { window.close() }
        func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15)) }
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        settle()
        let content = try #require(window.contentView)
        let toggle = try #require(views(content).compactMap { $0 as? NSSwitch }.first)
        _ = toggle.accessibilityPerformPress(); settle()
        #expect(f.debug.enabled)
        let picker = try #require(views(window.contentView!).compactMap { $0 as? NSSegmentedControl }.first)
        picker.selectedSegment = 1; #expect(picker.sendAction(picker.action, to: picker.target)); settle()
        // SwiftUI buttons are drawn by the hosting view. Use native mouse events.
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AURALIM_DEBUG_UI_OUTPUT"] ?? "/private/tmp/auralim-debug-ui")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func capture(_ name: String) throws {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.appendingPathComponent(name + ".png").path]
            try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
        }
        for theme in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: theme); settle()
            try capture(theme == .aqua ? "debug-light" : "debug-dark")
        }
        func click(_ x: CGFloat) throws {
            for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: kind, location: NSPoint(x: x, y: 119), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                app.sendEvent(event)
            }
            settle()
        }
        try click(65) // Countdown button.
        #expect(countdown.panel?.isVisible == true && f.debug.phase == .countdown(.dark))
        try click(520) // Stop preview.
        #expect(countdown.panel == nil && f.debug.phase == .idle)
        try click(143) // Animation button.
        #expect(animation.targets == [.dark] && f.debug.phase == .animation(.dark))
        try click(520)
        #expect(f.debug.phase == .idle)
        try click(215) // Full sequence button.
        let panel = try #require(countdown.panel)
        #expect(panel.isVisible && f.debug.phase == .countdown(.dark))
        countdown.complete()
        #expect(countdown.panel == nil && animation.targets == [.dark, .dark] && f.appearance.targets.isEmpty)
        animation.completion?(); settle(); #expect(f.debug.phase == .idle)
        picker.selectedSegment = 0; #expect(picker.sendAction(picker.action, to: picker.target)); settle()
        try click(143)
        #expect(animation.targets == [.dark, .dark, .light])
        animation.completion?(); settle()
        let switches = views(content).compactMap { $0 as? NSSwitch }
        let applySwitch = try #require(switches.first { $0 !== toggle })
        #expect(applySwitch.state == .off && !f.debug.applyAppearanceAfterPreview)
        _ = applySwitch.accessibilityPerformPress(); settle()
        #expect(f.debug.applyAppearanceAfterPreview)
        try capture("debug-apply-on")
        picker.selectedSegment = 1; #expect(picker.sendAction(picker.action, to: picker.target)); settle()
        try click(215); countdown.complete()
        #expect(f.appearance.targets.isEmpty)
        animation.completion?(); settle()
        #expect(f.appearance.targets == [.dark] && f.model.currentSystemAppearance == .dark)
        _ = toggle.accessibilityPerformPress(); settle()
        #expect(!f.debug.enabled && !f.debug.applyAppearanceAfterPreview && f.debug.phase == .idle)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_DEBUG_UI_TESTS"] == "1"))
    func sharedPanelActionsRespectPreviewSwitchAndAcknowledgement() throws {
        let app = NSApplication.shared; app.setActivationPolicy(.regular); app.finishLaunching()
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AURALIM_DEBUG_UI_OUTPUT"] ?? "/private/tmp/auralim-shared-buttons")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for apply in [false, true] {
            var now: TimeInterval = 100
            let countdown = CountdownController(now: { now }, preview: true)
            let f = PreviewFixture(countdown: countdown); defer { f.close() }; f.debug.enabled = true
            f.debug.applyAppearanceAfterPreview = apply
            f.appearance.beforeApply = { #expect(countdown.panel == nil && f.animation.completion == nil) }
            func click(_ x: CGFloat) throws {
                let panel = try #require(countdown.panel)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
                for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = try #require(NSEvent.mouseEvent(with: kind, location: NSPoint(x: x, y: 45), modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                        context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                    app.sendEvent(event)
                }
            }
            f.model.previewDebug(.sequence, target: .dark)
            let visible = try #require(countdown.panel)
            for theme in [NSAppearance.Name.aqua, .darkAqua] {
                visible.appearance = NSAppearance(named: theme)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-o", "-l", String(visible.windowNumber), output.appendingPathComponent("shared-buttons-\(apply)-\(theme == .aqua ? "light" : "dark").png").path]
                try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
            }
            try click(65) // Skip this switch must cancel, even when actual switching is enabled.
            #expect(countdown.panel == nil && f.debug.phase == .idle && f.appearance.targets.isEmpty)
            f.model.previewDebug(.sequence, target: .dark)
            try click(215) // Got it releases only the panel.
            #expect(countdown.panel == nil && f.debug.phase == .countdown(.dark) && f.debug.remaining == 10)
            now += 10; countdown.update()
            #expect(f.debug.phase == .animation(.dark) && f.appearance.targets.isEmpty)
            f.animation.completion?()
            #expect(f.debug.phase == .idle && f.appearance.targets == (apply ? [.dark] : []))
            f.model.previewDebug(.sequence, target: .light)
            try click(275) // Switch now skips the wait, but still waits for the animation.
            #expect(countdown.panel == nil && f.debug.phase == .animation(.light))
            #expect(f.appearance.targets == (apply ? [.dark] : []))
            f.animation.completion?()
            #expect(f.debug.phase == .idle && f.appearance.targets == (apply ? [.dark, .light] : []))
        }
    }

}
