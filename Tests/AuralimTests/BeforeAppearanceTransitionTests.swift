import AppKit
import AuralimCore
import Testing
@testable import Auralim

private final class DeferredAppearance: AppearanceApplying {
    var current: Appearance = .light
    var requests: [Appearance] = []
    var failure: AppearanceFailure?
    var hold = false
    var pending: (() -> Void)?
    var panelReleased: (() -> Bool)?
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        if let panelReleased { #expect(panelReleased()) }
        requests.append(appearance)
        let finish = { [self] in
            if let failure { completion(.failure(failure)); return }
            let changed = current != appearance
            current = appearance
            completion(.success(.init(changed: changed)))
        }
        if hold { pending = finish } else { finish() }
    }
    func finish() { let callback = pending; pending = nil; callback?() }
}

@MainActor
private final class DeferredTransition: AppearanceTransitionPlaying {
    var appearances: [Appearance] = []
    var completions: [@MainActor () -> Void] = []
    var active: (@MainActor () -> Void)?
    func play(_ appearance: Appearance, title: String, completion: @escaping @MainActor () -> Void) {
        appearances.append(appearance); completions.append(completion); active = completion
    }
    func stop() { active = nil }
    func finish() { let callback = active; active = nil; callback?() }
}

@MainActor
private final class DeferredFixture {
    let suite = "Auralim.BeforeTransition.\(UUID().uuidString)"
    let defaults: UserDefaults
    let workspace = NotificationCenter()
    let controller = DeferredAppearance()
    let player = DeferredTransition()
    let day = ISO8601DateFormatter().date(from: "2026-10-22T04:00:00Z")!
    let night = ISO8601DateFormatter().date(from: "2026-10-22T14:00:00Z")!
    var now: Date
    var ready = true
    var model: AppModel!
    init(player realPlayer: AppearanceTransitionPlaying? = nil) {
        now = day
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "transitionAnimationEnabled")
        defaults.set("Asia/Shanghai", forKey: "city")
        model = AppModel(defaults: defaults, controller: controller, clock: { [unowned self] in now }, enableTimers: false,
            workspaceNotifications: workspace, systemNotifications: NotificationCenter(), appearanceNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(),
            systemSettings: { [unowned self] in .init(mode: controller.current == .light ? .light : .dark, appearance: controller.current) },
            transitionPlayer: realPlayer ?? player, desktopReady: { [unowned self] in ready }, wakeAnimationDelay: 0.01)
    }
    func post(_ name: Notification.Name) { workspace.post(name: name, object: nil) }
    func shutdown() { model.shutdown(); defaults.removePersistentDomain(forName: suite) }
}

@MainActor
@Suite(.serialized)
struct BeforeAppearanceTransitionTests {
    @Test func manualSwitchWaitsForAnimationAndTrayKeepsActualAppearance() {
        let f = DeferredFixture(); defer { f.shutdown() }
        f.model.selectAppearanceMode(.dark)
        #expect(f.player.appearances == [.dark])
        #expect(f.controller.requests.isEmpty && f.controller.current == .light)
        #expect(f.model.currentSystemAppearance == .light && f.model.appearanceMode == .dark)
        f.player.finish()
        #expect(f.controller.requests == [.dark] && f.controller.current == .dark)
        #expect(f.model.currentSystemAppearance == .dark)
        f.model.selectAppearanceMode(.light)
        #expect(f.controller.requests == [.dark] && f.player.appearances == [.dark, .light])
        f.player.finish()
        #expect(f.controller.requests == [.dark, .light] && f.controller.current == .light)
    }

    @Test func repeatedReconciliationAndSameTargetEditsDoNotRestartAnimation() {
        let f = DeferredFixture(); defer { f.shutdown() }
        f.model.selectAppearanceMode(.dark)
        f.model.reconcile(); f.model.offset = 10; f.model.reconcile()
        #expect(f.player.appearances == [.dark] && f.controller.requests.isEmpty)
        f.player.finish()
        #expect(f.controller.requests == [.dark])
        f.model.reconcile()
        #expect(f.player.appearances == [.dark])
    }

