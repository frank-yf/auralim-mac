import Foundation

public enum Appearance: String, Sendable { case light, dark }
public struct Transition: Equatable, Sendable {
    public let date: Date
    public let appearance: Appearance
}
public struct Schedule: Sendable {
    public let appearance: Appearance
    public let nextTransition: Transition?
    public let nextCheck: Date
    public let today: SolarDay
    public let offsetWasClipped: Bool
}

public struct ScheduleEngine: Sendable {
    public init() {}
    public func evaluate(now: Date, city: City, sunsetOffset: Int) -> Schedule {
        let offset = Double(min(120, max(-120, sunsetOffset))) * 60
        let solar = SolarCalculator()
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = city.timeZone
        let start = calendar.startOfDay(for: now)
        let days = (-3...3).map { solar.day(containing: calendar.date(byAdding: .day, value: $0, to: start)!, city: city) }
        let rises = days.compactMap(\.sunrise).sorted()
        let sets = days.compactMap(\.sunset).sorted()
        var events = rises.map { Transition(date: $0, appearance: .light) }
        var clipped = false
        for sunset in sets {
            var effective = sunset.addingTimeInterval(offset)
            if let nextRise = rises.first(where: { $0 > sunset }), effective >= nextRise {
                clipped = true; continue
            }
            if let previousRise = rises.last(where: { $0 < sunset }), effective < previousRise {
                effective = previousRise; clipped = true
            }
            events.append(Transition(date: effective, appearance: .dark))
        }
        events.sort { $0.date == $1.date ? $0.appearance == .light && $1.appearance == .dark : $0.date < $1.date }
        // A clipped sunset can coincide with sunrise. The final state at that
        // instant wins; do not advertise a zero-duration light interval.
        var merged: [Transition] = []
        for event in events {
            if merged.last?.date == event.date { merged.removeLast() }
            merged.append(event)
        }
        events = merged
        let current = events.last(where: { $0.date <= now })?.appearance
            ?? (solar.isDaylight(at: now, city: city) ? .light : .dark)
        let next = events.first(where: { $0.date > now && $0.appearance != current })
        let midnight = calendar.date(byAdding: .day, value: 1, to: start)!
        return Schedule(appearance: current, nextTransition: next,
                        nextCheck: min(next?.date ?? midnight, midnight),
                        today: days[3], offsetWasClipped: clipped)
    }
}
