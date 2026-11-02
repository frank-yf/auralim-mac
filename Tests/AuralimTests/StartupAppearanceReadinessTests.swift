import AppKit
import AuralimCore
import Testing
@testable import Auralim

@MainActor
private final class StartupTimers {
    struct Job { let delay: TimeInterval; let timer: Timer; let action: @MainActor () -> Void }
    var jobs: [Job] = []
    var active: [Job] { jobs.filter { $0.timer.isValid } }
    func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in }
        jobs.append(.init(delay: delay, timer: timer, action: action))
        return timer
    }
    func fire() {
        guard let job = active.first else { Issue.record("No startup timer scheduled"); return }
        job.timer.invalidate(); job.action()
    }
}

private final class StartupService: AppearanceApplying, AppearanceReadinessChecking {
    var current: Appearance = .dark
    var reads: [(Result<Appearance, AppearanceFailure>) -> Void] = []
    var writes: [Appearance] = []
    var writeCompletions: [(Result<AppearanceApplication, AppearanceFailure>) -> Void] = []
    var cancellations = 0
    var holdWrites = false
    var writeFailure: AppearanceFailure?
    func readAppearance(completion: @escaping (Result<Appearance, AppearanceFailure>) -> Void) { reads.append(completion) }
    func cancel() { cancellations += 1 } // Keep callbacks to exercise late delivery.
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        writes.append(appearance); writeCompletions.append(completion)
        if !holdWrites {
            if let writeFailure { completion(.failure(writeFailure)); return }
            let changed = current != appearance; current = appearance
            completion(.success(.init(changed: changed)))
        }
    }
}

@MainActor
private final class StartupPlayer: AppearanceTransitionPlaying {
    var targets: [Appearance] = []
    var callbacks: [@MainActor () -> Void] = []
    private var active: (@MainActor () -> Void)?
    func play(_ appearance: Appearance, title: String, completion: @escaping @MainActor () -> Void) {
        targets.append(appearance); callbacks.append(completion); active = completion
    }
    func stop() { active = nil }
    func finish() { let action = active; active = nil; action?() }
}

@MainActor
private final class StartupFixture {
    let suite = "Auralim.StartupReadiness.\(UUID().uuidString)"
    let defaults: UserDefaults
    let service = StartupService(), timers = StartupTimers(), player = StartupPlayer()
    let workspace = NotificationCenter(), application = NotificationCenter(), appearance = NotificationCenter()
    var ready: Bool
    var now = ISO8601DateFormatter().date(from: "2026-11-02T04:00:00Z")!
    var preferencesAppearance: Appearance?
    var model: AppModel!
    init(ready: Bool = true, automatic: Bool = true, animation: Bool = true,
         explicitChecker: Bool = true, productionTimers: Bool = false) {
        self.ready = ready
        if productionTimers { now = Date() }
        defaults = UserDefaults(suiteName: suite)!
        defaults.set("Asia/Shanghai", forKey: "city")
        defaults.set("en", forKey: "language")
        defaults.set(automatic, forKey: "enabled")
        defaults.set(animation, forKey: "transitionAnimationEnabled")
        model = AppModel(defaults: defaults, controller: service, clock: { [unowned self] in now }, enableTimers: productionTimers,
            workspaceNotifications: workspace, systemNotifications: application, appearanceNotifications: appearance,
            loginItemController: FakeLoginItem(), locationController: FakeLocation(),
            systemSettings: { [unowned self] in
                let actual = preferencesAppearance ?? service.current
                return .init(mode: actual == .dark ? .dark : .light, appearance: actual)
            }, transitionPlayer: player, desktopReady: { [unowned self] in self.ready },
            startupReadinessChecker: explicitChecker ? service : nil, startupReadinessSchedule: { [unowned self] in timers.schedule($0, $1) })
    }
    func read(_ index: Int? = nil, result: Result<Appearance, AppearanceFailure>? = nil) {
        let requested = index ?? (service.reads.count - 1)
        guard service.reads.indices.contains(requested) else { Issue.record("No readiness callback at index \(requested)"); return }
        service.reads[requested](result ?? .success(service.current))
    }
    func close() { model.shutdown(); defaults.removePersistentDomain(forName: suite) }
    var unavailable: AppearanceFailure { .init(message: "", permissionDenied: false, reason: .script(-1712)) }
}

