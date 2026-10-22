import AppKit
import CoreLocation
import Testing
import AuralimCore
@testable import Auralim

@MainActor
private final class StubLocationSession: LocationSession {
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var onEvent: ((LocationSessionEvent) -> Void)?
    var authorizationRequests = 0
    var requests = 0
    var invalidations = 0
    func requestAuthorization() { authorizationRequests += 1 }
    func requestLocation() { requests += 1 }
    func stopUpdates() {}
    func invalidate() { invalidations += 1; onEvent = nil }
    func error(_ code: CLError.Code) {
        onEvent?(.failed(NSError(domain: kCLErrorDomain, code: code.rawValue)))
    }
}

@MainActor
private final class LocationEnvironment {
    static let baseline = Date(timeIntervalSince1970: 1_800_000_000)
    var date = baseline
    var services = true
    var authorization: CLAuthorizationStatus = .authorizedAlways
    var zone = TimeZone(identifier: "America/New_York")
    var sessions: [StubLocationSession] = []
    var timers: [(TimeInterval, Timer)] = []
    var failures: [LocationFailure] = []
    var cities: [City] = []
    var fallbackCities: [City?] = []
    var locating = 0

    func makeSession() -> any LocationSession {
        let session = StubLocationSession()
        session.authorizationStatus = authorization
        sessions.append(session)
        return session
    }
    func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        timers.append((delay, timer))
        return timer
    }
    func fire(_ delay: TimeInterval) {
        timers.last(where: { abs($0.0 - delay) < 0.01 })?.1.fire()
    }
    func sample(age: TimeInterval = 0, accuracy: Double = 1_000) -> LocationSample {
        LocationSample(latitude: 40.7128, longitude: -74.0060,
                       accuracy: accuracy, timestamp: date.addingTimeInterval(-age))
    }
}

@MainActor
private struct LocationHarness {
    let suite: String
    let store: UserDefaults
    let env: LocationEnvironment
    let controller: LocationController

    init(cache: CachedLocation? = nil,
         configure: (LocationEnvironment) -> Void = { _ in }) {
        suite = "Auralim.LocationController.\(UUID().uuidString)"
        store = UserDefaults(suiteName: suite)!
        if let cache { store.set(try! JSONEncoder().encode(cache), forKey: "cachedLocation") }
        let env = LocationEnvironment()
        configure(env)
        self.env = env
        controller = LocationController(defaults: store,
            makeSession: { env.makeSession() }, servicesEnabled: { env.services },
            now: { env.date }, lookupTimeZone: { _, _ in env.zone },
            schedule: { env.schedule($0, $1) })
        controller.onEvent = { event in
            switch event {
            case .locating: env.locating += 1
            case .resolved(let city): env.cities.append(city)
            case .failed(let failure, let city): env.failures.append(failure); env.fallbackCities.append(city)
            }
        }
    }
    func close() {
        controller.stop()
        store.removePersistentDomain(forName: suite)
    }
    static func cached(age: TimeInterval = 0) -> CachedLocation {
        CachedLocation(sample: LocationSample(latitude: 40.7128, longitude: -74.0060,
            accuracy: 1_000, timestamp: LocationEnvironment.baseline.addingTimeInterval(-age)),
            timeZone: TimeZone(identifier: "America/New_York")!)
    }
}

@MainActor
struct LocationControllerTests {
    @Test func transientFailureRetriesWithoutImmediatelyFallingBack() {
        let h = LocationHarness(); defer { h.close() }
        h.controller.start()
        let session = h.env.sessions[0]
        session.error(.locationUnknown)
        #expect(h.env.failures.isEmpty)
        #expect(h.env.locating == 1 && session.requests == 1)
        h.env.date += 2; h.env.fire(2)
        #expect(session.requests == 2)
        session.onEvent?(.locations([h.env.sample()]))
        #expect(h.env.cities.last?.timeZoneID == "America/New_York")
        #expect(session.invalidations == 1)
        #expect(h.store.data(forKey: "cachedLocation") != nil)
        #expect(h.controller.nextRefresh == h.env.date.addingTimeInterval(3 * 3600))
    }

    @Test func retriesAreBoundedAndNoContinuousSessionSurvivesFailure() {
        let h = LocationHarness(); defer { h.close() }
        h.controller.start()
        let session = h.env.sessions[0]
        for delay in [2.0, 5.0, 10.0] {
            session.error(.network)
            #expect(h.env.failures.isEmpty)
            h.env.date += delay; h.env.fire(delay)
        }
        session.error(.network)
        #expect(session.requests == 4)
        #expect(h.env.failures == [.unavailable])
        #expect(session.invalidations == 1)
        #expect(h.controller.nextRefresh == h.env.date.addingTimeInterval(3 * 3600))
        h.controller.refreshIfNeeded()
        #expect(h.env.sessions.count == 1)
    }

