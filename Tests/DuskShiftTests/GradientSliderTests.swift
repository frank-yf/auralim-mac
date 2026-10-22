import AppKit
import Testing
@testable import DuskShift

@MainActor
struct GradientSliderTests {
    private func render(sunrise: Bool, position: Double) throws -> NSBitmapImageRep {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 24,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 24)).fill()
        let cell = AppearanceSliderCell()
        cell.minValue = 0; cell.maxValue = 1; cell.doubleValue = position
        cell.sunrise = sunrise
        cell.drawBar(inside: NSRect(x: 0, y: 0, width: 200, height: 24), flipped: false)
        return bitmap
    }

    private func brightness(_ bitmap: NSBitmapImageRep, x: Int) throws -> CGFloat {
        let color = try #require(bitmap.colorAt(x: x, y: 12)?.usingColorSpace(.sRGB))
        return color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
    }

    private func color(_ bitmap: NSBitmapImageRep, x: Int) throws -> NSColor {
        try #require(bitmap.colorAt(x: x, y: 12)?.usingColorSpace(.sRGB))
    }

    private func difference(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        abs(lhs.redComponent - rhs.redComponent) + abs(lhs.greenComponent - rhs.greenComponent) + abs(lhs.blueComponent - rhs.blueComponent)
    }

    @Test func defaultTrackIsOneUniformGrayCapsule() throws {
        let baseline = try color(render(sunrise: true, position: 0.5), x: 25)
        for sunrise in [true, false] {
            let neutral = try render(sunrise: sunrise, position: 0.5)
            for x in [25, 50, 99, 100, 101, 150, 175] {
                #expect(try difference(color(neutral, x: x), baseline) < 0.01)
            }
        }
    }

    @Test func colorOnlyAppearsBetweenCenterAndThumbInAllFourDirections() throws {
        for sunrise in [true, false] {
            let neutral = try render(sunrise: sunrise, position: 0.5)
            for position in [0.15, 0.85] {
                let selected = try render(sunrise: sunrise, position: position)
                let inside = position < 0.5 ? 50 : 150
                let towardLight = sunrise ? position > 0.5 : position < 0.5
                let change = try brightness(selected, x: inside) - brightness(neutral, x: inside)
                #expect(towardLight ? change > 0.05 : change < -0.01)
                // Both beyond the thumb and on the unselected half stay gray.
                for x in position < 0.5 ? [25, 150, 175] : [25, 50, 175] {
                    #expect(try difference(color(selected, x: x), color(neutral, x: x)) < 0.01)
                }
                // No center marker or two-piece seam: the fill blends into gray.
                #expect(try difference(color(selected, x: 99), color(selected, x: 101)) < 0.03)
            }
        }
    }
}
