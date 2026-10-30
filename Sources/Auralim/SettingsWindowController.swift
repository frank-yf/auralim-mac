import AppKit
import SwiftUI
import Combine

@MainActor
final class SettingsWindowController: NSObject, ObservableObject, NSWindowDelegate {
    private(set) var window: NSWindow?
    private var languageSubscription: AnyCancellable?
    private var previousActivationPolicy: NSApplication.ActivationPolicy?

    func show(model: AppModel, updater: UpdateController? = nil) {
        if previousActivationPolicy == nil {
            previousActivationPolicy = NSApplication.shared.activationPolicy()
        }
        _ = NSApplication.shared.setActivationPolicy(.regular)
        model.refreshLoginItemStatus()
        model.reconcile()
        if let window {
            let wasVisible = window.isVisible
            if window.isMiniaturized { window.deminiaturize(nil) }
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            if !wasVisible { clearInitialFocus(in: window) }
            return
        }
        let screen = NSApplication.shared.keyWindow?.screen ?? NSScreen.main
        let height = SettingsPanelLayout.height(availableHeight: screen?.visibleFrame.height ?? 800)
        let controller = NSHostingController(rootView: SettingsContent(model: model, height: height, updater: updater))
        let window = SettingsWindow(contentViewController: controller)
        window.title = model.t("settings.title")
        window.identifier = NSUserInterfaceItemIdentifier("dusk-shift-settings")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: SettingsPanelLayout.width, height: height))
        if let frame = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2,
                                          y: frame.midY - window.frame.height / 2))
        } else {
            window.center()
        }
        window.delegate = self
        self.window = window
        languageSubscription = model.$language.sink { [weak window, weak model] language in
            guard let model else { return }
            window?.title = model.localizer(for: language).text("settings.title")
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        clearInitialFocus(in: window)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window, let policy = previousActivationPolicy else { return }
        previousActivationPolicy = nil
        _ = NSApplication.shared.setActivationPolicy(policy)
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
        min(640, max(400, availableHeight - 80))
    }
}

/// Commit text edits on blank clicks without intercepting controls or keyboard navigation.
@MainActor
private final class SettingsWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           let editor = firstResponder as? NSTextView, editor.isFieldEditor,
           let contentView,
           contentView.bounds.contains(contentView.convert(event.locationInWindow, from: nil)) {
            var hit = contentView.hitTest(contentView.convert(event.locationInWindow, from: nil))
            var isControl = false
            while let view = hit {
                if let field = view as? NSTextField {
                    if field.isEditable || field.isSelectable { isControl = true; break }
                } else if view is NSControl || view is NSTextView {
                    isControl = true; break
                }
                hit = view.superview
            }
            if !isControl { makeFirstResponder(nil) }
        }
        super.sendEvent(event)
    }
}
