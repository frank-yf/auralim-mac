import AppKit
import DuskShiftCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var cityID: String { didSet { defaults.set(cityID, forKey: "city"); configurationChanged() } }
    @Published var offset: Int { didSet { defaults.set(offset, forKey: "offset"); configurationChanged() } }
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled"); configurationChanged() } }
    @Published private(set) var schedule: Schedule?
    @Published private(set) var status = "自动切换尚未启用"
    @Published private(set) var errorMessage: String?
    @Published private(set) var isApplying = false

    private let defaults: UserDefaults
    private let controller: AppearanceApplying
    private let clock: () -> Date
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
         systemNotifications: NotificationCenter = .default) {
        self.defaults = defaults; self.controller = controller; self.clock = clock; self.enableTimers = enableTimers
        cityID = defaults.string(forKey: "city") ?? City.all[0].id
        offset = min(120, max(-120, defaults.integer(forKey: "offset")))
        enabled = defaults.bool(forKey: "enabled")
        observe(NSWorkspace.didWakeNotification, center: workspaceNotifications)
        observe(NSWorkspace.sessionDidBecomeActiveNotification, center: workspaceNotifications)
        observe(.NSSystemClockDidChange, center: systemNotifications)
        observe(.NSSystemTimeZoneDidChange, center: systemNotifications)
        reconcile()
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        observers.append((center, token))
    }

    private func configurationChanged() {
        generation += 1; failures = 0; permissionBlocked = false; errorMessage = nil
        reconcile()
    }

    func retry() { configurationChanged() }

    func reconcile() {
        timer?.invalidate(); timer = nil; scheduledCheck = nil
        let state = ScheduleEngine().evaluate(now: clock(), city: city, sunsetOffset: offset)
        schedule = state
        guard enabled else {
            status = "已暂停，当前系统外观保持不变"
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
            let fresh = ScheduleEngine().evaluate(now: self.clock(), city: self.city, sunsetOffset: self.offset)
            if fresh.appearance != state.appearance { self.reconcile(); return }
            self.schedule = fresh
            switch result {
            case .success:
                self.failures = 0; self.errorMessage = nil
                self.status = "已确认系统为\(state.appearance == .dark ? "深色" : "浅色")外观"
                self.arm(at: fresh.nextCheck)
            case .failure(let error):
                self.errorMessage = error.message
                self.status = "自动切换需要处理"
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

    func time(_ date: Date?) -> String {
        guard let date else { return "无" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = city.timeZone
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
