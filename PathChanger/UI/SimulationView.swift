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

/// Visual chrome mode for `SimulationView`.
///
/// `.full` is the legacy layout used when SimulationView hosts the entire
/// window (top toolbar with search + bottom main control panel both visible).
/// `.shell` is the new layout used inside `MainMapShell`: the shell takes
/// over search (sidebar) and the primary action (bottom-center pill), so
/// SimulationView suppresses its top toolbar and main control panel and
/// floats the mode-specific control panel higher to leave room for the pill.
enum SimulationViewChrome {
    case full
    case shell
}

struct SimulationView: View {
    let mode: AppMode
    var chrome: SimulationViewChrome = .full
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
    @FocusState private var isSearchFocused: Bool
    @FocusState private var focusedCoordinateField: CoordinateField?

    private enum CoordinateField: Hashable {
        case latitude
        case longitude
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Full Screen Map
            mapView
                .ignoresSafeArea()

            // 2. Top Controls (Search & Map Style) — only in full chrome.
            // In shell chrome the sidebar provides search and the host has its
            // own toolbars.
            if chrome == .full {
                VStack {
                    topControls
                    Spacer()
                }
            }

            // 3. Floating Action Panel
            VStack(spacing: AppSpacing.xl) {
                // Mode-specific controls
                modeSpecificControls

                // Main control panel — hidden in shell chrome where the action
                // pill (PrimaryActionPill) handles play/pause/stop.
                if chrome == .full {
                    mainControlPanel
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            // Push higher in shell chrome to clear the bottom action pill.
            .padding(.bottom, chrome == .shell ? 96 : AppSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chrome == .full ? Color.pcBackground : Color.clear)
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
                                .fill(Color.pcAccent.opacity(0.14))
                                .frame(width: 48, height: 48)
                            Circle()
                                .fill(Color.pcAccent)
                                .frame(width: 16, height: 16)
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 16, height: 16)
                        }
                        .shadow(color: Color.black.opacity(0.12), radius: 2)
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
        appState.targetLocationName = "Selected location"
        appState.statusMessage = mode == .route
            ? "Selected waypoint candidate. Use Add Waypoint to include it in the route."
            : String(format: "Selected location: %.4f, %.4f. Press Play or Apply to set.", coordinate.latitude, coordinate.longitude)
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
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(action.coordinate.formattedShort)
                .font(AppFont.metadata)
                .foregroundStyle(Color.pcTextMuted)
                .monospacedDigit()
            Button {
                appState.targetLocation = action.coordinate
                appState.targetLocationName = "Selected location"
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
            .foregroundStyle(Color.pcTextMuted)
            .accessibleButton(
                label: "Cancel map actions",
                hint: "Closes the map context menu",
                identifier: "mapContextCancelButton"
            )
        }
        .padding(AppSpacing.lg)
        .appGlassPanel(cornerRadius: AppRadius.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map context menu")
    }

    // MARK: - Top Controls

    private var topControls: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.pcTextMuted)

