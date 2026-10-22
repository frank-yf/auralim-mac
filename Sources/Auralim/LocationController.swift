import CoreLocation
import os
import AuralimCore

enum LocationMode: String, CaseIterable, Identifiable {
    case manual, automatic
    var id: String { rawValue }
}

enum LocationFailure: String, Error {
    case denied, servicesDisabled, unavailable, timeout, timeZoneUnavailable
    var localizationKey: String { "location.error." + rawValue }
}

enum LocationEvent {
    case locating, resolved(City), failed(LocationFailure, cachedCity: City? = nil)
}

@MainActor
protocol LocationProviding: AnyObject {
    var onEvent: ((LocationEvent) -> Void)? { get set }
    func start()
    func refresh()
    func stop()
    func refreshIfNeeded()
}

struct LocationSample {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date

    func isUsable(at now: Date) -> Bool {
        latitude.isFinite && longitude.isFinite && accuracy.isFinite &&
        (-90...90).contains(latitude) && (-180...180).contains(longitude) &&
        accuracy >= 0 && accuracy <= 20_000 &&
        (-60...300).contains(now.timeIntervalSince(timestamp))
    }
}

/// One-shot acquisition, a local cache and one-shot periodic refresh timers.
@MainActor
final class LocationController: LocationProviding {
    var onEvent: ((LocationEvent) -> Void)?
    private var session: (any LocationSession)?
    private var timeout: Timer?
    private var retry: Timer?
    private var refreshTimer: Timer?
    private(set) var nextRefresh: Date?
    private var pending = false
    private var active = false
    private var awaitingAuthorization = false
    private var requestGeneration = 0
    private var refreshGeneration = 0
    private var requestDeadline: Date?
    private var attempt = 0
    private let retryDelays: [TimeInterval] = [2, 5, 10]
    private let defaults: UserDefaults
    private var cache: CachedLocation?
    private let makeSession: @MainActor () -> any LocationSession
    private let servicesEnabled: @MainActor () -> Bool
    private let schedule: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Timer
    private let now: () -> Date
    private let lookupTimeZone: ((Double, Double) -> TimeZone?)?
    private lazy var timeZones = OfflineTimeZoneLookup()
    private let logger = Logger(subsystem: "app.duskshift.mac", category: "Location")

    init(defaults: UserDefaults = .standard,
         makeSession: @escaping @MainActor () -> any LocationSession = { CoreLocationSession() },
         servicesEnabled: @escaping @MainActor () -> Bool = { CLLocationManager.locationServicesEnabled() },
         now: @escaping () -> Date = Date.init,
         lookupTimeZone: ((Double, Double) -> TimeZone?)? = nil,
         schedule: @escaping @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Timer = { delay, action in
             let timer = Timer(timeInterval: delay, repeats: false) { _ in
                 MainActor.assumeIsolated { action() }
             }
             RunLoop.main.add(timer, forMode: .common)
             return timer
         }) {
        self.defaults = defaults
        cache = defaults.data(forKey: "cachedLocation").flatMap { try? JSONDecoder().decode(CachedLocation.self, from: $0) }
        self.makeSession = makeSession
        self.servicesEnabled = servicesEnabled
        self.now = now
        self.lookupTimeZone = lookupTimeZone
        self.schedule = schedule
    }

    func start() {
        guard !active else { return }
        active = true
        if let city = cache?.usableCity(at: now()) { onEvent?(.resolved(city)) }
        refreshIfNeeded()
    }

    func refresh() {
        guard active else { return }
        requestFix()
    }

    func refreshIfNeeded() {
        guard active, !pending, !awaitingAuthorization else { return }
        if let cache, cache.isFresh(at: now()) {
            scheduleRefresh(at: cache.timestamp.addingTimeInterval(LocationPolicy.refreshInterval))
        } else if nextRefresh == nil || now() >= nextRefresh! {
            requestFix()
        }
    }

