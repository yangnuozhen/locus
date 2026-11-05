import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct TunnelChecks {
    static func main() {
        assert(TunnelConfig.defaultIP == "10.7.0.1" && TunnelConfig.defaultServicePort == 49152)
        for address in ["10.7.0.1", "172.19.0.1", "192.168.10.2", "127.0.0.1", "255.255.255.255"] {
            assert(TunnelConfig.isValidIPv4(address))
        }
        for address in ["", "10.7.0", "10.7.0.256", "10.7.0.-1", "10.7.0.01", "10.7.0.1.",
                        "10..0.1", " 10.7.0.1", "host.local", "::1", "１０.7.0.1", "1e1.7.0.1"] {
            assert(!TunnelConfig.isValidIPv4(address))
        }

        var state = TunnelProbeState()
        assert(state.availability == .checking && !state.pending)
        let first = state.begin(target: "10.7.0.1")
        assert(state.pending)
        state.finish(token: first, reachable: true)
        assert(state.availability == .reachable && !state.pending)
        // No interface-address input: a proxy with a 172.x utun is accepted
        // when the configured developer endpoint is actually reachable.

        let retry = state.begin(target: "10.7.0.1")
        state.finish(token: first, reachable: false)
        assert(state.pending && state.availability == .reachable)
        state.finish(token: retry, reachable: false)
        assert(state.availability == .unverified)
        // Duplicate ready/failed callbacks and timeout races cannot overwrite completion.
        state.finish(token: retry, reachable: true)
        assert(state.availability == .unverified)

        let oldTarget = state.begin(target: "10.7.0.1")
        let newTarget = state.begin(target: "192.168.10.2")
        assert(state.availability == .checking && state.target == "192.168.10.2")
        state.finish(token: oldTarget, reachable: true)
        assert(state.pending && state.availability == .checking)
        state.finish(token: newTarget, reachable: true)
        assert(state.availability == .reachable)

        let background = state.begin(target: "192.168.10.2")
        state.invalidate()
        state.finish(token: background, reachable: false)
        assert(!state.pending && state.availability == .reachable)
        let resumed = state.begin(target: "192.168.10.2")
        state.finish(token: background, reachable: true)
        state.finish(token: resumed, reachable: false)
        assert(state.availability == .unverified)
        let suite = "locus.tunnelChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        assert(TunnelConfig.servicePort(in: defaults) == 49152)
        TunnelConfig.remember(port: 53001, host: "10.7.0.1", in: defaults)
        assert(TunnelConfig.servicePort(in: defaults) == 53001)
        // A newly confirmed port replaces the old cached endpoint after a restart/reinstall.
        TunnelConfig.remember(port: 54002, host: "10.7.0.1", in: defaults)
        assert(TunnelConfig.servicePort(in: defaults) == 54002)
        TunnelConfig.setEndpoint("10.7.0.1", port: 55003, in: defaults)
        assert(TunnelConfig.portOverride(in: defaults) == 55003 && TunnelConfig.servicePort(in: defaults) == 55003)
        TunnelConfig.remember(port: 56004, host: "10.7.0.1", in: defaults)
        assert(TunnelConfig.servicePort(in: defaults) == 55003) // Manual wins.
        TunnelConfig.setEndpoint("10.7.0.1", port: nil, in: defaults)
        assert(TunnelConfig.servicePort(in: defaults) == 56004)
        TunnelConfig.setEndpoint(" 10.8.0.1 ", port: nil, in: defaults)
        assert(TunnelConfig.targetIP(in: defaults) == "10.8.0.1" && TunnelConfig.servicePort(in: defaults) == 49152)
        defaults.set(70000, forKey: TunnelConfig.portKey)
        assert(TunnelConfig.portOverride(in: defaults) == nil)
        // Nearby devices must not supply a service port for this iPhone.
        assert(TunnelConfig.isLocalService(addresses: ["192.168.1.2"], localAddresses: ["192.168.1.2"], target: "10.7.0.1"))
        assert(TunnelConfig.isLocalService(addresses: ["10.7.0.1"], localAddresses: [], target: "10.7.0.1"))
        assert(!TunnelConfig.isLocalService(addresses: ["192.168.1.3"], localAddresses: ["192.168.1.2"], target: "10.7.0.1"))

        // Exercise a real BSD socket: open local service, then a refused endpoint.
        #if canImport(Darwin)
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        #else
        let listener = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        assert(listener >= 0)
        var local = sockaddr_in()
        #if canImport(Darwin)
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        local.sin_family = sa_family_t(AF_INET)
        local.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        assert(bound == 0 && listen(listener, 2) == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let located = withUnsafeMutablePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) }
        }
        assert(located == 0)
        let port = UInt16(bigEndian: local.sin_port)
        assert(TunnelTCPProbe().run(host: "127.0.0.1", port: port) == .reachable)
        close(listener)
        assert(TunnelTCPProbe().run(host: "127.0.0.1", port: port) == .systemError(ECONNREFUSED))
        let cancelled = TunnelTCPProbe()
        cancelled.cancel()
        assert(cancelled.run(host: "127.0.0.1", port: port) == .cancelled)
        assert(TunnelTCPProbe().run(host: "invalid", port: port) == .invalidAddress)
        assert(TunnelTCPProbe().run(host: "127.0.0.1", port: 0) == .invalidAddress)
        print("Tunnel checks passed (BSD sockets, dynamic/manual ports, host scoping, discovery filtering, cancellation)")
    }
}
