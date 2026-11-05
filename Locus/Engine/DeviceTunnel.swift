import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum TunnelConfig {
    static let defaultIP = "10.7.0.1"
    static let defaultServicePort: UInt16 = 49152
    static let defaultsKey = "locus.targetDeviceIP"
    static let portKey = "locus.remotePairingPortOverride"
    static let didChange = Notification.Name("locus.tunnelTargetChanged")

    static var targetIP: String { targetIP(in: .standard) }
    static var portOverride: UInt16? { portOverride(in: .standard) }
    static var servicePort: UInt16 { servicePort(in: .standard) }

    static func targetIP(in defaults: UserDefaults) -> String {
        let stored = defaults.string(forKey: defaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return stored?.isEmpty == false ? stored! : defaultIP
    }

    static func portOverride(in defaults: UserDefaults) -> UInt16? {
        let raw = defaults.integer(forKey: portKey)
        return (1...65535).contains(raw) ? UInt16(raw) : nil
    }

    static func servicePort(in defaults: UserDefaults) -> UInt16 {
        if let port = portOverride(in: defaults) { return port }
        let cached = defaults.integer(forKey: "locus.discoveredRPPort.\(targetIP(in: defaults))")
        return (1...65535).contains(cached) ? UInt16(cached) : defaultServicePort
    }

    static func remember(port: UInt16, host: String, in defaults: UserDefaults = .standard) {
        guard port > 0, isValidIPv4(host) else { return }
        defaults.set(Int(port), forKey: "locus.discoveredRPPort.\(host)")
    }

    static func setTargetIP(_ value: String) { setEndpoint(value, port: portOverride) }

    static func setEndpoint(_ value: String, port: UInt16?, in defaults: UserDefaults = .standard) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = normalized.isEmpty ? defaultIP : normalized
        guard host != targetIP(in: defaults) || port != portOverride(in: defaults) else { return }
        defaults.set(host, forKey: defaultsKey)
        defaults.set(Int(port ?? 0), forKey: portKey)
        if defaults === UserDefaults.standard { NotificationCenter.default.post(name: didChange, object: nil) }
    }

    static func isValidIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) } &&
                (part.count == 1 || part.first != "0") && UInt8(part) != nil
        }
    }

    static func isLocalService(addresses: Set<String>, localAddresses: Set<String>, target: String) -> Bool {
        addresses.contains(target) || !addresses.isDisjoint(with: localAddresses)
    }
}

struct TunnelProbeState {
    // A failed port test does not prove that the route, pairing, or VPN is broken.
    enum Availability { case checking, reachable, unverified }
    private(set) var availability: Availability = .checking
    private(set) var token = UUID()
    private(set) var target = ""
    private(set) var port: UInt16 = TunnelConfig.defaultServicePort
    private(set) var pending = false

    mutating func begin(target: String, port: UInt16 = TunnelConfig.defaultServicePort) -> UUID {
        token = UUID()
        if target != self.target || port != self.port { availability = .checking }
        self.target = target
        self.port = port
        pending = true
        return token
    }

    mutating func attempting(port: UInt16) { self.port = port }

    mutating func finish(token: UUID, reachable: Bool) {
        guard token == self.token, pending else { return }
        pending = false
        availability = reachable ? .reachable : .unverified
    }

    mutating func invalidate() { token = UUID(); pending = false }
}

/// Uses the same BSD socket routing path as the native library. The descriptor is
/// owned/closed by run(); cancel() only shuts it down under a lock to avoid fd reuse races.
final class TunnelTCPProbe: @unchecked Sendable {
    enum Outcome: Equatable { case reachable, timedOut, cancelled, invalidAddress, systemError(Int32) }
    private let lock = NSLock()
    private var cancelled = false
    private var descriptor: Int32 = -1

