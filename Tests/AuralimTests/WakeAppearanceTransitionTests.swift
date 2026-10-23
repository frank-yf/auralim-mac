import AppKit
import AuralimCore
import Testing
@testable import Auralim

private final class WakeAppearance: AppearanceApplying {
    var current: Appearance = .dark
    var requests: [Appearance] = []
    var failure: AppearanceFailure?
    var hold = false
    var pending: (() -> Void)?
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        requests.append(appearance)
        let finish = { [self] in
            if let failure { completion(.failure(failure)); return }
            let changed = current != appearance
            current = appearance
            completion(.success(.init(changed: changed)))
        }
        if hold { pending = finish } else { finish() }
    }
    func finish() { let completion = pending; pending = nil; completion?() }
}

@MainActor
private final class WakePlayer: AppearanceTransitionPlaying {
    var played: [Appearance] = []
    func play(_ appearance: Appearance, title: String) { played.append(appearance) }
    func stop() {}
}

@MainActor
private final class WakeFixture {
    let suite = "Auralim.Wake.\(UUID().uuidString)"
    let store: UserDefaults
    let workspace = NotificationCenter()
    let distributed = NotificationCenter()
    let controller = WakeAppearance()
    let player = WakePlayer()
    var ready = false
    var now = ISO8601DateFormatter().date(from: "2026-10-22T14:00:00Z")!
    let nextDay = ISO8601DateFormatter().date(from: "2026-10-23T04:00:00Z")!
    var model: AppModel!
    init(animation: Bool = true, automatic: Bool = true, startInDaylight: Bool = false) {
        if startInDaylight {
            now = nextDay
            controller.current = .light
        }
        store = UserDefaults(suiteName: suite)!
        store.set(automatic, forKey: "enabled")
        store.set("Asia/Shanghai", forKey: "city")
        store.set(animation, forKey: "transitionAnimationEnabled")
        model = AppModel(defaults: store, controller: controller, clock: { [unowned self] in now }, enableTimers: false,
            workspaceNotifications: workspace, systemNotifications: NotificationCenter(), appearanceNotifications: distributed,
            loginItemController: FakeLoginItem(), locationController: FakeLocation(),
            systemSettings: { [unowned self] in .init(mode: controller.current == .dark ? .dark : .light, appearance: controller.current) },
            transitionPlayer: player, desktopReady: { [unowned self] in ready }, wakeAnimationDelay: 0.01)
    }
    func post(_ name: Notification.Name) { workspace.post(name: name, object: nil) }
    func lock() { ready = false; distributed.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil) }
    func unlock() { ready = true; distributed.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil) }
    func shutdown() { model.shutdown(); store.removePersistentDomain(forName: suite) }
    func sleepThenMorning() async {
        post(NSWorkspace.willSleepNotification)
        await settle()
        now = nextDay
    }
    func settle() async { try? await Task.sleep(for: .milliseconds(50)) }
}

@MainActor
@Suite(.serialized)
struct WakeAppearanceTransitionTests {
    @Test func wakeCorrectsImmediatelyButWaitsForDisplayThenPlaysOnlyOnce() async {
        let f = WakeFixture(); defer { f.shutdown() }
        await f.sleepThenMorning()
        f.post(NSWorkspace.didWakeNotification)
        await f.settle()
        #expect(f.controller.current == .light) // Correction did not wait for display readiness.
        #expect(f.player.played.isEmpty)
        f.ready = true
        f.post(NSWorkspace.screensDidWakeNotification)
        await f.settle()
        #expect(f.player.played == [.light])
        f.post(NSWorkspace.sessionDidBecomeActiveNotification)
        f.post(NSWorkspace.didWakeNotification)
        f.post(NSWorkspace.screensDidWakeNotification)
        f.unlock()
        await f.settle()
        #expect(f.player.played == [.light])
    }

