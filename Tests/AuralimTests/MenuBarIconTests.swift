import AppKit
import SwiftUI
import Testing
import AuralimCore
@testable import Auralim

@MainActor
struct MenuBarIconTests {
    @Test func symbolsKeepTheirColorsAtStandardAndRetinaScale() throws {
        for appearance in [Appearance.light, .dark] {
            let image = MenuBarIcon.image(for: appearance)
            #expect(!image.isTemplate)
            #expect(image.size == NSSize(width: 18, height: 18))
            #expect(MenuBarIcon.symbol(for: appearance) == (appearance == .dark ? "moon.fill" : "sun.max.fill"))
            let expected = MenuBarIcon.color(for: appearance)
            for width in [18, 36] {
                let bitmap = try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.first { $0.pixelsWide == width })
                var opaquePixels = 0
                for y in 0..<width {
                    for x in 0..<width {
                        let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        if color.alphaComponent > 0.95 {
                            opaquePixels += 1
                            #expect(abs(color.redComponent - expected.redComponent) < 0.02)
                            #expect(abs(color.greenComponent - expected.greenComponent) < 0.02)
                            #expect(abs(color.blueComponent - expected.blueComponent) < 0.02)
                        }
                    }
                }
                #expect(opaquePixels > width)
            }
        }
    }

    @Test func crescentCutoutHasNoOuterCircleSeam() throws {
        let renderer = ImageRenderer(content: CrescentMoon().fill(.white).frame(width: 100, height: 100))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var crescentPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let alpha = try #require(bitmap.colorAt(x: x, y: y)).alphaComponent
                // Bitmap rows are top-down. The overlapping circle's interior,
                // including the old outer rim, must be fully transparent.
                let dx = (Double(x) + 0.5) / 2 - 77
                let dy = (Double(y) + 0.5) / 2 - 35
                if hypot(dx, dy) < 49 { #expect(alpha < 0.01) }
                if alpha > 0.95 { crescentPixels += 1 }
            }
        }
        #expect(crescentPixels > 1000)
        let output = URL(fileURLWithPath: "artifacts/menu-bar-0.3.2", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("crescent.png"))
        for appearance in [Appearance.light, .dark] {
            let bitmap = try #require(MenuBarIcon.image(for: appearance).representations.last as? NSBitmapImageRep)
            try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(appearance == .dark ? "moon.png" : "sun.png"))
        }
    }
}