@MainActor
@Suite(.serialized)
struct StartupAppearanceReadinessTests {
    @Test func productionInitializationAutomaticallyUsesTheControllersReadinessCapability() {
        let f = StartupFixture(explicitChecker: false, productionTimers: true); defer { f.close() }
        #expect(f.timers.active.map(\.delay) == [1])
        f.timers.fire()
        #expect(f.service.reads.count == 1 && f.service.writes.isEmpty && f.player.targets.isEmpty)
    }

    @Test func launchCompletionRechecksDesktopWithoutPolling() async {
        let f = StartupFixture(ready: false); defer { f.close() }
        #expect(f.timers.active.isEmpty)
        f.ready = true
        f.application.post(name: NSApplication.didFinishLaunchingNotification, object: nil)
        for _ in 0..<5 { await Task.yield() }
        #expect(f.timers.active.map(\.delay) == [1] && f.service.reads.isEmpty)
        f.timers.fire(); f.read()
        #expect(f.player.targets == [.light] && f.service.writes.isEmpty)
    }

    @Test func waitsForDesktopAndServiceBeforeStartingAnimationOrWriting() {
        let f = StartupFixture(ready: false); defer { f.close() }
        #expect(f.timers.active.isEmpty && f.service.reads.isEmpty && f.player.targets.isEmpty && f.service.writes.isEmpty)
        f.ready = true
        f.workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        #expect(f.timers.active.map(\.delay) == [1])
        f.timers.fire()
        #expect(f.service.reads.count == 1 && f.player.targets.isEmpty && f.service.writes.isEmpty)
        f.read()
        #expect(f.player.targets == [.light] && f.service.writes.isEmpty)
        f.player.finish()
        #expect(f.service.writes == [.light] && !f.model.isApplying)
    }

    @Test func serviceRecoveryUsesBoundedBackoffAndOnlyOneAnimation() {
        let f = StartupFixture(); defer { f.close() }
        f.timers.fire(); f.read(result: .failure(f.unavailable))
        #expect(f.timers.active.map(\.delay) == [2])
        for _ in 0..<10 { f.model.reconcile() }
        #expect(f.timers.jobs.count == 2 && f.service.reads.count == 1)
        f.timers.fire(); f.read()
        f.read() // Duplicate delivery cannot replay or create a setter.
        #expect(f.player.targets == [.light] && f.service.writes.isEmpty)
        f.player.finish()
        #expect(f.service.writes == [.light] && f.model.errorMessage == nil && f.timers.active.isEmpty)
    }

    @Test func exhaustionDoesNotRestartOnActivationOrConfigurationNotifications() async {
        let f = StartupFixture(); defer { f.close() }
        for _ in 0..<3 { f.timers.fire(); f.read(result: .failure(f.unavailable)) }
        #expect(f.timers.jobs.map(\.delay) == [1, 2, 5] && f.service.reads.count == 3)
        #expect(f.model.errorMessage != nil && !f.model.isApplying && f.player.targets.isEmpty)
        for _ in 0..<5 {
            f.model.reconcile()
            f.application.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        }
        for _ in 0..<5 { await Task.yield() }
        f.model.sunriseOffset = 1
        #expect(f.service.reads.count == 3 && f.timers.active.isEmpty && f.service.writes.isEmpty)
        #expect(f.model.errorMessage != nil)
        f.model.retry()
        #expect(f.player.targets == [.light] && f.service.reads.count == 3)
        f.player.finish()
        #expect(f.service.writes == [.light] && f.model.errorMessage == nil)
    }

