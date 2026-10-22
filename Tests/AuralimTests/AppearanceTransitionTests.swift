import AppKit
import Combine
import Testing
import AuralimCore
@testable import Auralim

private final class TransitionAppearance: AppearanceApplying {
    var current: Appearance = .light
    var requests = 0
    var failure: AppearanceFailure?
    var hold = false
    var pending: ((Result<AppearanceApplication, AppearanceFailure>) -> Void)?
    var requested: Appearance = .light
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        requests += 1
        requested = appearance
        if hold { pending = completion }
        else if let failure { completion(.failure(failure)) }
        else {
            let changed = current != appearance
            current = appearance
            completion(.success(AppearanceApplication(changed: changed)))
        }
    }
    func finish() {
        let completion = pending
        pending = nil
        let changed = current != requested
        current = requested
        completion?(.success(AppearanceApplication(changed: changed)))
    }
}

@MainActor
private final class TransitionRecorder: AppearanceTransitionPlaying {
    var appearances: [Appearance] = []
    var titles: [String] = []
    var stops = 0
    func play(_ appearance: Appearance, title: String) { appearances.append(appearance); titles.append(title) }
    func stop() { stops += 1 }
}

@MainActor
struct AppearanceTransitionTests {
    private let day = ISO8601DateFormatter().date(from: "2026-10-22T04:00:00Z")!
    private let night = ISO8601DateFormatter().date(from: "2026-10-22T14:00:00Z")!

    private func withModel(enabled: Bool = false, clock: (() -> Date)? = nil, animation: Bool? = true,
                           _ body: (AppModel, TransitionAppearance, TransitionRecorder) -> Void) {
        let suite = "Auralim.Transition.\(UUID().uuidString)", controller = TransitionAppearance(), player = TransitionRecorder()
        let store = UserDefaults(suiteName: suite)!
        store.set(enabled, forKey: "enabled"); store.set("zh-Hans", forKey: "language")
        if let animation { store.set(animation, forKey: "transitionAnimationEnabled") }
        let model = AppModel(defaults: store, controller: controller, clock: clock ?? { day }, enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(),
            systemSettings: { .init(mode: .light, appearance: .light) }, transitionPlayer: player)
        defer { model.shutdown(); store.removePersistentDomain(forName: suite) }
        body(model, controller, player)
    }

    @Test func verifiedReceiptsDistinguishActualChangesFromNoOps() throws {
        func descriptor(_ dark: Bool, _ changed: Bool) -> NSAppleEventDescriptor {
            let list = NSAppleEventDescriptor.list()
            list.insert(NSAppleEventDescriptor(boolean: dark), at: 1)
            list.insert(NSAppleEventDescriptor(boolean: changed), at: 2)
            return list
        }
        #expect(try AppearanceApplication.verified(descriptor(true, true), target: .dark).get().changed)
        #expect(try !AppearanceApplication.verified(descriptor(false, false), target: .light).get().changed)
        for result in [descriptor(true, true), NSAppleEventDescriptor.list(), NSAppleEventDescriptor(boolean: false), nil] {
            if case .failure(let failure) = AppearanceApplication.verified(result, target: .light) {
                if case .verification = failure.reason {} else { Issue.record("Expected verification failure") }
            } else { Issue.record("Unverified response must not animate") }
        }
        let malformed = NSAppleEventDescriptor.list()
        malformed.insert(NSAppleEventDescriptor(string: "false"), at: 1)
        malformed.insert(NSAppleEventDescriptor(boolean: true), at: 2)
        if case .success = AppearanceApplication.verified(malformed, target: .light) { Issue.record("Malformed response accepted") }
    }

    @Test func manualSwitchesPlaySunsetThenSunriseAfterSuccess() {
        withModel { model, _, player in
            #expect(player.appearances.isEmpty)
            model.selectAppearanceMode(.dark)
            #expect(player.appearances == [.dark])
            #expect(player.titles == ["日落 · 切换至深色"])
            model.selectAppearanceMode(.light)
            #expect(player.appearances == [.dark, .light])
            #expect(player.titles.last == "日出 · 切换至浅色")
        }
    }

