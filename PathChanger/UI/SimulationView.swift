//
//  SimulationView.swift
//  PathChanger
//
//  Map canvas from the pth mock.
//

import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct SimulationView: View {
    let mode: AppMode
    @Binding var mapStyle: MapStyleType
    @Binding var latitudeInput: String
    @Binding var longitudeInput: String
    @Binding var addressText: String
    var onPickLocation: ((LocationCoordinate, String) -> Void)?

    @EnvironmentObject var appState: AppState
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 6.4474, longitude: 3.3903),
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
        )
    )
    @State private var currentRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 6.4474, longitude: 3.3903),
        span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
    )
    @AppStorage("keepLocationCentered") private var keepCentered: Bool = true
    @AppStorage("showCoordinatesOnMap") private var showCoordinatesOnMap: Bool = true
    // The map layers (MapKit Phase 1, 2026-11-06): 3D elevation is opt-in, traffic is
    // off, places are on. Each persists separately.
    @AppStorage(MapLayerConfiguration.elevationKey) private var mapElevation3D: Bool = false
    @AppStorage(MapLayerConfiguration.trafficKey) private var mapShowsTraffic: Bool = false
    @AppStorage(MapLayerConfiguration.placesKey) private var mapShowsPlaces: Bool = true
    @State private var followMode: MapFollowMode = .following
    /// The camera MapKit last reported: the source of truth for preserving distance,
    /// heading and pitch across recenters and zooms. nil until the first camera change.
    @State private var lastKnownCamera: MapCameraState?
    /// Syncs the persisted base style into the binding once per launch: the binding
    /// lives in ContentView, which initializes it to Standard on every launch.
    private static var didSyncBaseStyleThisLaunch = false

    private var mapLayer: MapLayerConfiguration {
        MapLayerConfiguration(elevation3D: mapElevation3D, showsTraffic: mapShowsTraffic, showsPlaces: mapShowsPlaces)
    }

    var body: some View {
        ZStack {
            mapView
                .toolbar(.hidden)
                .clipped()

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    if mode == .joystick {
                        JoystickControlView()
                            .padding(.leading, 24)
                            .padding(.bottom, 24)
                    }
                    Spacer()
                    zoomStack
                        .padding(.trailing, 16)
                        .padding(.bottom, 20)
                }
            }

            VStack {
                Spacer()
                mapFooter
            }
        }
        .onAppear {
            appState.activeMode = mode
            appState.placeNameResolver?.update(for: appState.locationPresentation.appliedCoordinate)
            if !Self.didSyncBaseStyleThisLaunch {
                Self.didSyncBaseStyleThisLaunch = true
                if let stored = MapLayerConfiguration.readBaseStyle(from: .standard) {
                    mapStyle = stored
                }
                followMode = keepCentered ? .following : .off
            }
        }
        .onChange(of: mode) { _, newMode in
            appState.activeMode = newMode
        }
        // The planned route refetches only when its stops, directions or options change.
        .onChange(of: appState.routePreviewKey(for: mode), initial: true) { _, key in
            appState.routePreview.update(key)
        }
        .onChange(of: appState.locationPresentation.appliedCoordinate) { _, newLocation in
            appState.placeNameResolver?.update(for: newLocation)
            guard keepCentered, let location = newLocation else { return }
            // Steps arrive at up to 10 Hz while moving: move the camera without animating.
            follow(location, animated: !isMoving)
        }
        .onChange(of: appState.locationPresentation.desiredCoordinate) { _, newLocation in
            guard let location = newLocation, !appState.locationPresentation.isMovementActive else { return }
            follow(location, animated: true)
        }
        // A camera the user moved themselves pauses following: MapKit marks the position
        // positionedByUser, which programmatic writes never do.
        .onChange(of: position) { _, newPosition in
            if newPosition.positionedByUser {
                followMode = followMode.afterUserMovedCamera()
            }
        }
        // Every style source (the on-map menu and ContentView's cycling) lands here, so
        // the persisted base style never disagrees with what is on screen.
        .onChange(of: mapStyle) { _, newStyle in
            MapLayerConfiguration.writeBaseStyle(newStyle, to: .standard)
        }
        .fileImporter(
            isPresented: $appState.showRouteImport,
            allowedContentTypes: routeFileTypes,
            allowsMultipleSelection: false
        ) { result in
            handleRouteImport(result)
        }
    }

    /// The map, rebuilt only when what it draws changes (see `SimulationMapCanvas`).
    private var mapView: some View {
        let showsRoute = mode.showsRouteList
        return SimulationMapCanvas(
            marker: appState.locationMarker,
            mode: mode,
            legs: showsRoute ? appState.routePreview.legs : [],
            trailSegments: showsRoute ? appState.travelTrail.segments(for: mode).filter { $0.count >= 2 } : [],
            routeStops: showsRoute ? appState.currentRoute : [],
            mapStyle: mapStyle,
            mapLayer: mapLayer,
            cameraPosition: position,
            position: $position,
            onCameraChangeEnd: { region, camera in
                currentRegion = region
                lastKnownCamera = camera
            },
            onTap: { coordinate in handleMapTap(at: coordinate) },
            onRemoveStop: { index in appState.removeRouteWaypoint(at: index) }
        )
        .equatable()
    }

    private var mapFooter: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if mode.showsRouteList,
                   let legend = RoutePreviewPlanner.legendText(for: appState.routePreview.legs.map(\.style)) {
                    Text(legend)
                        .font(Organic.body(10, weight: .semibold))
                        .foregroundStyle(Organic.neutral700)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Organic.neutral100.opacity(0.75))
                        .clipShape(Capsule())
                        .accessibilityLabel("Map key: \(legend)")
                        .accessibilityIdentifier("map.routeLegend")
                }
                if showCoordinatesOnMap, let location = appState.locationPresentation.appliedCoordinate ?? appState.locationPresentation.desiredCoordinate {
                    if appState.locationPresentation.appliedCoordinate != nil, let resolver = appState.placeNameResolver {
                        PlaceNameLabel(resolver: resolver)
                    }
                    Text(String(format: "%.6f, %.6f", location.latitude, location.longitude))
                        .font(Organic.mono(10.5))
                        .foregroundStyle(Organic.neutral700)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Organic.neutral100.opacity(0.75))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.trailing, 60)
    }

    private var isMoving: Bool {
        appState.locationPresentation.isMovementActive || appState.isMovementEngineRunning
    }

    /// Keeps the spoofed point on screen at the user's zoom, tilt and rotation; the
    /// camera moves only when the point leaves the middle of the visible map
    /// (PRODUCT_REQUIREMENTS 3.5, owner decision 2026-11-02; pitch and heading are
    /// preserved since MapKit Phase 1, 2026-11-06). `currentRegion` follows so the
    /// dead-zone check and the zoom buttons work from the new centre.
    private func follow(_ location: LocationCoordinate, animated: Bool) {
        guard followMode.isFollowing else { return }
        let point = location.clLocationCoordinate2D
        guard MapFollow.needsRecentering(point, in: currentRegion) else { return }
        if let camera = lastKnownCamera, !camera.isEffectivelyFlat {
            let moved = camera.moved(to: point)
            lastKnownCamera = moved
            currentRegion.center = point
            apply(moved.cameraPosition, animated: animated)
        } else {
            let region = MapFollow.region(centeredOn: point, keeping: currentRegion)
            currentRegion = region
            apply(.region(region), animated: animated)
        }
    }

    private func apply(_ newPosition: MapCameraPosition, animated: Bool) {
        if animated {
            withAnimation { position = newPosition }
        } else {
            position = newPosition
        }
    }

    private var zoomStack: some View {
        VStack(spacing: 7) {
            mapLayerMenu

            Button {
                centerOnDevice()
            } label: {
                Image(systemName: "dot.viewfinder")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Organic.neutral700)
                    .frame(width: 36, height: 36)
                    .background(Organic.neutral100)
                    .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                            .stroke(Organic.neutral300, lineWidth: 1)
                    )
                    .shadow(color: Organic.shadow.opacity(0.08), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .help("Center on device")
            .accessibilityLabel("Center on device")

            VStack(spacing: 0) {
                Button { zoom(0.8) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Organic.neutral700)
                        .frame(width: 36, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zoom in")
                Rectangle().fill(Organic.neutral300).frame(height: 1)
                Button { zoom(1.25) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Organic.neutral700)
                        .frame(width: 36, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zoom out")
            }
            .background(Organic.neutral100)
            .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                    .stroke(Organic.neutral300, lineWidth: 1)
            )
            .shadow(color: Organic.shadow.opacity(0.08), radius: 3, y: 1)
        }
        .frame(width: 36)
        .fixedSize()
    }

    /// The on-map style and layer menu (MapKit Phase 1, 2026-11-06): the base style,
    /// the optional layers, and the follow preference. Traffic and places are shown but
    /// disabled on Satellite imagery, where MapKit has no parameters for them.
    private var mapLayerMenu: some View {
        Menu {
            Picker("Map style", selection: $mapStyle) {
                ForEach(MapStyleType.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.inline)
            Section("Layers") {
                Toggle("3D Terrain", isOn: $mapElevation3D)
                Toggle("Traffic", isOn: $mapShowsTraffic)
                    .disabled(!MapLayerConfiguration.supportsTraffic(mapStyle))
                Toggle("Places", isOn: $mapShowsPlaces)
                    .disabled(!MapLayerConfiguration.supportsPlaces(mapStyle))
            }
            Toggle("Keep the point centered", isOn: Binding(
                get: { keepCentered && followMode != .off },
                set: { on in
                    keepCentered = on
                    followMode = on ? .following : .off
                }
            ))
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Organic.neutral700)
                .frame(width: 36, height: 36)
                .background(Organic.neutral100)
                .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                        .stroke(Organic.neutral300, lineWidth: 1)
                )
                .shadow(color: Organic.shadow.opacity(0.08), radius: 3, y: 1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 36, height: 36)
        .help("Map style and layers")
        .accessibilityLabel("Map style and layers")
        .accessibilityIdentifier("map.styleAndLayers")
    }

    private func zoom(_ factor: Double) {
        if let camera = lastKnownCamera, !camera.isEffectivelyFlat {
            // A pitched or rotated camera zooms by distance, keeping heading and pitch.
            let zoomed = camera.zoomed(byFactor: factor)
            lastKnownCamera = zoomed
            currentRegion = MKCoordinateRegion(
                center: zoomed.centerCoordinate,
                span: MapZoom.scaled(currentRegion.span, factor: factor)
            )
            position = zoomed.cameraPosition
        } else {
            let center = currentRegion.center
            let span = MapZoom.scaled(currentRegion.span, factor: factor)
            let region = MKCoordinateRegion(center: center, span: span)
            currentRegion = region
            position = .region(region)
        }
    }

    /// The center button: resumes following and moves onto the spoofed point, keeping
    /// the user's zoom, tilt and rotation (MapKit Phase 1, 2026-11-06; it used to force
    /// a 0.01° span, which threw the zoom away).
    private func centerOnDevice() {
        guard let location = appState.locationPresentation.appliedCoordinate
                ?? appState.locationPresentation.desiredCoordinate else { return }
        keepCentered = true
        followMode = followMode.afterCenterPressed
        let point = location.clLocationCoordinate2D
        if let camera = lastKnownCamera, !camera.isEffectivelyFlat {
            let moved = camera.moved(to: point)
            lastKnownCamera = moved
            withAnimation { position = moved.cameraPosition }
        } else {
            let region = MapFollow.region(centeredOn: point, keeping: currentRegion)
            currentRegion = region
            withAnimation { position = .region(region) }
        }
    }

    private func handleMapTap(at coordinate: CLLocationCoordinate2D) {
        guard coordinate.latitude >= -90 && coordinate.latitude <= 90 &&
              coordinate.longitude >= -180 && coordinate.longitude <= 180 else {
            appState.statusMessage = "Invalid coordinates from tap"
            return
        }

        let location = LocationCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        latitudeInput = String(format: "%.6f", coordinate.latitude)
        longitudeInput = String(format: "%.6f", coordinate.longitude)
        addressText = location.formattedShort
        if let onPickLocation {
            onPickLocation(location, addressText)
            return
        }

        appState.stageLocation(location, for: mode)
    }

    private var routeFileTypes: [UTType] {
        var types: [UTType] = [.xml]
        if let gpx = UTType(filenameExtension: "gpx") {
            types.insert(gpx, at: 0)
        }
        return types
    }

    private func handleRouteImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await appState.importRoute(from: url) }
        case .failure(let error):
            appState.lastError = error.localizedDescription
            appState.statusMessage = error.localizedDescription
        }
    }
}

