//
//  ContentView.swift
//  PathChanger
//
//  Map-first Organic shell from the pctnhc mock.
//

import SwiftUI
import MapKit
import Combine
import AppKit

enum AppMode: String, CaseIterable, Identifiable {
    case teleport = "Teleport"
    case jump = "Jump"
    case twospot = "Two-spot"
    case route = "Multi-Spot"
    case joystick = "Joystick"
    case settings = "Settings"

    var id: String { rawValue }

    static var mapModes: [AppMode] { [.teleport, .jump, .twospot, .route, .joystick] }

    var glyph: OrganicGlyph {
        switch self {
        case .teleport: return .teleport
        case .jump: return .jump
        case .twospot: return .twoSpot
        case .route: return .multiSpot
        case .joystick: return .joystick
        case .settings: return .settings
        }
    }

    /// Legacy system-symbol name for views outside the canonical map-first shell.
    var icon: String {
        switch self {
        case .teleport: return "scope"
        case .jump: return "plus.viewfinder"
        case .twospot: return "arrow.left.and.right"
        case .route: return "point.topleft.down.curvedto.point.bottomright.up"
        case .joystick: return "figure.stand"
        case .settings: return "gear"
        }
    }

    var description: String {
        switch self {
        case .teleport: return "One acknowledged hop"
        case .jump: return "Numbered hops, one at a time"
        case .twospot: return "Travel between two points"
        case .route: return "Route through many stops"
        case .joystick: return "Steer by hand"
        case .settings: return "App settings"
        }
    }

    var locationMode: LocationMode? {
        switch self {
        case .teleport: return .teleport
        case .jump: return .jumpTeleport
        case .twospot: return .twoSpot
        case .route: return .multiSpot
        case .joystick: return .joystick
        case .settings: return nil
        }
    }
}

