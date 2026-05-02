//
//  ContentView.swift
//  PathChanger
//
//  Modern Pro UI - Main application view
//  Based on ProposedDesign with full backend integration
//

import SwiftUI
import MapKit
import Combine

// MARK: - App Mode

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

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedMode: AppMode? = .teleport
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var currentError: ErrorHandler.AppError?
    @State private var showErrorDialog = false

    var body: some View {
        VStack(spacing: 0) {
            // Newer iOS compatibility warning banner
            if let device = appState.selectedDevice, device.hasLocationCompatibilityWarning {
                IOSCompatibilityWarningBanner(device: device)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selectedMode: $selectedMode)
                    .navigationTitle("Location Changer")
                    .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 350)
            } detail: {
                if let mode = selectedMode {
                    switch mode {
                    case .teleport, .route, .joystick:
                        SimulationView(mode: mode)
                    case .settings:
                        SettingsView()
                    }
                } else {
                    ContentUnavailableView(
                        "Select a Mode",
                        systemImage: "location.slash",
                        description: Text("Choose a simulation mode from the sidebar")
                    )
                }
            }
            .navigationSplitViewStyle(.balanced)
        }
        .frame(minWidth: 760, idealWidth: 1000, minHeight: 560, idealHeight: 700)
        // Onboarding sheet
        .sheet(isPresented: $appState.showOnboarding) {
            OnboardingView()
        }
        // Error dialog sheet
        .sheet(isPresented: $showErrorDialog) {
            if let error = currentError {
                if error.type == .iosVersionUnsupported {
                    IOSCompatibilityWarningDialogView(
                        deviceVersion: appState.selectedDevice?.iosVersion ?? "newer",
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
        // Subscribe to error handler changes
        .onReceive(appState.errorHandler.$currentError) { error in
            if let error = error {
                currentError = error
                showErrorDialog = true
            }
        }
        // Toast notifications
        .withToasts()
    }

    private func handleErrorAction(_ action: ErrorHandler.ErrorAction) {
        switch action {
        case .retry:
            Task { await appState.refreshDevices() }
        case .openSettings:
            if let url = URL(string: "x-apple.systempreferences:") {
                NSWorkspace.shared.open(url)
            }
        case .startTunneld:
            Task { await TunneldManager.shared.autoStart() }
        case .enableDeveloperMode:
            break
        case .checkConnection:
            Task { await appState.checkTunneldStatus() }
        }
    }
}

// MARK: - Newer iOS Compatibility Warning Banner

struct IOSCompatibilityWarningBanner: View {
    let device: Device
    @State private var isExpanded = false
    @State private var showDialog = false
    @State private var isDismissed = false

    var body: some View {
        if !isDismissed && !AppPreferences.shared.isNewerIOSWarningDismissed(for: device.id) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("iOS \(device.iosVersion) Compatibility Warning")
                            .font(.subheadline.weight(.semibold))

                        if isExpanded {
                            Text("PathChanger will still try location simulation, but newer iOS versions may need upstream pymobiledevice3 fixes if DVT rejects the request.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibleButton(
                        label: isExpanded ? "Collapse iOS compatibility warning" : "Expand iOS compatibility warning",
                        hint: "Shows or hides details about newer iOS compatibility",
                        identifier: "iosCompatibilityWarningDisclosureButton"
                    )

                    Button("Learn More") {
                        showDialog = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibleButton(
                        label: "Learn more about iOS compatibility",
                        hint: "Opens compatibility guidance",
                        identifier: "iosCompatibilityWarningLearnMoreButton"
                    )

                    Button {
                        AppPreferences.shared.setNewerIOSWarningDismissed(for: device.id)
                        withAnimation {
                            isDismissed = true
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.borderless)
                    .accessibleButton(
                        label: "Dismiss iOS compatibility warning",
                        hint: "Hides this compatibility warning for the selected device",
                        identifier: "iosCompatibilityWarningDismissButton"
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.orange.opacity(0.15))
                .overlay(
                    Rectangle()
                        .fill(Color.orange.opacity(0.3))
                        .frame(height: 1),
                    alignment: .bottom
                )
            }
            .sheet(isPresented: $showDialog) {
                IOSCompatibilityWarningDialogView(
                    deviceVersion: device.iosVersion,
                    onDismiss: { showDialog = false },
                    onLearnMore: { url in
                        NSWorkspace.shared.open(url)
                    }
                )
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState())
            .preferredColorScheme(.dark)
    }
}
#endif
