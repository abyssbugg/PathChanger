//
//  SimulationView.swift
//  PathChanger
//
//  Modern Pro UI - Main simulation view with map and controls
//  Based on ProposedDesign with full backend integration
//

import SwiftUI
import MapKit
import UniformTypeIdentifiers
import AppKit

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
    @State private var mapContextAction: MapContextAction?

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
            VStack(spacing: AppSpacing.lg) {
                // Mode-specific controls
                modeSpecificControls

                // Main control panel
                mainControlPanel
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xl)
        }
        .background(Color.pcBackground)
        .preferredColorScheme(.dark)
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
        .fileImporter(
            isPresented: $appState.showRouteImport,
            allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml]
        ) { result in
            handleRouteImport(result)
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
                                .fill(Color.pcAccent.opacity(0.22))
                                .frame(width: 60, height: 60)
                            Circle()
                                .fill(Color.pcAccent)
                                .frame(width: 20, height: 20)
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 20, height: 20)
                        }
                        .shadow(color: Color.pcAccent.opacity(0.55), radius: 12)
                    }
                }

                // Route markers if in route mode
                if mode == .route && !appState.currentRoute.isEmpty {
                    ForEach(Array(appState.currentRoute.enumerated()), id: \.offset) { index, coord in
                        Marker("Point \(index + 1)", coordinate: CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude))
                            .tint(routeMarkerColor(index: index))
                    }
                }
            }
            .mapStyle(mapStyle.style)
            .onTapGesture { screenPoint in
                mapContextAction = nil
                // Convert tap point to map coordinate using MapProxy
                if let coordinate = proxy.convert(screenPoint, from: .local) {
                    handleMapTap(at: coordinate)
                }
            }
            .overlay {
                MapSecondaryClickOverlay { point in
                    if let coordinate = proxy.convert(point, from: .local) {
                        showMapContext(at: coordinate, screenPoint: point)
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if let action = mapContextAction {
                    mapContextMenu(for: action)
                        .offset(x: min(action.screenPoint.x, 520), y: min(action.screenPoint.y, 520))
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.Location.mapView)
            .accessibilityLabel("Interactive map")
            .accessibilityHint("Click to select a target location. Right-click for map actions.")
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
        appState.targetLocationName = "Map selection"
        appState.statusMessage = mode == .route
            ? "Selected waypoint candidate. Use Add Waypoint to include it in the route."
            : String(format: "Selected location: %.4f, %.4f. Press Play or Apply to spoof.", coordinate.latitude, coordinate.longitude)
    }

    private func showMapContext(at coordinate: CLLocationCoordinate2D, screenPoint: CGPoint) {
        guard coordinate.latitude >= -90 && coordinate.latitude <= 90 &&
              coordinate.longitude >= -180 && coordinate.longitude <= 180 else {
            return
        }

        let location = LocationCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        latitudeInput = String(format: "%.6f", coordinate.latitude)
        longitudeInput = String(format: "%.6f", coordinate.longitude)

        withAnimation(.easeInOut(duration: 0.15)) {
            mapContextAction = MapContextAction(coordinate: location, screenPoint: screenPoint)
        }
    }

    private func mapContextMenu(for action: MapContextAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(action.coordinate.formattedShort)
                .font(AppFont.caption)
                .foregroundStyle(Color.pcTextMuted)
                .monospacedDigit()

            Button {
                appState.targetLocation = action.coordinate
                appState.targetLocationName = "Map selection"
                appState.statusMessage = "Selected \(action.coordinate.formattedShort)"
                withAnimation { mapContextAction = nil }
            } label: {
                Label("Set Target", systemImage: "mappin")
            }
            .buttonStyle(.plain)
            .accessibleButton(
                label: "Set map target",
                hint: "Selects this coordinate without changing the device location",
                identifier: "mapContextSetTargetButton"
            )

            if mode == .route {
                Button {
                    appState.addRoutePoint(action.coordinate)
                    withAnimation { mapContextAction = nil }
                } label: {
                    Label("Add Waypoint", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .accessibleButton(
                    label: "Add map waypoint",
                    hint: "Adds this coordinate to the current route",
                    identifier: "mapContextAddWaypointButton"
                )
            }

            Button {
                withAnimation { mapContextAction = nil }
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibleButton(
                label: "Cancel map actions",
                hint: "Closes the map context menu",
                identifier: "mapContextCancelButton"
            )
        }
        .padding(AppSpacing.md)
        .appGlassPanel(cornerRadius: AppRadius.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map context menu")
    }

    // MARK: - Top Controls

    private var topControls: some View {
        HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.pcTextMuted)

                    TextField("Search location or coordinates...", text: $searchService.searchText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Color.pcText)
                        .onChange(of: searchService.searchText) { _, newValue in
                            showSearchResults = !newValue.isEmpty
                        }
                        .onSubmit {
                            if let firstResult = searchService.searchResults.first {
                                selectSearchResult(firstResult)
                            }
                        }
                        .accessibilityLabel("Search location or coordinates")
                        .accessibilityHint("Type a place name or decimal coordinates, then press Return to select the first result")
                        .accessibilityIdentifier(AccessibilityIdentifiers.Location.searchField)

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
                                .foregroundStyle(Color.pcTextMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibleButton(
                            label: "Clear search",
                            hint: "Clears the search field and hides results",
                            identifier: AccessibilityIdentifiers.Location.clearLocationButton
                        )
                    }
                }
                .padding(AppSpacing.md)
                .appGlassPanel(cornerRadius: AppRadius.lg, strokeOpacity: 0.12, shadowOpacity: 0.12)

                if showSearchResults && !searchService.searchResults.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(searchService.searchResults.prefix(5)) { result in
                            Button {
                                selectSearchResult(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.pcText)
                                    Text(result.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.pcTextMuted)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, AppSpacing.sm)
                            }
                            .buttonStyle(.plain)
                            .background(Color.clear)
                            .contentShape(Rectangle())
                            .accessibilityLabel("Select \(result.name)")
                            .accessibilityHint("Selects this result as the target location without applying it")

                            if result.id != searchService.searchResults.prefix(5).last?.id {
                                Divider()
                                    .overlay(Color.white.opacity(0.06))
                                    .padding(.horizontal, AppSpacing.sm)
                            }
                        }
                    }
                    .background(Color.pcSurface.opacity(0.92), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                }
            }
            .frame(minWidth: 240, idealWidth: 360, maxWidth: 420)

            Spacer()

            if let target = appState.targetLocation {
                PCStatusChip(title: "Target", icon: "scope", color: .pcPrimary, detail: target.formattedShort)
            } else {
                PCStatusChip(title: "Select Target", icon: "mappin", color: .pcWarning, detail: "tap map")
            }

            HStack(spacing: AppSpacing.xxs) {
                ForEach(MapStyleType.allCases) { style in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mapStyle = style
                        }
                    } label: {
                        Text(style.rawValue)
                            .font(.system(size: 13, weight: mapStyle == style ? .semibold : .regular))
                            .foregroundStyle(mapStyle == style ? Color.white : Color.pcTextMuted)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                    .fill(mapStyle == style ? Color.pcAccent : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(style.rawValue) map style")
                    .accessibilityHint("Changes the map appearance")
                }
            }
            .padding(AppSpacing.xxs)
            .appGlassPanel(cornerRadius: AppRadius.lg, strokeOpacity: 0.12, shadowOpacity: 0.12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mapStyleSelector")

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
                    .foregroundStyle(appState.currentLocation == nil ? Color.pcTextMuted : Color.pcPrimary)
                    .padding(AppSpacing.md)
                    .background(Color.pcSurface.opacity(0.82), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(appState.currentLocation == nil)
            .accessibleButton(
                label: "Center on current location",
                hint: "Moves the map to the current simulated location",
                identifier: "centerCurrentLocationButton"
            )
        }
        .padding(AppSpacing.lg)
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
        FloatingControlPanel(title: "Teleport", icon: "location.fill") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(appState.targetLocationName ?? "Manual Coordinates")
                            .font(AppFont.subheading)
                            .foregroundStyle(Color.pcText)
                            .lineLimit(1)
                        Text(appState.targetLocation?.formattedShort ?? "Enter coordinates or tap the map")
                            .font(AppFont.monoSmall)
                            .foregroundStyle(Color.pcTextMuted)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "location.north.fill")
                        .foregroundStyle(Color.pcPrimary)
                }

                PCFieldShell(label: "Latitude", prefix: "LAT") {
                    TextField("0.000000", text: $latitudeInput)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Latitude")
                        .accessibilityHint("Enter decimal latitude between -90 and 90")
                        .accessibilityIdentifier(AccessibilityIdentifiers.Location.latitudeField)
                }

                PCFieldShell(label: "Longitude", prefix: "LNG") {
                    TextField("0.000000", text: $longitudeInput)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Longitude")
                        .accessibilityHint("Enter decimal longitude between -180 and 180")
                        .accessibilityIdentifier(AccessibilityIdentifiers.Location.longitudeField)
                }

                Button {
                    teleportToCoordinates()
                } label: {
                    Label("Go Teleport", systemImage: "location.north.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
                .disabled(latitudeInput.isEmpty || longitudeInput.isEmpty)
                .accessibleButton(
                    label: AccessibilityLabels.Actions.setLocation,
                    hint: "Applies the entered coordinates to the selected device",
                    identifier: AccessibilityIdentifiers.Location.setLocationButton
                )
            }
        }
    }

    // MARK: - Route Controls

    private var routeControls: some View {
        FloatingControlPanel(title: "Multi-Spot", icon: "point.topleft.down.curvedto.point.bottomright.up") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Picker("Route Type", selection: $routeType) {
                    Text("Navigation").tag(RouteType.navigation)
                    Text("Straight").tag(RouteType.straight)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(AccessibilityIdentifiers.Route.routeList)
                HStack(spacing: AppSpacing.sm) {
                    Button {
                        appState.addRoutePoint()
                    } label: {
                        Label("Add Selected", systemImage: "plus.circle")
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
                    .disabled(appState.targetLocation == nil)
                    .accessibleButton(
                        label: "Add selected location as waypoint",
                        hint: "Adds the currently selected map or search location to the route",
                        identifier: AccessibilityIdentifiers.Route.addWaypointButton
                    )

                    Button {
                        appState.showRouteImport = true
                    } label: {
                        Label("Import GPX", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcPrimary))
                    .accessibleButton(
                        label: AccessibilityLabels.Actions.importRoute,
                        hint: "Opens a GPX file and loads its route points",
                        identifier: AccessibilityIdentifiers.Route.importButton
                    )

                    Button {
                        appState.clearRoute()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcDanger))
                    .disabled(appState.currentRoute.isEmpty)
                    .accessibleButton(
                        label: "Clear route",
                        hint: "Removes all current route waypoints",
                        identifier: AccessibilityIdentifiers.Route.clearRouteButton
                    )
                }

                if appState.currentRoute.isEmpty {
                    Text("Tap the map or search for a place, then add it as a waypoint. Right-click the map for quick actions.")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.pcTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    routePointList
                }
            }
            .frame(minWidth: 280, idealWidth: 420, maxWidth: 520)
        }
    }

    private var routePointList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(appState.currentRoute.count) waypoints", systemImage: "list.number")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.pcTextMuted)

                Spacer()

                if appState.isSimulating {
                    Text("\(Int(appState.routeProgress * 100))%")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.pcSecondary)
                        .accessibilityIdentifier(AccessibilityIdentifiers.Route.progressIndicator)
                }
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(appState.currentRoute.enumerated()), id: \.offset) { index, coord in
                        routePointRow(index: index, coordinate: coord)
                    }
                }
            }
            .frame(maxHeight: 160)
            .accessibilityIdentifier(AccessibilityIdentifiers.Route.routeList)
            .accessibilityLabel("Route waypoint list")
        }
    }

    private func routePointRow(index: Int, coordinate: LocationCoordinate) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(AppFont.caption)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(index == 0 ? Color.pcSecondary : (index == appState.currentRoute.count - 1 ? Color.pcDanger : Color.pcWarning))
                .clipShape(Circle())

            Text(coordinate.formattedShort)
                .font(AppFont.monospace)
                .foregroundStyle(Color.pcText)
                .lineLimit(1)

            Spacer()

            Button {
                appState.moveRoutePoint(from: index, to: index - 1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .accessibilityLabel("Move waypoint \(index + 1) up")

            Button {
                appState.moveRoutePoint(from: index, to: index + 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(index == appState.currentRoute.count - 1)
            .accessibilityLabel("Move waypoint \(index + 1) down")

            Button {
                appState.removeRoutePoint(at: index)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.pcDanger)
            .accessibilityLabel("Remove waypoint \(index + 1)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.pcSurfaceHigh.opacity(0.55), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Waypoint \(index + 1), \(coordinate.formattedShort)")
        .accessibilityIdentifier(AccessibilityIdentifiers.Route.routeRow)
    }


    // MARK: - Main Control Panel

    private var mainControlPanel: some View {
        HStack(spacing: AppSpacing.xl) {
            // Speed Control
            VStack(alignment: .leading, spacing: 6) {
                Text("Speed: \(appState.simulationSpeed.displayName)")
                    .font(AppFont.monoSmall)
                    .foregroundStyle(Color.pcTextMuted)
                    .monospacedDigit()

                HStack(spacing: 8) {
                    ForEach(SimulationSpeed.allCases, id: \.self) { speed in
                        Button {
                            appState.setSpeed(speed)
                        } label: {
                            Image(systemName: speed.icon)
                                .font(.caption)
                                .frame(width: 32, height: 32)
                                .background(appState.simulationSpeed == speed ? Color.pcAccent : Color.pcSurfaceHigh.opacity(0.5))
                                .foregroundStyle(appState.simulationSpeed == speed ? Color.white : Color.pcTextMuted)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(appState.simulationSpeed == speed ? 0.18 : 0.06), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Set speed to \(speed.displayName)")
                        .accessibilityValue(AccessibilityLabels.Values.speed(name: speed.displayName, metersPerSecond: speed.metersPerSecond))
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityIdentifiers.Simulation.speedSelector)

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
                        await appState.startSimulation(mode: mode)
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
            .disabled(!appState.canStartSimulation(for: mode) && !appState.isSimulating)
            .accessibleButton(
                label: playButtonAccessibilityLabel,
                hint: appState.isSimulating ? AccessibilityHints.pauseSimulation : AccessibilityHints.startSimulation,
                identifier: appState.isSimulating ? AccessibilityIdentifiers.Simulation.pauseButton : AccessibilityIdentifiers.Simulation.startButton
            )

            // Stop Button
            Button {
                Task {
                    await appState.stopSimulation()
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(Color.pcDanger.opacity(appState.isSimulating ? 0.2 : 0.1))
                    .foregroundStyle(Color.pcDanger)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!appState.isSimulating)
            .accessibleButton(
                label: AccessibilityLabels.Actions.stopSimulation,
                hint: AccessibilityHints.stopSimulation,
                identifier: AccessibilityIdentifiers.Simulation.stopButton
            )

            Divider()
                .frame(height: 40)

            // Status
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.simulationStatusText)
                    .font(AppFont.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.pcText)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Status.statusMessage)

                if let location = appState.currentLocation {
                    Text(location.formattedShort)
                        .font(.caption2)
                        .foregroundStyle(Color.pcTextMuted)
                        .monospacedDigit()
                }
            }
        }
        .padding(AppSpacing.lg)
        .appGlassPanel(cornerRadius: AppRadius.xxl)
        .accessibilityElement(children: .contain)
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
            return .pcWarning
        }
        return .pcAccent
    }

    private func routeMarkerColor(index: Int) -> Color {
        if index == 0 {
            return .pcSecondary
        }
        if index == appState.currentRoute.count - 1 {
            return .pcDanger
        }
        return .pcWarning
    }

    private var playButtonAccessibilityLabel: String {
        if appState.isSimulating {
            return appState.isPaused ? AccessibilityLabels.Actions.resumeSimulation : AccessibilityLabels.Actions.pauseSimulation
        }
        return AccessibilityLabels.Actions.startSimulation
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
            appState.targetLocation = coordinate
            appState.targetLocationName = "Manual coordinates"
            await appState.setLocation(coordinate, source: "Coordinates", name: "Manual coordinates")
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
        appState.targetLocationName = result.name

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

        appState.statusMessage = mode == .route
            ? "Selected \(result.name). Use Add Selected to add it to the route."
            : "Selected \(result.name). Press Play to apply it."
    }


    private func handleRouteImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                do {
                    let didAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if didAccess {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }

                    let route = try await appState.routeLibrary.importGPX(from: url)
                    appState.loadRoute(from: route.coordinates)
                    appState.statusMessage = "Imported \(route.pointCount) route points from \(route.name)"
                } catch {
                    appState.errorHandler.handle(error, context: "GPX import")
                }
            }
        case .failure(let error):
            appState.errorHandler.handle(error, context: "GPX import")
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

private struct MapContextAction: Identifiable {
    let id = UUID()
    let coordinate: LocationCoordinate
    let screenPoint: CGPoint
}

private struct MapSecondaryClickOverlay: NSViewRepresentable {
    let onSecondaryClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> SecondaryClickPassthroughView {
        let view = SecondaryClickPassthroughView()
        view.onSecondaryClick = onSecondaryClick
        return view
    }

    func updateNSView(_ nsView: SecondaryClickPassthroughView, context: Context) {
        nsView.onSecondaryClick = onSecondaryClick
    }

    static func dismantleNSView(_ nsView: SecondaryClickPassthroughView, coordinator: ()) {
        nsView.removeMonitor()
    }
}

private final class SecondaryClickPassthroughView: NSView {
    var onSecondaryClick: ((CGPoint) -> Void)?
    private var eventMonitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitor()
    }

    func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    deinit {
        removeMonitor()
    }

    private func installMonitor() {
        removeMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            guard let self, self.window === event.window else {
                return event
            }

            let localPoint = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(localPoint) else {
                return event
            }

            let swiftUIPoint = CGPoint(x: localPoint.x, y: self.bounds.height - localPoint.y)
            self.onSecondaryClick?(swiftUIPoint)
            return event
        }
    }
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
