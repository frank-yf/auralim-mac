import Testing
import AppKit
import SwiftUI
@testable import Auralim

struct MenuLayoutTests {
    @MainActor
    @Test
    func menuHasUsableSizeWithoutParentHeightProposal() {
        let suite = "Auralim.Layout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, enableTimers: false)
        defer { model.shutdown() }
        let host = NSHostingView(rootView: MenuContent(model: model))
        let size = host.fittingSize
        print("Unconstrained menu fitting size:", size)
        #expect(size.width == 320)
        #expect(size.height == 264)
        #expect(size.height <= 300)
        let controller = NSHostingController(rootView: MenuContent(model: model))
        let compressed = controller.sizeThatFits(in: NSSize(width: 320, height: 1))
        print("Compressed menu fitting size:", compressed)
        #expect(compressed.height == 264)
    }

    @Test
    func panelFitsSmallerDisplays() {
        #expect(SettingsPanelLayout.height(availableHeight: 900) == 720)
        #expect(SettingsPanelLayout.height(availableHeight: 600) == 520)
        #expect(SettingsPanelLayout.height(availableHeight: 480) == 400)
    }
}