/// The map and what it draws: the location marker, the planned legs, the trail and the
/// stops. It compares what it shows, so a change elsewhere in AppState (a step being sent,
/// a run's countdown, the card, the device list) does not rebuild the map; each rebuild
/// updated MKMapView's configuration, attribution and overlays (GUI lag, 2026-11-03).
struct SimulationMapCanvas: View, Equatable {
    let marker: LocationMarker?
    let mode: AppMode
    let legs: [RoutePreviewModel.Leg]
    let trailSegments: [[LocationCoordinate]]
    let routeStops: [LocationCoordinate]
    let mapStyle: MapStyleType
    /// The optional layers (3D, traffic, places) on top of the base style.
    let mapLayer: MapLayerConfiguration
    /// The camera position this canvas was built with: the binding alone always reads the
    /// current value, so it cannot tell a moved camera apart.
    let cameraPosition: MapCameraPosition
    @Binding var position: MapCameraPosition
    let onCameraChangeEnd: (MKCoordinateRegion, MapCameraState) -> Void
    let onTap: (CLLocationCoordinate2D) -> Void
    let onRemoveStop: (Int) -> Void

#if DEBUG
    /// Builds of the map's content, for the GUI load benchmark (`GUIUpdateLoadTests`).
    static var debugBuildCount = 0
#endif

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.marker == rhs.marker && lhs.mode == rhs.mode && lhs.legs == rhs.legs
            && lhs.trailSegments == rhs.trailSegments && lhs.routeStops == rhs.routeStops
            && lhs.mapStyle == rhs.mapStyle && lhs.mapLayer == rhs.mapLayer
            && lhs.cameraPosition == rhs.cameraPosition
    }

    var body: some View {
#if DEBUG
        Self.debugBuildCount += 1
#endif
        return MapReader { proxy in
            Map(position: $position, interactionModes: [.all]) {
                if let marker {
                    Annotation(marker.accessibilityLabel, coordinate: marker.coordinate.clLocationCoordinate2D) {
                        // Staged (nothing sent, PRODUCT_REQUIREMENTS 5.2): a hollow dashed
                        // ring in a neutral color. Spoofed: the filled accent dot. Uncertain
                        // (applied, but the session holding it is lost or unconfirmed): a
                        // hollow dashed ring in the accent color.
                        ZStack {
                            switch marker.style {
                            case .spoofed:
                                Circle()
                                    .fill(Organic.accent300.opacity(0.45))
                                    .frame(width: 34, height: 34)
                                Circle()
                                    .fill(Organic.accent600)
                                    .frame(width: 15, height: 15)
                                    .overlay(Circle().stroke(Organic.neutral100, lineWidth: 3))
                                    .shadow(color: Organic.shadow.opacity(0.2), radius: 6, y: 2)
                            case .uncertain:
                                Circle()
                                    .fill(Organic.accent100.opacity(0.6))
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        Circle().stroke(Organic.accent600, style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))
                                    )
                                    .shadow(color: Organic.shadow.opacity(0.15), radius: 4, y: 1)
                            case .staged:
                                Circle()
                                    .fill(Organic.neutral100.opacity(0.6))
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle().stroke(Organic.neutral600, style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))
                                    )
                                    .shadow(color: Organic.shadow.opacity(0.15), radius: 4, y: 1)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(marker.accessibilityLabel)
                    }
                }

                if mode.showsRouteList {
                    // Decorative: the stops and the legend carry the meaning.
                    ForEach(legs) { leg in
                        MapPolyline(coordinates: leg.points.map(\.clLocationCoordinate2D))
                            .stroke(RoutePreviewStroke.color(leg.style), style: RoutePreviewStroke.style(leg.style))
                    }
                    // The shown mode's own trail only, one line per segment (travel
                    // never joined by a line the phone did not drive).
                    ForEach(Array(trailSegments.enumerated()), id: \.offset) { _, segment in
                        MapPolyline(coordinates: segment.map(\.clLocationCoordinate2D))
                            .stroke(Organic.sage600, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                }

                if mode.showsRouteList {
                    ForEach(Array(routeStops.enumerated()), id: \.offset) { index, coord in
                        Annotation("Spot \(index + 1)", coordinate: coord.clLocationCoordinate2D) {
                            Text("\(index + 1)")
                                .font(Organic.body(11, weight: .bold))
                                .foregroundStyle(Organic.neutral100)
                                .frame(width: 22, height: 22)
                                .background(index == 0 ? Organic.sage600 : Organic.accent600)
                                .clipShape(Circle())
                                .shadow(color: Organic.shadow.opacity(0.18), radius: 4, y: 1)
                                .onTapGesture(count: 2) {
                                    onRemoveStop(index)
                                }
                        }
                    }
                }
            }
            .mapStyle(mapLayer.mapStyle(for: mapStyle))
            .mapControls {
                MapCompass()
                MapPitchSlider()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                // MapKit always reports the current camera with a change
                // (MapCameraUpdateContext.camera is not optional).
                onCameraChangeEnd(context.region, MapCameraState(context.camera))
            }
            .onTapGesture { screenPoint in
                if let coordinate = proxy.convert(screenPoint, from: .local) {
                    onTap(coordinate)
                }
            }
        }
    }
}

