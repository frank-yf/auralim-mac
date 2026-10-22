import SwiftUI
import AppKit
import DuskShiftCore

@main
struct DuskShiftApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        MenuBarExtra("Dusk Shift", systemImage: model.enabled ? "sun.max.circle.fill" : "sun.max.circle") {
            MenuContent(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuContent: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dusk Shift").font(.title2.bold())
                Text("随日升日落，自在切换明暗。").foregroundStyle(.secondary)
            }
            Toggle("自动切换系统外观", isOn: $model.enabled)
                .disabled(model.isApplying)
            Picker("手动城市", selection: $model.cityID) {
                ForEach(City.all) { Text($0.name).tag($0.id) }
            }.disabled(model.isApplying)
            Text("城市时区：\(model.city.timeZone.identifier)").font(.caption).foregroundStyle(.secondary)
            Stepper(value: $model.offset, in: -120...120) {
                Text("日落偏移：\(model.offset > 0 ? "+" : "")\(model.offset) 分钟")
            }.disabled(model.isApplying)
            HStack {
                Button("提前 30 分钟") { model.offset = max(-120, model.offset - 30) }
                Button("归零") { model.offset = 0 }
                Button("延后 30 分钟") { model.offset = min(120, model.offset + 30) }
            }.font(.caption).disabled(model.isApplying)
            Divider()
            if let state = model.schedule {
                LabeledContent("日出", value: model.time(state.today.sunrise))
                LabeledContent("日落", value: model.time(state.today.sunset))
                if state.today.condition != .normal {
                    Text(state.today.condition == .polarDay ? "当地处于极昼" : "当地处于极夜")
                }
                if let next = state.nextTransition {
                    LabeledContent(model.enabled ? "下次切换" : "计划预览", value: "\(model.time(next.date)) · \(next.appearance == .dark ? "深色" : "浅色")")
                } else {
                    Text("近期无明暗切换，下一当地日期自动重算").font(.caption)
                }
                if state.offsetWasClipped {
                    Text("近期昼夜间隔过短，偏移已按相邻日出边界裁剪。").font(.caption).foregroundStyle(.orange)
                }
            }
            Text(model.isApplying ? "正在检查系统外观…" : model.status).font(.caption).foregroundStyle(.secondary)
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                Button("重新检查权限并重试") { model.retry() }.disabled(model.isApplying)
            }
            Text("请将 macOS 外观设为浅色或深色，关闭系统“自动”外观，以免两个计划相互覆盖。日出日落与城市选择均可离线使用。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Button("立即检查") { model.retry() }.disabled(model.isApplying)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(18)
        .frame(width: 370)
        .onAppear { model.reconcile() }
    }
}
