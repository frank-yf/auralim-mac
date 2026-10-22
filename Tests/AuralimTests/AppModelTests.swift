import Testing
import AppKit
import AuralimCore
@testable import Auralim

private final class FakeAppearance: AppearanceApplying {
    var requests: [Appearance] = []
    var result: Result<AppearanceApplication, AppearanceFailure> = .success(AppearanceApplication(changed: false))
    var hold = false
    var pending: ((Result<AppearanceApplication, AppearanceFailure>) -> Void)?
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        requests.append(appearance)
        if hold { pending = completion } else { completion(result) }
    }
}

final class AppModelTests {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @MainActor
    @Test
    func testDisabledAppDoesNotTouchSystemOrScheduleTimer() {
        let store = UserDefaults(suiteName: UUID().uuidString)!
        let controller = FakeAppearance()
        let model = AppModel(defaults: store, controller: controller, clock: { self.date("2026-10-22T04:00:00Z") }, enableTimers: false)
        defer { model.shutdown() }
        #expect(controller.requests.isEmpty)
        #expect(model.scheduledCheck == nil)
        #expect(model.schedule != nil)
    }

    @MainActor
    @Test
    func testWakeNotificationReconcilesImmediatelyAndReschedules() async {
        let store = UserDefaults(suiteName: UUID().uuidString)!
        store.set(true, forKey: "enabled")
        let controller = FakeAppearance()
        let notifications = NotificationCenter()
        var now = date("2026-10-22T04:00:00Z")
        let model = AppModel(defaults: store, controller: controller, clock: { now }, enableTimers: false, workspaceNotifications: notifications)
        defer { model.shutdown() }
        #expect(controller.requests == [.light])
        now = date("2026-10-22T14:00:00Z")
        notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        await Task.yield()
        #expect(controller.requests == [.light, .dark])
        #expect(model.scheduledCheck! > now)
        model.enabled = false
        #expect(model.scheduledCheck == nil)
    }

    @MainActor
    @Test
    func testPermissionDenialDoesNotPromptRepeatedlyUntilExplicitRetry() {
        let store = UserDefaults(suiteName: UUID().uuidString)!
        store.set(true, forKey: "enabled")
        let controller = FakeAppearance()
        controller.result = .failure(AppearanceFailure(message: "Denied", permissionDenied: true))
        let model = AppModel(defaults: store, controller: controller, clock: { self.date("2026-10-22T04:00:00Z") }, enableTimers: false)
        defer { model.shutdown() }
        model.reconcile(); model.reconcile()
        #expect(controller.requests.count == 1)
        #expect(model.errorMessage == "Denied")
        controller.result = .success(AppearanceApplication(changed: false))
        model.retry()
        #expect(controller.requests.count == 2)
        #expect(model.errorMessage == nil)
    }

    @MainActor
    @Test
    func testTransientFailureRetriesAreBounded() {
        let store = UserDefaults(suiteName: UUID().uuidString)!
        store.set(true, forKey: "enabled")
        let controller = FakeAppearance()
        controller.result = .failure(AppearanceFailure(message: "Timeout", permissionDenied: false))
        let now = date("2026-10-22T04:00:00Z")
        let model = AppModel(defaults: store, controller: controller, clock: { now }, enableTimers: false)
        defer { model.shutdown() }
        #expect(model.scheduledCheck == now.addingTimeInterval(5))
        model.reconcile()
        #expect(model.scheduledCheck == now.addingTimeInterval(10))
        model.reconcile()
        #expect(model.scheduledCheck == model.schedule?.nextCheck)
    }

    @MainActor
    @Test
    func testInFlightRequestIsSerializedAndOldConfigurationIsReconciled() {
        let store = UserDefaults(suiteName: UUID().uuidString)!
        store.set(true, forKey: "enabled")
        let controller = FakeAppearance(); controller.hold = true
        let model = AppModel(defaults: store, controller: controller, clock: { self.date("2026-10-22T04:00:00Z") }, enableTimers: false)
        defer { model.shutdown() }
        model.cityID = "America/New_York"
        model.reconcile()
        #expect(controller.requests == [.light])
        controller.hold = false
        controller.pending?(.success(AppearanceApplication(changed: false)))
        #expect(controller.requests == [.light, .dark])
        #expect(model.schedule?.appearance == .dark)
        #expect(!(model.isApplying))
    }