/// How each planned leg is drawn: solid road, dashed straight-line fallback, the old
/// faint dotted line while loading, and a thin dashed connector for a jump.
enum RoutePreviewStroke {
    static func color(_ style: RoutePreviewLegStyle) -> Color {
        switch style {
        case .road: return Organic.accent600
        case .straight: return Organic.accent500
        case .loading: return Organic.accent600.opacity(0.6)
        case .jump: return Organic.neutral600
        }
    }

    static func style(_ style: RoutePreviewLegStyle) -> StrokeStyle {
        switch style {
        case .road: return StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
        case .straight: return StrokeStyle(lineWidth: 3, lineCap: .butt, lineJoin: .round, dash: [8, 6])
        case .loading: return StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [1, 5])
        case .jump: return StrokeStyle(lineWidth: 1.5, lineCap: .butt, lineJoin: .round, dash: [4, 6])
        }
    }
}

enum MapZoom {
    static let minDelta = 0.0008
    static let maxDelta = 80.0

    static func scaled(_ span: MKCoordinateSpan, factor: Double) -> MKCoordinateSpan {
        MKCoordinateSpan(
            latitudeDelta: min(maxDelta, max(minDelta, span.latitudeDelta * factor)),
            longitudeDelta: min(maxDelta, max(minDelta, span.longitudeDelta * factor))
        )
    }
}

