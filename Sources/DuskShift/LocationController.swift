import CoreLocation
import Network
import DuskShiftCore

enum LocationMode: String, CaseIterable, Identifiable {
    case manual, automatic
    var id: String { rawValue }
}

enum LocationFailure: String, Error {
    case denied, servicesDisabled, unavailable, timeout, timeZoneUnavailable
    var localizationKey: String { "location.error." + rawValue }
}

enum LocationEvent {
    case locating, resolved(City), failed(LocationFailure)
}

@MainActor
protocol LocationProviding: AnyObject {
    var onEvent: ((LocationEvent) -> Void)? { get set }
    func start()
    func refresh()
    func stop()
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

/// Uses significant-change notifications where supported, one-shot fixes on
/// network/wake/activation events otherwise. Never starts continuous updates.
@MainActor
// Managers are created on the main run loop, where Core Location delivers
// their delegate callbacks. The SDK's delegate protocol predates actor isolation.
final class LocationController: NSObject, LocationProviding, @preconcurrency CLLocationManagerDelegate {
    var onEvent: ((LocationEvent) -> Void)?
    private var manager: CLLocationManager?
    private var network: NWPathMonitor?
    private var timeout: Timer?
    private var pending = false
    private var monitoring = false
    private var lastRequest: Date?
    private var requestGeneration = 0
    private lazy var timeZones = OfflineTimeZoneLookup()

    func start() {
        guard manager == nil else { refresh(); return }
        let manager = CLLocationManager()
        self.manager = manager
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        let network = NWPathMonitor()
        network.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.requestFix(force: false) }
        }
        self.network = network
        network.start(queue: DispatchQueue(label: "app.duskshift.location-network", qos: .utility))
        requestFix(force: true)
    }

    func refresh() { requestFix(force: true) }

    private func requestFix(force: Bool) {
        guard let manager, !pending else { return }
        if !force, let lastRequest, Date().timeIntervalSince(lastRequest) < 60 { return }
        guard CLLocationManager.locationServicesEnabled() else { fail(.servicesDisabled); return }
        switch manager.authorizationStatus {
        case .denied, .restricted: fail(.denied)
        case .notDetermined:
            onEvent?(.locating)
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways:
            pending = true
            requestGeneration += 1
            let generation = requestGeneration
            lastRequest = Date()
            onEvent?(.locating)
            if !monitoring, CLLocationManager.significantLocationChangeMonitoringAvailable() {
                monitoring = true
                manager.startMonitoringSignificantLocationChanges()
            }
            timeout?.invalidate()
            let deadline = Timer(timeInterval: 30, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.pending, self.requestGeneration == generation else { return }
                    self.fail(.timeout)
                }
            }
            timeout = deadline
            RunLoop.main.add(deadline, forMode: .common)
            manager.requestLocation()
        @unknown default: fail(.unavailable)
        }
    }

    func stop() {
        requestGeneration += 1
        timeout?.invalidate(); timeout = nil
        network?.cancel(); network = nil
        manager?.delegate = nil
        manager?.stopUpdatingLocation()
        manager?.stopMonitoringSignificantLocationChanges()
        manager = nil; pending = false; monitoring = false; lastRequest = nil
    }

    private func fail(_ error: LocationFailure) {
        guard manager != nil else { return }
        requestGeneration += 1
        timeout?.invalidate(); timeout = nil; pending = false
        manager?.stopUpdatingLocation()
        if error == .denied || error == .servicesDisabled {
            manager?.stopMonitoringSignificantLocationChanges(); monitoring = false
        }
        onEvent?(.failed(error))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === self.manager else { return }
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            fail(.denied); return
        }
        requestFix(force: true)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === self.manager else { return }
        guard let sample = locations.reversed().map({
            LocationSample(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                           accuracy: $0.horizontalAccuracy, timestamp: $0.timestamp)
        }).first(where: { $0.isUsable(at: Date()) }) else {
            requestFix(force: false); return
        }
        requestGeneration += 1
        timeout?.invalidate(); timeout = nil; pending = false
        guard let zone = timeZones?.timeZone(latitude: sample.latitude, longitude: sample.longitude) else {
            fail(.timeZoneUnavailable); return
        }
        onEvent?(.resolved(City(id: "current-location", name: "", latitude: sample.latitude,
                               longitude: sample.longitude, timeZoneID: zone.identifier)))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === self.manager else { return }
        fail((error as? CLError)?.code == .denied ? .denied : .unavailable)
    }
}
