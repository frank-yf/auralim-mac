import AppKit
import Testing
import DuskShiftCore
@testable import DuskShift

private final class TransitionAppearance: AppearanceApplying {
    var current: Appearance = .light
    var failure: AppearanceFailure?
    var hold = false
    var pending: ((Result<AppearanceApplication, AppearanceFailure>) -> Void)?
    var requested: Appearance = .light
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
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

    private func withModel(enabled: Bool = false, clock: (() -> Date)? = nil,
                           _ body: (AppModel, TransitionAppearance, TransitionRecorder) -> Void) {
        let suite = "DuskShift.Transition.\(UUID().uuidString)", controller = TransitionAppearance(), player = TransitionRecorder()
        let store = UserDefaults(suiteName: suite)!
        store.set(enabled, forKey: "enabled"); store.set("zh-Hans", forKey: "language")
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
}
