import AppKit
import SwiftUI
import Sparkle
import Testing
import AuralimCore
@testable import Auralim

private final class UpdateUIAppearance: AppearanceApplying {
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        completion(.success(.init(changed: false)))
    }
}

@Suite(.serialized)
struct UpdateSettingsInteractionTests {
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_UPDATE_UI_TESTS"] == "1"))
    func footerOnlyShowsRestartAfterReadyAndInvokesTheInstallAction() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        let suite = "Auralim.UpdateUI.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        store.set("zh-Hans", forKey: "language")
        let model = AppModel(defaults: store, controller: UpdateUIAppearance(), enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(),
            appearanceNotifications: NotificationCenter(), loginItemController: FakeLoginItem(),
            locationController: FakeLocation(), systemSettings: { .init(mode: .light, appearance: .light) })
        defer { model.shutdown(); store.removePersistentDomain(forName: suite) }
        let updater = UpdateController()
        let engine = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: updater, delegate: updater)
        // Fixture initializer: version-dependent appcast properties are unused.
        let item = try #require(SUAppcastItem(dictionary: [
            "sparkle:version": "26", "sparkle:shortVersionString": "0.3.1",
            "enclosure": ["url": "https://github.com/frank-yf/auralim-mac/releases/download/v0.3.1/Auralim.zip"]
        ]))
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsContent(model: model, updater: updater)))
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 600, height: 720))
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        defer { window.close() }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AURALIM_UPDATE_UI_OUTPUT"] ?? "/private/tmp/auralim-update-ui")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func capture(_ name: String) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.appendingPathComponent(name + ".png").path]
            try process.run(); process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
        settle()
        try capture("idle-zh-Hans")
        updater.updater(engine, willDownloadUpdate: item, with: NSMutableURLRequest(url: UpdateController.feedURL))
        settle()
        #expect(updater.state == .downloading && !updater.canCheck)
        try capture("downloading-zh-Hans")
        var installs = 0
        #expect(updater.updater(engine, willInstallUpdateOnQuit: item, immediateInstallationBlock: { installs += 1 }))
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            model.language = language
            for theme in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: theme)
                settle()
                #expect(updater.state == .ready("0.3.1") && installs == 0)
                try capture("ready-\(language.rawValue)-\(theme == .aqua ? "light" : "dark")")
            }
        }
        // SwiftUI's accessibility tree is not materialized in the Swift Testing
        // host. Send native mouse events to the visible footer button instead.
        let point = NSPoint(x: 550, y: 51)
        for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            app.sendEvent(event)
        }
        settle()
        #expect(installs == 1 && updater.state == .installing)
        updater.showUpdaterError(URLError(.notConnectedToInternet), acknowledgement: {})
        settle()
        #expect(updater.state == .failed(.network) && updater.canCheck)
        try capture("failed-en-dark")
    }
}