    @Test func setterFailuresAfterReadinessAlsoHaveALaunchRetryLimit() {
        let f = StartupFixture(animation: false); defer { f.close() }
        f.service.writeFailure = f.unavailable
        f.timers.fire(); f.read()
        for _ in 0..<10 { f.model.reconcile() }
        #expect(f.service.writes == [.light, .light, .light] && f.model.errorMessage != nil)
        f.service.writeFailure = nil
        f.model.retry()
        #expect(f.service.writes.count == 4 && f.service.current == .light && f.model.errorMessage == nil)
    }

    @Test func permissionDenialStopsAfterOneRead() {
        let f = StartupFixture(); defer { f.close() }
        f.timers.fire()
        f.read(result: .failure(.init(message: "", permissionDenied: true, reason: .authorization)))
        f.model.reconcile()
        #expect(f.service.reads.count == 1 && f.timers.active.isEmpty && f.service.writes.isEmpty)
        #expect(f.model.errorMessage != nil && f.player.targets.isEmpty)
        f.model.selectAppearanceMode(.dark)
        #expect(f.service.writes == [.dark] && f.model.errorMessage == nil)
    }

    @Test func latestClockAndOffsetsAreEvaluatedAfterTheRead() {
        let f = StartupFixture(); defer { f.close() }
        f.timers.fire()
        f.now = ISO8601DateFormatter().date(from: "2026-11-02T14:00:00Z")!
        f.model.offset = 10
        f.read()
        #expect(f.model.schedule?.appearance == .dark)
        #expect(f.player.targets.isEmpty && f.service.writes.isEmpty && f.model.currentSystemAppearance == .dark)
    }

    @Test func authoritativeReadAvoidsAnimationAndSetterWhenAlreadyCorrect() {
        let f = StartupFixture(); defer { f.close() }
        f.preferencesAppearance = .dark // Cached preferences may still describe the previous session.
        f.service.current = .light
        f.timers.fire(); f.read()
        #expect(f.model.currentSystemAppearance == .light && f.player.targets.isEmpty && f.service.writes.isEmpty)
    }

