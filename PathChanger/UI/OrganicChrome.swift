//
//  OrganicChrome.swift
//  PathChanger
//
//  Title bar, favorites rail, and telemetry strip from the pth mock.
//

import SwiftUI

/// Words the title-bar chip, the device picker rows and the tunnel help use for a
/// device's live reachability. Pure so the wording is testable without a view.
///
/// The connection mode never decides reachability; it only picks the advice for an
/// unreachable phone: USB-only mode needs the cable, Wi-Fi and Auto (and Random, which
/// can pick Wi-Fi) need the phone unlocked on this network.
enum OrganicDeviceChromeText {
    private static let wiFi = "Wi\u{2011}Fi"

    static func reachabilityWord(_ reachability: DeviceReachability, mode: DeviceManager.ConnectionMode) -> String {
        switch reachability {
        case .connected: return "connected"
        case .readyUSB: return "ready on USB"
        case .readyWiFi: return "ready on \(wiFi)"
        case .onNetwork: return "on \(wiFi) network"
        case .notReachable:
            return mode == .usb ? "not reachable — connect the cable and unlock" : "not reachable — unlock iPhone"
        }
    }

    static func subtitle(device: Device?, reachability: DeviceReachability, mode: DeviceManager.ConnectionMode) -> String {
        guard let device else {
            return "No iOS device"
        }
        return "iOS \(device.iosVersion) · \(reachabilityWord(reachability, mode: mode))"
    }

    /// The reachability dot: green when PathChanger can reach the phone, accent when only
    /// the network sees it, grey otherwise.
    static func tone(_ reachability: DeviceReachability, hasDevice: Bool) -> Color {
        guard hasDevice else { return Organic.neutral500 }
        switch reachability {
        case .connected, .readyUSB, .readyWiFi: return Organic.sage600
        case .onNetwork: return Organic.accent600
        case .notReachable: return Organic.neutral500
        }
    }

    /// Tunnel help while nothing is running and no live source sees the selected phone.
    static func unreachableTunnelHelp(
        reachability: DeviceReachability,
        tunnelRunning: Bool,
        mode: DeviceManager.ConnectionMode
    ) -> String? {
        guard !tunnelRunning, reachability == .notReachable else { return nil }
        if mode == .usb {
            return "iPhone is not reachable over USB. Connect it with a data cable, unlock it and tap Trust, then click to start."
        }
        return "iPhone is not reachable. Unlock it and keep it on the same \(wiFi) as this Mac, then click to start."
    }
}

/// How PathChanger connects to the phone, as the window offers it: USB or Wi‑Fi first,
/// Auto, Random and Background daemon as secondary choices. It is the setting in use
/// (`DeviceManager.connectionMode`, and the tunnel's Background daemon mode), never a
/// guess of the transport.
enum ConnectionChoice: String, CaseIterable, Identifiable, Hashable {
    case usb, wifi, auto, random, daemon

    var id: String { rawValue }

    static let primary: [ConnectionChoice] = [.usb, .wifi]
    static let secondary: [ConnectionChoice] = [.auto, .random, .daemon]

    /// The choice in use. The tunnel mode decides, because it is what Start uses and the
    /// Settings window's Tunnel Mode picker sets it on its own; the connection-mode setting
    /// only tells Random (which sets USB or Wi-Fi) apart (review 2026-11-04 round 2 issue 7).
    static func current(connectionMode: DeviceManager.ConnectionMode, tunnelMode: TunnelMode) -> ConnectionChoice {
        switch tunnelMode {
        case .daemon: return .daemon
        case .auto: return .auto
        case .usb: return connectionMode == .random ? .random : .usb
        case .wifi: return connectionMode == .random ? .random : .wifi
        }
    }

    var title: String {
        switch self {
        case .usb: return "USB"
        case .wifi: return "Wi\u{2011}Fi"
        case .auto: return "Auto"
        case .random: return "Random"
        case .daemon: return "Background daemon"
        }
    }

    var shortTitle: String { self == .daemon ? "Daemon" : title }

    /// Background daemon only sets the tunnel mode: a running USB or Wi-Fi tunnel keeps
    /// running and the daemon is used from the next Start (review issue 6). Nil for every
    /// other case.
    func nextStartNote(tunnelRunning: Bool, activeMode: TunnelMode?) -> String? {
        guard self == .daemon, tunnelRunning, activeMode != .daemon else { return nil }
        let running: String
        switch activeMode {
        case .usb: running = "The USB tunnel"
        case .wifi: running = "The Wi\u{2011}Fi tunnel"
        case .auto: running = "The Auto tunnel"
        case .daemon, nil: running = "The running tunnel"
        }
        return "Background daemon applies at the next Start. \(running) keeps running until then."
    }

    /// The Other modes menu item: Background daemon says when it takes effect while
    /// another tunnel runs.
    func menuTitle(tunnelRunning: Bool, activeMode: TunnelMode?) -> String {
        nextStartNote(tunnelRunning: tunnelRunning, activeMode: activeMode) == nil
            ? title : "\(title) (from the next Start)"
    }

