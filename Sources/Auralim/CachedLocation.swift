import Foundation
import AuralimCore

enum LocationPolicy {
    static let refreshInterval: TimeInterval = 3 * 3600
}

struct CachedLocation: Codable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date
    let timeZoneID: String

    init(sample: LocationSample, timeZone: TimeZone) {
        latitude = sample.latitude
        longitude = sample.longitude
        accuracy = sample.accuracy
        timestamp = sample.timestamp
        timeZoneID = timeZone.identifier
    }

    var city: City? {
        guard latitude.isFinite, longitude.isFinite, accuracy.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              (0...20_000).contains(accuracy), TimeZone(identifier: timeZoneID) != nil else { return nil }
        return City(id: "current-location", name: "", latitude: latitude,
                    longitude: longitude, timeZoneID: timeZoneID)
    }

    func usableCity(at now: Date) -> City? {
        let age = now.timeIntervalSince(timestamp)
        guard age.isFinite, age >= -60 else { return nil }
        return city
    }

    func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        return usableCity(at: now) != nil && age < LocationPolicy.refreshInterval
    }
}
