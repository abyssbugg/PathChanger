//
//  SimulationView.swift
//  PathChanger
//
//  Modern Pro UI - Main simulation view with map and controls
//  Based on ProposedDesign with full backend integration
//

import SwiftUI
import MapKit

struct SimulationView: View {
    let mode: AppMode
    @EnvironmentObject var appState: AppState
    @StateObject private var searchService = LocationSearchService()
    
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )
    @State private var mapStyle: MapStyleType = .standard
    @State private var showSearchResults: Bool = false
    @State private var showCoordinateInput: Bool = false
    @State private var latitudeInput: String = ""
    @State private var longitudeInput: String = ""
    @State private var routeType: RouteType = .navigation
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Full Screen Map
            mapView
                .ignoresSafeArea()
            
            // 2. Top Controls (Search & Map Style)
            VStack {
                topControls
                Spacer()
            }
            
            // 3. Floating Action Panel
            VStack(spacing: 16) {
                // Mode-specific controls
                modeSpecificControls
                
                // Main control panel
                mainControlPanel
            }
            .padding(.bottom, 30)
        }
        .onChange(of: appState.currentLocation) { _, newLocation in
            if let location = newLocation {
                withAnimation {
                    position = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            }
        }
    }
    
    // MARK: - Map View
    
    @ViewBuilder
    private var mapView: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: [.all]) {
                // Current/Target location marker
                if let location = appState.currentLocation ?? appState.targetLocation {
                    Annotation("Location", coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)) {
                        ZStack {
                            Circle()
                                .fill(.blue.opacity(0.3))
                                .frame(width: 60, height: 60)
                            Circle()
                                .fill(.blue)
                                .frame(width: 20, height: 20)
                            Circle()
                                .stroke(.white, lineWidth: 3)
                                .frame(width: 20, height: 20)
                        }
                        .shadow(color: .blue.opacity(0.5), radius: 10)
                    }
                }
                
                // Route markers if in route mode
                if mode == .route && !appState.currentRoute.isEmpty {
                    ForEach(Array(appState.currentRoute.enumerated()), id: \.offset) { index, coord in
                        Marker("Point \(index + 1)", coordinate: CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude))
                            .tint(index == 0 ? .green : (index == appState.currentRoute.count - 1 ? .red : .orange))
                    }
                }
            }
            .mapStyle(mapStyle.style)
            .onTapGesture { screenPoint in
                // Convert tap point to map coordinate using MapProxy
                if let coordinate = proxy.convert(screenPoint, from: .local) {
                    handleMapTap(at: coordinate)
                }
            }
        }
    }
    
    /// Handle tap on map to set location
    private func handleMapTap(at coordinate: CLLocationCoordinate2D) {
        // Validate the coordinate
        guard coordinate.latitude >= -90 && coordinate.latitude <= 90 &&
              coordinate.longitude >= -180 && coordinate.longitude <= 180 else {
            appState.statusMessage = "Invalid coordinates from tap"
            return
        }
        
        let location = LocationCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        
        // Update coordinate input fields for reference
        latitudeInput = String(format: "%.6f", coordinate.latitude)
        longitudeInput = String(format: "%.6f", coordinate.longitude)
        
        // Set the target location
        appState.targetLocation = location
        appState.statusMessage = String(format: "Location set: %.4f, %.4f", coordinate.latitude, coordinate.longitude)
        
        // If a device is selected and not simulating, we can directly apply the location
        if appState.selectedDevice != nil && !appState.isSimulating {
            Task {
                await appState.setLocation(location)
            }
        }
    }
    
    // MARK: - Top Controls
    
    private var topControls: some View {
        HStack(spacing: 12) {
            // Search bar with autocomplete
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search location or coordinates...", text: $searchService.searchText)
                        .textFieldStyle(.plain)
                        .onChange(of: searchService.searchText) { _, newValue in
                            showSearchResults = !newValue.isEmpty
                        }
                        .onSubmit {
                            if let firstResult = searchService.searchResults.first {
                                selectSearchResult(firstResult)
                            }
                        }
                    
                    if searchService.isSearching {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    
                    if !searchService.searchText.isEmpty {
                        Button {
                            searchService.clearSearch()
                            showSearchResults = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // Search results dropdown
                if showSearchResults && !searchService.searchResults.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(searchService.searchResults.prefix(5)) { result in
                            Button {
                                selectSearchResult(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text(result.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .background(Color.clear)
                            .contentShape(Rectangle())
                            
                            if result.id != searchService.searchResults.prefix(5).last?.id {
                                Divider()
                                    .padding(.horizontal, 8)
                            }
                        }
                    }
                    .background(.ultraThickMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: 400)
            
            Spacer()
            
            // Map style picker
            HStack(spacing: 0) {
                ForEach(MapStyleType.allCases) { style in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mapStyle = style
                        }
                    } label: {
                        Text(style.rawValue)
                            .font(.system(size: 13, weight: mapStyle == style ? .semibold : .regular))
                            .foregroundStyle(mapStyle == style ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(mapStyle == style ? Color.blue : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            
            // Current location button
            Button {
                if let location = appState.currentLocation {
                    withAnimation {
                        position = .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))
                    }
                }
            } label: {
                Image(systemName: "location.fill")
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(appState.currentLocation == nil)
        }
        .padding()
    }
    
    // MARK: - Mode Specific Controls
    
    @ViewBuilder
    private var modeSpecificControls: some View {
        switch mode {
        case .teleport:
            teleportControls
        case .route:
            routeControls
        case .joystick:
            JoystickControlView()
        case .settings:
            EmptyView()
        }
    }
    
    // MARK: - Teleport Controls
    
    private var teleportControls: some View {
        HStack(spacing: 12) {
            // Coordinate input
            HStack(spacing: 8) {
                TextField("Latitude", text: $latitudeInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                
                TextField("Longitude", text: $longitudeInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                
                Button("Go") {
                    teleportToCoordinates()
                }
                .buttonStyle(.borderedProminent)
                .disabled(latitudeInput.isEmpty || longitudeInput.isEmpty)
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Route Controls
    
    private var routeControls: some View {
        VStack(spacing: 12) {
            // Route type toggle
            Picker("Route Type", selection: $routeType) {
                Text("Navigation").tag(RouteType.navigation)
                Text("Straight").tag(RouteType.straight)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Route info
            if !appState.currentRoute.isEmpty {
                HStack {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .foregroundStyle(.blue)
                    Text("\(appState.currentRoute.count) points")
                        .font(.caption)
                    
                    if appState.isSimulating {
                        Text("• \(Int(appState.routeProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            
            // Import route button
            Button {
                appState.showRouteImport = true
            } label: {
                Label("Import GPX", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - Main Control Panel
    
    private var mainControlPanel: some View {
        HStack(spacing: 24) {
            // Speed Control
            VStack(alignment: .leading, spacing: 6) {
                Text("Speed: \(appState.simulationSpeed.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                
                HStack(spacing: 8) {
                    ForEach(SimulationSpeed.allCases, id: \.self) { speed in
                        Button {
                            appState.setSpeed(speed)
                        } label: {
                            Image(systemName: speed.icon)
                                .font(.caption)
                                .frame(width: 32, height: 32)
                                .background(appState.simulationSpeed == speed ? .blue : .clear)
                                .foregroundStyle(appState.simulationSpeed == speed ? .white : .secondary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Divider()
                .frame(height: 40)
            
            // Play/Pause Button
            Button {
                Task {
                    if appState.isSimulating {
                        if appState.isPaused {
                            appState.resumeSimulation()
                        } else {
                            appState.pauseSimulation()
                        }
                    } else {
                        await appState.startSimulation()
                    }
                }
            } label: {
                Image(systemName: playButtonIcon)
                    .font(.title2)
                    .frame(width: 50, height: 50)
                    .background(playButtonColor)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!appState.canStartSimulation && !appState.isSimulating)
            
            // Stop Button
            Button {
                Task {
                    await appState.stopSimulation()
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(.red.opacity(appState.isSimulating ? 0.2 : 0.1))
                    .foregroundStyle(.red)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!appState.isSimulating)
            
            Divider()
                .frame(height: 40)
            
            // Status
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.simulationStatusText)
                    .font(.caption)
                    .fontWeight(.medium)
                
                if let location = appState.currentLocation {
                    Text(location.formattedShort)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    // MARK: - Helper Properties
    
    private var playButtonIcon: String {
        if appState.isSimulating && !appState.isPaused {
            return "pause.fill"
        }
        return "play.fill"
    }
    
    private var playButtonColor: Color {
        if appState.isSimulating && !appState.isPaused {
            return .orange
        }
        return .blue
    }
    
    // MARK: - Actions
    
    private func teleportToCoordinates() {
        guard let lat = Double(latitudeInput),
              let lon = Double(longitudeInput) else {
            withAnimation {
                appState.statusMessage = "Invalid coordinates"
            }
            return
        }
        
        let coordinate = LocationCoordinate(latitude: lat, longitude: lon)
        guard coordinate.isValid else {
            withAnimation {
                appState.statusMessage = "Coordinates out of range"
            }
            return
        }
        
        Task {
            await appState.setLocation(coordinate)
            withAnimation {
                appState.statusMessage = "Teleported to \(coordinate.formattedShort)"
            }
        }
    }
    
    private func selectSearchResult(_ result: LocationSearchResult) {
        let coordinate = result.coordinate
        
        // Update UI state
        latitudeInput = String(format: "%.6f", coordinate.latitude)
        longitudeInput = String(format: "%.6f", coordinate.longitude)
        
        // Set the target location
        appState.targetLocation = coordinate
        
        // Clear search and hide results
        searchService.clearSearch()
        showSearchResults = false
        
        // Move map to location
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
        
        appState.statusMessage = "Selected: \(result.name)"
        
        // If device is selected, apply location immediately
        if appState.selectedDevice != nil && !appState.isSimulating {
            Task {
                await appState.setLocation(coordinate)
            }
        }
    }
}

// MARK: - Map Style

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

// MARK: - Route Type

enum RouteType: String {
    case navigation
    case straight
}

// MARK: - Preview

#if DEBUG
struct SimulationView_Previews: PreviewProvider {
    static var previews: some View {
        SimulationView(mode: .teleport)
            .environmentObject(AppState())
            .preferredColorScheme(.dark)
    }
}
#endif
