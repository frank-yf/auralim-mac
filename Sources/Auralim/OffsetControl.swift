import SwiftUI
import AuralimCore

struct OffsetControl: View {
    let title: String
    let leftLabel: String
    let rightLabel: String
    @Binding var minutes: Int
    var localizer = Localizer(language: .system)
    var identifier = "offset"
    var sunrise = true
    @State private var draft = 0
    @State private var text = "0"
    @State private var inputError = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                DuskSymbol(name: sunrise ? "sunrise.fill" : "sunset.fill", tint: sunrise ? DuskStyle.gold : DuskStyle.blue)
                Text(localizer.text("offset.title", title)).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(summary)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.04), in: Capsule())
                Button(localizer.text("offset.reset")) { updateDraft(0); commit() }.font(.caption).controlSize(.small)
                    .accessibilityIdentifier("\(identifier)-reset")
            }
            HStack(spacing: 12) {
                GradientOffsetSlider(value: Binding(
                        get: { SolarOffset.sliderPosition(for: draft) },
                        set: { updateDraft(SolarOffset.minutes(forSliderPosition: $0)) }
                    ), sunrise: sunrise,
                    label: localizer.text("offset.accessibility", title, leftLabel, rightLabel),
                    summary: summary, identifier: "\(identifier)-slider", onEditingChanged: { editing in
                        if !editing { commit() }
                    })
                    .frame(height: 28)
                TextField(localizer.text("offset.placeholder"), text: $text)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 62)
                    .focused($inputFocused)
                    .onSubmit { commitText() }
                    .onChange(of: text) { value in
                        // Preview valid text immediately without applying half-entered values.
                        if let parsed = SolarOffset.parse(value) { draft = parsed; inputError = false }
                    }
                    .onChange(of: inputFocused) { focused in if !focused { commitText() } }
                    .accessibilityLabel(localizer.text("offset.inputAccessibility", title))
                    .accessibilityIdentifier("\(identifier)-input")
                Text(localizer.text("offset.unit")).font(.caption)
            }
            HStack {
                Label(leftLabel, systemImage: sunrise ? "moon.fill" : "sun.max.fill")
                Spacer()
                Text("0")
                Spacer()
                Label(rightLabel, systemImage: sunrise ? "sun.max.fill" : "moon.fill")
            }.font(.caption).foregroundStyle(.secondary).padding(.trailing, 88)
            if inputError {
                Text(localizer.text("offset.invalid")).font(.caption2).foregroundStyle(.red)
            }
        }
        .duskCard()
        .onAppear { updateDraft(minutes) }
        .onChange(of: minutes) { updateDraft($0) }
    }

    private var summary: String {
        draft == 0 ? localizer.text("offset.onTime")
            : localizer.text(draft < 0 ? "offset.earlier" : "offset.later", abs(draft))
    }

    private func updateDraft(_ value: Int) {
        draft = SolarOffset.clamp(value)
        text = draft > 0 ? "+\(draft)" : "\(draft)"
        inputError = false
    }
    private func commit() {
        if minutes != draft { minutes = draft }
    }
    private func commitText() {
        guard let value = SolarOffset.parse(text) else { inputError = true; return }
        updateDraft(value)
        commit()
    }
}
