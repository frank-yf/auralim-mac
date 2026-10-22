import Foundation

public struct City: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let timeZoneID: String
    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID)! }

    public init(id: String, name: String, latitude: Double, longitude: Double, timeZoneID: String? = nil) {
        precondition(TimeZone(identifier: timeZoneID ?? id) != nil)
        precondition((-90...90).contains(latitude) && (-180...180).contains(longitude))
        self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude
        self.timeZoneID = timeZoneID ?? id
    }

    public static let all: [City] = [
        .init(id: "Asia/Shanghai", name: "上海", latitude: 31.2304, longitude: 121.4737),
        .init(id: "beijing", name: "北京", latitude: 39.9042, longitude: 116.4074, timeZoneID: "Asia/Shanghai"),
        .init(id: "shenzhen", name: "深圳", latitude: 22.5431, longitude: 114.0579, timeZoneID: "Asia/Shanghai"),
        .init(id: "chengdu", name: "成都", latitude: 30.5728, longitude: 104.0668, timeZoneID: "Asia/Shanghai"),
        .init(id: "Asia/Hong_Kong", name: "香港", latitude: 22.3193, longitude: 114.1694),
        .init(id: "Asia/Tokyo", name: "东京", latitude: 35.6762, longitude: 139.6503),
        .init(id: "Asia/Singapore", name: "新加坡", latitude: 1.3521, longitude: 103.8198),
        .init(id: "Europe/London", name: "伦敦", latitude: 51.5074, longitude: -0.1278),
        .init(id: "Europe/Paris", name: "巴黎", latitude: 48.8566, longitude: 2.3522),
        .init(id: "America/New_York", name: "纽约", latitude: 40.7128, longitude: -74.0060),
        .init(id: "America/Los_Angeles", name: "洛杉矶", latitude: 34.0522, longitude: -118.2437),
        .init(id: "Australia/Sydney", name: "悉尼", latitude: -33.8688, longitude: 151.2093),
        .init(id: "Pacific/Auckland", name: "奥克兰", latitude: -36.8485, longitude: 174.7633),
        .init(id: "Europe/Oslo", name: "特罗姆瑟", latitude: 69.6492, longitude: 18.9553)
    ]
}
