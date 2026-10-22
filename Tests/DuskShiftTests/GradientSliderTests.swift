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

    @Test func renderedSunriseAndSunsetHaveOppositeBrightnessDirections() throws {
        let sunrise = try render(sunrise: true, position: 0.5)
        let sunset = try render(sunrise: false, position: 0.5)
        #expect(try brightness(sunrise, x: 175) > brightness(sunrise, x: 25) + 0.1)
        #expect(try brightness(sunset, x: 25) > brightness(sunset, x: 175) + 0.1)
    }

    @Test func selectedRangeChangesAsTheThumbMoves() throws {
        let neutral = try render(sunrise: true, position: 0.5)
        let left = try render(sunrise: true, position: 0.15)
        let right = try render(sunrise: true, position: 0.85)
        #expect(try abs(brightness(left, x: 50) - brightness(neutral, x: 50)) > 0.1)
        #expect(try abs(brightness(right, x: 150) - brightness(neutral, x: 150)) > 0.05)
    }
}
