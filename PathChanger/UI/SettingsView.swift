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
    @AppStorage(DeviceAutoRefreshPreferences.enabledKey) private var autoRefreshDevices: Bool = DeviceAutoRefreshPreferences.defaultEnabled
    @AppStorage(DeviceAutoRefreshPreferences.intervalKey) private var refreshInterval: Double = DeviceAutoRefreshPreferences.defaultInterval
    @AppStorage("defaultMapStyle") private var defaultMapStyle: String = "standard"
    @AppStorage("showCoordinatesOnMap") private var showCoordinatesOnMap: Bool = true
    @AppStorage("autoStartTunneld") private var autoStartTunneld: Bool = false
    @State private var showDiagnostics: Bool = false
    @State private var showTunnelStopConfirmation = false

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
            .frame(maxWidth: DS.Metrics.settingsContentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.pcBackground)
        .navigationTitle("Settings")
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsSheet()
                .environmentObject(appState)
        }
        .alert("Stop tunnel?", isPresented: $showTunnelStopConfirmation) {
            Button("Stop", role: .destructive) {
                tunneldManager.stopTunnel()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will disconnect the current tunnel session.")
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
                    SettingsLine(title: "Refresh interval", subtitle: "Controls background device scanning cadence; shorter intervals may reduce stability") {
                        Picker("", selection: $refreshInterval) {
                            Text("1 minute").tag(60.0)
                            Text("2 minutes").tag(120.0)
                            Text("5 minutes").tag(300.0)
                        }
                        .labelsHidden()
                        .frame(width: DS.Metrics.settingsPickerWidth)
                    }
                }
            }
        }
        .onChange(of: autoRefreshDevices) { _, enabled in
            appState.deviceManager.configureAutoRefresh(enabled: enabled, interval: refreshInterval)
        }
        .onChange(of: refreshInterval) { _, interval in
            appState.deviceManager.configureAutoRefresh(enabled: autoRefreshDevices, interval: interval)
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
        if let summary = ConnectionSummaryPresentation.resolve(
            isTunnelRunning: appState.isTunneldRunning,
            activeTunnelMode: tunneldManager.presentationActiveMode,
            tunnelInfoMode: tunneldManager.tunnelInfo?.mode,
            preferredMode: tunneldManager.preferredMode,
            selectedConnectionType: appState.selectedDevice?.connectionType,
            isUSBConnected: appState.isUSBConnected,
            isWiFiAvailable: appState.isWiFiAvailable,
            isConnectionHealthy: tunneldManager.currentTunnelConnectivityHealthy(),
            preferUSBConnection: appState.preferUSBConnection
        ) {
            PCStatusChip(
                title: summary.title,
                icon: summary.icon,
                color: summary.color,
                detail: summary.detail
            )
        }
    }

    /// Inspector/administrative tunnel control surface.
    ///
    /// W1 Authority Declaration (Slice S0 — documentation only; see W1
    /// governance plan):
    ///   - This card is an INSPECTOR/ADMIN-ONLY surface. It is NOT a
    ///     workflow authority and MUST NOT participate in the canonical
    ///     Device → Location → Simulation progression.
    ///   - Its Start/Stop controls are administrative overrides for
    ///     advanced users who explicitly open Settings. They do not own
    ///     Phase-1 readiness semantics (which belong to `DeviceTunnelPill`)
    ///     and they do not own T0 execution semantics (which belong to
    ///     `PrimaryActionPill`).
    ///   - The Start button dispatches `autoStart()` so surviving UI
    ///     tunnel-start surfaces share a single transport-start semantic.
    ///
    /// W1 Slice S0 is documentation-only. No behavior, layout, state,
    /// bindings, or routing are altered by this declaration.
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
                        Label(mode.displayName, systemImage: iconForTunnelMode(mode))
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
                            .scaleEffect(DS.Metrics.settingsTunnelSpinnerScale)
                    } else {
                        Circle()
                            .fill(tunneldManager.isRunning ? Color.pcSecondary : Color.pcDanger)
                            .frame(width: DS.Metrics.settingsStatusDotSize, height: DS.Metrics.settingsStatusDotSize)
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
                            showTunnelStopConfirmation = true
                        }
                        .buttonStyle(AppCapsuleButtonStyle(accent: .pcDanger))
                    } else if tunneldManager.isStarting {
                        Button("Starting...") { }
                            .buttonStyle(AppCapsuleButtonStyle(accent: .pcTextMuted))
                            .disabled(true)
                    } else {
                        Button("Start") {
                            Task {
                                await tunneldManager.autoStart()
                            }
                        }
                        .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
                    }
                }
                .padding(AppSpacing.md)
                .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: DS.Metrics.strokeWidth)
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
                        .background(Color.pcWarning.opacity(DS.Opacity.warningTint), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Label("USB mode: Fastest, requires USB cable", systemImage: "cable.connector")
                    Label("WiFi Only: Legacy manual-pairing path for iOS 17/18", systemImage: "wifi")
                    Label("Background Daemon: Recommended wireless mode for iOS 26+", systemImage: "server.rack")
                    Label("Requires administrator privileges", systemImage: "lock.shield")
                }
                .font(AppFont.metadata)
                .foregroundStyle(Color.pcTextMuted)
            }
        }
    }

    /// Wi-Fi pairing card. Visible only when the user explicitly targets the
    /// legacy WiFi Only mode. Surfaces:
    ///   1. Whether any iPhone is currently advertising over Bonjour ("Probe").
    ///   2. A "Pair Over Wi-Fi" button that drives `scripts/pair_wifi.py` with
    ///      administrator privileges (30s Bonjour browse + iPhone-side prompt).
    ///   3. The most recent script output, so users can diagnose failures
    ///      without leaving the app.
    @ViewBuilder
    private var wifiPairingCard: some View {
        if tunneldManager.preferredMode == .wifi {
            PCSectionCard(
                title: "Legacy Wi-Fi Pairing",
                subtitle: "Only needed for WiFi Only on iOS 17/18. For iOS 26+, use Background Daemon.",
                icon: "wifi.router",
                badge: "Legacy"
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
                .font(DS.Typography.title)
                .foregroundStyle(bonjourStatusColor)
                .frame(width: DS.Metrics.settingsListIconWidth)

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
                    ProgressView().scaleEffect(DS.Metrics.settingsProbeSpinnerScale)
                } else {
                    Label("Probe", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
            .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent))
            .disabled(tunneldManager.bonjourProbeInProgress)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: DS.Metrics.strokeWidth)
        )
    }

    private var pairButtonRow: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            Image(systemName: "key.horizontal")
                .font(DS.Typography.title)
                .foregroundStyle(Color.pcAccent)
                .frame(width: DS.Metrics.settingsListIconWidth)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("Pair this Mac with the iPhone for legacy WiFi Only")
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
                        ProgressView().scaleEffect(DS.Metrics.settingsPairSpinnerScale)
                        Text("Pairing…")
                    }
                } else {
                    Label("Pair Over Wi-Fi", systemImage: "wifi")
                }
            }
            .buttonStyle(AppCapsuleButtonStyle(accent: .pcAccent, isProminent: true))
            .disabled(tunneldManager.wifiPairingInProgress)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: DS.Metrics.strokeWidth)
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
            .frame(maxHeight: DS.Metrics.settingsLogMaxHeight)
            .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        }
    }

    private var pairInstructions: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Label("For iOS 26 and later, choose Background Daemon instead of WiFi Only", systemImage: "server.rack")
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
            return "No manual-pairing service was found. On iOS 26+, use Background Daemon instead."
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
                    .frame(width: DS.Metrics.settingsPickerWidth)
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
                    .frame(width: DS.Metrics.settingsPickerWidth)
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
                    .frame(width: DS.Metrics.settingsPickerWidth)
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
                    ShortcutRow(shortcut: "⌘\\", description: "Toggle sidebar")
                    ShortcutRow(shortcut: "⌘,", description: "Open settings")
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
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(Color.pcSurfaceHigh.opacity(AppSurfaceAlpha.selectedRow), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(Color.pcOutline.opacity(AppSurfaceAlpha.outline), lineWidth: DS.Metrics.strokeWidth)
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
                .stroke(
                    isConnected ? Color.pcSecondary.opacity(AppSurfaceAlpha.hoverRow) : Color.pcOutline.opacity(AppSurfaceAlpha.outline),
                    lineWidth: DS.Metrics.strokeWidth
                )
        )
    }
}

