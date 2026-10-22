import AppKit
import Testing
import AuralimCore
@testable import Auralim

@MainActor
final class FakeLocation: LocationProviding {
    var onEvent: ((LocationEvent) -> Void)?
    var starts = 0, refreshes = 0, stops = 0, freshnessChecks = 0
    func start() { starts += 1; onEvent?(.locating) }
    func refresh() { refreshes += 1; onEvent?(.locating) }
    func stop() { stops += 1 }
    func refreshIfNeeded() { freshnessChecks += 1 }
}

private final class LocationAppearanceSpy: AppearanceApplying {
    var requests: [Appearance] = []
    var permissionDenied = false
    var pending: ((Result<AppearanceApplication, AppearanceFailure>) -> Void)?
    var hold = false
    func apply(_ appearance: Appearance, completion: @escaping (Result<AppearanceApplication, AppearanceFailure>) -> Void) {
        requests.append(appearance)
        if hold { pending = completion }
        else if permissionDenied { completion(.failure(AppearanceFailure(message: "denied", permissionDenied: true))) }
        else { completion(.success(AppearanceApplication(changed: false))) }
    }
}

@MainActor
struct LocationTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-22T04:00:00Z")!
    private let newYork = City(id: "current-location", name: "", latitude: 40.7128, longitude: -74.0060, timeZoneID: "America/New_York")
    private func withModel(_ automatic: Bool = false,
                           _ body: (AppModel, FakeLocation, LocationAppearanceSpy, UserDefaults, NotificationCenter, NotificationCenter) async throws -> Void) async rethrows {
        let suite = "Auralim.Location.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        store.set(true, forKey: "enabled"); store.set("en", forKey: "language")
        if automatic { store.set("automatic", forKey: "locationMode") }
        let location = FakeLocation(), appearance = LocationAppearanceSpy()
        let workspace = NotificationCenter(), system = NotificationCenter()
        let model = AppModel(defaults: store, controller: appearance, clock: { now }, enableTimers: false,
                             workspaceNotifications: workspace, systemNotifications: system,
                             systemTimeZone: { TimeZone(identifier: "Asia/Shanghai")! }, locationController: location)
        defer { model.shutdown(); store.removePersistentDomain(forName: suite) }
        try await body(model, location, appearance, store, workspace, system)
    }

    @Test func manualModeDoesNotRequestLocationAndPreservesTheCity() async {
        await withModel { model, location, _, _, _, _ in
            #expect(location.starts == 0)
            model.refreshLocation()
            #expect(location.refreshes == 0)
            model.cityID = "beijing"
            model.locationMode = .automatic
            #expect(location.starts == 1)
            #expect(model.isLocating)
            location.onEvent?(.resolved(newYork))
            #expect(model.city.timeZoneID == "America/New_York")
            #expect(model.cityID == "beijing")
            model.locationMode = .manual
            #expect(location.stops == 1)
            #expect(model.city.id == "beijing")
            location.onEvent?(.resolved(newYork))
            #expect(model.city.id == "beijing")
        }
    }

    @Test func travelRecalculatesAppearanceAndDisplayedLocalDate() async {
        await withModel { model, location, appearance, _, _, _ in
            model.sunriseOffset = -37; model.offset = 42
            model.locationMode = .automatic
            location.onEvent?(.resolved(newYork))
            let expected = ScheduleEngine().evaluate(now: now, city: newYork, sunriseOffset: -37, sunsetOffset: 42)
            #expect(appearance.requests.last == .dark)
            #expect(model.schedule?.nextTransition == expected.nextTransition)
            #expect(model.schedule?.todayLightTime == expected.todayLightTime)
            #expect(model.cityName() == "Current location")
            #expect(model.time(now).contains("00:00"))
            let tokyo = City(id: "current-location", name: "", latitude: 35.6762, longitude: 139.6503, timeZoneID: "Asia/Tokyo")
            location.onEvent?(.resolved(tokyo))
            #expect(appearance.requests.last == .light)
            #expect(model.time(now).contains("13:00"))
            #expect(model.sunriseOffset == -37 && model.offset == 42)
        }
    }

    @Test func eachFailureWithoutCacheFallsBackAndCanRecoverWithoutOverwritingManualCity() async {
        await withModel(true) { model, location, _, store, _, _ in
            model.cityID = "Asia/Tokyo"
            for failure in [LocationFailure.denied, .servicesDisabled, .unavailable, .timeout, .timeZoneUnavailable] {
                location.onEvent?(.failed(failure))
                #expect(model.city.id == "Asia/Tokyo")
                #expect(model.locatedCity == nil)
                #expect(!model.isLocating)
                #expect(model.locationStatus.contains("Tokyo"))
                #expect(model.schedule?.appearance == .light)
                #expect(store.string(forKey: "city") == "Asia/Tokyo")
            }
            model.refreshLocation()
            location.onEvent?(.resolved(newYork))
            #expect(model.locationFailure == nil)
            #expect(model.city.timeZoneID == "America/New_York")
        }
    }

    @Test func automaticModePersistsAndRestoresThroughTheLocationProvider() async {
        await withModel { model, location, _, store, _, _ in
            model.locationMode = .automatic
            location.onEvent?(.resolved(newYork))
            #expect(store.string(forKey: "locationMode") == "automatic")
            let restoredLocation = FakeLocation()
            let restored = AppModel(defaults: store, controller: LocationAppearanceSpy(), enableTimers: false,
                                    locationController: restoredLocation)
            defer { restored.shutdown() }
            #expect(restored.locationMode == .automatic)
            #expect(restoredLocation.starts == 1)
            #expect(restored.locatedCity == nil)
            #expect(restored.city == restored.manualCity)
        }
    }

    @Test func wakeTimeZoneAndActivationRefreshOnlyAutomaticMode() async {
        await withModel { model, location, _, _, workspace, system in
            workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
            await Task.yield()
            #expect(location.refreshes == 0)
            model.locationMode = .automatic
            workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
            await Task.yield()
            system.post(name: .NSSystemTimeZoneDidChange, object: nil)
            await Task.yield()
            system.post(name: NSApplication.didBecomeActiveNotification, object: nil)
            await Task.yield()
            #expect(location.refreshes == 1 && location.freshnessChecks == 2)
            model.refreshLocation()
            #expect(location.refreshes == 2)
        }
    }

    @Test func lateAppearanceResultDoesNotOverwriteATravelledLocation() async {
        await withModel { model, location, appearance, _, _, _ in
            appearance.hold = true
            model.locationMode = .automatic
            location.onEvent?(.resolved(newYork))
            #expect(model.isApplying)
            appearance.hold = false
            appearance.pending?(.success(AppearanceApplication(changed: false)))
            #expect(appearance.requests.last == .dark)
            #expect(model.schedule?.appearance == .dark)
            #expect(!model.isApplying)
        }
    }

    @Test func locationUpdatesDoNotRepeatDeniedAutomationPrompts() async {
        await withModel { model, location, appearance, _, _, _ in
            appearance.permissionDenied = true
            model.locationMode = .automatic
            let count = appearance.requests.count
            location.onEvent?(.resolved(newYork))
            location.onEvent?(.failed(.unavailable))
            #expect(appearance.requests.count == count)
        }
    }

    @Test func languageChangeKeepsLocationAndDoesNotRequestANewFix() async {
        await withModel(true) { model, location, appearance, _, _, _ in
            location.onEvent?(.failed(.timeout))
            let count = appearance.requests.count, refreshes = location.refreshes
            model.language = .simplifiedChinese
            #expect(model.locationStatus.contains("超时"))
            #expect(model.locationStatus.contains("上海"))
            #expect(appearance.requests.count == count)
            #expect(location.refreshes == refreshes)
        }
    }

    @Test func staleInaccurateAndInvalidFixesAreRejected() {
        func valid(_ lat: Double = 31, _ lon: Double = 121, _ accuracy: Double = 1_000, _ age: Double = 0) -> Bool {
            LocationSample(latitude: lat, longitude: lon, accuracy: accuracy, timestamp: now.addingTimeInterval(-age)).isUsable(at: now)
        }
        #expect(valid())
        #expect(valid(31, 121, 20_000, 300))
        #expect(!valid(31, 121, -1))
        #expect(!valid(31, 121, 20_001))
        #expect(!valid(31, 121, 1_000, 301))
        #expect(!valid(31, 121, 1_000, -61))
        #expect(!valid(.nan))
        #expect(!valid(91))
        #expect(!valid(31, 181))
    }
    @Test(arguments: [("Asia/Shanghai", "Asia/Shanghai"), ("Asia/Tokyo", "Asia/Tokyo"),
                     ("America/New_York", "America/New_York"), ("US/Pacific", "America/Los_Angeles"),
                     ("UTC", "Asia/Shanghai")])
    func firstLaunchMatchesSystemTimeZoneAndPersistsCity(zone: String, expected: String) {
        let suite = "Auralim.InitialCity.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        let location = FakeLocation()
        let model = AppModel(defaults: store, controller: LocationAppearanceSpy(), enableTimers: false,
            systemTimeZone: { TimeZone(identifier: zone)! }, loginItemController: FakeLoginItem(),
            locationController: location)
        defer { model.shutdown() }
        #expect(model.cityID == expected && store.string(forKey: "city") == expected)
        #expect(model.locationMode == .manual && location.starts == 0)
    }

    @Test func savedManualCitySurvivesRestartAndObsoleteIntervalIsRemoved() {
        let suite = "Auralim.SavedCity.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        store.set("beijing", forKey: "city")
        store.set("7d", forKey: "locationRefreshInterval")
        let location = FakeLocation()
        let model = AppModel(defaults: store, controller: LocationAppearanceSpy(), enableTimers: false,
            systemTimeZone: { TimeZone(identifier: "America/New_York")! },
            loginItemController: FakeLoginItem(), locationController: location)
        defer { model.shutdown() }
        #expect(model.cityID == "beijing")
        #expect(store.object(forKey: "locationRefreshInterval") == nil)
        #expect(location.starts == 0)
    }

    @Test func failedRefreshKeepsCachedCoordinatesTimeZoneAndSolarSchedule() async {
        await withModel(true) { model, location, _, _, _, _ in
            model.cityID = "Asia/Tokyo"
            location.onEvent?(.resolved(newYork))
            let transition = model.schedule?.nextTransition
            for failure in [LocationFailure.denied, .servicesDisabled, .unavailable, .timeout, .timeZoneUnavailable] {
                location.onEvent?(.locating)
                #expect(model.city == newYork)
                location.onEvent?(.failed(failure, cachedCity: newYork))
                #expect(model.city == newYork && model.locatedCity == newYork)
                #expect(model.schedule?.nextTransition == transition)
                #expect(!model.isLocating && model.locationFailure == failure)
                #expect(model.locationStatus.contains("cached location"))
                #expect(model.locationStatus.contains("40.713") && model.locationStatus.contains("-74.006"))
                #expect(!model.locationStatus.contains("Tokyo"))
            }
            // A provider without an attached fallback must not discard the last successful fix either.
            location.onEvent?(.failed(.timeout))
            #expect(model.city == newYork)
            location.onEvent?(.resolved(City.all[0]))
            #expect(model.locationFailure == nil && model.city == City.all[0])
            model.locationMode = .manual
            #expect(model.city.id == "Asia/Tokyo")
        }
    }

}
