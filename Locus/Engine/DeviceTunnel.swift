import Foundation

enum TunnelConfig {
    /// Endpoint reached through LocalDevVPN or another compatible VPN's included route.
    static let defaultIP = "10.7.0.1"
    static let servicePort: UInt16 = 49152
    static let defaultsKey = "locus.targetDeviceIP"
    static let didChange = Notification.Name("locus.tunnelTargetChanged")

    static var targetIP: String {
        let stored = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored, !stored.isEmpty else { return defaultIP }
        return stored
    }

    static func setTargetIP(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized != targetIP else { return }
        UserDefaults.standard.set(normalized, forKey: defaultsKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func isValidIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) } &&
                (part.count == 1 || part.first != "0") && UInt8(part) != nil
        }
    }
}

/// The port probe is advisory: only a paired simulation confirms the service.
/// Tokens discard replies from cancelled probes, backgrounding, and old target IPs.
struct TunnelProbeState {
    enum Availability { case checking, reachable, unreachable }
    private(set) var availability: Availability = .checking
    private(set) var token = UUID()
    private(set) var target = ""
    private(set) var pending = false

    mutating func begin(target: String) -> UUID {
        token = UUID()
        if target != self.target { availability = .checking }
        self.target = target
        pending = true
        return token
    }

    mutating func finish(token: UUID, reachable: Bool) {
        guard token == self.token, pending else { return }
        pending = false
        availability = reachable ? .reachable : .unreachable
    }

    mutating func invalidate() {
        token = UUID()
        pending = false
    }
}

#if canImport(Network) && canImport(Combine) && !TUNNEL_CHECKS
import Combine
import Network

/// A single foreground monitor shared by the status bar, Settings, and setup.
/// No provider-name, interface-address, or VPN-installation assumptions.
@MainActor
final class DeveloperTunnelMonitor: ObservableObject {
    static let shared = DeveloperTunnelMonitor()
    @Published private(set) var probe = TunnelProbeState()
    private var connection: NWConnection?
    private var pathMonitor: NWPathMonitor?
    private var timer: Timer?
    private var timeoutTask: Task<Void, Never>?
    private var targetObserver: NSObjectProtocol?
    private let queue = DispatchQueue(label: "com.chrismack.locus.tunnelProbe")
    private var running = false
    private var lastProbeTime = -Double.infinity

    private init() {
        targetObserver = NotificationCenter.default.addObserver(forName: TunnelConfig.didChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: true) }
        }
    }

    func start() {
        guard !running else { return }
        running = true
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.refresh(force: true) }
        }
        pathMonitor = monitor
        monitor.start(queue: queue)
        let timer = Timer(timeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        refresh(force: true)
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        cancelProbe()
        probe = TunnelProbeState()
    }

    /// Cancel the advisory TCP probe before opening the actual DVT connection.
    func prepareForSimulation() {
        cancelProbe()
        lastProbeTime = ProcessInfo.processInfo.systemUptime
    }

    func refresh(force: Bool = false) {
        guard running else { return }
        // An active DVT session is stronger evidence than a second TCP connection.
        // Do not probe a service that may only accept a single client while in use.
        if LocationEngine.isSessionActive {
            cancelProbe()
            let token = probe.begin(target: TunnelConfig.targetIP)
            probe.finish(token: token, reachable: true)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || (!probe.pending && now - lastProbeTime >= 5) else { return }
        cancelProbe()
        lastProbeTime = now
        let target = TunnelConfig.targetIP
        let token = probe.begin(target: target)
        guard TunnelConfig.isValidIPv4(target) else {
            probe.finish(token: token, reachable: false)
            return
        }
        // Use the normal system routing table. A 10.7.0.1/32 route can be carried
        // by any compatible VPN, regardless of that VPN's interface address.
        let connection = NWConnection(host: NWEndpoint.Host(target),
                                      port: NWEndpoint.Port(rawValue: TunnelConfig.servicePort)!, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.complete(token: token, reachable: true)
                case .failed: self?.complete(token: token, reachable: false)
                default: break
                }
            }
        }
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            self?.complete(token: token, reachable: false)
        }
        connection.start(queue: queue)
    }

    private func complete(token: UUID, reachable: Bool) {
        guard running, probe.pending, probe.token == token else { return }
        probe.finish(token: token, reachable: reachable)
        timeoutTask?.cancel()
        timeoutTask = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    private func cancelProbe() {
        probe.invalidate()
        timeoutTask?.cancel()
        timeoutTask = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    deinit {
        if let targetObserver { NotificationCenter.default.removeObserver(targetObserver) }
    }
}
#endif
