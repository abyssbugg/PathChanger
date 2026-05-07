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

import SwiftUI

struct PrimaryActionPill: View {
    let mode: AppMode
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunneldManager: TunneldManager

    var body: some View {
        Button(action: performAction) {
            HStack(spacing: 8) {
                Image(systemName: pillState.iconName)
                    .font(.system(size: 14, weight: .semibold))
                Text(pillState.label)
            }
        }
        .buttonStyle(AppCapsuleActionStyle(tone: pillState.tone))
        .disabled(pillState.isDisabled)
        .opacity(pillState.isDisabled ? 0.55 : 1.0)
        .accessibilityLabel(pillState.label)
        .accessibilityHint(pillState.hint)
        .accessibilityIdentifier("mapShellPrimaryActionPill")
    }

    // MARK: - Action

    private func performAction() {
        switch pillState {
        case .tunnelRequired:
            Task { await tunneldManager.autoStart() }
        case .selectDevice:
            // Disabled — no-op
            break
        case .ready, .running:
            Task {
                if appState.isSimulating {
                    if mode == .teleport {
                        // Teleport doesn't really "stop" — clear simulating state
                        await appState.stopSimulation()
                    } else if mode == .joystick {
                        await appState.stopSimulation()
                    } else {
                        await appState.stopSimulation()
                    }
                } else {
                    await appState.startSimulation(mode: mode)
                }
            }
        case .selectTarget:
            // Disabled — no-op (action requires user to set a target on the map)
            break
        }
    }

    // MARK: - State derivation

    private enum PillState {
        case tunnelRequired
        case selectDevice
        case selectTarget(needs: String)
        case ready
        case running

        var isDisabled: Bool {
            switch self {
            case .selectDevice, .selectTarget: return true
            default: return false
            }
        }

        var tone: AppCapsuleActionStyle.Tone {
            switch self {
            case .tunnelRequired: return .warning
            case .running: return .danger
            default: return .accent
            }
        }

        var iconName: String {
            switch self {
            case .tunnelRequired: return "exclamationmark.triangle.fill"
            case .selectDevice: return "iphone.slash"
            case .selectTarget: return "mappin.slash"
            case .ready: return "play.fill"
            case .running: return "stop.fill"
            }
        }

        var label: String {
            switch self {
            case .tunnelRequired: return "Tunnel Required"
            case .selectDevice: return "Select a Device"
            case .selectTarget(let needs): return needs
            case .ready: return "Set Location"
            case .running: return "Stop"
            }
        }

        var hint: String {
            switch self {
            case .tunnelRequired: return "Starts the tunnel required for location simulation"
            case .selectDevice: return "Open the device pill (top-right) to choose a device"
            case .selectTarget(let needs): return needs
            case .ready: return "Applies the selected location to the device"
            case .running: return "Stops the active simulation"
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
                : .ready
        case .route:
            return appState.currentRoute.count >= 2
                ? .ready
                : .selectTarget(needs: "Add 2 Waypoints")
        case .joystick:
            return (appState.currentLocation != nil || appState.targetLocation != nil)
                ? .ready
                : .selectTarget(needs: "Pick a Start")
        case .settings:
            return .ready
        }
    }
}

#if DEBUG
struct PrimaryActionPill_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.2)
            PrimaryActionPill(mode: .teleport)
                .environmentObject(AppState())
                .environmentObject(TunneldManager.shared)
        }
        .frame(width: 320, height: 120)
    }
}
#endif