    /// What the picker says under the choice in use: what it does, and for Background
    /// daemon chosen while another tunnel runs, that it applies at the next Start.
    func detail(tunnelRunning: Bool, activeMode: TunnelMode?) -> String {
        guard let note = nextStartNote(tunnelRunning: tunnelRunning, activeMode: activeMode) else { return detail }
        return "\(detail) \(note)"
    }

    var systemImage: String {
        switch self {
        case .usb: return "cable.connector"
        case .wifi: return "wifi"
        case .auto: return "sparkles"
        case .random: return "shuffle"
        case .daemon: return "server.rack"
        }
    }

    var detail: String {
        switch self {
        case .usb: return "Over the cable. Unlock the iPhone and tap Trust once."
        case .wifi: return "Over this Mac's Wi\u{2011}Fi network. Prepare the iPhone for Wi\u{2011}Fi once, over the cable."
        case .auto: return "USB when the cable is connected, otherwise Wi\u{2011}Fi."
        case .random: return "USB or Wi\u{2011}Fi, picked at random when both are available."
        case .daemon: return "A background remote tunneld service finds the iPhone."
        }
    }

    /// The connection mode a transport choice sets; nil for Background daemon, which is a
    /// tunnel mode only.
    var connectionMode: DeviceManager.ConnectionMode? {
        switch self {
        case .usb: return .usb
        case .wifi: return .wifi
        case .auto: return .auto
        case .random: return .random
        case .daemon: return nil
        }
    }

    /// Resolves a click (`ConnectionChoiceAction`) and applies it at once unless it would
    /// end a held location. Returns the change to confirm first; nil when it was applied.
    @MainActor
    func select(
        deviceManager: DeviceManager,
        tunnel: TunneldManager,
        requiresLocationQuitDecision: Bool
    ) -> ConnectionChoiceChange? {
        let action = ConnectionChoiceAction.resolve(
            choice: self,
            connectionMode: deviceManager.connectionMode,
            tunnelMode: tunnel.preferredMode,
            tunnelRunning: tunnel.isRunning || tunnel.isStarting,
            requiresLocationQuitDecision: requiresLocationQuitDecision,
            usbAvailable: deviceManager.usbTransportAvailable,
            wifiAvailable: deviceManager.wifiTransportAvailable
        )
        switch action {
        case .none:
            return nil
        case .apply(let change):
            Self.apply(change, deviceManager: deviceManager, tunnel: tunnel)
            return nil
        case .confirm(let change):
            return change
        }
    }

    /// Applies a resolved change through the same calls the settings use: the connection
    /// mode (which also sets the tunnel mode, restarting a running tunnel when it changes),
    /// or the tunnel's Background daemon mode. Nothing is reapplied after a restart; the
    /// user presses Reapply location.
    @MainActor
    static func apply(_ change: ConnectionChoiceChange, deviceManager: DeviceManager, tunnel: TunneldManager) {
        if let mode = change.choice.connectionMode {
            deviceManager.setConnectionMode(mode, tunnelMode: change.tunnelMode)
        } else {
            tunnel.preferredMode = .daemon
        }
    }
}

/// A connection choice ready to apply: the tunnel mode it sets (Random's pick is made
/// once, before any dialog, so the dialog says what will happen) and whether that
/// restarts the running tunnel.
struct ConnectionChoiceChange: Equatable {
    let choice: ConnectionChoice
    let tunnelMode: TunnelMode
    let restartsTunnel: Bool

    var confirmationTitle: String { "Switch to \(choice.title)?" }

    var confirmationMessage: String {
        let ending = "restarts the tunnel and ends the location held on the iPhone."
        if choice == .random {
            let pick = tunnelMode == .usb ? ConnectionChoice.usb.title : ConnectionChoice.wifi.title
            return "Switching to Random picks \(pick), which \(ending)"
        }
        return "Switching to \(choice.title) \(ending)"
    }
}

/// What a click on a connection choice does, decided when it is pressed (like
/// `TunnelPillAction`). A restart of the running tunnel ends the held location and
/// latches reconnect (AppState treats it as a Stop), so it asks first, as the tunnel
/// pill's Stop does (review 2026-11-04 round 2 issue 4).
enum ConnectionChoiceAction: Equatable {
    /// The choice in use: nothing changes (re-clicking Random used to re-roll the
    /// transport and restart the tunnel half the time, review issue 5).
    case none
    case apply(ConnectionChoiceChange)
    case confirm(ConnectionChoiceChange)

