import AppKit
import SwiftUI
import Testing
import AuralimCore
@testable import Auralim

private final class LocalizationAppearance: AppearanceApplying {
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        completion(.success(.init(changed: false)))
    }
}

/// Exercises the real language picker with isolated preferences and system-service fakes.
@Suite(.serialized)
struct LocalizationInteractionTests {
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_LOCALIZATION_UI_TESTS"] == "1"))
    func twelveLanguagesUpdateSettingsAndMenu() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        let suite = "Auralim.LocalizationUI.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("en", forKey: "language")
        let model = AppModel(defaults: defaults, controller: LocalizationAppearance(), enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(),
            appearanceNotifications: NotificationCenter(), preferredLanguages: { ["ja-JP"] },
            loginItemController: FakeLoginItem(), locationController: FakeLocation(),
            systemSettings: { .init(mode: .light, appearance: .light) })
        defer { model.shutdown(); defaults.removePersistentDomain(forName: suite) }
        let presenter = SettingsWindowController()
        presenter.show(model: model, updater: UpdateController())
        let settings = try #require(presenter.window)
        let menu = NSWindow(contentViewController: NSHostingController(rootView: MenuContent(model: model, quit: {})))
        menu.isReleasedWhenClosed = false
        menu.setContentSize(NSSize(width: MenuPanelLayout.width, height: MenuPanelLayout.height))
        menu.center()
        defer { settings.close(); menu.close() }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AURALIM_LOCALIZATION_UI_OUTPUT"] ?? "/private/tmp/auralim-localization-ui")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func capture(_ window: NSWindow, _ name: String) throws {
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
            settle()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.appendingPathComponent(name + ".png").path]
            try process.run(); process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
        settle()
        let host = try #require(settings.contentView)
        for language in AppLanguage.allCases where language != .system {
            let picker = try #require(descendants(host).compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles.contains("Português (Brasil)") })
            #expect(picker.numberOfItems == 13)
            let index = picker.indexOfItem(withTitle: language.nativeName)
            #expect(index >= 0)
            try #require(picker.menu).performActionForItem(at: index)
            settle()
            #expect(model.language == language)
            #expect(defaults.string(forKey: "language") == language.rawValue)
            #expect(settings.title == Localizer(language: language).text("settings.title"))
            for window in [settings, menu] {
                let view = try #require(window.contentView)
                let modes = try #require(descendants(view).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 3 })
                if window === menu {
                    #expect(modes.intrinsicContentSize.width <= 180)
                }
                for (index, mode) in AppearanceMode.allCases.enumerated() {
                    #expect(modes.label(forSegment: index) == Localizer(language: language).text(mode.localizationKey))
                }
            }
            for theme in [NSAppearance.Name.aqua, .darkAqua] {
                settings.appearance = NSAppearance(named: theme)
                menu.appearance = NSAppearance(named: theme)
                let suffix = language.rawValue + (theme == .aqua ? "-light" : "-dark")
                try capture(settings, "settings-" + suffix)
                try capture(menu, "menu-" + suffix)
            }
            print("Completed language interaction checks:", language.rawValue)
        }
        model.language = .system
        settle()
        #expect(settings.title == Localizer(language: .japanese).text("settings.title"))
        #expect(defaults.string(forKey: "language") == "system")
    }
}
