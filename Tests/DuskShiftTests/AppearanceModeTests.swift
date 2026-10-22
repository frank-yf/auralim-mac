import AppKit
import Combine
import Testing
import DuskShiftCore
@testable import DuskShift

private final class ModeAppearanceSpy: AppearanceApplying {
    var requests: [Appearance] = []
    var result: Result<Void, AppearanceFailure> = .success(())
    var hold = false
    var pending: ((Result<Void, AppearanceFailure>) -> Void)?
    func apply(_ appearance: Appearance, completion: @escaping (Result<Void, AppearanceFailure>) -> Void) {
        requests.append(appearance)
        if hold { pending = completion } else { completion(result) }
    }
}

@MainActor
struct AppearanceModeTests {
    private let day = ISO8601DateFormatter().date(from: "2026-10-22T04:00:00Z")!
    private let night = ISO8601DateFormatter().date(from: "2026-10-22T14:00:00Z")!

    private func flush() async {
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.common]) { continuation.resume() }
        }
    }

    private func withModel(_ values: [String: Any] = [:], clock: (() -> Date)? = nil,
                           _ body: (AppModel, ModeAppearanceSpy, UserDefaults, NotificationCenter) async -> Void) async {
        let suite = "DuskShift.Mode.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        store.set("en", forKey: "language")
        for (key, value) in values { store.set(value, forKey: key) }
        let spy = ModeAppearanceSpy(), workspace = NotificationCenter()
        let model = AppModel(defaults: store, controller: spy, clock: clock ?? { day }, enableTimers: false,
            workspaceNotifications: workspace, systemNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(), systemAppearance: { .dark })
        defer { model.shutdown(); store.removePersistentDomain(forName: suite) }
        await body(model, spy, store, workspace)
    }

    @Test func legacyPausedInstallDoesNotChangeTheSystem() async {
        await withModel { model, spy, _, _ in
            #expect(model.appearanceMode == .dark)
            #expect(model.manualAppearance == nil)
            model.reconcile()
            #expect(spy.requests.isEmpty)
            #expect(model.scheduledCheck == nil)
            model.selectAppearanceMode(.dark)
            #expect(spy.requests == [.dark])
            #expect(model.manualAppearance == .dark)
        }
    }

    @Test func manualSelectionImmediatelyPausesAndPersists() async {
        await withModel(["enabled": true]) { model, spy, store, _ in
            #expect(spy.requests == [.light])
            model.selectAppearanceMode(.dark)
            #expect(spy.requests == [.light, .dark])
            #expect(!model.enabled && model.appearanceMode == .dark)
            #expect(store.bool(forKey: "enabled") == false)
            #expect(store.string(forKey: "manualAppearance") == "dark")
            #expect(model.scheduledCheck == nil)
            model.selectAppearanceMode(.dark)
            #expect(spy.requests == [.light, .dark])
        }
    }

    @Test func selectingAutomaticImmediatelyRestoresTheSolarPlan() async {
        await withModel(["enabled": true], clock: { night }) { model, spy, store, _ in
            #expect(spy.requests.last == .dark)
            model.selectAppearanceMode(.light)
            #expect(spy.requests.last == .light)
            #expect(model.scheduledCheck == nil)
            model.selectAppearanceMode(.automatic)
            #expect(model.enabled && model.appearanceMode == .automatic)
            #expect(model.manualAppearance == nil)
            #expect(store.string(forKey: "manualAppearance") == nil)
            #expect(spy.requests == [.dark, .light, .dark])
            #expect(model.scheduledCheck == model.schedule?.nextCheck)
        }
    }

    @Test func manualChoiceRestoresAndLegacyAutoTakesPriority() async {
        await withModel(["manualAppearance": "dark"]) { model, spy, store, _ in
            #expect(!model.enabled && model.appearanceMode == .dark)
            #expect(spy.requests == [.dark])
            let restoredSpy = ModeAppearanceSpy()
            let restored = AppModel(defaults: store, controller: restoredSpy, clock: { day }, enableTimers: false,
                loginItemController: FakeLoginItem(), locationController: FakeLocation())
            defer { restored.shutdown() }
            #expect(restored.appearanceMode == .dark)
            #expect(restoredSpy.requests == [.dark])
            store.set(true, forKey: "enabled")
            let autoSpy = ModeAppearanceSpy()
            let automatic = AppModel(defaults: store, controller: autoSpy, clock: { day }, enableTimers: false,
                loginItemController: FakeLoginItem(), locationController: FakeLocation())
            defer { automatic.shutdown() }
            #expect(automatic.appearanceMode == .automatic)
            #expect(autoSpy.requests == [.light])
        }
    }

    @Test func wakeAndScheduleEditsPreserveManualChoiceWithoutSolarTimer() async {
        var now = day
        await withModel(["manualAppearance": "light"], clock: { now }) { model, spy, _, workspace in
            now = night
            workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
            await Task.yield()
            model.sunriseOffset = 25
            model.offset = -35
            model.cityID = "America/New_York"
            model.reconcile()
            #expect(spy.requests.count >= 4)
            #expect(spy.requests.allSatisfy { $0 == .light })
            #expect(model.appearanceMode == .light && !model.enabled)
            #expect(model.scheduledCheck == nil)
        }
    }

    @Test func permissionFailureStaysVisibleUntilExplicitRetry() async {
        await withModel { model, spy, _, _ in
            spy.result = .failure(AppearanceFailure(message: "", permissionDenied: true, reason: .authorization))
            model.selectAppearanceMode(.light)
            #expect(model.appearanceMode == .light && !model.enabled)
            #expect(model.errorMessage?.contains("Automation permission") == true)
            model.reconcile()
            model.offset = 10
            #expect(spy.requests == [.light])
            #expect(model.scheduledCheck == nil)
            spy.result = .success(())
            model.retry()
            #expect(spy.requests == [.light, .light])
            #expect(model.errorMessage == nil)
        }
    }

    @Test func latestModeWinsAcrossInFlightManualAndAutomaticRequests() async {
        await withModel { model, spy, _, _ in
            spy.hold = true
            model.selectAppearanceMode(.automatic)
            model.selectAppearanceMode(.dark)
            #expect(spy.requests == [.light])
            spy.pending?(.success(()))
            #expect(spy.requests == [.light, .dark])
            model.selectAppearanceMode(.light)
            spy.pending?(.success(()))
            #expect(spy.requests == [.light, .dark, .light])
            model.selectAppearanceMode(.automatic)
            spy.pending?(.success(()))
            #expect(spy.requests == [.light, .dark, .light, .light])
            spy.pending?(.success(()))
            #expect(!model.isApplying)
            #expect(model.appearanceMode == .automatic)
            #expect(model.scheduledCheck != nil)
        }
    }

    @Test func manualTransientFailuresUseBoundedRetryTimersOnly() async {
        await withModel { model, spy, _, _ in
            spy.result = .failure(AppearanceFailure(message: "Timeout", permissionDenied: false))
            model.selectAppearanceMode(.light)
            #expect(model.scheduledCheck == day.addingTimeInterval(5))
            model.reconcile()
            #expect(model.scheduledCheck == day.addingTimeInterval(10))
            model.reconcile()
            #expect(model.scheduledCheck == nil)
            spy.result = .success(())
            model.retry()
            #expect(model.scheduledCheck == nil)
            #expect(model.errorMessage == nil)
        }
    }

    @Test func bothPresentationsShareModeAndOffsetUpdatesStayLocal() async {
        await withModel { model, _, _, _ in
            let first = SettingsPresentation(model: model), second = SettingsPresentation(model: model)
            model.selectAppearanceMode(.light)
            await flush()
            #expect(first.appearance.value.mode == .light && second.appearance.value.mode == .light)
            model.selectAppearanceMode(.automatic)
            await flush()
            #expect(first.appearance.value.mode == .automatic && second.appearance.value.mode == .automatic)
            var headerChanges = 0
            let subscription = first.appearance.objectWillChange.sink { headerChanges += 1 }
            defer { withExtendedLifetime(subscription) {} }
            model.sunriseOffset = 10
            await flush()
            #expect(headerChanges == 0)
        }
    }
}
