import Testing
import Foundation
@testable import DuskShiftCore

final class SolarTests {
    let solar = SolarCalculator()
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func city(_ id: String) -> City { City.all.first { $0.id == id }! }

    @Test
    func testGreenwichEquinoxReference() throws {
        // Standard apparent horizon, rounded reference values from Meeus/NOAA.
        let equator = City(id: "Etc/UTC", name: "Equator", latitude: 0, longitude: 0)
        let result = solar.day(containing: date("2024-03-20T12:00:00Z"), city: equator)
        #expect(abs((try #require(result.sunrise).timeIntervalSince(date("2024-03-20T06:04:00Z"))) - (0)) <= 90)
        #expect(abs((try #require(result.sunset).timeIntervalSince(date("2024-03-20T18:11:00Z"))) - (0)) <= 90)
    }

    @Test
    func testBeijingSolsticeReference() throws {
        let result = solar.day(containing: date("2024-06-21T04:00:00Z"), city: city("beijing"))
        #expect(abs((try #require(result.sunrise).timeIntervalSince(date("2024-06-20T20:46:00Z"))) - (0)) <= 120)
        #expect(abs((try #require(result.sunset).timeIntervalSince(date("2024-06-21T11:46:00Z"))) - (0)) <= 120)
    }

    @Test
    func testPolarDayAndNight() {
        let tromso = city("Europe/Oslo")
        let summer = solar.day(containing: date("2026-06-21T12:00:00Z"), city: tromso)
        let winter = solar.day(containing: date("2026-12-21T12:00:00Z"), city: tromso)
        #expect(summer.condition == .polarDay)
        #expect(summer.sunrise == nil); #expect(summer.sunset == nil)
        #expect(winter.condition == .polarNight)
        #expect(winter.sunrise == nil); #expect(winter.sunset == nil)
    }

    @Test
    func testSouthernHemisphereSeasons() throws {
        let sydney = city("Australia/Sydney")
        let summer = solar.day(containing: date("2026-12-21T02:00:00Z"), city: sydney)
        let winter = solar.day(containing: date("2026-06-21T02:00:00Z"), city: sydney)
        #expect(try #require(summer.sunset).timeIntervalSince(#require(summer.sunrise)) > 14*3600)
        #expect(try #require(winter.sunset).timeIntervalSince(#require(winter.sunrise)) < 10*3600)
    }

    @Test
    func testEventsBelongToSelectedLocalDayAcrossDateLineAndDST() throws {
        let cities = City.all + [City(id: "Pacific/Kiritimati", name: "Kiritimati", latitude: 1.8721, longitude: -157.4278)]
        for location in cities {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = location.timeZone
            for text in ["2024-02-29T12:00:00Z", "2026-03-08T12:00:00Z", "2026-11-01T12:00:00Z", "2026-12-31T12:00:00Z"] {
                let now = date(text)
                let result = solar.day(containing: now, city: location)
                for event in [result.sunrise, result.sunset].compactMap({ $0 }) {
                    #expect(calendar.isDate(event, inSameDayAs: now), "\(location.name) \(text)")
                }
            }
        }
    }

    @Test
    func testCrossingsActuallyChangeDaylightAcrossYear() throws {
        for location in City.all {
            for month in 1...12 {
                let now = date(String(format: "2026-%02d-15T12:00:00Z", month))
                let day = solar.day(containing: now, city: location)
                if let rise = day.sunrise {
                    #expect(!(solar.isDaylight(at: rise.addingTimeInterval(-60), city: location)))
                    #expect(solar.isDaylight(at: rise.addingTimeInterval(60), city: location))
                }
                if let set = day.sunset {
                    #expect(solar.isDaylight(at: set.addingTimeInterval(-60), city: location))
                    #expect(!(solar.isDaylight(at: set.addingTimeInterval(60), city: location)))
                }
            }
        }
    }

    @Test
    func testPolarSeasonBoundariesDoNotLoseCrossings() {
        let location = city("Europe/Oslo")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = location.timeZone
        let first = calendar.startOfDay(for: date("2026-01-01T12:00:00Z"))
        for index in 0..<365 {
            let start = calendar.date(byAdding: .day, value: index, to: first)!
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            let result = solar.day(containing: start, city: location)
            var previous = solar.isDaylight(at: start, city: location)
            var time = start.addingTimeInterval(300)
            while time < end {
                let current = solar.isDaylight(at: time, city: location)
                if current != previous {
                    #expect((current ? result.sunrise : result.sunset) != nil, "Lost crossing on \(start), rising=\(current)")
                }
                previous = current; time = time.addingTimeInterval(300)
            }
        }
    }
}