/// Keeps the spoofed position on screen without touching the user's zoom
/// (PRODUCT_REQUIREMENTS 3.5, owner decision 2026-11-02).
enum MapFollow {
    /// Used only when the visible span is unusable (zero or not a number).
    static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)

    /// The visible region moved onto `coordinate`, with the span the user chose.
    static func region(centeredOn coordinate: CLLocationCoordinate2D, keeping region: MKCoordinateRegion) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, span: isUsable(region.span) ? region.span : defaultSpan)
    }

    /// Whether `coordinate` has left the middle `innerFraction` of the visible region.
    /// Points inside it leave the camera alone, so movement at up to 10 Hz moves the map
    /// only when the dot nears the edge instead of on every step.
    static func needsRecentering(_ coordinate: CLLocationCoordinate2D, in region: MKCoordinateRegion, innerFraction: Double = 0.5) -> Bool {
        guard isUsable(region.span) else { return true }
        let latitudeOffset = abs(coordinate.latitude - region.center.latitude)
        let longitudeOffset = abs(Geo.normalizedDegrees(coordinate.longitude - region.center.longitude + 180) - 180)
        return latitudeOffset > region.span.latitudeDelta * innerFraction / 2
            || longitudeOffset > region.span.longitudeDelta * innerFraction / 2
    }

    private static func isUsable(_ span: MKCoordinateSpan) -> Bool {
        span.latitudeDelta.isFinite && span.longitudeDelta.isFinite
            && span.latitudeDelta > 0 && span.longitudeDelta > 0
    }
}

