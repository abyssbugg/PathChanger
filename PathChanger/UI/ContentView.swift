//
//  ContentView.swift
//  PathChanger
//
//  Organic shell from the pth mock: title bar, rail, map, inspector, telemetry.
//

import SwiftUI
import MapKit
import Combine
import AppKit

enum AppMode: String, CaseIterable, Identifiable {
    case teleport = "Teleport"
    case route = "Multi-Spot"
    case joystick = "Joystick"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .teleport: return "mappin.and.ellipse"
        case .route: return "point.topleft.down.curvedto.point.bottomright.up"
        case .joystick: return "gamecontroller"
        case .settings: return "gear"
        }
    }

    var description: String {
        switch self {
        case .teleport: return "Instantly change location"
        case .route: return "Follow a path"
        case .joystick: return "Manual control"
        case .settings: return "App settings"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedMode: AppMode = .teleport
    @State private var showSettings = false
    @State private var showDeviceMenu = false
    @State private var railPanel: RailPanel?
    @State private var mapStyle: MapStyleType = .standard
    @State private var latitudeInput: String = ""
    @State private var longitudeInput: String = ""
    @State private var addressText: String = "Tap the map"
    @State private var currentError: ErrorHandler.AppError?
    @State private var showErrorDialog = false

    var body: some View {
        ZStack {
            Organic.neutral300.ignoresSafeArea()

            VStack(spacing: 0) {
                OrganicTitleBar(
                    showDeviceMenu: $showDeviceMenu,
                    showSettings: $showSettings,
                    onToggleMapStyle: cycleMapStyle,
                    onRefresh: {
                        Task {
                            await appState.refreshDevices()
                            await appState.checkTunneldStatus()
                        }
                    }
                )
                .zIndex(2)

                HStack(spacing: 0) {
                    OrganicRail(openPanel: $railPanel) { coordinate, name in
                        applyPlace(coordinate, name: name)
                    }
                    .zIndex(1)

                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            SimulationView(
                                mode: selectedMode,
                                mapStyle: $mapStyle,
                                latitudeInput: $latitudeInput,
                                longitudeInput: $longitudeInput,
                                addressText: $addressText
                            )
                            InspectorPanel(
                                mode: $selectedMode,
                                latitudeInput: $latitudeInput,
                                longitudeInput: $longitudeInput,
                                address: addressText,
                                onTeleport: commitTeleport,
                                onCommitCoords: commitTeleport
                            )
                        }
                        OrganicTelemetryBar(mode: selectedMode)
                    }
                }
            }
            .background(Organic.bg)
            .clipShape(RoundedRectangle(cornerRadius: 0))

            if showSettings {
                OrganicSettingsSheet(isPresented: $showSettings, mapStyle: $mapStyle)
                    .zIndex(30)
            }
        }
        .frame(minWidth: 1100, minHeight: 740)
        .background(Organic.bg)
        .preferredColorScheme(.light)
        .onAppear {
            appState.activeMode = selectedMode
            Organic.registerFonts()
            syncCoordFields()
        }
        .onChange(of: selectedMode) { _, newMode in
            if newMode != .settings {
                appState.activeMode = newMode
            }
        }
        .onChange(of: appState.targetLocation) { _, _ in
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

    private func cycleMapStyle() {
        switch mapStyle {
        case .standard: mapStyle = .satellite
        case .satellite: mapStyle = .hybrid
        case .hybrid: mapStyle = .standard
        }
    }

    private func syncCoordFields() {
        if let location = appState.targetLocation ?? appState.currentLocation {
            latitudeInput = String(format: "%.6f", location.latitude)
            longitudeInput = String(format: "%.6f", location.longitude)
        }
    }

    private func applyPlace(_ coordinate: LocationCoordinate, name: String) {
        latitudeInput = String(format: "%.6f", coordinate.latitude)
        longitudeInput = String(format: "%.6f", coordinate.longitude)
        addressText = name
        appState.targetLocation = coordinate
        LocationFavoritesManager.shared.recordRecent(name: name, coordinate: coordinate)
        if selectedMode == .route {
            appState.addRouteWaypoint(coordinate)
        } else if selectedMode == .teleport {
            Task { await appState.setLocation(coordinate) }
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
        appState.targetLocation = coordinate
        LocationFavoritesManager.shared.recordRecent(name: addressText, coordinate: coordinate)
        Task { await appState.setLocation(coordinate) }
    }

    private func handleErrorAction(_ action: ErrorHandler.ErrorAction) {
        switch action {
        case .retry:
            Task { await appState.refreshDevices() }
        case .openSettings:
            showSettings = true
        case .startTunneld:
            Task { await TunneldManager.shared.autoStart() }
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
            .preferredColorScheme(.light)
    }
}
#endif
