//
//  AppStateStores.swift
//  PathChanger
//
//  Composed sub-store value types that hold the canonical application
//  state previously stored as individual `@Published` vars on `AppState`.
//
//  Introduced in Milestone 4 (AppState decomposition). Each sub-store
//  owns a single state domain — device, tunnel, simulation, route,
//  joystick, UI. AppState becomes a thin composed facade over these
//  stores: it exposes `@Published var <store>: <Store>` for each one
//  (so SwiftUI views observe mutations transparently) and forwards
//  legacy property names through computed facade getters/setters that
//  read/write the corresponding sub-store field.
//
//  Architectural rules (AAD §5.1):
//  - Sub-stores are plain `struct`s (value types). Mutating a sub-store
//    via AppState triggers `@Published` to publish the parent struct,
//    which in turn fires `objectWillChange` on AppState.
//  - Only AppState may mutate these stores (single-writer principle).
//    External code mutates through AppState's facade properties or
//    public mutation methods.
//  - No reference-type observers live inside the sub-stores — they hold
//    plain data only. Service references (`deviceManager`,
//    `simulationEngine`, etc.) stay on AppState directly.
//

import Foundation
import SwiftUI

// MARK: - DeviceStore

/// Canonical storage for device-related state: the currently selected
/// device, the list of discovered devices, transport availability flags
/// (USB / WiFi), and the high-level connection status.
///
/// Mutated only by `AppState`. UI consumers continue to read the legacy
/// property names (`appState.selectedDevice`, `appState.availableDevices`,
/// …) which now route through this store via computed facades.
struct DeviceStore {
    var selected: Device?
    var available: [Device] = []
    var connectionStatus: ConnectionStatus = .disconnected
    var isUSBConnected: Bool = false
    var isWiFiAvailable: Bool = false
    var recoveryState: ConnectionRecoveryState = .disconnected

    static let empty = DeviceStore()
}

// MARK: - TunnelStore

/// Canonical storage for tunnel-related state mirrored into AppState
/// from `TunneldManager.shared`. AppState's tunnel state is a UI-facing
/// mirror — the authoritative tunnel state machine lives in
/// `TunneldManager`. AppState debounces transitions to reduce UI
/// flicker (see `updateTunnelRunning(_:force:)`).
struct TunnelStore {
    var isRunning: Bool = false

    static let empty = TunnelStore()
}

// MARK: - SimulationStore

/// Canonical storage for simulation lifecycle and location state.
///
/// AppState owns the lifecycle flags here (`isSimulating`, `isPaused`,
/// `currentLocation`, `targetLocation`, …). Motion progression — the
/// per-tick timer, route interpolation, and `LocationBridge` calls —
/// is owned by `SimulationEngine`, the sole simulation authority
/// (Milestone 3). AppState mirrors engine state into this store via the
/// `setupSimulationEngineMirrors()` Combine subscriptions.
struct SimulationStore {
    var currentLocation: LocationCoordinate?
    var targetLocation: LocationCoordinate?
    var targetLocationName: String?
    var isSimulating: Bool = false
    var isPaused: Bool = false
    var speed: SimulationSpeed = .walking
    var injectionStats: InjectionStats = InjectionStats()
    var history: [LocationHistoryEntry] = []
    /// Set of device IDs that have already received the newer-iOS
    /// compatibility warning toast in this session. Used to dedupe the
    /// warning to one toast per device per process lifetime.
    var shownIOSWarningDeviceIds: Set<String> = []

    static let empty = SimulationStore()
}

// MARK: - RouteStore

/// Canonical storage for route playback inputs: the editable waypoint
/// list the user is composing, the progress (0…1) reported by the
/// simulation engine while a route plays back, and a loading flag for
/// route-import flows (GPX, route library).
struct RouteStore {
    var waypoints: [LocationCoordinate] = []
    var progress: Double = 0
    var isLoading: Bool = false

    static let empty = RouteStore()
}

// MARK: - JoystickStore

/// Canonical storage for joystick control UI state. The direction
/// vector is the SwiftUI-bindable source of truth for the joystick
/// view; AppState forwards it into `SimulationEngine.updateJoystickDirection(_:)`
/// which converts to a compass bearing internally (Milestone 3).
struct JoystickStore {
    var direction: CGPoint = .zero
    var speed: Double = 5.0

    static let empty = JoystickStore()
}

// MARK: - UIStore

/// Canonical storage for ephemeral UI presentation state — the last
/// surfaced error message, the user-visible status text, and the
/// modal/sheet-presentation flag for the location-input sheet.
///
/// Note: `showRouteImport`, `showOnboarding`, and `preferUSBConnection`
/// are intentionally NOT included here. SwiftUI's `$appState.X`
/// projected-value binding mechanism requires the underlying storage to
/// be a `@Published` property on the `ObservableObject` itself — it
/// does not project through a struct field. Those three properties
/// remain as direct `@Published` vars on `AppState` and are documented
/// at the property declaration site.
struct UIStore {
    var lastError: String?
    var statusMessage: String?
    var showLocationInput: Bool = false

    static let empty = UIStore()
}
