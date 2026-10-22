import Foundation

public enum SolarOffset {
    public static func clamp(_ minutes: Int) -> Int { min(120, max(-120, minutes)) }

    /// Signed clock offset: negative means earlier, positive means later.
    /// Moving right brings the upcoming appearance forward for both events.
    public static func sliderPosition(for minutes: Int) -> Double { -Double(clamp(minutes)) }
    public static func minutes(forSliderPosition position: Double) -> Int {
        guard position.isFinite else { return 0 }
        return Int(-min(120, max(-120, position)).rounded())
    }
    public static func parse(_ text: String) -> Int? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "−", with: "-")
        return Int(normalized).map(clamp)
    }
}
