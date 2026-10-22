import AppKit
import SwiftUI
import QuartzCore
import DuskShiftCore

@MainActor
protocol AppearanceTransitionPlaying {
    func play(_ appearance: Appearance, title: String)
    func stop()
}

enum HalfScreenTransition {
    static let duration: TimeInterval = 3.2
    static func frame(on screen: CGRect) -> CGRect {
        let size = CGSize(width: screen.width * 0.8, height: screen.height * 0.625)
        return CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}

/// Screen-left represents east and screen-right west. Both bodies travel in
/// the same direction; the one setting hands the sky over to the one rising.
enum CelestialOrbit {
    static func position(progress: Double, rising: Bool, size: CGSize) -> CGPoint {
        let progress = min(1, max(0, progress))
        let start = rising ? Double.pi : Double.pi / 2
        let end = rising ? Double.pi / 2 : 0
        let angle = start + (end - start) * progress
        return CGPoint(x: size.width * (0.5 + 0.44 * cos(angle)),
                       y: size.height * (1.005 - 0.705 * sin(angle)))
    }
}

/// A transparent atmosphere centered on the pointer's display (half its area).
/// Two one-shot common-mode timers fade and remove it even in menu tracking.
@MainActor
final class AppearanceTransitionController: AppearanceTransitionPlaying {
    private(set) var panel: NSPanel?
    private var fadeOut: Timer?
    private var dismissal: Timer?
    private let reduceMotion: () -> Bool
    private let duration: TimeInterval

    init(reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         duration: TimeInterval = HalfScreenTransition.duration) {
        self.reduceMotion = reduceMotion
        self.duration = duration
    }

    func play(_ appearance: Appearance, title: String) {
        stop()
        // A half-screen effect is large motion: omit it when macOS asks to
        // reduce motion, rather than replacing it with a large static overlay.
        guard !reduceMotion(),
              let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let frame = HalfScreenTransition.frame(on: screen.frame)
        let panel = TransitionPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier("appearance-transition")
        panel.title = title
        panel.setAccessibilityLabel(title)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: AppearanceTransitionView(appearance: appearance, duration: duration))
        panel.setFrame(frame, display: false)
        panel.alphaValue = 0
        self.panel = panel
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration * 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
        }
        let fadeOut = Timer(timeInterval: duration * 0.74, repeats: false) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, self.panel === panel else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = self.duration * 0.24
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().alphaValue = 0
                }
            }
        }
        self.fadeOut = fadeOut
        RunLoop.main.add(fadeOut, forMode: .common)
        let dismissal = Timer(timeInterval: duration, repeats: false) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, self.panel === panel else { return }
                self.stop()
            }
        }
        self.dismissal = dismissal
        RunLoop.main.add(dismissal, forMode: .common)
    }

    func stop() {
        fadeOut?.invalidate(); fadeOut = nil
        dismissal?.invalidate(); dismissal = nil
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
    var duration = HalfScreenTransition.duration
    @State private var progress = 0.0

    var body: some View {
        SolarTransitionScene(progress: progress, appearance: appearance)
            .accessibilityHidden(true)
            .task {
                withAnimation(.timingCurve(0.35, 0, 0.25, 1, duration: duration * 0.78)) { progress = 1 }
            }
    }
}

/// Soft, translucent sky and horizon light merge into the desktop. All four
/// edges are completely transparent; there is no frame, caption or opaque scene.
struct SolarTransitionScene: View, Animatable {
    var progress: Double
    var appearance: Appearance = .light
    var animatableData: Double { get { progress } set { progress = newValue } }

    var body: some View {
        Canvas { context, size in
            let phase = min(1, max(0, progress))
            let day = appearance == .light ? phase : 1 - phase
            let horizon = size.height * 0.90
            let radius = min(52, size.height * 0.095)
            func color(_ night: (Double, Double, Double), _ light: (Double, Double, Double)) -> Color {
                Color(red: night.0 + (light.0 - night.0) * day,
                      green: night.1 + (light.1 - night.1) * day,
                      blue: night.2 + (light.2 - night.2) * day)
            }
            let sky = color((0.14, 0.19, 0.31), (0.64, 0.72, 0.81))
            let warmth = color((0.35, 0.34, 0.47), (1, 0.68, 0.39))
            let bounds = Path(CGRect(origin: .zero, size: size))
            context.fill(bounds, with: .linearGradient(Gradient(stops: [
                .init(color: sky.opacity(0), location: 0),
                .init(color: sky.opacity(0.05), location: 0.28),
                .init(color: sky.opacity(0.20), location: 0.63),
                .init(color: sky.opacity(0.46), location: 1)
            ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let sun = CelestialOrbit.position(progress: phase, rising: appearance == .light, size: size)
            let moon = CelestialOrbit.position(progress: phase, rising: appearance == .dark, size: size)
            let glow = size.height * 0.70
            context.fill(bounds, with: .radialGradient(Gradient(colors: [
                warmth.opacity(0.35), warmth.opacity(0.13), warmth.opacity(0)
            ]), center: CGPoint(x: sun.x, y: min(sun.y, horizon)), startRadius: radius * 0.5, endRadius: glow))
            var disk = context
            disk.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)))
            disk.fill(Path(ellipseIn: CGRect(x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2)),
                      with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.93, blue: 0.74).opacity(0.92),
                                                            Color(red: 1, green: 0.77, blue: 0.46).opacity(0.78)]),
                                            center: sun, startRadius: 0, endRadius: radius))
            let moonRadius = radius * 0.76
            let moonRect = CGRect(x: moon.x - moonRadius, y: moon.y - moonRadius, width: moonRadius * 2, height: moonRadius * 2)
            disk.fill(Path(ellipseIn: moonRect.insetBy(dx: -moonRadius, dy: -moonRadius)),
                      with: .radialGradient(Gradient(colors: [Color(red: 0.78, green: 0.85, blue: 1).opacity(0.12), .clear]),
                                            center: moon, startRadius: moonRadius * 0.8, endRadius: moonRadius * 2))
            var crescent = Path(ellipseIn: moonRect)
            crescent.addEllipse(in: moonRect.offsetBy(dx: moonRadius * 0.54, dy: -moonRadius * 0.30))
            var moonDisk = disk
            moonDisk.clip(to: Path(ellipseIn: moonRect))
            moonDisk.fill(crescent, with: .color(Color(red: 0.88, green: 0.92, blue: 1).opacity(0.82)), style: FillStyle(eoFill: true))
            context.fill(bounds, with: .linearGradient(Gradient(stops: [
                .init(color: warmth.opacity(0), location: 0),
                .init(color: warmth.opacity(0), location: 0.64),
                .init(color: warmth.opacity(0.12), location: 0.85),
                .init(color: warmth.opacity(0.23), location: 0.94),
                .init(color: warmth.opacity(0.08), location: 1)
            ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        }
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.17),
                .init(color: .black, location: 0.83),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1)
            ], startPoint: .leading, endPoint: .trailing))
        }
        .accessibilityHidden(true)
    }
}
