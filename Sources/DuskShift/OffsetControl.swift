import SwiftUI
import DuskShiftCore

struct OffsetControl: View {
    let title: String
    let leftLabel: String
    let rightLabel: String
    @Binding var minutes: Int
    @State private var draft = 0
    @State private var text = "0"
    @State private var inputError = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(title)偏移").font(.headline)
                Spacer()
                Text(draft == 0 ? "准时切换" : "\(draft < 0 ? "提前" : "延后") \(abs(draft)) 分钟")
                    .font(.caption).foregroundStyle(.secondary)
                Button("归零") { updateDraft(0); commit() }.font(.caption)
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
                    .accessibilityLabel("\(title)偏移，左侧\(leftLabel)，右侧\(rightLabel)")
                    .accessibilityValue(draft == 0 ? "准时" : "\(draft < 0 ? "提前" : "延后")\(abs(draft))分钟")
                }
                TextField("分钟", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 62)
                    .focused($inputFocused)
                    .onSubmit { commitText() }
                    .onChange(of: inputFocused) { focused in if !focused { commitText() } }
                    .accessibilityLabel("\(title)偏移分钟，负数提前，正数延后")
                Text("分").font(.caption)
            }
            HStack {
                Text(leftLabel)
                Spacer()
                Text("0")
                Spacer()
                Text(rightLabel)
            }.font(.caption).foregroundStyle(.secondary).padding(.trailing, 88)
            Text(inputError ? "请输入 −120～+120 的整数分钟。" : "负数提前，正数延后；松开滑块或输入回车后生效。")
                .font(.caption2).foregroundStyle(inputError ? .red : .secondary)
        }
        .onAppear { updateDraft(minutes) }
        .onChange(of: minutes) { updateDraft($0) }
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
