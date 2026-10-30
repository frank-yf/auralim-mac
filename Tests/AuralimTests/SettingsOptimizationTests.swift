import AppKit
import SwiftUI
import Testing
import Vision
import AuralimCore
@testable import Auralim

private final class SettingsOptimizationAppearance: AppearanceApplying {
    var current: Appearance = .light
    var requests: [Appearance] = []
    var beforeApply: (() -> Void)?
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        beforeApply?(); requests.append(appearance)
        let changed = current != appearance; current = appearance
        completion(.success(.init(changed: changed)))
    }
}

@MainActor
@Suite(.serialized)
struct SettingsOptimizationTests {
    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.08)) }
    private func wait(until predicate: () -> Bool, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < deadline { settle(); try await Task.sleep(for: .milliseconds(20)) }
        #expect(predicate())
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_SETTINGS_OPT_UI"] == "1"))
    func motionEndRequestsAppearanceWhileFinalFrameHoldsForOneSecond() async throws {
        _ = NSApplication.shared
        let player = AppearanceTransitionController(reduceMotion: { false }, duration: 0.12)
        defer { player.stop() }
        var switched = 0, finished = 0
        var switchDate: Date?, releaseDate: Date?
        player.play(.dark, title: "Sunset", onAnimationEnd: {
            #expect(player.panel?.isVisible == true && player.isHoldingFinalFrame)
            switched += 1; switchDate = Date()
            player.panel?.appearance = NSAppearance(named: .darkAqua)
        }, completion: { #expect(player.panel == nil); finished += 1; releaseDate = Date() })
        #expect(switched == 0 && finished == 0)
        try await wait { switched == 1 }
        let held = try #require(player.panel)
        try await Task.sleep(for: .milliseconds(350)); settle()
        #expect(player.panel === held && held.isVisible && finished == 0)
        try await wait { finished == 1 }
        #expect(try #require(releaseDate).timeIntervalSince(try #require(switchDate)) >= 0.95)
        #expect(switched == 1 && held.contentView == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_SETTINGS_OPT_UI"] == "1"))
    func cancellingOrReplacingAHeldFrameCannotFinishTheReplacement() async throws {
        _ = NSApplication.shared
        let player = AppearanceTransitionController(reduceMotion: { false }, duration: 0.1, finalFrameDuration: 0.35)
        defer { player.stop() }
        var ends = 0, firstFinished = 0, replacementFinished = 0
        player.play(.dark, title: "Sunset", onAnimationEnd: { ends += 1 }, completion: { firstFinished += 1 })
        try await wait { player.isHoldingFinalFrame }
        let first = try #require(player.panel)
        player.play(.light, title: "Sunrise", onAnimationEnd: { ends += 1 }, completion: { replacementFinished += 1 })
        #expect(!first.isVisible && first.contentView == nil)
        try await wait { player.isHoldingFinalFrame }
        player.stop()
        try await Task.sleep(for: .milliseconds(500)); settle()
        #expect(player.panel == nil && ends == 2 && firstFinished == 0 && replacementFinished == 0)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_SETTINGS_OPT_UI"] == "1"))
    func settingsDockLifecycleAndUpdatePickerUseIsolatedPreferences() throws {
        let app = NSApplication.shared; app.finishLaunching()
        let previous = app.activationPolicy()
        defer { _ = app.setActivationPolicy(previous) }
        _ = app.setActivationPolicy(.accessory)
        let suite = "Auralim.SettingsOptimization.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("zh-Hans", forKey: "language"); defaults.set("Asia/Shanghai", forKey: "city")
        let service = SettingsOptimizationAppearance()
        let model = AppModel(defaults: defaults, controller: service, enableTimers: false,
            workspaceNotifications: NotificationCenter(), systemNotifications: NotificationCenter(), appearanceNotifications: NotificationCenter(),
            loginItemController: FakeLoginItem(), locationController: FakeLocation(), systemSettings: { .init(mode: .light, appearance: .light) })
        let updater = UpdateController(preferences: defaults)
        let controller = SettingsWindowController()
        defer { controller.window?.close(); model.shutdown(); defaults.removePersistentDomain(forName: suite) }
        controller.show(model: model, updater: updater); settle()
        #expect(app.activationPolicy() == .regular)
        let window = try #require(controller.window)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let host = try #require(window.contentView)
        let controls = descendants(host).compactMap { $0 as? NSSegmentedControl }
        let picker = try #require(controls.first { $0.segmentCount == 2 && $0.label(forSegment: 0) == "手动更新" })
        _ = picker.scrollToVisible(picker.bounds); settle()
        #expect(picker.selectedSegment == 0)
        for segment in [0, 1, 0] {
            picker.selectedSegment = segment
            #expect(picker.sendAction(picker.action, to: picker.target)); settle()
            #expect(updater.mode == (segment == 0 ? .manual : .automatic))
            #expect(defaults.bool(forKey: "SUEnableAutomaticChecks") == (segment == 1))
            #expect(defaults.bool(forKey: "SUAutomaticallyUpdate") == (segment == 1))
            #expect(updater.canCheck)
        }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AURALIM_SETTINGS_OPT_OUTPUT"]!)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in [AppLanguage.simplifiedChinese, .english] {
            model.language = language; settle()
            for theme in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: theme); window.makeFirstResponder(nil); settle()
                #expect(picker.visibleRect.width >= picker.intrinsicContentSize.width - 1)
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                let path = output.appendingPathComponent("settings-\(language.rawValue)-\(theme == .aqua ? "light" : "dark").png")
                try png.write(to: path)
                if language == .simplifiedChinese {
                    let request = VNRecognizeTextRequest(); request.recognitionLanguages = ["zh-Hans", "en-US"]
                    try VNImageRequestHandler(url: path).perform([request])
                    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined().replacingOccurrences(of: " ", with: "")
                    print("Settings visible copy:", text)
                    for removed in ["日出转亮", "日落转暗", "今日时间", "日出日落动画", "切换前倒计时"] { #expect(!text.contains(removed)) }
                    #expect(model.t("transition.enabled") == "切换动画" && model.t("countdown.enabled") == "切换倒计时")
                }
            }
        }
        window.close(); settle(); #expect(app.activationPolicy() == .accessory)
        controller.show(model: model, updater: updater); settle()
        #expect(controller.window === window && app.activationPolicy() == .regular && updater.mode == .manual)
        window.close(); settle(); #expect(app.activationPolicy() == .accessory)
    }
}
