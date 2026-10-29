import AppKit
import SwiftUI
import CoreImage
import AuralimCore

@MainActor
protocol AppearanceTransitionPlaying {
    func play(_ appearance: Appearance, title: String, completion: @escaping @MainActor () -> Void)
    func stop()
}

extension AppearanceTransitionPlaying {
    func play(_ appearance: Appearance, title: String) {
        play(appearance, title: title, completion: {})
    }
}

enum AppearanceTransitionLayout {
    static let duration: TimeInterval = 3.2
    static func frame(on screen: CGRect) -> CGRect {
        let size = CGSize(width: screen.width * 0.96, height: screen.height * 0.84)
        return CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}

/// Screen-left represents east and screen-right west. Both bodies travel in
/// the same direction; the one setting hands the sky over to the one rising.
enum CelestialOrbit {
    static func radius(for size: CGSize) -> CGFloat { min(60, size.height * 0.105) }
    static func position(progress: Double, rising: Bool, size: CGSize) -> CGPoint {
        let progress = min(1, max(0, progress))
        let start = rising ? Double.pi : Double.pi / 2
        let end = rising ? Double.pi / 2 : 0
        let angle = start + (end - start) * progress
        let radius = radius(for: size)
        let reach = max(0, min(size.width * 0.25, size.width * 0.26 - radius))
        return CGPoint(x: size.width * 0.5 + reach * cos(angle),
                       y: size.height * (0.72 - 0.22 * sin(angle)))
    }
}

/// A diffuse sky centered on the pointer's display. A single one-shot timer
/// releases it before applying appearance; rendering owns the fade envelope.
@MainActor
final class AppearanceTransitionController: AppearanceTransitionPlaying {
    private(set) var panel: NSPanel?
    private var dismissal: Timer?
    private var completion: (@MainActor () -> Void)?
    private var accessibilityObserver: NSObjectProtocol?
    private let reduceMotion: () -> Bool
    private let duration: TimeInterval

    init(reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         duration: TimeInterval = AppearanceTransitionLayout.duration) {
        self.reduceMotion = reduceMotion
        self.duration = duration
    }

    func play(_ appearance: Appearance, title: String, completion: @escaping @MainActor () -> Void) {
        stop()
        // This is a large motion effect: omit it when macOS asks to
        // reduce motion, rather than replacing it with a large static overlay.
        guard !reduceMotion(),
              let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { completion(); return }
        self.completion = completion
        let frame = AppearanceTransitionLayout.frame(on: screen.frame)
        // Prepare the static, quarter-resolution blur before starting playback.
        _ = TransitionSkyMask.image(for: frame.size)
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
        panel.alphaValue = 1
        self.panel = panel
        panel.orderFrontRegardless()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.reduceMotion() else { return }
                self.finish()
            }
        }
        let dismissal = Timer(timeInterval: duration, repeats: false) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, self.panel === panel else { return }
                self.finish()
            }
        }
        self.dismissal = dismissal
        RunLoop.main.add(dismissal, forMode: .common)
    }

    private func finish() {
        let completed = completion
        stop() // Release the overlay before asking macOS to redraw its windows.
        completed?()
    }

    func stop() {
        completion = nil
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
            self.accessibilityObserver = nil
        }
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

/// The website timeline: establish the initial sky, travel, then hold the
/// completed sky briefly while fading out. Geometry easing is independent of color.
struct SolarTransitionPhase {
    let travel: Double
    let orbit: Double
    let moonOrbit: Double
    let daylight: Double
    let sunlight: Double
    let moonlight: Double
    let opacity: Double

    init(progress: Double, appearance: Appearance) {
        let phase = min(1, max(0, progress))
        travel = min(1, max(0, (phase - 0.12) / 0.60))
        orbit = Self.ease(travel)
        moonOrbit = appearance == .dark ? Self.ease(max(0, travel - 0.045) / 0.955) : orbit
        let sky = travel * travel * (3 - 2 * travel)
        daylight = appearance == .light ? sky : 1 - sky
        func visible(_ value: Double) -> Double {
            let t = min(1, max(0, (value - 0.06) / 0.72))
            return t * t * (3 - 2 * t)
        }
        sunlight = visible(daylight); moonlight = visible(1 - daylight)
        opacity = max(0, min(1, phase / 0.14, (1 - phase) / 0.26)) * 0.78
    }

