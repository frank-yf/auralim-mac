import AppKit
import SwiftUI
import Testing
import AuralimCore
@testable import Auralim

private final class ModeUIAppearance: AppearanceApplying {
    var requests: [Appearance] = []
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        requests.append(appearance)
        completion(.success(AppearanceApplication(changed: false)))
    }
}

@Suite(.serialized)
struct AppearanceModeInteractionTests {
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DUSK_SHIFT_MODE_UI_TESTS"] == "1"))
    func nativePickersStaySynchronizedAndFitBothPanels() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        let suite = "Auralim.ModeUI.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("zh-Hans", forKey: "language")
        var system = SystemAppearanceSettings(mode: .automatic, appearance: .light)
        let controller = ModeUIAppearance()
        let model = AppModel(defaults: defaults, controller: controller,
            clock: { ISO8601DateFormatter().date(from: "2026-10-22T04:00:00Z")! }, enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(), systemSettings: { system })
        defer { model.shutdown(); defaults.removePersistentDomain(forName: suite) }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DUSK_SHIFT_MODE_UI_OUTPUT"] ?? "/private/tmp/auralim-mode-ui")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func settle() {
            let end = Date(timeIntervalSinceNow: 0.18)
            repeat {
                while Date() < end, let event = app.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) { app.sendEvent(event) }
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            } while Date() < end
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func picker(_ window: NSWindow) throws -> NSSegmentedControl {
            try #require(descendants(window.contentView!).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 3 })
        }
        let presenter = SettingsWindowController()
        presenter.show(model: model)
        let settings = try #require(presenter.window)
        defer { settings.close() }
        let menu = NSWindow(contentViewController: NSHostingController(rootView: MenuContent(model: model, quit: {})))
        menu.isReleasedWhenClosed = false
        menu.setContentSize(NSSize(width: MenuPanelLayout.width, height: MenuPanelLayout.height))
        menu.center()
        menu.makeKeyAndOrderFront(nil)
        defer { menu.close() }
        settle()
        let menuPicker = try picker(menu), settingsPicker = try picker(settings)
        #expect(menuPicker.selectedSegment == -1 && settingsPicker.selectedSegment == -1)
        func select(_ control: NSSegmentedControl, _ segment: Int) {
            control.selectedSegment = segment
            #expect(control.sendAction(control.action, to: control.target))
            settle()
            #expect(menuPicker.selectedSegment == segment)
            #expect(settingsPicker.selectedSegment == segment)
        }
        #expect(controller.requests.isEmpty)
        #expect(model.settingsStatus == "系统自动 · 当前浅色")
        for state in [SystemAppearanceSettings(mode: .light, appearance: .light),
                      .init(mode: .dark, appearance: .dark),
                      .init(mode: .automatic, appearance: .dark),
                      .init(mode: .unknown, appearance: .light)] {
            system = state
            model.reconcile()
            settle()
            let expected = state.mode == .light ? 0 : state.mode == .dark ? 2 : -1
            #expect(menuPicker.selectedSegment == expected && settingsPicker.selectedSegment == expected)
            #expect(controller.requests.isEmpty)
        }
        // Clicking the displayed system segment establishes an app choice.
        system = .init(mode: .light, appearance: .light)
        model.reconcile()
        settle()
        select(settingsPicker, 0)
        #expect(model.manualAppearance == .light)
        select(menuPicker, 1)
        select(menuPicker, 2)
        #expect(model.appearanceMode == .dark && !model.enabled)
        #expect(controller.requests.last == .dark)
        #expect(model.scheduledCheck == nil)
        select(menuPicker, 1)
        #expect(model.appearanceMode == .automatic && model.enabled)
        #expect(controller.requests.last == .light)
        #expect(model.scheduledCheck != nil)
        select(settingsPicker, 0)
        #expect(model.appearanceMode == .light && !model.enabled)
        #expect(controller.requests.last == .light)
        select(settingsPicker, 2)
        #expect(model.appearanceMode == .dark && controller.requests.last == .dark)
        select(settingsPicker, 1)
        #expect(model.enabled && model.scheduledCheck != nil)
        func capture(_ window: NSWindow, name: String) throws {
            window.makeKeyAndOrderFront(nil)
            settle()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-l", String(window.windowNumber), output.appendingPathComponent(name + ".png").path]
            try process.run(); process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
        // Only the changed system-managed presentation is captured. Existing
        // light/dark/solar behavior above is exercised once, without a full UI regression.
        model.enabled = false
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            model.language = language
            settle()
            let labels = ["light", "auto", "dark"].map { model.t($0) }
            for window in [menu, settings] {
                let control = try picker(window)
                #expect((0..<3).map { control.label(forSegment: $0) ?? "" } == labels)
                #expect(control.toolTip(forSegment: 1) == model.t("appearance.auto.help"))
                #expect(control.bounds.width >= control.intrinsicContentSize.width - 0.5)
                #expect(control.visibleRect.width >= control.bounds.width - 0.5)
            }
            for theme in [NSAppearance.Name.aqua, .darkAqua] {
                system = .init(mode: .automatic, appearance: theme == .aqua ? .light : .dark)
                model.reconcile()
                menu.appearance = NSAppearance(named: theme)
                settings.appearance = NSAppearance(named: theme)
                settle()
                #expect(menuPicker.selectedSegment == -1 && settingsPicker.selectedSegment == -1)
                let name = "\(language.rawValue)-\(theme == .aqua ? "light" : "dark")-system-auto"
                try capture(settings, name: "settings-" + name)
                try capture(menu, name: "menu-" + name)
            }
        }
        print("Verified system-managed empty/fixed selection, native menu/settings synchronization and app takeover; new status in 3 languages / 2 appearances; system services are faked")
    }
}
