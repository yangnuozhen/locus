import Foundation

@main
struct TunnelChecks {
    static func main() {
        assert(TunnelConfig.defaultIP == "10.7.0.1" && TunnelConfig.servicePort == 49152)
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
        assert(state.availability == .unreachable)
        // Duplicate ready/failed callbacks and timeout races cannot overwrite completion.
        state.finish(token: retry, reachable: true)
        assert(state.availability == .unreachable)

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
        assert(state.availability == .unreachable)
        print("Tunnel checks passed (IPv4, endpoint status, stale replies, cancellation, IP changes)")
    }
}
