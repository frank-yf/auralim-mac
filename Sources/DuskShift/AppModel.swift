import AppKit
import DuskShiftCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "language") } }
    @Published var cityID: String { didSet { defaults.set(cityID, forKey: "city"); configurationChanged() } }
    @Published var sunriseOffset: Int { didSet { defaults.set(sunriseOffset, forKey: "sunriseOffset"); configurationChanged() } }
    @Published var offset: Int { didSet { defaults.set(offset, forKey: "offset"); configurationChanged() } }
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled"); configurationChanged() } }
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

    private let defaults: UserDefaults
    private let controller: AppearanceApplying
    private let clock: () -> Date
    private let preferredLanguages: () -> [String]
    private let enableTimers: Bool
    private(set) var scheduledCheck: Date?
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var generation = 0
    private var failures = 0
    private var permissionBlocked = false
    var city: City { City.all.first(where: { $0.id == cityID }) ?? City.all[0] }

    init(defaults: UserDefaults = .standard, controller: AppearanceApplying = AppearanceController(),
         clock: @escaping () -> Date = Date.init, enableTimers: Bool = true,
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
         systemNotifications: NotificationCenter = .default,
         preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }) {
        self.defaults = defaults; self.controller = controller; self.clock = clock; self.enableTimers = enableTimers
        self.preferredLanguages = preferredLanguages
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "system") ?? .system
        cityID = defaults.string(forKey: "city") ?? City.all[0].id
        offset = SolarOffset.clamp(defaults.integer(forKey: "offset"))
        sunriseOffset = SolarOffset.clamp(defaults.integer(forKey: "sunriseOffset"))
        enabled = defaults.bool(forKey: "enabled")
        observe(NSWorkspace.didWakeNotification, center: workspaceNotifications)
        observe(NSWorkspace.sessionDidBecomeActiveNotification, center: workspaceNotifications)
        observe(.NSSystemClockDidChange, center: systemNotifications)
        observe(.NSSystemTimeZoneDidChange, center: systemNotifications)
        let localeObserver = systemNotifications.addObserver(forName: NSLocale.currentLocaleDidChangeNotification,
                                                             object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.language == .system else { return }
                self.language = .system
            }
        }
        observers.append((systemNotifications, localeObserver))
        reconcile()
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        observers.append((center, token))
    }

    private func configurationChanged() {
        generation += 1; failures = 0; permissionBlocked = false; failure = nil
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
    func cityName(_ city: City? = nil) -> String { localizer.cityName(city ?? self.city) }

    func time(_ date: Date?) -> String {
        guard let date else { return t("none") }
        let formatter = DateFormatter()
        formatter.locale = localizer.locale
        formatter.timeZone = city.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMdHHmm")
        return formatter.string(from: date)
    }
}
