import AppKit
import SwiftUI

/// Shared, appearance-aware surfaces; slider colors remain independently tuned.
enum DuskStyle {
    static let background = Color(nsColor: NSColor(name: "DuskBackground") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.12, green: 0.13, blue: 0.16, alpha: 1)
            : NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    })
    static let surface = Color(nsColor: NSColor(name: "DuskSurface") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.17, green: 0.18, blue: 0.21, alpha: 1)
            : NSColor.white
    })
    static let blue = Color(nsColor: NSColor(name: "DuskBlue") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.62, green: 0.73, blue: 0.91, alpha: 1)
            : NSColor(srgbRed: 0.35, green: 0.47, blue: 0.68, alpha: 1)
    })
    static let gold = Color(nsColor: NSColor(name: "DuskGold") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.94, green: 0.76, blue: 0.46, alpha: 1)
            : NSColor(srgbRed: 0.66, green: 0.45, blue: 0.18, alpha: 1)
    })
}

struct DuskMark: View {
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: "sun.horizon.fill")
            .font(.system(size: size * 0.52, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(red: 0.40, green: 0.49, blue: 0.68),
                                                Color(red: 0.72, green: 0.65, blue: 0.57)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct DuskSymbol: View {
    let name: String
    var tint = DuskStyle.blue
    var body: some View {
        Image(systemName: name).font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct DuskNotice: View {
    let text: String
    var warning = false
    var body: some View {
        Label(text, systemImage: warning ? "exclamationmark.circle" : "info.circle")
            .font(.caption)
            .foregroundStyle(warning ? Color.orange : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DuskCard: ViewModifier {
    var padding: CGFloat
    func body(content: Content) -> some View {
        content.padding(padding)
            .background(DuskStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func duskCard(padding: CGFloat = 14) -> some View { modifier(DuskCard(padding: padding)) }
}
