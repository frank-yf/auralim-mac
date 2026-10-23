import AppKit
import AuralimCore
import Testing
@testable import Auralim

@MainActor
struct WakeTransitionPresenterTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_WAKE_UI_TESTS"] == "1"))
    func deferredWakeCreatesOneVisiblePanelThenReleasesItInBothDirections() async throws {
        _ = NSApplication.shared
        #expect(WakeAppearanceTransition.desktopIsReady())
        for target in [Appearance.light, .dark] {
            var ready = false
            let player = AppearanceTransitionController(reduceMotion: { false }, duration: 0.5)
            let gate = WakeAppearanceTransition(desktopReady: { ready }, delay: 0.01) { appearance in
                player.play(appearance, title: "Wake transition test")
            }
            defer { gate.cancelWake(); player.stop() }
            gate.willSleep(appearance: target == .light ? .dark : .light)
            gate.didWake(fallback: target)
            #expect(!gate.verified(target, changed: false))
            try await Task.sleep(for: .milliseconds(50))
            #expect(player.panel == nil)
            ready = true
            gate.desktopChanged()
            try await Task.sleep(for: .milliseconds(80))
            let panel = try #require(player.panel)
            #expect(panel.isVisible && !panel.canBecomeKey && panel.ignoresMouseEvents)
            gate.desktopChanged()
            #expect(!gate.verified(target, changed: false))
            try await Task.sleep(for: .milliseconds(30))
            #expect(player.panel === panel)
            try await Task.sleep(for: .milliseconds(550))
            #expect(player.panel == nil && !panel.isVisible && panel.contentView == nil)
        }
    }
}
