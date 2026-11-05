import CoreLocation
import SwiftUI

struct RoutePlannerSheet: View {
    @Binding var stops: [RouteStop]
    var isRouting: Bool
    var completedLegs: Int
    var totalLegs: Int
    var buildError: String?
    var hasPreparedRoute: Bool
    var hasDrawnPath: Bool
    var preparedDistance: Double
    var canUsePin: Bool
    var onAddPin: () -> Void
    var onAddCurrent: () -> Void
    var onPickOnMap: () -> Void
    var onBuild: () -> Void
    var onCancelBuild: () -> Void
    var onPlay: () -> Void
    var onImportGPX: () -> Void
    var onExportGPX: () -> Void
    var onUseDrawn: () -> Void

    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if session.routeSimulation.phase != .idle {
                    Section(String(localized: "Current route")) {
                        RoutePlaybackControls()
                    }
                }
                Section(String(localized: "Movement speed")) {
                    SpeedControls()
                    if session.travelMode == .custom {
                        Picker(String(localized: "Road type"), selection: $session.motionSettings.customRoadDriving) {
                            Text(String(localized: "Walking roads")).tag(false)
                            Text(String(localized: "Driving roads")).tag(true)
                        }
                    }
                }
                Section {
                    if stops.isEmpty {
                        Text(String(localized: "Add your start, any stops along the way, and your destination."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(.black)
                                .frame(width: 28, height: 28)
                                .background(index == stops.count - 1 && index > 0 ? LocusTheme.accentSecondary : LocusTheme.accent, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(stopTitle(at: index)).font(.subheadline.weight(.semibold))
                                if !stop.name.isEmpty { Text(stop.name).font(.subheadline) }
                                Text(String(format: "%.5f, %.5f", stop.point.latitude, stop.point.longitude))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .onMove { stops.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { stops.remove(atOffsets: $0) }
                    Button(action: onPickOnMap) {
                        Label(String(localized: "Choose stops on map"), systemImage: "map")
                    }
                    Button(action: onAddPin) {
                        Label(String(localized: "Add selected pin as next stop"), systemImage: "mappin.and.ellipse")
                    }
                    .disabled(!canUsePin)
                    if stops.isEmpty {
                        Button(action: onAddCurrent) {
                            Label(String(localized: "Use current location as start"), systemImage: "location")
                        }
                        .disabled(session.idealCoordinate == nil && session.realCoordinate == nil && session.pin == nil)
                    }
                } header: {
                    Text(String(localized: "Start → Stops → Destination"))
                } footer: {
                    Text(String(localized: "Points are visited in order. The first is the start and the last is the destination. Use Edit to reorder or remove points; add more points to extend the route."))
                }

                Section {
                    if isRouting {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(format: String(localized: "Building segment %lld of %lld"),
                                        Int64(min(completedLegs + 1, max(1, totalLegs))), Int64(max(1, totalLegs))))
                            ProgressView(value: Double(completedLegs), total: Double(max(1, totalLegs)))
                                .tint(LocusTheme.accent)
                        }
                        Button(String(localized: "Cancel route build"), role: .cancel, action: onCancelBuild)
                    } else {
                        Button(action: onBuild) {
                            Label(String(localized: "Build connected route"), systemImage: "road.lanes")
                        }
                        .disabled(stops.count < 2)
                    }
                    if let buildError {
                        Text(buildError).font(.footnote).foregroundStyle(LocusTheme.danger)
                    }
                    if hasPreparedRoute {
                        LabeledContent(String(localized: "Prepared route"), value: distanceLabel)
                    }
                    Button(action: onPlay) {
                        Label(String(localized: "Start route"), systemImage: "play.fill")
                    }
                    .disabled(isRouting || !hasPreparedRoute || session.routeSimulation.canStop)
                } footer: {
                    Text(String(localized: "Editing stops or the road type requires rebuilding. Your current running or paused route is kept until you stop it."))
                }

                Section(String(localized: "Draw / GPX")) {
                    Button(action: onUseDrawn) {
                        Label(String(localized: "Use drawn path from map"), systemImage: "pencil.tip")
                    }
                    .disabled(!hasDrawnPath || isRouting)
                    Button(action: onImportGPX) {
                        Label(String(localized: "Import GPX"), systemImage: "square.and.arrow.down")
                    }
                    Button(action: onExportGPX) {
                        Label(String(localized: "Export GPX"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(!hasPreparedRoute || isRouting)
                }
                Section {
                    Text(String(localized: "Pause and Stop route keep your simulated location here. End spoofing restores real GPS. Enabled drift remains centered on the held location."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "Routes"))
            .tint(LocusTheme.accent)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }

    private var distanceLabel: String {
        if preparedDistance >= 1000 {
            return (preparedDistance / 1000).formatted(.number.precision(.fractionLength(1))) + " km"
        }
        return preparedDistance.rounded().formatted() + " m"
    }

    private func stopTitle(at index: Int) -> String {
        if index == 0 { return String(localized: "Start") }
        if index == stops.count - 1 { return String(localized: "End") }
        return String(format: String(localized: "Stop %lld"), Int64(index))
    }
}

/// Available without reopening Routes, and shared with its current-route section.
struct RoutePlaybackControls: View {
    @EnvironmentObject private var session: SpoofSession

    private var title: String {
        switch session.routeSimulation.phase {
        case .idle: return String(localized: "Routes")
        case .running: return String(localized: "Route running")
        case .paused: return String(localized: "Route paused")
        case .stopped: return String(localized: "Route stopped · location held")
        case .completed: return String(localized: "Route finished · location held")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(session.routeSimulation.progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if session.routeSimulation.phase == .running {
                    routeButton("pause.fill", label: String(localized: "Pause route")) { session.pauseRoute() }
                } else if session.routeSimulation.phase == .paused {
                    routeButton("play.fill", label: String(localized: "Resume route")) { session.resumeRoute() }
                        .disabled(session.status != .active)
                }
                if session.routeSimulation.canStop {
                    routeButton("stop.fill", label: String(localized: "Stop route"), tint: LocusTheme.danger) { session.stopRoute() }
                }
            }
            ProgressView(value: session.routeSimulation.progress)
                .tint(LocusTheme.accent)
                .accessibilityLabel(String(localized: "Route progress"))
        }
    }

    private func routeButton(_ icon: String, label: String, tint: Color = LocusTheme.accent,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Capsule().fill(tint.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}
