import SwiftUI
import DuskShiftCore

enum AppearanceMode: String, CaseIterable, Identifiable {
    case light, automatic, dark
    var id: String { rawValue }
    var localizationKey: String { self == .automatic ? "auto" : rawValue }
    var appearance: Appearance? { self == .automatic ? nil : self == .dark ? .dark : .light }
}

struct AppearanceModePicker: View {
    @Binding var selection: AppearanceMode
    let localizer: Localizer
    let identifier: String

    var body: some View {
        Picker(localizer.text("appearance.mode"), selection: $selection) {
            ForEach(AppearanceMode.allCases) { mode in
                Text(localizer.text(mode.localizationKey)).tag(mode)
            }
        }
        .pickerStyle(.segmented).labelsHidden()
        .accessibilityIdentifier(identifier)
    }
}