    @Test func everyManualModeIncludingSelectedAutoCancelsTheStartupDelay() {
        for mode in AppearanceMode.allCases {
            let f = StartupFixture(); defer { f.close() }
            let oldTimer = f.timers.jobs[0]
            f.model.selectAppearanceMode(mode)
            oldTimer.action() // A timer already queued when cancelled is harmless.
            #expect(f.timers.active.isEmpty && f.service.reads.isEmpty && f.model.appearanceMode == mode)
            if mode == .dark { #expect(f.service.writes == [.dark] && f.player.targets.isEmpty) }
            else {
                #expect(f.player.targets == [.light])
                f.player.finish()
                #expect(f.service.writes == [.light])
            }
        }
    }

    @Test func manualChoiceCancelsActiveProbeAndIgnoresItsLateSuccessOrFailure() {
        for mode in AppearanceMode.allCases {
            let f = StartupFixture(); defer { f.close() }
            f.timers.fire()
            f.model.selectAppearanceMode(mode)
            #expect(f.service.cancellations == 1)
            f.read(0, result: .success(.light)); f.read(0, result: .failure(f.unavailable))
            #expect(f.model.appearanceMode == mode && f.model.errorMessage == nil && f.timers.active.isEmpty)
            if mode == .dark { #expect(f.player.targets.isEmpty && f.service.writes == [.dark]) }
            else {
                #expect(f.player.targets == [.light] && f.service.writes.isEmpty)
                f.player.finish()
                #expect(f.service.writes == [.light])
            }
        }
    }

    @Test func manualChoiceDuringStartupAnimationInvalidatesItsCompletion() {
        let f = StartupFixture(); defer { f.close() }
        f.timers.fire(); f.read()
        let oldAnimation = f.player.callbacks[0]
        f.model.selectAppearanceMode(.dark)
        oldAnimation()
        #expect(f.service.writes == [.dark] && f.model.appearanceMode == .dark)
        #expect(!f.model.isApplying && f.model.errorMessage == nil && f.timers.active.isEmpty)
    }

    @Test func selectedAutoCanTakeOverAfterReadinessExhaustion() {
        let f = StartupFixture(); defer { f.close() }
        for _ in 0..<3 { f.timers.fire(); f.read(result: .failure(f.unavailable)) }
        f.model.selectAppearanceMode(.automatic)
        #expect(f.player.targets == [.light] && f.model.errorMessage == nil)
        f.player.finish()
        #expect(f.service.writes == [.light] && f.service.reads.count == 3)
    }

    @Test func aLaterSolarTargetResumesSchedulingAfterStartupFailure() {
        let f = StartupFixture(); defer { f.close() }
        for _ in 0..<3 { f.timers.fire(); f.read(result: .failure(f.unavailable)) }
        f.now = ISO8601DateFormatter().date(from: "2026-11-02T14:00:00Z")!
        f.model.reconcile()
        #expect(f.model.errorMessage == nil && f.service.writes == [.dark])
        f.now = ISO8601DateFormatter().date(from: "2026-11-03T04:00:00Z")!
        f.model.reconcile(); f.player.finish()
        #expect(f.service.writes == [.dark, .light] && f.service.reads.count == 3)
    }

    @Test func manualChoicePreemptsStartupSetterAndOldCompletionCannotClearNewBusyState() {
        let f = StartupFixture(); defer { f.close() }
        f.timers.fire(); f.read(); f.service.holdWrites = true; f.player.finish()
        #expect(f.model.isApplying && f.service.writes == [.light])
        f.model.selectAppearanceMode(.dark)
        #expect(f.service.writes == [.light, .dark] && f.service.cancellations == 1 && f.model.isApplying)
        f.service.writeCompletions[0](.success(.init(changed: true)))
        #expect(f.model.isApplying && f.model.appearanceMode == .dark)
        f.service.writeCompletions[1](.success(.init(changed: false)))
        #expect(!f.model.isApplying && f.model.currentSystemAppearance == .dark)
    }

    @Test func lockingPausesTheProbeAndLateCallbackCannotBypassUnlock() {
        let f = StartupFixture(); defer { f.close() }
        f.timers.fire(); f.ready = false
        f.appearance.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        #expect(f.service.cancellations == 1 && f.timers.active.isEmpty)
        f.read(0)
        #expect(f.player.targets.isEmpty && f.service.writes.isEmpty)
        f.ready = true
        f.appearance.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        f.timers.fire(); f.read(1)
        #expect(f.service.reads.count == 2 && f.player.targets == [.light])
    }

    @Test func wakeCorrectionBypassesStartupWaiting() {
        let f = StartupFixture(); defer { f.close() }
        f.timers.fire()
        f.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        f.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(f.service.writes == [.light] && f.service.current == .light)
        f.read(0)
        #expect(f.service.writes == [.light] && f.timers.active.isEmpty)
    }

    @Test func shutdownCancelsProbeAndDisablingAutoCancelsPendingTimers() {
        let f = StartupFixture(); defer { f.close() }
        f.timers.fire(); f.model.shutdown(); f.read(0)
        #expect(f.service.cancellations >= 1 && f.timers.active.isEmpty && f.player.targets.isEmpty && f.service.writes.isEmpty)
        let other = StartupFixture(); defer { other.close() }
        let queued = other.timers.jobs[0]
        other.model.enabled = false; queued.action()
        #expect(other.service.reads.isEmpty && other.player.targets.isEmpty && other.service.writes.isEmpty)
    }

    @Test func systemManagedLaunchDoesNotProbeOrChangeAppearance() {
        let f = StartupFixture(automatic: false); defer { f.close() }
        #expect(f.timers.jobs.isEmpty && f.service.reads.isEmpty && f.service.writes.isEmpty)
    }
}
