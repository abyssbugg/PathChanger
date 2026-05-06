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
    let showsHeader: Bool
    @AppStorage("autoRefreshDevices") private var autoRefreshDevices: Bool = true
    @AppStorage("refreshInterval") private var refreshInterval: Double = 5.0
    @AppStorage("defaultMapStyle") private var defaultMapStyle: String = "standard"
    @AppStorage("showCoordinatesOnMap") private var showCoordinatesOnMap: Bool = true
    @AppStorage("autoStartTunneld") private var autoStartTunneld: Bool = false
    @State private var showDiagnostics: Bool = false

    init(showsHeader: Bool = true) {
        self.showsHeader = showsHeader
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                if showsHeader {
                    settingsHeader
                }
                deviceConnectionCard
                connectionModeCard
                tunnelModeCard
                wifiPairingCard
                mapDisplayCard
                advancedSettingsCard
                keyboardShortcutsCard
                troubleshootingCard
                aboutCard
            }
            .padding(AppSpacing.xl)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
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
                .font(AppFont.metadata)
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
            subtitle: "Choose how PathChanger connects to the selected device.",
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
            PCStatusChip(title: "Using USB", icon: "checkmark.circle.fill", color: .pcSecondary, detail: "cable connected")
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
            subtitle: "Connect to iOS devices through the selected tunnel transport.",
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
                    .font(AppFont.metadata)
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

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(tunneldStatusText)
                            .font(AppFont.body)
                            .foregroundStyle(Color.pcText)
                        if let message = tunneldManager.statusMessage {
                            Text(message)
                                .font(AppFont.metadata)
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
                .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
                )

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
                        .font(AppFont.metadata)
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
                .font(AppFont.metadata)
                .foregroundStyle(Color.pcTextMuted)
            }
        }
    }

    /// Wi-Fi pairing card. Visible only when the user is targeting Wi-Fi mode
    /// (preferredMode == .wifi or .auto). Surfaces:
    ///   1. Whether any iPhone is currently advertising over Bonjour ("Probe").
    ///   2. A "Pair Over Wi-Fi" button that drives `scripts/pair_wifi.py` with
    ///      administrator privileges (30s Bonjour browse + iPhone-side prompt).
    ///   3. The most recent script output, so users can diagnose failures
    ///      without leaving the app.
    @ViewBuilder
    private var wifiPairingCard: some View {
        if tunneldManager.preferredMode == .wifi || tunneldManager.preferredMode == .auto {
            PCSectionCard(
                title: "Wi-Fi Pairing",
                subtitle: "Required once per Mac before WiFi-mode tunnels can connect.",
                icon: "wifi.router",
                badge: "iOS 17+"
            ) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    bonjourProbeRow
                    pairButtonRow
                    if !tunneldManager.wifiPairingLog.isEmpty {
                        pairScriptLogView
                    }
                    pairInstructions
                }
            }
        }
    }

    private var bonjourProbeRow: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            Image(systemName: bonjourStatusIcon)
                .font(.system(size: 18))
                .foregroundStyle(bonjourStatusColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(bonjourStatusTitle)
                    .font(AppFont.body)
                    .foregroundStyle(Color.pcText)
                Text(bonjourStatusSubtitle)
                    .font(AppFont.metadata)
                    .foregroundStyle(Color.pcTextMuted)
            }

            Spacer()

            Button {
                Task { await tunneldManager.probeBonjourWiFiDevices() }
            } label: {
                if tunneldManager.bonjourProbeInProgress {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Label("Probe", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
            .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent))
            .disabled(tunneldManager.bonjourProbeInProgress)
        }
        .padding(AppSpacing.md)
        .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
        )
    }

    private var pairButtonRow: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 18))
                .foregroundStyle(Color.pcAccent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("Pair this Mac with the iPhone over Wi-Fi")
                    .font(AppFont.body)
                    .foregroundStyle(Color.pcText)
                Text(pairButtonSubtitle)
                    .font(AppFont.metadata)
                    .foregroundStyle(Color.pcTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                Task { _ = await tunneldManager.pairOverWiFi() }
            } label: {
                if tunneldManager.wifiPairingInProgress {
                    HStack(spacing: AppSpacing.xs) {
                        ProgressView().scaleEffect(0.65)
                        Text("Pairing…")
                    }
                } else {
                    Label("Pair Over Wi-Fi", systemImage: "wifi")
                }
            }
            .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
            .disabled(tunneldManager.wifiPairingInProgress)
        }
        .padding(AppSpacing.md)
        .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
        )
    }

    private var pairScriptLogView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Pairing log")
                .font(AppFont.label)
                .foregroundStyle(Color.pcTextMuted)
            ScrollView {
                Text(tunneldManager.wifiPairingLog)
                    .font(AppFont.monoSmall)
                    .foregroundStyle(Color.pcText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.sm)
            }
            .frame(maxHeight: 160)
            .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        }
    }

    private var pairInstructions: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Label("On the iPhone, enable Settings → Privacy & Security → Developer Mode", systemImage: "hammer")
            Label("Settings → Developer → \u{201C}Pair Wirelessly\u{201D} (toggle name varies by iOS version)", systemImage: "wifi.circle")
            Label("iPhone must be UNLOCKED and on the same Wi-Fi as this Mac", systemImage: "lock.open")
            Label("You will be prompted for an administrator password and then for confirmation on the iPhone", systemImage: "checkmark.seal")
        }
        .font(AppFont.metadata)
        .foregroundStyle(Color.pcTextMuted)
    }

    // MARK: WiFi Pairing Helpers

    private var bonjourStatusIcon: String {
        if tunneldManager.bonjourProbeInProgress { return "clock" }
        return tunneldManager.bonjourVisibleUDIDs.isEmpty ? "questionmark.circle" : "wifi"
    }

    private var bonjourStatusColor: Color {
        if tunneldManager.bonjourProbeInProgress { return .pcTextMuted }
        return tunneldManager.bonjourVisibleUDIDs.isEmpty ? .pcWarning : .pcSecondary
    }

    private var bonjourStatusTitle: String {
        if tunneldManager.bonjourProbeInProgress {
            return "Probing local network…"
        }
        let count = tunneldManager.bonjourVisibleUDIDs.count
        if count == 0 {
            return "No iPhones currently visible over Bonjour"
        }
        return "\(count) iPhone(s) visible over Bonjour"
    }

    private var bonjourStatusSubtitle: String {
        if tunneldManager.bonjourProbeInProgress {
            return "Looking for `_remotepairing._tcp` services on this Wi-Fi…"
        }
        if tunneldManager.bonjourVisibleUDIDs.isEmpty {
            return "Click \u{201C}Probe\u{201D} to scan, or pair the iPhone first."
        }
        return tunneldManager.bonjourVisibleUDIDs.prefix(2).joined(separator: ", ")
            + (tunneldManager.bonjourVisibleUDIDs.count > 2 ? ", …" : "")
    }

    private var pairButtonSubtitle: String {
        switch tunneldManager.lastWiFiPairingResult {
        case .success(let count):
            return "Last attempt succeeded (\(count) device(s) paired)."
        case .noDevicesFound:
            return "Last attempt found no _remotepairing-manual-pairing instances. Enable wireless pairing on the iPhone and retry."
        case .scriptError(let message):
            return "Last attempt failed: \(message)"
        case .userCancelled:
            return "Pairing was cancelled. You can retry anytime."
        case .scriptMissing:
            return "pair_wifi.py is missing from the app bundle. Reinstall PathChanger."
        case .none:
            return "Runs scripts/pair_wifi.py with admin privileges; iPhone will prompt for confirmation."
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
                Divider().overlay(Color.pcOutline.opacity(AppSurfaceAlpha.divider))
                ShortcutGroup(title: "Simulation") {
                    ShortcutRow(shortcut: "⌘Space", description: "Start simulation")
                    ShortcutRow(shortcut: "⌘P", description: "Pause simulation")
                    ShortcutRow(shortcut: "⌘Esc", description: "Stop simulation")
                }
                Divider().overlay(Color.pcOutline.opacity(AppSurfaceAlpha.divider))
                ShortcutGroup(title: "Navigation") {
                    ShortcutRow(shortcut: "⌘⇧S", description: "Toggle sidebar")
                    ShortcutRow(shortcut: "⌘,", description: "Open settings")
                }
                Divider().overlay(Color.pcOutline.opacity(AppSurfaceAlpha.divider))
                ShortcutGroup(title: "Speed Control") {
                    ShortcutRow(shortcut: "⌘⌥↑", description: "Increase simulation speed")
                    ShortcutRow(shortcut: "⌘⌥↓", description: "Decrease simulation speed")
                }
            }
        }
    }

    private var troubleshootingCard: some View {
        PCSectionCard(title: "Troubleshooting", subtitle: "Check required tools, device access, and tunnel status.", icon: "stethoscope") {
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
                    Text("Attempts newer iOS versions when support tools allow it")
                        .font(AppFont.metadata)
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
            return "Tunnel inactive"
        }
    }

    private func iconForMode(_ mode: DeviceManager.ConnectionMode) -> String {
        switch mode {
        case .auto: return "arrow.triangle.2.circlepath"
        case .usb: return "cable.connector"
        case .wifi: return "wifi"
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
                        .font(AppFont.metadata)
                        .foregroundStyle(Color.pcTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            trailing
        }
        .padding(AppSpacing.md)
        .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
        )
    }
}

struct ConnectionStatusBadge: View {
    let title: String
    let isConnected: Bool
    let icon: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .foregroundColor(.pcTextMuted)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .font(AppFont.label)
                    .foregroundStyle(Color.pcText)
                Text(isConnected ? "Available" : "Unavailable")
                    .font(AppFont.metadata)
                    .foregroundColor(isConnected ? .pcSecondary : .pcTextMuted)
            }
        }
        .padding(AppSpacing.sm)
        .background(isConnected ? Color.pcSecondary.opacity(AppSurfaceAlpha.idleRow) : Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(isConnected ? Color.pcSecondary.opacity(AppSurfaceAlpha.hoverRow) : Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: 1)
        )
    }
}

// MARK: - Keyboard Shortcut Helper Views

/// Groups related shortcuts with a title
struct ShortcutGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppFont.labelCaps)
                .foregroundColor(.pcTextMuted)
                .textCase(.uppercase)
                .tracking(0.7)

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
                .font(AppFont.monoSmall)
                .foregroundColor(.pcText)
                .frame(width: 80, alignment: .leading)

            Text(description)
                .font(AppFont.body)
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
