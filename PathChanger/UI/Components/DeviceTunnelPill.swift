//
//  DeviceTunnelPill.swift
//  PathChanger
//
//  Subordinate top-right pill showing device + tunnel status.
//  This component owns device selection and status visibility only.
//
// DeviceTunnelPill is the SOLE production Phase-1 readiness authority.
//

import SwiftUI

struct DeviceTunnelPill: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager
    @State private var isShowingPopover = false
    @State private var isHovered = false

    var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                avatar
                textStack
            }
            .padding(.horizontal, DS.Spacing.sm)
            .frame(width: DS.Metrics.devicePillWidth, height: DS.Metrics.devicePillHeight)
        }
        .buttonStyle(DevicePillButtonStyle(isHovered: isHovered))
        .onHover { hovering in
            withAnimation(DS.Animation.fast) {
                isHovered = hovering
            }
        }
        .popover(isPresented: $isShowingPopover, arrowEdge: .top) {
            DevicePopoverContent(isPresented: $isShowingPopover)
                .environmentObject(appState)
                .environmentObject(tunneldManager)
                .frame(width: DS.Metrics.popoverWidth)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("mapShellDevicePill")
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(AppActionGradient.avatar)
                .frame(width: DS.Metrics.deviceAvatarSize, height: DS.Metrics.deviceAvatarSize)
            Text(avatarInitials)
                .font(DS.Typography.labelPrimary)
                .foregroundStyle(DS.Color.foregroundPrimary)
        }
    }

    private var avatarInitials: String {
        guard let device = appState.selectedDevice else {
            return "—"
        }
        let trimmed = device.displayName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return "iP"
        }
        return String(trimmed.uppercased().prefix(2))
    }

    private var textStack: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(deviceName)
                .font(DS.Typography.labelPrimary)
                .foregroundStyle(DS.Color.foregroundPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: DS.Spacing.xs) {
                Circle()
                    .fill(statusColor)
                    .frame(width: DS.Metrics.statusDotSize, height: DS.Metrics.statusDotSize)
                Text(statusText)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.foregroundSecondary)
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
            return DS.Color.warning
        }
        if tunneldManager.isRunning {
            return DS.Color.success
        }
        return appState.selectedDevice == nil ? DS.Color.inactive : DS.Color.destructive
    }

    private var statusText: String {
        guard let device = appState.selectedDevice else {
            return "Select an iPhone"
        }
        if tunneldManager.isStarting {
            return "Tunnel starting…"
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

private struct DevicePillButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        return configuration.label
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous)
                    .fill(backgroundColor(isPressed: isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous)
                    .stroke(DS.Color.foregroundTertiary.opacity(DS.Opacity.outline), lineWidth: DS.Metrics.strokeWidth)
            )
            .shadow(
                color: .black.opacity(DS.Opacity.idleRow),
                radius: DS.Metrics.subordinatePillShadowRadius,
                x: DS.Metrics.zero,
                y: DS.Metrics.subordinatePillShadowYOffset
            )
            .scaleEffect(scaleValue(isPressed: isPressed))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous))
            .animation(DS.Animation.fast, value: configuration.isPressed)
            .animation(DS.Animation.fast, value: isHovered)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return DS.Color.backgroundSecondary
        }
        if isHovered {
            return DS.Color.backgroundElevated
        }
        return DS.Color.backgroundElevated.opacity(DS.Opacity.panel)
    }

    private func scaleValue(isPressed: Bool) -> CGFloat {
        if isPressed {
            return DS.Metrics.subordinatePillPressedScale
        }
        if isHovered {
            return DS.Metrics.subordinatePillHoverScale
        }
        return DS.Metrics.unitScale
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

private struct DevicePopoverContent: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text("Devices")
                    .font(DS.Typography.labelPrimary)
                    .foregroundStyle(DS.Color.foregroundPrimary)
                Spacer()
                Button {
                    Task { await appState.refreshDevices() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(DS.Typography.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Color.foregroundSecondary)
                .accessibilityLabel("Refresh device list")
            }

            Divider()

            if appState.availableDevices.isEmpty {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "iphone.slash")
                        .foregroundStyle(DS.Color.inactive)
                    Text("No iPhone connected")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.foregroundSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Spacing.xs)
            } else {
                VStack(spacing: DS.Spacing.xxs) {
                    ForEach(appState.availableDevices) { device in
                        Button {
                            appState.selectDevice(device)
                            isPresented = false
                        } label: {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: "iphone")
                                    .foregroundStyle(DS.Color.foregroundSecondary)
                                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                                    Text(device.displayName)
                                        .font(DS.Typography.labelPrimary)
                                        .foregroundStyle(DS.Color.foregroundPrimary)
                                    Text("iOS \(device.iosVersion) · \(device.connectionType.rawValue)")
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Color.foregroundSecondary)
                                }
                                Spacer()
                                if appState.selectedDevice?.id == device.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(DS.Color.accent)
                                }
                            }
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, DS.Spacing.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                    .fill(appState.selectedDevice?.id == device.id
                                          ? DS.Color.accent.opacity(DS.Opacity.selectionTint)
                                          : Color.clear)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select \(device.displayName)")
                    }
                }
            }

            Divider()

            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: transportPresentation.icon)
                    .foregroundStyle(tunnelPresentationColor)
                Text(tunneldManager.isRunning ? transportPresentation.title : "Tunnel offline · \(transportPresentation.title)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.foregroundSecondary)
                Spacer()
            }
        }
        .padding(DS.Spacing.sm)
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

    private var tunnelPresentationColor: Color {
        if tunneldManager.isStarting {
            return DS.Color.warning
        }
        if tunneldManager.isRunning {
            return DS.Color.success
        }
        return DS.Color.destructive
    }
}

#if DEBUG
struct DeviceTunnelPill_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            DS.Color.backgroundSecondary
            DeviceTunnelPill()
                .environmentObject(AppState())
                .environmentObject(TunneldManager.shared)
        }
        .frame(
            width: DS.Metrics.devicePillWidth + DS.Spacing.xl,
            height: DS.Metrics.devicePillHeight + DS.Spacing.xxl
        )
    }
}
#endif