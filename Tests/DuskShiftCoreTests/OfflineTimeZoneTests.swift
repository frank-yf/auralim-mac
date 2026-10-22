import Foundation
import Testing
@testable import DuskShiftCore

struct OfflineTimeZoneTests {
    @Test func builtInCitiesMatchOfflineBoundaries() throws {
        let lookup = try #require(OfflineTimeZoneLookup())
        for city in City.all {
            #expect(lookup.timeZone(latitude: city.latitude, longitude: city.longitude)?.identifier == city.timeZoneID,
                    "\(city.name) must match its stored IANA zone")
        }
    }

    @Test func travelLocationsOutsideTheBuiltInList() throws {
        let lookup = try #require(OfflineTimeZoneLookup())
        let points: [(Double, Double, String)] = [
            (28.6139, 77.2090, "Asia/Kolkata"), (27.7172, 85.3240, "Asia/Kathmandu"),
            (21.3069, -157.8583, "Pacific/Honolulu"), (33.4484, -112.0740, "America/Phoenix"),
            (49.2827, -123.1207, "America/Vancouver"), (-33.9249, 18.4241, "Africa/Johannesburg"),
            (-34.6037, -58.3816, "America/Argentina/Buenos_Aires"), (41.0082, 28.9784, "Europe/Istanbul")
        ]
        for (latitude, longitude, identifier) in points {
            #expect(lookup.timeZone(latitude: latitude, longitude: longitude)?.identifier == identifier)
        }
    }

    @Test func nearbyLocationsAcrossABorderDoNotUseNearestCityOrLongitude() throws {
        let lookup = try #require(OfflineTimeZoneLookup())
        // Needles, California and Mohave Valley, Arizona are close together,
        // but only California observes daylight saving time.
        let california = try #require(lookup.timeZone(latitude: 34.8481, longitude: -114.6141))
        let arizona = try #require(lookup.timeZone(latitude: 34.9235, longitude: -114.5886))
        #expect(california.identifier == "America/Los_Angeles")
        #expect(arizona.identifier == "America/Phoenix")
        let summer = ISO8601DateFormatter().date(from: "2026-07-01T12:00:00Z")!
        let winter = ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z")!
        #expect(california.secondsFromGMT(for: summer) == arizona.secondsFromGMT(for: summer))
        #expect(california.secondsFromGMT(for: winter) != arizona.secondsFromGMT(for: winter))
    }

    @Test func invalidOrAmbiguousCoordinatesNeverBecomeGuessedZones() throws {
        let lookup = try #require(OfflineTimeZoneLookup())
        for (latitude, longitude) in [(Double.nan, 0.0), (0, Double.infinity), (91, 0), (0, -181)] {
            #expect(lookup.timeZone(latitude: latitude, longitude: longitude) == nil)
        }
        // The data contains overlapping Shanghai / Urumqi zones here.
        #expect(lookup.timeZone(latitude: 43.8256, longitude: 87.6168) == nil)
    }
}