    func cancel() {
        lock.lock()
        cancelled = true
        if descriptor >= 0 { _ = shutdown(descriptor, Int32(SHUT_RDWR)) }
        lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func run(host: String, port: UInt16, timeout: TimeInterval = 2) -> Outcome {
        guard !isCancelled else { return .cancelled }
        guard TunnelConfig.isValidIPv4(host), port > 0 else { return .invalidAddress }
        var address = sockaddr_in()
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #else
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard fd >= 0 else { return .systemError(errno) }
        lock.lock()
        descriptor = fd
        let wasCancelled = cancelled
        lock.unlock()
        defer {
            lock.lock()
            _ = close(fd)
            descriptor = -1
            lock.unlock()
        }
        guard !wasCancelled else { return .cancelled }
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard host.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else { return .invalidAddress }
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { return .systemError(errno) }
        let connected = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if connected == 0 { return isCancelled ? .cancelled : .reachable }
        let initialError = errno
        guard initialError == EINPROGRESS || initialError == EWOULDBLOCK else { return isCancelled ? .cancelled : .systemError(initialError) }
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        while !isCancelled {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 { return .timedOut }
            var descriptorPoll = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&descriptorPoll, 1, Int32(max(1, min(100, remaining * 1000))))
            if ready < 0 {
                if errno == EINTR { continue }
                return isCancelled ? .cancelled : .systemError(errno)
            }
            if ready == 0 { continue }
            guard !isCancelled else { return .cancelled }
            var socketError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 else { return .systemError(errno) }
            if socketError != 0 { return .systemError(socketError) }
            return (descriptorPoll.revents & Int16(POLLOUT)) != 0 ? .reachable : .systemError(ECONNABORTED)
        }
        return .cancelled
    }
}

#if canImport(Network) && canImport(Combine) && !TUNNEL_CHECKS
import Combine
import Network

/// Resolves only services on this device (or the configured endpoint), not a
/// random nearby phone. Bonjour discovers the port; the VPN target IP stays unchanged.
private final class RemotePairingDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var timer: Timer?
    private var target = ""
    private var localAddresses = Set<String>()
    private var onPort: ((UInt16) -> Void)?
    private var onDone: (() -> Void)?

    func start(target: String, onPort: @escaping (UInt16) -> Void, onDone: @escaping () -> Void) {
        self.target = target
        self.localAddresses = Self.interfaceAddresses()
        self.onPort = onPort
        self.onDone = onDone
        browser.delegate = self
        browser.includesPeerToPeer = true
        browser.searchForServices(ofType: "_remotepairing._tcp.", inDomain: "local.")
        let timer = Timer(timeInterval: 3, repeats: false) { [weak self] _ in self?.finish() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        browser.delegate = nil
        browser.stop()
        for service in services { service.delegate = nil; service.stop() }
        services.removeAll()
        onPort = nil
        onDone = nil
    }

    private func finish() {
        let callback = onDone
        stop()
        callback?()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.includesPeerToPeer = true
        service.delegate = self
        service.resolve(withTimeout: 2)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) { finish() }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard (1...65535).contains(sender.port) else { return }
        let addresses = Set((sender.addresses ?? []).compactMap { data -> String? in
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress, raw.count >= MemoryLayout<sockaddr>.size else { return nil }
                return Self.numericAddress(base.assumingMemoryBound(to: sockaddr.self), length: socklen_t(raw.count))
            }
        })
        if TunnelConfig.isLocalService(addresses: addresses, localAddresses: localAddresses, target: target) {
            onPort?(UInt16(sender.port))
        }
    }

    private static func numericAddress(_ address: UnsafePointer<sockaddr>, length: socklen_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(address, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        return String(cString: buffer).components(separatedBy: "%")[0]
    }

    private static func interfaceAddresses() -> Set<String> {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var pointer = first
        var result = Set<String>()
        while let current = pointer {
            if let address = current.pointee.ifa_addr {
                let family = Int32(address.pointee.sa_family)
                if family == AF_INET || family == AF_INET6,
                   let ip = numericAddress(address, length: socklen_t(address.pointee.sa_len)) { result.insert(ip) }
            }
            pointer = current.pointee.ifa_next
        }
        return result
    }
}

@MainActor
final class DeveloperTunnelMonitor: ObservableObject {
    static let shared = DeveloperTunnelMonitor()
    @Published private(set) var probe = TunnelProbeState()
    @Published private(set) var lastOutcome: TunnelTCPProbe.Outcome?
    private var socketProbe: TunnelTCPProbe?
    private var discovery: RemotePairingDiscovery?
    private var discoveryFinished = true
    private var candidates: [UInt16] = []
    private var attempted = Set<UInt16>()
    private var pathMonitor: NWPathMonitor?
    private var timer: Timer?
    private var timeoutTask: Task<Void, Never>?
    private var targetObserver: NSObjectProtocol?
    private let queue = DispatchQueue(label: "com.chrismack.locus.tunnelProbe")
    private var running = false
    private var lastProbeTime = -Double.infinity

