import SwiftUI

@MainActor
struct UpdateSettingsView: View {
    @ObservedObject var updater: UpdateController
    let localizer: Localizer

    var body: some View {
        HStack(spacing: 10) {
            Text(status).font(.caption).foregroundStyle(isFailure ? Color.orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("update-status")
            Spacer(minLength: 4)
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
        }.controlSize(.small)
    }

    private var isFailure: Bool { if case .failed = updater.state { return true }; return false }
    private var isAvailable: Bool { if case .available = updater.state { return true }; return false }
    private var status: String {
        switch updater.state {
        case .idle: return localizer.text("update.automatic")
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