    @Test func repeatedSelectionVerificationAndScheduleEditsDoNotReplay() {
        withModel { model, _, player in
            model.selectAppearanceMode(.light) // System is already light.
            #expect(player.appearances.isEmpty)
            model.selectAppearanceMode(.dark)
            model.selectAppearanceMode(.dark)
            model.reconcile(); model.retry(); model.offset = 15
            #expect(player.appearances == [.dark])
        }
    }

    @Test func failedSwitchDoesNotAnimateAndSuccessfulRetryCanAnimate() {
        withModel { model, controller, player in
            controller.failure = AppearanceFailure(message: "Denied", permissionDenied: true)
            model.selectAppearanceMode(.dark)
            #expect(player.appearances.isEmpty)
            #expect(model.errorMessage != nil)
            controller.failure = nil
            model.retry()
            #expect(player.appearances == [.dark])
            #expect(model.errorMessage == nil)
        }
    }

    @Test func staleCompletionNeverPlaysTheWrongDirection() {
        withModel { model, controller, player in
            controller.hold = true
            model.selectAppearanceMode(.dark)
            model.selectAppearanceMode(.light)
            #expect(player.appearances.isEmpty)
            controller.finish() // Obsolete Dark request completed; latest Light is now pending.
            #expect(player.appearances.isEmpty)
            controller.finish()
            #expect(player.appearances == [.light])
        }
    }

    @Test func solarSwitchesAnimateButOpeningThePanelDoesNot() {
        var now = day
        withModel(enabled: true, clock: { now }) { model, _, player in
            #expect(player.appearances.isEmpty)
            now = night
            model.reconcile()
            #expect(player.appearances == [.dark])
            model.reconcile()
            #expect(player.appearances == [.dark])
            model.selectAppearanceMode(.light)
            #expect(player.appearances == [.dark, .light])
            model.selectAppearanceMode(.automatic)
            #expect(player.appearances == [.dark, .light, .dark])
        }
    }

    @Test func shutdownStopsTheTransientPresenter() {
        withModel { model, _, player in
            model.selectAppearanceMode(.dark)
            model.shutdown()
            #expect(player.stops == 1)
        }
    }

    @Test func animationDefaultsOffIncludingUpgradesAndAutomaticUsers() {
        for automatic in [false, true] {
            withModel(enabled: automatic, animation: nil) { model, controller, player in
                #expect(!model.transitionAnimationEnabled)
                model.selectAppearanceMode(.dark)
                #expect(controller.current == .dark)
                model.selectAppearanceMode(.light)
                #expect(controller.current == .light)
                model.selectAppearanceMode(.automatic)
                #expect(model.enabled && model.scheduledCheck != nil)
                #expect(player.appearances.isEmpty)
            }
        }
    }

