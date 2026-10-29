import SwiftUI
import AuralimCore

/// Independent presenters finish before any optional appearance request.
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
        animation.play(target, title: localizer.text(target == .light ? "transition.sunrise" : "transition.sunset")) { [weak self] in
            guard let self, self.token == id else { return }
            self.finishPreview(target, id: id, completion: completion)
        }
    }

    private func finishPreview(_ target: Appearance, id: UUID, completion: @MainActor (Appearance) -> Void) {
        guard token == id else { return }
        let apply = applyAppearanceAfterPreview
        stop() // Release both presenters before calling the app model.
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
            Toggle(model.t("debug.enabled"), isOn: $preview.enabled)
                .toggleStyle(.switch).controlSize(.small).font(.caption)
                .accessibilityIdentifier("debug-enabled")
            if preview.enabled {
                Text(model.t(preview.applyAppearanceAfterPreview ? "debug.applyHint" : "debug.hint")).font(.caption).foregroundStyle(.secondary)
                Toggle(model.t("debug.apply"), isOn: $preview.applyAppearanceAfterPreview)
                    .toggleStyle(.switch).controlSize(.small).font(.caption)
                    .accessibilityIdentifier("debug-apply-appearance")
                Picker(model.t("debug.target"), selection: $target) {
                    Text(model.t("transition.sunrise")).tag(Appearance.light)
                    Text(model.t("transition.sunset")).tag(Appearance.dark)
                }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("debug-target")
                HStack {
                    Button(model.t("debug.countdown")) { model.previewDebug(.countdown, target: target) }
                        .accessibilityIdentifier("debug-countdown")
                    Button(model.t("debug.animation")) { model.previewDebug(.animation, target: target) }
                        .accessibilityIdentifier("debug-animation")
                    Button(model.t("debug.sequence")) { model.previewDebug(.sequence, target: target) }
                        .accessibilityIdentifier("debug-sequence")
                    Spacer(minLength: 0)
                    Button(model.t("debug.stop")) { preview.stop() }
                        .disabled(preview.phase == .idle).accessibilityIdentifier("debug-stop")
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
}
