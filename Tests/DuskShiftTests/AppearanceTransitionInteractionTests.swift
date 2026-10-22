import AppKit
import SwiftUI
import Testing
import DuskShiftCore
@testable import DuskShift

private final class TransitionUIAppearance: AppearanceApplying {
    var current: Appearance = .light
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        let changed = current != appearance
        current = appearance
        completion(.success(AppearanceApplication(changed: changed)))
    }
}

@Suite(.serialized)
struct AppearanceTransitionInteractionTests {
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DUSK_SHIFT_TRANSITION_UI_TESTS"] == "1"))
    func bothPanelsTriggerNonactivatingAnimationsThatReplaceAndRelease() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        let suite = "DuskShift.TransitionUI.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("zh-Hans", forKey: "language")
        let player = AppearanceTransitionController(reduceMotion: { false })
        let model = AppModel(defaults: defaults, controller: TransitionUIAppearance(), enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(),
            systemSettings: { .init(mode: .light, appearance: .light) }, transitionPlayer: player)
        defer { model.shutdown(); defaults.removePersistentDomain(forName: suite) }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DUSK_SHIFT_TRANSITION_UI_OUTPUT"] ?? "/private/tmp/dusk-shift-transition-ui")
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
        #expect(player.panel == nil)
        try choose(menu, 2)
        let sunset = try #require(player.panel)
        #expect(sunset.title == "日落 · 切换至深色")
        #expect(sunset.isVisible && sunset.ignoresMouseEvents)
        #expect(!sunset.canBecomeKey && !sunset.canBecomeMain)
        #expect(app.keyWindow === menu)
        settle(0.40)
        #expect(try picker(settings).selectedSegment == 2)
        try capture(sunset, "sunset-middle")
        settle(1.4)
        #expect(player.panel == nil && !sunset.isVisible && sunset.contentView == nil)
        try choose(settings, 0)
        let sunrise = try #require(player.panel)
        #expect(sunrise.title == "日出 · 切换至浅色")
        #expect(app.keyWindow === settings)
        settle(0.55)
        #expect(try picker(menu).selectedSegment == 0)
        try capture(sunrise, "sunrise-middle")
        settle(1.2)
        #expect(player.panel == nil && !sunrise.isVisible)
        model.reconcile()
        #expect(player.panel == nil) // Unchanged appearance, no replay.
        try choose(menu, 2)
        let replaced = try #require(player.panel)
        try choose(settings, 0)
        let latest = try #require(player.panel)
        #expect(latest !== replaced && !replaced.isVisible && replaced.contentView == nil)
        #expect(latest.title == "日出 · 切换至浅色")
        settle(0.35)
        #expect(player.panel === latest && latest.isVisible)
        settle(1.4)
        #expect(player.panel == nil && !latest.isVisible)
        // Reduced motion draws the final scene once and disappears promptly.
        let reduced = AppearanceTransitionController(reduceMotion: { true })
        reduced.play(.dark, title: "日落 · 切换至深色")
        let still = try #require(reduced.panel)
        settle(0.12)
        try capture(still, "reduced-motion-dark")
        settle(0.8)
        #expect(reduced.panel == nil && still.contentView == nil)
        reduced.play(.light, title: "Sunrise · Light appearance")
        let lightStill = try #require(reduced.panel)
        settle(0.12)
        try capture(lightStill, "reduced-motion-light")
        reduced.stop()
        #expect(reduced.panel == nil && !lightStill.isVisible && lightStill.contentView == nil)
        // Snapshots of the same production scene verify its actual drawing at
        // the start / midpoint / end without a persistent animation clock.
        let preview = NSWindow(contentViewController: NSHostingController(rootView: SolarTransitionScene(daylight: 0)))
        preview.isReleasedWhenClosed = false
        preview.setContentSize(NSSize(width: 248, height: 112))
        defer { preview.close() }
        for (name, daylight) in [("night", 0.0), ("horizon", 0.5), ("day", 1.0)] {
            preview.contentView = NSHostingView(rootView: SolarTransitionScene(daylight: daylight))
            preview.orderFront(nil)
            settle()
            try capture(preview, "scene-" + name)
        }
        print("Verified menu sunset, settings sunrise, mode sync, no focus stealing or click interception, replacement/cancellation, no replay, reduced motion and complete window/content cleanup; system controller is faked")
    }
}
