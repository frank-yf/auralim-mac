import AppKit
import SwiftUI
import Testing
import DuskShiftCore
@testable import DuskShift

private final class VisualAppearanceController: AppearanceApplying {
    func apply(_ appearance: Appearance, completion: @escaping (Result<Void, AppearanceFailure>) -> Void) {
        completion(.success(()))
    }
}

/// Opt-in visual checks use temporary preferences and fake system services.
@Suite(.serialized)
struct UIAppearanceTests {
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DUSK_SHIFT_VISUAL_TESTS"] == "1"))
    func settingsAndMenuLayouts() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        let suite = "DuskShift.Visual.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("zh-Hans", forKey: "language")
        let login = FakeLoginItem(), location = FakeLocation()
        let model = AppModel(defaults: defaults, controller: VisualAppearanceController(),
            clock: { ISO8601DateFormatter().date(from: "2026-10-22T04:00:00Z")! },
            enableTimers: false, loginItemController: login, locationController: location)
        defer { model.shutdown(); defaults.removePersistentDomain(forName: suite) }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DUSK_SHIFT_VISUAL_OUTPUT"] ?? "/private/tmp/dusk-shift-visual")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func settle() {
            let end = Date(timeIntervalSinceNow: 0.25)
            repeat {
                while Date() < end, let event = app.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) { app.sendEvent(event) }
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            } while Date() < end
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func capture(_ window: NSWindow, _ name: String) throws {
            window.makeKeyAndOrderFront(nil)
            window.contentView?.layoutSubtreeIfNeeded()
            settle()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-l", String(window.windowNumber), output.appendingPathComponent(name + ".png").path]
            try process.run(); process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
        let presenter = SettingsWindowController()
        presenter.show(model: model)
        let window = try #require(presenter.window)
        defer { window.close() }
        let host = try #require(window.contentView)
        settle()
        #expect(!(window.firstResponder is NSTextView))
        #expect(host.bounds.width == 600)
        #expect(host.bounds.height <= 720)
        #expect(descendants(host).compactMap { $0 as? NSSlider }.count == 2)
        #expect(descendants(host).compactMap { $0 as? NSTextField }.filter(\.isEditable).count == 2)
        let switches = descendants(host).compactMap { $0 as? NSSwitch }
        print("Native settings switches:", switches.count)
        #expect(switches.count == 2)
        if switches.count == 2 {
            // SwiftUI forwards the action but its native bridge can return false;
            // verify the binding and service requests after each press instead.
            _ = switches[0].accessibilityPerformPress()
            settle()
            #expect(model.enabled)
            _ = switches[0].accessibilityPerformPress()
            settle()
            #expect(!model.enabled)
            _ = switches[1].accessibilityPerformPress()
            settle()
            #expect(login.requests == [true])
            _ = switches[1].accessibilityPerformPress()
            settle()
            #expect(login.requests == [true, false])
        }
        window.makeFirstResponder(nil)
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            model.language = language
            settle()
            #expect(window.title == model.t("settings.title"))
            for theme in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: theme)
                try capture(window, "settings-\(language.rawValue)-\(theme == .aqua ? "light" : "dark")")
            }
        }
        model.language = .simplifiedChinese
        model.locationMode = .automatic
        location.onEvent?(.resolved(City(id: "current-location", name: "", latitude: 31.23,
                                        longitude: 121.47, timeZoneID: "Asia/Shanghai")))
        settle()
        for slider in descendants(host).compactMap({ $0 as? NSSlider }) {
            #expect(slider.visibleRect.height >= slider.bounds.height - 0.5)
        }
        try capture(window, "settings-automatic-location")
        location.onEvent?(.failed(.denied))
        settle()
        try capture(window, "settings-location-error")
        model.locationMode = .manual
        login.approvalRequired = true
        model.setLaunchAtLogin(true)
        settle()
        #expect(model.loginItemStatus == .requiresApproval)
        try capture(window, "settings-login-approval")
        model.setLaunchAtLogin(false)
        // A short viewport keeps the footer reachable while the body scrolls.
        let small = NSWindow(contentViewController: NSHostingController(rootView: SettingsContent(model: model, height: 400)))
        small.isReleasedWhenClosed = false
        small.title = model.t("settings.title")
        small.setContentSize(NSSize(width: SettingsPanelLayout.width, height: 400))
        small.center()
        defer { small.close() }
        let smallHost = try #require(small.contentView)
        small.makeKeyAndOrderFront(nil)
        settle()
        let smallSliders = descendants(smallHost).compactMap { $0 as? NSSlider }
        #expect(smallSliders.count == 2)
        let scroll = try #require(smallSliders.first?.enclosingScrollView)
        #expect(scroll.documentView!.bounds.height > scroll.contentView.bounds.height)
        if let field = descendants(smallHost).compactMap({ $0 as? NSTextField }).last(where: \.isEditable) {
            field.scrollToVisible(field.bounds.insetBy(dx: 0, dy: -32))
            settle()
            let frame = field.convert(field.bounds, to: smallHost)
            #expect(frame.minY >= 0 && frame.maxY <= smallHost.bounds.maxY)
            #expect(field.visibleRect.height >= field.bounds.height - 0.5)
        }
        try capture(small, "settings-small-screen")
        small.close()
        window.close()
        let menu = NSWindow(contentViewController: NSHostingController(rootView: MenuContent(model: model, quit: {})))
        menu.styleMask = [.borderless]
        menu.isReleasedWhenClosed = false
        menu.setContentSize(NSSize(width: MenuPanelLayout.width, height: MenuPanelLayout.height))
        menu.center()
        defer { menu.close() }
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            model.language = language
            for enabled in [false, true] {
                model.enabled = enabled
                for theme in [NSAppearance.Name.aqua, .darkAqua] {
                    menu.appearance = NSAppearance(named: theme)
                    try capture(menu, "menu-\(language.rawValue)-\(enabled ? "on" : "off")-\(theme == .aqua ? "light" : "dark")")
                    #expect(menu.contentView!.bounds.size == NSSize(width: 320, height: 264))
                }
            }
        }
        print("UI-only verification: three languages, light/dark settings and menu, on/off state, location error, login approval, small-screen scrolling")
    }
}
