import Foundation

@main
struct MotionChecks {
    static func main() {
        let origin = MotionPoint(latitude: 31.23, longitude: 121.47)
        let end = origin.offset(east: 10, north: 0)
        // Many short segments and duplicate points must not add artificial waiting time.
        let points = [origin, origin] + (1...100).map { origin.interpolated(to: end, fraction: Double($0) / 100) } + [end]
        var route = RoutePlayback(points: points)!
        for _ in 0..<19 { route.advance(meters: 0.5) }
        assert(!route.finished)
        assert(abs(origin.distance(to: route.position) - 9.5) < 0.00001)
        route.advance(meters: 0.50001)
        assert(route.finished && route.position == end)
        route.advance(meters: 100)
        assert(route.position == end)

        // The same elapsed-time budget works with very slow custom speeds and live changes.
        var slow = RoutePlayback(points: [origin, end])!
        slow.advance(meters: (0.1 / 3.6) * 0.25)
        assert(abs(origin.distance(to: slow.position) - 0.1 / 3.6 * 0.25) < 0.00001)
        slow.advance(meters: (36.0 / 3.6) * 0.25)
        assert(abs(origin.distance(to: slow.position) - (2.5 + 0.1 / 3.6 * 0.25)) < 0.00001)
        assert(RoutePlayback(points: [origin]) == nil)
        assert(RoutePlayback(points: [origin, MotionPoint(latitude: .nan, longitude: 0)]) == nil)
        var duplicate = RoutePlayback(points: [origin, origin, origin])!
        duplicate.advance(meters: 0)
        assert(duplicate.finished)

        // Pause/stop retain the center and progress; neither consumes a queued tick.
        var simulation = RouteSimulation()
        assert(simulation.start(points: [origin, end]))
        simulation.advance(meters: 2)
        assert(simulation.phase == .running && simulation.canStop)
        let held = simulation.position
        let heldProgress = simulation.progress
        simulation.pause()
        simulation.pause()
        for _ in 0..<100 { simulation.advance(meters: 100_000) }
        assert(simulation.phase == .paused && simulation.position == held)
        assert(simulation.progress == heldProgress)
        simulation.resume()
        simulation.advance(meters: 1)
        assert(abs(origin.distance(to: simulation.position!) - 3) < 0.00001)
        simulation.pause()
        simulation.stop()
        let stopped = simulation.position
        simulation.resume()
        simulation.advance(meters: 100)
        assert(simulation.phase == .stopped && !simulation.canStop && simulation.position == stopped)
        assert(!simulation.start(points: [origin]))
        assert(simulation.phase == .stopped && simulation.position == stopped)
        assert(simulation.start(points: [end, origin]))
        simulation.advance(meters: 100)
        assert(simulation.phase == .completed && simulation.position == origin && simulation.progress == 1)
        simulation.resume()
        assert(simulation.phase == .completed)
        simulation.clear()
        assert(simulation.phase == .idle && simulation.position == nil && simulation.path.isEmpty)
        assert(simulation.start(points: [origin, origin]))
        assert(simulation.phase == .completed && simulation.progress == 1)

        // Joining legs preserves visit order and shared endpoints, including a return trip.
        let middle = origin.offset(east: 5, north: 0)
        let connected = RouteGeometry.joined([[origin, middle], [middle, end], [end, middle, origin]])
        assert(connected == [origin, middle, end, middle, origin])
        assert(RouteGeometry.joined([]).isEmpty)
        assert(RouteGeometry.distinctStops([origin, origin, middle, middle, end, origin]) == [origin, middle, end, origin])
        var connectedPlayback = RouteSimulation()
        assert(connectedPlayback.start(points: connected))
        assert(abs(connectedPlayback.totalDistance - 20) < 0.00001)
        connectedPlayback.advance(meters: 12)
        assert(abs(connectedPlayback.progress - 0.6) < 0.00001)
        assert(abs(origin.distance(to: connectedPlayback.position!) - 8) < 0.00001)
        connectedPlayback.advance(meters: 8.00001)
        assert(connectedPlayback.phase == .completed && connectedPlayback.position == origin)
        var stops = [RouteStop(point: origin, name: "A"), RouteStop(point: middle, name: "B"), RouteStop(point: end, name: "C")]
        let firstID = stops[0].id
        stops.swapAt(0, 2)
        assert(stops[2].id == firstID && stops.map(\.name) == ["C", "B", "A"])

        let crossing = MotionPoint(latitude: 0, longitude: 179.99999)
        let across = crossing.offset(east: 10, north: 0)
        assert(abs(crossing.distance(to: across) - 10) < 0.00001)
        assert(across.longitude < 0)
        let pole = MotionPoint(latitude: 90, longitude: 0).offset(east: 1, north: 1)
        assert(pole.latitude.isFinite && pole.longitude.isFinite)

        var settings = MotionSettings()
        assert(!settings.driftEnabled && settings.driftRadius == 3)
        assert(settings.speedVariationEnabled && settings.speedVariationPercent == 10)
        assert(settings.customSpeedKPH == 5 && !settings.customRoadDriving)
        settings.driftEnabled = true
        settings.speedVariationPercent = 90
        var noise = MotionVariation()
        var rng = SeededRandom()
        for _ in 0..<10_000 {
            let sample = noise.update(seconds: 0.25, settings: settings, random: { rng.next() })
            assert(hypot(sample.east, sample.north) <= 3.00000001)
            let output = origin.offset(east: sample.east, north: sample.north)
            assert(origin.distance(to: output) <= 3.0000001)
            assert(sample.multiplier >= 0.1 - 1e-12 && sample.multiplier <= 1.9 + 1e-12)
        }
        // Lowering the radius is effective immediately, even mid-transition.
        settings.driftRadius = 1
        let smaller = noise.update(seconds: 0.25, settings: settings, random: { rng.next() })
        assert(hypot(smaller.east, smaller.north) <= 1.00000001)
        settings.driftEnabled = false
        settings.speedVariationEnabled = false
        let off = noise.update(seconds: 0.25, settings: settings)
        assert(off.east == 0 && off.north == 0 && off.multiplier == 1)
        settings.speedVariationEnabled = true
        settings.speedVariationPercent = 0
        assert(noise.update(seconds: 1, settings: settings).multiplier == 1)
        // Smoothstep must not jump straight to a new random target.
        settings.driftEnabled = true
        var smooth = MotionVariation()
        let first = smooth.update(seconds: 0.25, settings: settings, random: { 1 })
        assert(hypot(first.east, first.north) > 0 && hypot(first.east, first.north) < 0.1)

        let suite = "locus.motionChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        assert(MotionSettings.load(from: defaults) == MotionSettings())
        settings.customSpeedKPH = 17.4
        settings.save(to: defaults)
        assert(MotionSettings.load(from: defaults) == settings)
        settings.customSpeedKPH = .nan
        settings.driftRadius = -5
        settings.speedVariationPercent = .infinity
        settings.save(to: defaults)
        let sanitized = MotionSettings.load(from: defaults)
        assert(sanitized.customSpeedKPH == 5 && sanitized.driftRadius == 1 && sanitized.speedVariationPercent == 10)
        defaults.set(Data("invalid".utf8), forKey: MotionSettings.defaultsKey)
        assert(MotionSettings.load(from: defaults) == MotionSettings())
        print("Motion checks passed (pause/resume/stop, connected routes, timing, drift, persistence, edge cases)")
    }
}

private struct SeededRandom {
    var state: UInt64 = 42
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}
