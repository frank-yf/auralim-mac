import AppKit
import Combine
import DuskShiftCore
import Testing
@testable import DuskShift

private final class SettingsAppearanceSpy: AppearanceApplying {
    var requests: [Appearance] = []
    var hold = false
    var denied = false
    var pending: ((Result<Void, AppearanceFailure>) -> Void)?
    func apply(_ appearance: Appearance, completion: @escaping (Result<Void, AppearanceFailure>) -> Void) {
        requests.append(appearance)
        if hold { pending = completion }
        else if denied { completion(.failure(AppearanceFailure(message: "", permissionDenied: true, reason: .authorization))) }
        else { completion(.success(())) }
    }
}

@MainActor
struct SettingsPresentationTests {
    private func flush() async {
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.common]) { continuation.resume() }
        }
    }

    private func withModel(_ body: (AppModel, SettingsAppearanceSpy) async -> Void) async {
        let suite = "DuskShift.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "enabled")
        defaults.set("en", forKey: "language")
        let controller = SettingsAppearanceSpy()
        let model = AppModel(defaults: defaults, controller: controller,
            clock: { ISO8601DateFormatter().date(from: "2026-10-22T04:00:00Z")! }, enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation())
        defer { model.shutdown(); defaults.removePersistentDomain(forName: suite) }
        await body(model, controller)
    }

    @Test func offsetOnlyPublishesEditedSectionAndTimeTextDuringAndAfterVerification() async {
        await withModel { model, controller in
            let state = SettingsPresentation(model: model)
            var changes: [String] = []
            let subscriptions = [
                state.objectWillChange.sink { changes.append("panel") },
                state.appearance.objectWillChange.sink { changes.append("appearance") },
                state.location.objectWillChange.sink { changes.append("location") },
                state.sunrise.objectWillChange.sink { changes.append("sunrise") },
                state.sunset.objectWillChange.sink { changes.append("sunset") },
                state.times.objectWillChange.sink { changes.append("times") },
                state.login.objectWillChange.sink { changes.append("login") }
            ]
            defer { withExtendedLifetime(subscriptions) {} }
            controller.hold = true
            model.sunriseOffset = 15
            #expect(model.isApplying)
            await flush()
            #expect(changes == ["sunrise", "times"])
            controller.pending?(.success(()))
            await flush()
            #expect(changes == ["sunrise", "times"])
            #expect(!model.isApplying)
            changes.removeAll()
            model.offset = -20
            #expect(model.isApplying)
            await flush()
            #expect(changes == ["sunset", "times"])
            controller.pending?(.success(()))
            await flush()
            #expect(changes == ["sunset", "times"])
        }
    }

    @Test func editingOffsetsDoesNotCollapseErrorsOrRepeatDeniedPermissionRequests() async {
        await withModel { model, controller in
            controller.denied = true
            model.retry()
            let state = SettingsPresentation(model: model)
            let error = state.appearance.value.error
            #expect(error != nil)
            let requestCount = controller.requests.count
            var headerChanges = 0
            let subscription = state.appearance.objectWillChange.sink { headerChanges += 1 }
            defer { withExtendedLifetime(subscription) {} }
            model.sunriseOffset = 10
            model.offset = 20
            await flush()
            #expect(state.appearance.value.error == error)
            #expect(headerChanges == 0)
            #expect(controller.requests.count == requestCount)
            #expect(state.sunrise.value == 10 && state.sunset.value == 20)
        }
    }

    @Test func languageAndLocationStillUpdateTheSettings() async {
        await withModel { model, _ in
            let state = SettingsPresentation(model: model)
            model.language = .traditionalChinese
            await flush()
            #expect(state.locale.selection == .traditionalChinese)
            #expect(state.appearance.value.status.contains("淺色"))
            #expect(state.times.value.title.contains("上海"))
            model.cityID = "Asia/Tokyo"
            await flush()
            #expect(state.location.value.timeZoneID == "Asia/Tokyo")
            #expect(state.times.value.title.contains("東京"))
        }
    }

    @Test func duplicateOffsetCommitsDoNotPublishOrReapplyAppearance() async {
        await withModel { model, controller in
            let state = SettingsPresentation(model: model)
            var changes = 0
            let subscriptions = [state.sunrise.objectWillChange.sink { changes += 1 },
                                 state.sunset.objectWillChange.sink { changes += 1 },
                                 state.times.objectWillChange.sink { changes += 1 }]
            defer { withExtendedLifetime(subscriptions) {} }
            let requests = controller.requests.count
            model.sunriseOffset = 0
            model.offset = 0
            await flush()
            #expect(changes == 0)
            #expect(controller.requests.count == requests)
        }
    }
}
