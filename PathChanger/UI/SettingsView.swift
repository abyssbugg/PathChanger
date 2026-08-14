//
//  SettingsView.swift
//  PathChanger
//
//  Application settings view
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var tunneldManager = TunneldManager.shared
    @AppStorage("autoRefreshDevices") private var autoRefreshDevices: Bool = true
    @AppStorage("refreshInterval") private var refreshInterval: Double = 5.0
    @AppStorage("defaultMapStyle") private var defaultMapStyle: String = "standard"
    @AppStorage("showCoordinatesOnMap") private var showCoordinatesOnMap: Bool = true
    @AppStorage("autoStartTunneld") private var autoStartTunneld: Bool = true
    @State private var showDiagnostics: Bool = false

    var body: some View {
        Form {
            Section("Device Connection") {
                Toggle("Auto-refresh device list", isOn: $autoRefreshDevices)

                if autoRefreshDevices {
                    HStack {
                        Text("Refresh interval")
                        Spacer()
                        Picker("", selection: $refreshInterval) {
                            Text("5 seconds").tag(5.0)
                            Text("10 seconds").tag(10.0)
                            Text("30 seconds").tag(30.0)
                            Text("60 seconds").tag(60.0)
                        }
                        .frame(width: 150)
                    }
                }
            }

            // NEW: Connection Mode Section
            connectionModeSection

            Section("Map Display") {
                Picker("Default map style", selection: $defaultMapStyle) {
                    Text("Standard").tag("standard")
                    Text("Satellite").tag("satellite")
                    Text("Hybrid").tag("hybrid")
                }

                Toggle("Show coordinates overlay", isOn: $showCoordinatesOnMap)
            }

            // Enhanced tunneld section with auto-management
            tunneldSection

            // Advanced Settings
            advancedSection

            // Keyboard Shortcuts Section
            keyboardShortcutsSection

            // Diagnostics Section
            Section("Troubleshooting") {
                Button {
                    showDiagnostics = true
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Run Diagnostics")
                            Text("Check Python, tunnel, device, and injection status")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "stethoscope")
                            .foregroundColor(.blue)
                    }
                }
                .buttonStyle(.plain)
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsSheet()
                    .environmentObject(appState)
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("iOS Support")
                    Spacer()
                    Text("iOS 15–27 (keep tunnel running)")
                        .foregroundColor(.secondary)
                }

                Link("Documentation", destination: URL(string: "https://github.com/doronz88/pymobiledevice3")!)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    // MARK: - Tunnel Section (Multi-Mode Support)

    private var tunneldSection: some View {
        Section("Tunnel (iOS 17+ Device Communication)") {
            // Tunnel Mode Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Tunnel Mode")
                    .font(.headline)

                Picker("Mode", selection: $tunneldManager.preferredMode) {
                    ForEach(TunnelMode.allCases) { mode in
                        HStack {
                            Image(systemName: iconForTunnelMode(mode))
                            Text(mode.rawValue)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                // Mode description
                Text(tunneldManager.preferredMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)

            // Status indicator with start/stop controls
            HStack {
                // Status indicator
                HStack(spacing: 8) {
                    if tunneldManager.isStarting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 10, height: 10)
                    } else {
                        Circle()
                            .fill(tunneldManager.isRunning ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(tunneldStatusText)
                                .fontWeight(.medium)
                            if let mode = tunneldManager.activeMode {
                                Text("(\(mode.rawValue))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let message = tunneldManager.statusMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Control buttons
                if tunneldManager.isRunning {
                    Button("Stop Tunnel") {
                        tunneldManager.stopTunnel()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else if tunneldManager.isStarting {
                    Button("Starting...") { }
                        .buttonStyle(.bordered)
                        .disabled(true)
                } else {
                    Button("Start Tunnel") {
                        Task {
                            await tunneldManager.startTunnel()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            // RSD Connection Info (if available)
            if let info = tunneldManager.tunnelInfo {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.blue)
                        Text("RSD Address: \(info.rsdAddress)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Image(systemName: "number")
                            .foregroundColor(.blue)
                        Text("Port: \(info.rsdPort)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let interface = info.interface {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.blue)
                            Text("Interface: \(interface)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Auto-start toggle
            Toggle(isOn: $autoStartTunneld) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-start tunnel on app launch")
                    Text("Automatically manages the tunnel lifecycle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Error display
            if let error = tunneldManager.lastError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            // Info about tunnel modes
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("USB mode: Fastest, requires USB cable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "cable.connector")
                        .foregroundColor(.blue)
                }

                Label {
                    Text("WiFi mode: True wireless, device must be on same network")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "wifi")
                        .foregroundColor(.blue)
                }

                Label {
                    Text("Daemon mode: Background service, auto-discovers devices")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "server.rack")
                        .foregroundColor(.blue)
                }

                Label {
                    Text("Runs with your user account")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "person.crop.circle")
                        .foregroundColor(.blue)
                }
            }
            .padding(.top, 4)
        }
    }

    private func iconForTunnelMode(_ mode: TunnelMode) -> String {
        switch mode {
        case .auto: return "sparkles"
        case .usb: return "cable.connector"
        case .wifi: return "wifi"
        case .daemon: return "server.rack"
        }
    }

    private var tunneldStatusText: String {
        if tunneldManager.isStarting {
            return "Starting..."
        } else if tunneldManager.isRunning {
            return "Running"
        } else {
            return "Not Running"
        }
    }

    // MARK: - Connection Mode Section

    private var connectionModeSection: some View {
        Section("Connection Mode") {
            // Connection Mode Picker
            Picker("Preferred Connection", selection: Binding(
                get: { appState.deviceManager.connectionMode },
                set: { appState.deviceManager.setConnectionMode($0) }
            )) {
                ForEach(DeviceManager.ConnectionMode.allCases, id: \.self) { mode in
                    HStack {
                        Image(systemName: iconForMode(mode))
                        Text(mode.rawValue)
                    }
                    .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // Connection Status Indicators
            HStack(spacing: 16) {
                ConnectionStatusBadge(
                    title: "USB",
                    isConnected: appState.isUSBConnected,
                    icon: "cable.connector"
                )

                ConnectionStatusBadge(
                    title: "WiFi",
                    isConnected: appState.isTunneldRunning,
                    icon: "wifi"
                )
            }
            .padding(.vertical, 8)

            // Prefer USB Toggle
            Toggle(isOn: $appState.preferUSBConnection) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prefer USB when available")
                    Text("USB connection is more stable but requires a cable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Fallback Information
            if !appState.isTunneldRunning && !appState.isUSBConnected {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("No connection available. Connect via USB or start tunneld for WiFi.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else if appState.preferUSBConnection && appState.isUSBConnected {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Using USB connection (preferred)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else if appState.isTunneldRunning {
                HStack {
                    Image(systemName: "wifi")
                        .foregroundColor(.blue)
                    Text("Using WiFi connection via tunneld")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func iconForMode(_ mode: DeviceManager.ConnectionMode) -> String {
        switch mode {
        case .auto: return "arrow.triangle.2.circlepath"
        case .usb: return "cable.connector"
        case .wifi: return "wifi"
        }
    }

    // MARK: - Advanced Settings Section

    private var advancedSection: some View {
        Section("Advanced") {
            HStack {
                Text("Command Timeout")
                Spacer()
                Picker("", selection: Binding(
                    get: { AppSettings.shared.commandTimeout },
                    set: { AppSettings.shared.commandTimeout = $0 }
                )) {
                    Text("15 seconds").tag(15.0)
                    Text("30 seconds").tag(30.0)
                    Text("45 seconds").tag(45.0)
                    Text("60 seconds").tag(60.0)
                }
                .frame(width: 150)
            }

            HStack {
                Text("Tunnel Start Timeout")
                Spacer()
                Picker("", selection: Binding(
                    get: { AppSettings.shared.tunnelTimeout },
                    set: { AppSettings.shared.tunnelTimeout = $0 }
                )) {
                    Text("30 seconds").tag(30.0)
                    Text("45 seconds").tag(45.0)
                    Text("60 seconds").tag(60.0)
                    Text("90 seconds").tag(90.0)
                }
                .frame(width: 150)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("These timeouts control how long the app waits for device communication.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Increase if you experience timeout errors on slow connections.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Keyboard Shortcuts Section

    private var keyboardShortcutsSection: some View {
        Section("Keyboard Shortcuts") {
            VStack(alignment: .leading, spacing: 16) {
                // Location Commands
                ShortcutGroup(title: "Location") {
                    ShortcutRow(shortcut: "⌘L", description: "Set location at current coordinates")
                    ShortcutRow(shortcut: "⌘K", description: "Clear current location")
                    ShortcutRow(shortcut: "⌘R", description: "Refresh device list")
                }

                Divider()

                // Simulation Commands
                ShortcutGroup(title: "Simulation") {
                    ShortcutRow(shortcut: "⌘Space", description: "Start simulation")
                    ShortcutRow(shortcut: "⌘P", description: "Pause simulation")
                    ShortcutRow(shortcut: "⌘Esc", description: "Stop simulation")
                }

                Divider()

                // Navigation Commands
                ShortcutGroup(title: "Navigation") {
                    ShortcutRow(shortcut: "⌘⇧S", description: "Toggle sidebar")
                    ShortcutRow(shortcut: "⌘,", description: "Open settings")
                }

                Divider()

                // Speed Control Commands
                ShortcutGroup(title: "Speed Control") {
                    ShortcutRow(shortcut: "⌘⌥↑", description: "Increase simulation speed")
                    ShortcutRow(shortcut: "⌘⌥↓", description: "Decrease simulation speed")
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Connection Status Badge

struct ConnectionStatusBadge: View {
    let title: String
    let isConnected: Bool
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(isConnected ? .green : .gray)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(isConnected ? "Available" : "Unavailable")
                    .font(.caption2)
                    .foregroundColor(isConnected ? .green : .secondary)
            }
        }
        .padding(8)
        .background(isConnected ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Keyboard Shortcut Helper Views

/// Groups related shortcuts with a title
struct ShortcutGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            content()
        }
    }
}

/// Displays a single shortcut with its description
struct ShortcutRow: View {
    let shortcut: String
    let description: String

    var body: some View {
        HStack {
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(.blue)
                .frame(width: 80, alignment: .leading)

            Text(description)
                .font(.callout)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AppState())
    }
}
#endif