    static func resolve(
        choice: ConnectionChoice,
        connectionMode: DeviceManager.ConnectionMode,
        tunnelMode: TunnelMode,
        tunnelRunning: Bool,
        requiresLocationQuitDecision: Bool,
        usbAvailable: Bool,
        wifiAvailable: Bool,
        randomPicksUSB: () -> Bool = { Bool.random() }
    ) -> ConnectionChoiceAction {
        // In use only when the setting agrees too: clicking the shown choice while the
        // setting disagrees (the Settings window set the tunnel mode) aligns the setting.
        guard choice != ConnectionChoice.current(connectionMode: connectionMode, tunnelMode: tunnelMode)
                || !(choice.connectionMode.map { $0 == connectionMode } ?? true) else {
            return .none
        }
        let change: ConnectionChoiceChange
        if let mode = choice.connectionMode {
            let next = DeviceManager.tunnelMode(
                for: mode, usbAvailable: usbAvailable, wifiAvailable: wifiAvailable, randomPicksUSB: randomPicksUSB)
            change = ConnectionChoiceChange(
                choice: choice,
                tunnelMode: next,
                restartsTunnel: DeviceManager.switchRestartsTunnel(from: tunnelMode, to: next, tunnelRunning: tunnelRunning)
            )
        } else {
            // Background daemon only sets the tunnel mode; a running tunnel keeps running.
            change = ConnectionChoiceChange(choice: choice, tunnelMode: .daemon, restartsTunnel: false)
        }
        return change.restartsTunnel && requiresLocationQuitDecision ? .confirm(change) : .apply(change)
    }
}

/// The dialog a connection choice shows before a switch that ends the held location.
/// Switch applies the change; Cancel changes nothing.
struct ConnectionChoiceConfirmation: ViewModifier {
    @Binding var pending: ConnectionChoiceChange?
    let deviceManager: DeviceManager
    let tunnel: TunneldManager