/// The camera facts a recenter or zoom must preserve: distance, heading and pitch
/// (MapKit Phase 1, 2026-11-06). Captured from `MapCameraUpdateContext.camera`, which
/// MapKit reports after every camera change.
struct MapCameraState: Equatable {
    let centerCoordinate: CLLocationCoordinate2D
    let distance: Double
    let heading: Double
    let pitch: Double

    /// CLLocationCoordinate2D is not Equatable, so the comparison is written out.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.centerCoordinate.latitude == rhs.centerCoordinate.latitude
            && lhs.centerCoordinate.longitude == rhs.centerCoordinate.longitude
            && lhs.distance == rhs.distance
            && lhs.heading == rhs.heading
            && lhs.pitch == rhs.pitch
    }

    /// Distance bounds mirroring `MapZoom`'s span clamps (0.0008°–80° of latitude is
    /// about 89 m – 8,880 km), so both zoom paths enforce the same envelope.
    static let minDistance: Double = MapZoom.minDelta * 111_000
    static let maxDistance: Double = MapZoom.maxDelta * 111_000

    init(centerCoordinate: CLLocationCoordinate2D, distance: Double, heading: Double = 0, pitch: Double = 0) {
        self.centerCoordinate = centerCoordinate
        self.distance = distance
        self.heading = heading
        self.pitch = pitch
    }

    /// The camera MapKit reported after a change.
    init(_ camera: MapCamera) {
        self.init(
            centerCoordinate: camera.centerCoordinate,
            distance: camera.distance,
            heading: camera.heading,
            pitch: camera.pitch
        )
    }

    /// The same framing over a new point: distance, heading and pitch are kept.
    func moved(to newCenter: CLLocationCoordinate2D) -> MapCameraState {
        MapCameraState(centerCoordinate: newCenter, distance: distance, heading: heading, pitch: pitch)
    }

    /// The camera zoomed by `factor`, the same direction as `MapZoom.scaled` (below 1
    /// zooms in), clamped to the distance bounds.
    func zoomed(byFactor factor: Double) -> MapCameraState {
        MapCameraState(
            centerCoordinate: centerCoordinate,
            distance: min(Self.maxDistance, max(Self.minDistance, distance * factor)),
            heading: heading,
            pitch: pitch
        )
    }

    /// Whether this camera is indistinguishable from the flat, north-up view the region
    /// path produces. A flat camera keeps using the region path, so users who never
    /// tilt or rotate see exactly the pre-Phase-1 behavior.
    var isEffectivelyFlat: Bool {
        pitch < 0.5 && abs(heading.truncatingRemainder(dividingBy: 360)) < 0.5
    }

    var cameraPosition: MapCameraPosition {
        .camera(MapCamera(centerCoordinate: centerCoordinate, distance: distance, heading: heading, pitch: pitch))
    }
}

