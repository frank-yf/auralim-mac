import AppKit
import SwiftUI
import AuralimCore
import Testing
@testable import Auralim

private final class CountdownAppearance: AppearanceApplying {
    var current: Appearance = .light
    var requests: [Appearance] = []
    var failure: AppearanceFailure?
    var beforeApply: (() -> Void)?
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        beforeApply?()
        requests.append(appearance)
        if let failure { completion(.failure(failure)); return }
        let changed = current != appearance; current = appearance
        completion(.success(.init(changed: changed)))
    }
}
@MainActor
private final class CountdownPlayer: AppearanceTransitionPlaying {
    var targets: [Appearance] = []
    var completion: (@MainActor () -> Void)?
    var beforePlay: (() -> Void)?
    func play(_ appearance: Appearance, title: String, completion: @escaping @MainActor () -> Void) {
        beforePlay?(); targets.append(appearance); self.completion = completion
    }
    func stop() { completion = nil }
    func finish() { let callback = completion; stop(); callback?() }
}
@MainActor
private final class CountdownPanelFake: CountdownPresenting {
    var starts = 0
    var seconds: Int?
    var tick: (@MainActor (Int) -> Void)?
    var finish: (@MainActor () -> Void)?
    var cancel: (@MainActor () -> Void)?
    func start(seconds: Int, target: Appearance, localizer: Localizer, tick: @escaping @MainActor (Int) -> Void,
               finish: @escaping @MainActor () -> Void, cancel: @escaping @MainActor () -> Void) {
        starts += 1; self.seconds = seconds; self.tick = tick; self.finish = finish; self.cancel = cancel
    }
    func stop() { seconds = nil; tick = nil; finish = nil; cancel = nil }
}
@MainActor
private final class CountdownFixture {
    let suite = "Auralim.Countdown.\(UUID().uuidString)"
    let defaults: UserDefaults
    let appearance = CountdownAppearance()
    let player = CountdownPlayer()
    let panel = CountdownPanelFake()
    let workspace = NotificationCenter()
    var ready = true
    var now = ISO8601DateFormatter().date(from: "2026-10-22T04:00:00Z")!
    var model: AppModel!
    init(presenter: CountdownPresenting? = nil, transition: AppearanceTransitionPlaying? = nil, savedSeconds: Int? = nil) {
        defaults = UserDefaults(suiteName: suite)!
        defaults.set("Asia/Shanghai", forKey: "city")
        defaults.set("zh-Hans", forKey: "language")
        if let savedSeconds { defaults.set(savedSeconds, forKey: "countdownSeconds") }
        model = AppModel(defaults: defaults, controller: appearance, clock: { [unowned self] in now }, enableTimers: false,
            workspaceNotifications: workspace, systemNotifications: NotificationCenter(), appearanceNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(),
            systemSettings: { [unowned self] in .init(mode: appearance.current == .light ? .light : .dark, appearance: appearance.current) },
            transitionPlayer: transition ?? player, desktopReady: { [unowned self] in ready }, wakeAnimationDelay: 0.01,
            countdownPresenter: presenter ?? panel)
    }
    func enable(animation: Bool = true) { model.transitionAnimationEnabled = animation; model.countdownEnabled = true }
    func schedule(_ target: Appearance) {
        now = ISO8601DateFormatter().date(from: target == .dark ? "2026-10-22T14:00:00Z" : "2026-10-23T04:00:00Z")!
        // Simulate a scheduled/automatic event, not an explicit picker selection.
        if model.enabled { model.reconcile() }
        else { model.enabled = true }
    }
    func close() { model.shutdown(); defaults.removePersistentDomain(forName: suite) }
}

