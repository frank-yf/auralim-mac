import SwiftUI
import DuskShiftCore

struct SettingsContent: View {
    @ObservedObject var model: AppModel
    var height: CGFloat = 720

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dusk Shift").font(.title2.bold())
                Text("随日升日落，自在切换明暗。").foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.top, 20)
            TabView {
                general.tabItem { Label("自动切换", systemImage: "sun.max") }
                instructions.tabItem { Label("使用说明", systemImage: "info.circle") }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .frame(width: SettingsPanelLayout.width, height: height)
        .onAppear { model.reconcile() }
    }

    private var general: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Toggle("自动切换系统外观", isOn: $model.enabled).disabled(model.isApplying)
                VStack(alignment: .leading, spacing: 6) {
                    Picker("手动城市", selection: $model.cityID) {
                        ForEach(City.all) { Text($0.name).tag($0.id) }
                    }.disabled(model.isApplying)
                    Text("城市时区：\(model.city.timeZone.identifier)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                OffsetControl(title: "日出", leftLabel: "转暗 · 延后", rightLabel: "转亮 · 提前",
                              minutes: $model.sunriseOffset).disabled(model.isApplying)
                OffsetControl(title: "日落", leftLabel: "转亮 · 延后", rightLabel: "转暗 · 提前",
                              minutes: $model.offset).disabled(model.isApplying)
                Divider()
                if let state = model.schedule {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("今日时间 · \(model.city.name)").font(.headline)
                        LabeledContent("日出", value: model.time(state.today.sunrise))
                        LabeledContent("日出转亮", value: state.today.sunrise == nil ? "无日出" : state.todayLightTime.map { model.time($0) } ?? "本次已跳过")
                            .accessibilityIdentifier("sunrise-switch-time")
                        LabeledContent("日落", value: model.time(state.today.sunset))
                        LabeledContent("日落转暗", value: state.today.sunset == nil ? "无日落" : state.todayDarkTime.map { model.time($0) } ?? "本次已跳过")
                            .accessibilityIdentifier("sunset-switch-time")
                    }
                    if state.today.condition != .normal {
                        Text(state.today.condition == .polarDay ? "当地处于极昼" : "当地处于极夜")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if state.offsetWasClipped {
                        Text("近期昼夜间隔过短，偏移已按调整后的相邻切换时间裁剪。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.isApplying ? "正在检查系统外观…" : model.status)
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = model.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("重新检查权限并重试") { model.retry() }.disabled(model.isApplying)
                    } else {
                        Button("立即检查") { model.retry() }.disabled(model.isApplying)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var instructions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                help("开始使用", "先在 macOS 系统设置 → 外观中选择浅色或深色，关闭系统自带的自动外观。选择城市和偏移，再启用自动切换。首次使用请允许 Dusk Shift 控制 System Events。")
                help("日出与日落偏移", "日出和日落分别支持前后 120 分钟，精确到 1 分钟。滑块中点为准时；日出左侧延后转亮、右侧提前转亮，日落左侧延后转暗、右侧提前转暗。输入框负数提前、正数延后。有效输入立即预览，松开滑块、按回车或离开输入框后生效；归零可恢复准时切换。")
                help("城市、时区与离线使用", "所有时间按所选城市的时区显示，包含当地日期，并处理夏令时。日出日落在本机计算，无需网络或定位权限。旅行时请手动更换城市。本版本仅支持内置城市。")
                help("切换与休眠恢复", "日出转为浅色，日落转为深色。启动和从睡眠中唤醒时会检查并恢复当前应有外观。暂停或退出后保留最后的系统外观；应用退出期间不会切换，请保持应用运行。本版本尚未提供登录启动。")
                help("特殊日期与计算精度", "极昼默认保持浅色，极夜默认保持深色。偏移越过相邻切换边界时会裁剪或跳过对应时段，并在设置中提示。时间采用标准天文条件计算，山体遮挡、海拔和实际天气可能影响肉眼观察结果。")
                help("权限与隐私", "如果切换失败，请在系统设置 → 隐私与安全性 → 自动化中允许 Dusk Shift 控制 System Events，然后回到自动切换页重试。城市、偏移与启用状态保存在本机；本应用不上传这些信息。")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func help(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
}
