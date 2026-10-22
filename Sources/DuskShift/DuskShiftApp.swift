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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                DuskMark(size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dusk Shift").font(.system(size: 15, weight: .semibold))
                    Text(model.enabled ? model.t("auto") : model.t("paused"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(model.t("auto.switch"), isOn: $model.enabled)
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    .accessibilityIdentifier("menu-auto-switch")
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(model.cityName()).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(model.t(model.enabled ? "next" : "preview"))
                }.font(.caption).foregroundStyle(.secondary)
                if let next = model.schedule?.nextTransition {
                    HStack(spacing: 10) {
                        DuskSymbol(name: next.appearance == .dark ? "moon.fill" : "sun.max.fill",
                                   tint: next.appearance == .dark ? DuskStyle.blue : DuskStyle.gold)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.time(next.date))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                            Text(model.t(next.appearance == .dark ? "dark" : "light"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    Label(model.t("no.schedule"), systemImage: "sun.horizon")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }.duskCard(padding: 12)
            Label(model.settingsStatus, systemImage: model.errorMessage != nil ? "exclamationmark.circle" : model.enabled ? "checkmark.circle" : "pause.circle")
                .font(.caption).foregroundStyle(model.errorMessage == nil ? Color.secondary : .orange)
                .lineLimit(2).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .help(model.errorMessage ?? model.settingsStatus)
            Divider()
            HStack {
                Button {
                    dismiss()
                    openSettings()
                } label: {
                    Label(model.t("settings.open"), systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityIdentifier("open-settings")
                Spacer()
                Button(action: quit) { Label(model.t("quit"), systemImage: "power") }
            }.buttonStyle(.borderless).controlSize(.small)
        }
        .padding(16)
        // Keep an explicit viewport: MenuBarExtra can propose a near-zero height.
        .frame(width: MenuPanelLayout.width, height: MenuPanelLayout.height)
        .background(DuskStyle.background)
        .environment(\.locale, model.localizer.locale)
        .onAppear { model.reconcile() }
    }
}

enum MenuPanelLayout {
    static let width: CGFloat = 320
    static let height: CGFloat = 264
}