    func body(content: Content) -> some View {
        content.confirmationDialog(
            pending?.confirmationTitle ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { change in
            Button("Switch", role: .destructive) {
                pending = nil
                ConnectionChoice.apply(change, deviceManager: deviceManager, tunnel: tunnel)
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { change in
            Text(change.confirmationMessage)
        }
    }
}

extension View {
    func connectionChoiceConfirmation(
        _ pending: Binding<ConnectionChoiceChange?>,
        deviceManager: DeviceManager,
        tunnel: TunneldManager
    ) -> some View {
        modifier(ConnectionChoiceConfirmation(pending: pending, deviceManager: deviceManager, tunnel: tunnel))
    }
}

enum RailPanel: String {
    case favorites
    case places
    case recent
}

/// The window's title bar: the phone and its connection choice, the tunnel pill, and the
/// appearance and Settings buttons.
///
/// It observes the device, tunnel and reconnect state it shows, never `AppState` itself:
/// AppState re-sends every change of a running route (about two renders per acknowledged
/// point), none of which the title bar shows. AppState is read when a button is pressed.
struct OrganicTitleBar: View {
    let appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager
    @ObservedObject private var device: DeviceStateManager
    @ObservedObject private var deviceManager: DeviceManager
    @ObservedObject private var reconnector: TunnelAutoReconnector
    @Binding var showDeviceMenu: Bool
    @State private var confirmTunnelStop = false
    @State private var pendingConnectionChange: ConnectionChoiceChange?
    @Binding var showSettings: Bool
    @Binding var appearanceRaw: String
    let onRefresh: () -> Void
    /// The values the parent rendered with. `==` compares these, never the bindings: the
    /// parent's bindings read the same storage on both sides, so they always compared
    /// equal (review 2026-11-04 round 2 issue 9). The body draws from them too.
    private let deviceMenuShown: Bool
    private let settingsShown: Bool
    private let appearanceValue: String

    init(
        appState: AppState,
        showDeviceMenu: Binding<Bool>,
        showSettings: Binding<Bool>,
        appearanceRaw: Binding<String>,
        onRefresh: @escaping () -> Void
    ) {
        self.appState = appState
        _device = ObservedObject(wrappedValue: appState.device)
        _deviceManager = ObservedObject(wrappedValue: appState.deviceManager)
        _reconnector = ObservedObject(wrappedValue: appState.tunnelAutoReconnector)
        _showDeviceMenu = showDeviceMenu
        _showSettings = showSettings
        _appearanceRaw = appearanceRaw
        self.onRefresh = onRefresh
        deviceMenuShown = showDeviceMenu.wrappedValue
        settingsShown = showSettings.wrappedValue
        appearanceValue = appearanceRaw.wrappedValue
    }

    var body: some View {
#if DEBUG
        let _ = GUIRenderCounts.titleBar += 1
#endif
        HStack(spacing: 12) {
            Spacer(minLength: 0)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                deviceCluster
                tunnelButton
            }
            // The centre group keeps its own width; the flexible sides give way.
            .fixedSize()
            .layoutPriority(1)

            HStack(spacing: 8) {
                chromeCircleButton(
                    glyph: appearance == .dark ? .sun : .moon,
                    selected: false,
                    help: appearance == .dark ? "Switch to light" : "Switch to dark"
                ) {
                    appearanceRaw = appearance == .dark
                        ? OrganicAppearance.light.rawValue
                        : OrganicAppearance.dark.rawValue
                }
                chromeCircleButton(glyph: .settings, selected: settingsShown, help: "Settings") {
                    showSettings.toggle()
                }
                .accessibilityIdentifier("chrome.settings")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 40)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(Organic.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Organic.neutral400).frame(height: 1)
        }
    }

    private func chromeCircleButton(
        glyph: OrganicGlyph,
        selected: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            OrganicGlyphView(glyph: glyph, size: 15)
                .foregroundStyle(selected ? Organic.accent700 : Organic.neutral700)
                .frame(width: 32, height: 32)
                .background(selected ? Organic.accent100 : Organic.neutral100)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(selected ? Organic.accent400 : Organic.neutral400, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var appearance: OrganicAppearance {
        OrganicAppearance.persisted(appearanceValue)
    }

    private var hasSelectedDevice: Bool {
        appState.selectedDevice != nil
    }

    /// The phone and how PathChanger connects to it: one capsule holding the device button
    /// (name, then a dot and the live reachability) and the USB / Wi‑Fi choice.
    private var deviceCluster: some View {
        HStack(spacing: 10) {
            Button { showDeviceMenu.toggle() } label: {
                HStack(spacing: 9) {
                    OrganicGlyphView(glyph: .phone, size: 15)
                        .foregroundStyle(hasSelectedDevice ? Organic.sage700 : Organic.neutral500)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(appState.selectedDevice?.chromeTitle ?? "No device")
                            .font(Organic.body(12, weight: .bold))
                            .foregroundStyle(Organic.text)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(OrganicDeviceChromeText.tone(selectedReachability, hasDevice: hasSelectedDevice))
                                .frame(width: 6, height: 6)
                            Text(deviceSubtitle)
                                .font(Organic.body(10.5))
                                .foregroundStyle(Organic.neutral600)
                        }
                    }
                    .lineLimit(1)
                    .fixedSize()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Organic.neutral500)
                        .rotationEffect(.degrees(deviceMenuShown ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Choose the iPhone")
            .accessibilityLabel("iPhone")
            .accessibilityValue(appState.selectedDevice.map { "\($0.chromeTitle), \(deviceSubtitle)" } ?? "No device")
            .accessibilityHint("Shows the iPhones PathChanger can see")
            .popover(isPresented: $showDeviceMenu, arrowEdge: .bottom) {
                OrganicDevicePopover(isPresented: $showDeviceMenu, connectionMode: connectionMode, onRefresh: onRefresh)
                    .environmentObject(appState)
                    .environmentObject(tunneldManager)
            }

            Rectangle().fill(Organic.neutral300).frame(width: 1, height: 20)

            // USB and Wi‑Fi up front; a secondary mode in use shows as a third segment.
            // Never disabled without a phone: the choice decides where to look for one.
            OrganicSegmented(
                options: transportOptions,
                selection: connectionChoice,
                height: 28,
                title: { $0.shortTitle },
                icon: { $0.systemImage },
                onSelect: { choose($0) }
            )
            .fixedSize()
            .help(connectionChoice.detail(tunnelRunning: tunneldManager.isRunning, activeMode: tunneldManager.activeMode))
            .connectionChoiceConfirmation($pendingConnectionChange, deviceManager: deviceManager, tunnel: tunneldManager)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Connect over")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 36)
        .background(Capsule().fill(Organic.neutral100))
        .overlay(Capsule().strokeBorder(Organic.neutral400, lineWidth: 1))
    }

    private var connectionChoice: ConnectionChoice {
        ConnectionChoice.current(connectionMode: deviceManager.connectionMode, tunnelMode: tunneldManager.preferredMode)
    }

    /// Whether a location is held is read when the choice is pressed, as for the pill.
    private func choose(_ choice: ConnectionChoice) {
        pendingConnectionChange = choice.select(
            deviceManager: deviceManager,
            tunnel: tunneldManager,
            requiresLocationQuitDecision: appState.requiresLocationQuitDecision
        )
    }

    private var transportOptions: [ConnectionChoice] {
        ConnectionChoice.primary.contains(connectionChoice)
            ? ConnectionChoice.primary
            : ConnectionChoice.primary + [connectionChoice]
    }

    private var selectedReachability: DeviceReachability {
        appState.selectedDevice.map(reachability(of:)) ?? .notReachable
    }

    private var tunnelButton: some View {
        Button {
            switch TunnelPillAction.resolve(
                isRunning: tunneldManager.isRunning,
                requiresLocationQuitDecision: appState.requiresLocationQuitDecision,
                isWaitingForDevice: tunneldManager.isWaitingForDevice,
                isStarting: tunneldManager.isStarting,
                isAutoReconnecting: appState.isTunnelAutoReconnecting,
                isError: isTunnelError
            ) {
            case .confirmStop:
                confirmTunnelStop = true
            case .stop:
                // A live tunnel, or a wait that can run for minutes: clicking cancels it.
                tunneldManager.stopTunnel()
            case .stopReconnecting:
                appState.stopTunnelReconnect()
            case .reconnect:
                Task { await appState.reconnectTunnel() }
            case .start:
                Task { await appState.startSelectedTunnel() }
            case .none:
                break
            }
        } label: {
            TunnelPillFace(model: tunnelPillModel)
        }
        .buttonStyle(.plain)
        .disabled(!isTunnelPillEnabled)
        .accessibilityLabel(tunnelPillModel.accessibilityLabel)
        .accessibilityValue(tunnelPillModel.accessibilityValue)
        .accessibilityIdentifier("tunnel.pill")
        .help(appState.isTunnelAutoReconnecting && !tunneldManager.isRunning
              ? "PathChanger keeps trying to reconnect. Click to stop reconnecting."
              : connectionHelp)
        .confirmationDialog(
            "Stop the tunnel?",
            isPresented: $confirmTunnelStop
        ) {
            Button("Stop Tunnel", role: .destructive) { tunneldManager.stopTunnel() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The simulated location is held over this tunnel. Stopping it ends the location on the device.")
        }
    }

    private func chromeIconButton(system: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Organic.neutral700)
                .frame(width: 28, height: 28)
                .background(Organic.neutral100)
                .clipShape(Circle())
                .overlay(Circle().stroke(Organic.neutral400, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private var deviceSubtitle: String {
        OrganicDeviceChromeText.subtitle(
            device: appState.selectedDevice,
            reachability: appState.selectedDevice.map(reachability(of:)) ?? .notReachable,
            mode: connectionMode
        )
    }

    /// The user's connection-mode choice; selects which advice an unreachable phone gets
    /// (cable for USB, Wi-Fi otherwise). Never used as evidence of reachability.
    private var connectionMode: DeviceManager.ConnectionMode {
        deviceManager.connectionMode
    }

    /// Live reachability from usbmux, Bonjour and the tunnel manager, never from the
    /// connection-mode setting (live 2026-11-01: "trusted · Wi-Fi" while usbmux had no phone).
    private func reachability(of device: Device) -> DeviceReachability {
        appState.device.reachability(of: device, tunnelRunning: tunneldManager.isRunning)
    }

    private var isTunnelError: Bool {
        if case .error = tunneldManager.state { return true }
        return false
    }

    private var isTunnelPillEnabled: Bool {
        TunnelPillAction.isEnabled(
            hasSelectedDevice: hasSelectedDevice,
            isWaitingForDevice: tunneldManager.isWaitingForDevice,
            isAutoReconnecting: appState.isTunnelAutoReconnecting
        )
    }

    private var tunnelPillModel: TunnelPillModel {
        TunnelPillModel.resolve(
            isRunning: tunneldManager.isRunning,
            isWaitingForDevice: tunneldManager.isWaitingForDevice,
            isStarting: tunneldManager.isStarting,
            isError: isTunnelError,
            isAutoReconnecting: appState.isTunnelAutoReconnecting,
            hasSelectedDevice: hasSelectedDevice
        )
    }

    private var directTransportReady: Bool {
        appState.device.selectedDirectTransportAvailable
    }

    private var connectionHelp: String {
        if !hasSelectedDevice { return "Connect a device to enable RemoteXPC tunnel" }
        if tunneldManager.isRunning { return "Stop RemoteXPC tunnel" }
        if tunneldManager.isWaitingForDevice {
            return "Waiting for the iPhone to appear on Wi‑Fi. Unlock it and keep it on this network. Click to cancel."
        }
        if case .error = tunneldManager.state {
            if let error = tunneldManager.lastError { return "\(error)\nClick to try again." }
            return "Retry RemoteXPC tunnel start"
        }
        if let device = appState.selectedDevice,
           let hint = OrganicDeviceChromeText.unreachableTunnelHelp(
               reachability: reachability(of: device),
               tunnelRunning: tunneldManager.isRunning,
               mode: connectionMode
           ) {
            return hint
        }
        if directTransportReady {
            return appState.selectedDevice?.isWireless == true
                ? "Direct Wi-Fi connection ready. Click to start RemoteXPC tunnel."
                : "Direct USB connection ready. Click to start RemoteXPC tunnel."
        }
        return "Start RemoteXPC tunnel"
    }
}

/// The window re-renders on every AppState change; the title bar's own observed objects
/// re-render it when what it shows changes, so a new parent render with the same values
/// (and new, equivalent bindings and refresh closure) is the same title bar.
extension OrganicTitleBar: Equatable {
    nonisolated static func == (lhs: OrganicTitleBar, rhs: OrganicTitleBar) -> Bool {
        MainActor.assumeIsolated {
            lhs.appState === rhs.appState
                && lhs.deviceMenuShown == rhs.deviceMenuShown
                && lhs.settingsShown == rhs.settingsShown
                && lhs.appearanceValue == rhs.appearanceValue
        }
    }
}

/// The device picker the device button opens: how to connect (USB or Wi‑Fi up front, the
/// other modes in a menu), one row per phone, and Prepare for Wi‑Fi.
struct OrganicDevicePopover: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager
    @Binding var isPresented: Bool
    let connectionMode: DeviceManager.ConnectionMode
    var onRefresh: () -> Void = {}
    @State private var pendingConnectionChange: ConnectionChoiceChange?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            connectSection
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            divider
            deviceList
                .padding(6)
            divider
            Button {
                Task { await appState.prepareSelectedDeviceForWiFi() }
            } label: {
                Label("Prepare for Wi\u{2011}Fi…", systemImage: "wifi")
                    .font(Organic.body(12, weight: .bold))
                    .foregroundStyle(Organic.accent700)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("With the iPhone on the cable and unlocked: pairs it for Wi\u{2011}Fi connections")
        }
        .frame(width: 320)
        .background(Organic.neutral100)
    }

    private var divider: some View {
        Rectangle().fill(Organic.neutral300).frame(height: 1)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("iPhones")
                .font(Organic.body(13, weight: .bold))
                .foregroundStyle(Organic.text)
                .accessibilityAddTraits(.isHeader)
            Text(countText)
                .font(Organic.body(11))
                .foregroundStyle(Organic.neutral600)
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Organic.neutral700)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Look for iPhones again")
            .accessibilityLabel("Look for iPhones again")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var countText: String {
        let count = appState.availableDevices.count
        return count == 1 ? "1 found" : "\(count) found"
    }

    private var choice: ConnectionChoice {
        ConnectionChoice.current(connectionMode: connectionMode, tunnelMode: tunneldManager.preferredMode)
    }

    private var choiceDetail: String {
        let detail = choice.detail(tunnelRunning: tunneldManager.isRunning, activeMode: tunneldManager.activeMode)
        return ConnectionChoice.primary.contains(choice) ? detail : "Using \(choice.title): \(detail)"
    }

    private func choose(_ option: ConnectionChoice) {
        pendingConnectionChange = option.select(
            deviceManager: appState.deviceManager,
            tunnel: tunneldManager,
            requiresLocationQuitDecision: appState.requiresLocationQuitDecision
        )
    }

    private var connectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OrganicGroupHeader(title: "Connect over") {
                Menu {
                    ForEach(ConnectionChoice.secondary) { option in
                        Button {
                            choose(option)
                        } label: {
                            let title = option.menuTitle(
                                tunnelRunning: tunneldManager.isRunning, activeMode: tunneldManager.activeMode)
                            if option == choice {
                                Label(title, systemImage: "checkmark")
                            } else {
                                Text(title)
                            }
                        }
                    }
                } label: {
                    Text("Other modes")
                        .font(Organic.body(11, weight: .semibold))
                        .foregroundStyle(Organic.accent700)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
                .fixedSize()
                .help("Auto, Random or Background daemon")
            }
            OrganicSegmented(
                options: ConnectionChoice.primary,
                selection: ConnectionChoice.primary.contains(choice) ? choice : nil,
                height: 34,
                fillsWidth: true,
                title: { $0.title },
                icon: { $0.systemImage },
                onSelect: { choose($0) }
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Connect over")
            .connectionChoiceConfirmation($pendingConnectionChange, deviceManager: appState.deviceManager, tunnel: tunneldManager)
            Text(choiceDetail)
                .font(Organic.body(11))
                .foregroundStyle(Organic.neutral600)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var deviceList: some View {
        VStack(spacing: 2) {
            if appState.availableDevices.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("No iPhone found yet")
                        .font(Organic.body(12, weight: .semibold))
                        .foregroundStyle(Organic.neutral800)
                    Text(connectionMode == .usb
                         ? "Connect it with a data cable, unlock it and tap Trust."
                         : "Unlock it and keep it on this Mac's Wi\u{2011}Fi, or connect the cable.")
                        .font(Organic.body(11))
                        .foregroundStyle(Organic.neutral600)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
            ForEach(appState.availableDevices) { device in
                deviceRow(device)
            }
        }
    }

    private func deviceRow(_ device: Device) -> some View {
        let selected = appState.selectedDevice?.id == device.id
        let reachable = reachability(of: device)
        return Button {
            appState.selectDevice(device)
            isPresented = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: device.isWireless ? "wifi" : "cable.connector")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Organic.neutral700)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Organic.neutral200))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.chromeTitle)
                        .font(Organic.body(12.5, weight: .semibold))
                        .foregroundStyle(Organic.text)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text("iOS \(device.iosVersion)")
                            .foregroundStyle(Organic.neutral600)
                        Circle()
                            .fill(OrganicDeviceChromeText.tone(reachable, hasDevice: true))
                            .frame(width: 6, height: 6)
                        Text(OrganicDeviceChromeText.reachabilityWord(reachability(of: device), mode: connectionMode))
                            .foregroundStyle(Organic.neutral700)
                            .lineLimit(1)
                    }
                    .font(Organic.body(10.5))
                }
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Organic.accent700)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: Organic.radiusSM, style: .continuous)
                    .fill(selected ? Organic.accent100 : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Live reachability from usbmux, Bonjour and the tunnel manager, never from the
    /// connection-mode setting.
    private func reachability(of device: Device) -> DeviceReachability {
        appState.device.reachability(of: device, tunnelRunning: tunneldManager.isRunning)
    }
}

/// The tunnel pill's face: where the tunnel stands, then (after a hairline) what a click
/// does. A stopped tunnel is one filled "Start tunnel" button, the title bar's only filled
/// call to action. Drawn from `TunnelPillModel` alone, so every phase renders in the GUI
/// snapshots without a running tunnel.
struct TunnelPillFace: View {
    let model: TunnelPillModel

    var body: some View {
        HStack(spacing: 8) {
            if model.isPrimary {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(model.actionText ?? model.statusText)
                    .font(Organic.body(12, weight: .bold))
            } else {
                indicator
                Text(model.statusText)
                    .font(Organic.body(12, weight: .semibold))
                    .foregroundStyle(statusInk)
                if let action = model.actionText {
                    Rectangle()
                        .fill(stroke)
                        .frame(width: 1, height: 16)
                    Text(action)
                        .font(Organic.body(12, weight: .bold))
                        .foregroundStyle(actionInk)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(model.isPrimary ? primaryInk : statusInk)
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
        .contentShape(Capsule())
    }

    @ViewBuilder
    private var indicator: some View {
        if model.showsProgress {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
                .frame(width: 12, height: 12)
        } else {
            Circle().fill(dot).frame(width: 7, height: 7)
        }
    }

    private var primaryInk: Color { model.isEnabled ? Organic.accentInk : Organic.neutral600 }

    private var dot: Color {
        switch model.phase {
        case .live: return Organic.sage600
        case .error: return Organic.danger
        case .waitingForDevice, .connecting, .reconnecting, .stopped: return Organic.neutral500
        }
    }

    private var statusInk: Color {
        switch model.phase {
        case .live: return Organic.sage800
        case .error: return Organic.accent800
        case .waitingForDevice, .connecting, .reconnecting, .stopped: return Organic.neutral800
        }
    }

    private var actionInk: Color {
        switch model.phase {
        case .live: return Organic.sage700
        case .error, .reconnecting, .waitingForDevice: return Organic.accent700
        case .connecting, .stopped: return Organic.neutral700
        }
    }

    private var fill: Color {
        if model.isPrimary { return model.isEnabled ? Organic.accent : Organic.neutral200 }
        switch model.phase {
        case .live: return Organic.sage100
        case .error, .reconnecting: return Organic.accent100
        case .waitingForDevice, .connecting, .stopped: return Organic.neutral100
        }
    }

    private var stroke: Color {
        if model.isPrimary { return model.isEnabled ? Organic.accent600 : Organic.neutral300 }
        switch model.phase {
        case .live: return Organic.sage300
        case .error, .reconnecting: return Organic.accent300
        case .waitingForDevice, .connecting, .stopped: return Organic.neutral400
        }
    }
}

struct OrganicRail: View {
    @ObservedObject var favorites = LocationFavoritesManager.shared
    @Binding var openPanel: RailPanel?
    var mode: AppMode = .teleport
    let onSelect: (LocationCoordinate, String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 4) {
                railButton(.favorites, icon: "star", label: "Favorites")
                railButton(.places, icon: "mappin.circle", label: "Places")
                railButton(.recent, icon: "clock", label: "Recent")
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .padding(.bottom, 10)
            .padding(.horizontal, 8)
            .frame(width: 76)
            .frame(maxHeight: .infinity)
            .background(Organic.surface)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Organic.neutral300).frame(width: 1)
            }

            if let panel = openPanel {
                flyout(for: panel)
                    .frame(width: 218, alignment: .top)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: 520, alignment: .top)
                    .padding(.leading, 84)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .offset(x: -6)))
            }
        }
        .frame(width: 76, alignment: .leading)
        .zIndex(40)
        .animation(.easeInOut(duration: 0.18), value: openPanel)
    }

