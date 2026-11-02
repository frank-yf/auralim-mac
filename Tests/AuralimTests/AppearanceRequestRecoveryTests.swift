import AppKit
import AuralimCore
import Testing
@testable import Auralim

private final class RunnerAttempts {
    // Accessed only by the controller's serial worker.
    private var count = 0
    func arguments(for appearance: Appearance) -> [String] {
        count += 1
        if count == 1 {
            // No descendant keeps pipes open. Ignoring TERM requires the hard
            // kill path, and never uses System Events or changes real appearance.
            return ["-c", "trap '' TERM; exec /bin/sleep 30"]
        }
        return ["-c", "printf '{\(appearance == .dark ? "true" : "false"), true}\\n'"]
    }
}

private final class ReceiptSystem: AppearanceApplying {
    let runner: AppearanceController
    var current: Appearance = .dark
    init(_ runner: AppearanceController) { self.runner = runner }
    func cancel() { runner.cancel() }
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        runner.apply(appearance) { [self] result in
            #expect(Thread.isMainThread)
            if case .success = result { current = appearance }
            completion(result)
        }
    }
}

@MainActor
@Suite(.serialized)
struct AppearanceRequestRecoveryTests {
    private func result(_ runner: AppearanceController, target: Appearance) async -> Result<AppearanceApplication, AppearanceFailure> {
        await withCheckedContinuation { continuation in
            runner.apply(target) { value in
                #expect(Thread.isMainThread)
                continuation.resume(returning: value)
            }
        }
    }

    private func readResult(_ runner: AppearanceController) async -> Result<Appearance, AppearanceFailure> {
        await withCheckedContinuation { continuation in
            runner.readAppearance { value in
                #expect(Thread.isMainThread)
                continuation.resume(returning: value)
            }
        }
    }

    @Test func readinessReadsBooleansAndRejectsNonBooleanReceipts() async throws {
        for (text, expected) in [("true", Appearance.dark), ("false", Appearance.light)] {
            let runner = AppearanceController(readinessArguments: { ["-s", "s", "-e", "return \(text)"] })
            #expect(try await readResult(runner).get() == expected)
        }
        let invalid = AppearanceController(readinessArguments: { ["-s", "s", "-e", "return 42"] })
        guard case .failure(let error) = await readResult(invalid) else { Issue.record("Invalid readiness reply accepted"); return }
        if case .verification = error.reason {} else { Issue.record("Invalid reply must fail verification") }
    }

    @Test func readinessTimeoutReleasesTheRunnerForManualSwitches() async throws {
        let runner = AppearanceController(executableURL: URL(fileURLWithPath: "/bin/sh"), timeout: 20, terminationGrace: 0.05,
            arguments: { _ in ["-c", "printf '{true, true}\\n'"] }, readinessTimeout: 0.15,
            readinessArguments: { ["-c", "trap '' TERM; exec /bin/sleep 30"] })
        let start = Date()
        guard case .failure(let error) = await readResult(runner) else { Issue.record("Hung probe must time out"); return }
        if case .script(-1712) = error.reason {} else { Issue.record("Probe timeout code lost") }
        #expect(Date().timeIntervalSince(start) < 3)
        #expect(try await result(runner, target: .dark).get().changed)
    }

