import Foundation

public struct JourneyPoint: Codable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let timestamp: Date
    public let accuracy: Double
    public var segment: Int = 0
    public init(latitude: Double, longitude: Double, timestamp: Date, accuracy: Double) {
        self.latitude = latitude; self.longitude = longitude
        self.timestamp = timestamp; self.accuracy = accuracy
    }
    public func isFresh(at now: Date) -> Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) &&
        (-180...180).contains(longitude) && accuracy.isFinite && (0...100).contains(accuracy) &&
        (-5...15).contains(now.timeIntervalSince(timestamp))
    }
    public var mapsURL: URL {
        URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=Shared%20location")!
    }
    public var shareText: String {
        "My location · Saarthi\nUpdated \(timestamp.formatted(date: .abbreviated, time: .standard))\nGPS accuracy ±\(Int(accuracy)) m\n\(mapsURL.absoluteString)\nThis is a location snapshot."
    }
    public func distance(to other: Self) -> Double {
        let radians = Double.pi / 180
        let lat = (other.latitude - latitude) * radians
        let lon = (other.longitude - longitude) * radians
        let a = pow(sin(lat / 2), 2) + cos(latitude * radians) * cos(other.latitude * radians) * pow(sin(lon / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(min(1, a)), sqrt(max(0, 1 - a)))
    }
}

public struct Journey: Codable, Identifiable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public var endedAt: Date?
    public var points: [JourneyPoint] = []
    public var distanceMeters: Double = 0
    public var checkIns = 0
    public var alarms = 0
    private var segment = 0
    public init(startedAt: Date = Date()) { id = UUID(); self.startedAt = startedAt }
    public mutating func breakRoute() { segment += 1 }
    @discardableResult public mutating func append(_ input: JourneyPoint, now: Date) -> Bool {
        guard input.isFresh(at: now) else { return false }
        var point = input; point.segment = segment
        if let last = points.last {
            let elapsed = point.timestamp.timeIntervalSince(last.timestamp)
            guard elapsed > 0 else { return false }
            let distance = last.distance(to: point)
            // Do not draw or count unobserved travel during a long GPS gap.
            if elapsed > 60 && last.segment == segment { breakRoute(); point.segment = segment }
            if last.segment == point.segment {
                guard distance / elapsed < 55 else { return false }
                guard distance >= 15 || elapsed >= 60 else { return false }
                distanceMeters += distance
            }
        }
        points.append(point)
        // Bound storage for very long sessions, preserving segment boundaries.
        if points.count > 12_000 {
            points = points.enumerated().filter { index, point in
                index == 0 || index == points.count - 1 || index % 2 == 0 ||
                point.segment != points[index - 1].segment || point.segment != points[index + 1].segment
            }.map(\.element)
        }
        return true
    }
    public var distanceLabel: String { String(format: "%.1f km", distanceMeters / 1000) }
    public var durationLabel: String {
        let minutes = max(0, Int((endedAt ?? points.last?.timestamp ?? startedAt).timeIntervalSince(startedAt) / 60))
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
    public var shareText: String {
        var text = "Saarthi journey · \(startedAt.formatted(date: .abbreviated, time: .shortened))\nRecorded distance: \(distanceLabel) · Duration: \(durationLabel)\nCheck-ins: \(checkIns) · Alarms: \(alarms)"
        if let point = points.last { text += "\nLast recorded location: \(point.mapsURL.absoluteString)\nRecorded \(point.timestamp.formatted(date: .abbreviated, time: .standard))" }
        return text + "\nForeground GPS recording; gaps may omit travel."
    }
}