@MainActor
@Suite(.serialized)
struct AppearanceCountdownTests {
    @Test func defaultsBoundsAndPersistence() {
        let f = CountdownFixture(); defer { f.close() }
        #expect(!f.model.countdownEnabled && f.model.countdownSeconds == 10)
        f.enable(); #expect(f.defaults.bool(forKey: "countdownEnabled"))
        f.model.countdownSeconds = 999; #expect(f.model.countdownSeconds == 120 && f.defaults.integer(forKey: "countdownSeconds") == 120)
        f.model.countdownSeconds = -9; #expect(f.model.countdownSeconds == 1)
        let invalid = CountdownFixture(savedSeconds: 0); defer { invalid.close() }
        #expect(invalid.model.countdownSeconds == 1)
    }
    @Test func manualChoicesSkipEnabledCountdownAndWaitForAnimationInBothDirections() {
        let f = CountdownFixture(); defer { f.close() }; f.enable()
        for (target, mode) in [(Appearance.dark, AppearanceMode.dark), (.light, .light)] {
            let old = f.appearance.current
            let requests = f.appearance.requests.count
            f.model.selectAppearanceMode(mode)
            #expect(f.panel.starts == 0 && f.model.countdownRemaining == nil)
            #expect(f.player.targets.last == target && f.appearance.current == old)
            #expect(f.appearance.requests.count == requests)
            f.model.offset = 12; f.model.countdownSeconds = 20; f.model.reconcile()
            #expect(f.panel.starts == 0 && f.appearance.requests.count == requests)
            f.player.finish()
            #expect(f.appearance.current == target && f.appearance.requests.count == requests + 1)
        }
    }
    @Test func manualChoiceWithDisabledAnimationAppliesWithoutCountdown() {
        let f = CountdownFixture(); defer { f.close() }; f.enable(animation: false)
        f.model.selectAppearanceMode(.dark)
        #expect(f.panel.starts == 0 && f.player.targets.isEmpty && f.appearance.requests == [.dark])
        f.model.selectAppearanceMode(.light)
        #expect(f.panel.starts == 0 && f.player.targets.isEmpty && f.appearance.requests == [.dark, .light])
    }
    @Test func manualChoiceReplacesAutomaticCountdownAndIgnoresStaleCompletion() throws {
        for mode in [AppearanceMode.light, .dark] {
            let f = CountdownFixture(); defer { f.close() }; f.enable(); f.schedule(.dark)
            let stale = try #require(f.panel.finish)
            f.model.selectAppearanceMode(mode)
            #expect(f.panel.seconds == nil && f.model.countdownRemaining == nil && f.panel.starts == 1)
            stale()
            #expect(f.panel.starts == 1 && !f.model.enabled)
            if mode == .dark {
                #expect(f.player.targets == [.dark] && f.appearance.requests.isEmpty)
                f.player.finish(); #expect(f.appearance.current == .dark)
            } else {
                #expect(f.player.targets.isEmpty && !f.appearance.requests.contains(.dark))
            }
        }
    }

    @Test func explicitAutomaticSelectionSkipsCountdownInBothDirectionsWithOrWithoutAnimation() {
        for animation in [false, true] {
            for prior in [AppearanceMode.light, .dark] {
                let f = CountdownFixture(); defer { f.close() }; f.enable(animation: animation)
                f.model.selectAppearanceMode(prior); f.player.finish()
                let target: Appearance = prior == .light ? .dark : .light
                f.now = ISO8601DateFormatter().date(from: target == .dark ? "2026-10-22T14:00:00Z" : "2026-10-22T04:00:00Z")!
                let requests = f.appearance.requests.count, plays = f.player.targets.count
                let previousAppearance = f.appearance.current
                f.model.selectAppearanceMode(.automatic)
                #expect(f.model.enabled && f.model.appearanceMode == .automatic)
                #expect(f.defaults.bool(forKey: "enabled") && f.defaults.object(forKey: "manualAppearance") == nil)
                #expect(f.model.countdownEnabled && f.panel.starts == 0 && f.model.countdownRemaining == nil)
                if animation {
                    #expect(f.player.targets.count == plays + 1 && f.player.targets.last == target)
                    #expect(f.appearance.current == previousAppearance && f.appearance.requests.count == requests)
                    f.model.reconcile() // A pending animation must not acquire a countdown later.
                    #expect(f.panel.starts == 0)
                    f.player.finish()
                } else {
                    #expect(f.player.targets.count == plays)
                }
                #expect(f.appearance.current == target && f.appearance.requests.count == requests + 1)
                // The next solar transition keeps the user's countdown preference.
                f.now = ISO8601DateFormatter().date(from: target == .dark ? "2026-10-23T04:00:00Z" : "2026-10-22T14:00:00Z")!
                f.model.reconcile()
                #expect(f.panel.starts == 1 && f.model.countdownRemaining == 10)
            }
        }
    }

