import Testing
import Foundation
@testable import AuralimCore

final class ScheduleTests {
    let engine = ScheduleEngine()
    let solar = SolarCalculator()
    let shanghai = City.all[0]
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test
    func testEveryOffsetBoundaryIncludingExtremes() throws {
        let day = solar.day(containing: date("2026-10-22T04:00:00Z"), city: shanghai)
        for offset in [-120, -60, -1, 0, 1, 60, 120] {
            let switchTime = try #require(day.sunset).addingTimeInterval(Double(offset)*60)
            let before = engine.evaluate(now: switchTime.addingTimeInterval(-1), city: shanghai, sunsetOffset: offset)
            let after = engine.evaluate(now: switchTime, city: shanghai, sunsetOffset: offset)
            #expect(before.appearance == .light)
            #expect(before.nextTransition?.date == switchTime)
            #expect(after.appearance == .dark)
            #expect(after.nextCheck > switchTime)
        }
    }

    @Test
    func testSunriseIsNotShifted() throws {
        let rise = try #require(solar.day(containing: date("2026-10-22T04:00:00Z"), city: shanghai).sunrise)
        for offset in [-120, 0, 120] {
            #expect(engine.evaluate(now: rise.addingTimeInterval(-1), city: shanghai, sunsetOffset: offset).appearance == .dark)
            #expect(engine.evaluate(now: rise, city: shanghai, sunsetOffset: offset).appearance == .light)
        }
    }

    @Test
    func testIndependentSunriseAndSunsetOffsets() throws {
        let day = solar.day(containing: date("2026-10-22T04:00:00Z"), city: shanghai)
        for riseOffset in [-120, -1, 0, 1, 120] {
            for setOffset in [-120, 0, 120] {
                let rise = try #require(day.sunrise).addingTimeInterval(Double(riseOffset) * 60)
                let set = try #require(day.sunset).addingTimeInterval(Double(setOffset) * 60)
                let beforeRise = engine.evaluate(now: rise.addingTimeInterval(-1), city: shanghai, sunriseOffset: riseOffset, sunsetOffset: setOffset)
                let atRise = engine.evaluate(now: rise, city: shanghai, sunriseOffset: riseOffset, sunsetOffset: setOffset)
                let beforeSet = engine.evaluate(now: set.addingTimeInterval(-1), city: shanghai, sunriseOffset: riseOffset, sunsetOffset: setOffset)
                let atSet = engine.evaluate(now: set, city: shanghai, sunriseOffset: riseOffset, sunsetOffset: setOffset)
                #expect(beforeRise.appearance == .dark)
                #expect(beforeRise.nextTransition?.date == rise)
                #expect(atRise.appearance == .light)
                #expect(beforeSet.appearance == .light)
                #expect(beforeSet.nextTransition?.date == set)
                #expect(atSet.appearance == .dark)
                #expect(atRise.todayLightTime == rise)
                #expect(atRise.todayDarkTime == set)
            }
        }
    }

    @Test
    func testSliderDirectionsProduceRequestedAppearances() throws {
        let day = solar.day(containing: date("2026-10-22T04:00:00Z"), city: shanghai)
        let rise = try #require(day.sunrise)
        let set = try #require(day.sunset)
        let left = SolarOffset.minutes(forSliderPosition: -30)
        let right = SolarOffset.minutes(forSliderPosition: 30)
        #expect(engine.evaluate(now: rise, city: shanghai, sunriseOffset: left, sunsetOffset: 0).appearance == .dark)
        #expect(engine.evaluate(now: rise, city: shanghai, sunriseOffset: right, sunsetOffset: 0).appearance == .light)
        #expect(engine.evaluate(now: set, city: shanghai, sunriseOffset: 0, sunsetOffset: left).appearance == .light)
        #expect(engine.evaluate(now: set, city: shanghai, sunriseOffset: 0, sunsetOffset: right).appearance == .dark)
    }

    @Test
    func testShortNightUsesAdjustedNextSunrise() throws {
        let city = City(id: "Europe/Helsinki", name: "Oulu", latitude: 65.0121, longitude: 25.4651)
        let day = solar.day(containing: date("2026-06-21T12:00:00Z"), city: city)
        let sunset = try #require(day.sunset)
        let now = sunset.addingTimeInterval(125 * 60)
        // Delaying sunrise restores a valid night that would otherwise be skipped.
        let state = engine.evaluate(now: now, city: city, sunriseOffset: 120, sunsetOffset: 120)
        #expect(state.appearance == .dark)
        #expect(state.nextTransition?.date == day.sunrise?.addingTimeInterval(120 * 60))
    }

