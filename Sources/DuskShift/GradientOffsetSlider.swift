import AppKit
import SwiftUI

/// Keeps native mouse tracking, keyboard focus and accessibility while drawing
/// an appearance gradient instead of the system accent-color progress bar.
struct GradientOffsetSlider: NSViewRepresentable {
    @Binding var value: Double // -120...120; physical right is earlier.
    let sunrise: Bool
    let label: String
    let summary: String
    let identifier: String
    let onEditingChanged: (Bool) -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> AppearanceSlider {
        let slider = AppearanceSlider()
        slider.cell = AppearanceSliderCell()
        slider.minValue = 0; slider.maxValue = 1
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.editingChanged = { [weak coordinator = context.coordinator] editing in
            coordinator?.parent.onEditingChanged(editing)
        }
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return slider
    }

    func updateNSView(_ slider: AppearanceSlider, context: Context) {
        context.coordinator.parent = self
        slider.doubleValue = min(1, max(0, (value + 120) / 240))
        slider.isEnabled = isEnabled
        (slider.cell as? AppearanceSliderCell)?.sunrise = sunrise
        slider.setAccessibilityLabel(label)
        slider.setAccessibilityIdentifier(identifier)
        slider.setAccessibilityValueDescription(summary)
        slider.needsDisplay = true
    }

    final class Coordinator: NSObject {
        var parent: GradientOffsetSlider
        init(_ parent: GradientOffsetSlider) { self.parent = parent }
        @objc func changed(_ slider: AppearanceSlider) {
            let position = (slider.doubleValue * 240 - 120).rounded()
            slider.doubleValue = (position + 120) / 240
            parent.value = position
            slider.needsDisplay = true
            if !slider.isTrackingMouse { parent.onEditingChanged(false) }
        }
    }
}

final class AppearanceSlider: NSSlider {
    var editingChanged: ((Bool) -> Void)?
    private(set) var isTrackingMouse = false

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isTrackingMouse = true
        editingChanged?(true)
        super.mouseDown(with: event)
        isTrackingMouse = false
        editingChanged?(false)
    }

    private func move(_ direction: Double, step: Double = 1) {
        guard isEnabled else { return }
        doubleValue = min(1, max(0, doubleValue + direction * step / 240))
        _ = sendAction(action, to: target)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 125: move(-1, step: event.modifierFlags.contains(.option) ? 10 : 1)
        case 124, 126: move(1, step: event.modifierFlags.contains(.option) ? 10 : 1)
        default: super.keyDown(with: event)
        }
    }

    override func accessibilityPerformIncrement() -> Bool { guard isEnabled else { return false }; move(1); return true }
    override func accessibilityPerformDecrement() -> Bool { guard isEnabled else { return false }; move(-1); return true }
}

final class AppearanceSliderCell: NSSliderCell {
    var sunrise = true
    static let trackColor = NSColor(srgbRed: 0.29, green: 0.30, blue: 0.33, alpha: 1)
    static let night = NSColor(srgbRed: 0.18, green: 0.24, blue: 0.38, alpha: 1)
    static let day = NSColor(srgbRed: 1, green: 0.87, blue: 0.61, alpha: 1)

    private var fraction: CGFloat { CGFloat(min(1, max(0, doubleValue))) }
    private var selectionColor: NSColor {
        let towardLight = sunrise ? fraction > 0.5 : fraction < 0.5
        let endpoint = towardLight ? Self.day : Self.night
        return Self.trackColor.blended(withFraction: abs(fraction - 0.5) * 2, of: endpoint) ?? endpoint
    }

    private func track(in rect: NSRect) -> NSRect {
        NSRect(x: rect.minX, y: rect.midY - 6, width: rect.width, height: 12)
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let bar = track(in: rect)
        let outline = NSBezierPath(roundedRect: bar, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        let context = NSGraphicsContext.current?.cgContext
        context?.setAlpha(isEnabled ? 1 : 0.35)
        context?.beginTransparencyLayer(auxiliaryInfo: nil)
        Self.trackColor.setFill()
        outline.fill()
        let center = bar.midX
        let position = bar.minX + bar.width * fraction
        // One capsule, one selected interval. The gradient begins with the same
        // gray as the track, avoiding a visible join at the neutral position.
        if abs(position - center) > 0.01 {
            let selected = NSRect(x: min(center, position), y: bar.minY,
                                  width: abs(position - center), height: bar.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selected).addClip()
            NSGradient(starting: Self.trackColor, ending: selectionColor)?
                .draw(in: selected, angle: position < center ? 180 : 0)
            NSGraphicsContext.restoreGraphicsState()
        }
        context?.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.labelColor.withAlphaComponent(0.09).setStroke()
        outline.lineWidth = 0.5; outline.stroke()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let circle = NSRect(x: knobRect.midX - 10, y: knobRect.midY - 10, width: 20, height: 20)
        let path = NSBezierPath(ovalIn: circle)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 3
        shadow.set()
        NSColor.white.withAlphaComponent(isEnabled ? 1 : 0.5).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        selectionColor.withAlphaComponent(isEnabled ? 1 : 0.35).setFill()
        NSBezierPath(ovalIn: circle.insetBy(dx: 3, dy: 3)).fill()
    }
}
