import Foundation

public enum SolarCondition: String, Sendable { case normal, polarDay, polarNight }

public struct SolarDay: Sendable {
    public let sunrise: Date?
    public let sunset: Date?
    public let condition: SolarCondition
}

/// Meeus/NOAA solar coordinates; standard apparent horizon is -0.833 degrees.
/// No weather, terrain or elevation correction. All intermediate times are UTC.
public struct SolarCalculator: Sendable {
    public init() {}
    private func radians(_ x: Double) -> Double { x * .pi / 180 }
    private func degrees(_ x: Double) -> Double { x * 180 / .pi }
    private func normalized(_ x: Double) -> Double { (x.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }

    private func coordinates(at date: Date) -> (declination: Double, equation: Double) {
        let t = (date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545) / 36525
        let l = radians(normalized(280.46646 + t * (36000.76983 + t * 0.0003032)))
        let m = radians(357.52911 + t * (35999.05029 - 0.0001537 * t))
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2*m) * (0.019993 - 0.000101 * t) + sin(3*m) * 0.000289
        let omega = radians(125.04 - 1934.136 * t)
        let lambda = l + radians(c - 0.00569 - 0.00478 * sin(omega))
        let seconds = 21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))
        let epsilon = radians(23 + (26 + seconds / 60) / 60 + 0.00256 * cos(omega))
        let declination = asin(sin(epsilon) * sin(lambda))
        let y = pow(tan(epsilon / 2), 2)
        let eq = y*sin(2*l) - 2*e*sin(m) + 4*e*y*sin(m)*cos(2*l)
            - 0.5*y*y*sin(4*l) - 1.25*e*e*sin(2*m)
        return (declination, 4 * degrees(eq))
    }

    private func horizonDistance(at date: Date, city: City) -> Double {
        let c = coordinates(at: date)
        let utcSeconds = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400)
        let hourAngle = radians((utcSeconds / 60 + c.equation + 4 * city.longitude) / 4 - 180)
        let lat = radians(city.latitude)
        let sineAltitude = sin(lat)*sin(c.declination) + cos(lat)*cos(c.declination)*cos(hourAngle)
        return sineAltitude - sin(radians(-0.833))
    }

    public func isDaylight(at date: Date, city: City) -> Bool {
        horizonDistance(at: date, city: city) >= 0
    }

    public func day(containing date: Date, city: City) -> SolarDay {
        var local = Calendar(identifier: .gregorian); local.timeZone = city.timeZone
        let start = local.startOfDay(for: date)
        let end = local.date(byAdding: .day, value: 1, to: start)!
        let duration = end.timeIntervalSince(start)
        func value(_ seconds: Double) -> Double {
            horizonDistance(at: start.addingTimeInterval(seconds), city: city)
        }

        // Numerical work happens only during recalculation, never as a polling
        // loop. Include extrema so even a very short polar night is bracketed.
        let step = 1800.0
        let samples = stride(from: -step, through: duration + step, by: step).map { ($0, value($0)) }
        var points = [0.0, duration]
        points += samples.map(\.0).filter { $0 > 0 && $0 < duration }
        for index in 1..<(samples.count - 1) {
            let previous = samples[index - 1], current = samples[index], next = samples[index + 1]
            let maximum = current.1 > previous.1 && current.1 > next.1
            let minimum = current.1 < previous.1 && current.1 < next.1
            guard maximum || minimum else { continue }
            var lower = previous.0, upper = next.0
            for _ in 0..<40 {
                let left = lower + (upper - lower) / 3
                let right = upper - (upper - lower) / 3
                if (value(left) < value(right)) == maximum { lower = left } else { upper = right }
            }
            let extremum = (lower + upper) / 2
            if extremum > 0 && extremum < duration { points.append(extremum) }
        }
        points.sort()
        var rises: [Date] = [], sets: [Date] = []
        for (left, right) in zip(points, points.dropFirst()) {
            let leftDay = value(left) >= 0
            guard leftDay != (value(right) >= 0) else { continue }
            var lower = left, upper = right
            while upper - lower > 0.01 {
                let middle = (lower + upper) / 2
                if (value(middle) >= 0) == leftDay { lower = middle } else { upper = middle }
            }
            let event = start.addingTimeInterval((lower + upper) / 2)
            guard event >= start, event < end else { continue }
            if leftDay { sets.append(event) } else { rises.append(event) }
        }
        let condition: SolarCondition = rises.isEmpty && sets.isEmpty
            ? (value(duration / 2) >= 0 ? .polarDay : .polarNight) : .normal
        return SolarDay(sunrise: rises.first, sunset: sets.first, condition: condition)
    }
}
