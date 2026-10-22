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
                Text(model.enabled ? "自动" : "已暂停")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("自动切换", isOn: $model.enabled).disabled(model.isApplying)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.city.name + " · " + (model.enabled ? "下次切换" : "计划预览"))
                    .font(.caption).foregroundStyle(.secondary)
                if let next = model.schedule?.nextTransition {
                    Label("\(model.time(next.date)) · \(next.appearance == .dark ? "深色" : "浅色")",
                          systemImage: next.appearance == .dark ? "moon.fill" : "sun.max.fill")
                } else {
                    Text("近期无切换计划").font(.callout)
                }
            }
            Text(model.isApplying ? "正在检查系统外观…" : model.status)
                .font(.caption).foregroundStyle(model.errorMessage == nil ? Color.secondary : .orange)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Button("设置…") {
                    dismiss()
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityIdentifier("open-settings")
                Spacer()
                Button("退出", action: quit)
            }
        }
        .padding(18)
        // Keep an explicit viewport: MenuBarExtra can propose a near-zero height.
        .frame(width: MenuPanelLayout.width, height: MenuPanelLayout.height)
        .onAppear { model.reconcile() }
    }
}

enum MenuPanelLayout {
    static let width: CGFloat = 320
    static let height: CGFloat = 240
}