    private func requestFix() {
        guard active, !pending else { return }
        if session == nil {
            let session = makeSession()
            self.session = session
            session.onEvent = { [weak self, weak session] event in
                guard let self, let session, self.session === session else { return }
                self.receive(event)
            }
        }
        guard let session else { return }
        guard servicesEnabled() else { fail(.servicesDisabled); return }
        logger.info("Authorization status: \(session.authorizationStatus.rawValue, privacy: .public)")
        switch session.authorizationStatus {
        case .denied, .restricted: fail(.denied)
        case .notDetermined:
            guard !awaitingAuthorization else { return }
            awaitingAuthorization = true
            onEvent?(.locating)
            session.requestAuthorization()
        case .authorizedAlways:
            awaitingAuthorization = false
            pending = true
            attempt = 1
            requestGeneration += 1
            let generation = requestGeneration
            requestDeadline = now().addingTimeInterval(30)
            cancelRefresh()
            onEvent?(.locating)
            timeout = schedule(30) { [weak self] in
                guard let self, self.pending, self.requestGeneration == generation else { return }
                self.fail(.timeout)
            }
            logger.info("Requesting location, attempt 1")
            session.requestLocation()
        @unknown default: fail(.unavailable)
        }
    }

    private func receive(_ event: LocationSessionEvent) {
        switch event {
        case .authorizationChanged:
            guard let session else { return }
            if session.authorizationStatus == .denied || session.authorizationStatus == .restricted {
                fail(.denied)
            } else {
                requestFix()
            }
        case .locations(let samples):
            guard let sample = samples.reversed().first(where: { $0.isUsable(at: now()) }) else {
                scheduleRetry()
                return
            }
            let zone: TimeZone?
            if let lookupTimeZone {
                zone = lookupTimeZone(sample.latitude, sample.longitude)
            } else {
                zone = timeZones?.timeZone(latitude: sample.latitude, longitude: sample.longitude)
            }
            guard let zone else { fail(.timeZoneUnavailable); return }
            let cached = CachedLocation(sample: sample, timeZone: zone)
            cache = cached
            if let data = try? JSONEncoder().encode(cached) {
                defaults.set(data, forKey: "cachedLocation")
            }
            cancelRequest()
            releaseSession()
            scheduleRefresh(at: sample.timestamp.addingTimeInterval(LocationPolicy.refreshInterval))
            logger.info("Location resolved and cached using offline time-zone lookup")
            if let city = cached.city { onEvent?(.resolved(city)) }
        case .failed(let error):
            let nsError = error as NSError
            logger.error("Location error domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            guard nsError.domain == kCLErrorDomain else { fail(.unavailable); return }
            switch CLError.Code(rawValue: nsError.code) {
            case .denied: fail(.denied)
            case .locationUnknown, .network: scheduleRetry()
            default: fail(.unavailable)
            }
        }
    }

    private func scheduleRetry() {
        guard pending, session != nil, retry == nil else { return }
        guard attempt <= retryDelays.count else { fail(.unavailable); return }
        let delay = retryDelays[attempt - 1]
        let generation = requestGeneration
        logger.info("Retrying location after \(delay, privacy: .public) seconds")
        retry = schedule(delay) { [weak self] in
            guard let self, self.pending, self.requestGeneration == generation else { return }
            self.retry = nil
            guard let deadline = self.requestDeadline, self.now() < deadline else {
                self.fail(.timeout); return
            }
            self.attempt += 1
            self.logger.info("Requesting location, attempt \(self.attempt, privacy: .public)")
            self.session?.requestLocation()
        }
    }

    private func cancelRequest() {
        requestGeneration += 1
        timeout?.invalidate(); timeout = nil
        retry?.invalidate(); retry = nil
        pending = false
        requestDeadline = nil
    }

    private func releaseSession() {
        session?.onEvent = nil
        session?.invalidate()
        session = nil
        awaitingAuthorization = false
    }

    private func cancelRefresh() {
        refreshGeneration += 1
        refreshTimer?.invalidate(); refreshTimer = nil; nextRefresh = nil
    }

    private func scheduleRefresh(at date: Date) {
        cancelRefresh()
        nextRefresh = date
        guard active else { return }
        let generation = refreshGeneration
        refreshTimer = schedule(max(0, date.timeIntervalSince(now()))) { [weak self] in
            guard let self, self.active, self.refreshGeneration == generation else { return }
            self.refreshTimer = nil
            self.nextRefresh = nil
            self.requestFix()
        }
    }

    func stop() {
        active = false
        cancelRequest()
        cancelRefresh()
        releaseSession()
    }

    private func fail(_ error: LocationFailure) {
        guard let session else { return }
        cancelRequest()
        session.stopUpdates()
        releaseSession()
        // Keep the previous fix and wait three hours before the next automatic attempt.
        scheduleRefresh(at: now().addingTimeInterval(LocationPolicy.refreshInterval))
        logger.error("Location request ended: \(error.rawValue, privacy: .public)")
        onEvent?(.failed(error, cachedCity: cache?.usableCity(at: now())))
    }
}
