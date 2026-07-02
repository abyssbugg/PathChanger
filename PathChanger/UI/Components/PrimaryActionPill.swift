//
//  PrimaryActionPill.swift
//  PathChanger
//
//  Bottom-center 220×56 floating action capsule.
//
//  - Mode-aware label and action (Teleport / Multi-Spot / Joystick).
//  - When the tunnel is down, transforms into an amber "Tunnel Required" pill
//    that auto-starts the tunnel on tap.
//  - Disabled when no device is selected.
//
//  Reads tunnel truth directly from TunneldManager (matches the bug-fix
//  discipline used by the WiFi-mode work).
//
// MARK: - W1 Authority Declaration (Slice S0 — documentation only)
//
// PrimaryActionPill is the SOLE production T0 execution authority.
//
// Authority rules (frozen — see W1 governance plan):
//   - This is the only production UI surface authorized to initiate
//     simulation execution: teleport apply, route start, joystick start,
//     and simulation stop.
//   - When the tunnel is offline it transforms into a workflow-advancement
//     proxy that invokes `TunneldManager.shared.autoStart()` so the user
//     can still progress through Device → Location → Simulation from a
//     single surface; this is the canonical T0 tunnel-required path.
//   - All other UI surfaces (inspectors, menus, sidebars, map gestures,
//     history rows, search results) are subordinate. They may set target,
//     edit route, or stream joystick input, but MUST NOT call
//     `AppState.startSimulation(...)`, `AppState.stopSimulation()`, or
//     `AppState.setLocation(...)` as a user-facing execution gesture.
//   - DeviceTunnelPill is the sibling Phase-1 readiness authority and is
//     NOT a competing T0 surface — it owns device selection and proactive
//     tunnel-readiness within its own popover.
//
// W1 Slice S0 is documentation-only. No behavior, layout, state, bindings,
// or routing are altered by this declaration.
//

import SwiftUI

struct PrimaryActionPill: View {
    let mode: AppMode
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager
    @State private var isHovered = false
    @State private var isPerformingAction = false
    @State private var loadingContext = "Working…"

