import AppKit
import CoreFoundation
import DuskShiftCore

/// Read-only snapshot of macOS appearance preferences, separate from the app's
/// solar schedule. A missing Auto preference is the system's fixed-mode default.
struct SystemAppearanceSettings: Equatable {
    enum Mode { case light, dark, automatic, unknown }
    let mode: Mode
    let appearance: Appearance

    init(mode: Mode, appearance: Appearance) {
        self.mode = mode
        self.appearance = appearance
    }

    init(automatic: Any?, style: Any?, fallback: Appearance) {
        let parsedStyle: Appearance? = style == nil ? .light
            : (style as? String == "Dark" ? .dark : style as? String == "Light" ? .light : nil)
        appearance = parsedStyle ?? fallback
        if let automatic {
            guard let number = automatic as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID() || number == 0 || number == 1 else {
                mode = .unknown
                return
            }
            if number.boolValue { mode = .automatic; return }
        }
        mode = parsedStyle.map { $0 == .dark ? .dark : .light } ?? .unknown
    }

    @MainActor
    static func current() -> Self {
        // Exact global domains avoid an app-specific appearance override. This
        // never writes preferences or asks System Events for Automation access.
        let fallback: Appearance = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        for host in [kCFPreferencesCurrentHost, kCFPreferencesAnyHost] {
            guard CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, host) else {
                return Self(mode: .unknown, appearance: fallback)
            }
        }
        func read(_ key: String) -> Any? {
            for host in [kCFPreferencesCurrentHost, kCFPreferencesAnyHost] {
                if let value = CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication,
                                                     kCFPreferencesCurrentUser, host) { return value }
            }
            return nil
        }
        return Self(automatic: read("AppleInterfaceStyleSwitchesAutomatically"),
                    style: read("AppleInterfaceStyle"), fallback: fallback)
    }
}