    private func railButton(_ panel: RailPanel, icon: String, label: String) -> some View {
        let selected = openPanel == panel
        let ink: Color = (selected && panel == .recent) ? Organic.sage800 : (selected ? Organic.accent700 : Organic.neutral700)
        return Button {
            openPanel = selected ? nil : panel
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(Organic.body(10, weight: .bold))
            }
            .foregroundStyle(ink)
            .frame(width: 58)
            .padding(.top, 9)
            .padding(.bottom, 8)
            .background(selected ? Organic.accent100 : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous)
                    .stroke(selected ? Organic.accent400 : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private func flyout(for panel: RailPanel) -> some View {
        let items: [FavoriteLocation] = {
            switch panel {
            case .favorites: return favorites.favorites
            case .places: return favorites.places
            case .recent: return favorites.recents
            }
        }()
        let title: String = {
            switch panel {
            case .favorites: return "Favorites"
            case .places: return "Places"
            case .recent: return "Recent"
            }
        }()
        let hint = mode == .route ? "Tap to add a stop" : "Tap to set location"

        return VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(Organic.body(12, weight: .bold))
                    .lineLimit(1)
                Spacer()
                Button { openPanel = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Organic.neutral700)
                        .frame(width: 20, height: 20)
                        .background(Organic.neutral200)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 10)
            .padding(.top, 9)
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Organic.neutral300).frame(height: 1) }