    @Test func reversingToCurrentAppearanceCancelsAndIgnoresObsoleteCompletion() {
        let f = DeferredFixture(); defer { f.shutdown() }
        f.model.selectAppearanceMode(.dark)
        let obsolete = f.player.completions[0]
        f.model.selectAppearanceMode(.light)
        #expect(f.player.active == nil && f.controller.current == .light)
        let count = f.controller.requests.count
        obsolete()
        #expect(f.controller.requests.count == count && !f.controller.requests.contains(.dark))
    }

    @Test func disablingMidAnimationAppliesLatestTargetImmediatelyExactlyOnce() {
        let f = DeferredFixture(); defer { f.shutdown() }
        f.model.selectAppearanceMode(.dark)
        let obsolete = f.player.completions[0]
        f.model.transitionAnimationEnabled = false
        #expect(f.player.active == nil && f.controller.requests == [.dark])
        obsolete()
        #expect(f.controller.requests == [.dark])
        f.model.transitionAnimationEnabled = true
        #expect(f.player.appearances == [.dark])
    }

    @Test func solarBoundaryIsAnimatedBeforeApplyAndReevaluatedAfterEffect() {
        let f = DeferredFixture(); defer { f.shutdown() }
        f.model.selectAppearanceMode(.automatic) // Day is already light.
        #expect(f.player.appearances.isEmpty)
        f.now = f.night
        f.model.reconcile()
        let requests = f.controller.requests.count
        #expect(f.player.appearances == [.dark] && f.controller.current == .light)
        f.now = f.day // The clock moved again before the effect finished.
        f.player.finish()
        #expect(f.controller.requests.count == requests + 1)
        #expect(f.controller.requests.last == .light && !f.controller.requests.contains(.dark))
    }

    @Test func permissionFailureAppearsAfterEffectAndAutomaticEventsDoNotReplay() {
        let f = DeferredFixture(); defer { f.shutdown() }
        f.controller.failure = .init(message: "Denied", permissionDenied: true)
        f.model.selectAppearanceMode(.dark)
        #expect(f.model.errorMessage == nil && f.controller.requests.isEmpty)
        f.player.finish()
        #expect(f.model.errorMessage != nil && f.controller.current == .light)
        f.model.reconcile()
        #expect(f.player.appearances == [.dark] && f.controller.requests == [.dark])
        f.controller.failure = nil
        f.model.retry()
        #expect(f.player.appearances == [.dark, .dark] && f.controller.requests == [.dark])
        f.player.finish()
        #expect(f.controller.current == .dark && f.model.errorMessage == nil)
    }

    @Test func transientAutomaticRetryDoesNotReplayTheIntroAnimation() {
        let f = DeferredFixture(); defer { f.shutdown() }
        f.controller.failure = .init(message: "Temporary", permissionDenied: false)
        f.model.selectAppearanceMode(.dark); f.player.finish()
        f.controller.failure = nil
        f.model.reconcile()
        #expect(f.player.appearances == [.dark] && f.controller.requests == [.dark, .dark])
        #expect(f.controller.current == .dark)
    }

    @Test func sleepCancelsIntroAndWakeCorrectsWithoutWaitingForAnEffect() {
        let f = DeferredFixture(); defer { f.shutdown() }
        f.model.selectAppearanceMode(.dark)
        let obsolete = f.player.completions[0]
        f.post(NSWorkspace.willSleepNotification)
        #expect(f.player.active == nil && f.controller.requests.isEmpty)
        f.post(NSWorkspace.didWakeNotification)
        #expect(f.controller.current == .dark && f.controller.requests == [.dark])
        obsolete()
        #expect(f.controller.requests == [.dark])
    }

