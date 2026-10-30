import SwiftUI

@MainActor
struct UpdateSettingsView: View {
    @ObservedObject var updater: UpdateController
    let localizer: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsPreferenceRow(title: localizer.text("update.mode")) {
                Picker(localizer.text("update.mode"), selection: Binding(get: { updater.mode }, set: { updater.selectMode($0) })) {
                    Text(localizer.text("update.mode.manual")).tag(UpdateController.Mode.manual)
                    Text(localizer.text("update.mode.automatic")).tag(UpdateController.Mode.automatic)
                }.pickerStyle(.segmented).labelsHidden()
                    .accessibilityIdentifier("update-mode")
            }
            HStack(spacing: 10) {
                Text(status).font(.caption).foregroundStyle(isFailure ? Color.orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("update-status")
                if case .ready = updater.state {
                    Button(localizer.text("update.restart")) { updater.restartToUpdate() }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("restart-to-update")
                } else {
                    if isFailure || isAvailable {
                        Button(localizer.text("update.releases")) { updater.openReleases() }
                            .accessibilityIdentifier("update-releases")
                    }
                    Button(localizer.text(isFailure ? "update.retry" : "update.check")) { updater.checkForUpdates() }
                        .disabled(!updater.canCheck).accessibilityIdentifier("check-for-updates")
                }
            }
        }.controlSize(.small)
    }

    private var isFailure: Bool { if case .failed = updater.state { return true }; return false }
    private var isAvailable: Bool { if case .available = updater.state { return true }; return false }
    private var status: String {
        switch updater.state {
        case .idle: return localizer.text(updater.mode == .automatic ? "update.automatic" : "update.manual")
        case .checking: return localizer.text("update.checking")
        case .downloading: return localizer.text("update.downloading")
        case .preparing: return localizer.text("update.preparing")
        case .upToDate: return localizer.text("update.current")
        case .ready(let version): return localizer.text("update.ready", version)
        case .installing: return localizer.text("update.installing")
        case .available(let version): return localizer.text("update.available", version)
        case .failed(let failure): return localizer.text("update.error." + failure.rawValue)
        }
    }
}
