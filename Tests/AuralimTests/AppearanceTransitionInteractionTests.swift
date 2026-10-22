import AppKit
import SwiftUI
import Testing
import AuralimCore
@testable import Auralim

private final class TransitionUIAppearance: AppearanceApplying {
    var current: Appearance = .light
    var requests = 0
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        requests += 1
        let changed = current != appearance
        current = appearance
        completion(.success(AppearanceApplication(changed: changed)))
    }
}

@Suite(.serialized)
struct AppearanceTransitionInteractionTests {
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DUSK_SHIFT_TRANSITION_UI_TESTS"] == "1"))
    func halfScreenTransitionsRespectTheSettingsSwitchAndRelease() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        let suite = "Auralim.TransitionUI.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("zh-Hans", forKey: "language")
        let player = AppearanceTransitionController(reduceMotion: { false }), controller = TransitionUIAppearance()
        let model = AppModel(defaults: defaults, controller: controller, enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(),
            systemSettings: { .init(mode: .light, appearance: .light) }, transitionPlayer: player)
        defer { model.shutdown(); defaults.removePersistentDomain(forName: suite) }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DUSK_SHIFT_TRANSITION_UI_OUTPUT"] ?? "/private/tmp/auralim-transition-ui")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func settle(_ duration: TimeInterval = 0.18) {
            let end = Date(timeIntervalSinceNow: duration)
            repeat {
                while Date() < end, let event = app.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) { app.sendEvent(event) }
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            } while Date() < end
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func picker(_ window: NSWindow) throws -> NSSegmentedControl {
            try #require(descendants(window.contentView!).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 3 })
        }
        func choose(_ window: NSWindow, _ segment: Int) throws {
            window.makeKeyAndOrderFront(nil)
            let control = try picker(window)
            control.selectedSegment = segment
            #expect(control.sendAction(control.action, to: control.target))
        }
        func capture(_ window: NSWindow, _ name: String) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-l", String(window.windowNumber), output.appendingPathComponent(name + ".png").path]
            try process.run(); process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
        func checkFrame(_ panel: NSPanel) throws {
            let screen = try #require(NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main)
            #expect(panel.frame == HalfScreenTransition.frame(on: screen.frame))
            #expect(panel.contentView?.bounds.size == panel.frame.size)
            #expect(panel.ignoresMouseEvents && !panel.canBecomeKey && !panel.canBecomeMain)
            #expect(descendants(panel.contentView!).compactMap { $0 as? NSTextField }.isEmpty)
        }
        let settingsController = SettingsWindowController()
        settingsController.show(model: model)
        let settings = try #require(settingsController.window)
        defer { settings.close() }
        let menu = NSWindow(contentViewController: NSHostingController(rootView: MenuContent(model: model, quit: {})))
        menu.isReleasedWhenClosed = false
        menu.setContentSize(NSSize(width: MenuPanelLayout.width, height: MenuPanelLayout.height))
        menu.makeKeyAndOrderFront(nil)
        defer { menu.close() }
        settle()
        let switches = descendants(settings.contentView!).compactMap { $0 as? NSSwitch }
        #expect(switches.count == 2)
        let animationSwitch = try #require(switches.first)
        #expect(animationSwitch.state == .off && !model.transitionAnimationEnabled)
        try choose(menu, 2)
        try choose(settings, 0)
        #expect(player.panel == nil && controller.current == .light)
        let beforeEnable = controller.requests
        _ = animationSwitch.accessibilityPerformPress()
        settle()
        #expect(animationSwitch.state == .on && model.transitionAnimationEnabled)
        #expect(defaults.bool(forKey: "transitionAnimationEnabled"))
        #expect(player.panel == nil && controller.requests == beforeEnable)
        try capture(settings, "settings-animation-on")
        try choose(menu, 2)
        let sunset = try #require(player.panel)
        try checkFrame(sunset)
        #expect(sunset.title == "日落 · 切换至深色" && app.keyWindow === menu)
        settle(1.15)
        #expect(try picker(settings).selectedSegment == 2)
        try capture(sunset, "sunset-middle")
        settle(2.4)
        #expect(player.panel == nil && !sunset.isVisible && sunset.contentView == nil)
        try choose(settings, 0)
        let sunrise = try #require(player.panel)
        try checkFrame(sunrise)
        #expect(sunrise.title == "日出 · 切换至浅色" && app.keyWindow === settings)
        settle(1.15)
        #expect(try picker(menu).selectedSegment == 0)
        try capture(sunrise, "sunrise-middle")
        settle(2.4)
        #expect(player.panel == nil && !sunrise.isVisible && sunrise.contentView == nil)
        model.reconcile()
        #expect(player.panel == nil)
        try choose(menu, 2)
        let replaced = try #require(player.panel)
        try choose(settings, 0)
        let latest = try #require(player.panel)
        #expect(latest !== replaced && !replaced.isVisible && replaced.contentView == nil)
        settle(0.35)
        #expect(player.panel === latest && latest.isVisible)
        let beforeDisable = controller.requests
        _ = animationSwitch.accessibilityPerformPress()
        settle()
        #expect(!model.transitionAnimationEnabled && animationSwitch.state == .off)
        #expect(!defaults.bool(forKey: "transitionAnimationEnabled"))
        #expect(player.panel == nil && !latest.isVisible && latest.contentView == nil)
        #expect(controller.requests == beforeDisable && model.appearanceMode == .light)
        try choose(menu, 2)
        #expect(player.panel == nil && model.appearanceMode == .dark)
        // This now omits the large effect entirely for Reduce Motion.
        let reduced = AppearanceTransitionController(reduceMotion: { true })
        reduced.play(.dark, title: "日落")
        #expect(reduced.panel == nil)
        reduced.play(.light, title: "日出")
        #expect(reduced.panel == nil)
        // Only the new switch's label and placement are checked across locales.
        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            model.language = language
            settle()
            #expect(animationSwitch.visibleRect.height >= animationSwitch.bounds.height - 0.5)
            #expect(animationSwitch.state == .off)
            try capture(settings, "settings-animation-off-" + language.rawValue)
        }
        let preview = NSWindow(contentViewController: NSHostingController(rootView: SolarTransitionScene(progress: 0).background(Color(red: 0.30, green: 0.33, blue: 0.38))))
        preview.isReleasedWhenClosed = false
        preview.setContentSize(NSSize(width: 1000, height: 400))
        defer { preview.close() }
        for appearance in [Appearance.light, .dark] {
            for (name, progress) in [("start", 0.0), ("middle", 0.5), ("end", 1.0)] {
                preview.contentView = NSHostingView(rootView: SolarTransitionScene(progress: progress, appearance: appearance).background(Color(red: 0.30, green: 0.33, blue: 0.38)))
                preview.orderFront(nil)
                settle()
                try capture(preview, "scene-" + (appearance == .light ? "sunrise-" : "sunset-") + name)
            }
        }
        print("Verified default off; native settings switch on/off and no appearance requests; centered half-area display geometry; menu sunset/settings sunrise; focus and click-through; replacement, immediate cancellation and release; reduced motion skips; no replay. Actual system appearance is faked")
    }
}
