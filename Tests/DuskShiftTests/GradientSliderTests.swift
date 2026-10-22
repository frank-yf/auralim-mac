import AppKit
import Testing
@testable import DuskShift

@MainActor
struct GradientSliderTests {
    private func render(sunrise: Bool, position: Double, appearance: NSAppearance.Name = .aqua) throws -> NSBitmapImageRep {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 24,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        let theme = try #require(NSAppearance(named: appearance))
        theme.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 24)).fill()
            let cell = AppearanceSliderCell()
            cell.minValue = 0; cell.maxValue = 1; cell.doubleValue = position
            cell.sunrise = sunrise
            cell.drawBar(inside: NSRect(x: 0, y: 0, width: 200, height: 24), flipped: false)
        }
        return bitmap
    }

    private func color(_ bitmap: NSBitmapImageRep, x: Int) throws -> NSColor {
        try #require(bitmap.colorAt(x: x, y: 12)?.usingColorSpace(.sRGB))
    }

    private func difference(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        abs(lhs.redComponent - rhs.redComponent) + abs(lhs.greenComponent - rhs.greenComponent) + abs(lhs.blueComponent - rhs.blueComponent)
    }

    @Test func defaultTrackIsSubtleAndUniformInBothAppearances() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let baseline = try color(render(sunrise: true, position: 0.5, appearance: appearance), x: 25)
            let luminance = baseline.redComponent * 0.2126 + baseline.greenComponent * 0.7152 + baseline.blueComponent * 0.0722
            #expect(appearance == .aqua ? luminance > 0.8 && luminance < 0.94 : luminance > 0.2 && luminance < 0.38)
            for sunrise in [true, false] {
                let neutral = try render(sunrise: sunrise, position: 0.5, appearance: appearance)
                for x in [25, 50, 99, 100, 101, 150, 175] {
                    #expect(try difference(color(neutral, x: x), baseline) < 0.01)
                }
            }
        }
    }

    @Test func bothEventsHaveVisibleSelectedColorsAndUnchangedUnselectedTrack() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for sunrise in [true, false] {
                let neutral = try render(sunrise: sunrise, position: 0.5, appearance: appearance)
                for position in [0.15, 0.375, 0.625, 0.85] {
                    let selected = try render(sunrise: sunrise, position: position, appearance: appearance)
                    let inside = position < 0.5 ? (position < 0.25 ? 50 : 80) : (position > 0.75 ? 150 : 120)
                    let towardLight = sunrise ? position > 0.5 : position < 0.5
                    let tint = try color(selected, x: inside)
                    let base = try color(neutral, x: inside)
                    #expect(difference(tint, base) > 0.1)
                    let warmth = tint.redComponent - tint.blueComponent
                    let baseWarmth = base.redComponent - base.blueComponent
                    #expect(towardLight ? warmth > baseWarmth + 0.08 : warmth < baseWarmth - 0.08)
                    // Both beyond the thumb and on the unselected half stay gray.
                    for x in position < 0.5 ? [25, 150, 175] : [25, 50, 175] {
                        #expect(try difference(color(selected, x: x), color(neutral, x: x)) < 0.01)
                    }
                    // No center marker can bleed into the unselected side.
                    let centerOutside = position < 0.5 ? 100 : 99
                    #expect(try difference(color(selected, x: centerOutside), color(neutral, x: centerOutside)) < 0.01)
                }
            }
        }
    }

}
