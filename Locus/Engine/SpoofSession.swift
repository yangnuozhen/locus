import CoreLocation
import Foundation
import MapKit
import UIKit
import UserNotifications

enum TravelMode: String, CaseIterable, Identifiable {
    case walk, run, cycle, drive, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return String(localized: "Walk")
        case .run: return String(localized: "Run")
        case .cycle: return String(localized: "Cycle")
        case .drive: return String(localized: "Drive")
        case .custom: return String(localized: "Custom")
        }
    }

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .cycle: return "bicycle"
        case .drive: return "car.fill"
        case .custom: return "speedometer"
        }
    }

    /// Base meters per second before natural variation.
    var baseSpeed: CLLocationSpeed {
        switch self {
        case .walk: return 1.4
        case .run: return 3.3
        case .cycle: return 6.5
        case .drive: return 13.4
        case .custom: return 5.0 / 3.6
        }
    }

    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .walk, .run, .custom: return .walking
        case .cycle, .drive: return .automobile
        }
    }
}

enum SpoofStatus: Equatable {
    case idle
    case connecting
    case active
    case reconnecting
    case dropped(String)

    var label: String {
        switch self {
        case .idle: return String(localized: "Not Spoofing")
        case .connecting: return String(localized: "Starting…")
        case .active: return String(localized: "Spoofing")
        case .reconnecting: return String(localized: "Reconnecting…")
        case .dropped: return String(localized: "Interrupted")
        }
    }

    var isDropped: Bool {
        if case .dropped = self { return true }
        return false
    }
}

@MainActor
final class SpoofSession: ObservableObject {
    @Published var status: SpoofStatus = .idle
    @Published var pin: CLLocationCoordinate2D?
    @Published var simulated: CLLocationCoordinate2D?
    @Published var travelMode: TravelMode = .walk {
        didSet { UserDefaults.standard.set(travelMode.rawValue, forKey: "locus.travelMode") }
    }
    @Published var motionSettings = MotionSettings.load() {
        didSet { motionSettings.save() }
    }
    /// Unperturbed source for movement, history, and route starts.
    private(set) var idealCoordinate: CLLocationCoordinate2D?

    var baseSpeed: Double {
        travelMode == .custom ? motionSettings.normalized.customSpeedKPH / 3.6 : travelMode.baseSpeed
    }

    var roadTransportType: MKDirectionsTransportType {
        travelMode == .custom ? (motionSettings.customRoadDriving ? .automobile : .walking) : travelMode.mkTransportType
    }
    @Published var mapStyleIndex: Int = 0
    @Published var lastError: String?
    @Published var isBusy = false
    @Published var joystickActive = false

    @Published var favorites: [SavedPlace] = []
    @Published var recents: [SavedPlace] = []

    private var resendTimer: Timer?
    private var healthTimer: Timer?
    private var motionTimer: Timer?
    @Published private(set) var routeSimulation = RouteSimulation()
    private var variation = MotionVariation()
    private var driftOffset = (east: 0.0, north: 0.0)
    private var lastMotionTime = ProcessInfo.processInfo.systemUptime
    private var generation = UUID()
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var joystickVector: CGVector = .zero
    private let locationKeeper = BackgroundKeepAlive()

    private let favoritesKey = "locus.favorites"
    private let recentsKey = "locus.recents"

    init() {
        favorites = SavedPlace.load(key: favoritesKey)
        recents = SavedPlace.load(key: recentsKey)
        travelMode = TravelMode(rawValue: UserDefaults.standard.string(forKey: "locus.travelMode") ?? "") ?? .walk
    }

    var isSpoofing: Bool {
        if case .active = status { return true }
        if case .reconnecting = status { return true }
        return false
    }

