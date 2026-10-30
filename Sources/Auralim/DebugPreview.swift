import SwiftUI
import AuralimCore

/// Independent previews switch at motion end and keep the final frame visible.
@MainActor
final class DebugPreviewController: ObservableObject {
    enum Action { case countdown, animation, sequence }
    enum Phase: Equatable { case idle, countdown(Appearance), animation(Appearance) }
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "debugModeEnabled")
            if !enabled { applyAppearanceAfterPreview = false; stop() }
        }
    }
    @Published var applyAppearanceAfterPreview = false
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remaining: Int?
    private let defaults: UserDefaults
    private let countdown: CountdownPresenting
    private let animation: AppearanceTransitionPlaying
    private var token: UUID?

    init(defaults: UserDefaults, countdown: CountdownPresenting? = nil,
         animation: AppearanceTransitionPlaying? = nil) {
        self.defaults = defaults
        self.countdown = countdown ?? CountdownController(preview: true)
        self.animation = animation ?? AppearanceTransitionController()
        enabled = BuildFeatures.debugToolsEnabled && defaults.bool(forKey: "debugModeEnabled")
    }

    func preview(_ action: Action, target: Appearance, seconds: Int, localizer: Localizer,
                 completion: @escaping @MainActor (Appearance) -> Void = { _ in }) {
        guard BuildFeatures.debugToolsEnabled, enabled else { return }
        stop()
        let id = UUID(); token = id
        if action == .animation { playAnimation(target, localizer: localizer, id: id, completion: completion); return }
        let seconds = min(120, max(1, seconds))
        phase = .countdown(target); remaining = seconds
        countdown.start(seconds: seconds, target: target, localizer: localizer,
            tick: { [weak self] value in
                guard let self, self.token == id else { return }
                self.remaining = value
            }, finish: { [weak self] in
                guard let self, self.token == id else { return }
                self.countdown.stop(); self.remaining = nil
                if action == .sequence { self.playAnimation(target, localizer: localizer, id: id, completion: completion) }
                else { self.finishPreview(target, id: id, completion: completion) }
            }, cancel: { [weak self] in
                guard let self, self.token == id else { return }
                self.stop()
            })
    }

    private func playAnimation(_ target: Appearance, localizer: Localizer, id: UUID, completion: @escaping @MainActor (Appearance) -> Void) {
        phase = .animation(target)
        animation.play(target, title: localizer.text(target == .light ? "transition.sunrise" : "transition.sunset"), onAnimationEnd: { [weak self] in
            guard let self, self.token == id else { return }
            if self.applyAppearanceAfterPreview { completion(target) }
        }, completion: { [weak self] in
            guard let self, self.token == id else { return }
            self.finishPreview(target, id: id, applyAppearance: false, completion: completion)
        })
    }

    private func finishPreview(_ target: Appearance, id: UUID, applyAppearance: Bool = true, completion: @MainActor (Appearance) -> Void) {
        guard token == id else { return }
        let apply = applyAppearance && applyAppearanceAfterPreview
        stop() // Release the completed preview; countdown-only requests apply below.
        if apply { completion(target) }
    }

    func stop() {
        token = nil
        countdown.stop(); animation.stop()
        remaining = nil; phase = .idle
    }
}

@MainActor
struct DebugSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preview: DebugPreviewController
    @State private var target: Appearance = .light

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsPreferenceRow(title: model.t("debug.enabled")) {
                Toggle(model.t("debug.enabled"), isOn: $preview.enabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityIdentifier("debug-enabled")
            }
            if preview.enabled {
                Divider()
                SettingsPreferenceRow(title: model.t("debug.apply")) {
                    Toggle(model.t("debug.apply"), isOn: $preview.applyAppearanceAfterPreview)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .accessibilityIdentifier("debug-apply-appearance")
                }
                Text(model.t(preview.applyAppearanceAfterPreview ? "debug.applyHint" : "debug.hint"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                SettingsPreferenceRow(title: model.t("debug.target")) {
                    Picker(model.t("debug.target"), selection: $target) {
                        Text(model.t("transition.sunrise")).tag(Appearance.light)
                        Text(model.t("transition.sunset")).tag(Appearance.dark)
                    }.pickerStyle(.segmented).labelsHidden().controlSize(.small)
                        .accessibilityIdentifier("debug-target")
                }
                Divider()
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    previewButton("debug.countdown", identifier: "debug-countdown") { model.previewDebug(.countdown, target: target) }
                    previewButton("debug.animation", identifier: "debug-animation") { model.previewDebug(.animation, target: target) }
                    previewButton("debug.sequence", identifier: "debug-sequence") { model.previewDebug(.sequence, target: target) }
                    previewButton("debug.stop", identifier: "debug-stop") { preview.stop() }
                        .disabled(preview.phase == .idle)
                }.controlSize(.small).disabled(!model.canPreviewDebug)
                if case .countdown(let target) = preview.phase, let remaining = preview.remaining {
                    Text(model.t("debug.remaining", model.t(target == .light ? "light" : "dark"), remaining))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                } else if case .animation(let target) = preview.phase {
                    Text(model.t(target == .light ? "transition.sunrise" : "transition.sunset"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.duskCard()
    }
    private func previewButton(_ key: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(model.t(key)).frame(maxWidth: .infinity, minHeight: 22)
        }.buttonStyle(.bordered).accessibilityIdentifier(identifier)
    }

}
