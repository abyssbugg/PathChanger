//
//  DeviceTunnelPill.swift
//  PathChanger
//
//  Top-right 280×56 floating glass pill that shows the active device avatar,
//  device name, and tunnel status. Tapping it opens a popover that lets the
//  user switch devices or refresh the device list.
//
//  Tunnel-truth comes directly from `TunneldManager.shared.isRunning` (and its
//  `isStarting` flag) — NOT through AppState's debounced mirror. This matches
//  the bug-fix discipline established in the WiFi-mode work and avoids the
//  pre-existing flicker/clobber issues.
//
// MARK: - W1 Authority Declaration (Slice S0 — documentation only)
//
// DeviceTunnelPill is the SOLE production Phase-1 readiness authority.
//
// Authority rules (frozen — see W1 governance plan):
//   - This pill owns device selection (Phase-1 device readiness) and the
//     proactive tunnel-readiness controls inside its own popover. Its
//     popover "Start Tunnel" button is the canonical Phase-1 transport-
//     start surface and routes through `TunneldManager.shared.autoStart()`.
//   - This pill is NOT a T0 execution authority. PrimaryActionPill is the
//     sole T0 surface; DeviceTunnelPill never initiates simulation
//     execution.
//   - All other UI surfaces that depict tunnel state outside this pill
//     (SettingsView admin card, DiagnosticsView, status banners,
//     CollapsibleSidebar status detail) are inspector-only or read-only.
//     They may surface tunnel state but MUST NOT define Phase-1 readiness
//     semantics or compete with this pill for device-selection authority.
//
// W1 Slice S0 is documentation-only. No behavior, layout, state, bindings,
// or routing are altered by this declaration.
//

import SwiftUI
import Combine

struct DeviceTunnelPill: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager
    @State private var isShowingPopover = false

    var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            HStack(spacing: 12) {
                avatar
                textStack
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .frame(width: 280, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.pcSurfaceTintDynamic)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.pcOutlineDynamic, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingPopover, arrowEdge: .top) {
            DevicePopoverContent(
                isPresented: $isShowingPopover
            )
            .environmentObject(appState)
            .environmentObject(tunneldManager)
            .frame(width: 320)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("mapShellDevicePill")
    }

    // MARK: - Avatar

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(AppActionGradient.avatar)
                .frame(width: 32, height: 32)
            Text(avatarInitials)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
        }
    }

    private var avatarInitials: String {
        guard let device = appState.selectedDevice else { return "—" }
        let trimmed = device.displayName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "iP" }
        return String(trimmed.uppercased().prefix(2))
    }

    // MARK: - Text stack

    private var textStack: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(deviceName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.pcTextDynamic)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.pcTextMutedDynamic)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deviceName: String {
        appState.selectedDevice?.displayName ?? "Select an iPhone"
    }

    private var statusColor: Color {
        if tunneldManager.isStarting {
            return .orange
        }
        return tunneldManager.isRunning ? .green : .red
    }

    private var statusText: String {
        guard let device = appState.selectedDevice else {
            return "Select an iPhone"
        }
        if tunneldManager.isStarting {
            return "Tunnel starting…"
        }
        if tunneldManager.isRunning {
            return "\(transportPresentation.title) · iOS \(device.iosVersion)"
        }
        return "\(transportPresentation.title) · iOS \(device.iosVersion)"
    }

    private var accessibilityLabel: String {
        "\(deviceName), \(statusText). Tap to switch devices."
    }

    private var transportPresentation: ActiveTransportPresentation {
        ActiveTransportPresentation.resolve(
            isTunnelRunning: tunneldManager.isRunning,
            activeTunnelMode: tunneldManager.presentationActiveMode,
            tunnelInfoMode: tunneldManager.tunnelInfo?.mode,
            preferredMode: tunneldManager.preferredMode,
            selectedConnectionType: appState.selectedDevice?.connectionType,
            isUSBConnected: appState.isUSBConnected,
            isWiFiAvailable: appState.isWiFiAvailable,
            preferUSBConnection: appState.preferUSBConnection
        )
    }
}

struct ActiveTransportPresentation: Equatable {
    let title: String
    let icon: String
    let isActive: Bool

