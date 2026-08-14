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

    @EnvironmentObject var appState: AppState
    @StateObject private var searchService = LocationSearchService()
    @ObservedObject private var favorites = LocationFavoritesManager.shared

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
        )
    )
    @State private var showSearchResults: Bool = false
    @AppStorage("keepLocationCentered") private var keepCentered: Bool = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            mapView

            VStack {
                topSearch
                Spacer()
            }
            .padding(16)

            VStack {
                HStack {
                    Spacer()
                    zoomStack
                }
                Spacer()
            }
            .padding(16)

            if mode == .joystick {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        JoystickControlView()
                            .padding(28)
                    }
                }
            }

            VStack {
                Spacer()
                HStack {
                    HStack(spacing: 8) {
                        Capsule().fill(Organic.neutral700).frame(width: 34, height: 3)
                        Text("500 m")
                            .font(Organic.body(10.5))
                            .foregroundStyle(Organic.neutral700)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Organic.neutral100.opacity(0.75))
                    .clipShape(Capsule())
                    Spacer()
                    Text("© PathChanger Maps · OSM")
                        .font(Organic.body(10.5))
                        .foregroundStyle(Organic.neutral600)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Organic.neutral100.opacity(0.75))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .onAppear {
            appState.activeMode = mode
        }
        .onChange(of: mode) { _, newMode in
            appState.activeMode = newMode
        }
        .onChange(of: appState.currentLocation) { _, newLocation in
            guard keepCentered, let location = newLocation else { return }
            withAnimation {
                position = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                ))
            }
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
                if let location = appState.currentLocation ?? appState.targetLocation {
                    Annotation("Location", coordinate: location.clLocationCoordinate2D) {
                        ZStack {
                            Circle()
                                .fill(Organic.accent300.opacity(0.45))
                                .frame(width: 34, height: 34)
                            Circle()
                                .fill(Organic.accent600)
                                .frame(width: 15, height: 15)
                                .overlay(Circle().stroke(Organic.neutral100, lineWidth: 3))
                                .shadow(color: Organic.neutral900.opacity(0.2), radius: 6, y: 2)
                        }
                    }
                }

                if mode == .route && appState.currentRoute.count >= 2 {
                    MapPolyline(coordinates: appState.currentRoute.map(\.clLocationCoordinate2D))
                        .stroke(Organic.sage700, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [1, 4]))
                }

                if mode == .route {
                    ForEach(Array(appState.currentRoute.enumerated()), id: \.offset) { index, coord in
                        Annotation("Spot \(index + 1)", coordinate: coord.clLocationCoordinate2D) {
                            Text("\(index + 1)")
                                .font(Organic.body(11, weight: .bold))
                                .foregroundStyle(Organic.neutral100)
                                .frame(width: 22, height: 22)
                                .background(index == 0 ? Organic.sage600 : Organic.accent600)
                                .clipShape(Circle())
                                .shadow(color: Organic.neutral900.opacity(0.18), radius: 4, y: 1)
                        }
                    }
                }
            }
            .mapStyle(mapStyle.style)
            .onTapGesture { screenPoint in
                if let coordinate = proxy.convert(screenPoint, from: .local) {
                    handleMapTap(at: coordinate)
                }
            }
        }
    }

    private var topSearch: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Organic.neutral600)
                    TextField("Search a place or paste coordinates", text: $searchService.searchText)
                        .textFieldStyle(.plain)
                        .font(Organic.body(12.5))
                        .onChange(of: searchService.searchText) { _, newValue in
                            showSearchResults = !newValue.isEmpty
                        }
                        .onSubmit {
                            if let first = searchService.searchResults.first {
                                selectSearchResult(first)
                            }
                        }
                    if searchService.isSearching {
                        ProgressView().scaleEffect(0.6)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Organic.neutral100)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Organic.neutral300, lineWidth: 1))
                .shadow(color: Organic.neutral900.opacity(0.08), radius: 4, y: 1)

                if showSearchResults && !searchService.searchResults.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(searchService.searchResults.prefix(5)) { result in
                            Button {
                                selectSearchResult(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name)
                                        .font(Organic.body(13, weight: .medium))
                                        .foregroundStyle(Organic.text)
                                    Text(result.subtitle)
                                        .font(Organic.body(11))
                                        .foregroundStyle(Organic.neutral600)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Organic.neutral100)
                    .clipShape(RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous)
                            .stroke(Organic.neutral300, lineWidth: 1)
                    )
                    .shadow(color: Organic.neutral900.opacity(0.16), radius: 10, y: 4)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: 340)

            Button {
                toggleStar()
            } label: {
                Image(systemName: currentIsFavorite ? "star.fill" : "star")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(currentIsFavorite ? Organic.accent600 : Organic.neutral700)
                    .frame(width: 36, height: 36)
                    .background(Organic.neutral100)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Organic.neutral300, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(appState.targetLocation == nil && appState.currentLocation == nil)

            Spacer()
        }
    }

    private var zoomStack: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                Button("+") { zoom(0.6) }
                    .buttonStyle(.plain)
                    .font(Organic.body(16))
                    .foregroundStyle(Organic.neutral700)
                    .frame(width: 32, height: 30)
                Rectangle().fill(Organic.neutral300).frame(height: 1)
                Button("−") { zoom(1.6) }
                    .buttonStyle(.plain)
                    .font(Organic.body(16))
                    .foregroundStyle(Organic.neutral700)
                    .frame(width: 32, height: 30)
            }
            .background(Organic.neutral100)
            .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                    .stroke(Organic.neutral300, lineWidth: 1)
            )

            Button {
                if let location = appState.currentLocation ?? appState.targetLocation {
                    position = .region(MKCoordinateRegion(
                        center: location.clLocationCoordinate2D,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            } label: {
                Image(systemName: "location.north.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Organic.neutral700)
                    .frame(width: 32, height: 32)
                    .background(Organic.neutral100)
                    .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                            .stroke(Organic.neutral300, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var currentIsFavorite: Bool {
        guard let location = appState.targetLocation ?? appState.currentLocation else { return false }
        return favorites.isFavorite(location)
    }

    private func toggleStar() {
        guard let location = appState.targetLocation ?? appState.currentLocation else { return }
        favorites.toggleFavorite(name: addressText, coordinate: location)
    }

    private func zoom(_ factor: Double) {
        if let location = appState.currentLocation ?? appState.targetLocation {
            position = .region(MKCoordinateRegion(
                center: location.clLocationCoordinate2D,
                span: MKCoordinateSpan(latitudeDelta: 0.02 * factor, longitudeDelta: 0.02 * factor)
            ))
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
        favorites.recordRecent(name: addressText, coordinate: location)

        switch mode {
        case .route:
            guard !appState.isSimulating else {
                appState.statusMessage = "Stop playback before adding spots"
                return
            }
            appState.addRouteWaypoint(location)
        case .joystick:
            appState.targetLocation = location
            appState.statusMessage = String(format: "Start set: %.4f, %.4f", coordinate.latitude, coordinate.longitude)
            if appState.isSimulating {
                Task { await appState.setLocation(location, quiet: true, usePerformanceMode: true) }
            }
        case .teleport, .settings:
            appState.targetLocation = location
            appState.statusMessage = String(format: "Location set: %.4f, %.4f", coordinate.latitude, coordinate.longitude)
            if appState.selectedDevice != nil && !appState.isSimulating {
                Task { await appState.setLocation(location) }
            }
        }
    }

    private func selectSearchResult(_ result: LocationSearchResult) {
        let coordinate = result.coordinate
        latitudeInput = String(format: "%.6f", coordinate.latitude)
        longitudeInput = String(format: "%.6f", coordinate.longitude)
        addressText = result.name
        searchService.clearSearch()
        showSearchResults = false
        favorites.recordRecent(name: result.name, coordinate: coordinate)

        withAnimation {
            position = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }

        switch mode {
        case .route:
            if !appState.isSimulating {
                appState.addRouteWaypoint(coordinate)
            }
        case .joystick:
            appState.targetLocation = coordinate
        case .teleport, .settings:
            appState.targetLocation = coordinate
            if appState.selectedDevice != nil && !appState.isSimulating {
                Task { await appState.setLocation(coordinate) }
            }
        }
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

enum MapStyleType: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case satellite = "Satellite"
    case hybrid = "Hybrid"

    var id: String { rawValue }

    var style: MapStyle {
        switch self {
        case .standard: return .standard(elevation: .realistic)
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
