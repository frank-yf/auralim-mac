import AppKit
import Testing
import AuralimCore
@testable import Auralim

@MainActor
final class FakeLoginItem: LoginItemControlling {
    var status: LoginItemStatus = .notRegistered
    var requests: [Bool] = []
    var approvalRequired = false
    var failure: NSError?
    var settingsOpened = false
    func setEnabled(_ enabled: Bool) throws {
        requests.append(enabled)
        if let failure { throw failure }
        status = enabled ? (approvalRequired ? .requiresApproval : .enabled) : .notRegistered
    }
    func openSystemSettings() { settingsOpened = true }
}

private final class LoginAppearanceSpy: AppearanceApplying {
    var requests = 0
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        requests += 1; completion(.success(AppearanceApplication(changed: false)))
    }
}

@MainActor
struct LoginItemTests {
    private func withModel(_ body: (AppModel, FakeLoginItem, LoginAppearanceSpy, NotificationCenter) async throws -> Void) async rethrows {
        let suite = "Auralim.Login.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "enabled")
        defaults.set("en", forKey: "language")
        let service = FakeLoginItem(), appearance = LoginAppearanceSpy(), notifications = NotificationCenter()
        let model = AppModel(defaults: defaults, controller: appearance, enableTimers: false,
                             systemNotifications: notifications, loginItemController: service)
        defer { model.shutdown(); defaults.removePersistentDomain(forName: suite) }
        try await body(model, service, appearance, notifications)
    }

    @Test func registrationAndRemovalPreserveAppearanceAndSchedule() async {
        await withModel { model, service, appearance, _ in
            #expect(service.requests.isEmpty)
            let check = model.scheduledCheck, count = appearance.requests
            model.setLaunchAtLogin(true)
            #expect(model.loginItemStatus == .enabled)
            model.setLaunchAtLogin(true)
            #expect(service.requests == [true])
            model.setLaunchAtLogin(false)
            #expect(model.loginItemStatus == .notRegistered)
            #expect(service.requests == [true, false])
            #expect(model.enabled)
            #expect(appearance.requests == count)
            #expect(model.scheduledCheck == check)
        }
    }

    @Test func pendingApprovalCanOpenSettingsAndBeCancelled() async {
        await withModel { model, service, _, _ in
            service.approvalRequired = true
            model.setLaunchAtLogin(true)
            #expect(model.loginItemStatus == .requiresApproval)
            #expect(model.loginItemStatus.isRegistered)
            #expect(model.t(model.loginItemStatus.localizationKey).contains("not active"))
            model.openLoginItemSettings()
            #expect(service.settingsOpened)
            model.setLaunchAtLogin(false)
            #expect(model.loginItemStatus == .notRegistered)
        }
    }

    @Test func failuresReadActualStateAndRelocalize() async {
        await withModel { model, service, _, _ in
            service.failure = NSError(domain: "LoginTest", code: 42, userInfo: [NSLocalizedDescriptionKey: "denied"])
            model.setLaunchAtLogin(true)
            #expect(model.loginItemStatus == .notRegistered)
            #expect(model.loginItemError == "Could not change launch at login: denied")
            model.language = .simplifiedChinese
            #expect(model.loginItemError == "无法更改登录时启动：denied")
            service.failure = nil
            model.setLaunchAtLogin(true)
            service.failure = NSError(domain: "LoginTest", code: 42)
            model.setLaunchAtLogin(false)
            #expect(model.loginItemStatus == .enabled)
            #expect(model.loginItemError != nil)
        }
    }

    @Test func returningFromSystemSettingsRefreshesWithoutApplyingAppearance() async {
        await withModel { model, service, appearance, notifications in
            model.setLaunchAtLogin(true)
            let count = appearance.requests, check = model.scheduledCheck
            service.status = .requiresApproval
            notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
            await Task.yield()
            #expect(model.loginItemStatus == .requiresApproval)
            service.status = .notRegistered
            model.refreshLoginItemStatus()
            #expect(!model.loginItemStatus.isRegistered)
            #expect(appearance.requests == count)
            #expect(model.scheduledCheck == check)
        }
    }

    @Test func openingSettingsReadsExternalStateAndStartupDoesNotRegister() async {
        await withModel { model, service, _, _ in
            service.status = .enabled
            model.refreshLoginItemStatus()
            #expect(model.loginItemStatus == .enabled)
            service.status = .notFound
            model.refreshLoginItemStatus()
            #expect(model.loginItemStatus == .notFound)
            #expect(!model.loginItemStatus.isRegistered)
            #expect(service.requests.isEmpty)
        }
    }
}