    static func ease(_ phase: Double) -> Double {
        let target = min(1, max(0, phase))
        var low = 0.0, high = 1.0
        for _ in 0..<16 {
            let t = (low + high) / 2
            let x = 3 * pow(1 - t, 2) * t * 0.35 + 3 * (1 - t) * t * t * 0.25 + t * t * t
            if x < target { low = t } else { high = t }
        }
        let t = (low + high) / 2
        return 3 * (1 - t) * t * t + t * t * t
    }
}

/// A small, read-only alpha texture. Core Image blur runs on cache misses only,
/// before the panel is shown; the GPU reuses the resulting texture during playback.
enum TransitionSkyMask {
    private static let cache: NSCache<NSString, NSImage> = {
        let result = NSCache<NSString, NSImage>(); result.countLimit = 4; return result
    }()
    private static let renderer = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])

    static func image(for size: CGSize) -> NSImage {
        let width = max(1, Int(ceil(size.width * 0.25)))
        let height = max(1, Int(ceil(size.height * 0.25)))
        let key = "\(width)x\(height)" as NSString
        if let existing = cache.object(forKey: key) { return existing }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return NSImage(size: size)
        }
        ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: CGFloat(width) * 0.5, y: CGFloat(height))
        ctx.scaleBy(x: CGFloat(width) * 0.52, y: CGFloat(height) * 0.98)
        let stops: [(CGFloat, CGFloat)] = [(0, 1), (0.24, 1), (0.45, 0.94), (0.65, 0.80),
            (0.80, 0.56), (1, 0.27), (1.15, 0.10), (1.35, 0)]
        let colors = stops.map { CGColor(colorSpace: colorSpace, components: [0, 0, 0, $0.1])! }
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: stops.map { $0.0 / 1.35 })!
        ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero,
                               endRadius: 1.35, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        guard let raw = ctx.makeImage() else { return NSImage(size: size) }
        let input = CIImage(cgImage: raw)
        let blur = min(100, max(28, min(size.width, size.height) * 0.10)) * 0.25
        let blurred = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur])
        guard let output = renderer.createCGImage(blurred, from: input.extent) else { return NSImage(cgImage: raw, size: size) }
        let image = NSImage(cgImage: output, size: size)
        cache.setObject(image, forKey: key)
        return image
    }
}

struct AppearanceTransitionView: View {
    let appearance: Appearance
    var duration = AppearanceTransitionLayout.duration
    @State private var progress = 0.0

    var body: some View {
        SolarTransitionScene(progress: progress, appearance: appearance)
            .accessibilityHidden(true)
            .task {
                withAnimation(.linear(duration: duration)) { progress = 1 }
            }
    }
}

/// Native Canvas port of the website's desktop sky. Only the sky is dome-masked;
/// sun and crescent contours stay sharp, with their own halos and surface shading.
struct SolarTransitionScene: View, Animatable {
    var progress: Double
    var appearance: Appearance = .light
    var animatableData: Double { get { progress } set { progress = newValue } }

