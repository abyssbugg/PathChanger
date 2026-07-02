//
//  ConnectionPill.swift
//  PathChanger
//
//  Top-bar connection-state indicator — the SwiftUI port of the mockup's
//  4-state `.conn-pill` (geospoofer-pro.html).
//
//  States mirror DeviceTunnelPill + ActiveTransportPresentation exactly:
//    Disconnected (gray, no pulse) → Connecting (amber, fast pulse) →
//    USB Active (emerald, slow pulse, "tunnel · lockdown") →
//    Wi-Fi Active (emerald, slow pulse, "tunnel · daemon").
//
//  The state mapping lives in a pure, side-effect-free resolver
//  (`ConnectionPillState.resolve`) so it is unit-testable without SwiftUI.
//  This component is presentation-only; the transport layer is untouched.
//  DeviceTunnelPill remains the production readiness authority.
//

import SwiftUI

/// The four visual states of the connection indicator, mirroring the mockup's
/// `.conn-pill[data-state]` values. Pure value type + pure resolver so the
/// state logic can be unit-tested independently of the view.
enum ConnectionPillState: String, Equatable, CaseIterable {
    case disconnected
    case connecting
    case usbActive
    case wifiActive

    /// Map live tunnel/transport signals to a pill state.
    ///
    /// - Parameters:
    ///   - isStarting: tunnel is in the process of coming up.
    ///   - isRunning: tunnel state machine reports an active tunnel.
    ///   - transportIcon: the SF Symbol name from `ActiveTransportPresentation`
    ///     (`"wifi"` for wireless/daemon transports, `"cable.connector"` for USB,
    ///     anything else for a generic active tunnel).
    static func resolve(isStarting: Bool, isRunning: Bool, transportIcon: String) -> ConnectionPillState {
        if isStarting { return .connecting }
        guard isRunning else { return .disconnected }
        return transportIcon == "wifi" ? .wifiActive : .usbActive
    }

    var title: String {
        switch self {
        case .disconnected: return "No Connection"
        case .connecting:   return "Connecting…"
        case .usbActive:    return "USB Active"
        case .wifiActive:   return "Wi-Fi Active"
        }
    }

    var subtitle: String {
        switch self {
        case .disconnected: return "no device"
        case .connecting:   return "tunnel starting"
        case .usbActive:    return "tunnel · lockdown"
        case .wifiActive:   return "tunnel · daemon"
        }
    }

    var systemImage: String {
        switch self {
        case .disconnected: return "iphone.slash"
        case .connecting:   return "arrow.clockwise"
        case .usbActive:    return "cable.connector"
        case .wifiActive:   return "wifi"
        }
    }

    /// Whether the status dot animates (connecting + active pulse; disconnected is static).
    var pulses: Bool { self != .disconnected }

    /// Pulse period in seconds — fast while connecting, slow-and-steady when live.
    var pulsePeriod: Double { self == .connecting ? 1.2 : 2.4 }
}

struct ConnectionPill: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager

    @State private var isPulsing = false

    var body: some View {
        let state = resolvedState
        let tint = color(for: state)

        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: state.systemImage)
                .font(.system(size: DS.Metrics.connPillIconSize, weight: .medium))
                .frame(width: DS.Metrics.connPillIconSize, height: DS.Metrics.connPillIconSize)

            Circle()
                .fill(tint)
                .frame(width: DS.Metrics.connPillDotSize, height: DS.Metrics.connPillDotSize)
                .shadow(color: tint.opacity(DS.Opacity.statusGlow), radius: state.pulses ? DS.Metrics.two : 0)
                .opacity(state.pulses && isPulsing ? DS.Opacity.activeRow : 1.0)

            VStack(alignment: .leading, spacing: 0) {
                Text(state.title)
                    .font(DS.Typography.caption.weight(.semibold))
                Text(state.subtitle)
                    .font(DS.Typography.monoSmall)
                    .opacity(DS.Opacity.subtleDivider)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DS.Metrics.connPillHPadding)
        .frame(height: DS.Metrics.minButtonHeight)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(tint.opacity(DS.Opacity.statusTint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .stroke(tint.opacity(DS.Opacity.statusBorder), lineWidth: DS.Metrics.strokeWidth)
        )
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
        .animation(DS.Animation.standard, value: state)
        .onAppear { startPulse(for: state) }
        .onChange(of: state) { _, newValue in startPulse(for: newValue) }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("connectionPill")
        .accessibilityLabel("\(state.title), \(state.subtitle)")
    }

    private var resolvedState: ConnectionPillState {
        ConnectionPillState.resolve(
            isStarting: tunneldManager.isStarting,
            isRunning: tunneldManager.isRunning,
            transportIcon: transportPresentation.icon
        )
    }

    private func color(for state: ConnectionPillState) -> Color {
        switch state {
        case .disconnected: return DS.Color.inactive
        case .connecting:   return DS.Color.mockupAmber
        case .usbActive, .wifiActive: return DS.Color.mockupEmerald
        }
    }

    private func startPulse(for state: ConnectionPillState) {
        isPulsing = false
        guard state.pulses else { return }
        withAnimation(.easeInOut(duration: state.pulsePeriod / 2).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
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
struct ConnectionPill_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            DS.Color.backgroundSecondary
            ConnectionPill()
                .environmentObject(AppState())
                .environmentObject(TunneldManager.shared)
        }
        .frame(width: DS.Metrics.devicePillWidth + DS.Spacing.xl, height: DS.Metrics.devicePillHeight)
    }
}
#endif