    @Test func lockedWakeWaitsForUnlockEvenIfDisplayIsAwake() async {
        let f = WakeFixture(); defer { f.shutdown() }
        await f.sleepThenMorning()
        f.lock()
        f.post(NSWorkspace.didWakeNotification)
        f.post(NSWorkspace.screensDidWakeNotification)
        await f.settle()
        #expect(f.controller.current == .light && f.player.played.isEmpty)
        f.unlock()
        await f.settle()
        #expect(f.player.played == [.light])
    }

    @Test func alreadySwitchedBySystemStillAnimatesAgainstPreSleepAppearance() async {
        let f = WakeFixture(); defer { f.shutdown() }
        await f.sleepThenMorning()
        f.controller.current = .light
        f.ready = true
        f.post(NSWorkspace.didWakeNotification)
        await f.settle()
        #expect(f.player.played == [.light])
    }

    @Test func readyDesktopWithoutLockPlaysAfterWake() async {
        let f = WakeFixture(); defer { f.shutdown() }
        await f.sleepThenMorning()
        f.ready = true
        f.post(NSWorkspace.didWakeNotification)
        await f.settle()
        #expect(f.controller.current == .light && f.player.played == [.light])
    }

    @Test func sunsetWakePlaysDarkDirectionAfterDesktopReturns() async {
        let f = WakeFixture(startInDaylight: true); defer { f.shutdown() }
        f.post(NSWorkspace.willSleepNotification)
        f.now = ISO8601DateFormatter().date(from: "2026-10-23T14:00:00Z")!
        f.post(NSWorkspace.didWakeNotification)
        #expect(f.controller.current == .dark && f.player.played.isEmpty)
        f.unlock()
        await f.settle()
        #expect(f.player.played == [.dark])
    }

    @Test func unchangedThemeAndSystemManagedModeDoNotAnimate() async {
        for automatic in [true, false] {
            let f = WakeFixture(automatic: automatic)
            f.post(NSWorkspace.willSleepNotification)
            await f.settle()
            f.ready = true
            f.post(NSWorkspace.didWakeNotification)
            await f.settle()
            #expect(f.player.played.isEmpty)
            #expect(f.controller.current == .dark)
            f.shutdown()
        }
    }

    @Test func animationDisabledStillCorrectsAppearance() async {
        let f = WakeFixture(animation: false); defer { f.shutdown() }
        await f.sleepThenMorning()
        f.ready = true
        f.post(NSWorkspace.didWakeNotification)
        await f.settle()
        #expect(f.controller.current == .light && f.player.played.isEmpty)
    }

    @Test func disablingPendingAnimationClearsItEvenIfReenabledBeforeUnlock() async {
        let f = WakeFixture(); defer { f.shutdown() }
        await f.sleepThenMorning()
        f.post(NSWorkspace.didWakeNotification)
        await f.settle()
        f.model.transitionAnimationEnabled = false
        f.model.transitionAnimationEnabled = true
        f.unlock()
        await f.settle()
        #expect(f.controller.current == .light && f.player.played.isEmpty)
    }

    @Test func targetChangesWhileLockedOnlyLatestTargetIsConsidered() async {
        let f = WakeFixture(); defer { f.shutdown() }
        await f.sleepThenMorning()
        f.post(NSWorkspace.didWakeNotification)
        await f.settle()
        f.model.selectAppearanceMode(.dark)
        f.unlock()
        await f.settle()
        #expect(f.controller.current == .dark && f.player.played.isEmpty)
    }

    @Test func failedCorrectionDoesNotAnimateAndVerifiedRetryCanAnimate() async {
        let f = WakeFixture(); defer { f.shutdown() }
        await f.sleepThenMorning()
        f.controller.failure = .init(message: "Denied", permissionDenied: true)
        f.ready = true
        f.post(NSWorkspace.didWakeNotification)
        await f.settle()
        #expect(f.player.played.isEmpty && f.model.errorMessage != nil)
        f.controller.failure = nil
        f.model.retry()
        await f.settle()
        #expect(f.player.played == [.light])
    }

