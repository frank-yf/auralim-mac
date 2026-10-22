import Testing
import AppKit
import SwiftUI
@testable import DuskShift

struct MenuLayoutTests {
    @MainActor
    @Test
    func menuHasUsableSizeWithoutParentHeightProposal() {
        let suite = "DuskShift.Layout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, enableTimers: false)
        defer { model.shutdown() }
        let host = NSHostingView(rootView: MenuContent(model: model))
        let size = host.fittingSize
        print("Unconstrained menu fitting size:", size)
        #expect(size.width >= 380)
        #expect(size.height >= 280)
        #expect(size.height <= 720)
        let controller = NSHostingController(rootView: MenuContent(model: model))
        let compressed = controller.sizeThatFits(in: NSSize(width: 390, height: 1))
        print("Compressed menu fitting size:", compressed)
        #expect(compressed.height >= 280)
    }

    @Test
    func panelFitsSmallerDisplays() {
        #expect(MenuPanelLayout.height(availableHeight: 900) == 720)
        #expect(MenuPanelLayout.height(availableHeight: 600) == 560)
        #expect(MenuPanelLayout.height(availableHeight: 360) == 320)
    }
}
