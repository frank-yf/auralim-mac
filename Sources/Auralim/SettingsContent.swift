import SwiftUI
import AuralimCore

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
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                DuskMark(size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.t("app.name")).accessibilityIdentifier("settings-app-name").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text(model.t("slogan")).accessibilityIdentifier("app-slogan").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    appearance
                    times
                    location
                    offset(sunrise: true)
                    offset(sunrise: false)
                }
                .padding(.horizontal, 24).padding(.bottom, 18).padding(.top, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .frame(width: SettingsPanelLayout.width, height: height)
        .background(DuskStyle.background)
        .environment(\.locale, state.localizer.locale)
        .onAppear { model.refreshLoginItemStatus(); model.reconcile() }
    }

    private var appearance: some View {
        SettingsSectionView(section: state.appearance) { value in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    DuskSymbol(name: "circle.lefthalf.filled")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.t("appearance.mode")).font(.system(size: 13, weight: .semibold))
                        Text(value.status).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    AppearanceModePicker(selection: Binding(get: { model.appearanceMode }, set: { model.selectAppearanceMode($0) }),
                                         localizer: state.localizer, identifier: "settings-appearance-mode")
                        .frame(width: 210, alignment: .trailing)
                }
                Toggle(model.t("transition.enabled"), isOn: Binding(get: { model.transitionAnimationEnabled }, set: { model.transitionAnimationEnabled = $0 }))
                    .toggleStyle(.switch).controlSize(.small).font(.caption)
                    .accessibilityIdentifier("appearance-animation")
                if let error = value.error {
                    HStack(alignment: .top, spacing: 12) {
                        DuskNotice(text: error, warning: true)
                        Spacer(minLength: 0)
                        Button(model.t("appearance.retry")) { model.retry() }
                            .accessibilityIdentifier("retry-appearance")
                    }
                }
            }.duskCard()
        }
    }

    private var location: some View {
        SettingsSectionView(section: state.location) { value in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    DuskSymbol(name: "location")
                    Text(model.t("location.mode")).font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 8)
                    Picker(model.t("location.mode"), selection: Binding(get: { model.locationMode }, set: { model.locationMode = $0 })) {
                        Text(model.t("location.manual")).tag(LocationMode.manual)
                        Text(model.t("location.automatic")).tag(LocationMode.automatic)
                    }.pickerStyle(.segmented).labelsHidden()
                        .frame(width: 240).accessibilityIdentifier("location-mode")
                }
                HStack(alignment: .center, spacing: 16) {
                    Picker(model.t(value.mode == .automatic ? "location.fallbackCity" : "city.picker"),
                           selection: Binding(get: { model.cityID }, set: { model.cityID = $0 })) {
                        ForEach(City.all) { Text(model.cityName($0)).tag($0.id) }
                    }.frame(maxWidth: 260).accessibilityIdentifier("city-picker")
                    Spacer(minLength: 0)
                    Text(value.timeZoneID).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .help(model.t("city.timeZone", value.timeZoneID))
                }
                if let status = value.status {
                    HStack(alignment: .top, spacing: 12) {
                        DuskNotice(text: status, warning: value.failed)
                            .accessibilityIdentifier("location-status")
                        Spacer(minLength: 0)
                        Button(model.t("location.refresh")) { model.refreshLocation() }
                            .controlSize(.small).disabled(value.isLocating)
                    }
                }
            }.duskCard()
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
            VStack(alignment: .leading, spacing: 10) {
                Text(value.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    timeTile(label: model.t("sunrise.switch"), value: value.lightTime, symbol: "sunrise.fill", tint: DuskStyle.gold)
                        .accessibilityIdentifier("sunrise-switch-time").help(value.sunriseHelp)
                    timeTile(label: model.t("sunset.switch"), value: value.darkTime, symbol: "sunset.fill", tint: DuskStyle.blue)
                        .accessibilityIdentifier("sunset-switch-time").help(value.sunsetHelp)
                }
                if let notice = value.polarNotice { DuskNotice(text: notice) }
                if value.clipped { DuskNotice(text: model.t("clipped"), warning: true) }
            }
        }
    }

    private func timeTile(label: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
            Text(value).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity, alignment: .leading).duskCard()
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Divider()
            HStack(alignment: .top, spacing: 20) {
                login.frame(maxWidth: .infinity, alignment: .leading)
                Picker(model.t("language"), selection: Binding(get: { model.language }, set: { model.language = $0 })) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language == .system ? model.t("language.system") : language.nativeName).tag(language)
                    }
                }.accessibilityIdentifier("language-picker").frame(width: 235)
            }
            HStack {
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text("\(model.t("app.name")) \(version)").accessibilityIdentifier("app-version").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(model.t("licenses.open")) { openNotices() }
                    .buttonStyle(.link).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 24).padding(.bottom, 16)
    }

    private var login: some View {
        SettingsSectionView(section: state.login) { value in
            VStack(alignment: .leading, spacing: 6) {
                Toggle(model.t("login.title"), isOn: Binding(get: { model.loginItemStatus.isRegistered }, set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch).controlSize(.small)
                    .accessibilityIdentifier("launch-at-login")
                if value.status == .requiresApproval || value.status == .unknown {
                    DuskNotice(text: model.t(value.status.localizationKey))
                        .accessibilityIdentifier("login-item-status")
                }
                if let error = value.error { DuskNotice(text: error, warning: true) }
                if value.status == .requiresApproval || value.error != nil {
                    Button(model.t("login.settings")) { model.openLoginItemSettings() }.font(.caption)
                }
            }
        }
    }

    private func openNotices() {
        if let bundle = Bundle.main.url(forResource: "Auralim_AuralimCore", withExtension: "bundle"),
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
