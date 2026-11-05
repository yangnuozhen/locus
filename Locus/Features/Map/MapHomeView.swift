import MapKit
import SwiftUI

struct MapHomeView: View {
    var onOpenSettings: () -> Void
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore

    @StateObject private var search = PlaceSearchCompleter()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var routeStops: [RouteStop] = []
    @State private var routePicking = false
    @State private var routeBuildTask: Task<Void, Never>?
    @State private var routeBuildID = UUID()
    @State private var completedLegs = 0
    @State private var totalLegs = 0
    @State private var routeBuildError: String?
    @State private var routeIsRoadRoute = false
    @State private var preparedDistance = 0.0
    @State private var pendingGPXImport = false
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var isRouting = false
    @State private var showRouteSheet = false
    @State private var showGPXImporter = false
    @State private var drawnPath: [CLLocationCoordinate2D] = []
    @State private var drawMode = false
    @State private var pinSelected = false
    @State private var isDraggingPin = false
    @State private var suppressNextMapTap = false
    /// Set when the pin comes from search / a named place so starring keeps the title.
    @State private var pinPlaceName: String?
    @State private var favoriteCoordinate: CLLocationCoordinate2D?
    @State private var favoriteName = ""
    @State private var showAddFavorite = false

    private var mapStyle: MapStyle {
        switch session.mapStyleIndex {
        case 1: return .hybrid(elevation: .realistic)
        case 2: return .imagery(elevation: .realistic)
        default: return .standard(elevation: .realistic)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Keep Map inside the safe layout bounds so MapProxy.convert matches
            // finger position. Ignoring the safe area makes the tiles full-bleed but
            // shifts convert() upward by ~status-bar height.
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()

                    if let pin = session.pin, !routePicking {
                        Annotation("", coordinate: pin, anchor: .bottom) {
                            MapDropPin(
                                selected: pinSelected,
                                isDragging: isDraggingPin,
                                onSelect: {
                                    searchFocused = false
                                    suppressNextMapTap = true
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                        pinSelected.toggle()
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        suppressNextMapTap = false
                                    }
                                },
                                onFavorite: prepareFavorite,
                                onRemove: {
                                    suppressNextMapTap = true
                                    withAnimation {
                                        session.pin = nil
                                        pinSelected = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        suppressNextMapTap = false
                                    }
                                },
                                onDragBegan: {
                                    searchFocused = false
                                    suppressNextMapTap = true
                                    pinSelected = false
                                    isDraggingPin = true
                                    pinPlaceName = nil
                                },
                                onDragMoved: { globalPoint in
                                    if let coord = proxy.convert(globalPoint, from: .global) {
                                        session.pin = coord
                                    }
                                },
                                onDragEnded: {
                                    isDraggingPin = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        suppressNextMapTap = false
                                    }
                                }
                            )
                        }
                    }
                    if let sim = session.simulated {
                        Annotation(String(localized: "Spoof"), coordinate: sim) {
                            ZStack {
                                Circle().fill(LocusTheme.accent.opacity(0.25)).frame(width: 44, height: 44)
                                Circle().fill(LocusTheme.accent).frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                        }
                    }
                    if routePicking || routeIsRoadRoute || routeCoords.isEmpty {
                        ForEach(Array(routeStops.enumerated()), id: \.element.id) { index, stop in
                            Annotation("", coordinate: stop.point.coordinate) {
                                Text("\(index + 1)")
                                    .font(.caption.bold().monospacedDigit())
                                    .foregroundStyle(.black)
                                    .frame(width: 28, height: 28)
                                    .background(index == routeStops.count - 1 && index > 0 ? LocusTheme.accentSecondary : LocusTheme.accent, in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    if session.routeSimulation.canStop {
                        MapPolyline(coordinates: session.routeSimulation.path.map(\.coordinate))
                            .stroke(LocusTheme.accent, lineWidth: 5)
                    } else if routeCoords.count > 1 {
                        MapPolyline(coordinates: routeCoords)
                            .stroke(LocusTheme.accent, lineWidth: 5)
                    }
                    if drawnPath.count > 1 {
                        MapPolyline(coordinates: drawnPath)
                            .stroke(LocusTheme.accentSecondary, style: StrokeStyle(lineWidth: 4, dash: [6, 4]))
                    }
                }
                .mapStyle(mapStyle)
                .mapControlVisibility(.hidden)
                .onTapGesture { point in
                    searchFocused = false
                    guard !suppressNextMapTap, !isDraggingPin else { return }
                    pinSelected = false
                    placePin(at: point, proxy: proxy)
                }
            }
            .background(Color.black.ignoresSafeArea())

            topChrome
        }
        .alert(String(localized: "Save Favorite"), isPresented: $showAddFavorite) {
            TextField(String(localized: "Name"), text: $favoriteName)
            Button(String(localized: "Cancel"), role: .cancel) { favoriteCoordinate = nil }
            Button(String(localized: "Save")) {
                if let coordinate = favoriteCoordinate {
                    session.addFavorite(name: favoriteName, coordinate: coordinate)
                }
                favoriteCoordinate = nil
            }
        } message: {
            Text(String(localized: "Choose a name for this map location. Leave it blank to use coordinates."))
        }
        .onAppear {
            session.startLocationUpdates()
        }
        .onChange(of: session.pin?.latitude) { _, newValue in
            if newValue == nil { pinSelected = false }
        }
        .onChange(of: routeStops) { _, _ in
            cancelRoadBuild()
            routeCoords.removeAll()
            preparedDistance = 0
        }
        .onChange(of: session.roadTransportType.rawValue) { _, _ in
            if isRouting || routeIsRoadRoute {
                cancelRoadBuild()
                routeCoords.removeAll()
                preparedDistance = 0
            }
        }
        .onDisappear { cancelRoadBuild() }
        .onReceive(NotificationCenter.default.publisher(for: .locusImportGPX)) { note in
            guard let url = note.object as? URL else { return }
            importGPX(url)
        }
        .fileImporter(isPresented: $showGPXImporter, allowedContentTypes: [.xml, .data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                importGPX(url)
            }
        }
        .sheet(isPresented: $showRouteSheet, onDismiss: {
            if pendingGPXImport {
                pendingGPXImport = false
                showGPXImporter = true
            }
        }) {
            routePlanner
        }
    }

    private var routePlanner: some View {
        RoutePlannerSheet(
            stops: $routeStops,
            isRouting: isRouting,
            completedLegs: completedLegs,
            totalLegs: totalLegs,
            buildError: routeBuildError,
            hasPreparedRoute: routeCoords.count >= 2,
            hasDrawnPath: drawnPath.count >= 2,
            preparedDistance: preparedDistance,
            canUsePin: session.pin != nil,
            onAddPin: {
                if let pin = session.pin { addRouteStop(pin, name: pinPlaceName ?? "") }
            },
            onAddCurrent: {
                if let coordinate = session.idealCoordinate ?? session.realCoordinate ?? session.pin {
                    addRouteStop(coordinate)
                }
            },
            onPickOnMap: {
                searchFocused = false
                pinSelected = false
                drawMode = false
                routePicking = true
                showRouteSheet = false
            },
            onBuild: buildRoadRoute,
            onCancelBuild: cancelRoadBuild,
            onPlay: playRoute,
            onImportGPX: {
                pendingGPXImport = true
                showRouteSheet = false
            },
            onExportGPX: exportGPX,
            onUseDrawn: {
                cancelRoadBuild()
                setPreparedRoute(RouteBuilder.sample(coordinates: drawnPath, every: 10), isRoad: false)
                drawnPath.removeAll()
                drawMode = false
            }
        )
        .presentationDetents([.large])
    }

    private func prepareFavorite() {
        guard let pin = session.pin else { return }
        favoriteCoordinate = pin
        favoriteName = session.suggestedFavoriteName(for: pin, fallback: pinPlaceName)
        searchFocused = false
        pinSelected = false
        showAddFavorite = true
    }

    private func placePin(at point: CGPoint, proxy: MapProxy) {
        guard let coord = proxy.convert(point, from: .local) else { return }
        if routePicking {
            addRouteStop(coord)
        } else if drawMode {
            drawnPath.append(coord)
        } else {
            session.pin = coord
            pinPlaceName = nil
            pinSelected = false
        }
    }

    private var topChrome: some View {
        VStack(spacing: 10) {
            StatusBarView(onOpenSettings: onOpenSettings)

            searchBar

            if routePicking {
                routePickingBanner
            } else if isRouting {
                routeBuildBanner
            } else if let routeBuildError {
                VStack(alignment: .leading, spacing: 4) {
                    Text(routeBuildError).font(.footnote).foregroundStyle(LocusTheme.danger)
                    Button(String(localized: "Routes")) { showRouteSheet = true }
                        .frame(minHeight: 44)
                }
                .padding(12)
                .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if !searchText.isEmpty && !search.results.isEmpty {
                searchResults
            }

            HStack(alignment: .center, spacing: 10) {
                mapChromeButtons
                Spacer(minLength: 0)
                locateButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
        .safeAreaPadding(.top, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(String(localized: "Search places"), text: $searchText)
                .textInputAutocapitalization(.words)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    searchFocused = false
                }
                .onChange(of: searchText) { _, value in
                    search.query = value
                }
            if searchFocused || !searchText.isEmpty {
                Button {
                    searchText = ""
                    search.query = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear and dismiss keyboard"))
            }
            if searchFocused {
                Button(String(localized: "Done")) {
                    searchFocused = false
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(LocusTheme.accent)
            }
        }
        .padding(12)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(search.results.prefix(5), id: \.self) { item in
                Button {
                    select(completion: item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
            }
        }
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var mapChromeButtons: some View {
        HStack(spacing: 4) {
            chromeIconButton("square.3.layers.3d") {
                session.mapStyleIndex = (session.mapStyleIndex + 1) % 3
            }
            chromeIconButton("point.topleft.down.to.point.bottomright.curvepath") {
                routePicking = false
                showRouteSheet = true
            }
            .accessibilityLabel(String(localized: "Routes"))
            chromeIconButton(drawMode ? "pencil.tip.crop.circle.badge.minus" : "pencil.tip.crop.circle") {
                routePicking = false
                drawMode.toggle()
                if !drawMode { drawnPath.removeAll() }
            }
            .foregroundStyle(drawMode ? LocusTheme.accentSecondary : .primary)

            if session.pin != nil {
                chromeIconButton("star.circle") {
                    prepareFavorite()
                }
                .accessibilityLabel(String(localized: "Save Favorite"))
            }
        }
        .padding(6)
        .locusGlass(.clear, in: Capsule())
        .contentShape(Capsule())
    }

    private var locateButton: some View {
        Button {
            searchFocused = false
            goToCurrentLocation()
        } label: {
            Image(systemName: "location.fill")
                .font(.body.weight(.semibold))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .locusGlass(.interactive, in: Circle())
        .foregroundStyle(.primary)
        .contentShape(Circle())
        .accessibilityLabel(String(localized: "Current location"))
    }

    /// Centers on the spoofed fix while spoofing, otherwise the real GPS —
    /// never the leftover teleport pin (`.automatic` would frame that marker).
    private func goToCurrentLocation() {
        let meters: CLLocationDistance = 900
        withAnimation(.easeInOut(duration: 0.35)) {
            if session.isSpoofing, let sim = session.simulated {
                position = .region(MKCoordinateRegion(
                    center: sim,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else if let real = session.realCoordinate {
                position = .region(MKCoordinateRegion(
                    center: real,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else {
                position = .userLocation(
                    followsHeading: false,
                    fallback: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                        latitudinalMeters: 2000,
                        longitudinalMeters: 2000
                    ))
                )
            }
        }
    }

    private func chromeIconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func select(completion: MKLocalSearchCompletion) {
        Task {
            let request = MKLocalSearch.Request(completion: completion)
            if let response = try? await MKLocalSearch(request: request).start(),
               let item = response.mapItems.first {
                let coord = item.placemark.coordinate
                let title = item.name ?? completion.title
                await MainActor.run {
                    session.pin = coord
                    pinPlaceName = title
                    position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1200, longitudinalMeters: 1200))
                    searchText = ""
                    search.query = ""
                    searchFocused = false
                    if routePicking {
                        addRouteStop(coord, name: title)
                    } else {
                        session.addFavorite(name: title, coordinate: coord)
                        session.pushNamedRecent(name: title, coordinate: coord)
                    }
                }
            }
        }
    }

    private func addRouteStop(_ coordinate: CLLocationCoordinate2D, name: String = "") {
        let point = MotionPoint(coordinate)
        guard routeStops.last.map({ $0.point.distance(to: point) >= 1 }) ?? true else { return }
        routeStops.append(RouteStop(point: point, name: name))
    }

    private func cancelRoadBuild() {
        routeBuildID = UUID()
        routeBuildTask?.cancel()
        routeBuildTask = nil
        isRouting = false
        routeBuildError = nil
    }

    private func setPreparedRoute(_ coordinates: [CLLocationCoordinate2D], isRoad: Bool) {
        routeCoords = coordinates
        routeIsRoadRoute = isRoad
        preparedDistance = RoutePlayback(points: coordinates.map(MotionPoint.init))?.totalDistance ?? 0
    }

    private func buildRoadRoute() {
        let points = RouteGeometry.distinctStops(routeStops.map(\.point))
        guard points.count >= 2 else {
            routeBuildError = String(localized: "Add at least two different route stops.")
            return
        }
        cancelRoadBuild()
        let requestID = routeBuildID
        let transportType = session.roadTransportType
        isRouting = true
        completedLegs = 0
        totalLegs = points.count - 1
        routeBuildTask = Task { @MainActor in
            do {
                let coords = try await RouteBuilder.roadRoute(through: points.map(\.coordinate), transportType: transportType) { done, total in
                    guard requestID == routeBuildID, !Task.isCancelled else { return }
                    completedLegs = done
                    totalLegs = total
                }
                guard requestID == routeBuildID, !Task.isCancelled else { return }
                setPreparedRoute(coords, isRoad: true)
            } catch {
                guard requestID == routeBuildID, !Task.isCancelled else { return }
                routeBuildError = error.localizedDescription
            }
            isRouting = false
            routeBuildTask = nil
        }
    }

    private func playRoute() {
        guard !isRouting, !session.routeSimulation.canStop else { return }
        guard routeCoords.count >= 2 else {
            session.lastError = String(localized: "Build or draw a route first.")
            return
        }
        session.followRoute(routeCoords, pairing: pairing)
        if session.status == .active { showRouteSheet = false }
    }

    private func importGPX(_ url: URL) {
        do {
            let coords = try GPXCodec.parse(url)
            cancelRoadBuild()
            setPreparedRoute(RouteBuilder.sample(coordinates: coords, every: 10), isRoad: false)
            drawnPath.removeAll()
            drawMode = false
            if let first = coords.first {
                pinPlaceName = nil
                session.pin = first
                position = .region(MKCoordinateRegion(center: first, latitudinalMeters: 2000, longitudinalMeters: 2000))
            }
        } catch {
            session.lastError = error.localizedDescription
        }
    }

    private var routePickingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Tap the map or search to add stops in order."))
                .font(.subheadline.weight(.semibold))
            HStack {
                Text(String(format: String(localized: "%lld route stops"), Int64(routeStops.count)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Undo")) { if !routeStops.isEmpty { routeStops.removeLast() } }
                    .disabled(routeStops.isEmpty)
                Button(String(localized: "Done")) {
                    routePicking = false
                    showRouteSheet = true
                }
                .fontWeight(.semibold)
            }
            .frame(minHeight: 44)
        }
        .padding(12)
        .tint(LocusTheme.accent)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var routeBuildBanner: some View {
        HStack {
            ProgressView().tint(LocusTheme.accent)
            Text(String(format: String(localized: "Building segment %lld of %lld"),
                        Int64(min(completedLegs + 1, max(1, totalLegs))), Int64(max(1, totalLegs))))
                .font(.subheadline)
            Spacer()
            Button(String(localized: "Cancel"), action: cancelRoadBuild)
                .frame(minHeight: 44)
        }
        .padding(12)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func exportGPX() {
        let path = routeCoords
        guard !path.isEmpty else {
            session.lastError = String(localized: "Nothing to export.")
            return
        }
        let gpx = GPXCodec.export(path)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Locus-Route.gpx")
        do {
            try gpx.data(using: .utf8)?.write(to: url)
            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.keyWindow?.rootViewController {
                var presenter = root
                while let next = presenter.presentedViewController { presenter = next }
                if let popover = av.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
                    popover.permittedArrowDirections = []
                }
                presenter.present(av, animated: true)
            }
        } catch {
            session.lastError = error.localizedDescription
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
}

@MainActor
final class PlaceSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    var query: String = "" {
        didSet {
            completer.queryFragment = query
        }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results
        Task { @MainActor in self.results = items }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}
