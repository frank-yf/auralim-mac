import SwiftUI
import DuskShiftCore

@MainActor
struct SettingsContent: View {
    let model: AppModel
    var height: CGFloat
    @StateObject private var state: SettingsPresentation

    init(model: AppModel, height: CGFloat = 720) {
        self.model = model
        self.height = height
        _state = StateObject(wrappedValue: SettingsPresentation(model: model))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dusk Shift").font(.title2.bold())
                Text(model.t("slogan")).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.top, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    appearance
                    Divider()
                    location
                    offset(sunrise: true)
                    offset(sunrise: false)
                    times
                    Divider()
                    login
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 16)
            HStack {
                Picker(model.t("language"), selection: Binding(get: { model.language }, set: { model.language = $0 })) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language == .system ? model.t("language.system") : language.nativeName).tag(language)
                    }
                }.accessibilityIdentifier("language-picker").frame(maxWidth: 270)
                Spacer()
                Button(model.t("licenses.open")) { openNotices() }
                    .buttonStyle(.link).font(.caption2)
            }.padding(.horizontal, 34).padding(.bottom, 20)
        }
        .frame(width: SettingsPanelLayout.width, height: height)
        .environment(\.locale, state.localizer.locale)
        .onAppear { model.refreshLoginItemStatus(); model.reconcile() }
    }

    private var appearance: some View {
        SettingsSectionView(section: state.appearance) { value in
            VStack(alignment: .leading, spacing: 8) {
                Toggle(model.t("auto.system"), isOn: Binding(get: { model.enabled }, set: { model.enabled = $0 }))
                HStack {
                    Text(value.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(model.t("check.now")) { model.retry() }.font(.caption)
                }
                if let error = value.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var location: some View {
        SettingsSectionView(section: state.location) { value in
            VStack(alignment: .leading, spacing: 6) {
                Picker(model.t("location.mode"), selection: Binding(get: { model.locationMode }, set: { model.locationMode = $0 })) {
                    Text(model.t("location.manual")).tag(LocationMode.manual)
                    Text(model.t("location.automatic")).tag(LocationMode.automatic)
                }.pickerStyle(.segmented).accessibilityIdentifier("location-mode")
                Picker(model.t(value.mode == .automatic ? "location.fallbackCity" : "city.picker"),
                       selection: Binding(get: { model.cityID }, set: { model.cityID = $0 })) {
                    ForEach(City.all) { Text(model.cityName($0)).tag($0.id) }
                }
                Text(model.t("city.timeZone", value.timeZoneID)).font(.caption).foregroundStyle(.secondary)
                if let status = value.status {
                    Text(status).font(.caption)
                        .foregroundStyle(value.failed ? Color.orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("location-status")
                    Button(model.t("location.refresh")) { model.refreshLocation() }.disabled(value.isLocating)
                }
            }
        }
    }

    private func offset(sunrise: Bool) -> some View {
        SettingsSectionView(section: sunrise ? state.sunrise : state.sunset) { _ in
            OffsetControl(title: model.t(sunrise ? "sunrise" : "sunset"),
                leftLabel: model.t(sunrise ? "sunrise.left" : "sunset.left"),
                rightLabel: model.t(sunrise ? "sunrise.right" : "sunset.right"),
                minutes: Binding(get: { sunrise ? model.sunriseOffset : model.offset }, set: {
                    if sunrise { model.sunriseOffset = $0 } else { model.offset = $0 }
                }), localizer: state.localizer, identifier: sunrise ? "sunrise" : "sunset", sunrise: sunrise)
        }
    }

    private var times: some View {
        SettingsSectionView(section: state.times) { value in
            VStack(alignment: .leading, spacing: 8) {
                Text(value.title).font(.headline)
                LabeledContent(model.t("sunrise.switch"), value: value.lightTime)
                    .accessibilityIdentifier("sunrise-switch-time").help(value.sunriseHelp)
                LabeledContent(model.t("sunset.switch"), value: value.darkTime)
                    .accessibilityIdentifier("sunset-switch-time").help(value.sunsetHelp)
                if let notice = value.polarNotice {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                }
                if value.clipped {
                    Text(model.t("clipped")).font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private var login: some View {
        SettingsSectionView(section: state.login) { value in
            VStack(alignment: .leading, spacing: 6) {
                Toggle(model.t("login.title"), isOn: Binding(get: { model.loginItemStatus.isRegistered }, set: { model.setLaunchAtLogin($0) }))
                    .accessibilityIdentifier("launch-at-login")
                if value.status != .notRegistered && value.status != .enabled {
                    Text(model.t(value.status.localizationKey)).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("login-item-status")
                }
                if let error = value.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if value.status == .requiresApproval || value.error != nil {
                    Button(model.t("login.settings")) { model.openLoginItemSettings() }
                }
            }
        }
    }

    private func openNotices() {
        if let bundle = Bundle.main.url(forResource: "DuskShift_DuskShiftCore", withExtension: "bundle"),
           let notice = Bundle(url: bundle)?.url(forResource: "TimezoneData-NOTICE", withExtension: "txt") {
            NSWorkspace.shared.open(notice)
        }
    }
}

@MainActor
private struct SettingsSectionView<Value: Equatable, Content: View>: View {
    @ObservedObject var section: SettingsSection<Value>
    @ViewBuilder let content: (Value) -> Content
    var body: some View { content(section.value) }
}
