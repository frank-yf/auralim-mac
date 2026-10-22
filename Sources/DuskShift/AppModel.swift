import AppKit
import DuskShiftCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "language") } }
    @Published var cityID: String { didSet { defaults.set(cityID, forKey: "city"); configurationChanged() } }
    @Published var sunriseOffset: Int { didSet { if sunriseOffset != oldValue { defaults.set(sunriseOffset, forKey: "sunriseOffset"); offsetChanged() } } }
    @Published var offset: Int { didSet { if offset != oldValue { defaults.set(offset, forKey: "offset"); offsetChanged() } } }
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled"); configurationChanged() } }
    @Published var locationMode: LocationMode {
        didSet {
            guard locationMode != oldValue else { return }
            defaults.set(locationMode.rawValue, forKey: "locationMode")
            locatedCity = nil; locationFailure = nil; isLocating = false
            configurationChanged()
            if locationMode == .automatic { locationController.start() }
            else { locationController.stop() }
        }
    }
    @Published private(set) var locatedCity: City?
    @Published private(set) var isLocating = false
    @Published private(set) var locationFailure: LocationFailure?
    @Published private(set) var schedule: Schedule?
    private enum Status { case disabled, paused, confirmed(Appearance), attention }
    @Published private var statusState: Status = .disabled
    @Published private var failure: AppearanceFailure?
    var status: String {
        switch statusState {
        case .disabled: return t("status.disabled")
        case .paused: return t("status.paused")
        case .confirmed(let mode): return t("status.confirmed", t(mode == .dark ? "dark" : "light"))
        case .attention: return t("status.attention")
        }
    }
    var settingsStatus: String {
        if enabled {
            switch statusState {
            case .disabled, .paused: return t("checking")
            default: break
            }
        }
        return status
    }
    var errorMessage: String? {
        guard let failure else { return nil }
        switch failure.reason {
        case .custom: return failure.message
        case .authorization: return t("error.permission")
        case .script(let code): return t("error.script", code, failure.message.isEmpty ? t("error.unknown") : failure.message)
        case .verification: return t("error.verification")
        }
    }
    @Published private(set) var isApplying = false
    @Published private(set) var loginItemStatus: LoginItemStatus = .notRegistered
    @Published private var loginItemFailure: String?
    var loginItemError: String? { loginItemFailure.map { t("login.error", $0) } }

    private let defaults: UserDefaults
    private let controller: AppearanceApplying
    private let loginItemController: LoginItemControlling
    private let locationController: LocationProviding
    private let clock: () -> Date
    private let preferredLanguages: () -> [String]
    private let enableTimers: Bool
    private(set) var scheduledCheck: Date?
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var generation = 0
    private var failures = 0
    private var permissionBlocked = false
    var manualCity: City { City.all.first(where: { $0.id == cityID }) ?? City.all[0] }
    var city: City { locationMode == .automatic ? locatedCity ?? manualCity : manualCity }

    init(defaults: UserDefaults = .standard, controller: AppearanceApplying = AppearanceController(),
         clock: @escaping () -> Date = Date.init, enableTimers: Bool = true,
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
         systemNotifications: NotificationCenter = .default,
         preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages },
         loginItemController: LoginItemControlling? = nil,
         locationController: LocationProviding? = nil) {
        self.defaults = defaults; self.controller = controller; self.clock = clock; self.enableTimers = enableTimers
        self.loginItemController = loginItemController ?? LoginItemController()
        self.locationController = locationController ?? LocationController()
        self.preferredLanguages = preferredLanguages
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "system") ?? .system
        cityID = defaults.string(forKey: "city") ?? City.all[0].id
        offset = SolarOffset.clamp(defaults.integer(forKey: "offset"))
        sunriseOffset = SolarOffset.clamp(defaults.integer(forKey: "sunriseOffset"))
        enabled = defaults.bool(forKey: "enabled")
        locationMode = LocationMode(rawValue: defaults.string(forKey: "locationMode") ?? "manual") ?? .manual
        observe(NSWorkspace.didWakeNotification, center: workspaceNotifications, refreshLocation: true)
        observe(NSWorkspace.sessionDidBecomeActiveNotification, center: workspaceNotifications, refreshLocation: true)
        observe(.NSSystemClockDidChange, center: systemNotifications)
        observe(.NSSystemTimeZoneDidChange, center: systemNotifications, refreshLocation: true)
        let localeObserver = systemNotifications.addObserver(forName: NSLocale.currentLocaleDidChangeNotification,
                                                             object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.language == .system else { return }
                self.language = .system
            }
        }
        observers.append((systemNotifications, localeObserver))
        let activationObserver = systemNotifications.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshLoginItemStatus(); self?.refreshLocation() }
        }
        observers.append((systemNotifications, activationObserver))
        refreshLoginItemStatus()
        self.locationController.onEvent = { [weak self] event in self?.receiveLocation(event) }
        reconcile()
        if locationMode == .automatic { self.locationController.start() }
    }

    func refreshLocation() {
        guard locationMode == .automatic else { return }
        locationController.refresh()
    }

    private func receiveLocation(_ event: LocationEvent) {
        guard locationMode == .automatic else { return }
        let previous = city
        switch event {
        case .locating: isLocating = true; locationFailure = nil
        case .resolved(let city):
            locatedCity = city; isLocating = false; locationFailure = nil
        case .failed(let error):
            locatedCity = nil; isLocating = false; locationFailure = error
        }
        guard previous != city else { return }
        // Location events are automatic; they must not repeatedly request a
        // previously denied Automation permission.
        generation += 1; failures = 0
        reconcile()
    }

    var locationStatus: String {
        if let locationFailure { return t("location.fallback", t(locationFailure.localizationKey), cityName(manualCity)) }
        if isLocating { return t("location.locating") }
        if let locatedCity {
            let coordinates = String(format: "%.3f, %.3f", locale: localizer.locale,
                                     locatedCity.latitude, locatedCity.longitude)
            return t("location.using", coordinates)
        }
        return t("location.manual.hint")
    }

    func refreshLoginItemStatus() {
        let actual = loginItemController.status
        if actual != loginItemStatus { loginItemFailure = nil }
        loginItemStatus = actual
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        refreshLoginItemStatus()
        guard enabled != loginItemStatus.isRegistered else { return }
        loginItemFailure = nil
        do { try loginItemController.setEnabled(enabled) }
        catch { loginItemFailure = (error as NSError).localizedDescription }
        // Read the system state even on error: registration may be awaiting approval.
        loginItemStatus = loginItemController.status
    }

    func openLoginItemSettings() { loginItemController.openSystemSettings() }

    private func observe(_ name: Notification.Name, center: NotificationCenter, refreshLocation: Bool = false) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.reconcile()
                if refreshLocation { self?.refreshLocation() }
            }
        }
        observers.append((center, token))
    }

    private func configurationChanged() {
        generation += 1; failures = 0; permissionBlocked = false; failure = nil
        reconcile()
    }

    private func offsetChanged() {
        // Editing a schedule is not an explicit permission retry. Keep any
        // existing error visible instead of collapsing and re-adding its row.
        generation += 1; failures = 0
        reconcile()
    }

    func retry() { configurationChanged() }

    func reconcile() {
        timer?.invalidate(); timer = nil; scheduledCheck = nil
        let state = ScheduleEngine().evaluate(now: clock(), city: city, sunriseOffset: sunriseOffset, sunsetOffset: offset)
        schedule = state
        guard enabled else {
            statusState = .paused
            return
        }
        arm(at: state.nextCheck)
        guard !permissionBlocked, !isApplying else { return }
        isApplying = true
        let requestGeneration = generation
        controller.apply(state.appearance) { [weak self] result in
            guard let self else { return }
            self.isApplying = false
            guard self.enabled else { return }
            guard requestGeneration == self.generation else { self.reconcile(); return }
            // A request may span a clock change or solar boundary while waiting for consent.
            let fresh = ScheduleEngine().evaluate(now: self.clock(), city: self.city, sunriseOffset: self.sunriseOffset, sunsetOffset: self.offset)
            if fresh.appearance != state.appearance { self.reconcile(); return }
            self.schedule = fresh
            switch result {
            case .success:
                self.failures = 0; self.failure = nil
                self.statusState = .confirmed(state.appearance)
                self.arm(at: fresh.nextCheck)
            case .failure(let error):
                self.failure = error
                self.statusState = .attention
                self.permissionBlocked = error.permissionDenied
                self.failures += 1
                if !error.permissionDenied && self.failures <= 2 {
                    self.arm(at: min(fresh.nextCheck, self.clock().addingTimeInterval(Double(self.failures) * 5)))
                }
            }
        }
    }

    private func arm(at date: Date) {
        timer?.invalidate()
        scheduledCheck = max(date, clock().addingTimeInterval(0.1))
        guard enableTimers else { return }
        let next = Timer(fire: scheduledCheck!, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        next.tolerance = 0.5
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }

    func shutdown() {
        locationController.onEvent = nil
        locationController.stop()
        timer?.invalidate(); timer = nil; scheduledCheck = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    var localizer: Localizer { localizer(for: language) }
    func localizer(for language: AppLanguage) -> Localizer {
        Localizer(language: language, preferredLanguages: preferredLanguages())
    }
    func t(_ key: String, _ arguments: CVarArg...) -> String {
        localizer.text(key, arguments: arguments)
    }
    func cityName(_ city: City? = nil) -> String {
        let selected = city ?? self.city
        return selected.id == "current-location" ? t("location.current") : localizer.cityName(selected)
    }

    func time(_ date: Date?) -> String {
        guard let date else { return t("none") }
        let formatter = DateFormatter()
        formatter.locale = localizer.locale
        formatter.timeZone = city.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMdHHmm")
        return formatter.string(from: date)
    }
}
