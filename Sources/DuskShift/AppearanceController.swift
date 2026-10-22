import AppKit
import DuskShiftCore

struct AppearanceFailure: Error {
    let message: String
    let permissionDenied: Bool
    enum Reason { case custom, authorization, script(Int), verification }
    var reason: Reason = .custom
}

protocol AppearanceApplying {
    func apply(_ appearance: Appearance, completion: @escaping (Result<Void, AppearanceFailure>) -> Void)
}

final class AppearanceController: AppearanceApplying {
    private let queue = DispatchQueue(label: "app.duskshift.appearance", qos: .utility)

    func apply(_ appearance: Appearance, completion: @escaping (Result<Void, AppearanceFailure>) -> Void) {
        queue.async {
            let value = appearance == .dark ? "true" : "false"
            let source = """
            with timeout of 10 seconds
                tell application "System Events"
                    tell appearance preferences
                        if dark mode is not \(value) then set dark mode to \(value)
                        return dark mode
                    end tell
                end tell
            end timeout
            """
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let outcome: Result<Void, AppearanceFailure>
            if let error {
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                let denied = code == -1743 || code == -1744
                outcome = .failure(AppearanceFailure(
                    message: error[NSAppleScript.errorMessage] as? String ?? "",
                    permissionDenied: denied, reason: denied ? .authorization : .script(code)))
            } else if let result, result.booleanValue == (appearance == .dark) {
                outcome = .success(())
            } else {
                outcome = .failure(AppearanceFailure(message: "", permissionDenied: false, reason: .verification))
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }
}
