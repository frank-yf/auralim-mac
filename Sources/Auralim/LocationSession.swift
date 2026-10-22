import CoreLocation

enum LocationSessionEvent {
    case authorizationChanged
    case locations([LocationSample])
    case failed(Error)
}

/// A small boundary around Core Location so request recovery can be checked
/// without contacting the system location service.
@MainActor
protocol LocationSession: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var onEvent: ((LocationSessionEvent) -> Void)? { get set }
    func requestAuthorization()
    func requestLocation()
    func stopUpdates()
    func invalidate()
}

@MainActor
final class CoreLocationSession: NSObject, LocationSession, @preconcurrency CLLocationManagerDelegate {
    private let manager: CLLocationManager
    var onEvent: ((LocationSessionEvent) -> Void)?
    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
    }

    func requestAuthorization() { manager.requestWhenInUseAuthorization() }
    func requestLocation() { manager.requestLocation() }
    func stopUpdates() { manager.stopUpdatingLocation() }
    func invalidate() {
        manager.delegate = nil
        manager.stopUpdatingLocation()
        onEvent = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === self.manager else { return }
        onEvent?(.authorizationChanged)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === self.manager else { return }
        onEvent?(.locations(locations.map {
            LocationSample(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                           accuracy: $0.horizontalAccuracy, timestamp: $0.timestamp)
        }))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === self.manager else { return }
        onEvent?(.failed(error))
    }
}