                    TextField("Search location or coordinates...", text: $searchService.searchText)
                        .textFieldStyle(.plain)
                        .font(AppFont.body)
                        .foregroundStyle(Color.pcText)
                        .focused($isSearchFocused)
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
                .padding(.horizontal, AppSpacing.md)
                .frame(minHeight: 36)
                .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.inputField), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .stroke(isSearchFocused ? Color.pcAccent.opacity(0.6) : Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
                )
                .frame(minWidth: 260, idealWidth: 360, maxWidth: 420)

                Spacer(minLength: AppSpacing.md)

                if let target = appState.targetLocation {
                    PCStatusChip(title: "Target location", icon: "scope", color: .pcPrimary, detail: target.formattedShort)
                } else {
                    PCStatusChip(title: "Select target", icon: "mappin", color: .pcTextMuted, detail: "tap map")
                }

                Divider()
                    .frame(height: 28)
                    .overlay(Color.pcOutline.opacity(AppSurfaceAlpha.divider))

                HStack(spacing: AppSpacing.xxs) {
                    ForEach(MapStyleType.allCases) { style in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                mapStyle = style
                            }
                        } label: {
                            Text(style.rawValue)
                                .font(mapStyle == style ? AppFont.label : AppFont.body)
                                .foregroundStyle(mapStyle == style ? Color.pcText : Color.pcTextMuted)
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, AppSpacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                        .fill(mapStyle == style ? Color.pcAccent.opacity(AppSurfaceAlpha.selectedRow) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .appHoverOverlay(cornerRadius: AppRadius.sm)
                        .accessibilityLabel("\(style.rawValue) map style")
                        .accessibilityHint("Changes the map appearance")
                    }
                }
                .padding(AppSpacing.xxs)
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
                        .frame(width: 32, height: 32)
                        .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.inputField), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .appHoverOverlay(cornerRadius: AppRadius.sm)
                .disabled(appState.currentLocation == nil)
                .accessibleButton(
                    label: "Center on current location",
                    hint: "Moves the map to the current simulated location",
                    identifier: "centerCurrentLocationButton"
                )
            }
            .padding(AppSpacing.sm)
            .appGlassPanel(cornerRadius: AppRadius.lg, strokeOpacity: 0.18, shadowOpacity: 0.12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mapToolbar")

            if showSearchResults && !searchService.searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(searchService.searchResults.prefix(5)) { result in
                        Button {
                            selectSearchResult(result)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name)
                                    .font(AppFont.label)
                                    .foregroundStyle(Color.pcText)
                                Text(result.subtitle)
                                    .font(AppFont.metadata)
                                    .foregroundStyle(Color.pcTextMuted)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.sm)
                        }
                        .buttonStyle(.plain)
                        .appHoverOverlay(cornerRadius: AppRadius.sm)
                        .background(Color.clear)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Select \(result.name)")
                        .accessibilityHint("Selects this result as the target location without applying it")

                        if result.id != searchService.searchResults.prefix(5).last?.id {
                            Divider()
                                .overlay(Color.pcOutline.opacity(AppSurfaceAlpha.divider))
                                .padding(.horizontal, AppSpacing.sm)
                        }
                    }
                }
                .frame(width: 420, alignment: .leading)
                .background(Color.pcSurface.opacity(0.98), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
        }
        .padding(AppSpacing.lg)
    }

    // MARK: - Mode Specific Controls
    // W1 visual governance: mode-specific panels are subordinate interaction
    // surfaces. They may prepare targets or context, but PrimaryActionPill
    // remains the canonical authority for T0 execution.

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
            // Operational refinement: tighter inner rhythm (sm vs md), drop
            // the redundant "Custom Location / Enter coordinates\u2026" empty-
            // state copy when no target exists (panel title already conveys
            // it), and consolidate the disabled-state hint inline so the
            // panel no longer grows a permanent third row at empty state.
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if let target = appState.targetLocation {
                    HStack(alignment: .center, spacing: AppSpacing.sm) {
                        Image(systemName: "location.north.fill")
                            .font(AppFont.metadata)
                            .foregroundStyle(Color.pcPrimary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(appState.targetLocationName ?? "Custom Location")
                                .font(AppFont.label)
                                .foregroundStyle(Color.pcText)
                                .lineLimit(1)
                            Text(target.formattedShort)
                                .font(AppFont.metadata)
                                .foregroundStyle(Color.pcTextMuted)
                                .lineLimit(1)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 0)
                    }
                }

                PCFieldShell(label: "Latitude", prefix: "Lat", isFocused: focusedCoordinateField == .latitude) {
                    TextField("0.000000", text: $latitudeInput)
                        .textFieldStyle(.plain)
                        .focused($focusedCoordinateField, equals: .latitude)
                        .accessibilityLabel("Latitude")
                        .accessibilityHint("Enter decimal latitude between -90 and 90")
                        .accessibilityIdentifier(AccessibilityIdentifiers.Location.latitudeField)
                }

                PCFieldShell(label: "Longitude", prefix: "Lng", isFocused: focusedCoordinateField == .longitude) {
                    TextField("0.000000", text: $longitudeInput)
                        .textFieldStyle(.plain)
                        .focused($focusedCoordinateField, equals: .longitude)
                        .accessibilityLabel("Longitude")
                        .accessibilityHint("Enter decimal longitude between -180 and 180")
                        .accessibilityIdentifier(AccessibilityIdentifiers.Location.longitudeField)
                }

                // W1 visual governance: this Teleport inspector action is a
                // subordinate interaction. It applies coordinates as target
                // context only and must not become an execution authority.
                HStack(spacing: AppSpacing.sm) {
                    Button {
                        applyCoordinatesToTarget()
                    } label: {
                        Label("Apply", systemImage: "mappin")
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent))
                    .disabled(coordinateApplyDisabledReason != nil)
                    .help(coordinateApplyDisabledReason ?? "Apply entered coordinates as the target")
                    .accessibleButton(
                        label: "Apply coordinates as target",
                        hint: "Selects the entered coordinates without applying them to the device",
                        identifier: AccessibilityIdentifiers.Location.setLocationButton
                    )

                    if let coordinateApplyDisabledReason {
                        Text(coordinateApplyDisabledReason)
                            .font(AppFont.metadata)
                            .foregroundStyle(Color.pcTextMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 0)
                }
            }
            .frame(minWidth: 260, idealWidth: 296, maxWidth: 312)
        }
        .frame(maxWidth: 312, alignment: .leading)
    }

    // MARK: - Route Controls

    // W1 visual governance: route controls are subordinate-prominent
    // interactions for route composition/import/clearing only. Execution
    // remains owned by the canonical PrimaryActionPill.
    private var routeControls: some View {
        FloatingControlPanel(title: "Multi-Spot", icon: "point.topleft.down.curvedto.point.bottomright.up") {
            // Operational refinement: tighten inner rhythm (sm vs md), demote
            // Import/Clear to icon-only buttons so the prominent Add Waypoint
            // CTA can fill remaining width without wrapping, and shorten the
            // empty-state hint so the panel no longer grows a multi-line
            // tutorial below the action row.
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Picker("Route Type", selection: $routeType) {
                    Text("Navigation").tag(RouteType.navigation)
                    Text("Straight").tag(RouteType.straight)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(AccessibilityIdentifiers.Route.routeList)

                routeTargetSummary

                HStack(spacing: AppSpacing.xs) {
                    Button {
                        appState.addRoutePoint()
                    } label: {
                        Label("Add Waypoint", systemImage: "plus.circle")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
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
                        Image(systemName: "square.and.arrow.down")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcTextMuted))
                    .help("Import GPX")
                    .accessibleButton(
                        label: AccessibilityLabels.Actions.importRoute,
                        hint: "Opens a GPX file and loads its route points",
                        identifier: AccessibilityIdentifiers.Route.importButton
                    )

                    Button {
                        appState.clearRoute()
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcDanger))
                    .disabled(appState.currentRoute.isEmpty)
                    .help("Clear route")
                    .accessibleButton(
                        label: "Clear route",
                        hint: "Removes all current route waypoints",
                        identifier: AccessibilityIdentifiers.Route.clearRouteButton
                    )
                }

                if appState.currentRoute.isEmpty {
                    Label("Search the sidebar or tap the map to add spots.", systemImage: "info.circle")
                        .labelStyle(.titleAndIcon)
                        .font(AppFont.metadata)
                        .foregroundStyle(Color.pcTextMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    routePointList
                }
            }
            .frame(minWidth: 280, idealWidth: 312, maxWidth: 332)
        }
        .frame(maxWidth: 332, alignment: .leading)
    }

    private var routeTargetSummary: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(appState.targetLocation == nil ? Color.pcTextMuted : Color.pcPrimary)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(appState.targetLocationName ?? "No selected spot")
                    .font(AppFont.label)
                    .foregroundStyle(Color.pcText)
                    .lineLimit(1)
                Text(appState.targetLocation?.formattedShort ?? "Search or tap the map")
                    .font(AppFont.metadata)
                    .foregroundStyle(Color.pcTextMuted)
                    .lineLimit(1)
            }

            Spacer()

            // Operational refinement: suppress the "0" chip in empty state so
            // the summary row stops carrying dead chrome before any waypoint
            // has been added.
            if !appState.currentRoute.isEmpty {
                Text("\(appState.currentRoute.count)")
                    .font(AppFont.monoSmall)
                    .foregroundStyle(Color.pcTextMuted)
                    .padding(.horizontal, AppSpacing.sm)
                    .frame(height: 22)
                    .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.activeRow), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
        )
        .accessibilityIdentifier("routeSelectedTargetSummary")
    }
    private var routePointList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Label("\(appState.currentRoute.count) waypoints", systemImage: "list.number")
                    .font(AppFont.metadata)
                    .foregroundStyle(Color.pcTextMuted)

                Spacer()

                if appState.isSimulating {
                    Text("\(Int(appState.routeProgress * 100))%")
                        .font(AppFont.metadata)
                        .foregroundStyle(Color.pcSecondary)
                        .accessibilityIdentifier(AccessibilityIdentifiers.Route.progressIndicator)
                }
            }
            ScrollView {
                LazyVStack(spacing: AppSpacing.sm) {
                    ForEach(Array(appState.currentRoute.enumerated()), id: \.offset) { index, coord in
                        routePointRow(index: index, coordinate: coord)
                    }
                }
            }
            .frame(maxHeight: 132)
            .accessibilityIdentifier(AccessibilityIdentifiers.Route.routeList)
            .accessibilityLabel("Route waypoint list")
        }
    }

    private func routePointRow(index: Int, coordinate: LocationCoordinate) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Text("\(index + 1)")
                .font(AppFont.metadata)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(index == 0 ? Color.pcSecondary : (index == appState.currentRoute.count - 1 ? Color.pcDanger : Color.pcWarning))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))

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
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.sm)
        .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.activeRow), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Waypoint \(index + 1), \(coordinate.formattedShort)")
        .accessibilityIdentifier(AccessibilityIdentifiers.Route.routeRow)
    }


    // MARK: - Main Control Panel

    private var mainControlPanel: some View {
        HStack(spacing: AppSpacing.xl) {
            // Speed Control
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Speed: \(appState.simulationSpeed.displayName)")
                    .font(AppFont.metadata)
                    .foregroundStyle(Color.pcTextMuted)
                    .monospacedDigit()

                HStack(spacing: AppSpacing.sm) {
                    ForEach(SimulationSpeed.allCases, id: \.self) { speed in
                        Button {
                            appState.setSpeed(speed)
                        } label: {
                            Image(systemName: speed.icon)
                                .font(AppFont.metadata)
                                .frame(width: 32, height: 32)
                                .background(appState.simulationSpeed == speed ? Color.pcAccent.opacity(AppSurfaceAlpha.hoverRow) : Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.activeRow))
                                .foregroundStyle(appState.simulationSpeed == speed ? Color.pcText : Color.pcTextMuted)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                        .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .appHoverOverlay(cornerRadius: AppRadius.sm)
                        .accessibilityLabel("Set speed to \(speed.displayName)")
                        .accessibilityValue(AccessibilityLabels.Values.speed(name: speed.displayName, metersPerSecond: speed.metersPerSecond))
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityIdentifiers.Simulation.speedSelector)

            Divider()
                .frame(height: 40)
                .overlay(Color.pcOutline)

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
                Label(playButtonTitle, systemImage: playButtonIcon)
                    .frame(width: 112)
            }
            .buttonStyle(AppCapsuleButtonStyle(accent: playButtonColor, isProminent: true))
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
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(AppCapsuleButtonStyle(accent: .pcDanger))
            .disabled(!appState.isSimulating)
            .accessibleButton(
                label: AccessibilityLabels.Actions.stopSimulation,
                hint: AccessibilityHints.stopSimulation,
                identifier: AccessibilityIdentifiers.Simulation.stopButton
            )

            Divider()
                .frame(height: 40)
                .overlay(Color.pcOutline)

            // Status
            PCStatusChip(
                title: simulationStatusTitle,
                icon: "circle.fill",
                color: simulationStatusColor,
                detail: simulationStatusDetail
            )
            .help(appState.simulationStatusText)
            .accessibilityIdentifier(AccessibilityIdentifiers.Status.statusMessage)
        }
        .padding(AppSpacing.lg)
        .appGlassPanel(cornerRadius: AppRadius.xl)
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

    private var playButtonTitle: String {
        if appState.isSimulating {
            return appState.isPaused ? "Resume" : "Pause"
        }
        return "Start"
    }

    private var simulationStatusTitle: String {
        if appState.isSimulating {
            return appState.isPaused ? "Paused" : "Active"
        }
        return appState.canStartSimulation(for: mode) ? "Ready" : "Waiting"
    }

    private var simulationStatusColor: Color {
        if appState.isSimulating {
            return appState.isPaused ? .pcWarning : .pcSecondary
        }
        return appState.canStartSimulation(for: mode) ? .pcPrimary : .pcTextMuted
    }

    private var simulationStatusDetail: String? {
        if let location = appState.currentLocation {
            return location.formattedShort
        }
        if !appState.canStartSimulation(for: mode) && !appState.isSimulating {
            return simulationUnavailableReason
        }
        return appState.simulationStatusText
    }

    private var coordinateApplyDisabledReason: String? {
        if latitudeInput.isEmpty || longitudeInput.isEmpty {
            return "Enter latitude and longitude"
        }
        return nil
    }

    private var simulationUnavailableReason: String? {
        if !appState.isTunneldRunning {
            return "Start tunnel"
        }
        if appState.selectedDevice == nil {
            return "Select device"
        }

        switch mode {
        case .teleport:
            return appState.targetLocation == nil ? "Select target" : nil
        case .route:
            return appState.currentRoute.count < 2 ? "Add 2 waypoints" : nil
        case .joystick:
            return appState.currentLocation == nil && appState.targetLocation == nil ? "Select start" : nil
        case .settings:
            return nil
        }
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

    private func applyCoordinatesToTarget() {
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

        withAnimation {
            appState.targetLocation = coordinate
            appState.targetLocationName = "Custom location"
            appState.statusMessage = String(format: "Selected location: %.4f, %.4f. Press Play or Apply to set.", coordinate.latitude, coordinate.longitude)
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
            ? "Selected \(result.name). Use Add Waypoint to add it to the route."
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
    }
}
#endif
