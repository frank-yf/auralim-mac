import AppKit
import Testing
import AuralimCore
@testable import Auralim

private final class SyncAppearanceSpy: AppearanceApplying {
    var requests: [Appearance] = []
    var result: Result<AppearanceApplication, AppearanceFailure> = .success(.init(changed: false))
    var hold = false
    var pending: ((Result<AppearanceApplication, AppearanceFailure>) -> Void)?

    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        requests.append(appearance)
        if hold { pending = completion } else { completion(result) }
    }
}

@MainActor
struct AppearanceSyncTests {
    private func flush() async {
        await Task.yield()
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.common]) { continuation.resume() }
        }
    }

    private func withModel(_ body: (AppModel, SyncAppearanceSpy, NotificationCenter, NotificationCenter,
                                    (SystemAppearanceSettings) -> Void) async -> Void) async {
        let suite = "Auralim.AppearanceSync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("en", forKey: "language")
        defaults.set("Asia/Shanghai", forKey: "city")
        var system = SystemAppearanceSettings(mode: .light, appearance: .light)
        let spy = SyncAppearanceSpy(), appearance = NotificationCenter(), application = NotificationCenter()
        let model = AppModel(defaults: defaults, controller: spy,
            clock: { ISO8601DateFormatter().date(from: "2026-10-22T04:00:00Z")! }, enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: application,
            appearanceNotifications: appearance, loginItemController: FakeLoginItem(),
            locationController: FakeLocation(), systemSettings: { system })
        defer { model.shutdown(); defaults.removePersistentDomain(forName: suite) }
        await body(model, spy, appearance, application, { system = $0 })
    }

    @Test func systemAppearanceChangesSynchronizeOpenPresentationsAndStopAfterShutdown() async {
        await withModel { model, spy, notifications, _, setSystem in
            let settings = SettingsPresentation(model: model), menu = SettingsPresentation(model: model)
            setSystem(.init(mode: .dark, appearance: .dark))
            notifications.post(name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
            await flush()
            #expect(settings.appearance.value.mode == .dark && menu.appearance.value.mode == .dark)
            #expect(settings.appearance.value.status == "System managed · Currently Dark")
            #expect(spy.requests.isEmpty)
            model.shutdown()
            setSystem(.init(mode: .light, appearance: .light))
            notifications.post(name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
            await flush()
            #expect(model.appearanceMode == .dark)
            #expect(spy.requests.isEmpty)
        }
    }

    @Test func activationRefreshesSystemAutomaticModeEvenWhenThemeHasNotChanged() async {
        await withModel { model, spy, _, application, setSystem in
            let settings = SettingsPresentation(model: model)
            setSystem(.init(mode: .automatic, appearance: .light))
            application.post(name: NSApplication.didBecomeActiveNotification, object: nil)
            await flush()
            #expect(settings.appearance.value.mode == nil)
            #expect(settings.appearance.value.status == "System Auto · Currently Light")
            #expect(spy.requests.isEmpty)
        }
    }

    @Test func appearanceEventsReconcileAppModeWithoutRepeatingDeniedPermission() async {
        await withModel { model, spy, notifications, application, _ in
            model.selectAppearanceMode(.automatic)
            notifications.post(name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
            await flush()
            #expect(spy.requests == [.light, .light])
            spy.result = .failure(.init(message: "", permissionDenied: true, reason: .authorization))
            model.selectAppearanceMode(.dark)
            let count = spy.requests.count
            notifications.post(name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
            application.post(name: NSApplication.didBecomeActiveNotification, object: nil)
            await flush()
            #expect(spy.requests.count == count)
            #expect(model.errorMessage != nil)
        }
    }

    @Test func retryErrorAppearsOnlyAfterFailureAndClearsWhileRetryingAndAfterSuccess() async {
        await withModel { model, spy, _, _, _ in
            let settings = SettingsPresentation(model: model)
            #expect(settings.appearance.value.error == nil)
            spy.result = .failure(.init(message: "", permissionDenied: true, reason: .authorization))
            model.selectAppearanceMode(.dark)
            await flush()
            #expect(settings.appearance.value.error != nil)
            spy.hold = true
            model.retry()
            await flush()
            #expect(model.isApplying)
            #expect(settings.appearance.value.error == nil)
            spy.pending?(.success(.init(changed: false)))
            await flush()
            #expect(!model.isApplying)
            #expect(settings.appearance.value.error == nil)
            #expect(settings.appearance.value.status == "App manual · Currently Dark")
        }
    }
}