    @Test func preferencePersistsAndPublishesOnlyAppearanceWithoutReapplying() async {
        let suite = "Auralim.AnimationPreference.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        store.set(true, forKey: "enabled")
        let controller = TransitionAppearance(), player = TransitionRecorder()
        func makeModel(_ controller: TransitionAppearance, _ player: TransitionRecorder) -> AppModel {
            AppModel(defaults: store, controller: controller, clock: { day }, enableTimers: false,
                workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(),
                loginItemController: FakeLoginItem(), locationController: FakeLocation(),
                systemSettings: { .init(mode: .light, appearance: .light) }, transitionPlayer: player)
        }
        let model = makeModel(controller, player), state = SettingsPresentation(model: model)
        defer { model.shutdown(); store.removePersistentDomain(forName: suite) }
        #expect(!model.transitionAnimationEnabled && !state.appearance.value.animationEnabled)
        let before = controller.requests, nextCheck = model.scheduledCheck
        var changes: [String] = []
        let subscriptions = [state.objectWillChange.sink { changes.append("panel") },
            state.appearance.objectWillChange.sink { changes.append("appearance") },
            state.times.objectWillChange.sink { changes.append("times") },
            state.location.objectWillChange.sink { changes.append("location") },
            state.login.objectWillChange.sink { changes.append("login") },
            state.sunrise.objectWillChange.sink { changes.append("sunrise") },
            state.sunset.objectWillChange.sink { changes.append("sunset") }]
        defer { withExtendedLifetime(subscriptions) {} }
        model.transitionAnimationEnabled = true
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.common]) { continuation.resume() }
        }
        #expect(changes == ["appearance"])
        #expect(state.appearance.value.animationEnabled)
        #expect(store.bool(forKey: "transitionAnimationEnabled"))
        let restored = makeModel(TransitionAppearance(), TransitionRecorder())
        #expect(restored.transitionAnimationEnabled)
        restored.shutdown()
        model.transitionAnimationEnabled = false
        #expect(!store.bool(forKey: "transitionAnimationEnabled"))
        let restoredOff = makeModel(TransitionAppearance(), TransitionRecorder())
        #expect(!restoredOff.transitionAnimationEnabled)
        restoredOff.shutdown()
        #expect(model.enabled && model.scheduledCheck == nextCheck)
        #expect(controller.requests == before && player.appearances.isEmpty)
        #expect(player.stops == 1)
    }

    @Test func disablingDuringAnInFlightRequestSuppressesItsAnimation() {
        withModel { model, controller, player in
            controller.hold = true
            model.selectAppearanceMode(.dark)
            model.transitionAnimationEnabled = false
            controller.finish()
            #expect(controller.current == .dark && model.appearanceMode == .dark)
            #expect(player.appearances.isEmpty && player.stops == 1)
            let count = controller.requests
            model.transitionAnimationEnabled = true
            #expect(player.appearances.isEmpty && controller.requests == count)
        }
    }

    @Test func turningAnimationOffStopsCurrentEffectWithoutChangingAppearance() {
        withModel { model, controller, player in
            model.selectAppearanceMode(.dark)
            #expect(player.appearances == [.dark])
            let count = controller.requests
            model.transitionAnimationEnabled = false
            #expect(player.stops == 1 && controller.requests == count)
            #expect(model.appearanceMode == .dark && controller.current == .dark)
            model.transitionAnimationEnabled = true
            #expect(player.appearances == [.dark])
            model.selectAppearanceMode(.light)
            #expect(player.appearances == [.dark, .light])
        }
    }

    @Test func halfScreenFrameIsCenteredAndCoversHalfTheDisplayArea() {
        for screen in [CGRect(x: 0, y: 0, width: 1920, height: 1080),
                       CGRect(x: -2560, y: -360, width: 2560, height: 1440),
                       CGRect(x: 100, y: 1200, width: 1512, height: 982)] {
            let frame = HalfScreenTransition.frame(on: screen)
            #expect(abs(frame.midX - screen.midX) < 0.001)
            #expect(abs(frame.midY - screen.midY) < 0.001)
            #expect(abs(frame.width * frame.height / (screen.width * screen.height) - 0.5) < 0.00001)
            #expect(frame.minX > screen.minX && frame.maxX < screen.maxX)
            #expect(frame.minY > screen.minY && frame.maxY < screen.maxY)
        }
    }

    @Test func celestialOrbitRisesInTheEastAndSetsInTheWestForBothBodies() {
        let size = CGSize(width: 1920, height: 540)
        let horizon = size.height * 0.90
        let east = CelestialOrbit.position(progress: 0, rising: true, size: size)
        let noon = CelestialOrbit.position(progress: 1, rising: true, size: size)
        let west = CelestialOrbit.position(progress: 1, rising: false, size: size)
        #expect(east.x < size.width / 2 && east.y > horizon)
        #expect(abs(noon.x - size.width / 2) < 0.001 && noon.y < horizon)
        #expect(west.x > size.width / 2 && west.y > horizon)
        #expect(CelestialOrbit.position(progress: 0, rising: false, size: size) == noon)
        // At dawn the Sun rises / Moon sets; at dusk these tracks exchange.
        for rising in [true, false] {
            let positions = (0...20).map { CelestialOrbit.position(progress: Double($0) / 20, rising: rising, size: size) }
            for (before, after) in zip(positions, positions.dropFirst()) {
                #expect(after.x > before.x)
                #expect(rising ? after.y < before.y : after.y > before.y)
            }
        }
    }

    @Test func celestialOrbitClampsTransientAnimationOvershoot() {
        let size = CGSize(width: 1512, height: 491)
        for rising in [true, false] {
            #expect(CelestialOrbit.position(progress: -0.2, rising: rising, size: size) == CelestialOrbit.position(progress: 0, rising: rising, size: size))
            #expect(CelestialOrbit.position(progress: 1.2, rising: rising, size: size) == CelestialOrbit.position(progress: 1, rising: rising, size: size))
        }
    }

}
