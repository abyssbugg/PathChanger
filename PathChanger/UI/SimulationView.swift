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
    /// When true, render the map only (no floating mode panels, no safe-area
    /// bleed) so the map can sit inside a bounded shell region. The mode
    /// panels move to the shell's right control panel in the redesigned shell.
    var embedded: Bool = false
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
    @State private var mapContextAction: MapContextAction?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var focusedCoordinateField: CoordinateField?

    private enum CoordinateField: Hashable {
        case latitude
        case longitude
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Map — full-bleed when standalone, bounded when embedded.
            if embedded {
                mapView
            } else {
                mapView
                    .ignoresSafeArea()
            }

            // 3. Floating Action Panel — only in the legacy standalone layout.
            // In the redesigned shell the mode panels live in the right
            // control panel, so they are suppressed when embedded.
            if !embedded {
                VStack(spacing: AppSpacing.xl) {
                    // Mode-specific controls
                    modeSpecificControls
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, DS.Spacing.xl * DS.Metrics.two)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
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
                                .fill(DS.Color.accent.opacity(DS.Opacity.mapMarkerHalo))
                                .frame(width: DS.Metrics.mapMarkerHaloSize, height: DS.Metrics.mapMarkerHaloSize)
                            Circle()
                                .fill(DS.Color.accent)
                                .frame(width: DS.Metrics.mapMarkerCoreSize, height: DS.Metrics.mapMarkerCoreSize)
                            Circle()
                                .stroke(DS.Color.markerStroke, lineWidth: DS.Metrics.mapMarkerStrokeWidth)
                                .frame(width: DS.Metrics.mapMarkerCoreSize, height: DS.Metrics.mapMarkerCoreSize)
                        }
                        .shadow(color: DS.Color.shadow.opacity(DS.Opacity.mapMarkerShadow), radius: DS.Metrics.mapMarkerShadowRadius)
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
                        .offset(
                            x: min(action.screenPoint.x, DS.Metrics.mapContextMenuMaxOffset),
                            y: min(action.screenPoint.y, DS.Metrics.mapContextMenuMaxOffset)
                        )
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
            ? "Selected route spot. Use Add Waypoint to include it in the route."
            : String(format: "Selected target: %.4f, %.4f. Use the primary action pill to apply it to the device.", coordinate.latitude, coordinate.longitude)
    }

    private func showMapContext(at coordinate: CLLocationCoordinate2D, screenPoint: CGPoint) {
        guard coordinate.latitude >= -90 && coordinate.latitude <= 90 &&
              coordinate.longitude >= -180 && coordinate.longitude <= 180 else {
            return
        }

        let location = LocationCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        latitudeInput = String(format: "%.6f", coordinate.latitude)
        longitudeInput = String(format: "%.6f", coordinate.longitude)

        withAnimation(DS.Animation.fast) {
            mapContextAction = MapContextAction(coordinate: location, screenPoint: screenPoint)
        }
    }

    private func mapContextMenu(for action: MapContextAction) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(action.coordinate.formattedShort)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.foregroundSecondary)
                .monospacedDigit()
            Button {
                appState.targetLocation = action.coordinate
                appState.targetLocationName = "Selected location"
                appState.statusMessage = mode == .route
                    ? "Selected route spot. Use Add Waypoint to include it in the route."
                    : "Selected \(action.coordinate.formattedShort)"
                withAnimation { mapContextAction = nil }
            } label: {
                if mode == .route {
                    Label("Set Route Spot", systemImage: "mappin")
                } else {
                    Label("Set Target", systemImage: "mappin")
                }
            }
            .font(DS.Typography.labelPrimary)
            .foregroundStyle(DS.Color.foregroundPrimary)
            .buttonStyle(.plain)
            .accessibleButton(
                label: mode == .route ? "Set route spot" : "Set map target",
                hint: mode == .route ? "Selects this coordinate so Add Waypoint can include it in the route" : "Selects this coordinate without changing the device location",
                identifier: "mapContextSetTargetButton"
            )

            Button {
                withAnimation { mapContextAction = nil }
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .font(DS.Typography.labelSecondary)
            .foregroundStyle(DS.Color.foregroundTertiary)
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
                            .scaleEffect(DS.Opacity.hoverRow)
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
                .frame(minHeight: DS.Metrics.mapToolbarSearchMinHeight)
                .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.inputField), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .stroke(
                            isSearchFocused ? DS.Color.accent.opacity(DS.Opacity.focusStroke) : DS.Color.foregroundTertiary.opacity(AppSurfaceAlpha.outline),
                            lineWidth: DS.Metrics.strokeWidth
                        )
                )
                .frame(
                    minWidth: DS.Metrics.mapToolbarSearchMinWidth,
                    idealWidth: DS.Metrics.mapToolbarSearchIdealWidth,
                    maxWidth: DS.Metrics.mapToolbarSearchMaxWidth
                )

                Spacer(minLength: AppSpacing.md)

                if let target = appState.targetLocation {
                    PCStatusChip(title: "Target location", icon: "scope", color: .pcPrimary, detail: target.formattedShort)
                } else {
                    PCStatusChip(title: "Select target", icon: "mappin", color: .pcTextMuted, detail: "tap map")
                }

                Divider()
                    .frame(height: DS.Metrics.mapToolbarDividerHeight)
                    .overlay(Color.pcOutline.opacity(AppSurfaceAlpha.divider))

                HStack(spacing: AppSpacing.xxs) {
                    ForEach(MapStyleType.allCases) { style in
                        Button {
                            withAnimation(DS.Animation.standard) {
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
                        .frame(width: DS.Metrics.mapToolbarLocateButtonSize, height: DS.Metrics.mapToolbarLocateButtonSize)
                        .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.inputField), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: DS.Metrics.strokeWidth)
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
            .appGlassPanel(cornerRadius: AppRadius.lg, strokeOpacity: DS.Opacity.toolbarPanelStroke, shadowOpacity: DS.Opacity.toolbarPanelShadow)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mapToolbar")

            if showSearchResults && !searchService.searchResults.isEmpty {
                VStack(alignment: .leading, spacing: DS.Metrics.zero) {
                    ForEach(searchService.searchResults.prefix(5)) { result in
                        Button {
                            selectSearchResult(result)
                        } label: {
                            VStack(alignment: .leading, spacing: DS.Metrics.two) {
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
                .frame(width: DS.Metrics.mapToolbarSearchMaxWidth, alignment: .leading)
                .background(Color.pcSurface.opacity(DS.Opacity.searchResultsSurface), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: DS.Metrics.strokeWidth)
                )
                .shadow(
                    color: DS.Color.shadow.opacity(DS.Opacity.searchResultsShadow),
                    radius: DS.Metrics.mapSearchResultsShadowRadius,
                    y: DS.Metrics.mapSearchResultsShadowYOffset
                )
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
        FloatingControlPanel(title: "Teleport", icon: "location.fill", accent: DS.ModeAccent.teleport.base) {
            // Operational refinement: tighter inner rhythm (sm vs md), drop
            // the redundant "Custom Location / Enter coordinates\u2026" empty-
            // state copy when no target exists (panel title already conveys
            // it), and consolidate the disabled-state hint inline so the
            // panel no longer grows a permanent third row at empty state.
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                teleportPanelStateStrip
                if let target = appState.targetLocation {
                    HStack(alignment: .center, spacing: AppSpacing.sm) {
                        Image(systemName: "location.north.fill")
                            .font(AppFont.metadata)
                            .foregroundStyle(Color.pcPrimary)
                        VStack(alignment: .leading, spacing: DS.Metrics.one) {
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
                        Label("Set Target", systemImage: "mappin")
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
            .frame(
                minWidth: DS.Metrics.mapTeleportPanelMinWidth,
                idealWidth: DS.Metrics.mapTeleportPanelIdealWidth,
                maxWidth: DS.Metrics.mapTeleportPanelMaxWidth
            )
        }
        .frame(maxWidth: DS.Metrics.mapTeleportPanelMaxWidth, alignment: .leading)
    }

    // MARK: - Route Controls

    // W1 visual governance: route controls are subordinate-prominent
    // interactions for route composition/import/clearing only. Execution
    // remains owned by the canonical PrimaryActionPill.
    // Route Type control is intentionally hidden until it is wired to route playback behavior.
    private var routeControls: some View {
        FloatingControlPanel(title: "Multi-Spot", icon: "point.topleft.down.curvedto.point.bottomright.up", accent: DS.ModeAccent.multiSpot.base) {
            // Operational refinement: tighten inner rhythm (sm vs md), demote
            // Import/Clear to icon-only buttons so the prominent Add Waypoint
            // CTA can fill remaining width without wrapping, and shorten the
            // empty-state hint so the panel no longer grows a multi-line
            // tutorial below the action row.
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                routePanelStateStrip

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
                    .help(addWaypointDisabledReason ?? "Adds the selected spot to the route")
                    .accessibleButton(
                        label: "Add selected location as waypoint",
                        hint: addWaypointDisabledReason ?? "Adds the currently selected map or search location to the route",
                        identifier: AccessibilityIdentifiers.Route.addWaypointButton
                    )

                    Button {
                        appState.showRouteImport = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .frame(width: DS.Metrics.mapRoutePanelButtonSize, height: DS.Metrics.mapRoutePanelButtonSize)
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
                            .frame(width: DS.Metrics.mapRoutePanelButtonSize, height: DS.Metrics.mapRoutePanelButtonSize)
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
                    Label("Select a spot, then Add Waypoint.", systemImage: "info.circle")
                        .labelStyle(.titleAndIcon)
                        .font(AppFont.metadata)
                        .foregroundStyle(Color.pcTextMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    routePointList
                }
            }
            .frame(
                minWidth: DS.Metrics.mapRoutePanelMinWidth,
                idealWidth: DS.Metrics.mapRoutePanelIdealWidth,
                maxWidth: DS.Metrics.mapRoutePanelMaxWidth
            )
        }
        .frame(maxWidth: DS.Metrics.mapRoutePanelMaxWidth, alignment: .leading)
    }
    private var teleportPanelStateStrip: some View {
        let hasTarget = appState.targetLocation != nil
        return PanelStateStrip(
            title: hasTarget ? "Target selected · Not applied" : "No target selected",
            detail: hasTarget ? "Use Apply to Device to move the device" : "Tap map, search, or enter coordinates",
            icon: hasTarget ? "scope" : "mappin",
            color: hasTarget ? .pcPrimary : .pcTextMuted,
            accessibilityIdentifier: "teleportPanelStateStrip"
        )
    }

    private var routePanelStateStrip: some View {
        let routeCount = appState.currentRoute.count
        if appState.isSimulating {
            return PanelStateStrip(
                title: "Route running",
                detail: "\(Int(appState.routeProgress * 100))% complete",
                icon: "play.circle.fill",
                color: .pcSecondary,
                accessibilityIdentifier: "routePanelStateStrip"
            )
        }

        if routeCount > 0 {
            return PanelStateStrip(
                title: "Ready to start",
                detail: "\(routeCount) waypoint\(routeCount == 1 ? "" : "s") · Start Route uses the primary action",
                icon: "point.topleft.down.curvedto.point.bottomright.up",
                color: .pcSecondary,
                accessibilityIdentifier: "routePanelStateStrip"
            )
        }

        if appState.targetLocation != nil {
            return PanelStateStrip(
                title: "Spot selected · Not added",
                detail: "Use Add Waypoint to include it in the route",
                icon: "mappin",
                color: .pcPrimary,
                accessibilityIdentifier: "routePanelStateStrip"
            )
        }

        return PanelStateStrip(
            title: "No route spots",
            detail: "Select a spot before adding a waypoint",
            icon: "mappin.and.ellipse",
            color: .pcTextMuted,
            accessibilityIdentifier: "routePanelStateStrip"
        )
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
                    .frame(height: DS.Metrics.mapRouteCounterHeight)
                    .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.activeRow), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: DS.Metrics.strokeWidth)
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
            .frame(maxHeight: DS.Metrics.mapRouteListMaxHeight)
            .accessibilityIdentifier(AccessibilityIdentifiers.Route.routeList)
            .accessibilityLabel("Route waypoint list")
        }
    }

    private func routePointRow(index: Int, coordinate: LocationCoordinate) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Text("\(index + 1)")
                .font(AppFont.metadata)
                .foregroundStyle(DS.Color.markerStroke)
                .frame(width: DS.Metrics.mapRouteCounterHeight, height: DS.Metrics.mapRouteCounterHeight)
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
                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: DS.Metrics.strokeWidth)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Waypoint \(index + 1), \(coordinate.formattedShort)")
        .accessibilityIdentifier(AccessibilityIdentifiers.Route.routeRow(index: index))
    }


    private var coordinateApplyDisabledReason: String? {
        if latitudeInput.isEmpty || longitudeInput.isEmpty {
            return "Enter latitude and longitude"
        }
        guard let latitude = Double(latitudeInput), let longitude = Double(longitudeInput) else {
            return "Enter valid decimal coordinates"
        }
        let coordinate = LocationCoordinate(latitude: latitude, longitude: longitude)
        if !coordinate.isValid {
            return "Latitude must be -90...90; longitude -180...180"
        }
        return nil
    }

    private var addWaypointDisabledReason: String? {
        appState.targetLocation == nil ? "Select a spot first" : nil
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
            appState.statusMessage = String(format: "Selected target: %.4f, %.4f. Use the primary action pill to apply it to the device.", coordinate.latitude, coordinate.longitude)
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
            ? "Selected \(result.name) as route spot. Use Add Waypoint to include it in the route."
            : "Selected \(result.name) as target. Use the primary action pill to apply it to the device."
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