            VStack(spacing: 1) {
                if items.isEmpty && panel == .favorites {
                    Text("No favorites yet. Star a place, or use the star on the map.")
                        .font(Organic.body(11))
                        .foregroundStyle(Organic.neutral600)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 16)
                } else if !items.isEmpty {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(items) { item in
                                HStack(spacing: 2) {
                                    Button {
                                        onSelect(item.coordinate, item.name)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(item.name)
                                                .font(Organic.body(11.5, weight: .semibold))
                                                .lineLimit(1)
                                            Text(item.coordinate.formattedShort)
                                                .font(Organic.mono(9.5))
                                                .foregroundStyle(Organic.neutral600)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 8)
                                        .padding(.vertical, 7)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        favorites.toggleFavorite(name: item.name, coordinate: item.coordinate)
                                    } label: {
                                        Image(systemName: favorites.isFavorite(item.coordinate) ? "star.fill" : "star")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(favorites.isFavorite(item.coordinate) ? Organic.accent600 : Organic.neutral500)
                                            .frame(width: 22, height: 22)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Favorite")
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 360)
                }
                Text(hint)
                    .font(Organic.body(9.5))
                    .foregroundStyle(Organic.neutral600)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 3)
            }
            .padding(5)
        }
        .background(Organic.neutral100)
        .clipShape(RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous)
                .stroke(Organic.neutral300, lineWidth: 1)
        )
        .shadow(color: Organic.shadow.opacity(0.16), radius: 16, y: 8)
    }
}