    func teleport(to coordinate: CLLocationCoordinate2D, pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = String(localized: "Import an RPPairing file in Settings first.")
            return
        }
        cancelMovement()
        variation = MotionVariation()
        driftOffset = (0, 0)
        apply(coordinate, pairing: pairing, markRecent: true)
    }

    func stop(pairing: PairingStore) {
        cancelMovement()
        motionTimer?.invalidate()
        motionTimer = nil
        generation = UUID()
        variation = MotionVariation()
        driftOffset = (0, 0)
        stopResend()
        stopHealth()
        isBusy = true
        let result = LocationEngine.clear()
        isBusy = false
        switch result {
        case .success:
            simulated = nil
            idealCoordinate = nil
            status = .idle
            endBackground()
            // Keep location updates running so the map puck / locate button
            // can return to the real GPS fix (not the leftover pin).
            locationKeeper.start()
        case .failure(let error):
            lastError = error.localizedDescription
            status = .dropped(error.localizedDescription)
            postDropNotification(error.localizedDescription)
            endBackground()
        }
    }

    /// Best-known real device coordinate (not the teleport pin).
    var realCoordinate: CLLocationCoordinate2D? {
        locationKeeper.lastKnownCoordinate
    }

    /// Start lightweight GPS updates for the map puck / locate button.
    func startLocationUpdates() {
        locationKeeper.start()
    }

    func startJoystick(pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = String(localized: "Import an RPPairing file in Settings first.")
            return
        }
        let start = idealCoordinate ?? pin ?? locationKeeper.lastKnownCoordinate
        guard let start else {
            lastError = String(localized: "Drop a pin or teleport somewhere before using the joystick.")
            return
        }
        cancelMovement()
        if simulated == nil || status.isDropped {
            apply(start, pairing: pairing, markRecent: false)
        }
        guard status == .active else { return }
        joystickActive = true
        lastMotionTime = ProcessInfo.processInfo.systemUptime
    }

    func updateJoystick(vector: CGVector) {
        joystickVector = vector
    }

    func stopJoystick() {
        joystickActive = false
        joystickVector = .zero
    }

    private func cancelMovement() {
        routeSimulation.clear()
        stopJoystick()
    }

    func followRoute(_ coordinates: [CLLocationCoordinate2D], pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = String(localized: "Import an RPPairing file in Settings first.")
            return
        }
        var next = RouteSimulation()
        guard next.start(points: coordinates.map(MotionPoint.init)) else { return }
        cancelMovement()
        apply(coordinates[0], pairing: pairing, markRecent: true)
        guard status == .active else { return }
        routeSimulation = next
        lastMotionTime = ProcessInfo.processInfo.systemUptime
    }

    func pauseRoute() {
        guard status == .active else { return }
        routeSimulation.pause()
        lastMotionTime = ProcessInfo.processInfo.systemUptime
    }

    func resumeRoute() {
        guard status == .active else { return }
        // Exclude the entire paused interval from the next movement tick.
        lastMotionTime = ProcessInfo.processInfo.systemUptime
        routeSimulation.resume()
    }

    func stopRoute() {
        routeSimulation.stop()
        lastMotionTime = ProcessInfo.processInfo.systemUptime
        // Keep the simulation, resend timer, health checks, and current ideal center.
    }

    private func interruptMovement() {
        routeSimulation.stop()
        stopJoystick()
    }

    func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        // Don't let a generic star overwrite a named favorite for the same spot.
        if let existing = favorites.first(where: { $0.id == place.id }),
           Self.isGenericFavoriteName(place.name),
           !Self.isGenericFavoriteName(existing.name) {
            return
        }
        favorites.removeAll { $0.id == place.id }
        favorites.insert(place, at: 0)
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func renameFavorite(_ place: SavedPlace, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        favorites[index].name = trimmed
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeFavorite(_ place: SavedPlace) {
        favorites.removeAll { $0.id == place.id }
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeRecent(_ place: SavedPlace) {
        recents.removeAll { $0.id == place.id }
        SavedPlace.save(recents, key: recentsKey)
    }

    /// Best display name for starring the current pin (search title, matching recent, etc.).
    func suggestedFavoriteName(for coordinate: CLLocationCoordinate2D, fallback: String? = nil) -> String {
        if let fallback, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let favorite = favorites.first(where: { $0.id == SavedPlace(name: "", latitude: coordinate.latitude, longitude: coordinate.longitude).id }),
           !Self.isGenericFavoriteName(favorite.name) {
            return favorite.name
        }
        if let recent = recents.first(where: {
            abs($0.latitude - coordinate.latitude) < 0.00015 && abs($0.longitude - coordinate.longitude) < 0.00015
        }), !Self.isGenericFavoriteName(recent.name) {
            return recent.name
        }
        return Self.coordinateLabel(coordinate)
    }

    private static func coordinateLabel(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private static func isGenericFavoriteName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Favorite" { return true }
        // Coordinate-looking labels from older teleports.
        let parts = trimmed.split(separator: ",")
        if parts.count == 2,
           Double(parts[0].trimmingCharacters(in: .whitespaces)) != nil,
           Double(parts[1].trimmingCharacters(in: .whitespaces)) != nil {
            return true
        }
        return false
    }

    private func apply(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore, markRecent: Bool) {
        if status == .idle || status.isDropped {
            status = .connecting
        }
        let output = MotionPoint(coordinate).offset(east: driftOffset.east, north: driftOffset.north).coordinate
        DeveloperTunnelMonitor.shared.prepareForSimulation()
        isBusy = true
        let result = LocationEngine.set(
            latitude: output.latitude,
            longitude: output.longitude,
            pairingPath: pairing.pairingPath,
            deviceIP: TunnelConfig.targetIP
        )
        isBusy = false
        switch result {
        case .success:
            simulated = output
            idealCoordinate = coordinate
            pin = coordinate
            status = .active
            lastError = nil
            beginBackground()
            locationKeeper.start()
            startResend(pairing: pairing)
            startHealth(pairing: pairing)
            startMotion(pairing: pairing)
            if markRecent {
                pushRecent(coordinate)
            }
        case .failure(let error):
            interruptMovement()
            lastError = error.localizedDescription
            if simulated != nil {
                status = .dropped(error.localizedDescription)
                postDropNotification(error.localizedDescription)
            } else {
                status = .idle
            }
        }
    }

    private func startMotion(pairing: PairingStore) {
        guard motionTimer == nil else { return }
        lastMotionTime = ProcessInfo.processInfo.systemUptime
        let token = generation
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.tickMotion(pairing: pairing)
            }
        }
        motionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tickMotion(pairing: PairingStore) {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = max(0, now - lastMotionTime)
        lastMotionTime = now
        guard status == .active, let ideal = idealCoordinate else { return }
        let noise = variation.update(seconds: dt, settings: motionSettings)
        let oldOffset = driftOffset
        driftOffset = (noise.east, noise.north)
        var next = MotionPoint(ideal)
        var moved = false
        var advancedRoute: RouteSimulation?
        if routeSimulation.phase == .running {
            var candidate = routeSimulation
            candidate.advance(meters: baseSpeed * noise.multiplier * dt)
            next = candidate.position ?? next
            advancedRoute = candidate
            moved = true
        } else if joystickActive {
            let magnitude = hypot(joystickVector.dx, joystickVector.dy)
            if magnitude > 0.08 {
                let meters = baseSpeed * noise.multiplier * min(1, magnitude) * dt
                next = next.offset(east: joystickVector.dx / magnitude * meters,
                                   north: -joystickVector.dy / magnitude * meters)
                moved = true
            }
        }
        if moved || driftOffset.east != oldOffset.east || driftOffset.north != oldOffset.north {
            // Idle drift must not move a pin the user is placing elsewhere on the map.
            let selectedPin = pin
            apply(next.coordinate, pairing: pairing, markRecent: false)
            if status == .active, let advancedRoute { routeSimulation = advancedRoute }
            if !moved { pin = selectedPin }
        }
    }

    private func startResend(pairing: PairingStore) {
        guard resendTimer == nil else { return }
        let token = generation
        let timer = Timer(timeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token, self.status == .active,
                      let sim = self.simulated else { return }
                let result = LocationEngine.set(
                    latitude: sim.latitude,
                    longitude: sim.longitude,
                    pairingPath: pairing.pairingPath,
                    deviceIP: TunnelConfig.targetIP
                )
                if case .failure(let error) = result {
                    self.interruptMovement()
                    self.lastError = error.localizedDescription
                    self.status = .dropped(error.localizedDescription)
                    self.postDropNotification(error.localizedDescription)
                }
            }
        }
        resendTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopResend() {
        resendTimer?.invalidate()
        resendTimer = nil
    }

    private func startHealth(pairing: PairingStore) {
        guard healthTimer == nil else { return }
        let token = generation
        let timer = Timer(timeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token, let ideal = self.idealCoordinate else { return }
                let selectedPin = self.pin
                if case .dropped = self.status {
                    self.status = .reconnecting
                    self.apply(ideal, pairing: pairing, markRecent: false)
                } else if !LocationEngine.isSessionActive, self.isSpoofing {
                    self.interruptMovement()
                    self.status = .reconnecting
                    self.apply(ideal, pairing: pairing, markRecent: false)
                }
                self.pin = selectedPin
            }
        }
        healthTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopHealth() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    private func pushRecent(_ coordinate: CLLocationCoordinate2D) {
        pushNamedRecent(
            name: Self.coordinateLabel(coordinate),
            coordinate: coordinate
        )
    }

    func pushNamedRecent(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        recents.removeAll {
            abs($0.latitude - place.latitude) < 0.00015 && abs($0.longitude - place.longitude) < 0.00015
        }
        recents.insert(place, at: 0)
        if recents.count > 20 { recents = Array(recents.prefix(20)) }
        SavedPlace.save(recents, key: recentsKey)
    }

    private func beginBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackground()
        }
    }

    private func endBackground() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func postDropNotification(_ message: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Locus spoof dropped")
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

extension MotionPoint {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
