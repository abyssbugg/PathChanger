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

    var body: some View {
        ZStack {
            mapView
                .toolbar(.hidden)
                .mapControlVisibility(.hidden)
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
        }
        .onChange(of: mode) { _, newMode in
            appState.activeMode = newMode
        }
        .onChange(of: appState.locationPresentation.appliedCoordinate) { _, newLocation in
            guard keepCentered, let location = newLocation else { return }
            withAnimation { focus(location) }
        }
        .onChange(of: appState.locationPresentation.desiredCoordinate) { _, newLocation in
            guard let location = newLocation, !appState.locationPresentation.isMovementActive else { return }
            withAnimation { focus(location) }
        }
        .fileImporter(
            isPresented: $appState.showRouteImport,
            allowedContentTypes: routeFileTypes,
            allowsMultipleSelection: false
        ) { result in
            handleRouteImport(result)
        }
    }

    private var mapView: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: [.all]) {
                if let location = appState.locationPresentation.appliedCoordinate ?? appState.locationPresentation.desiredCoordinate {
                    Annotation("Location", coordinate: location.clLocationCoordinate2D) {
                        ZStack {
                            Circle()
                                .fill(Organic.accent300.opacity(0.45))
                                .frame(width: 34, height: 34)
                            Circle()
                                .fill(Organic.accent600)
                                .frame(width: 15, height: 15)
                                .overlay(Circle().stroke(Organic.neutral100, lineWidth: 3))
                                .shadow(color: Organic.shadow.opacity(0.2), radius: 6, y: 2)
                        }
                    }
                }

                if mode.showsRouteList && appState.currentRoute.count >= 2 {
                    MapPolyline(coordinates: polylineCoordinates)
                        .stroke(Organic.accent600, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [1, 5]))
                }

                if mode.showsRouteList {
                    ForEach(Array(appState.currentRoute.enumerated()), id: \.offset) { index, coord in
                        Annotation("Spot \(index + 1)", coordinate: coord.clLocationCoordinate2D) {
                            Text("\(index + 1)")
                                .font(Organic.body(11, weight: .bold))
                                .foregroundStyle(Organic.neutral100)
                                .frame(width: 22, height: 22)
                                .background(index == 0 ? Organic.sage600 : Organic.accent600)
                                .clipShape(Circle())
                                .shadow(color: Organic.shadow.opacity(0.18), radius: 4, y: 1)
                                .onTapGesture(count: 2) {
                                    appState.removeRouteWaypoint(at: index)
                                }
                        }
                    }
                }
            }
            .mapStyle(mapStyle.style)
            .mapControlVisibility(.hidden)
            .onMapCameraChange(frequency: .onEnd) { context in
                currentRegion = context.region
            }
            .onTapGesture { screenPoint in
                if let coordinate = proxy.convert(screenPoint, from: .local) {
                    handleMapTap(at: coordinate)
                }
            }
        }
    }

    private var mapFooter: some View {
        HStack {
            Spacer()
            if showCoordinatesOnMap, let location = appState.locationPresentation.appliedCoordinate ?? appState.locationPresentation.desiredCoordinate {
                Text(String(format: "%.6f, %.6f", location.latitude, location.longitude))
                    .font(Organic.mono(10.5))
                    .foregroundStyle(Organic.neutral700)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Organic.neutral100.opacity(0.75))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.trailing, 60)
    }

    private func focus(_ location: LocationCoordinate) {
        position = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        ))
    }

    private var zoomStack: some View {
        VStack(spacing: 7) {
            Text(scaleLabel)
                .font(Organic.body(10, weight: .bold))
                .foregroundStyle(Organic.neutral700)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Organic.neutral100.opacity(0.86))
                .overlay(Capsule().stroke(Organic.neutral300, lineWidth: 1))
                .clipShape(Capsule())

            Button {
                if let location = appState.locationPresentation.appliedCoordinate ?? appState.locationPresentation.desiredCoordinate {
                    position = .region(MKCoordinateRegion(
                        center: location.clLocationCoordinate2D,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
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

    private var scaleLabel: String {
        let meters = currentRegion.span.latitudeDelta * 111_000 * 0.18
        if meters >= 1000 {
            return String(format: "%.0f km", meters / 1000)
        }
        return "\(max(10, Int(meters.rounded()))) m"
    }

    private var polylineCoordinates: [CLLocationCoordinate2D] {
        var points = appState.currentRoute.map(\.clLocationCoordinate2D)
        if mode == .twospot, let start = appState.locationPresentation.appliedCoordinate {
            points.insert(start.clLocationCoordinate2D, at: 0)
        }
        return points
    }

    private func zoom(_ factor: Double) {
        let center = currentRegion.center
        let span = MapZoom.scaled(currentRegion.span, factor: factor)
        let region = MKCoordinateRegion(center: center, span: span)
        currentRegion = region
        position = .region(region)
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
            appState.importRoute(from: url)
        case .failure(let error):
            appState.lastError = error.localizedDescription
            appState.statusMessage = error.localizedDescription
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

enum MapStyleType: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case satellite = "Satellite"
    case hybrid = "Hybrid"

    var id: String { rawValue }

    var style: MapStyle {
        switch self {
        case .standard: return .standard(elevation: .flat, emphasis: .muted)
        case .satellite: return .imagery
        case .hybrid: return .hybrid
        }
    }
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
