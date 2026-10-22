import SwiftUI
import DuskShiftCore

struct SettingsContent: View {
    @ObservedObject var model: AppModel
    var height: CGFloat = 720

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dusk Shift").font(.title2.bold())
                Text(model.t("slogan")).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.top, 20)
            TabView {
                general.tabItem { Label(model.t("auto.switch"), systemImage: "sun.max") }
                instructions.tabItem { Label(model.t("tab.help"), systemImage: "info.circle") }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .frame(width: SettingsPanelLayout.width, height: height)
        .environment(\.locale, model.localizer.locale)
        .onAppear { model.refreshLoginItemStatus(); model.reconcile() }
    }

    private var general: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Picker(model.t("language"), selection: $model.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language == .system ? model.t("language.system") : language.nativeName).tag(language)
                        }
                    }.accessibilityIdentifier("language-picker")
                    Text(model.t("language.hint")).font(.caption).foregroundStyle(.secondary)
                }
                Toggle(model.t("auto.system"), isOn: $model.enabled).disabled(model.isApplying)
                VStack(alignment: .leading, spacing: 6) {
                    Picker(model.t("location.mode"), selection: $model.locationMode) {
                        Text(model.t("location.manual")).tag(LocationMode.manual)
                        Text(model.t("location.automatic")).tag(LocationMode.automatic)
                    }.pickerStyle(.segmented).accessibilityIdentifier("location-mode")
                    Picker(model.t(model.locationMode == .automatic ? "location.fallbackCity" : "city.picker"), selection: $model.cityID) {
                        ForEach(City.all) { Text(model.cityName($0)).tag($0.id) }
                    }.disabled(model.isApplying)
                    Text(model.t("city.timeZone", model.city.timeZone.identifier))
                        .font(.caption).foregroundStyle(.secondary)
                    if model.locationMode == .automatic {
                        Text(model.locationStatus).font(.caption)
                            .foregroundStyle(model.locationFailure == nil ? Color.secondary : .orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("location-status")
                        Button(model.t("location.refresh")) { model.refreshLocation() }.disabled(model.isLocating)
                    }
                }
                OffsetControl(title: model.t("sunrise"), leftLabel: model.t("sunrise.left"), rightLabel: model.t("sunrise.right"),
                              minutes: $model.sunriseOffset, localizer: model.localizer, identifier: "sunrise").disabled(model.isApplying)
                OffsetControl(title: model.t("sunset"), leftLabel: model.t("sunset.left"), rightLabel: model.t("sunset.right"),
                              minutes: $model.offset, localizer: model.localizer, identifier: "sunset").disabled(model.isApplying)
                Divider()
                if let state = model.schedule {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.t("today.city", model.cityName())).font(.headline)
                        LabeledContent(model.t("sunrise"), value: model.time(state.today.sunrise))
                        LabeledContent(model.t("sunrise.switch"), value: state.today.sunrise == nil ? model.t("no.sunrise") : state.todayLightTime.map { model.time($0) } ?? model.t("skipped"))
                            .accessibilityIdentifier("sunrise-switch-time")
                        LabeledContent(model.t("sunset"), value: model.time(state.today.sunset))
                        LabeledContent(model.t("sunset.switch"), value: state.today.sunset == nil ? model.t("no.sunset") : state.todayDarkTime.map { model.time($0) } ?? model.t("skipped"))
                            .accessibilityIdentifier("sunset-switch-time")
                    }
                    if state.today.condition != .normal {
                        Text(state.today.condition == .polarDay ? model.t("polar.day") : model.t("polar.night"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if state.offsetWasClipped {
                        Text(model.t("clipped"))
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.isApplying ? model.t("checking") : model.status)
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = model.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(model.t("retry")) { model.retry() }.disabled(model.isApplying)
                    } else {
                        Button(model.t("check.now")) { model.retry() }.disabled(model.isApplying)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(model.t("login.title"), isOn: Binding(
                        get: { model.loginItemStatus.isRegistered },
                        set: { model.setLaunchAtLogin($0) }
                    )).accessibilityIdentifier("launch-at-login")
                    Text(model.t("login.hint")).font(.caption).foregroundStyle(.secondary)
                    Text(model.t(model.loginItemStatus.localizationKey))
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("login-item-status")
                    if let error = model.loginItemError {
                        Text(error).font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.loginItemStatus == .requiresApproval || model.loginItemError != nil {
                        Button(model.t("login.settings")) { model.openLoginItemSettings() }
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
                help(model.t("help.start.title"), model.t("help.start.body"))
                help(model.t("help.offset.title"), model.t("help.offset.body"))
                help(model.t("help.city.title"), model.t("help.city.body"))
                help(model.t("help.location.title"), model.t("help.location.body"))
                help(model.t("help.sleep.title"), model.t("help.sleep.body"))
                help(model.t("help.login.title"), model.t("help.login.body"))
                help(model.t("help.polar.title"), model.t("help.polar.body"))
                help(model.t("help.privacy.title"), model.t("help.privacy.body"))
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