    static func resolve(
        isTunnelRunning: Bool,
        activeTunnelMode: TunnelMode?,
        tunnelInfoMode: TunnelMode? = nil,
        preferredMode: TunnelMode = .auto,
        selectedConnectionType: ConnectionType?,
        isUSBConnected: Bool,
        isWiFiAvailable: Bool,
        preferUSBConnection: Bool
    ) -> ActiveTransportPresentation {
        if isTunnelRunning {
            let resolvedMode = presentationMode(
                activeTunnelMode: activeTunnelMode,
                tunnelInfoMode: tunnelInfoMode,
                preferredMode: preferredMode
            )
            // Presentation-only guard: if USB is not physically connected,
            // the running tunnel cannot be cable-backed. A stale `.usb`
            // active mode would otherwise mis-report "USB Active" during an
            // actual Wi-Fi session (e.g. after the cable was unplugged and
            // recovery converged on Wi-Fi). Collapse to the wireless
            // presentation. Runtime ownership is not modified.
            if resolvedMode == .usb && !isUSBConnected {
                return ActiveTransportPresentation(title: "Wi-Fi Active", icon: "wifi", isActive: true)
            }
            switch resolvedMode {
            case .usb:
                return ActiveTransportPresentation(title: "USB Active", icon: "cable.connector", isActive: true)
            case .wifi, .daemon:
                return ActiveTransportPresentation(title: "Wi-Fi Active", icon: "wifi", isActive: true)
            case .auto, .none:
                return ActiveTransportPresentation(title: "Tunnel Active", icon: "point.3.connected.trianglepath.dotted", isActive: true)
            }
        }

        if selectedConnectionType == .usb {
            return ActiveTransportPresentation(title: "USB Selected", icon: "cable.connector", isActive: false)
        }
        if selectedConnectionType == .wifi {
            return ActiveTransportPresentation(title: "Wi-Fi Selected", icon: "wifi", isActive: false)
        }
        if preferUSBConnection && isUSBConnected {
            return ActiveTransportPresentation(title: "USB Preferred", icon: "cable.connector", isActive: false)
        }
        if isUSBConnected {
            return ActiveTransportPresentation(title: "USB Available", icon: "cable.connector", isActive: false)
        }
        if isWiFiAvailable {
            return ActiveTransportPresentation(title: "Wi-Fi Available", icon: "wifi", isActive: false)
        }
        return ActiveTransportPresentation(title: "No Connection", icon: "iphone.slash", isActive: false)
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
}

// MARK: - Popover content

private struct DevicePopoverContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Devices")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.pcTextDynamic)
                Spacer()
                Button {
                    Task { await appState.refreshDevices() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.pcTextMutedDynamic)
                .accessibilityLabel("Refresh device list")
            }

            Divider()

            if appState.availableDevices.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "iphone.slash")
                        .foregroundStyle(Color.pcTextMutedDynamic)
                    Text("No iPhone connected")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.pcTextMutedDynamic)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(appState.availableDevices) { device in
                        Button {
                            appState.selectDevice(device)
                            isPresented = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "iphone")
                                    .foregroundStyle(Color.pcTextMutedDynamic)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.displayName)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.pcTextDynamic)
                                    Text("iOS \(device.iosVersion) · \(device.connectionType.rawValue)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.pcTextMutedDynamic)
                                }
                                Spacer()
                                if appState.selectedDevice?.id == device.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.pcSystemBlue)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(appState.selectedDevice?.id == device.id
                                          ? Color.pcSystemBlue.opacity(0.10)
                                          : Color.clear)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select \(device.displayName)")
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: transportPresentation.icon)
                    .foregroundStyle(tunneldManager.isRunning ? Color.green : Color.orange)
                Text(tunneldManager.isRunning ? transportPresentation.title : "Tunnel offline · \(transportPresentation.title)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.pcTextMutedDynamic)
                Spacer()
                if !tunneldManager.isRunning && !tunneldManager.isStarting {
                    Button {
                        Task { await tunneldManager.autoStart() }
                    } label: {
                        Text("Start Tunnel")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(AppCapsuleButtonStyle(accent: .pcSystemBlue, isProminent: true))
                    .controlSize(.small)
                    .accessibilityLabel("Start tunnel")
                }
            }
        }
        .padding(14)
    }

    private var transportPresentation: ActiveTransportPresentation {
        ActiveTransportPresentation.resolve(
            isTunnelRunning: tunneldManager.isRunning,
            activeTunnelMode: tunneldManager.presentationActiveMode,
            tunnelInfoMode: tunneldManager.tunnelInfo?.mode,
            preferredMode: tunneldManager.preferredMode,
            selectedConnectionType: appState.selectedDevice?.connectionType,
            isUSBConnected: appState.isUSBConnected,
            isWiFiAvailable: appState.isWiFiAvailable,
            preferUSBConnection: appState.preferUSBConnection
        )
    }
}

#if DEBUG
struct DeviceTunnelPill_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.opacity(0.12)
            DeviceTunnelPill()
                .environmentObject(AppState())
                .environmentObject(TunneldManager.shared)
        }
        .frame(width: 360, height: 120)
    }
}
#endif
