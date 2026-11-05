import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var tunnel: DeveloperTunnelMonitor
    @Environment(\.dismiss) private var dismiss

    @AppStorage(CoordinateTransform.defaultsKey) private var coordinateMode = CoordinateTransform.Mode.none.rawValue
    @State private var showImporter = false
    @State private var showPairOnDevice = false
    @State private var showNameEasterEgg = false
    @State private var tunnelIP = TunnelConfig.targetIP
    @State private var automaticPort = TunnelConfig.portOverride == nil
    @State private var tunnelPortText = String(TunnelConfig.servicePort)
    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled
    @Environment(\.scenePhase) private var scenePhase

    private var supportsOnDevicePairing: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    private var tunnelAvailable: Bool {
        session.status == .active || tunnel.probe.availability == .reachable
    }

    private var tunnelStatus: String {
        if session.status == .active { return String(localized: "Connected") }
        return tunnel.statusLabel
    }

    private var manualPort: UInt16? {
        guard let port = UInt16(tunnelPortText.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0 else { return nil }
        return port
    }

    private var tunnelSettingsValid: Bool {
        TunnelConfig.isValidIPv4(tunnelIP.trimmingCharacters(in: .whitespacesAndNewlines)) &&
            (automaticPort || manualPort != nil)
    }

    @discardableResult
    private func saveTunnelSettings() -> Bool {
        guard !session.isSpoofing, !session.isBusy, tunnelSettingsValid else { return false }
        TunnelConfig.setEndpoint(tunnelIP, port: automaticPort ? nil : manualPort)
        return true
    }

    private var probeDetail: String? {
        switch tunnel.lastOutcome {
        case .systemError(let code):
            return String(format: String(localized: "TCP test %@:%u failed (errno %d). This does not prove the VPN route is missing."),
                          tunnel.probe.target, UInt32(tunnel.probe.port), code)
        case .timedOut:
            return String(format: String(localized: "TCP test %@:%u timed out. Try automatic discovery or match SideStore’s current Remote Pairing port."),
                          tunnel.probe.target, UInt32(tunnel.probe.port))
        case .invalidAddress: return String(localized: "Tunnel IP is invalid. Check Settings → Tunnel IP (usually 10.7.0.1).")
        default: return nil
        }
    }

    private var tunnelSection: some View {
        Section {
            TextField(String(localized: "Device tunnel IP"), text: $tunnelIP)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { saveTunnelSettings() }
                .disabled(session.isSpoofing || session.isBusy)
            Toggle(String(localized: "Discover Remote Pairing port"), isOn: $automaticPort)
                .disabled(session.isSpoofing || session.isBusy)
                .onChange(of: automaticPort) { _, automatic in
                    if !automatic { tunnelPortText = String(TunnelConfig.servicePort) }
                }
            if !automaticPort {
                TextField(String(localized: "Remote Pairing port"), text: $tunnelPortText)
                    .keyboardType(.numberPad)
                    .disabled(session.isSpoofing || session.isBusy)
            }
            if !tunnelSettingsValid {
                Text(String(localized: "Enter a valid IPv4 address and a port from 1 to 65535."))
                    .font(.footnote).foregroundStyle(LocusTheme.danger)
            }
            LabeledContent(String(localized: "Status")) {
                Text(tunnelStatus)
                    .foregroundStyle(tunnelAvailable ? LocusTheme.statusGood : LocusTheme.statusWarn)
            }
            Button(String(localized: "Save tunnel settings")) { saveTunnelSettings() }
                .disabled(session.isSpoofing || session.isBusy || !tunnelSettingsValid)
            LabeledContent(String(localized: "Tunnel endpoint"), value: "\(TunnelConfig.targetIP):\(TunnelConfig.servicePort)")
                .font(.subheadline.monospacedDigit())
            if !tunnel.probe.pending, let probeDetail, session.status != .active {
                Text(probeDetail).font(.footnote).foregroundStyle(.secondary)
            }
            Button(String(localized: "Check developer tunnel")) {
                if session.isSpoofing || session.isBusy || saveTunnelSettings() { tunnel.refresh(force: true) }
            }
            .disabled(tunnel.probe.pending || (!tunnelSettingsValid && !session.isSpoofing))
            Button {
                if localDevVPNInstalled { LocalDevVPN.openInstalled() } else { LocalDevVPN.openAppStore() }
            } label: {
                Label(localDevVPNInstalled ? String(localized: "Open LocalDevVPN") : String(localized: "Get LocalDevVPN (App Store)"),
                      systemImage: localDevVPNInstalled ? "lock.shield.fill" : "arrow.down.app.fill")
            }
        } header: {
            Text(String(localized: "Tunnel"))
        } footer: {
            Text(String(localized: "Remote Pairing ports can change. Automatic mode uses the last working port, then discovers this device’s service via Bonjour. If discovery is unavailable, enter the same port used by SideStore. The VPN route and IP stay unchanged. Allow Local Network access for Locus or its container. Stop spoofing before editing."))
        }
        .tint(LocusTheme.accent)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(pairing.hasPairingFile ? String(localized: "RPPairing file installed") : String(localized: "No pairing file"))
                    } icon: {
                        Image(systemName: pairing.hasPairingFile ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(pairing.hasPairingFile ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }

                    if supportsOnDevicePairing {
                        Button {
                            showPairOnDevice = true
                        } label: {
                            Label(String(localized: "Pair on this iPhone"), systemImage: "iphone.gen3.radiowaves.left.and.right")
                        }
                    }

                    Button(String(localized: "Import RPPairing file…")) { showImporter = true }
                    Button(String(localized: "Paste RPPairing from clipboard")) {
                        do {
                            try pairing.importPairingFromClipboard()
                        } catch {
                            session.lastError = error.localizedDescription
                        }
                    }
                    if pairing.hasPairingFile {
                        Button(String(localized: "Remove pairing file"), role: .destructive) {
                            try? pairing.removePairing()
                        }
                    }
                } header: {
                    Text(String(localized: "Developer pairing"))
                } footer: {
                    Text(supportsOnDevicePairing
                         ? String(localized: "On iOS 27, use Pair on this iPhone — no computer. Locus advertises a pairable host; confirm the 6-digit code under Settings › Privacy & Security › Developer Mode › Pair with Host. On older iOS, import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing). LiveContainer: enable Fix File Picker on Locus, or use Paste / Share → LiveContainer → Locus.")
                         : String(localized: "Import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing). If the file picker fails (common in LiveContainer), enable Fix File Picker on the app, share the file into LiveContainer → Locus, or copy the plist and use Paste."))
                }

                tunnelSection

                Section {
                    Picker(String(localized: "Conversion"), selection: $coordinateMode) {
                        ForEach(CoordinateTransform.Mode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .disabled(session.isSpoofing || session.isBusy || session.simulated != nil)
                } header: {
                    Text(String(localized: "Coordinate conversion"))
                } footer: {
                    Text(String(localized: "Off by default. Converts only coordinates sent to the device; saved places and GPX remain unchanged. Use WGS-84 → GCJ-02 or BD-09 only when the destination expects that system. For a GCJ-02 map pin sent to GPS, use GCJ-02 → WGS-84. Stop spoofing before changing this setting. Coverage uses an approximate China bounding box; leave it off elsewhere, including border areas."))
                }

                Section {
                    Toggle(String(localized: "Random location drift"), isOn: $session.motionSettings.driftEnabled)
                    if session.motionSettings.driftEnabled {
                        NumericSettingRow(title: String(localized: "Maximum drift radius"), unit: "m",
                                          value: $session.motionSettings.driftRadius, range: 1...100, step: 1,
                                          help: String(localized: "Drift stays near the ideal location without accumulating. Applies while stationary and moving."))
                    }
                    Toggle(String(localized: "Random speed variation"), isOn: $session.motionSettings.speedVariationEnabled)
                    if session.motionSettings.speedVariationEnabled {
                        NumericSettingRow(title: String(localized: "Speed variation"), unit: "%",
                                          value: $session.motionSettings.speedVariationPercent, range: 0...90, step: 1,
                                          help: String(localized: "Varies above and below the base speed. At 5 km/h, ±10% means 4.5–5.5 km/h."), prefix: "±")
                    }
                    Button(String(localized: "Restore simulation defaults")) {
                        session.motionSettings.driftEnabled = false
                        session.motionSettings.driftRadius = 3
                        session.motionSettings.speedVariationEnabled = true
                        session.motionSettings.speedVariationPercent = 10
                    }
                } header: {
                    Text(String(localized: "Random simulation"))
                } footer: {
                    Text(String(localized: "Smooth changes every 3 seconds. Drift is off by default (3 m); speed variation is on (±10%). Changes apply immediately. Saved places and GPX keep their original coordinates."))
                }
                .tint(LocusTheme.accent)

                Section(String(localized: "Privacy")) {
                    Text(String(localized: "Fully on-device. Favorites and recents stay in UserDefaults. No analytics, no accounts, nothing uploaded."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(String(localized: "About")) {
                    LabeledContent(String(localized: "Version"), value: appVersion)
                    LabeledContent(String(localized: "Engine"), value: String(localized: "idevice DVT location simulation"))
                    Text(String(localized: "Locus is free and open source (MIT). Location injection uses the MIT-licensed idevice FFI."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showNameEasterEgg = true
                    } label: {
                        Text(String(localized: "locus, n. — a place. From the Latin for where you are."))
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle(String(localized: "Settings"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) {
                        if !session.isSpoofing && !session.isBusy { saveTunnelSettings() }
                        dismiss()
                    }
                    .disabled(!tunnelSettingsValid && !session.isSpoofing)
                }
            }
            .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        try pairing.importPairing(from: url)
                    } catch {
                        session.lastError = error.localizedDescription
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
            .sheet(isPresented: $showPairOnDevice) {
                PairOnDeviceView()
                    .environmentObject(pairing)
            }
            .fullScreenCover(isPresented: $showNameEasterEgg) {
                LocusEasterEggView()
            }
            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    localDevVPNInstalled = LocalDevVPN.isInstalled
                }
            }
        }
    }
}

struct PlacesView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @State private var placeToRename: SavedPlace?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "Favorites")) {
                    if session.favorites.isEmpty {
                        Text(String(localized: "Star a pin from the map to save it."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.favorites) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeFavorite(place)
                                } label: {
                                    Label(String(localized: "Delete"), systemImage: "trash.fill")
                                }
                                Button {
                                    placeToRename = place
                                    renameText = place.name
                                } label: {
                                    Label(String(localized: "Rename"), systemImage: "pencil")
                                }
                                .tint(.gray)
                            }
                    }
                }

                Section(String(localized: "Recents")) {
                    if session.recents.isEmpty {
                        Text(String(localized: "Teleports show up here."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.recents) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeRecent(place)
                                } label: {
                                    Label(String(localized: "Delete"), systemImage: "trash.fill")
                                }
                            }
                    }
                }
            }
            .navigationTitle(String(localized: "Places"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .alert(String(localized: "Rename Favorite"), isPresented: Binding(
                get: { placeToRename != nil },
                set: { if !$0 { placeToRename = nil } }
            )) {
                TextField(String(localized: "Name"), text: $renameText)
                Button(String(localized: "Cancel"), role: .cancel) {
                    placeToRename = nil
                }
                Button(String(localized: "Save")) {
                    if let place = placeToRename {
                        session.renameFavorite(place, to: renameText)
                    }
                    placeToRename = nil
                }
            } message: {
                Text(String(localized: "Choose a name you’ll recognize later."))
            }
        }
    }

    private func placeButton(_ place: SavedPlace) -> some View {
        Button {
            session.teleport(to: place.coordinate, pairing: pairing)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(.primary)
                Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
