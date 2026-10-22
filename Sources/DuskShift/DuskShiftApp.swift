import SwiftUI
import AppKit
import DuskShiftCore

@main
struct DuskShiftApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var settings = SettingsWindowController()

    var body: some Scene {
        MenuBarExtra("Dusk Shift", systemImage: model.enabled ? "sun.max.circle.fill" : "sun.max.circle") {
            MenuContent(model: model, openSettings: { settings.show(model: model) })
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    var openSettings: () -> Void = {}
    var quit: () -> Void = { NSApplication.shared.terminate(nil) }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Dusk Shift").font(.headline)
                Spacer()
                Text(model.enabled ? model.t("auto") : model.t("paused"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle(model.t("auto.switch"), isOn: $model.enabled).disabled(model.isApplying)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.cityName() + " · " + (model.enabled ? model.t("next") : model.t("preview")))
                    .font(.caption).foregroundStyle(.secondary)
                if let next = model.schedule?.nextTransition {
                    Label("\(model.time(next.date)) · \(next.appearance == .dark ? model.t("dark") : model.t("light"))",
                          systemImage: next.appearance == .dark ? "moon.fill" : "sun.max.fill")
                } else {
                    Text(model.t("no.schedule")).font(.callout)
                }
            }
            Text(model.isApplying ? model.t("checking") : model.status)
                .font(.caption).foregroundStyle(model.errorMessage == nil ? Color.secondary : .orange)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Button(model.t("settings.open")) {
                    dismiss()
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityIdentifier("open-settings")
                Spacer()
                Button(model.t("quit"), action: quit)
            }
        }
        .padding(18)
        // Keep an explicit viewport: MenuBarExtra can propose a near-zero height.
        .frame(width: MenuPanelLayout.width, height: MenuPanelLayout.height)
        .environment(\.locale, model.localizer.locale)
        .onAppear { model.reconcile() }
    }
}

enum MenuPanelLayout {
    static let width: CGFloat = 320
    static let height: CGFloat = 240
}