    @Test func timeoutCancelsQueuedRetryAndLateCallbacks() {
        let h = LocationHarness(); defer { h.close() }
        h.controller.start()
        let session = h.env.sessions[0]
        let late = session.onEvent
        session.error(.locationUnknown)
        h.env.date += 30; h.env.fire(30); h.env.fire(2)
        late?(.locations([h.env.sample()]))
        #expect(session.requests == 1)
        #expect(h.env.failures == [.timeout])
        #expect(h.env.cities.isEmpty)
    }

    @Test func retryAfterWakeCannotExceedTheOverallDeadline() {
        let h = LocationHarness(); defer { h.close() }
        h.controller.start()
        h.env.sessions[0].error(.locationUnknown)
        h.env.date += 31; h.env.fire(2)
        #expect(h.env.failures == [.timeout])
        #expect(h.env.sessions[0].requests == 1)
    }

    @Test func invalidFixesRetryAndSuccessCancelsTheRetry() {
        let h = LocationHarness(); defer { h.close() }
        h.controller.start()
        let session = h.env.sessions[0]
        session.onEvent?(.locations([h.env.sample(age: 301), h.env.sample(accuracy: -1)]))
        #expect(h.env.failures.isEmpty && h.env.cities.isEmpty)
        session.onEvent?(.locations([h.env.sample()]))
        h.env.fire(2)
        #expect(session.requests == 1 && h.env.cities.count == 1)
    }

    @Test func permissionPromptIsRequestedOnceAndGrantStartsAcquisition() {
        let h = LocationHarness(configure: { $0.authorization = .notDetermined }); defer { h.close() }
        h.controller.start()
        let session = h.env.sessions[0]
        h.controller.refresh()
        session.onEvent?(.authorizationChanged)
        #expect(session.authorizationRequests == 1 && session.requests == 0)
        session.authorizationStatus = .authorizedAlways
        session.onEvent?(.authorizationChanged)
        #expect(session.requests == 1)
    }

    @Test(arguments: [CLAuthorizationStatus.denied, .restricted])
    func deniedPermissionDoesNotRetryOrRequestAPosition(status: CLAuthorizationStatus) {
        let h = LocationHarness(configure: { $0.authorization = status }); defer { h.close() }
        h.controller.start()
        #expect(h.env.failures == [.denied])
        #expect(h.env.sessions[0].requests == 0 && h.env.sessions[0].authorizationRequests == 0)
        #expect(h.env.timers.count == 1) // Only the fixed periodic refresh remains.
    }

    @Test func disabledServicesAndMissingTimeZoneKeepTheManualFallback() {
        let h = LocationHarness(configure: { $0.services = false }); defer { h.close() }
        h.controller.start()
        #expect(h.env.failures == [.servicesDisabled])
        #expect(h.env.sessions[0].requests == 0)
        h.env.services = true; h.env.zone = nil
        h.controller.refresh()
        h.env.sessions.last?.onEvent?(.locations([h.env.sample()]))
        #expect(h.env.failures.last == .timeZoneUnavailable)
        #expect(h.store.data(forKey: "cachedLocation") == nil)
    }

    @Test func freshDiskCacheAvoidsCreatingALocationManager() {
        let h = LocationHarness(cache: LocationHarness.cached(age: 300)); defer { h.close() }
        h.controller.start()
        h.controller.refreshIfNeeded()
        #expect(h.env.sessions.isEmpty && h.env.locating == 0)
        #expect(h.env.cities.last?.timeZoneID == "America/New_York")
        #expect(h.controller.nextRefresh == LocationEnvironment.baseline.addingTimeInterval(3 * 3600 - 300))
    }

    @Test func expiredCacheRefreshesOnceAndWakeReusesTheNewCache() {
        let h = LocationHarness(cache: LocationHarness.cached(age: 3 * 3600)); defer { h.close() }
        h.controller.start()
        h.controller.refreshIfNeeded()
        #expect(h.env.sessions.count == 1 && h.env.sessions[0].requests == 1)
        h.env.sessions[0].onEvent?(.locations([h.env.sample()]))
        h.controller.refreshIfNeeded()
        #expect(h.env.sessions.count == 1)
        h.env.date += 3 * 3600; h.env.fire(3 * 3600)
        #expect(h.env.sessions.count == 2 && h.env.sessions[1].requests == 1)
    }

    @Test func manualRefreshOverridesFreshCacheAndStopCancelsAllTimers() {
        let h = LocationHarness(cache: LocationHarness.cached()); defer { h.close() }
        h.controller.start()
        h.controller.refresh()
        #expect(h.env.sessions.count == 1)
        h.env.sessions[0].error(.locationUnknown)
        h.controller.stop()
        for (_, timer) in h.env.timers { timer.fire() }
        #expect(h.env.sessions[0].requests == 1)
        #expect(h.env.timers.allSatisfy { !$0.1.isValid })
        #expect(h.controller.nextRefresh == nil)
    }