struct ConnectionSummaryPresentation: Equatable {
    /// Four-state-per-transport tone model (see Connection Mode redesign):
    /// - connected: tunnel up AND device reachable/healthy (green)
    /// - active: this transport owns the running tunnel but health is not yet
    ///   confirmed, e.g. starting/handshaking (white/grey)
    /// - notConnected: transport is available but no working tunnel (red)
    /// - warning: nothing available and nothing connected (amber)
    enum Tone: Equatable {
        case connected
        case active
        case notConnected
        case warning

        var color: Color {
            switch self {
            case .connected:
                return .pcSecondary   // green
            case .active:
                return .pcText        // white / grey-white
            case .notConnected:
                return .pcDanger      // red
            case .warning:
                return .pcWarning     // amber
            }
        }
    }

    let title: String
    let icon: String
    let tone: Tone
    let detail: String?

    var color: Color {
        tone.color
    }

    static func resolve(
        isTunnelRunning: Bool,
        activeTunnelMode: TunnelMode?,
        tunnelInfoMode: TunnelMode? = nil,
        preferredMode: TunnelMode = .auto,
        selectedConnectionType: ConnectionType?,
        isUSBConnected: Bool,
        isWiFiAvailable: Bool,
        isConnectionHealthy: Bool,
        preferUSBConnection: Bool
    ) -> ConnectionSummaryPresentation? {
        // Honest availability for the detail line, including the real
        // both-at-once case (cable in AND same Wi-Fi network).
        let availability = availabilityText(usb: isUSBConnected, wifi: isWiFiAvailable)

        // Active tunnel: report the ACTIVE transport and whether it is
        // confirmed connected (green) or merely active/handshaking (grey).
        if isTunnelRunning {
            let resolvedMode = presentationMode(
                activeTunnelMode: activeTunnelMode,
                tunnelInfoMode: tunnelInfoMode,
                preferredMode: preferredMode
            )
            // When USB is not physically connected, a running tunnel cannot be
            // cable-backed; collapse a stale `.usb` signal to wireless so we
            // never claim USB under a Wi-Fi session.
            let coerceToWireless = (resolvedMode == .usb) && !isUSBConnected
            let mode = coerceToWireless ? TunnelMode.wifi : resolvedMode

            let transport: String
            let icon: String
            let tunnelKind: String
            switch mode {
            case .usb:
                transport = "USB"; icon = "cable.connector"; tunnelKind = "lockdown tunnel"
            case .wifi:
                transport = "Wi-Fi"; icon = "wifi"; tunnelKind = "Wi-Fi tunnel"
            case .daemon:
                transport = "Wi-Fi"; icon = "wifi"; tunnelKind = "background daemon tunnel"
            case .auto, .none:
                transport = "Tunnel"; icon = "point.3.connected.trianglepath.dotted"; tunnelKind = "tunnel"
            }

            let detail = [tunnelKind, availability].compactMap { $0 }.joined(separator: " · ")
            return ConnectionSummaryPresentation(
                title: "\(transport) \(isConnectionHealthy ? "Connected" : "Active")",
                icon: icon,
                tone: isConnectionHealthy ? .connected : .active,
                detail: detail.isEmpty ? nil : detail
            )
        }

        // No tunnel running. If a transport is available, it is reachable but
        // not connected (red). Choose which transport to title by
        // selection/preference, else USB before Wi-Fi.
        let reported: (label: String, icon: String)?
        if selectedConnectionType == .usb, isUSBConnected {
            reported = ("USB", "cable.connector")
        } else if selectedConnectionType == .wifi, isWiFiAvailable {
            reported = ("Wi-Fi", "wifi")
        } else if preferUSBConnection, isUSBConnected {
            reported = ("USB", "cable.connector")
        } else if isUSBConnected {
            reported = ("USB", "cable.connector")
        } else if isWiFiAvailable {
            reported = ("Wi-Fi", "wifi")
        } else {
            reported = nil
        }

        if let reported {
            return ConnectionSummaryPresentation(
                title: "\(reported.label) Not Connected",
                icon: reported.icon,
                tone: .notConnected,
                detail: availability
            )
        }

        // Nothing available and nothing connected.
        return ConnectionSummaryPresentation(
            title: "No Connection",
            icon: "exclamationmark.triangle.fill",
            tone: .warning,
            detail: "connect USB or start tunnel"
        )
    }

    private static func presentationMode(
        activeTunnelMode: TunnelMode?,
        tunnelInfoMode: TunnelMode?,
        preferredMode: TunnelMode
    ) -> TunnelMode? {
        if preferredMode == .wifi || preferredMode == .daemon {
            return preferredMode
        }
        if let tunnelInfoMode,
           tunnelInfoMode != .auto,
           tunnelInfoMode != activeTunnelMode {
            return tunnelInfoMode
        }
        return activeTunnelMode ?? tunnelInfoMode
    }

    /// Honest availability detail reflecting exactly which transports are
    /// available, including the both-at-once (USB cable + same Wi-Fi) case.
    private static func availabilityText(usb: Bool, wifi: Bool) -> String? {
        switch (usb, wifi) {
        case (true, true):
            return "USB + Wi-Fi available"
        case (true, false):
            return "USB available"
        case (false, true):
            return "Wi-Fi available"
        case (false, false):
            return nil
        }
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
                .tracking(DS.Metrics.shortcutLabelTracking)

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
                .frame(width: DS.Metrics.shortcutKeyWidth, alignment: .leading)

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
