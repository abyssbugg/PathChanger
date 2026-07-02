import Foundation

/// Phase 3 ownership declarations for runtime modules.
///
/// These declarations are intentionally code-local (not an external markdown
/// artifact) so ownership contracts ship with the compiled source tree.
enum RuntimeOwnershipDeclarations {
    // MARK: Tunnel ownership

    /// `TunneldManager` mode-selection ownership:
    /// - `startTunnel(replaceStaleOnMissingRsd:)`
    /// - `deviceConnectionAvailability()`
    /// - `detectRunningTunnelMode()`
    /// Owns transport-mode resolution and launch intent.
    static let tunnelModeSelectionOwner = "TunneldManager (mode selection)"

    /// `TunneldManager` process-orchestration ownership:
    /// - `attemptStart(mode:)`
    /// - `executePrivilegedWrapper(script:timeout:)`
    /// - `killTrackedTunnelProcesses()`
    /// Owns privileged launch and validated child-process lifecycle.
    static let tunnelProcessOrchestrationOwner = "TunneldManager (process orchestration)"

    /// `TunneldManager` RSD-resolution ownership:
    /// - `parseRsdInfo()`
    /// - `queryTunneldAPI()`
    /// - `getRsdInfo(for:)`
    /// Owns all live tunnel endpoint materialization.
    static let tunnelRsdResolutionOwner = "TunneldManager (RSD resolution)"

    /// `TunneldManager` recovery ownership:
    /// - `recoverFromTransientTransportFailure(reason:)`
    /// - `scheduleRecovery(after:)`
    /// - `waitForAuthoritativeStartup(...)`
    /// Owns transient tunnel recovery and bounded restart behavior.
    static let tunnelRecoveryOwner = "TunneldManager (recovery)"

    // MARK: AppState ownership

    /// AppState facade ownership:
    /// owns property facades over `DeviceStore`, `TunnelStore`,
    /// `SimulationStore`, `RouteStore`, `JoystickStore`, and `UIStore`.
    static let appStateFacadeOwner = "AppState (state facade)"

    /// AppState orchestration ownership:
    /// owns simulation lifecycle orchestration (`startSimulation`, `stopSimulation`,
    /// route and joystick handoff) while delegating motion authority to
    /// `SimulationEngine`.
    static let appStateOrchestrationOwner = "AppState (orchestration)"

    /// AppState polling/recovery ownership:
    /// owns fallback tunnel-status polling gate and transient transport recovery
    /// state-machine mirroring.
    static let appStatePollingRecoveryOwner = "AppState (polling/recovery)"

    // MARK: Device/tunnel truth ownership

    /// Device/tunnel truth is owned by `TunneldManager`.
    /// `DeviceManager` mirrors status from `TunneldManager` and no longer
    /// duplicates process-pattern detection.
    static let tunnelTruthOwner = "TunneldManager (single tunnel truth)"
}
