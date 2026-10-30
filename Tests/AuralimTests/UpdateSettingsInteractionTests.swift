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
        let updater = UpdateController(preferences: store)
        let engine = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: updater, delegate: updater)
        // Fixture initializer: version-dependent appcast properties are unused.
        let item = try #require(SUAppcastItem(dictionary: [
            "sparkle:version": "26", "sparkle:shortVersionString": "0.3.1",
            "enclosure": ["url": "https://github.com/frank-yf/auralim-mac/releases/download/v0.3.1/Auralim.zip"]
        ]))
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsContent(model: model, updater: updater)))
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 600, height: 640))
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        defer { window.close() }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AURALIM_UPDATE_UI_OUTPUT"] ?? "/private/tmp/auralim-update-ui")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func capture(_ name: String) throws {
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            if let content = window.contentView,
               let scroll = descendants(content).compactMap({ $0 as? NSScrollView }).first,
               let document = scroll.documentView {
                let end = max(0, document.bounds.height - scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? end : 0))
                scroll.reflectScrolledClipView(scroll.contentView); settle()
            }
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
        let point = NSPoint(x: 550, y: 80)
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
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_UPDATE_UI_TESTS"] == "1"))
    func generalPreferenceControlsUseOneTrailingColumn() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular); app.finishLaunching()
        let suite = "Auralim.PreferenceAlignment.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        store.set("zh-Hans", forKey: "language")
        let login = FakeLoginItem()
        let model = AppModel(defaults: store, controller: UpdateUIAppearance(), enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(),
            appearanceNotifications: NotificationCenter(), loginItemController: login,
            locationController: FakeLocation(), systemSettings: { .init(mode: .light, appearance: .light) })
        let updater = UpdateController(preferences: store)
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsContent(model: model, updater: updater)))
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 600, height: 640)); window.center(); window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        defer { window.close(); model.shutdown(); store.removePersistentDomain(forName: suite) }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.18)) }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let host = try #require(window.contentView)
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AURALIM_UPDATE_UI_OUTPUT"] ?? "/private/tmp/auralim-update-ui")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        settle()
        let scroll = try #require(descendants(host).compactMap { $0 as? NSScrollView }.first)
        let document = try #require(scroll.documentView)
        func scrollToBottom() {
            let end = max(0, document.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? end : 0))
            scroll.reflectScrolledClipView(scroll.contentView); settle()
        }
        for language in [AppLanguage.simplifiedChinese, .english] {
            let popup = try #require(descendants(host).compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles.contains("English") })
            try #require(popup.menu).performActionForItem(at: popup.indexOfItem(withTitle: language.nativeName)); settle()
            #expect(model.language == language)
            let toggle = try #require(descendants(host).compactMap { $0 as? NSSwitch }.last)
            _ = toggle.accessibilityPerformPress(); settle()
            #expect(login.requests.last == true && model.loginItemStatus.isRegistered)
            _ = toggle.accessibilityPerformPress(); settle()
            #expect(login.requests.last == false && !model.loginItemStatus.isRegistered)
            let mode = try #require(descendants(host).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 2 && $0.label(forSegment: 0) == model.t("update.mode.manual") })
            for index in [1, 0] {
                mode.selectedSegment = index
                #expect(mode.sendAction(mode.action, to: mode.target)); settle()
                #expect(updater.mode == (index == 0 ? .manual : .automatic))
            }
            for theme in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: theme); scrollToBottom()
                let controls: [NSView] = [toggle, popup, mode]
                let rightEdges = controls.map { $0.convert($0.bounds, to: host).maxX }
                print("Preference trailing edges:", language.rawValue, rightEdges)
                #expect(try #require(rightEdges.max()) - (try #require(rightEdges.min())) < 8)
                #expect(controls.allSatisfy { $0.visibleRect.width > 20 })
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("preferences-\(language.rawValue)-\(theme == .aqua ? "light" : "dark").png"))
            }
        }
    }

}
