import SwiftUI
import AuralimCore

enum AppearanceMode: String, CaseIterable, Identifiable {
    case light, automatic, dark
    var id: String { rawValue }
    var localizationKey: String { self == .automatic ? "auto" : rawValue }
    var appearance: Appearance? { self == .automatic ? nil : self == .dark ? .dark : .light }
}

/// One native control supports an intentionally empty selection while macOS
/// manages Auto; nil is a display state, never an extra selectable mode.
struct AppearanceModePicker: NSViewRepresentable {
    @Binding var selection: AppearanceMode?
    let localizer: Localizer
    let identifier: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: ["", "", ""], trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.setAccessibilityIdentifier(identifier)
        control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        updateNSView(control, context: context)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        for (index, mode) in AppearanceMode.allCases.enumerated() {
            control.setLabel(localizer.text(mode.localizationKey), forSegment: index)
        }
        control.setToolTip(localizer.text("appearance.auto.help"), forSegment: 1)
        control.setAccessibilityLabel(localizer.text("appearance.mode"))
        control.selectedSegment = selection.flatMap { AppearanceMode.allCases.firstIndex(of: $0) } ?? -1
    }

    final class Coordinator: NSObject {
        var parent: AppearanceModePicker
        init(_ parent: AppearanceModePicker) { self.parent = parent }
        @objc func changed(_ sender: NSSegmentedControl) {
            guard AppearanceMode.allCases.indices.contains(sender.selectedSegment) else { return }
            parent.selection = AppearanceMode.allCases[sender.selectedSegment]
        }
    }
}