struct OrganicTelemetryBar: View {
    @EnvironmentObject var appState: AppState
    let mode: AppMode

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Circle()
                    .fill(appState.locationPresentation.isSpoofing ? Organic.sage600 : Organic.neutral500)
                    .frame(width: 8, height: 8)
                Text(appState.locationPresentation.applicationLabel)
                    .accessibilityIdentifier("location.status.application")
                    .font(Organic.body(12.5, weight: .bold))
                    .lineLimit(1)
                Text(appState.locationPresentation.appliedCoordinateLabel)
                    .accessibilityIdentifier("location.status.coordinate")
                    .font(Organic.mono(11.5))
                    .foregroundStyle(Organic.neutral700)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Organic.neutral200)
                    .overlay(Capsule().stroke(Organic.neutral300, lineWidth: 1))
                    .clipShape(Capsule())
                Text(mode.rawValue)
                    .font(Organic.body(11, weight: .bold))
                    .foregroundStyle(Organic.accent800)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Organic.accent200)
                    .clipShape(Capsule())
            }
            Spacer(minLength: 8)
            metric("ACCURACY", "5.0 m")
            metric("ALTITUDE", "12.4 m")
            metric("SPEED", speedText)
            Button {
                appState.pauseSimulation()
            } label: {
                Label("Pause", systemImage: "pause.fill")
                    .font(Organic.body(12, weight: .bold))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
            }
            .buttonStyle(.plain)
            .disabled(!appState.locationPresentation.isMovementActive)
            .accessibilityIdentifier("location.action.pauseMovement")

            Button {
                Task { await appState.stopSimulation() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Stop")
                        .font(Organic.body(12, weight: .bold))
                }
                .foregroundStyle(appState.locationPresentation.isMovementActive ? Organic.neutral100 : Organic.neutral700)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(appState.locationPresentation.isMovementActive ? Organic.accent600 : Organic.neutral200)
                .clipShape(Capsule())
            }
            .accessibilityIdentifier("location.action.stopMovement")
            .buttonStyle(.plain)
            .disabled(!appState.locationPresentation.isMovementActive)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Organic.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Organic.neutral300).frame(height: 1)
        }
    }

    private var speedText: String {
        // The speed of the movement under way: the travel speed the cards show, or
        // Joystick's own speed while the joystick moves (PRODUCT_REQUIREMENTS 3.5).
        // Previously this used the raw `simulationSpeed.metersPerSecond`, so the telemetry
        // bar showed 1.4 m/s while the other panels showed 1.6 m/s for the same Walking preset.
        String(format: "%.1f m/s", appState.shownMovementSpeedMetersPerSecond)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(Organic.body(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Organic.neutral600)
            Text(value)
                .font(Organic.mono(12, weight: .semibold))
        }
    }
}
