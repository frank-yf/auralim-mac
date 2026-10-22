import SwiftUI
import DuskShiftCore

struct OffsetControl: View {
    let title: String
    let leftLabel: String
    let rightLabel: String
    @Binding var minutes: Int
    var localizer = Localizer(language: .system)
    var identifier = "offset"
    @State private var draft = 0
    @State private var text = "0"
    @State private var inputError = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(localizer.text("offset.title", title)).font(.headline)
                Spacer()
                Text(summary)
                    .font(.caption).foregroundStyle(.secondary)
                Button(localizer.text("offset.reset")) { updateDraft(0); commit() }.font(.caption)
            }
            HStack(spacing: 12) {
                ZStack {
                    Rectangle().fill(.secondary.opacity(0.5))
                        .frame(width: 1, height: 18).allowsHitTesting(false)
                    Slider(value: Binding(
                        get: { SolarOffset.sliderPosition(for: draft) },
                        set: { updateDraft(SolarOffset.minutes(forSliderPosition: $0)) }
                    ), in: -120...120, step: 1, onEditingChanged: { editing in
                        if !editing { commit() }
                    })
                    .accessibilityLabel(localizer.text("offset.accessibility", title, leftLabel, rightLabel))
                    .accessibilityIdentifier("\(identifier)-slider")
                    .accessibilityValue(summary)
                }
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
                Text(leftLabel)
                Spacer()
                Text("0")
                Spacer()
                Text(rightLabel)
            }.font(.caption).foregroundStyle(.secondary).padding(.trailing, 88)
            Text(localizer.text(inputError ? "offset.invalid" : "offset.hint"))
                .font(.caption2).foregroundStyle(inputError ? .red : .secondary)
        }
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