    @MainActor
    @Test
    func testSettingsPersistAndOutOfRangeOffsetIsRepairedAtStartup() {
        let store = UserDefaults(suiteName: UUID().uuidString)!
        store.set(500, forKey: "offset")
        let model = AppModel(defaults: store, controller: FakeAppearance(), enableTimers: false)
        defer { model.shutdown() }
        #expect(model.offset == 120)
        model.cityID = "beijing"; model.offset = -30
        #expect(store.string(forKey: "city") == "beijing")
        #expect(store.integer(forKey: "offset") == -30)
    }

    @MainActor
    @Test
    func testSunriseOffsetPersistsWithoutChangingLegacySunsetOffset() throws {
        let store = UserDefaults(suiteName: UUID().uuidString)!
        store.set(-30, forKey: "offset")
        let rise = try #require(SolarCalculator().day(containing: date("2026-10-22T04:00:00Z"), city: City.all[0]).sunrise)
        let controller = FakeAppearance()
        let model = AppModel(defaults: store, controller: controller, clock: { rise }, enableTimers: false)
        defer { model.shutdown() }
        #expect(model.sunriseOffset == 0)
        #expect(model.offset == -30)
        model.enabled = true
        #expect(controller.requests.last == .light)
        model.sunriseOffset = 37
        #expect(controller.requests.last == .dark)
        #expect(model.schedule?.nextTransition?.date == rise.addingTimeInterval(37 * 60))
        let restored = AppModel(defaults: store, controller: FakeAppearance(), clock: { rise }, enableTimers: false)
        defer { restored.shutdown() }
        #expect(restored.sunriseOffset == 37)
        #expect(restored.offset == -30)
    }
    @MainActor
    @Test
    func languageSwitchIsImmediatePersistsAndDoesNotApplyAppearance() {
        let suite = "Auralim.Language.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        store.set(true, forKey: "enabled")
        store.set(-30, forKey: "offset")
        let controller = FakeAppearance()
        let model = AppModel(defaults: store, controller: controller,
                             clock: { self.date("2026-10-22T04:00:00Z") }, enableTimers: false,
                             preferredLanguages: { ["zh-CN"] })
        defer { model.shutdown() }
        let requests = controller.requests.count
        let nextCheck = model.scheduledCheck
        let nextSwitch = model.schedule?.nextTransition
        model.language = .english
        #expect(model.status == "System appearance confirmed: Light")
        #expect(model.cityName() == "Shanghai")
        #expect(model.t("sunrise.switch") == "Switch to light")
        model.language = .traditionalChinese
        #expect(model.status == "已確認系統為淺色外觀")
        #expect(controller.requests.count == requests)
        #expect(model.scheduledCheck == nextCheck)
        #expect(model.schedule?.nextTransition == nextSwitch)
        #expect(model.offset == -30)
        let restored = AppModel(defaults: store, controller: FakeAppearance(), enableTimers: false)
        defer { restored.shutdown() }
        #expect(restored.language == .traditionalChinese)
        #expect(restored.offset == -30)
    }

    @MainActor
    @Test
    func existingPermissionErrorRelocalizesAndInvalidPreferenceFallsBack() {
        let suite = "Auralim.LanguageError.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        store.set(true, forKey: "enabled")
        store.set("unsupported", forKey: "language")
        let controller = FakeAppearance()
        controller.result = .failure(AppearanceFailure(message: "", permissionDenied: true, reason: .authorization))
        let model = AppModel(defaults: store, controller: controller, enableTimers: false,
                             preferredLanguages: { ["zh-TW"] })
        defer { model.shutdown() }
        #expect(model.language == .system)
        #expect(model.errorMessage?.contains("自動化權限") == true)
        let requests = controller.requests.count
        model.language = .english
        #expect(model.errorMessage?.contains("Automation permission") == true)
        #expect(controller.requests.count == requests)
    }
}