    @Test func oldRefreshPreferenceCannotChangeTheThreeHourSchedule() {
        let h = LocationHarness(cache: LocationHarness.cached()); defer { h.close() }
        h.store.set("30d", forKey: "locationRefreshInterval")
        h.controller.start()
        #expect(h.controller.nextRefresh == h.env.date.addingTimeInterval(3 * 3600))
        #expect(h.env.sessions.isEmpty)
    }

    @Test func corruptOrFutureCacheCannotBeUsedAsCurrentLocation() {
        let h = LocationHarness(cache: LocationHarness.cached(age: -120)); defer { h.close() }
        h.controller.start()
        #expect(h.env.cities.isEmpty && h.env.sessions.count == 1)
        let invalid = CachedLocation(sample: LocationSample(latitude: .nan, longitude: 0,
            accuracy: 0, timestamp: h.env.date), timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(invalid.city == nil && !invalid.isFresh(at: h.env.date))
    }
    @Test func successfulFixCanBeRestoredFromDiskWithoutContactingCoreLocation() {
        let h = LocationHarness(); defer { h.close() }
        h.controller.start()
        h.env.sessions[0].onEvent?(.locations([h.env.sample(age: 60)]))
        h.controller.stop()
        let otherStore = UserDefaults(suiteName: h.suite)!
        let restored = LocationController(defaults: otherStore,
            makeSession: { h.env.makeSession() }, now: { h.env.date },
            schedule: { h.env.schedule($0, $1) })
        defer { restored.stop() }
        var restoredCity: City?
        restored.onEvent = { if case .resolved(let city) = $0 { restoredCity = city } }
        restored.start()
        #expect(h.env.sessions.count == 1)
        #expect(restoredCity?.timeZoneID == "America/New_York")
        #expect(restored.nextRefresh == h.env.date.addingTimeInterval(3 * 3600 - 60))
    }

    @Test func failedManualRefreshPreservesThePreviousDiskCache() {
        let h = LocationHarness(cache: LocationHarness.cached()); defer { h.close() }
        let before = h.store.data(forKey: "cachedLocation")
        h.controller.start()
        h.controller.refresh()
        h.env.sessions[0].error(.denied)
        #expect(h.env.failures == [.denied])
        #expect(h.store.data(forKey: "cachedLocation") == before)
        #expect(h.env.fallbackCities.last!?.timeZoneID == "America/New_York")
        h.controller.refreshIfNeeded()
        #expect(h.env.sessions.count == 1)
        #expect(h.controller.nextRefresh == h.env.date.addingTimeInterval(3 * 3600))
    }

    @Test(arguments: [LocationFailure.denied, .servicesDisabled, .unavailable, .timeout, .timeZoneUnavailable])
    func expiredCacheSurvivesRestartAndEachFailedRefresh(failure: LocationFailure) {
        let h = LocationHarness(cache: LocationHarness.cached(age: 7 * 24 * 3600)); defer { h.close() }
        let before = h.store.data(forKey: "cachedLocation")
        if failure == .servicesDisabled { h.env.services = false }
        h.controller.start()
        #expect(h.env.cities.first?.timeZoneID == "America/New_York")
        let session = h.env.sessions[0]
        switch failure {
        case .denied: session.error(.denied)
        case .unavailable: session.onEvent?(.failed(NSError(domain: "test", code: 1)))
        case .timeout: h.env.date += 30; h.env.fire(30)
        case .timeZoneUnavailable:
            h.env.zone = nil; session.onEvent?(.locations([h.env.sample()]))
        case .servicesDisabled: break
        }
        #expect(h.env.failures == [failure])
        #expect(h.env.fallbackCities.last!?.timeZoneID == "America/New_York")
        #expect(h.store.data(forKey: "cachedLocation") == before)
        #expect(h.controller.nextRefresh == h.env.date.addingTimeInterval(3 * 3600))
        #expect(session.invalidations == 1)
    }

    @Test func firstEnableIsTheOnlyTimeAnUndeterminedPermissionIsRequested() {
        let h = LocationHarness(configure: { $0.authorization = .notDetermined }); defer { h.close() }
        #expect(h.env.sessions.isEmpty) // Manual mode has not started the provider.
        h.controller.start()
        let session = h.env.sessions[0]
        #expect(session.authorizationRequests == 1 && session.requests == 0)
        session.authorizationStatus = .authorizedAlways
        session.onEvent?(.authorizationChanged)
        session.onEvent?(.locations([h.env.sample()]))
        h.env.authorization = .authorizedAlways
        h.controller.refresh()
        #expect(h.env.sessions[1].authorizationRequests == 0 && h.env.sessions[1].requests == 1)
    }

}