    var body: some View {
        Button(action: performAction) {
            labelContent
        }
        .buttonStyle(
            PrimaryActionPillStyle(
                visualState: visualState,
                accent: DS.ModeAccent.forMode(mode),
                isHovered: isHovered,
                isDisabled: isInteractionDisabled
            )
        )
        .disabled(isInteractionDisabled)
        .onHover { hovering in
            guard !isInteractionDisabled else {
                isHovered = false
                return
            }
            withAnimation(DS.Animation.fast) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(isLoading ? loadingContext : pillState.label)
        .accessibilityHint(pillState.hint)
        .accessibilityIdentifier("mapShellPrimaryActionPill")
    }

    // MARK: - Action

    private func performAction() {
        guard !isInteractionDisabled else {
            return
        }
        switch pillState {
        case .tunnelRequired:
            runWithLoading(context: "Starting Tunnel…") {
                await tunneldManager.autoStart()
            }
        case .selectDevice:
            return
        case .ready, .running:
            runWithLoading(context: simulationLoadingContext) {
                if appState.isSimulating {
                    await appState.stopSimulation()
                } else {
                    await appState.startSimulation(mode: mode)
                }
            }
        case .selectTarget:
            return
        }
    }

    private func runWithLoading(context: String, operation: @escaping () async -> Void) {
        Task {
            await MainActor.run {
                loadingContext = context
                isPerformingAction = true
            }
            await operation()
            await MainActor.run {
                isPerformingAction = false
            }
        }
    }

    // MARK: - Display state

    private var isLoading: Bool {
        isPerformingAction || (pillState == .tunnelRequired && tunneldManager.isStarting)
    }

    private var isInteractionDisabled: Bool {
        pillState.isDisabled || isLoading
    }

    private var visualState: PrimaryActionPillStyle.VisualState {
        if isInteractionDisabled {
            return .inactive
        }
        switch pillState {
        case .tunnelRequired:
            return .warning
        default:
            return .accent
        }
    }

    private var simulationLoadingContext: String {
        if appState.isSimulating {
            return "Stopping…"
        }
        switch mode {
        case .teleport:
            return "Applying Location…"
        case .route:
            return "Starting Route…"
        case .joystick:
            return "Starting Joystick…"
        case .settings:
            return "Applying…"
        }
    }

    @ViewBuilder
    private var labelContent: some View {
        HStack(spacing: DS.Spacing.xs) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                Text(loadingContext)
                    .lineLimit(1)
            } else {
                Image(systemName: pillState.iconName)
                Text(pillState.label)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - State derivation

    private enum PillState: Equatable {
        case tunnelRequired
        case selectDevice
        case selectTarget(needs: String)
        case ready(label: String, hint: String)
        case running

        var isDisabled: Bool {
            switch self {
            case .selectDevice, .selectTarget:
                return true
            default:
                return false
            }
        }

        var iconName: String {
            switch self {
            case .tunnelRequired:
                return "exclamationmark.triangle.fill"
            case .selectDevice:
                return "iphone.slash"
            case .selectTarget:
                return "mappin.slash"
            case .ready:
                return "play.fill"
            case .running:
                return "stop.fill"
            }
        }

        var label: String {
            switch self {
            case .tunnelRequired:
                return "Tunnel Required"
            case .selectDevice:
                return "Select a Device"
            case .selectTarget(let needs):
                return needs
            case .ready(let label, _):
                return label
            case .running:
                return "Stop"
            }
        }

        var hint: String {
            switch self {
            case .tunnelRequired:
                return "Starts the tunnel required for location simulation"
            case .selectDevice:
                return "Open the device pill (top-right) to choose a device"
            case .selectTarget(let needs):
                return needs
            case .ready(_, let hint):
                return hint
            case .running:
                return "Stops the active simulation"
            }
        }
    }

    private var pillState: PillState {
        if appState.selectedDevice == nil {
            return .selectDevice
        }
        if !tunneldManager.isRunning {
            return .tunnelRequired
        }
        if appState.isSimulating {
            return .running
        }
        switch mode {
        case .teleport:
            return appState.targetLocation == nil
                ? .selectTarget(needs: "Tap a Place")
                : .ready(label: "Apply to Device", hint: "Applies the selected target to the device")
        case .route:
            return appState.currentRoute.count >= 2
                ? .ready(label: "Start Route", hint: "Starts route playback on the selected device")
                : .selectTarget(needs: "Add 2 Waypoints")
        case .joystick:
            return (appState.currentLocation != nil || appState.targetLocation != nil)
                ? .ready(label: "Start Joystick", hint: "Starts joystick control on the selected device")
                : .selectTarget(needs: "Pick a Start")
        case .settings:
            return .ready(label: "Apply to Device", hint: "Applies the selected target to the device")
        }
    }
}

private struct PrimaryActionPillStyle: ButtonStyle {
    enum VisualState {
        case accent
        case warning
        case inactive
    }

    let visualState: VisualState
    /// Per-mode accent (mockup `[data-mode]` --accent): Teleport violet,
    /// Multi-Spot sky, Joystick orange. Drives the ready-state gradient + glow.
    let accent: DS.ModeAccent
    let isHovered: Bool
    let isDisabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && !isDisabled
        let scaleValue = scale(isPressed: isPressed)

        return configuration.label
            .font(DS.Typography.headline)
            .foregroundStyle(DS.Color.foregroundPrimary)
            .frame(width: DS.Metrics.primaryPillWidth, height: DS.Metrics.primaryPillHeight)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous)
                    .fill(backgroundFill(isPressed: isPressed))
                    .brightness(visualState == .accent && isHovered && !isPressed ? 0.05 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous)
                    .stroke(DS.Color.foregroundTertiary.opacity(DS.Opacity.hoverRow), lineWidth: DS.Metrics.strokeWidth)
            )
            .scaleEffect(scaleValue)
            .shadow(
                color: glowColor,
                radius: isDisabled ? DS.Metrics.zero : DS.Metrics.primaryPillShadowRadius,
                x: DS.Metrics.zero,
                y: isDisabled ? DS.Metrics.zero : DS.Metrics.primaryPillShadowYOffset
            )
            .animation(DS.Animation.fast, value: configuration.isPressed)
            .animation(DS.Animation.fast, value: isHovered)
    }

    private var glowColor: Color {
        if isDisabled {
            return .clear
        }
        // Mockup btn-primary: accent-colored glow instead of plain black.
        return visualState == .accent ? accent.glow : .black.opacity(DS.Opacity.hoverRow)
    }

    private func backgroundFill(isPressed: Bool) -> AnyShapeStyle {
        if isDisabled {
            return AnyShapeStyle(DS.Color.inactive)
        }
        switch visualState {
        case .accent:
            // Mockup btn-primary gradient (base -> base2), dimmed while pressed.
            return AnyShapeStyle(accent.gradient.opacity(isPressed ? 0.9 : 1.0))
        case .warning:
            return AnyShapeStyle(DS.Color.warning)
        case .inactive:
            return AnyShapeStyle(DS.Color.inactive)
        }
    }

    private func scale(isPressed: Bool) -> CGFloat {
        if isDisabled {
            return DS.Metrics.unitScale
        }
        if isPressed {
            return DS.Metrics.primaryPillPressedScale
        }
        if isHovered {
            return DS.Metrics.primaryPillHoverScale
        }
        return DS.Metrics.unitScale
    }
}

#if DEBUG
struct PrimaryActionPill_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            DS.Color.backgroundSecondary
            PrimaryActionPill(mode: .teleport)
                .environmentObject(AppState())
                .environmentObject(TunneldManager.shared)
        }
        .frame(
            width: DS.Metrics.primaryPillWidth + DS.Spacing.xl,
            height: DS.Metrics.primaryPillHeight + DS.Spacing.xxl
        )
    }
}
#endif
