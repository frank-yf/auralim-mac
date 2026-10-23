import AppKit
import AuralimCore

@MainActor
enum MenuBarIcon {
    static func symbol(for appearance: Appearance) -> String {
        appearance == .dark ? "moon.fill" : "sun.max.fill"
    }

    static func color(for appearance: Appearance) -> NSColor {
        let rgb = appearance == .dark ? (0xA7, 0xB7, 0xF5) : (0xE6, 0xB4, 0x50)
        return NSColor(srgbRed: Double(rgb.0) / 255, green: Double(rgb.1) / 255,
                       blue: Double(rgb.2) / 255, alpha: 1)
    }

    private static let sun = makeImage(for: .light)
    private static let moon = makeImage(for: .dark)

    static func image(for appearance: Appearance) -> NSImage {
        appearance == .dark ? moon : sun
    }

    private static func makeImage(for appearance: Appearance) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        guard let source = NSImage(systemSymbolName: symbol(for: appearance), accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular)) else { return image }
        // Bake the tint into ordinary bitmap representations so the menu bar
        // cannot treat the SF Symbol as a monochrome template.
        for scale in [1, 2] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 18 * scale, pixelsHigh: 18 * scale,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            bitmap.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            let fit = min(16 / source.size.width, 16 / source.size.height)
            let fitted = NSSize(width: source.size.width * fit, height: source.size.height * fit)
            let rect = NSRect(x: (18 - fitted.width) / 2, y: (18 - fitted.height) / 2, width: fitted.width, height: fitted.height)
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            color(for: appearance).setFill()
            NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
        }
        image.isTemplate = false
        return image
    }
}