    @Test func manualRequestCancelsProbeBeforeItsLongDeadline() async throws {
        let runner = AppearanceController(executableURL: URL(fileURLWithPath: "/bin/sh"), terminationGrace: 0.05,
            arguments: { _ in ["-c", "printf '{true, true}\\n'"] }, readinessTimeout: 20,
            readinessArguments: { ["-c", "trap '' TERM; exec /bin/sleep 30"] })
        let probe = Task { await readResult(runner) }
        try await Task.sleep(for: .milliseconds(150))
        let start = Date()
        runner.cancel()
        #expect(try await result(runner, target: .dark).get().changed)
        guard case .failure(let error) = await probe.value else { Issue.record("Old probe succeeded after manual takeover"); return }
        if case .script(-128) = error.reason {} else { Issue.record("Probe was not cancelled") }
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test func validatesTheActualStateAndChangeReceipt() throws {
        #expect(try AppearanceController.verifiedOutput("{false, true}\n", target: .light).get().changed)
        #expect(try !AppearanceController.verifiedOutput("{true, false}", target: .dark).get().changed)
        for text in ["false, true", "{false}", "{0, 1}", "{true, true}", "{false, true, false}", ""] {
            if case .success = AppearanceController.verifiedOutput(text, target: .light) {
                Issue.record("Unverified receipt accepted: \(text)")
            }
        }
        for code in [-1743, -1744] {
            let failure = AppearanceController.scriptFailure("execution error: Not authorized. (\(code))\n")
            #expect(failure.permissionDenied)
            if case .authorization = failure.reason {} else { Issue.record("Permission error must not auto-retry") }
        }
        let timeout = AppearanceController.scriptFailure("execution error: AppleEvent timed out. (-1712)")
        #expect(!timeout.permissionDenied)
        if case .script(-1712) = timeout.reason {} else { Issue.record("Timeout code lost") }
    }

    @Test func realInterpreterReceiptDoesNotRequireSystemEvents() async throws {
        let runner = AppearanceController(arguments: { _ in ["-s", "s", "-e", "return {true, false}"] })
        let receipt = try await result(runner, target: .dark).get()
        #expect(!receipt.changed)
    }

    @Test func hungRunnerTimesOutAndLaterRequestsStillWork() async throws {
        let attempts = RunnerAttempts()
        let runner = AppearanceController(executableURL: URL(fileURLWithPath: "/bin/sh"),
            timeout: 0.15, terminationGrace: 0.05, arguments: attempts.arguments)
        let started = Date()
        let failed = await result(runner, target: .light)
        guard case .failure(let error) = failed else { Issue.record("Hung runner must fail"); return }
        if case .script(-1712) = error.reason {} else { Issue.record("Expected timeout") }
        #expect(!error.permissionDenied && Date().timeIntervalSince(started) < 3)
        #expect(try await result(runner, target: .dark).get().changed)
        #expect(try await result(runner, target: .light).get().changed)
    }

    @Test func cancellationStopsActiveAndQueuedWorkWithoutPoisoningTheRunner() async throws {
        let attempts = RunnerAttempts()
        let runner = AppearanceController(executableURL: URL(fileURLWithPath: "/bin/sh"),
            timeout: 20, terminationGrace: 0.05, arguments: attempts.arguments)
        let first = Task { await result(runner, target: .light) }
        try await Task.sleep(for: .milliseconds(150))
        let start = Date()
        runner.cancel()
        guard case .failure(let failure) = await first.value else { Issue.record("Cancelled request succeeded"); return }
        if case .script(-128) = failure.reason {} else { Issue.record("Cancellation was not distinguished from timeout") }
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(try await result(runner, target: .dark).get().changed)
    }

    @Test func failedLaunchAndPermissionDenialAlwaysComplete() async {
        let missing = AppearanceController(executableURL: URL(fileURLWithPath: "/nonexistent/auralim-runner"))
        if case .success = await result(missing, target: .light) { Issue.record("Missing executable accepted") }
        let denied = AppearanceController(executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: { _ in ["-c", "printf 'execution error: Not authorized. (-1743)\\n' >&2; exit 1"] })
        guard case .failure(let failure) = await result(denied, target: .dark) else {
            Issue.record("Permission denial must fail"); return
        }
        #expect(failure.permissionDenied)
    }

    private func withModel(runner: AppearanceController,
                           body: (AppModel, ReceiptSystem, NotificationCenter) async throws -> Void) async rethrows {
        let suite = "Auralim.RequestRecovery.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        defaults.set("Asia/Shanghai", forKey: "city")
        defaults.set(true, forKey: "enabled")
        defaults.set("en", forKey: "language")
        let system = ReceiptSystem(runner), notifications = NotificationCenter()
        let model = AppModel(defaults: defaults, controller: system,
            clock: { ISO8601DateFormatter().date(from: "2026-11-02T04:00:00Z")! }, enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: notifications, appearanceNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(),
            systemSettings: { .init(mode: system.current == .dark ? .dark : .light, appearance: system.current) }, desktopReady: { true })
        defer { model.shutdown(); defaults.removePersistentDomain(forName: suite) }
        try await body(model, system, notifications)
    }

    @Test func timedOutLoginShowsRetryAndAcceptsLaterManualChoices() async throws {
        let attempts = RunnerAttempts()
        let runner = AppearanceController(executableURL: URL(fileURLWithPath: "/bin/sh"),
            timeout: 0.15, terminationGrace: 0.05, arguments: attempts.arguments)
        try await withModel(runner: runner) { model, system, _ in
            try await Task.sleep(for: .milliseconds(450))
            #expect(!model.isApplying && model.errorMessage != nil && system.current == .dark)
            model.retry()
            try await Task.sleep(for: .milliseconds(200))
            #expect(!model.isApplying && model.errorMessage == nil && system.current == .light)
            model.selectAppearanceMode(.dark)
            try await Task.sleep(for: .milliseconds(200))
            #expect(!model.isApplying && model.errorMessage == nil && system.current == .dark)
        }
    }

    @Test func applicationTerminationKillsTheRunnerAndInvalidatesQueuedWork() async throws {
        let attempts = RunnerAttempts()
        let runner = AppearanceController(executableURL: URL(fileURLWithPath: "/bin/sh"),
            timeout: 20, terminationGrace: 0.05, arguments: attempts.arguments)
        try await withModel(runner: runner) { model, _, notifications in
            try await Task.sleep(for: .milliseconds(150))
            #expect(model.isApplying)
            let queued = Task { await result(runner, target: .dark) }
            await Task.yield()
            notifications.post(name: NSApplication.willTerminateNotification, object: nil)
            guard case .failure(let error) = await queued.value else { Issue.record("Queued work ran after quit"); return }
            if case .script(-128) = error.reason {} else { Issue.record("Queued work was not cancelled") }
            try await Task.sleep(for: .milliseconds(50))
            #expect(!model.isApplying)
            #expect(try await result(runner, target: .dark).get().changed)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_BEFORE_TRANSITION_UI_TESTS"] == "1"))
    func panelCleansUpEvenWithoutAViewStartupCallback() async throws {
        _ = NSApplication.shared
        let player = AppearanceTransitionController(reduceMotion: { false }, duration: 0.05, finalFrameDuration: 0.05)
        defer { player.stop() }
        var ended = 0, completed = 0
        player.play(.light, title: "Startup recovery test", onAnimationEnd: { ended += 1 }, completion: { completed += 1 })
        let panel = try #require(player.panel)
        // Simulate SwiftUI startup never reaching its task, or that task being cancelled.
        panel.contentView = NSView(frame: panel.contentView?.bounds ?? .zero)
        try await Task.sleep(for: .milliseconds(250))
        #expect(ended == 1 && completed == 1)
        #expect(player.panel == nil && !panel.isVisible && panel.contentView == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_BEFORE_TRANSITION_UI_TESTS"] == "1"))
    func daytimeLoginWithNightAppearanceReleasesPanelAndRecoversManualSelection() async throws {
        _ = NSApplication.shared
        let suite = "Auralim.StartupRecovery.\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suite)!
        isolated.set("Asia/Shanghai", forKey: "city")
        isolated.set(true, forKey: "enabled")
        isolated.set(true, forKey: "transitionAnimationEnabled")
        isolated.set("en", forKey: "language")
        let attempts = RunnerAttempts()
        let runner = AppearanceController(executableURL: URL(fileURLWithPath: "/bin/sh"),
            timeout: 0.65, terminationGrace: 0.05, arguments: attempts.arguments)
        let system = ReceiptSystem(runner)
        let player = AppearanceTransitionController(reduceMotion: { false }, duration: 0.05, finalFrameDuration: 0.05)
        let model = AppModel(defaults: isolated, controller: system,
            clock: { ISO8601DateFormatter().date(from: "2026-11-02T04:00:00Z")! }, enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(), appearanceNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(),
            systemSettings: { .init(mode: system.current == .dark ? .dark : .light, appearance: system.current) },
            transitionPlayer: player, desktopReady: { true })
        defer { model.shutdown(); isolated.removePersistentDomain(forName: suite) }
        try await Task.sleep(for: .milliseconds(250))
        #expect(player.panel == nil && model.isApplying && system.current == .dark)
        // This edit arrives while the first request is stuck. It must survive
        // that request's timeout, rather than being lost or applied as stale Light.
        model.selectAppearanceMode(.dark)
        try await Task.sleep(for: .milliseconds(800))
        #expect(!model.isApplying && model.appearanceMode == .dark && model.errorMessage == nil)
        #expect(player.panel == nil && system.current == .dark)
        model.selectAppearanceMode(.light)
        try await Task.sleep(for: .milliseconds(350))
        #expect(!model.isApplying && model.appearanceMode == .light && system.current == .light)
        #expect(model.errorMessage == nil && player.panel == nil)
    }
}
