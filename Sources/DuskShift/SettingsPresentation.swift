import Combine
import Foundation
import DuskShiftCore

/// A section publishes only when its displayed values change. Background
/// appearance verification must not invalidate every control in the window.
@MainActor
final class SettingsSection<Value: Equatable>: ObservableObject {
    @Published private(set) var value: Value
    init(_ value: Value) { self.value = value }
    func update(_ value: Value) {
        if self.value != value { self.value = value }
    }
}

struct SettingsLocale: Equatable {
    let selection: AppLanguage
    let resolved: AppLanguage
}

struct AppearanceSettings: Equatable {
    let mode: AppearanceMode?
    let status: String
    let error: String?
}

struct LocationSettings: Equatable {
    let mode: LocationMode
    let cityID: String
    let timeZoneID: String
    let status: String?
    let isLocating: Bool
    let failed: Bool
}

struct SwitchTimeSettings: Equatable {
    let title: String
    let lightTime: String
    let darkTime: String
    let sunriseHelp: String
    let sunsetHelp: String
    let polarNotice: String?
    let clipped: Bool
}

struct LoginSettings: Equatable {
    let status: LoginItemStatus
    let error: String?
}

@MainActor
final class SettingsPresentation: ObservableObject {
    @Published private(set) var locale: SettingsLocale
    let appearance: SettingsSection<AppearanceSettings>
    let location: SettingsSection<LocationSettings>
    let sunrise: SettingsSection<Int>
    let sunset: SettingsSection<Int>
    let times: SettingsSection<SwitchTimeSettings>
    let login: SettingsSection<LoginSettings>
    var localizer: Localizer { model.localizer }

    private let model: AppModel
    private var subscription: AnyCancellable?
    private var updatePending = false

    init(model: AppModel) {
        self.model = model
        let values = Snapshot(model)
        locale = values.locale
        appearance = SettingsSection(values.appearance)
        location = SettingsSection(values.location)
        sunrise = SettingsSection(model.sunriseOffset)
        sunset = SettingsSection(model.offset)
        times = SettingsSection(values.times)
        login = SettingsSection(values.login)
        subscription = model.objectWillChange.sink { [weak self] _ in
            guard let self, !self.updatePending else { return }
            self.updatePending = true
            // @Published announces before mutation. Coalesce each burst and
            // read the completed state on the next run-loop turn, including
            // AppKit tracking/modal loops where main-queue work can be delayed.
            RunLoop.main.perform(inModes: [.common]) { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    private func refresh() {
        updatePending = false
        let values = Snapshot(model)
        appearance.update(values.appearance)
        location.update(values.location)
        sunrise.update(model.sunriseOffset)
        sunset.update(model.offset)
        times.update(values.times)
        login.update(values.login)
        if locale != values.locale { locale = values.locale }
    }

    @MainActor
    private struct Snapshot {
        let locale: SettingsLocale
        let appearance: AppearanceSettings
        let location: LocationSettings
        let times: SwitchTimeSettings
        let login: LoginSettings

        init(_ model: AppModel) {
            locale = SettingsLocale(selection: model.language, resolved: model.localizer.language)
            appearance = AppearanceSettings(mode: model.appearanceMode, status: model.settingsStatus, error: model.errorMessage)
            location = LocationSettings(mode: model.locationMode, cityID: model.cityID,
                timeZoneID: model.city.timeZoneID,
                status: model.locationMode == .automatic ? model.locationStatus : nil,
                isLocating: model.isLocating, failed: model.locationFailure != nil)
            let schedule = model.schedule
            times = SwitchTimeSettings(title: model.t("today.city", model.cityName()),
                lightTime: schedule?.today.sunrise == nil ? model.t("no.sunrise") : schedule?.todayLightTime.map { model.time($0) } ?? model.t("skipped"),
                darkTime: schedule?.today.sunset == nil ? model.t("no.sunset") : schedule?.todayDarkTime.map { model.time($0) } ?? model.t("skipped"),
                sunriseHelp: model.t("sunrise") + ": " + model.time(schedule?.today.sunrise),
                sunsetHelp: model.t("sunset") + ": " + model.time(schedule?.today.sunset),
                polarNotice: schedule?.today.condition == .polarDay ? model.t("polar.day")
                    : schedule?.today.condition == .polarNight ? model.t("polar.night") : nil,
                clipped: schedule?.offsetWasClipped ?? false)
            login = LoginSettings(status: model.loginItemStatus, error: model.loginItemError)
        }
    }
}
