import AppKit
import Combine

/// Disposable app entry point for the real Sparkle install/relaunch smoke test.
@main
struct UpdateSmoke {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let info = Bundle.main.infoDictionary!
        let output = URL(fileURLWithPath: info["SmokeTestOutput"] as! String)
        func record(_ event: String) {
            let data = (event + "\n").data(using: .utf8)!
            if !FileManager.default.fileExists(atPath: output.path) { FileManager.default.createFile(atPath: output.path, contents: nil) }
            let file = try! FileHandle(forWritingTo: output)
            try! file.seekToEnd(); try! file.write(contentsOf: data); try! file.close()
        }
        let build = info["CFBundleVersion"] as! String
        record("launched-build-" + build)
        if build == "26" {
            record("verified-installed-and-relaunched")
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
            return
        }
        let updater = UpdateController()
        var requestedRestart = false
        let subscription = updater.$state.sink { state in
            record("state-" + String(describing: state))
            if case .ready = state, !requestedRestart {
                requestedRestart = true
                // A visible wait proves readiness does not force an immediate restart.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if info["SmokeQuitInsteadOfRestart"] as? Bool == true {
                        record("normal-quit-action")
                        app.terminate(nil)
                    } else {
                        record("explicit-restart-action")
                        updater.restartToUpdate()
                    }
                }
            }
            if case .failed = state { DispatchQueue.main.async { app.terminate(nil) } }
        }
        updater.start()
        withExtendedLifetime(subscription) { app.run() }
    }
}
