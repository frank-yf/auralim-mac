import AppKit
import SwiftUI
import Combine

@MainActor
final class SettingsWindowController: ObservableObject {
    private(set) var window: NSWindow?
    private var languageSubscription: AnyCancellable?

    func show(model: AppModel) {
        model.refreshLoginItemStatus()
        model.reconcile()
        if let window {
            let wasVisible = window.isVisible
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            if !wasVisible { clearInitialFocus(in: window) }
            return
        }
        let screen = NSApplication.shared.keyWindow?.screen ?? NSScreen.main
        let height = SettingsPanelLayout.height(availableHeight: screen?.visibleFrame.height ?? 800)
        let controller = NSHostingController(rootView: SettingsContent(model: model, height: height))
        let window = NSWindow(contentViewController: controller)
        window.title = model.t("settings.title")
        window.identifier = NSUserInterfaceItemIdentifier("dusk-shift-settings")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: SettingsPanelLayout.width, height: height))
        if let frame = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2,
                                          y: frame.midY - window.frame.height / 2))
        } else {
            window.center()
        }
        self.window = window
        languageSubscription = model.$language.sink { [weak window, weak model] language in
            guard let model else { return }
            window?.title = model.localizer(for: language).text("settings.title")
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        clearInitialFocus(in: window)
    }

    private func clearInitialFocus(in window: NSWindow) {
        // AppKit chooses a text field after SwiftUI lays out a newly shown window.
        // Clear only that initial choice; normal editing never uses this path.
        RunLoop.main.perform(inModes: [.common]) { [weak window] in
            MainActor.assumeIsolated { _ = window?.makeFirstResponder(nil) }
        }
    }
}

enum SettingsPanelLayout {
    static let width: CGFloat = 600
    static func height(availableHeight: CGFloat) -> CGFloat {
        min(720, max(400, availableHeight - 80))
    }
}