    @Test func screenSleepingMidAnimationCorrectsWithoutWaitingForInvisiblePlayback() {
        let f = DeferredFixture(); defer { f.shutdown() }
        f.model.selectAppearanceMode(.dark)
        f.ready = false
        f.post(NSWorkspace.screensDidSleepNotification)
        #expect(f.player.active == nil && f.controller.current == .dark)
    }

    @Test func unavailableDesktopSkipsIntro() {
        let f = DeferredFixture(); defer { f.shutdown() }
        f.ready = false
        f.model.selectAppearanceMode(.dark)
        #expect(f.player.appearances.isEmpty && f.controller.current == .dark)
    }

    @Test func shutdownCancelsWithoutApplyingEvenIfCompletionWasAlreadyQueued() {
        let f = DeferredFixture(); defer { f.shutdown() }
        f.model.selectAppearanceMode(.dark)
        let obsolete = f.player.completions[0]
        f.model.shutdown(); obsolete()
        #expect(f.controller.requests.isEmpty && f.player.active == nil)
    }

    @Test func asyncSystemRequestsRemainSerializedAfterAnimation() {
        let f = DeferredFixture(); defer { f.shutdown() }
        f.controller.hold = true
        f.model.selectAppearanceMode(.dark); f.player.finish()
        #expect(f.controller.requests == [.dark] && f.model.isApplying)
        f.model.selectAppearanceMode(.light)
        #expect(f.player.appearances == [.dark])
        f.controller.finish()
        #expect(f.player.appearances == [.dark, .light] && f.controller.requests == [.dark])
        f.player.finish()
        #expect(f.controller.requests == [.dark, .light])
        f.controller.finish()
        #expect(!f.model.isApplying && f.controller.current == .light)
    }

    @Test func reducedMotionSkipsAnimationAndAppliesImmediately() {
        let player = AppearanceTransitionController(reduceMotion: { true })
        let f = DeferredFixture(player: player); defer { f.shutdown() }
        f.model.selectAppearanceMode(.dark)
        #expect(player.panel == nil && f.controller.current == .dark)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_BEFORE_TRANSITION_UI_TESTS"] == "1"))
    func realPanelHoldsDuringSystemApplyAndCancelledEffectsCannotApply() async throws {
        _ = NSApplication.shared
        let player = AppearanceTransitionController(reduceMotion: { false }, duration: 0.15)
        let f = DeferredFixture(player: player); defer { f.shutdown() }
        f.controller.panelReleased = { MainActor.assumeIsolated { player.panel?.isVisible == true && player.isHoldingFinalFrame } }
        f.model.selectAppearanceMode(.dark)
        let first = try #require(player.panel)
        #expect(first.isVisible && f.controller.requests.isEmpty)
        try await Task.sleep(for: .milliseconds(300))
        #expect(f.controller.requests == [.dark] && player.panel === first && first.isVisible)
        try await Task.sleep(for: .milliseconds(1000))
        #expect(player.panel == nil && first.contentView == nil)
        f.controller.panelReleased = nil
        f.model.selectAppearanceMode(.light)
        let cancelled = try #require(player.panel)
        f.model.selectAppearanceMode(.dark) // Dark is still the actual system appearance.
        #expect(player.panel == nil && !cancelled.isVisible)
        let requests = f.controller.requests
        try await Task.sleep(for: .milliseconds(300))
        #expect(f.controller.requests == requests && f.controller.current == .dark)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_BEFORE_TRANSITION_UI_TESTS"] == "1"))
    func enablingReduceMotionDuringRealPlaybackFinishesThePendingSwitch() async throws {
        var reduced = false
        let player = AppearanceTransitionController(reduceMotion: { reduced }, duration: 5)
        let f = DeferredFixture(player: player); defer { f.shutdown() }
        f.model.selectAppearanceMode(.dark)
        #expect(player.panel != nil && f.controller.requests.isEmpty)
        reduced = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(player.panel == nil && f.controller.requests == [.dark])
        try await Task.sleep(for: .milliseconds(50))
        #expect(f.controller.requests == [.dark])
    }
}
