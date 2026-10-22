import AppKit
import SwiftUI
import DuskShiftCore

@MainActor
protocol AppearanceTransitionPlaying {
    func play(_ appearance: Appearance, title: String)
    func stop()
}

/// One short-lived, click-through panel. No window, task or animation is kept
/// alive between appearance changes. Rapid changes replace the previous scene.
@MainActor
final class AppearanceTransitionController: AppearanceTransitionPlaying {
    private(set) var panel: NSPanel?
    private var dismissal: Timer?
    private let reduceMotion: () -> Bool
    private let duration: TimeInterval

    init(reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         duration: TimeInterval = 1.55) {
        self.reduceMotion = reduceMotion
        self.duration = duration
    }

    func play(_ appearance: Appearance, title: String) {
        stop()
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let reduced = reduceMotion()
        let panel = TransitionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier("appearance-transition")
        panel.title = title
        panel.setAccessibilityLabel(title)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: AppearanceTransitionView(appearance: appearance, title: title, reducedMotion: reduced))
        panel.setContentSize(NSSize(width: 280, height: 184))
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - 140, y: frame.midY - 92))
        self.panel = panel
        panel.orderFrontRegardless()
        // AppKit menu tracking can run a nested loop. A single common-mode
        // timer dismisses on time there too; it never polls between switches.
        let dismissal = Timer(timeInterval: reduced ? 0.7 : duration, repeats: false) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, self.panel === panel else { return }
                self.stop()
            }
        }
        self.dismissal = dismissal
        RunLoop.main.add(dismissal, forMode: .common)
    }

    func stop() {
        dismissal?.invalidate()
        dismissal = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }
}

private final class TransitionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct AppearanceTransitionView: View {
    let appearance: Appearance
    let title: String
    var reducedMotion = false
    @State private var progress = 0.0
    @State private var opacity = 0.0

    var body: some View {
        VStack(spacing: 0) {
            SolarTransitionScene(daylight: appearance == .light ? progress : 1 - progress)
                .frame(height: 112)
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(.regularMaterial)
        }
        .frame(width: 248, height: 152)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .opacity(opacity)
        .frame(width: 280, height: 184)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .task {
            if reducedMotion { progress = 1; opacity = 1; return }
            withAnimation(.easeOut(duration: 0.14)) { opacity = 1 }
            withAnimation(.easeInOut(duration: 1.1)) { progress = 1 }
            do { try await Task.sleep(nanoseconds: 1_300_000_000) }
            catch { return }
            withAnimation(.easeOut(duration: 0.2)) { opacity = 0 }
        }
    }
}

/// Daylight is the single continuous value shared by both directions. Keeping
/// drawing in one Canvas prevents layout or control updates during the effect.
struct SolarTransitionScene: View, Animatable {
    var daylight: Double
    var animatableData: Double { get { daylight } set { daylight = newValue } }

    var body: some View {
        Canvas { context, size in
            let day = min(1, max(0, daylight))
            let horizon = size.height * 0.73
            func color(_ night: (Double, Double, Double), _ light: (Double, Double, Double)) -> Color {
                Color(red: night.0 + (light.0 - night.0) * day,
                      green: night.1 + (light.1 - night.1) * day,
                      blue: night.2 + (light.2 - night.2) * day)
            }
            let top = color((0.10, 0.14, 0.25), (0.43, 0.57, 0.73))
            let bottom = color((0.29, 0.29, 0.42), (0.98, 0.79, 0.54))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            for (x, y, radius) in [(0.12, 0.22, 1.0), (0.25, 0.38, 0.8), (0.42, 0.17, 1.2), (0.58, 0.33, 0.8), (0.87, 0.18, 1.0)] {
                context.fill(Path(ellipseIn: CGRect(x: x * size.width, y: y * size.height, width: radius * 2, height: radius * 2)),
                             with: .color(.white.opacity((1 - day) * 0.7)))
            }
            let moon = CGRect(x: size.width * 0.76, y: size.height * 0.21, width: 16, height: 16)
            var crescent = Path(ellipseIn: moon)
            crescent.addEllipse(in: moon.offsetBy(dx: 5, dy: -4))
            var moonContext = context
            moonContext.clip(to: Path(ellipseIn: moon))
            moonContext.fill(crescent, with: .color(Color(red: 0.91, green: 0.93, blue: 1).opacity(1 - day)), style: FillStyle(eoFill: true))
            var sky = context
            sky.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)))
            let sun = CGPoint(x: size.width * 0.5, y: horizon + 17 - day * 60)
            sky.fill(Path(ellipseIn: CGRect(x: sun.x - 35, y: sun.y - 35, width: 70, height: 70)), with: .radialGradient(
                Gradient(colors: [.orange.opacity(0.28), .orange.opacity(0)]), center: sun, startRadius: 8, endRadius: 35))
            sky.fill(Path(ellipseIn: CGRect(x: sun.x - 12, y: sun.y - 12, width: 24, height: 24)),
                     with: .color(Color(red: 1, green: 0.87, blue: 0.58)))
            context.fill(Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)),
                         with: .color(color((0.12, 0.17, 0.28), (0.40, 0.50, 0.61))))
            var line = Path()
            line.move(to: CGPoint(x: 0, y: horizon)); line.addLine(to: CGPoint(x: size.width, y: horizon))
            context.stroke(line, with: .color(.white.opacity(0.25)), lineWidth: 0.5)
            for row in 0..<3 {
                let width = CGFloat(40 - row * 10)
                let rect = CGRect(x: size.width / 2 - width / 2, y: horizon + 6 + CGFloat(row * 7), width: width, height: 1)
                context.fill(Path(roundedRect: rect, cornerRadius: 0.5), with: .color(.white.opacity(day * 0.22)))
            }
        }
        .accessibilityHidden(true)
    }
}