    var body: some View {
        let state = SolarTransitionPhase(progress: progress, appearance: appearance)
        Canvas { context, size in
            let horizon = size.height * 0.9, radius = CelestialOrbit.radius(for: size)
            let bounds = Path(CGRect(origin: .zero, size: size))
            let rect = CGRect(origin: .zero, size: size)
            func color(_ night: (Double, Double, Double), _ light: (Double, Double, Double)) -> Color {
                Color(red: night.0 + (light.0 - night.0) * state.daylight,
                      green: night.1 + (light.1 - night.1) * state.daylight,
                      blue: night.2 + (light.2 - night.2) * state.daylight)
            }
            let zenith = color((0.065, 0.095, 0.18), (0.45, 0.66, 0.86))
            let sky = color((0.14, 0.19, 0.31), (0.64, 0.78, 0.90))
            let horizonSky = color((0.26, 0.29, 0.40), (0.94, 0.85, 0.71))
            let warmth = color((0.35, 0.34, 0.47), (1, 0.68, 0.39))
            let sun = CelestialOrbit.position(progress: state.orbit, rising: appearance == .light, size: size)
            let moon = CelestialOrbit.position(progress: state.moonOrbit, rising: appearance == .dark, size: size)
            let moonAtmosphere = CelestialOrbit.position(progress: state.orbit, rising: appearance == .dark, size: size)
            let mr = radius * 0.76
            context.drawLayer { background in
                background.fill(bounds, with: .linearGradient(Gradient(stops: [
                    .init(color: zenith.opacity(0.96), location: 0), .init(color: sky.opacity(0.96), location: 0.55),
                    .init(color: horizonSky.opacity(0.94), location: 1)
                ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                background.fill(bounds, with: .radialGradient(Gradient(stops: [
                    .init(color: warmth.opacity(0.35 * state.sunlight), location: 0),
                    .init(color: warmth.opacity(0.13 * state.sunlight), location: 0.4), .init(color: .clear, location: 1)
                ]), center: CGPoint(x: sun.x, y: min(sun.y, horizon)), startRadius: radius * 0.5, endRadius: size.height * 0.7))
                background.fill(bounds, with: .radialGradient(Gradient(stops: [
                    .init(color: Color(red: 43/255, green: 60/255, blue: 91/255).opacity(0.28 * state.moonlight), location: 0),
                    .init(color: Color(red: 53/255, green: 71/255, blue: 104/255).opacity(0.20 * state.moonlight), location: 0.28),
                    .init(color: Color(red: 64/255, green: 83/255, blue: 118/255).opacity(0.07 * state.moonlight), location: 0.65),
                    .init(color: .clear, location: 1)
                ]), center: moonAtmosphere, startRadius: 0, endRadius: mr * 4.8))
                background.fill(bounds, with: .linearGradient(Gradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .clear, location: 0.64),
                    .init(color: warmth.opacity(0.12), location: 0.85), .init(color: warmth.opacity(0.23), location: 0.94),
                    .init(color: warmth.opacity(0.08), location: 1)
                ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                background.blendMode = .destinationIn
                background.draw(Image(nsImage: TransitionSkyMask.image(for: size)).interpolation(.high), in: rect)
            }
            var disk = context
            disk.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)))
            disk.opacity = state.sunlight
            disk.fill(Path(ellipseIn: CGRect(x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(Gradient(stops: [
                    .init(color: Color(red: 1, green: 237/255, blue: 189/255).opacity(0.92), location: 0),
                    .init(color: Color(red: 1, green: 196/255, blue: 117/255).opacity(0.78), location: 1)
                ]), center: sun, startRadius: 0, endRadius: radius))
            var lunar = context
            lunar.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)))
            lunar.opacity = state.moonlight
            lunar.fill(Path(ellipseIn: CGRect(x: moon.x - mr * 1.8, y: moon.y - mr * 1.8, width: mr * 3.6, height: mr * 3.6)),
                with: .radialGradient(Gradient(colors: [Color(red: 185/255, green: 204/255, blue: 235/255).opacity(0.06), .clear]),
                    center: moon, startRadius: mr * 0.8, endRadius: mr * 1.8))
            let moonRect = CGRect(x: moon.x - mr, y: moon.y - mr, width: mr * 2, height: mr * 2)
            let crescent = CrescentMoon().path(in: moonRect)
            var surface = lunar
            surface.addFilter(.shadow(color: Color(red: 51/255, green: 70/255, blue: 105/255).opacity(0.28), radius: mr * 0.12))
            surface.fill(crescent, with: .linearGradient(Gradient(stops: [
                .init(color: Color(red: 232/255, green: 239/255, blue: 250/255).opacity(0.97), location: 0),
                .init(color: Color(red: 212/255, green: 224/255, blue: 243/255).opacity(0.97), location: 0.5),
                .init(color: Color(red: 178/255, green: 197/255, blue: 224/255).opacity(0.96), location: 1)
            ]), startPoint: CGPoint(x: moon.x - mr, y: moon.y - mr), endPoint: CGPoint(x: moon.x + mr, y: moon.y + mr)))
            lunar.stroke(crescent, with: .color(Color(red: 66/255, green: 87/255, blue: 123/255).opacity(0.42)), lineWidth: 0.8)
        }
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.17),
                .init(color: .black, location: 0.83), .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92), .init(color: .clear, location: 1)
            ], startPoint: .leading, endPoint: .trailing))
        }
        .opacity(state.opacity)
        .accessibilityHidden(true)
    }
}

/// A single contour avoids the antialiased full-circle seam produced by an
/// even-odd pair of disks clipped against the outer disk.
struct CrescentMoon: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        guard radius > 0 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let offset = CGPoint(x: radius * 0.54, y: -radius * 0.30)
        let direction = atan2(offset.y, offset.x)
        let angle = acos(hypot(offset.x, offset.y) / (2 * radius))
        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: .radians(direction - angle), endAngle: .radians(direction + angle), clockwise: true)
        path.addArc(center: CGPoint(x: center.x + offset.x, y: center.y + offset.y), radius: radius,
                    startAngle: .radians(direction + .pi - angle), endAngle: .radians(direction + .pi + angle), clockwise: false)
        path.closeSubpath()
        return path
    }
}