/// The follow switch's three states (MapKit Phase 1, 2026-11-06): following tracks the
/// spoofed point; a user drag pauses it so exploring the map is never fought; off stops
/// the camera from moving on its own. The persisted keepLocationCentered preference is
/// the off state's storage.
enum MapFollowMode: Equatable {
    case following
    case pausedByUser
    case off

    /// After the user moved the map themselves: following pauses; paused and off stay.
    func afterUserMovedCamera() -> MapFollowMode {
        self == .following ? .pausedByUser : self
    }

    /// The center button always resumes following.
    var afterCenterPressed: MapFollowMode { .following }

    /// Whether automatic recenters act in this mode.
    var isFollowing: Bool { self == .following }
}

/// The decisions one base style plus the layer switches produce, in plain Equatable
/// fields (MapKit's MapStyle is not Equatable, and its Elevation and StandardEmphasis
/// enums are not either). Standard always renders with MapKit's muted emphasis — the
/// app's fixed look — which lives in `MapLayerConfiguration.mapStyle(for:)`.
struct MapStyleRecipe: Equatable {
    var base: MapStyleType
    /// Realistic 3D elevation when true, flat otherwise.
    var elevationIsRealistic: Bool
    var showsPlaces: Bool
    var showsTraffic: Bool
}

/// The map layers on top of the base style: realistic 3D elevation, traffic and places,
/// each persisted separately (defaults: 3D off — it is opt-in; traffic off; places on).
/// Satellite imagery has no traffic or place parameters, so those two layers report
/// themselves unavailable there and the recipe drops them.
struct MapLayerConfiguration: Equatable {
    var elevation3D: Bool
    var showsTraffic: Bool
    var showsPlaces: Bool