    @Test
    func testWakeAfterSunsetOrSeveralDaysUsesCurrentState() {
        #expect(engine.evaluate(now: date("2026-10-22T04:00:00Z"), city: shanghai, sunsetOffset: 0).appearance == .light)
        #expect(engine.evaluate(now: date("2026-10-22T14:00:00Z"), city: shanghai, sunsetOffset: 0).appearance == .dark)
        #expect(engine.evaluate(now: date("2026-10-26T04:00:00Z"), city: shanghai, sunsetOffset: 0).appearance == .light)
    }

    @Test
    func testCityChangeImmediatelyChangesTarget() {
        let now = date("2026-10-22T04:00:00Z")
        let newYork = City.all.first { $0.id == "America/New_York" }!
        #expect(engine.evaluate(now: now, city: shanghai, sunsetOffset: 0).appearance == .light)
        #expect(engine.evaluate(now: now, city: newYork, sunsetOffset: 0).appearance == .dark)
    }

    @Test
    func testOffsetIsClamped() {
        let now = date("2026-10-22T04:00:00Z")
        #expect(engine.evaluate(now: now, city: shanghai, sunsetOffset: 999).nextTransition == engine.evaluate(now: now, city: shanghai, sunsetOffset: 120).nextTransition)
        #expect(engine.evaluate(now: now, city: shanghai, sunsetOffset: -999).nextTransition == engine.evaluate(now: now, city: shanghai, sunsetOffset: -120).nextTransition)
    }

    @Test
    func testPolarStatesScheduleFutureMaintenance() {
        let tromso = City.all.first { $0.id == "Europe/Oslo" }!
        for (text, expected) in [("2026-06-21T12:00:00Z", Appearance.light), ("2026-12-21T12:00:00Z", Appearance.dark)] {
            let now = date(text)
            let state = engine.evaluate(now: now, city: tromso, sunsetOffset: 120)
            #expect(state.appearance == expected)
            #expect(state.nextTransition == nil)
            #expect(state.nextCheck > now)
            #expect(state.nextCheck.timeIntervalSince(now) <= 25*3600)
        }
    }

    @Test
    func testDSTAndYearBoundaryAlwaysScheduleForward() {
        for city in City.all {
            for text in ["2026-03-08T06:59:59Z", "2026-11-01T05:59:59Z", "2026-12-31T23:59:59Z"] {
                let now = date(text)
                let state = engine.evaluate(now: now, city: city, sunsetOffset: -120)
                #expect(state.nextCheck > now)
                if let next = state.nextTransition { #expect(next.date > now) }
            }
        }
    }

    @Test
    func testDelayedSunsetCanCrossLocalMidnight() throws {
        let city = City(id: "Europe/Helsinki", name: "Oulu", latitude: 65.0121, longitude: 25.4651)
        let day = solar.day(containing: date("2026-05-20T12:00:00Z"), city: city)
        let delayed = try #require(day.sunset).addingTimeInterval(120*60)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = city.timeZone
        #expect(!(calendar.isDate(delayed, inSameDayAs: try #require(day.sunset))))
        #expect(engine.evaluate(now: delayed.addingTimeInterval(-1), city: city, sunsetOffset: 120).appearance == .light)
        #expect(engine.evaluate(now: delayed, city: city, sunsetOffset: 120).appearance == .dark)
    }

    @Test
    func testDelayPastNextSunriseSkipsShortNight() throws {
        let city = City(id: "Europe/Helsinki", name: "Oulu", latitude: 65.0121, longitude: 25.4651)
        let day = solar.day(containing: date("2026-06-21T12:00:00Z"), city: city)
        let sunset = try #require(day.sunset)
        let sunrise = try #require(day.sunrise)
        #expect(sunrise > sunset)
        #expect(sunrise.timeIntervalSince(sunset) < 120*60)
        let state = engine.evaluate(now: sunset.addingTimeInterval(30*60), city: city, sunsetOffset: 120)
        #expect(state.offsetWasClipped)
        #expect(state.appearance == .light)
        #expect(state.todayDarkTime == nil)
    }
}