    var statusLabel: String {
        if probe.pending { return String(localized: "Checking developer tunnel…") }
        switch probe.availability {
        case .checking: return String(localized: "Checking developer tunnel…")
        case .reachable: return String(localized: "Endpoint reachable")
        case .unverified: return String(localized: "Remote Pairing port not verified")
        }
    }

    private init() {
        targetObserver = NotificationCenter.default.addObserver(forName: TunnelConfig.didChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: true) }
        }
    }

    func start() {
        guard !running else { return }
        running = true
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in Task { @MainActor in self?.refresh(force: true) } }
        pathMonitor = monitor
        monitor.start(queue: queue)
        let timer = Timer(timeInterval: 8, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        refresh(force: true)
    }

    func stop() {
        running = false
        timer?.invalidate(); timer = nil
        pathMonitor?.cancel(); pathMonitor = nil
        cancelProbe()
        probe = TunnelProbeState()
    }

    /// A real connection waits for default/cached and discovered ports first.
    /// Preflight remains advisory: native authentication is still attempted if it fails.
    func resolveBeforeConnecting() async {
        if !running { start() } else if !probe.pending { refresh(force: true) }
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while probe.pending && ProcessInfo.processInfo.systemUptime < deadline {
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
        }
    }

    func prepareForSimulation() { cancelProbe(); lastProbeTime = ProcessInfo.processInfo.systemUptime }

    func refresh(force: Bool = false) {
        guard running else { return }
        if LocationEngine.isSessionActive {
            cancelProbe()
            let token = probe.begin(target: TunnelConfig.targetIP, port: TunnelConfig.servicePort)
            probe.finish(token: token, reachable: true)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || (!probe.pending && now - lastProbeTime >= 5) else { return }
        cancelProbe()
        lastProbeTime = now
        lastOutcome = nil
        let token = probe.begin(target: TunnelConfig.targetIP, port: TunnelConfig.servicePort)
        guard TunnelConfig.isValidIPv4(probe.target) else { complete(token: token, outcome: .invalidAddress); return }
        candidates = [TunnelConfig.servicePort]
        attempted = []
        discoveryFinished = TunnelConfig.portOverride != nil
        if !discoveryFinished {
            let discovery = RemotePairingDiscovery()
            self.discovery = discovery
            discovery.start(target: probe.target, onPort: { [weak self] port in
                guard let self, self.probe.pending, self.probe.token == token, !self.attempted.contains(port) else { return }
                if !self.candidates.contains(port) { self.candidates.append(port) }
                self.tryNext(token: token)
            }, onDone: { [weak self] in
                guard let self, self.probe.token == token else { return }
                self.discoveryFinished = true
                self.tryNext(token: token)
            })
        }
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 7_000_000_000) } catch { return }
            guard let self else { return }
            self.complete(token: token, outcome: .timedOut)
        }
        tryNext(token: token)
    }

    private func tryNext(token: UUID) {
        guard probe.pending, probe.token == token, socketProbe == nil else { return }
        guard let port = candidates.first(where: { !attempted.contains($0) }) else {
            if discoveryFinished { complete(token: token, outcome: lastOutcome ?? .timedOut) }
            return
        }
        candidates.removeAll { $0 == port }
        attempted.insert(port)
        probe.attempting(port: port)
        let host = probe.target
        let socketProbe = TunnelTCPProbe()
        self.socketProbe = socketProbe
        queue.async { [weak self] in
            let outcome = socketProbe.run(host: host, port: port)
            Task { @MainActor in
                guard let self, self.probe.pending, self.probe.token == token else { return }
                self.socketProbe = nil
                self.lastOutcome = outcome
                if outcome == .reachable {
                    if TunnelConfig.portOverride == nil { TunnelConfig.remember(port: port, host: host) }
                    self.complete(token: token, outcome: outcome)
                } else { self.tryNext(token: token) }
            }
        }
    }

    private func complete(token: UUID, outcome: TunnelTCPProbe.Outcome) {
        guard running, probe.pending, probe.token == token else { return }
        lastOutcome = outcome
        probe.finish(token: token, reachable: outcome == .reachable)
        stopOperations()
    }

    private func stopOperations() {
        socketProbe?.cancel(); socketProbe = nil
        discovery?.stop(); discovery = nil
        timeoutTask?.cancel(); timeoutTask = nil
        candidates.removeAll()
    }

    private func cancelProbe() { probe.invalidate(); stopOperations() }

    deinit { if let targetObserver { NotificationCenter.default.removeObserver(targetObserver) } }
}
#endif