    static let `default` = MapLayerConfiguration(elevation3D: false, showsTraffic: false, showsPlaces: true)
    static let elevationKey = "mapElevation3D"
    static let trafficKey = "mapShowsTraffic"
    static let placesKey = "mapShowsPlaces"
    /// The persisted base style; the on-map menu and ContentView's cycling both land
    /// here through SimulationView's onChange(of: mapStyle).
    static let baseStyleKey = "mapBaseStyle"

    /// Whether the base style can show traffic at all.
    static func supportsTraffic(_ base: MapStyleType) -> Bool { base != .satellite }

    /// Whether the base style can show places at all.
    static func supportsPlaces(_ base: MapStyleType) -> Bool { base != .satellite }

    func styleRecipe(for base: MapStyleType) -> MapStyleRecipe {
        MapStyleRecipe(
            base: base,
            elevationIsRealistic: elevation3D,
            showsPlaces: Self.supportsPlaces(base) && showsPlaces,
            showsTraffic: Self.supportsTraffic(base) && showsTraffic
        )
    }

    func mapStyle(for base: MapStyleType) -> MapStyle {
        let recipe = styleRecipe(for: base)
        let elevation: MapStyle.Elevation = recipe.elevationIsRealistic ? .realistic : .flat
        switch recipe.base {
        case .standard:
            return .standard(
                elevation: elevation,
                emphasis: .muted,
                pointsOfInterest: recipe.showsPlaces ? .all : .excludingAll,
                showsTraffic: recipe.showsTraffic
            )
        case .hybrid:
            return .hybrid(
                elevation: elevation,
                pointsOfInterest: recipe.showsPlaces ? .all : .excludingAll,
                showsTraffic: recipe.showsTraffic
            )
        case .satellite:
            return .imagery(elevation: elevation)
        }
    }

    func write(to defaults: UserDefaults) {
        defaults.set(elevation3D, forKey: Self.elevationKey)
        defaults.set(showsTraffic, forKey: Self.trafficKey)
        defaults.set(showsPlaces, forKey: Self.placesKey)
    }

    static func read(from defaults: UserDefaults) -> MapLayerConfiguration {
        MapLayerConfiguration(
            elevation3D: defaults.object(forKey: elevationKey) as? Bool ?? false,
            showsTraffic: defaults.object(forKey: trafficKey) as? Bool ?? false,
            showsPlaces: defaults.object(forKey: placesKey) as? Bool ?? true
        )
    }

    static func writeBaseStyle(_ style: MapStyleType, to defaults: UserDefaults) {
        defaults.set(style.rawValue, forKey: baseStyleKey)
    }

    /// The stored base style, or nil when nothing usable is stored (first launch, or an
    /// unknown value from another build).
    static func readBaseStyle(from defaults: UserDefaults) -> MapStyleType? {
        MapStyleType(rawValue: defaults.string(forKey: baseStyleKey) ?? "")
    }
}

/// The place or street name of the spoofed location, above its coordinates. Shows
/// nothing while no name is known.
private struct PlaceNameLabel: View {
    @ObservedObject var resolver: PlaceNameResolver

    var body: some View {
        if let name = resolver.placeName {
            Text(name)
                .font(Organic.body(11, weight: .semibold))
                .foregroundStyle(Organic.neutral700)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Organic.neutral100.opacity(0.75))
                .clipShape(Capsule())
                .frame(maxWidth: 320, alignment: .trailing)
                .help(name)
                .accessibilityLabel("Place: \(name)")
                .accessibilityIdentifier("map.placeName")
        }
    }
}

enum MapStyleType: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case satellite = "Satellite"
    case hybrid = "Hybrid"

    var id: String { rawValue }
    // The MapStyle each case produces comes from MapLayerConfiguration.mapStyle(for:),
    // which layers 3D elevation, traffic and places on top of the base style.
}

enum RouteType: String {
    case navigation
    case straight
}

#if DEBUG
struct SimulationView_Previews: PreviewProvider {
    static var previews: some View {
        SimulationView(
            mode: .teleport,
            mapStyle: .constant(.standard),
            latitudeInput: .constant("37.774900"),
            longitudeInput: .constant("-122.419400"),
            addressText: .constant("San Francisco")
        )
        .environmentObject(AppState())
    }
}
#endif
