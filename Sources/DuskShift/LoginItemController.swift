import ServiceManagement

enum LoginItemStatus: Equatable {
    case notRegistered, enabled, requiresApproval, notFound, unknown

    var isRegistered: Bool { self == .enabled || self == .requiresApproval }
    var localizationKey: String {
        switch self {
        case .notRegistered: return "login.disabled"
        case .enabled: return "login.enabled"
        case .requiresApproval: return "login.approval"
        case .notFound: return "login.notFound"
        case .unknown: return "login.unknown"
        }
    }
}

@MainActor
protocol LoginItemControlling {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

@MainActor
final class LoginItemController: LoginItemControlling {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .unknown
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