extension AppMode {
    var locationAccessibilityIdentifier: String {
        switch self {
        case .teleport: return "location.mode.teleport"
        case .jump: return "location.mode.jump"
        case .twospot: return "location.mode.twoSpot"
        case .route: return "location.mode.multiSpot"
        case .joystick: return "location.mode.joystick"
        case .settings: return "location.mode.settings"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager
    @StateObject private var searchService = LocationSearchService()
    @ObservedObject private var favorites = LocationFavoritesManager.shared

    @State private var selectedMode: AppMode = .teleport
    @State private var showSettings = false
    @State private var showDeviceMenu = false
    @State private var mapStyle: MapStyleType = .standard
    @State private var latitudeInput: String = ""
    @State private var longitudeInput: String = ""
    @State private var addressText: String = "Tap the map"
    @State private var currentError: ErrorHandler.AppError?
    @State private var showClearConfirmation = false
    @State private var showErrorDialog = false
    @State private var cardOpen = false
    @State private var savedOpen = false
    @State private var savedTab: SavedTab = .favorites
    @State private var showSearchResults = false
    @AppStorage("PathChanger.Appearance") private var appearanceRaw = OrganicAppearance.light.rawValue
    @AppStorage("dismissedCoach") private var dismissedCoach = false
    @State private var coachOpen = true

    var body: some View {
        ZStack {
            Organic.neutral300.ignoresSafeArea()

            VStack(spacing: 0) {
                OrganicTitleBar(
                    showDeviceMenu: $showDeviceMenu,
                    showSettings: $showSettings,
                    appearanceRaw: $appearanceRaw,
                    onRefresh: {
                        Task {
                            await appState.refreshDevices()
                            await appState.checkTunneldStatus()
                        }
                    }
                )
                .zIndex(2)

                ZStack(alignment: .topLeading) {
                    SimulationView(
                        mode: selectedMode,
                        mapStyle: $mapStyle,
                        latitudeInput: $latitudeInput,
                        longitudeInput: $longitudeInput,
                        addressText: $addressText,
                        onPickLocation: applyPlace
                    )

                    mapChrome
                }
            }
            .background(Organic.bg)

            if showSettings {
                OrganicSettingsSheet(
                    isPresented: $showSettings,
                    appearanceRaw: $appearanceRaw
                )
                    .zIndex(30)
            }
        }
        .frame(minWidth: 1180, minHeight: 760)
        .background(Organic.bg)
        .preferredColorScheme(OrganicAppearance.persisted(appearanceRaw).colorScheme)
        .onAppear {
            selectedMode = .teleport
            appState.activeMode = .teleport
            cardOpen = false
            Organic.registerFonts()
            syncCoordFields()
            coachOpen = !dismissedCoach
        }
        .onChange(of: selectedMode) { oldMode, newMode in
            if newMode != .settings {
                appState.activeMode = newMode
            }
            guard oldMode != newMode else { return }
            appState.jumpIndex = 0
            if newMode.maxStops > 0, appState.currentRoute.count > newMode.maxStops {
                appState.loadRoute(from: Array(appState.currentRoute.prefix(newMode.maxStops)))
            }
            if newMode == .joystick {
                appState.clearRoute()
            }
            cardOpen = true
            savedOpen = false
            coachOpen = false
        }
        .onChange(of: appState.locationPresentation.desiredCoordinate) { _, _ in
            syncCoordFields()
        }
        .sheet(isPresented: $appState.showOnboarding) {
            OnboardingView()
        }
        .sheet(isPresented: $showErrorDialog) {
            if let error = currentError {
                if error.type == .iosVersionUnsupported {
                    IOS18WarningDialogView(
                        deviceVersion: appState.selectedDevice?.iosVersion ?? "18+",
                        onDismiss: {
                            showErrorDialog = false
                            appState.errorHandler.clearCurrentError()
                        },
                        onLearnMore: { url in
                            NSWorkspace.shared.open(url)
                        }
                    )
                } else {
                    EnhancedErrorDialogView(
                        error: error,
                        onDismiss: {
                            showErrorDialog = false
                            appState.errorHandler.clearCurrentError()
                        },
                        onAction: { action in
                            handleErrorAction(action)
                            showErrorDialog = false
                        },
                        onLearnMore: { url in
                            NSWorkspace.shared.open(url)
                        }
                    )
                }
            }
        }
        .onReceive(appState.errorHandler.$currentError) { error in
            if let error = error {
                currentError = error
                showErrorDialog = true
            }
        }
        .withToasts()
    }

    private var mapChrome: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    searchField
                    livePill
                    modePill
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                Spacer().allowsHitTesting(false)
            }
            .allowsHitTesting(true)

            if savedOpen {
                SavedPlacesCard(tab: $savedTab, onSelect: applyPlace, onClose: { savedOpen = false })
                    .padding(.leading, 16)
                    .padding(.top, 70)
                    .zIndex(26)
            } else if cardOpen {
                ModeContextCard(
                    mode: $selectedMode,
                    latitudeInput: $latitudeInput,
                    longitudeInput: $longitudeInput,
                    address: addressText,
                    onClose: { cardOpen = false },
                    onMove: performMove,
                    onCommitCoords: commitTeleport
                )
                .padding(.leading, 16)
                .padding(.top, 70)
                .zIndex(25)
            }

            VStack {
                Spacer().allowsHitTesting(false)
                HStack {
                    handleButton
                    Spacer().allowsHitTesting(false)
                }
                Spacer().allowsHitTesting(false)
            }

            if coachOpen && !cardOpen && !savedOpen {
                coachToast
            }
        }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Organic.neutral500)
                TextField("Address or 6.447400, 3.390300", text: $searchService.searchText)
                    .textFieldStyle(.plain)
                    .font(Organic.body(12, weight: .semibold))
                    .onChange(of: searchService.searchText) { _, newValue in
                        showSearchResults = !newValue.isEmpty
                    }
                    .onSubmit { commitSearch() }
                if searchService.isSearching {
                    ProgressView().controlSize(.mini)
                }
                Button(action: commitSearch) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Organic.neutral100)
                        .frame(width: 30, height: 30)
                        .background(Organic.accent)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Go to location")
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(height: 42)
            .background(Organic.neutral100)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Organic.neutral300, lineWidth: 1))
            .shadow(color: Organic.shadow.opacity(0.08), radius: 4, y: 1)

            if showSearchResults && !searchService.searchResults.isEmpty {
                VStack(spacing: 1) {
                    ForEach(searchService.searchResults.prefix(6)) { result in
                        Button {
                            applyPlace(result.coordinate, name: result.name)
                            searchService.clearSearch()
                            showSearchResults = false
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "mappin.circle")
                                    .foregroundStyle(Organic.accent600)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(result.name)
                                        .font(Organic.body(12, weight: .bold))
                                        .lineLimit(1)
                                    Text(result.subtitle)
                                        .font(Organic.mono(10))
                                        .foregroundStyle(Organic.neutral600)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(5)
                .background(Organic.neutral100)
                .clipShape(RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                        .stroke(Organic.neutral300, lineWidth: 1)
                )
                .shadow(color: Organic.shadow.opacity(0.16), radius: 10, y: 4)
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    private var livePill: some View {
        let status = appState.locationPresentation
        return HStack(spacing: 10) {
            statusMetric(
                status.connectionLabel,
                localizationKey: "accessibility.location.status.connection",
                id: "location.status.connection"
            )
            statusMetric(
                status.applicationLabel,
                localizationKey: "accessibility.location.status.application",
                id: "location.status.application"
            )
            statusMetric(
                status.movementLabel,
                localizationKey: "accessibility.location.status.movement",
                id: "location.status.movement"
            )
            statusMetric(
                status.appliedCoordinateLabel,
                localizationKey: "accessibility.location.status.coordinate",
                id: "location.status.coordinate"
            )
            Spacer(minLength: 4)
            Button("Clear") { showClearConfirmation = true }
                .buttonStyle(.plain)
                .font(Organic.body(11, weight: .bold))
                .foregroundStyle(Organic.accent700)
                .disabled(!status.canClear)
                .accessibilityIdentifier("location.action.clear")
                .confirmationDialog(
                    "Return to real GPS?",
                    isPresented: $showClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear simulated location", role: .destructive) {
                        Task { await appState.clearLocation() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This is the only action that removes the applied location.")
                }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Organic.neutral100)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Organic.neutral300, lineWidth: 1))
    }

    private func statusMetric(
        _ text: String,
        localizationKey: String,
        id: String
    ) -> some View {
        Text(text)
            .font(Organic.mono(10, weight: .semibold))
            .lineLimit(1)
            .accessibilityIdentifier(id)
            .accessibilityLabel(NSLocalizedString(localizationKey, comment: "Location status field"))
            .accessibilityValue(text)
    }

    private var modePill: some View {
        HStack(spacing: 3) {
            ForEach(AppMode.mapModes) { mode in
                Button {
                    if selectedMode == mode {
                        cardOpen.toggle()
                        savedOpen = false
                    } else {
                        selectedMode = mode
                    }
                } label: {
                    OrganicGlyphView(glyph: mode.glyph, size: 14)
                        .foregroundStyle(selectedMode == mode && cardOpen ? Organic.neutral100 : Organic.neutral700)
                        .frame(width: 36, height: 36)
                        .background(selectedMode == mode && cardOpen ? Organic.accent : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(mode.description)
                .accessibilityIdentifier(mode.locationAccessibilityIdentifier)
            }
            Rectangle()
                .fill(Organic.neutral300)
                .frame(width: 1, height: 22)
                .padding(.horizontal, 3)
            Button {
                savedOpen.toggle()
                if savedOpen {
                    cardOpen = false
                    coachOpen = false
                }
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(savedOpen ? Organic.accent800 : Organic.neutral600)
                    .frame(width: 36, height: 36)
                    .background(savedOpen ? Organic.neutral200 : Color.clear)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Saved & history")
        }
        .padding(5)
        .background(Organic.neutral100)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Organic.neutral300, lineWidth: 1))
        .shadow(color: Organic.shadow.opacity(0.08), radius: 4, y: 1)
    }

    private var handleButton: some View {
        Button {
            if savedOpen {
                savedOpen = false
                cardOpen = true
            } else if cardOpen {
                cardOpen = false
            } else {
                cardOpen = true
                coachOpen = false
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Organic.neutral600)
                .rotationEffect(.degrees(cardOpen || savedOpen ? 0 : 180))
                .frame(width: 17, height: 46)
                .background(Organic.neutral100)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 10, topTrailingRadius: 10, style: .continuous))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 10, topTrailingRadius: 10, style: .continuous)
                        .stroke(Organic.neutral300, lineWidth: 1)
                )
                .shadow(color: Organic.shadow.opacity(0.08), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .help(cardOpen || savedOpen ? "Hide panel" : "Show \(selectedMode.cardTitle) panel")
    }

    private var coachToast: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(Organic.accent400)
                    Text(appState.canStartSimulation
                         ? "Click the map to set a destination — the card comes to you."
                         : "Connect a device or start the tunnel, then click the map.")
                        .font(Organic.body(12, weight: .semibold))
                        .foregroundStyle(Organic.neutral100)
                    Button("Got it") {
                        coachOpen = false
                        dismissedCoach = true
                    }
                    .buttonStyle(.plain)
                    .font(Organic.body(10, weight: .bold))
                    .foregroundStyle(Organic.accent400)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Organic.neutral100.opacity(0.12))
                    .clipShape(Capsule())
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .padding(.vertical, 9)
                .background(Organic.neutral900)
                .clipShape(Capsule())
                .shadow(color: Organic.shadow.opacity(0.24), radius: 12, y: 6)
                Spacer()
            }
            .padding(.bottom, 20)
        }
        .allowsHitTesting(true)
    }

    private func cycleMapStyle() {
        switch mapStyle {
        case .standard: mapStyle = .satellite
        case .satellite: mapStyle = .hybrid
        case .hybrid: mapStyle = .standard
        }
    }

    private func syncCoordFields() {
        if let location = appState.locationPresentation.desiredCoordinate ?? appState.locationPresentation.appliedCoordinate {
            latitudeInput = String(format: "%.6f", location.latitude)
            longitudeInput = String(format: "%.6f", location.longitude)
        }
    }

    private func applyPlace(_ coordinate: LocationCoordinate, name: String) {
        latitudeInput = String(format: "%.6f", coordinate.latitude)
        longitudeInput = String(format: "%.6f", coordinate.longitude)
        addressText = name
        appState.stageLocation(coordinate, for: selectedMode)

        cardOpen = true
        savedOpen = false
        coachOpen = false
        showSearchResults = false
    }

    private func commitSearch() {
        if let first = searchService.searchResults.first {
            applyPlace(first.coordinate, name: first.name)
            searchService.clearSearch()
            showSearchResults = false
        }
    }

    private func commitTeleport() {
        guard let lat = Double(latitudeInput), let lon = Double(longitudeInput) else {
            appState.statusMessage = "Invalid coordinates"
            return
        }
        let coordinate = LocationCoordinate(latitude: lat, longitude: lon)
        guard coordinate.isValid else {
            appState.statusMessage = "Coordinates out of range"
            return
        }
        applyPlace(coordinate, name: addressText)
    }

    private func performMove() {
        if appState.locationPresentation.isMovementActive, selectedMode == .route || selectedMode == .twospot {
            Task { await appState.stopSimulation() }
            return
        }
        appState.activeMode = selectedMode == .settings ? .teleport : selectedMode
        let plan = SimulationPlanner.plan(
            mode: appState.activeMode,
            targetLocation: appState.locationPresentation.desiredCoordinate,
            currentLocation: appState.locationPresentation.appliedCoordinate,
            route: appState.currentRoute,
            speed: appState.simulationSpeed,
            jumpIndex: appState.jumpIndex
        )
        if LocationHistoryPolicy.shouldRecord(
            canStartSimulation: appState.canStartSimulation,
            plan: plan
        ), let coordinate = LocationHistoryPolicy.coordinate(for: plan) {
            let name = coordinate == appState.locationPresentation.desiredCoordinate ? addressText : coordinate.formattedShort
            LocationFavoritesManager.shared.recordRecent(name: name, coordinate: coordinate)
            LocationFavoritesManager.shared.rememberPlace(name: name, coordinate: coordinate)
        }
        Task { await appState.startSimulation() }
    }

    private func handleErrorAction(_ action: ErrorHandler.ErrorAction) {
        switch action {
        case .retry:
            Task { await appState.refreshDevices() }
        case .openSettings:
            showSettings = true
        case .startTunneld:
            Task { await appState.startSelectedTunnel() }
        case .enableDeveloperMode:
            break
        case .checkConnection:
            Task { await appState.checkTunneldStatus() }
        }
    }
}

struct IOS18WarningBanner: View {
    let device: Device
    @State private var isExpanded = false
    @State private var showDialog = false
    @State private var isDismissed = false

    var body: some View {
        if !isDismissed && !AppPreferences.shared.isIOS18WarningDismissed(for: device.id) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Organic.accent600)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iOS \(device.iosVersion) — keep the tunnel running")
                        .font(Organic.body(13, weight: .semibold))
                    if isExpanded {
                        Text("If the pin snaps back, start the tunnel again and leave PathChanger open.")
                            .font(Organic.body(11))
                            .foregroundStyle(Organic.neutral600)
                    }
                }
                Spacer()
                Button("Learn More") { showDialog = true }
                    .buttonStyle(.plain)
                    .font(Organic.body(12, weight: .bold))
                    .foregroundStyle(Organic.accent700)
                Button {
                    AppPreferences.shared.setIOS18WarningDismissed(for: device.id)
                    isDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(Organic.neutral600)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Organic.accent100)
            .sheet(isPresented: $showDialog) {
                IOS18WarningDialogView(
                    deviceVersion: device.iosVersion,
                    onDismiss: { showDialog = false },
                    onLearnMore: { url in NSWorkspace.shared.open(url) }
                )
            }
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState())
    }
}
#endif