    @Test func explicitAutomaticSelectionWithMatchingAppearanceDoesNotAnimateOrCountDown() {
        for prior in [AppearanceMode.light, .dark] {
            let f = CountdownFixture(); defer { f.close() }; f.enable()
            f.model.selectAppearanceMode(prior); f.player.finish()
            f.now = ISO8601DateFormatter().date(from: prior == .light ? "2026-10-22T04:00:00Z" : "2026-10-22T14:00:00Z")!
            let plays = f.player.targets.count
            f.model.selectAppearanceMode(.automatic)
            #expect(f.model.enabled && f.player.targets.count == plays && f.panel.starts == 0)
            #expect(f.model.countdownRemaining == nil && f.model.scheduledCheck != nil)
        }
    }

    @Test func fullSequenceKeepsActualAppearanceUntilAnimationEnds() throws {
        let f = CountdownFixture(); defer { f.close() }; f.enable()
        f.schedule(.dark)
        #expect(f.panel.seconds == 10)
        #expect(f.appearance.requests.isEmpty && f.player.targets.isEmpty && f.model.currentSystemAppearance == .light)
        f.panel.tick?(9)
        #expect(f.model.countdownRemaining == 9 && f.model.settingsStatus.contains("9"))
        f.model.reconcile(); f.model.offset = 5
        #expect(f.panel.starts == 1)
        f.player.beforePlay = { #expect(f.panel.seconds == nil) }
        let done = try #require(f.panel.finish); done()
        #expect(f.model.countdownRemaining == nil && f.player.targets == [.dark] && f.appearance.requests.isEmpty)
        f.model.reconcile(); #expect(f.panel.starts == 1)
        f.player.finish()
        #expect(f.appearance.requests == [.dark] && f.model.currentSystemAppearance == .dark)
    }
    @Test func immediateButtonSkipsRemainingTimeButStillPlaysAnimation() {
        let f = CountdownFixture(); defer { f.close() }; f.enable()
        f.schedule(.dark); f.panel.finish?()
        #expect(f.panel.seconds == nil && f.player.targets == [.dark] && f.appearance.requests.isEmpty)
        f.player.finish(); #expect(f.appearance.current == .dark)
    }
    @Test func disabledAnimationStillCountsDown() {
        let f = CountdownFixture(); defer { f.close() }; f.enable(animation: false)
        f.schedule(.dark)
        #expect(f.panel.starts == 1 && f.appearance.requests.isEmpty)
        f.panel.finish?()
        #expect(f.player.targets.isEmpty && f.appearance.current == .dark)
    }
    @Test func reverseCancelsPanelAndStaleCallbacks() throws {
        let f = CountdownFixture(); defer { f.close() }; f.enable()
        f.schedule(.dark)
        let done = try #require(f.panel.finish), tick = try #require(f.panel.tick)
        f.model.selectAppearanceMode(.light); done(); tick(2)
        #expect(f.model.countdownRemaining == nil && f.panel.seconds == nil)
        #expect(!f.appearance.requests.contains(.dark) && f.player.targets.isEmpty)
    }
    @Test func cancelSkipsCurrentSolarTargetUntilNextTargetOrExplicitSelection() {
        let f = CountdownFixture(); defer { f.close() }; f.enable()
        f.model.selectAppearanceMode(.automatic)
        f.now = ISO8601DateFormatter().date(from: "2026-10-22T14:00:00Z")!
        f.model.reconcile(); f.panel.cancel?()
        f.model.reconcile(); f.model.offset = 10
        #expect(f.panel.starts == 1 && f.player.targets.isEmpty && f.appearance.current == .light)
        f.model.selectAppearanceMode(.automatic)
        #expect(f.panel.starts == 1 && f.player.targets == [.dark])
        f.player.finish()
        f.now = ISO8601DateFormatter().date(from: "2026-10-23T04:00:00Z")!
        f.model.reconcile()
        #expect(f.panel.starts == 2)
        f.panel.finish?(); f.player.finish()
        f.now = ISO8601DateFormatter().date(from: "2026-10-23T14:00:00Z")!
        f.model.reconcile(); #expect(f.panel.starts == 3)
    }
    @Test func disablingCountdownContinuesWithAnimationAndIgnoresOldFinish() throws {
        let f = CountdownFixture(); defer { f.close() }; f.enable()
        f.schedule(.dark)
        let done = try #require(f.panel.finish)
        f.model.countdownEnabled = false
        #expect(f.player.targets == [.dark] && f.panel.seconds == nil)
        done(); #expect(f.player.targets == [.dark])
        f.player.finish(); #expect(f.appearance.current == .dark)
    }
    @Test func changingSecondsRestartsOnceAndDisablingAnimationKeepsCountdown() {
        let f = CountdownFixture(); defer { f.close() }; f.enable()
        f.schedule(.dark)
        f.model.countdownSeconds = 20
        #expect(f.panel.seconds == 20 && f.panel.starts == 2)
        f.model.transitionAnimationEnabled = false
        #expect(f.panel.seconds == 20 && f.appearance.requests.isEmpty)
        f.panel.finish?(); #expect(f.appearance.current == .dark && f.player.targets.isEmpty)
    }
    @Test func sleepClearsCountdownAndWakeCorrectsImmediately() throws {
        let f = CountdownFixture(); defer { f.close() }; f.enable()
        f.schedule(.dark)
        let stale = try #require(f.panel.finish)
        f.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(f.panel.seconds == nil && f.appearance.requests.isEmpty)
        f.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(f.appearance.current == .dark && f.panel.starts == 1 && f.player.targets.isEmpty)
        stale(); #expect(f.appearance.requests == [.dark])
    }
    @Test func unavailableDesktopAndShutdownNeverLeaveCountdown() {
        let f = CountdownFixture(); defer { f.close() }; f.enable()
        f.ready = false; f.model.selectAppearanceMode(.dark)
        #expect(f.panel.starts == 0 && f.appearance.current == .dark)
        f.ready = true; f.model.selectAppearanceMode(.light)
        let done = f.panel.finish
        f.model.shutdown(); done?()
        #expect(f.panel.seconds == nil && f.appearance.current == .dark)
    }
    @Test func lockCancelsCountdownAndCorrectsImmediately() {
        let f = CountdownFixture(); defer { f.close() }; f.enable()
        f.schedule(.dark); f.ready = false
        f.workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        #expect(f.panel.seconds == nil && f.appearance.current == .dark && f.panel.starts == 1)
    }
    @Test func changedSolarTargetAtDeadlineIsReevaluated() {
        let f = CountdownFixture(); defer { f.close() }; f.enable()
        f.model.selectAppearanceMode(.automatic)
        f.now = ISO8601DateFormatter().date(from: "2026-10-22T14:00:00Z")!
        f.model.reconcile()
        f.now = ISO8601DateFormatter().date(from: "2026-10-23T04:00:00Z")!
        f.panel.finish?()
        #expect(f.player.targets.isEmpty && !f.appearance.requests.contains(.dark))
    }
    @Test func transientRetryDoesNotRepeatCountdown() {
        let f = CountdownFixture(); defer { f.close() }; f.enable(animation: false)
        f.appearance.failure = .init(message: "temporary", permissionDenied: false)
        f.schedule(.dark); f.panel.finish?()
        f.appearance.failure = nil; f.model.reconcile()
        #expect(f.panel.starts == 1 && f.appearance.current == .dark)
    }

    @Test func wakeCorrectsBeforeUnlockThenPlaysOnceWithoutCountdown() async throws {
        let f = CountdownFixture(); defer { f.close() }; f.enable()
        f.model.selectAppearanceMode(.automatic)
        f.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        f.ready = false
        f.now = ISO8601DateFormatter().date(from: "2026-10-22T14:00:00Z")!
        f.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(f.appearance.current == .dark && f.panel.starts == 0 && f.player.targets.isEmpty)
        f.ready = true
        f.workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(80))
        #expect(f.player.targets == [.dark] && f.panel.starts == 0)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_COUNTDOWN_UI_TESTS"] == "1"))
    func nativeManualPickersSkipCountdownAndApplyWhileFinalFrameHolds() async throws {
        let app = NSApplication.shared; app.setActivationPolicy(.regular); app.finishLaunching()
        let countdown = CountdownController()
        let animation = AppearanceTransitionController(reduceMotion: { false }, duration: 0.15)
        let f = CountdownFixture(presenter: countdown, transition: animation); defer { f.close() }; f.enable()
        let window = NSWindow(contentViewController: NSHostingController(rootView: MenuContent(model: f.model, quit: {})))
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: MenuPanelLayout.width, height: MenuPanelLayout.height))
        window.makeKeyAndOrderFront(nil); defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08)) }
        let content = try #require(window.contentView)
        let menuPicker = try #require(views(content).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 3 })
        let settingsPresenter = SettingsWindowController(); settingsPresenter.show(model: f.model)
        let settings = try #require(settingsPresenter.window); defer { settings.close() }
        settle()
        let settingsContent = try #require(settings.contentView)
        let settingsPicker = try #require(views(settingsContent).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 3 })
        f.appearance.beforeApply = { #expect(countdown.panel == nil && animation.panel?.isVisible == true && animation.isHoldingFinalFrame) }
        for picker in [menuPicker, settingsPicker] {
            for (segment, target) in [(2, Appearance.dark), (0, .light)] {
                let requests = f.appearance.requests.count
                picker.selectedSegment = segment
                #expect(picker.sendAction(picker.action, to: picker.target))
                #expect(countdown.panel == nil && f.model.countdownRemaining == nil)
                #expect(animation.panel?.isVisible == true && f.appearance.requests.count == requests)
                for _ in 0..<40 {
                    settle()
                    if animation.panel == nil { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                #expect(animation.panel == nil && countdown.panel == nil)
                #expect(f.appearance.current == target && f.appearance.requests.count == requests + 1)
                #expect(menuPicker.selectedSegment == segment && settingsPicker.selectedSegment == segment)
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_COUNTDOWN_UI_TESTS"] == "1"))
    func nativeAutomaticPickersSkipCountdownAndKeepBothPanelsInSync() async throws {
        let app = NSApplication.shared; app.setActivationPolicy(.regular); app.finishLaunching()
        let countdown = CountdownController()
        let animation = AppearanceTransitionController(reduceMotion: { false }, duration: 0.08, finalFrameDuration: 0.08)
        let f = CountdownFixture(presenter: countdown, transition: animation); defer { f.close() }; f.enable()
        let menu = NSWindow(contentViewController: NSHostingController(rootView: MenuContent(model: f.model, quit: {})))
        menu.isReleasedWhenClosed = false
        menu.setContentSize(NSSize(width: MenuPanelLayout.width, height: MenuPanelLayout.height)); menu.makeKeyAndOrderFront(nil)
        let settingsPresenter = SettingsWindowController(); settingsPresenter.show(model: f.model)
        let settings = try #require(settingsPresenter.window)
        defer { menu.close(); settings.close() }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }
        func views(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(views) }
        settle()
        let menuContent = try #require(menu.contentView), settingsContent = try #require(settings.contentView)
        let menuPicker = try #require(views(menuContent).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 3 })
        let settingsPicker = try #require(views(settingsContent).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 3 })
        for picker in [menuPicker, settingsPicker] {
            for prior in [AppearanceMode.light, .dark] {
                f.appearance.beforeApply = nil
                f.model.transitionAnimationEnabled = false
                f.model.selectAppearanceMode(prior)
                let target: Appearance = prior == .light ? .dark : .light
                f.now = ISO8601DateFormatter().date(from: target == .dark ? "2026-10-22T14:00:00Z" : "2026-10-22T04:00:00Z")!
                f.model.transitionAnimationEnabled = true
                f.appearance.beforeApply = { #expect(countdown.panel == nil && animation.isHoldingFinalFrame) }
                let requests = f.appearance.requests.count
                picker.selectedSegment = 1
                #expect(picker.sendAction(picker.action, to: picker.target))
                #expect(countdown.panel == nil && f.model.countdownRemaining == nil)
                #expect(animation.panel?.isVisible == true && f.appearance.requests.count == requests)
                for _ in 0..<60 {
                    settle()
                    if animation.panel == nil { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                #expect(animation.panel == nil && countdown.panel == nil && f.appearance.current == target)
                #expect(f.appearance.requests.count == requests + 1 && f.model.countdownEnabled)
                #expect(menuPicker.selectedSegment == 1 && settingsPicker.selectedSegment == 1)
            }
        }
        f.appearance.beforeApply = nil
        f.now = ISO8601DateFormatter().date(from: "2026-10-22T14:00:00Z")!
        f.model.reconcile()
        #expect(countdown.panel?.isVisible == true && f.model.countdownRemaining == 10)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_COUNTDOWN_UI_TESTS"] == "1"))
    func nativePanelDeadlineButtonsAndSettingsControls() throws {
        let app = NSApplication.shared; app.setActivationPolicy(.regular); app.finishLaunching()
        var now: TimeInterval = 100
        let panel = CountdownController(now: { now })
        let f = CountdownFixture(presenter: panel); defer { f.close() }
        let settings = SettingsWindowController(); settings.show(model: f.model)
        let window = try #require(settings.window); defer { window.close() }
        func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2)) }
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        settle()
        let controls = views(try #require(window.contentView))
        let switches = controls.compactMap { $0 as? NSSwitch }
        #expect(switches.count == 3 + (BuildFeatures.debugToolsEnabled ? 1 : 0))
        let toggle = try #require(switches.dropFirst().first)
        #expect(toggle.state == .off)
        _ = toggle.accessibilityPerformPress(); settle()
        #expect(f.model.countdownEnabled)
        let updatedControls = views(try #require(window.contentView))
        let input = try #require(updatedControls.compactMap { $0 as? NSTextField }.first { $0.isEditable && $0.stringValue == "10" })
        window.makeFirstResponder(input)
        let editor = try #require(input.currentEditor() as? NSTextView)
        editor.selectAll(nil); editor.insertText("12", replacementRange: editor.selectedRange()); settle()
        let enter = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        app.sendEvent(enter); settle()
        #expect(f.model.countdownSeconds == 12)
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AURALIM_COUNTDOWN_UI_OUTPUT"] ?? "/private/tmp/auralim-countdown-ui")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func capture(_ captured: NSWindow, _ name: String) throws {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l", String(captured.windowNumber), output.appendingPathComponent(name + ".png").path]
            try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
        }
        for theme in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: theme); settle()
            try capture(window, theme == .aqua ? "settings-light" : "settings-dark")
        }
        f.model.transitionAnimationEnabled = true
        f.player.beforePlay = { #expect(panel.panel == nil) }
        f.schedule(.dark)
        let first = try #require(panel.panel)
        #expect(first.isVisible && !first.ignoresMouseEvents && f.model.countdownRemaining == 12)
        for theme in [NSAppearance.Name.aqua, .darkAqua] {
            first.appearance = NSAppearance(named: theme); settle()
            try capture(first, theme == .aqua ? "countdown-light" : "countdown-dark")
        }
        now += 4; panel.update()
        #expect(f.model.countdownRemaining == 8)
        now += 20; panel.update()
        #expect(panel.panel == nil && first.contentView == nil && !first.isVisible)
        #expect(f.player.targets == [.dark] && f.appearance.requests.isEmpty)
        f.player.finish(); #expect(f.appearance.current == .dark)
        f.schedule(.light); settle()
        func clickPanel(x: CGFloat) throws {
            let current = try #require(panel.panel)
            for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: kind, location: NSPoint(x: x, y: 34), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: current.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                app.sendEvent(event)
            }
            settle()
        }
        try clickPanel(x: 65)
        #expect(panel.panel == nil && f.appearance.current == .dark)
        f.schedule(.light); settle()
        try clickPanel(x: 275)
        #expect(panel.panel == nil && f.player.targets == [.dark, .light])
        f.player.finish(); #expect(f.appearance.current == .light)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_COUNTDOWN_UI_TESTS"] == "1"))
    func realTimerReleasesPanelBeforeCompletingExactlyOnce() async throws {
        _ = NSApplication.shared
        let panel = CountdownController()
        defer { panel.stop() }
        var finished = 0
        var ticks: [Int] = []
        panel.start(seconds: 1, target: .light, localizer: Localizer(language: .english),
            tick: { ticks.append($0) }, finish: { #expect(panel.panel == nil); finished += 1 }, cancel: {})
        #expect(panel.panel?.isVisible == true && ticks == [1])
        try await Task.sleep(for: .milliseconds(1250))
        #expect(panel.panel == nil && finished == 1)
        panel.complete(); panel.cancelByUser()
        #expect(finished == 1)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_COUNTDOWN_UI_TESTS"] == "1"))
    func nativeCountdownThenAnimationHoldsFinalFrameDuringApply() async throws {
        _ = NSApplication.shared
        let countdown = CountdownController()
        let transition = AppearanceTransitionController(reduceMotion: { false }, duration: 0.15)
        let f = CountdownFixture(presenter: countdown, transition: transition); defer { f.close() }
        f.appearance.beforeApply = { #expect(countdown.panel == nil && transition.panel?.isVisible == true && transition.isHoldingFinalFrame) }
        f.enable()
        f.schedule(.dark)
        #expect(countdown.panel?.isVisible == true && transition.panel == nil && f.appearance.current == .light)
        countdown.complete()
        #expect(countdown.panel == nil && transition.panel?.isVisible == true && f.appearance.requests.isEmpty)
        try await Task.sleep(for: .milliseconds(300))
        #expect(countdown.panel == nil && transition.panel?.isVisible == true && f.appearance.requests == [.dark])
        try await Task.sleep(for: .milliseconds(1000))
        #expect(transition.panel == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_COUNTDOWN_UI_TESTS"] == "1"))
    func acknowledgingPanelKeepsCountdownAndCompletesTheSwitch() throws {
        let app = NSApplication.shared; app.setActivationPolicy(.regular); app.finishLaunching()
        var now: TimeInterval = 100
        let panel = CountdownController(now: { now })
        let f = CountdownFixture(presenter: panel); defer { f.close() }; f.enable(animation: false)
        f.schedule(.dark)
        let original = try #require(panel.panel)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: kind, location: NSPoint(x: 215, y: 34), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: original.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            app.sendEvent(event)
        }
        #expect(panel.panel == nil && original.contentView == nil)
        #expect(f.model.countdownRemaining == 10 && f.appearance.requests.isEmpty)
        now += 3; panel.update()
        #expect(f.model.countdownRemaining == 7 && f.appearance.requests.isEmpty)
        f.model.reconcile()
        now += 7; panel.update()
        #expect(f.appearance.requests == [.dark] && f.model.countdownRemaining == nil)
        panel.complete(); #expect(f.appearance.requests == [.dark])
    }

}
