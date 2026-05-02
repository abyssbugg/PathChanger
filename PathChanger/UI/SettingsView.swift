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
    @AppStorage("autoStartTunneld") private var autoStartTunneld: Bool = false
    @State private var showDiagnostics: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                settingsHeader
                deviceConnectionCard
                connectionModeCard
                tunnelModeCard
                mapDisplayCard
                advancedSettingsCard
                keyboardShortcutsCard
                troubleshootingCard
                aboutCard
            }
            .padding(AppSpacing.xl)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .background(Color.pcBackground)
        .navigationTitle("Settings")
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsSheet()
                .environmentObject(appState)
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Settings")
                .font(AppFont.title)
                .foregroundStyle(Color.pcText)
            Text("Device connection, tunnel, display, shortcuts, and diagnostics")
                .font(AppFont.caption)
                .foregroundStyle(Color.pcTextMuted)
        }
        .padding(.bottom, AppSpacing.xs)
    }

    private var deviceConnectionCard: some View {
        PCSectionCard(
            title: "Device Connection",
            subtitle: "Manage hardware scanning behavior.",
            icon: "iphone"
        ) {
            VStack(spacing: AppSpacing.md) {
                SettingsLine(title: "Auto-refresh device list", subtitle: "Keep connected device state fresh") {
                    Toggle("", isOn: $autoRefreshDevices)
                        .labelsHidden()
                }

                if autoRefreshDevices {
                    SettingsLine(title: "Refresh interval", subtitle: "Controls automatic device scanning cadence") {
                        Picker("", selection: $refreshInterval) {
                            Text("5 seconds").tag(5.0)
                            Text("10 seconds").tag(10.0)
                            Text("30 seconds").tag(30.0)
                            Text("60 seconds").tag(60.0)
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }
            }
        }
    }

    private var connectionModeCard: some View {
        PCSectionCard(
            title: "Connection Mode",
            subtitle: "Prefer USB for stability while preserving true Wi-Fi availability detection.",
            icon: "point.3.connected.trianglepath.dotted"
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Picker("Preferred Connection", selection: Binding(
                    get: { appState.deviceManager.connectionMode },
                    set: { appState.deviceManager.setConnectionMode($0) }
                )) {
                    ForEach(DeviceManager.ConnectionMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: iconForMode(mode))
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: AppSpacing.md) {
                    ConnectionStatusBadge(
                        title: "USB",
                        isConnected: appState.isUSBConnected,
                        icon: "cable.connector"
                    )

                    ConnectionStatusBadge(
                        title: "Wi-Fi",
                        isConnected: appState.isWiFiAvailable,
                        icon: "wifi"
                    )
                }

                SettingsLine(title: "Prefer USB when available", subtitle: "USB is the stable default when a cable is connected") {
                    Toggle("", isOn: $appState.preferUSBConnection)
                        .labelsHidden()
                }

                connectionSummary
            }
        }
    }

    @ViewBuilder
    private var connectionSummary: some View {
        if !appState.isTunneldRunning && !appState.isUSBConnected && !appState.isWiFiAvailable {
            PCStatusChip(title: "No Connection", icon: "exclamationmark.triangle.fill", color: .pcWarning, detail: "connect USB or start tunnel")
        } else if appState.preferUSBConnection && appState.isUSBConnected {
            PCStatusChip(title: "USB Preferred", icon: "checkmark.circle.fill", color: .pcSecondary, detail: "using cable")
        } else if appState.selectedDevice?.connectionType == .usb {
            PCStatusChip(title: "USB", icon: "cable.connector", color: .pcPrimary, detail: appState.isTunneldRunning ? "active tunnel" : "direct")
        } else if appState.selectedDevice?.connectionType == .wifi {
            PCStatusChip(title: "Wi-Fi", icon: "wifi", color: .pcPrimary, detail: appState.isTunneldRunning ? "active tunnel" : "available")
        } else if appState.isTunneldRunning {
            PCStatusChip(title: "Tunnel Active", icon: "point.3.connected.trianglepath.dotted", color: .pcSecondary)
        }
    }

    private var tunnelModeCard: some View {
        PCSectionCard(
            title: "Tunnel Mode",
            subtitle: "iOS 17+ communication through pymobiledevice3 tunnels.",
            icon: "network",
            badge: "iOS 17+"
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Picker("Mode", selection: $tunneldManager.preferredMode) {
                    ForEach(TunnelMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: iconForTunnelMode(mode))
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(tunneldManager.preferredMode.description)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.pcTextMuted)

                HStack(spacing: AppSpacing.md) {
                    if tunneldManager.isStarting {
                        ProgressView()
                            .scaleEffect(0.75)
                    } else {
                        Circle()
                            .fill(tunneldManager.isRunning ? Color.pcSecondary : Color.pcDanger)
                            .frame(width: 8, height: 8)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tunneldStatusText)
                            .font(AppFont.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.pcText)
                        if let message = tunneldManager.statusMessage {
                            Text(message)
                                .font(AppFont.caption)
                                .foregroundStyle(Color.pcTextMuted)
                        }
                    }

                    Spacer()

                    if tunneldManager.isRunning {
                        Button("Stop") {
                            tunneldManager.stopTunnel()
                        }
                        .buttonStyle(AppCapsuleButtonStyle(accent: .pcDanger))
                    } else if tunneldManager.isStarting {
                        Button("Starting...") { }
                            .buttonStyle(AppCapsuleButtonStyle(accent: .pcTextMuted))
                            .disabled(true)
                    } else {
                        Button("Start") {
                            Task {
                                await tunneldManager.startTunnel()
                            }
                        }
                        .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
                    }
                }
                .padding(AppSpacing.md)
                .background(Color.pcSurfaceHigh.opacity(0.5), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))

                if let info = tunneldManager.tunnelInfo {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        PCStatusChip(title: "RSD", icon: "network", color: .pcPrimary, detail: "\(info.rsdAddress):\(info.rsdPort)")
                        if let interface = info.interface {
                            PCStatusChip(title: "Interface", icon: "antenna.radiowaves.left.and.right", color: .pcPrimary, detail: interface)
                        }
                    }
                }

                SettingsLine(title: "Auto-start tunnel on app launch", subtitle: "Automatically manages the tunnel lifecycle") {
                    Toggle("", isOn: $autoStartTunneld)
                        .labelsHidden()
                }

                if let error = tunneldManager.lastError {
                    Text(error)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.pcWarning)
                        .padding(AppSpacing.md)
                        .background(Color.pcWarning.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Label("USB mode: Fastest, requires USB cable", systemImage: "cable.connector")
                    Label("Wi-Fi mode: True wireless, device must be on same network", systemImage: "wifi")
                    Label("Daemon mode: Background service, auto-discovers devices", systemImage: "server.rack")
                    Label("Requires administrator privileges", systemImage: "lock.shield")
                }
                .font(AppFont.caption)
                .foregroundStyle(Color.pcTextMuted)
            }
        }
    }

    private var mapDisplayCard: some View {
        PCSectionCard(title: "Map Display", subtitle: "Default map presentation preferences.", icon: "map") {
            VStack(spacing: AppSpacing.md) {
                SettingsLine(title: "Default map style", subtitle: "Used when opening the map") {
                    Picker("", selection: $defaultMapStyle) {
                        Text("Standard").tag("standard")
                        Text("Satellite").tag("satellite")
                        Text("Hybrid").tag("hybrid")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                SettingsLine(title: "Show coordinates overlay", subtitle: "Display coordinate readouts on the map") {
                    Toggle("", isOn: $showCoordinatesOnMap)
                        .labelsHidden()
                }
            }
        }
    }

    private var advancedSettingsCard: some View {
        PCSectionCard(title: "Advanced", subtitle: "Timeouts for device and tunnel communication.", icon: "slider.horizontal.3") {
            VStack(spacing: AppSpacing.md) {
                SettingsLine(title: "Command Timeout", subtitle: "How long command execution may wait") {
                    Picker("", selection: Binding(
                        get: { AppSettings.shared.commandTimeout },
                        set: { AppSettings.shared.commandTimeout = $0 }
                    )) {
                        Text("15 seconds").tag(15.0)
                        Text("30 seconds").tag(30.0)
                        Text("45 seconds").tag(45.0)
                        Text("60 seconds").tag(60.0)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                SettingsLine(title: "Tunnel Start Timeout", subtitle: "How long tunnel startup may wait") {
                    Picker("", selection: Binding(
                        get: { AppSettings.shared.tunnelTimeout },
                        set: { AppSettings.shared.tunnelTimeout = $0 }
                    )) {
                        Text("30 seconds").tag(30.0)
                        Text("45 seconds").tag(45.0)
                        Text("60 seconds").tag(60.0)
                        Text("90 seconds").tag(90.0)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }
        }
    }

    private var keyboardShortcutsCard: some View {
        PCSectionCard(title: "Keyboard Shortcuts", subtitle: "Quick access for core app flows.", icon: "keyboard") {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                ShortcutGroup(title: "Location") {
                    ShortcutRow(shortcut: "⌘L", description: "Set location at current coordinates")
                    ShortcutRow(shortcut: "⌘K", description: "Clear current location")
                    ShortcutRow(shortcut: "⌘R", description: "Refresh device list")
                }
                Divider().overlay(Color.white.opacity(0.08))
                ShortcutGroup(title: "Simulation") {
                    ShortcutRow(shortcut: "⌘Space", description: "Start simulation")
                    ShortcutRow(shortcut: "⌘P", description: "Pause simulation")
                    ShortcutRow(shortcut: "⌘Esc", description: "Stop simulation")
                }
                Divider().overlay(Color.white.opacity(0.08))
                ShortcutGroup(title: "Navigation") {
                    ShortcutRow(shortcut: "⌘⇧S", description: "Toggle sidebar")
                    ShortcutRow(shortcut: "⌘,", description: "Open settings")
                }
                Divider().overlay(Color.white.opacity(0.08))
                ShortcutGroup(title: "Speed Control") {
                    ShortcutRow(shortcut: "⌘⌥↑", description: "Increase simulation speed")
                    ShortcutRow(shortcut: "⌘⌥↓", description: "Decrease simulation speed")
                }
            }
        }
    }

    private var troubleshootingCard: some View {
        PCSectionCard(title: "Troubleshooting", subtitle: "Check Python, tunnel, device, and injection status.", icon: "stethoscope") {
            Button {
                showDiagnostics = true
            } label: {
                Label("Run Diagnostics", systemImage: "wrench.and.screwdriver.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
        }
    }

    private var aboutCard: some View {
        PCSectionCard(title: "About", icon: "info.circle") {
            VStack(spacing: AppSpacing.md) {
                SettingsLine(title: "Version") {
                    Text("1.0.0")
                        .font(AppFont.monoSmall)
                        .foregroundStyle(Color.pcTextMuted)
                }

                SettingsLine(title: "iOS Support") {
                    Text("Attempts all versions; newer iOS may need pymobiledevice3 updates")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.pcTextMuted)
                        .multilineTextAlignment(.trailing)
                }

                Link(destination: URL(string: "https://github.com/doronz88/pymobiledevice3")!) {
                    Label("pymobiledevice3 Documentation", systemImage: "arrow.up.right.square")
                        .foregroundStyle(Color.pcPrimary)
                }
            }
        }
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
                    Button("Stop") {
                        tunneldManager.stopTunnel()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else if tunneldManager.isStarting {
                    Button("Starting...") { }
                        .buttonStyle(.bordered)
                        .disabled(true)
                } else {
                    Button("Start") {
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
                    Text("Requires administrator privileges")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.orange)
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
                    title: "Wi-Fi",
                    isConnected: appState.isWiFiAvailable,
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
            if !appState.isTunneldRunning && !appState.isUSBConnected && !appState.isWiFiAvailable {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("No connection available. Connect via USB or start a tunnel.")
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
            } else if appState.selectedDevice?.connectionType == .usb {
                HStack {
                    Image(systemName: "cable.connector")
                        .foregroundColor(.blue)
                    Text(appState.isTunneldRunning ? "Using USB connection via active tunnel" : "Using USB connection")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else if appState.selectedDevice?.connectionType == .wifi {
                HStack {
                    Image(systemName: "wifi")
                        .foregroundColor(.blue)
                    Text(appState.isTunneldRunning ? "Using Wi-Fi connection via active tunnel" : "Wi-Fi device available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else if appState.isTunneldRunning {
                HStack {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundColor(.green)
                    Text("Tunnel active")
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

// MARK: - Settings Helper Views

struct SettingsLine<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppFont.body)
                    .foregroundStyle(Color.pcText)
                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.pcTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            trailing
        }
        .padding(AppSpacing.md)
        .background(Color.pcSurfaceHigh.opacity(0.38), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

struct ConnectionStatusBadge: View {
    let title: String
    let isConnected: Bool
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(isConnected ? .pcSecondary : .pcTextMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.pcText)
                Text(isConnected ? "Available" : "Unavailable")
                    .font(.caption2)
                    .foregroundColor(isConnected ? .pcSecondary : .pcTextMuted)
            }
        }
        .padding(AppSpacing.sm)
        .background(isConnected ? Color.pcSecondary.opacity(0.1) : Color.pcSurfaceHigh.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(isConnected ? Color.pcSecondary.opacity(0.24) : Color.white.opacity(0.06), lineWidth: 1)
        )
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
                .font(AppFont.labelCaps)
                .fontWeight(.semibold)
                .foregroundColor(.pcPrimary)
                .textCase(.uppercase)
                .tracking(1.4)

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
                .foregroundColor(.pcPrimary)
                .frame(width: 80, alignment: .leading)

            Text(description)
                .font(.callout)
                .foregroundColor(.pcTextMuted)

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
