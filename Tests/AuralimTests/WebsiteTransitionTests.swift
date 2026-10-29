import AppKit
import SwiftUI
import Testing
import AuralimCore
@testable import Auralim

@MainActor
@Suite(.serialized)
struct WebsiteTransitionTests {
    @Test func phaseMatchesWebsiteInitialMiddleAndFinalSkies() {
        for target in [Appearance.light, .dark] {
            let start = SolarTransitionPhase(progress: 0.16, appearance: target)
            let middle = SolarTransitionPhase(progress: 0.42, appearance: target)
            let end = SolarTransitionPhase(progress: 0.72, appearance: target)
            #expect(target == .light ? start.daylight < 0.02 : start.daylight > 0.98)
            #expect(abs(middle.daylight - 0.5) < 0.00001)
            #expect(target == .light ? end.daylight > 0.999 : end.daylight < 0.001)
            #expect(start.opacity == 0.78 && middle.opacity == 0.78 && abs(end.opacity - 0.78) < 0.00001)
            #expect(SolarTransitionPhase(progress: 0, appearance: target).opacity == 0)
            #expect(SolarTransitionPhase(progress: 1, appearance: target).opacity == 0)
            #expect(target == .dark ? middle.moonOrbit < middle.orbit : middle.moonOrbit == middle.orbit)
            #expect(SolarTransitionPhase(progress: 0, appearance: target).orbit < 0.00001)
            #expect(end.orbit > 0.99999)
            #expect(target == .light ? end.sunlight == 1 && end.moonlight == 0 : end.sunlight == 0 && end.moonlight == 1)
        }
    }

    @Test func blurMaskIsCachedAndHasBroadProgressiveFeathering() throws {
        let size = CGSize(width: 1000, height: 600)
        let mask = TransitionSkyMask.image(for: size)
        #expect(mask === TransitionSkyMask.image(for: size))
        let cg = try #require(mask.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cg)
        #expect(bitmap.pixelsWide == 250 && bitmap.pixelsHigh == 150)
        func alpha(_ x: Double, _ y: Double) throws -> CGFloat {
            try #require(bitmap.colorAt(x: Int(Double(bitmap.pixelsWide) * x), y: Int(Double(bitmap.pixelsHigh) * y))).alphaComponent
        }
        let top = try alpha(0.5, 0.1), feather = try alpha(0.5, 0.2), crown = try alpha(0.5, 0.3), core = try alpha(0.5, 0.6)
        print("Native sky mask alpha:", top, feather, crown, core)
        #expect(top < feather && feather < crown && crown < core)
        #expect(top > 0.15 && top < 0.6 && core > 0.8)
        #expect(try alpha(0.1, 0.3) < 0.4)
        #expect(mask !== TransitionSkyMask.image(for: CGSize(width: 1200, height: 600)))
    }

    @Test func enlargedDisksRemainWithinDenseSkyAndOutsideEdgeFades() {
        for size in [CGSize(width: 1843, height: 907), CGSize(width: 1000, height: 600), CGSize(width: 374, height: 709)] {
            let radius = CelestialOrbit.radius(for: size)
            #expect(radius == min(60, size.height * 0.105))
            for rising in [true, false] {
                for frame in 0...20 {
                    let center = CelestialOrbit.position(progress: Double(frame) / 20, rising: rising, size: size)
                    for edge in 0..<24 {
                        let angle = Double(edge) / 24 * Double.pi * 2
                        let x = center.x + radius * cos(angle), y = center.y + radius * sin(angle)
                        #expect(hypot((x - size.width * 0.5) / (size.width * 0.52), (y - size.height) / (size.height * 0.98)) < 0.66)
                        #expect(x >= size.width * 0.08 && x <= size.width * 0.92 && y >= size.height * 0.17 && y <= size.height * 0.83)
                    }
                }
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AURALIM_WEBSITE_TRANSITION_UI_TESTS"] == "1"))
    func nativeSkiesRenderInBothDirectionsOnLightAndDarkWindows() throws {
        let app = NSApplication.shared; app.setActivationPolicy(.regular); app.finishLaunching()
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AURALIM_WEBSITE_TRANSITION_UI_OUTPUT"] ?? "/private/tmp/auralim-native-website-ui")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let size = CGSize(width: 1000, height: 650)
        let window = NSWindow(contentViewController: NSHostingController(rootView: Color.white.frame(width: size.width, height: size.height)))
        window.isReleasedWhenClosed = false; window.center(); window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        for darkBackground in [false, true] {
            for target in [Appearance.light, .dark] {
                var brightness: [Double] = []
                for (stage, progress) in [("start", 0.16), ("middle", 0.42), ("end", 0.72)] {
                    let backdrop = darkBackground ? Color(red: 0.12, green: 0.13, blue: 0.16) : .white
                    window.contentView = NSHostingView(rootView: SolarTransitionScene(progress: progress, appearance: target)
                        .frame(width: size.width, height: size.height).background(backdrop))
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.16))
                    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    let name = "\(target == .light ? "sunrise" : "sunset")-\(stage)-\(darkBackground ? "dark" : "light").png"
                    process.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.appendingPathComponent(name).path]
                    try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
                    let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: output.appendingPathComponent(name))))
                    let scale = CGFloat(bitmap.pixelsWide) / size.width
                    let titleHeight = window.frame.height - (window.contentView?.bounds.height ?? size.height)
                    let sample = try #require(bitmap.colorAt(x: Int(size.width * 0.4 * scale), y: Int((titleHeight + size.height * 0.45) * scale))?.usingColorSpace(.deviceRGB))
                    brightness.append(Double((sample.redComponent + sample.greenComponent + sample.blueComponent) / 3))
                }
                #expect(brightness.count == 3)
                #expect(target == .light ? brightness[2] - brightness[0] > 0.12 : brightness[0] - brightness[2] > 0.12)
            }
        }
    }
}
