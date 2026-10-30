import SwiftUI
import AuralimCore

@MainActor
struct SettingsContent: View {
    let model: AppModel
    var height: CGFloat
    let updater: UpdateController?
    @StateObject private var state: SettingsPresentation

    init(model: AppModel, height: CGFloat = 640, updater: UpdateController? = nil) {
        self.model = model
        self.height = height
        self.updater = updater
        _state = StateObject(wrappedValue: SettingsPresentation(model: model))
    }

    var body: some View {
        VStack(spacing: 0) {
            brand.padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    appearance
                    location
                    offset(sunrise: true)
                    offset(sunrise: false)
                    SettingsSectionView(section: state.times) { value in
                        if let notice = value.polarNotice { DuskNotice(text: notice) }
                        if value.clipped { DuskNotice(text: model.t("clipped"), warning: true) }
                    }
                    #if AURALIM_DEBUG_TOOLS
                    DebugSettingsView(model: model, preview: model.debugPreview)
                    #endif
                    preferences
                }
                .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .frame(width: SettingsPanelLayout.width, height: height)
        .background(DuskStyle.background)
        .environment(\.locale, state.localizer.locale)
        .onAppear { model.refreshLoginItemStatus(); model.reconcile() }
    }

    private var brand: some View {
        HStack(spacing: 12) {
            DuskMark(size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.t("app.name")).accessibilityIdentifier("settings-app-name")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text(model.t("slogan")).accessibilityIdentifier("app-slogan")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 4)
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
                        .frame(width: DuskLayout.controlWidth, alignment: .trailing)
                }
                Divider()
                VStack(spacing: 6) {
                    SettingsPreferenceRow(title: model.t("transition.enabled")) {
                        Toggle(model.t("transition.enabled"), isOn: Binding(get: { model.transitionAnimationEnabled }, set: { model.transitionAnimationEnabled = $0 }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                            .accessibilityIdentifier("appearance-animation")
                    }
                    SettingsPreferenceRow(title: model.t("countdown.enabled")) {
                        HStack(spacing: 12) {
                            Group {
                                if value.countdownEnabled {
                                    HStack(spacing: 6) {
                                        TextField("", value: Binding(get: { model.countdownSeconds }, set: { model.countdownSeconds = $0 }), format: .number.precision(.fractionLength(0)).grouping(.never))
                                            .textFieldStyle(.roundedBorder).frame(width: 48)
                                            .accessibilityLabel(model.t("countdown.seconds"))
                                            .accessibilityIdentifier("countdown-seconds")
                                        Stepper("", value: Binding(get: { model.countdownSeconds }, set: { model.countdownSeconds = $0 }), in: 1...120)
                                            .labelsHidden().accessibilityLabel(model.t("countdown.seconds"))
                                        Text(model.t("countdown.seconds")).font(.caption).foregroundStyle(.secondary)
                                    }
                                } else { Color.clear }
                            }.frame(width: 106, height: 28)
                            Toggle(model.t("countdown.enabled"), isOn: Binding(get: { model.countdownEnabled }, set: { model.countdownEnabled = $0 }))
                                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                                .accessibilityIdentifier("countdown-enabled")
                        }
                    }
                }
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    DuskSymbol(name: "location")
                    Text(model.t("location.mode")).font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 8)
                    Picker(model.t("location.mode"), selection: Binding(get: { model.locationMode }, set: { model.locationMode = $0 })) {
                        Text(model.t("location.manual")).tag(LocationMode.manual)
                        Text(model.t("location.automatic")).tag(LocationMode.automatic)
                    }.pickerStyle(.segmented).labelsHidden()
                        .frame(width: DuskLayout.controlWidth, alignment: .trailing).accessibilityIdentifier("location-mode")
                }
                SettingsPreferenceRow(title: model.t(value.mode == .automatic ? "location.fallbackCity" : "city.picker")) {
                    Picker(model.t(value.mode == .automatic ? "location.fallbackCity" : "city.picker"),
                           selection: Binding(get: { model.cityID }, set: { model.cityID = $0 })) {
                        ForEach(City.all) { Text(model.cityName($0)).tag($0.id) }
                    }.labelsHidden().controlSize(.small)
                        .frame(width: DuskLayout.controlWidth, alignment: .trailing).accessibilityIdentifier("city-picker")
                }
                Divider()
                HStack(spacing: 16) {
                    Label(value.timeZoneID, systemImage: "globe")
                        .font(.caption2).lineLimit(1).truncationMode(.middle)
                        .help(model.t("city.timeZone", value.timeZoneID))
                    Spacer(minLength: 4)
                    HStack(spacing: 16) {
                        Label {
                            Text("\(model.t("sunrise")) \(value.sunriseTime)").monospacedDigit()
                        } icon: {
                            Image(systemName: "sunrise.fill").foregroundStyle(DuskStyle.gold)
                        }
                        Label {
                            Text("\(model.t("sunset")) \(value.sunsetTime)").monospacedDigit()
                        } icon: {
                            Image(systemName: "sunset.fill").foregroundStyle(DuskStyle.blue)
                        }
                    }.font(.caption).fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("location-solar-times")
                }.foregroundStyle(.secondary)
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

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 12) {
            login
            Divider()
            SettingsPreferenceRow(title: model.t("language")) {
                Picker(model.t("language"), selection: Binding(get: { model.language }, set: { model.language = $0 })) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language == .system ? model.t("language.system") : language.nativeName).tag(language)
                    }
                }.labelsHidden().controlSize(.small).accessibilityIdentifier("language-picker")
            }
            if let updater {
                Divider()
                UpdateSettingsView(updater: updater, localizer: state.localizer)
            }
        }.duskCard().accessibilityIdentifier("settings-preferences")
    }

    private var footer: some View {
        HStack {
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("v\(version)").accessibilityIdentifier("app-version").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(model.t("licenses.open")) { openNotices() }
                .buttonStyle(.link).font(.caption2).foregroundStyle(.secondary)
        }.padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 12)
    }

    private var login: some View {
        SettingsSectionView(section: state.login) { value in
            VStack(alignment: .leading, spacing: 6) {
                SettingsPreferenceRow(title: model.t("login.title")) {
                    Toggle(model.t("login.title"), isOn: Binding(get: { model.loginItemStatus.isRegistered }, set: { model.setLaunchAtLogin($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .accessibilityIdentifier("launch-at-login")
                }
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
        if let notice = Localizer.resourceBundle.url(forResource: "ThirdPartyNotices", withExtension: "txt") {
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

/// A shared label and trailing control column for general preferences.
struct SettingsPreferenceRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 16) {
            Text(title).font(DuskLayout.rowFont).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            control.frame(width: DuskLayout.controlWidth, alignment: .trailing)
        }.frame(minHeight: DuskLayout.rowHeight).font(DuskLayout.rowFont)
    }
}
