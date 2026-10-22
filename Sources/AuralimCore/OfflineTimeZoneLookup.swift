import Foundation
import CZoneDetect

/// Polygon lookup using the bundled ZoneDetect database. No network or system
/// time-zone assumptions. Ambiguous borders and missing data return nil.
public final class OfflineTimeZoneLookup {
    private let database: OpaquePointer

    public init?() {
        let bundled = Bundle.main.url(forResource: "Auralim_AuralimCore", withExtension: "bundle")
            .flatMap(Bundle.init(url:))
        let resources = bundled ?? Bundle.module
        guard let path = resources.path(forResource: "timezone21", ofType: "bin"),
              let database = ZDOpenDatabase(path) else { return nil }
        self.database = database
    }

    public func timeZone(latitude: Double, longitude: Double) -> TimeZone? {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              let results = ZDLookup(database, Float(latitude), Float(longitude), nil) else { return nil }
        defer { ZDFreeResults(results) }
        var identifiers: Set<String> = []
        var index = 0
        while results[index].lookupResult != ZD_LOOKUP_END {
            let result = results[index]
            guard result.lookupResult != ZD_LOOKUP_PARSE_ERROR else { return nil }
            if result.lookupResult == ZD_LOOKUP_IN_ZONE || result.lookupResult == ZD_LOOKUP_ON_BORDER_VERTEX || result.lookupResult == ZD_LOOKUP_ON_BORDER_SEGMENT {
                var prefix: String?, name: String?
                for field in 0..<Int(result.numFields) {
                    guard let key = result.fieldNames?[field], let value = result.data?[field] else { continue }
                    switch String(cString: key) {
                    case "TimezoneIdPrefix": prefix = String(cString: value)
                    case "TimezoneId": name = String(cString: value)
                    default: break
                    }
                }
                if let prefix, let name { identifiers.insert(prefix + name) }
            }
            index += 1
        }
        guard identifiers.count == 1, let identifier = identifiers.first else { return nil }
        return TimeZone(identifier: identifier)
    }

    deinit { ZDCloseDatabase(database) }
}
