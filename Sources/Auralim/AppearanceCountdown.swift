import AppKit
import SwiftUI
import AuralimCore

@MainActor
protocol CountdownPresenting {
    func start(seconds: Int, target: Appearance, localizer: Localizer,
               tick: @escaping @MainActor (Int) -> Void,
               finish: @escaping @MainActor () -> Void,
               cancel: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
private final class CountdownDisplay: ObservableObject {
    @Published var remaining = 10
}

/// A timer exists only while counting down. Remaining time is derived from a
/// deadline, so a delayed run-loop tick never extends the requested duration.
@MainActor
final class CountdownController: CountdownPresenting {
    private(set) var panel: NSPanel?
    private var timer: Timer?
    private var deadline: TimeInterval?
    private let now: () -> TimeInterval
    private let display = CountdownDisplay()
    private let preview: Bool
    private var tick: (@MainActor (Int) -> Void)?
    private var finish: (@MainActor () -> Void)?
    private var cancel: (@MainActor () -> Void)?

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, preview: Bool = false) {
        self.now = now; self.preview = preview
    }

    func start(seconds: Int, target: Appearance, localizer: Localizer,
               tick: @escaping @MainActor (Int) -> Void,
               finish: @escaping @MainActor () -> Void,
               cancel: @escaping @MainActor () -> Void) {
        stop()
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else {
            finish(); return
        }
        self.tick = tick; self.finish = finish; self.cancel = cancel
        deadline = now() + Double(seconds)
        display.remaining = seconds
        let size = CGSize(width: 340, height: 112)
        let frame = CGRect(x: screen.visibleFrame.maxX - size.width - 24,
                           y: screen.visibleFrame.maxY - size.height - 24, width: size.width, height: size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier("appearance-countdown")
        panel.title = localizer.text(preview ? "debug.countdown" : "countdown.enabled")
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: CountdownView(display: display, target: target, localizer: localizer, preview: preview,
            finish: { [weak self] in self?.complete() }, cancel: { [weak self] in self?.cancelByUser() },
            acknowledge: { [weak self] in self?.acknowledge() }))
        self.panel = panel
        panel.orderFrontRegardless()
        update()
    }

    func update() {
        guard let deadline else { return }
        let interval = deadline - now()
        guard interval > 0 else { complete(); return }
        let seconds = Int(ceil(interval))
        display.remaining = seconds
        tick?(seconds)
        timer?.invalidate()
        let timer = Timer(timeInterval: min(1, interval), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func complete() { let callback = finish; stop(); callback?() }
    func cancelByUser() { let callback = cancel; stop(); callback?() }

    /// Dismiss only the panel. Keep the deadline and callbacks alive so the
    /// scheduled transition proceeds even after the user acknowledges it.
    func acknowledge() {
        panel?.orderOut(nil); panel?.contentView = nil; panel?.close(); panel = nil
    }

    func stop() {
        timer?.invalidate(); timer = nil; deadline = nil
        tick = nil; finish = nil; cancel = nil
        acknowledge()
    }
}

@MainActor
private struct CountdownView: View {
    @ObservedObject var display: CountdownDisplay
    let target: Appearance
    let localizer: Localizer
    let preview: Bool
    let finish: () -> Void
    let cancel: () -> Void
    let acknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DuskSymbol(name: target == .light ? "sun.max.fill" : "moon.fill",
                           tint: target == .light ? DuskStyle.gold : DuskStyle.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(localizer.text("app.name")).font(.system(size: 13, weight: .semibold))
                    Text(localizer.text(preview ? "debug.remaining" : "countdown.remaining", localizer.text(target == .light ? "light" : "dark"), display.remaining))
                        .font(.callout).monospacedDigit().fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("countdown-remaining")
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button(localizer.text("countdown.cancel"), action: cancel)
                    .accessibilityIdentifier("countdown-cancel")
                Spacer(minLength: 4)
                Button(localizer.text("countdown.acknowledge"), action: acknowledge)
                    .buttonStyle(CountdownAcknowledgementStyle())
                    .accessibilityIdentifier("countdown-acknowledge")
                Button(localizer.text("countdown.now"), action: finish)
                    .accessibilityIdentifier("countdown-now")
            }.buttonStyle(CountdownSecondaryStyle()).controlSize(.small).font(.caption)
        }.padding(14).frame(width: 340, height: 112)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .environment(\.locale, localizer.locale)
    }
}

private struct CountdownSecondaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1).minimumScaleFactor(0.85)
            .padding(.horizontal, 10).frame(height: 24)
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 7))
    }
}

/// Countdown panels intentionally never activate the app. A custom fill keeps
/// the acknowledgement highlighted even when AppKit de-emphasizes native bezels.
private struct CountdownAcknowledgementStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .lineLimit(1).minimumScaleFactor(0.85)
            .padding(.horizontal, 10).frame(height: 24)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
