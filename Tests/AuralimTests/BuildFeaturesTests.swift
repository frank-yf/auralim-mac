import AppKit
import SwiftUI
import Testing
import AuralimCore
@testable import Auralim

private final class BuildAppearance: AppearanceApplying {
    var requests: [Appearance] = []
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        requests.append(appearance); completion(.success(.init(changed: false)))
    }
}

@MainActor
struct BuildFeaturesTests {
    @Test func compileFlagGatesPreferencesAndProgrammaticEntry() {
        let suite = "Auralim.BuildFeatures.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "debugModeEnabled")
        let appearance = BuildAppearance()
        let model = AppModel(defaults: defaults, controller: appearance, enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(), appearanceNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(),
            systemSettings: { .init(mode: .light, appearance: .light) }, desktopReady: { true })
        defer { model.shutdown(); defaults.removePersistentDomain(forName: suite) }
        #expect(model.debugPreview.enabled == BuildFeatures.debugToolsEnabled)
        #expect(model.canPreviewDebug == BuildFeatures.debugToolsEnabled)
        if !BuildFeatures.debugToolsEnabled {
            model.debugPreview.enabled = true
            model.debugPreview.applyAppearanceAfterPreview = true
            model.previewDebug(.animation, target: .dark)
            #expect(model.debugPreview.phase == .idle && appearance.requests.isEmpty)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_BUILD_UI_TESTS"] == "1"))
    func packagedSettingsOnlyIncludesDebugSwitchInDebugBuild() throws {
        _ = NSApplication.shared
        let suite = "Auralim.BuildUI.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let model = AppModel(defaults: defaults, controller: BuildAppearance(), enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(), appearanceNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(),
            systemSettings: { .init(mode: .light, appearance: .light) }, desktopReady: { true })
        defer { model.shutdown(); defaults.removePersistentDomain(forName: suite) }
        let host = NSHostingController(rootView: SettingsContent(model: model))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false; window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        let count = views(host.view).compactMap { $0 as? NSSwitch }.count
        #expect(count == (BuildFeatures.debugToolsEnabled ? 4 : 3))
    }
}
