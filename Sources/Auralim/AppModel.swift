import AppKit
import AuralimCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "language") } }
    @Published var cityID: String { didSet { defaults.set(cityID, forKey: "city"); configurationChanged() } }
    @Published var sunriseOffset: Int { didSet { if sunriseOffset != oldValue { defaults.set(sunriseOffset, forKey: "sunriseOffset"); offsetChanged() } } }
    @Published var offset: Int { didSet { if offset != oldValue { defaults.set(offset, forKey: "offset"); offsetChanged() } } }
    @Published var enabled: Bool {
        didSet {
            if enabled { manualAppearance = nil; defaults.removeObject(forKey: "manualAppearance") }
            defaults.set(enabled, forKey: "enabled")
            configurationChanged()
        }
    }
    @Published var transitionAnimationEnabled: Bool {
        didSet {
            guard transitionAnimationEnabled != oldValue else { return }
            defaults.set(transitionAnimationEnabled, forKey: "transitionAnimationEnabled")
            if !transitionAnimationEnabled {
                wakeTransition.suppressAnimation()
                let hadPending = pendingTransition != nil && cancelPendingTransition()
                if !hadPending { transitionPlayer.stop() }
                if hadPending { reconcile(allowAnimation: false, allowCountdown: false) }
            }
        }
    }
    @Published var countdownEnabled: Bool {
        didSet {
            guard countdownEnabled != oldValue else { return }
            defaults.set(countdownEnabled, forKey: "countdownEnabled")
            if !countdownEnabled, pendingCountdown != nil {
                cancelCountdown()
                reconcile(allowCountdown: false)
            }
        }
    }
    @Published var countdownSeconds: Int {
        didSet {
            let clamped = min(120, max(1, countdownSeconds))
            if clamped != countdownSeconds { countdownSeconds = clamped }
            defaults.set(countdownSeconds, forKey: "countdownSeconds")
            if countdownSeconds != oldValue, pendingCountdown != nil {
                cancelCountdown()
                reconcile()
            }
        }
    }
    @Published private(set) var countdownRemaining: Int?
    @Published private(set) var manualAppearance: Appearance?
    @Published private var systemSettings: SystemAppearanceSettings
    var currentSystemAppearance: Appearance { systemSettings.appearance }
    var appearanceMode: AppearanceMode? {
        if enabled { return .automatic }
        if let manualAppearance { return manualAppearance == .dark ? .dark : .light }
        switch systemSettings.mode {
        case .light: return .light
        case .dark: return .dark
        case .automatic, .unknown: return nil
        }
    }
    var appearanceModeTitle: String {
        if enabled { return t("appearance.appAuto") }
        if manualAppearance != nil { return t("appearance.appManual") }
        return t(systemSettings.mode == .automatic ? "appearance.systemAuto" : "appearance.systemManaged")
    }
    private var managedAppearanceStatus: String {
        t("appearance.current", appearanceModeTitle, t(systemSettings.appearance == .dark ? "dark" : "light"))
    }
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
        if cancelledCountdownTarget != nil { return t("countdown.cancelled") }
        if let countdownRemaining, let target = pendingCountdown?.target {
            return t("countdown.remaining", t(target == .light ? "light" : "dark"), countdownRemaining)
        }
        if enabled || manualAppearance != nil {
            switch statusState {
            case .disabled, .paused: return t("checking")
            default: break
            }
        }
        if !enabled && manualAppearance == nil { return managedAppearanceStatus }
        if case .confirmed(let appearance) = statusState {
            return enabled ? t("appearance.solarStatus", t(appearance == .dark ? "dark" : "light"))
                : t("appearance.current", appearanceModeTitle, t(appearance == .dark ? "dark" : "light"))
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

    let debugPreview: DebugPreviewController
    let debugAppearanceCheck: DebugAppearanceCheckController
    private let defaults: UserDefaults
    private let controller: AppearanceApplying
    private let transitionPlayer: AppearanceTransitionPlaying
    private var wakeTransition: WakeAppearanceTransition!
    private let countdownPresenter: CountdownPresenting
    private var pendingCountdown: (id: UUID, target: Appearance)?
    private var cancelledCountdownTarget: Appearance?
    private var applyingDebugPreview = false
    private var handlingAppearanceSelection = false
    private var pendingTransition: (id: UUID, target: Appearance)?
    private var activeAppearanceRequest: UUID?
    private var startupReadiness: StartupAppearanceReadiness?
    private var startupRecoveryInProgress = false
    private var startupFailure: (target: Appearance, error: AppearanceFailure)?
    private let desktopReady: @MainActor () -> Bool
    private let loginItemController: LoginItemControlling
    private let locationController: LocationProviding
    private let clock: () -> Date
    private let preferredLanguages: () -> [String]
    private let readSystemSettings: @MainActor () -> SystemAppearanceSettings
    private let enableTimers: Bool
    private(set) var scheduledCheck: Date?
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var generation = 0
    private var failures = 0
    private var permissionBlocked = false
    private var isShutdown = false
    var manualCity: City { City.all.first(where: { $0.id == cityID }) ?? City.all[0] }
    var city: City { locationMode == .automatic ? locatedCity ?? manualCity : manualCity }

    init(defaults: UserDefaults = .standard, controller: AppearanceApplying = AppearanceController(),
         clock: @escaping () -> Date = Date.init, enableTimers: Bool = true,
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
         systemNotifications: NotificationCenter = .default,
         appearanceNotifications: NotificationCenter = DistributedNotificationCenter.default(),
         preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages },
         systemTimeZone: () -> TimeZone = { .current },
         loginItemController: LoginItemControlling? = nil,
         locationController: LocationProviding? = nil,
         systemSettings: @escaping @MainActor () -> SystemAppearanceSettings = { .current() },
         transitionPlayer: AppearanceTransitionPlaying? = nil,
         desktopReady: @escaping @MainActor () -> Bool = { WakeAppearanceTransition.desktopIsReady() },
         wakeAnimationDelay: TimeInterval = 0.6,
         countdownPresenter: CountdownPresenting? = nil,
         debugPreview: DebugPreviewController? = nil,
         debugAppearanceCheck: DebugAppearanceCheckController? = nil,
         startupReadinessChecker: AppearanceReadinessChecking? = nil,
         startupReadinessDelays: [TimeInterval] = [1, 2, 5],
         startupReadinessSchedule: StartupAppearanceReadiness.Scheduler? = nil) {
        self.defaults = defaults; self.controller = controller; self.clock = clock; self.enableTimers = enableTimers
        self.transitionPlayer = transitionPlayer ?? AppearanceTransitionController()
        self.debugPreview = debugPreview ?? DebugPreviewController(defaults: defaults)
        self.debugAppearanceCheck = debugAppearanceCheck ?? DebugAppearanceCheckController()
        self.desktopReady = desktopReady
        self.countdownPresenter = countdownPresenter ?? CountdownController()
        self.loginItemController = loginItemController ?? LoginItemController()
        self.locationController = locationController ?? LocationController(defaults: defaults)
        self.preferredLanguages = preferredLanguages
        self.readSystemSettings = systemSettings
        self.systemSettings = systemSettings()
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "system") ?? .system
        if let savedCity = defaults.string(forKey: "city") {
            cityID = savedCity
        } else {
            let initialCity = City.matching(timeZone: systemTimeZone()) ?? City.all[0]
            cityID = initialCity.id
            defaults.set(initialCity.id, forKey: "city")
        }
        offset = SolarOffset.clamp(defaults.integer(forKey: "offset"))
        sunriseOffset = SolarOffset.clamp(defaults.integer(forKey: "sunriseOffset"))
        let automatic = defaults.bool(forKey: "enabled")
        enabled = automatic
        // Solar Auto remains an explicit app preference. Otherwise each launch
        // starts from macOS, rather than reapplying a stale saved manual theme.
        manualAppearance = nil
        countdownEnabled = defaults.bool(forKey: "countdownEnabled")
        countdownSeconds = min(120, max(1, (defaults.object(forKey: "countdownSeconds") as? Int) ?? 10))
        transitionAnimationEnabled = defaults.bool(forKey: "transitionAnimationEnabled")
        locationMode = LocationMode(rawValue: defaults.string(forKey: "locationMode") ?? "manual") ?? .manual
        defaults.removeObject(forKey: "locationRefreshInterval")
        wakeTransition = WakeAppearanceTransition(desktopReady: desktopReady, delay: wakeAnimationDelay) { [weak self] target in
            guard let self, self.transitionAnimationEnabled else { return }
            self.playTransition(target)
        }
        // Test models with timers disabled stay deterministic unless a checker
        // is explicitly injected. The production controller always supports this.
        if automatic, let checker = startupReadinessChecker ?? (enableTimers ? controller as? AppearanceReadinessChecking : nil) {
            startupRecoveryInProgress = true
            startupReadiness = StartupAppearanceReadiness(checker: checker, desktopReady: desktopReady,
                delays: startupReadinessDelays, schedule: startupReadinessSchedule) { [weak self] result in
                    self?.startupReadinessFinished(result)
                }
        }
        observeLifecycle(NSWorkspace.willSleepNotification, center: workspaceNotifications)
        observeLifecycle(NSWorkspace.didWakeNotification, center: workspaceNotifications)
        observeLifecycle(NSWorkspace.screensDidSleepNotification, center: workspaceNotifications)
        observeLifecycle(NSWorkspace.screensDidWakeNotification, center: workspaceNotifications)
        observeLifecycle(NSWorkspace.sessionDidResignActiveNotification, center: workspaceNotifications)
        observeLifecycle(NSWorkspace.sessionDidBecomeActiveNotification, center: workspaceNotifications)
        // Screen locking does not necessarily deactivate the workspace session.
        observeLifecycle(Notification.Name("com.apple.screenIsLocked"), center: appearanceNotifications)
        observeLifecycle(Notification.Name("com.apple.screenIsUnlocked"), center: appearanceNotifications)
        observe(NSApplication.didFinishLaunchingNotification, center: systemNotifications)
        observe(.NSSystemClockDidChange, center: systemNotifications)
        observe(Notification.Name("AppleInterfaceThemeChangedNotification"), center: appearanceNotifications)
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
            Task { @MainActor in self?.reconcile(); self?.refreshLoginItemStatus(); self?.refreshLocation(force: false) }
        }
        observers.append((systemNotifications, activationObserver))
        let terminationObserver = systemNotifications.addObserver(forName: NSApplication.willTerminateNotification,
                                                                  object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutdown() }
        }
        observers.append((systemNotifications, terminationObserver))
        refreshLoginItemStatus()
        self.locationController.onEvent = { [weak self] event in self?.receiveLocation(event) }
        reconcile()
        if locationMode == .automatic { self.locationController.start() }
    }

    func refreshLocation(force: Bool = true) {
        guard locationMode == .automatic else { return }
        if force { locationController.refresh() }
        else { locationController.refreshIfNeeded() }
    }

    private func receiveLocation(_ event: LocationEvent) {
        guard locationMode == .automatic else { return }
        let previous = city
        switch event {
        case .locating: isLocating = true; locationFailure = nil
        case .resolved(let city):
            locatedCity = city
            isLocating = false; locationFailure = nil
        case .failed(let error, let cachedCity):
            locatedCity = cachedCity ?? locatedCity; isLocating = false; locationFailure = error
        }
        guard previous != city else { return }
        // Location events are automatic; they must not repeatedly request a
        // previously denied Automation permission.
        generation += 1; failures = 0
        reconcile()
    }

    var locationStatus: String {
        if let locationFailure {
            if let locatedCity {
                return t("location.cachedFallback", t(locationFailure.localizationKey), locationCoordinates(locatedCity))
            }
            return t("location.fallback", t(locationFailure.localizationKey), cityName(manualCity))
        }
        if isLocating {
            if let locatedCity { return t("location.cachedRefreshing", locationCoordinates(locatedCity)) }
            return t("location.locating")
        }
        if let locatedCity {
            return t("location.using", locationCoordinates(locatedCity))
        }
        return t("location.manual.hint")
    }

    private func locationCoordinates(_ city: City) -> String {
        String(format: "%.3f, %.3f", locale: localizer.locale, city.latitude, city.longitude)
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
                if refreshLocation { self?.refreshLocation(force: name == .NSSystemTimeZoneDidChange) }
            }
        }
        observers.append((center, token))
    }

    private func observeLifecycle(_ name: Notification.Name, center: NotificationCenter) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isShutdown else { return }
                self.debugPreview.stop()
                self.debugAppearanceCheck.cancel()
                switch name {
                case NSWorkspace.willSleepNotification:
                    self.startupReadiness?.desktopUnavailable()
                    self.cancelPendingTransition()
                    self.refreshSystemAppearance()
                    self.wakeTransition.willSleep(appearance: self.currentSystemAppearance)
                    self.transitionPlayer.stop()
                    return
                case NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification,
                     Notification.Name("com.apple.screenIsLocked"):
                    let hadPending = self.cancelPendingTransition()
                    self.wakeTransition.desktopUnavailable()
                    self.startupReadiness?.desktopUnavailable()
                    self.transitionPlayer.stop()
                    if hadPending { self.reconcile(allowAnimation: false) }
                    return
                case NSWorkspace.didWakeNotification:
                    self.cancelStartupRecovery() // Wake correction must remain immediate.
                    self.cancelPendingTransition()
                    self.cancelledCountdownTarget = nil
                    self.wakeTransition.didWake(fallback: self.currentSystemAppearance)
                default:
                    self.wakeTransition.desktopChanged()
                    self.startupReadiness?.desktopChanged()
                }
                self.reconcile()
                if name == NSWorkspace.didWakeNotification || name == NSWorkspace.sessionDidBecomeActiveNotification {
                    self.refreshLocation(force: false)
                }
            }
        }
        observers.append((center, token))
    }

    private func startupReadinessFinished(_ result: Result<Appearance, AppearanceFailure>) {
        guard !isShutdown, enabled, startupReadiness != nil else { return }
        startupReadiness = nil
        switch result {
        case .success(let observed):
            // Recompute now, not at launch: city, offsets and the solar boundary
            // may have changed while the desktop/service was unavailable.
            reconcile(observedAppearance: observed)
        case .failure(let error):
            startupRecoveryInProgress = false
            let state = ScheduleEngine().evaluate(now: clock(), city: city, sunriseOffset: sunriseOffset, sunsetOffset: offset)
            startupFailure = (state.appearance, error)
            reconcile()
        }
    }

    private func cancelStartupRecovery() {
        let ownedRequest = startupRecoveryInProgress
        startupRecoveryInProgress = false
        startupReadiness?.cancel(); startupReadiness = nil
        startupFailure = nil
        if ownedRequest {
            cancelPendingTransition()
            if activeAppearanceRequest != nil {
                activeAppearanceRequest = nil; isApplying = false
                controller.cancel()
            }
        }
    }

    private func playTransition(_ target: Appearance) {
        debugPreview.stop()
        transitionPlayer.play(target, title: t(target == .light ? "transition.sunrise" : "transition.sunset"))
    }

    @discardableResult
    private func cancelPendingTransition() -> Bool {
        let hadCountdown = pendingCountdown != nil
        cancelCountdown()
        guard pendingTransition != nil else { return hadCountdown }
        pendingTransition = nil // Invalidate even a completion already queued by the player.
        transitionPlayer.stop()
        return true
    }

    private func cancelCountdown() {
        pendingCountdown = nil
        countdownRemaining = nil
        countdownPresenter.stop()
    }

    private func startCountdown(_ target: Appearance) {
        debugPreview.stop()
        let id = UUID()
        pendingCountdown = (id, target)
        countdownRemaining = countdownSeconds
        countdownPresenter.start(seconds: countdownSeconds, target: target, localizer: localizer,
            tick: { [weak self] seconds in
                guard let self, self.pendingCountdown?.id == id else { return }
                self.countdownRemaining = seconds
            }, finish: { [weak self] in
                guard let self, !self.isShutdown, self.pendingCountdown?.id == id else { return }
                self.cancelCountdown() // Release the small panel before the celestial animation.
                self.reconcile(allowCountdown: false)
            }, cancel: { [weak self] in
                guard let self, self.pendingCountdown?.id == id else { return }
                self.cancelledCountdownTarget = target
                self.cancelCountdown()
            })
    }

    private func animateBeforeApplying(_ target: Appearance) {
        debugPreview.stop()
        let id = UUID()
        pendingTransition = (id, target)
        transitionPlayer.play(target, title: t(target == .light ? "transition.sunrise" : "transition.sunset"), onAnimationEnd: { [weak self] in
            guard let self, !self.isShutdown, self.pendingTransition?.id == id else { return }
            self.pendingTransition = nil
            // Re-evaluate time, city, settings and actual appearance after the
            // effect. Never apply a captured target that has become obsolete.
            self.reconcile(allowAnimation: false, allowCountdown: false)
        }, completion: {})
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

    func selectAppearanceMode(_ selection: AppearanceMode?) {
        guard let mode = selection else { return }
        guard mode != appearanceMode || cancelledCountdownTarget != nil || (!enabled && manualAppearance == nil)
                || startupRecoveryInProgress || startupFailure != nil else { return }
        cancelStartupRecovery()
        // Explicit choices, including Auto, express intent to switch now.
        // Scope this to the selection so later scheduled transitions still count down.
        let previousSelection = handlingAppearanceSelection
        handlingAppearanceSelection = true
        defer { handlingAppearanceSelection = previousSelection }
        cancelledCountdownTarget = nil
        statusState = .disabled
        if mode == .automatic {
            enabled = true
        } else {
            manualAppearance = mode.appearance
            defaults.set(mode.appearance!.rawValue, forKey: "manualAppearance")
            if enabled { enabled = false }
            else { configurationChanged() }
        }
    }

    var canPreviewDebug: Bool {
        BuildFeatures.debugToolsEnabled && !isShutdown && startupReadiness == nil && !isApplying && pendingCountdown == nil && pendingTransition == nil
            && !wakeTransition.requiresImmediateCorrection && desktopReady()
    }

    func previewDebug(_ action: DebugPreviewController.Action, target: Appearance) {
        guard canPreviewDebug, debugPreview.enabled else { return }
        // A wake effect may still be playing after its immediate correction.
        // Release it before showing the independent preview presenters.
        transitionPlayer.stop()
        debugPreview.preview(action, target: target, seconds: countdownSeconds, localizer: localizer) { [weak self] target in
            guard let self, self.canPreviewDebug, self.debugPreview.enabled else { return }
            // Enter manual mode through normal verification/error handling, but
            // do not repeat the countdown or animation that just finished.
            self.applyingDebugPreview = true
            defer { self.applyingDebugPreview = false }
            self.manualAppearance = target
            self.defaults.set(target.rawValue, forKey: "manualAppearance")
            self.cancelledCountdownTarget = nil
            if self.enabled { self.enabled = false }
            else { self.configurationChanged() }
        }
    }

    func retry() { cancelStartupRecovery(); cancelledCountdownTarget = nil; configurationChanged() }

    func reconcile(allowAnimation: Bool = true, allowCountdown: Bool = true, observedAppearance: Appearance? = nil) {
        guard !isShutdown else { return }
        wakeTransition.invalidateVerification()
        timer?.invalidate(); timer = nil; scheduledCheck = nil
        let state = ScheduleEngine().evaluate(now: clock(), city: city, sunriseOffset: sunriseOffset, sunsetOffset: offset)
        schedule = state
        // The tray always reflects the observed system appearance, including
        // App Auto/manual mode and requests that are still pending or failed.
        refreshSystemAppearance()
        if let observedAppearance {
            systemSettings = .init(mode: systemSettings.mode, appearance: observedAppearance)
        }
        if !enabled { cancelStartupRecovery() }
        guard let target = enabled ? state.appearance : manualAppearance else {
            statusState = .paused
            cancelPendingTransition()
            wakeTransition.cancelWake()
            return
        }
        if enabled { arm(at: state.nextCheck) }
        if let startupReadiness {
            startupReadiness.startIfReady()
            return // No countdown, animation or setter before a successful read.
        }
        if let blocked = startupFailure {
            if blocked.target == target {
                if currentSystemAppearance == target && !blocked.error.permissionDenied {
                    startupFailure = nil; failure = nil; failures = 0
                    statusState = .confirmed(target)
                } else {
                    failure = blocked.error; permissionBlocked = blocked.error.permissionDenied
                    statusState = .attention
                }
                return // Activation/configuration notifications cannot restart the retry budget.
            }
            startupFailure = nil // A later solar target is a new scheduled event.
            if !blocked.error.permissionDenied { failure = nil; failures = 0; permissionBlocked = false }
        }
        if startupRecoveryInProgress && !isApplying && currentSystemAppearance == target {
            cancelPendingTransition()
            startupRecoveryInProgress = false
            failure = nil; failures = 0
            statusState = .confirmed(target)
            return // An already-correct system needs neither animation nor a setter.
        }
        if cancelledCountdownTarget != target { cancelledCountdownTarget = nil }
        if cancelledCountdownTarget == target && !wakeTransition.requiresImmediateCorrection { return }
        // Manual choices already express intent: animate and apply without a countdown.
        let canCountdown = enabled && !handlingAppearanceSelection && !applyingDebugPreview && allowCountdown && countdownEnabled && failures == 0
            && !wakeTransition.requiresImmediateCorrection && desktopReady() && target != currentSystemAppearance
        if let pendingCountdown {
            if pendingCountdown.target == target && canCountdown { return }
            cancelCountdown()
        }
        let canAnimate = !applyingDebugPreview && allowAnimation && transitionAnimationEnabled && failures == 0
            && !wakeTransition.requiresImmediateCorrection && desktopReady()
            && target != currentSystemAppearance
        if let pendingTransition {
            if pendingTransition.target == target && canAnimate { return }
            cancelPendingTransition()
        }
        guard !permissionBlocked, !isApplying else { return }
        if canCountdown {
            startCountdown(target)
            return
        }
        if canAnimate {
            animateBeforeApplying(target)
            return
        }
        if target != currentSystemAppearance && !applyingDebugPreview { debugPreview.stop() }
        isApplying = true
        let requestID = UUID()
        activeAppearanceRequest = requestID
        let requestGeneration = generation
        controller.apply(target) { [weak self] result in
            guard let self, self.activeAppearanceRequest == requestID else { return }
            self.activeAppearanceRequest = nil
            self.isApplying = false
            guard !self.isShutdown else { return }
            self.refreshSystemAppearance()
            guard self.enabled || self.manualAppearance != nil else { return }
            guard requestGeneration == self.generation else { self.reconcile(); return }
            // Requests can span a clock/solar boundary or a manual/auto change.
            let fresh = ScheduleEngine().evaluate(now: self.clock(), city: self.city, sunriseOffset: self.sunriseOffset, sunsetOffset: self.offset)
            let freshTarget = self.enabled ? fresh.appearance : self.manualAppearance
            if freshTarget != target { self.reconcile(); return }
            self.schedule = fresh
            switch result {
            case .success(let application):
                self.startupRecoveryInProgress = false
                // Ordinary switches have already animated. Only wake recovery
                // can schedule a post-correction effect after the desktop returns.
                _ = self.wakeTransition.verified(target, changed: application.changed)
                self.failures = 0; self.failure = nil
                self.statusState = .confirmed(target)
                if self.enabled { self.arm(at: fresh.nextCheck) }
            case .failure(let error):
                self.failure = error
                self.statusState = .attention
                self.permissionBlocked = error.permissionDenied
                self.failures += 1
                if error.permissionDenied || self.failures > 2 {
                    if self.startupRecoveryInProgress { self.startupFailure = (target, error) }
                    self.startupRecoveryInProgress = false
                }
                if !error.permissionDenied && self.failures <= 2 {
                    let retry = self.clock().addingTimeInterval(Double(self.failures) * 5)
                    self.arm(at: self.enabled ? min(fresh.nextCheck, retry) : retry)
                }
            }
        }
    }

    private func refreshSystemAppearance() {
        let actual = readSystemSettings()
        if systemSettings != actual { systemSettings = actual }
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
        guard !isShutdown else { return }
        isShutdown = true
        cancelStartupRecovery()
        activeAppearanceRequest = nil; isApplying = false
        controller.cancel()
        debugAppearanceCheck.cancel()
        debugPreview.stop()
        cancelPendingTransition()
        wakeTransition.cancelWake()
        transitionPlayer.stop()
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

    func clockTime(_ date: Date?) -> String {
        guard let date else { return t("none") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = city.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
