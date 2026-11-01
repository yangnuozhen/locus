import Foundation

/// Stored in user-facing units; calculations use meters and seconds.
struct MotionSettings: Codable, Equatable {
    var customSpeedKPH = 5.0
    var driftEnabled = false
    var driftRadius = 3.0
    var speedVariationEnabled = true
    var speedVariationPercent = 10.0
    var customRoadDriving = false

    static let defaultsKey = "locus.motionSettings"

    var normalized: MotionSettings {
        var copy = self
        copy.customSpeedKPH = Self.clamp(customSpeedKPH, to: 0.1...300, fallback: 5)
        copy.driftRadius = Self.clamp(driftRadius, to: 1...100, fallback: 3)
        copy.speedVariationPercent = Self.clamp(speedVariationPercent, to: 0...90, fallback: 10)
        return copy
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }

    static func load(from defaults: UserDefaults = .standard) -> MotionSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(MotionSettings.self, from: data) else {
            return MotionSettings()
        }
        return settings.normalized
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// Framework-independent geometry, also used by standalone checks on Linux/macOS.
struct MotionPoint: Equatable {
    var latitude: Double
    var longitude: Double

    private static let earth = 6_378_137.0

    func distance(to other: MotionPoint) -> Double {
        let a = latitude * .pi / 180
        let b = other.latitude * .pi / 180
        let dLat = b - a
        let dLon = (other.longitude - longitude) * .pi / 180
        let h = pow(sin(dLat / 2), 2) + cos(a) * cos(b) * pow(sin(dLon / 2), 2)
        return Self.earth * 2 * asin(sqrt(min(1, max(0, h))))
    }

    func offset(east: Double, north: Double) -> MotionPoint {
        let meters = hypot(east, north)
        guard meters > 0 else { return self }
        let bearing = atan2(east, north)
        let angular = meters / Self.earth
        let lat = latitude * .pi / 180
        let lon = longitude * .pi / 180
        let nextLat = asin(min(1, max(-1, sin(lat) * cos(angular) + cos(lat) * sin(angular) * cos(bearing))))
        let nextLon = lon + atan2(sin(bearing) * sin(angular) * cos(lat), cos(angular) - sin(lat) * sin(nextLat))
        return MotionPoint(latitude: nextLat * 180 / .pi,
                           longitude: (nextLon * 180 / .pi + 540).truncatingRemainder(dividingBy: 360) - 180)
    }

    func interpolated(to other: MotionPoint, fraction: Double) -> MotionPoint {
        let a = latitude * .pi / 180
        let b = other.latitude * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let bearing = atan2(sin(dLon) * cos(b), cos(a) * sin(b) - sin(a) * cos(b) * cos(dLon))
        let meters = distance(to: other) * fraction
        return offset(east: sin(bearing) * meters, north: cos(bearing) * meters)
    }
}

/// Carries unused travel distance across segment boundaries, including duplicate points.
struct RoutePlayback {
    private let points: [MotionPoint]
    private var index = 0
    private var segmentProgress = 0.0
    private(set) var position: MotionPoint
    var finished: Bool { index >= points.count - 1 }

    init?(points: [MotionPoint]) {
        guard points.count >= 2,
              points.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite &&
                  abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }) else { return nil }
        self.points = points
        position = points[0]
    }

    mutating func advance(meters: Double) {
        guard meters.isFinite, meters >= 0 else { return }
        var remaining = meters
        while !finished {
            let start = points[index]
            let end = points[index + 1]
            let length = start.distance(to: end)
            let needed = max(0, length - segmentProgress)
            if remaining >= needed {
                remaining -= needed
                index += 1
                segmentProgress = 0
                position = end
            } else {
                segmentProgress += remaining
                position = start.interpolated(to: end, fraction: segmentProgress / length)
                break
            }
        }
    }
}

/// Three-second smooth transitions. Drift is an offset from the ideal position,
/// never a random walk. A convex interpolation keeps it within the chosen disk.
struct MotionVariation {
    private var elapsed = 3.0
    private var from = (east: 0.0, north: 0.0, speed: 0.0)
    private var target = (east: 0.0, north: 0.0, speed: 0.0)
    private var current = (east: 0.0, north: 0.0, speed: 0.0)
    private var previousSettings: MotionSettings?

    mutating func update(seconds: Double, settings rawSettings: MotionSettings,
                         random: () -> Double = { Double.random(in: 0...1) }) -> (east: Double, north: Double, multiplier: Double) {
        let settings = rawSettings.normalized
        if settings != previousSettings {
            // Clear disabled states immediately; clamp retained offsets after a radius reduction.
            if !settings.driftEnabled {
                current.east = 0
                current.north = 0
            }
            let length = hypot(current.east, current.north)
            if length > settings.driftRadius {
                current.east *= settings.driftRadius / length
                current.north *= settings.driftRadius / length
            }
            current.speed = settings.speedVariationEnabled ? min(1, max(-1, current.speed)) : 0
            elapsed = 3
            previousSettings = settings
        }
        if elapsed >= 3 {
            from = current
            let radius = settings.driftEnabled ? sqrt(random()) * settings.driftRadius : 0
            let angle = random() * 2 * .pi
            target = (radius * cos(angle), radius * sin(angle), settings.speedVariationEnabled ? random() * 2 - 1 : 0)
            elapsed = 0
        }
        elapsed = min(3, elapsed + max(0, seconds))
        let t = elapsed / 3
        let smooth = t * t * (3 - 2 * t)
        current = (from.east + (target.east - from.east) * smooth,
                   from.north + (target.north - from.north) * smooth,
                   from.speed + (target.speed - from.speed) * smooth)
        return (current.east, current.north, 1 + current.speed * settings.speedVariationPercent / 100)
    }
}