    @Test func unlockBeforeSlowCorrectionWaitsForVerifiedResult() async {
        let f = WakeFixture(); defer { f.shutdown() }
        await f.sleepThenMorning()
        f.controller.hold = true
        f.post(NSWorkspace.didWakeNotification)
        await f.settle()
        f.unlock()
        await f.settle()
        #expect(f.player.played.isEmpty && f.controller.current == .dark)
        f.controller.finish()
        await f.settle()
        #expect(f.player.played == [.light])
    }

    @Test func obsoleteWakeRequestCannotPlayAfterTargetChanges() async {
        let f = WakeFixture(); defer { f.shutdown() }
        await f.sleepThenMorning()
        f.controller.hold = true
        f.post(NSWorkspace.didWakeNotification) // Light request remains in flight.
        f.model.selectAppearanceMode(.dark)
        f.unlock()
        f.controller.finish() // Stale Light receipt starts the latest Dark request.
        await f.settle()
        #expect(f.player.played.isEmpty)
        f.controller.finish()
        await f.settle()
        #expect(f.controller.current == .dark && f.player.played.isEmpty)
    }

    @Test func shutdownOrSleepingAgainCancelsQueuedPlayback() async {
        for shutdown in [true, false] {
            let f = WakeFixture()
            await f.sleepThenMorning()
            f.post(NSWorkspace.didWakeNotification)
            await f.settle()
            if shutdown { f.model.shutdown() }
            else { f.post(NSWorkspace.willSleepNotification); await f.settle() }
            f.unlock()
            await f.settle()
            #expect(f.player.played.isEmpty)
            f.shutdown()
        }
    }

    @Test func shutdownWhileCorrectionIsInFlightCannotResurrectPlayback() async {
        let f = WakeFixture(); defer { f.shutdown() }
        await f.sleepThenMorning()
        f.controller.hold = true
        f.post(NSWorkspace.didWakeNotification)
        f.model.shutdown()
        f.ready = true
        f.controller.finish()
        await f.settle()
        #expect(f.player.played.isEmpty)
        #expect(f.model.scheduledCheck == nil)
    }

    @Test func reduceMotionStillSuppressesDeferredPresenter() async {
        let player = AppearanceTransitionController(reduceMotion: { true })
        let gate = WakeAppearanceTransition(desktopReady: { true }, delay: 0.01) { target in
            player.play(target, title: "Wake")
        }
        gate.willSleep(appearance: .dark)
        gate.didWake(fallback: .dark)
        #expect(!gate.verified(.light, changed: false))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(player.panel == nil)
        gate.cancelWake()
    }

    @Test func readinessIsCheckedAfterSettleRatherThanAtNotificationArrival() async {
        var ready = false
        var played: [Appearance] = []
        let gate = WakeAppearanceTransition(desktopReady: { ready }, delay: 0.03) { played.append($0) }
        gate.willSleep(appearance: .dark)
        gate.didWake(fallback: .dark)
        #expect(!gate.verified(.light, changed: true))
        ready = true // WindowServer state catches up after the unlock notification.
        try? await Task.sleep(for: .milliseconds(80))
        #expect(played == [.light])
        gate.cancelWake()
    }

    @Test func relockDuringSettleDelayCancelsUntilNextUnlock() async {
        var ready = true
        var played: [Appearance] = []
        let gate = WakeAppearanceTransition(desktopReady: { ready }, delay: 0.05) { played.append($0) }
        gate.willSleep(appearance: .dark)
        gate.didWake(fallback: .dark)
        #expect(!gate.verified(.light, changed: true))
        ready = false
        gate.desktopUnavailable()
        try? await Task.sleep(for: .milliseconds(80))
        #expect(played.isEmpty)
        ready = true
        gate.desktopChanged()
        try? await Task.sleep(for: .milliseconds(80))
        #expect(played == [.light])
        gate.cancelWake()
    }
}
