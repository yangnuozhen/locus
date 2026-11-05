import CoreLocation
import Foundation
import idevice

enum LocationEngineError: LocalizedError {
    case invalidCoordinate
    case invalidIP
    case pairingRead
    case tunnelCreate
    case remoteServer
    case simulationCreate
    case locationSet
    case locationClear
    case notActive
    indirect case native(LocationEngineError, Int32, Int32, String)

    var errorDescription: String? {
        switch self {
        case .invalidCoordinate: return String(localized: "Invalid coordinates.")
        case .invalidIP: return String(localized: "Tunnel IP is invalid. Check Settings → Tunnel IP (usually 10.7.0.1).")
        case .pairingRead: return String(localized: "Could not read the RPPairing file. Generate one with idevice_pair in RPPairing mode.")
        case .tunnelCreate: return String(localized: "Could not establish Remote Pairing. Check the service port and this app’s RPPairing file; a working VPN route alone does not verify them.")
        case .remoteServer: return String(localized: "Connected to the tunnel but RemoteXPC handshake failed.")
        case .simulationCreate: return String(localized: "Could not open Apple’s location simulation service.")
        case .locationSet: return String(localized: "Failed to set simulated coordinates.")
        case .locationClear: return String(localized: "Failed to clear simulated location.")
        case .notActive: return String(localized: "No active simulation session.")
        case .native(let stage, let code, let subCode, let endpoint):
            return (stage.errorDescription ?? "") + "\n" + String(format: String(localized: "Endpoint %@ · native error %d/%d"), endpoint, code, subCode)
        }
    }

    static func from(code: Int32) -> LocationEngineError {
        switch code {
        case 1: return .invalidIP
        case 2: return .pairingRead
        case 3: return .tunnelCreate
        case 9: return .remoteServer
        case 10: return .simulationCreate
        case 11: return .locationSet
        case 12: return .locationClear
        default: return .locationSet
        }
    }
}

/// Thin Swift wrapper around idevice’s DVT location simulation (injects into locationd).
enum LocationEngine {
    private static let queue = DispatchQueue(label: "com.chrismack.locus.location", qos: .userInitiated)

    private static var adapter: OpaquePointer?
    private static var handshake: OpaquePointer?
    private static var remoteServer: OpaquePointer?
    private static var locationSimulation: OpaquePointer?
    private static var connectedEndpoint: String?
    private static var nativeFailure: (Int32, Int32)?

    private static let ok: Int32 = 0
    private static let invalidIP: Int32 = 1
    private static let pairingRead: Int32 = 2
    private static let tunnelCreate: Int32 = 3
    private static let remoteServerCode: Int32 = 9
    private static let simulationCreate: Int32 = 10
    private static let locationSet: Int32 = 11
    private static let locationClear: Int32 = 12

    static var isSessionActive: Bool { queue.sync { locationSimulation != nil } }

    static func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) -> Result<Void, LocationEngineError> {
        let input = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(input) else { return .failure(.invalidCoordinate) }
        let output = CoordinateTransform.convert(input, mode: CoordinateTransform.selectedMode)
        var result: Result<Void, LocationEngineError> = .failure(.locationSet)
        let port = TunnelConfig.servicePort
        queue.sync {
            nativeFailure = nil
            let code = setLocked(latitude: output.latitude, longitude: output.longitude, pairingPath: pairingPath, deviceIP: deviceIP, port: port)
            result = code == ok ? .success(()) : .failure(failure(code: code, endpoint: "\(deviceIP):\(port)"))
        }
        return result
    }

    static func clear() -> Result<Void, LocationEngineError> {
        var result: Result<Void, LocationEngineError> = .failure(.notActive)
        queue.sync {
            nativeFailure = nil
            let endpoint = connectedEndpoint ?? "\(TunnelConfig.targetIP):\(TunnelConfig.servicePort)"
            let code = clearLocked()
            result = code == ok ? .success(()) : .failure(failure(code: code, endpoint: endpoint))
        }
        return result
    }

    /// Retain only numeric native diagnostics; never pairing payloads or native messages.
    private static func releaseError(_ error: UnsafeMutablePointer<IdeviceFfiError>) {
        nativeFailure = (error.pointee.code, error.pointee.sub_code)
        idevice_error_free(error)
    }

    private static func failure(code: Int32, endpoint: String) -> LocationEngineError {
        let stage = LocationEngineError.from(code: code)
        if let nativeFailure { return .native(stage, nativeFailure.0, nativeFailure.1, endpoint) }
        return stage
    }

    private static func cleanup() {
        connectedEndpoint = nil
        if let locationSimulation {
            location_simulation_free(locationSimulation)
            self.locationSimulation = nil
        }
        if let remoteServer {
            remote_server_free(remoteServer)
            self.remoteServer = nil
        }
        if let handshake {
            rsd_handshake_free(handshake)
            self.handshake = nil
        }
        if let adapter {
            adapter_free(adapter)
            self.adapter = nil
        }
    }

    private static func setLocked(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String, port: UInt16) -> Int32 {
        if let current = connectedEndpoint, current != "\(deviceIP):\(port)" { cleanup() }
        if let locationSimulation {
            if let err = location_simulation_set(locationSimulation, latitude, longitude) {
                releaseError(err)
                cleanup()
            } else {
                return ok
            }
        }

        nativeFailure = nil
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        let inetResult = deviceIP.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        guard inetResult == 1 else { return invalidIP }

        var pairingHandle: OpaquePointer?
        if let pairingError = pairingPath.withCString({ rp_pairing_file_read($0, &pairingHandle) }) {
            releaseError(pairingError)
            return pairingRead
        }
        guard let pairingHandle else { return pairingRead }
        defer { rp_pairing_file_free(pairingHandle) }

        let providerError = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing(
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.stride),
                    "LocusLocation",
                    pairingHandle,
                    nil,
                    nil,
                    &adapter,
                    &handshake
                )
            }
        }
        if let providerError {
            releaseError(providerError)
            cleanup()
            return tunnelCreate
        }

        if let remoteServerError = remote_server_connect_rsd(adapter, handshake, &remoteServer) {
            releaseError(remoteServerError)
            cleanup()
            return remoteServerCode
        }

        if let simError = location_simulation_new(remoteServer, &locationSimulation) {
            releaseError(simError)
            cleanup()
            return simulationCreate
        }
        // location_simulation_new consumes/owns remote server lifecycle alongside handle
        remoteServer = nil

        if let setError = location_simulation_set(locationSimulation, latitude, longitude) {
            releaseError(setError)
            cleanup()
            return locationSet
        }
        connectedEndpoint = "\(deviceIP):\(port)"
        return ok
    }

    private static func clearLocked() -> Int32 {
        guard let locationSimulation else { return locationClear }
        let err = location_simulation_clear(locationSimulation)
        cleanup()
        if let err {
            releaseError(err)
            return locationClear
        }
        return ok
    }
}
