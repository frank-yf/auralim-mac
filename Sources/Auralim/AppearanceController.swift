import AppKit
import AuralimCore

struct AppearanceFailure: Error {
    let message: String
    let permissionDenied: Bool
    enum Reason { case custom, authorization, script(Int), verification }
    var reason: Reason = .custom
}

struct AppearanceApplication {
    let changed: Bool

    static func verified(_ result: NSAppleEventDescriptor?, target: Appearance) -> Result<Self, AppearanceFailure> {
        guard let result, result.numberOfItems == 2,
              let actual = result.atIndex(1), let changed = result.atIndex(2),
              [typeBoolean, typeTrue, typeFalse].contains(actual.descriptorType),
              [typeBoolean, typeTrue, typeFalse].contains(changed.descriptorType),
              actual.booleanValue == (target == .dark) else {
            return .failure(AppearanceFailure(message: "", permissionDenied: false, reason: .verification))
        }
        return .success(Self(changed: changed.booleanValue))
    }
}

protocol AppearanceApplying {
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void)
}

final class AppearanceController: AppearanceApplying {
    private let queue = DispatchQueue(label: "app.duskshift.appearance", qos: .utility)

    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        queue.async {
            let value = appearance == .dark ? "true" : "false"
            let source = """
            with timeout of 10 seconds
                tell application "System Events"
                    tell appearance preferences
                        set didChange to (dark mode is not \(value))
                        if didChange then set dark mode to \(value)
                        return {dark mode, didChange}
                    end tell
                end tell
            end timeout
            """
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let outcome: Result<AppearanceApplication, AppearanceFailure>
            if let error {
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                let denied = code == -1743 || code == -1744
                outcome = .failure(AppearanceFailure(
                    message: error[NSAppleScript.errorMessage] as? String ?? "",
                    permissionDenied: denied, reason: denied ? .authorization : .script(code)))
            } else {
                outcome = AppearanceApplication.verified(result, target: appearance)
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }
}
