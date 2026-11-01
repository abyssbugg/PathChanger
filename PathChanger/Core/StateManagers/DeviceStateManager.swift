//
//  DeviceStateManager.swift
//  PathChanger
//
//  Owns device discovery, selection, tunnel status and transport fallback.
//  Extracted from AppState (ARCH-002).
//
//  This is a behaviour-preserving move: the logic here came out of AppState, which is the
//  version that actually ran. The previous contents of this file were an earlier, unwired
//  decomposition that had drifted — notably it used a 0.3s tunnel debounce where AppState
//  used 2.5s to stop the connection indicator flickering, and its `checkTunneldStatus`
//  called `TunneldManager.autoStart()` on every poll. That call is deliberately not carried
//  over: it can raise an administrator prompt, and it was inert only because
//  `TunnelStartPolicy.mayElevate(for: .statusPoll)` returns false.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class DeviceStateManager: ObservableObject {

    // MARK: Published State

    @Published var selectedDevice: Device?
    @Published var availableDevices: [Device] = []
    @Published var isTunneldRunning: Bool = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var isUSBConnected: Bool = false
    @Published var isWiFiTransportAvailable: Bool = false
    @Published var usbDirectDeviceIds: Set<String> = []
    @Published var wifiDirectDeviceIds: Set<String> = []
    @Published var preferUSBConnection: Bool = false
    @Published var recoveryState: ConnectionRecoveryState = .disconnected

    // MARK: Owned Collaborators

    let deviceManager: DeviceManager
    let reliabilityManager: ReliabilityManager
    let usbFallbackManager: USBFallbackManager

    // Tunnel health is monitored only by TunneldManager's own TunnelHealthMonitor,
    // which is wired to the tunnel state machine. A second monitor here had no
    // failure handler: it doubled every liveness and endpoint probe to no effect.

    // MARK: Callbacks
    //
    // Callbacks rather than direct references, so this type stays independent of the
    // simulation and error-presentation layers.

    /// Fires when the active device changes, so the simulation engine can follow it.
    var onDeviceSelected: ((Device) -> Void)?

    /// Fires when the tunnel becomes active or inactive.
    var onTunnelActiveChanged: ((Bool) -> Void)?

    /// Fires when the connection drops, for user-facing messaging.
    var onConnectionLost: (() -> Void)?

    /// Fires when automatic reconnection gives up, carrying the reason.
    var onReconnectionFailed: ((String) -> Void)?

    /// Publishes typed transport/device changes to the location-session coordinator.
    var onLocationSessionLoss: ((LocationSessionLossEvent) -> Void)?

    // MARK: Debouncing

    private var lastTunnelStateChange: Date = .distantPast
    private var lastUSBStateChange: Date = .distantPast
    private let stateDebounceInterval: TimeInterval = 2.5

    /// Transport availability refreshes at most this often on the status poll while a
    /// device is selected or the tunnel is running: routing (`--udid` vs `--rsd`) must
    /// not act on minutes-old usbmux visibility, but the 5 s poll must not spawn a
    /// subprocess on every tick either.
    private var lastTransportRefresh: Date = .distantPast
    private let transportRefreshInterval: TimeInterval = 15

    private var cancellables = Set<AnyCancellable>()
    private var isResolvingRecoverySession = false
    private var lastObservedTunnelState: TunnelState?

    // MARK: Computed

    /// Whether a device is ready to receive location updates.
    var isDeviceReady: Bool {
        selectedDevice != nil && (selectedDirectTransportAvailable || isTunneldRunning)
    }

    /// Whether usbmux currently exposes the selected device over its own transport.
    ///
    /// `ConnectionType.network` devices can carry DVT directly via `--udid`; the installed
    /// reference app has been verified doing exactly this on iOS 27 with the USB cable
    /// disconnected. A RemoteXPC tunnel is an alternative, not a prerequisite.
    var selectedDirectTransportAvailable: Bool {
        guard let selectedDevice else { return false }
        switch selectedDevice.connectionType {
        case .usb:
            return usbDirectDeviceIds.contains(selectedDevice.id)
        case .wifi:
            return wifiDirectDeviceIds.contains(selectedDevice.id)
        }
    }

    /// True only when the selected device is not reachable directly through usbmux.
    var requiresTunnelForSelectedDevice: Bool {
        selectedDevice != nil && !selectedDirectTransportAvailable
    }

    // MARK: Initialization

    // Collaborators are resolved inside the body rather than as default arguments: a default
    // argument is evaluated in the caller's context, which is nonisolated, and these types
    // are main-actor isolated.
    init(
        deviceManager: DeviceManager? = nil,
        reliabilityManager: ReliabilityManager? = nil,
        usbFallbackManager: USBFallbackManager? = nil,
        startBackgroundServices: Bool = true
    ) {
        // A DeviceManager built here follows this manager's background-services choice;
        // building it with background services on regardless spawned pymobiledevice3
        // discovery from every test AppState on each tunnel change (~4.8k pipes).
        self.deviceManager = deviceManager ?? DeviceManager(startBackgroundServices: startBackgroundServices)
        self.reliabilityManager = reliabilityManager ?? ReliabilityManager()
        self.usbFallbackManager = usbFallbackManager ?? USBFallbackManager()

        observeDeviceDiscovery()

        guard startBackgroundServices else { return }

        observeTunnelState()
        startStatusPolling()
        setupReliabilityManager()
        setupUSBFallback()
    }

    // MARK: Setup

    private func observeDeviceDiscovery() {
        deviceManager.$devices
            .dropFirst()
            .sink { [weak self] devices in
                self?.synchronizeDiscoveredDevices(devices)
            }
            .store(in: &cancellables)
    }

    private func synchronizeDiscoveredDevices(_ discoveredDevices: [Device]) {
        var seenUDIDs = Set<String>()
        let uniqueDevices = discoveredDevices.filter { device in
            seenUDIDs.insert(device.id).inserted
        }

        availableDevices = uniqueDevices

        if let selectedDevice,
           let updated = availableDevices.first(where: { $0.id == selectedDevice.id }) {
            let transportChanged = updated.connectionType != selectedDevice.connectionType
            self.selectedDevice = updated
            onDeviceSelected?(updated)
            if transportChanged && !isResolvingRecoverySession {
                onLocationSessionLoss?(.endpointReplaced)
            }
        } else if let selectedDevice {
            self.selectedDevice = nil
            connectionStatus = .disconnected
            onLocationSessionLoss?(.selectedDeviceLost(stableDeviceID: selectedDevice.id))
        } else if let first = availableDevices.first {
            selectedDevice = first
            onDeviceSelected?(first)
        }

        updateUSBConnected(deviceManager.usbTransportAvailable, force: true)
        isWiFiTransportAvailable = deviceManager.wifiTransportAvailable
        usbDirectDeviceIds = deviceManager.usbDirectDeviceIds
        wifiDirectDeviceIds = deviceManager.wifiDirectDeviceIds

        connectionStatus = selectedDevice != nil ? .connected : .disconnected
        if connectionStatus == .connected {
            reliabilityManager.connectionEstablished()
        }
    }

    /// Only a tunnel that was running and stopped is a loss. Idle and starting are
    /// not: reporting them as lost failed the Connection chip before any tunnel
    /// existed (live 2026-11-01). Running -> error is a health loss; running ->
    /// stopping/idle is an explicit stop (Stop Tunnel, Reconnect, transport switch).
    nonisolated static func tunnelLossEvent(
        previous: TunnelState?,
        current: TunnelState
    ) -> LocationSessionLossEvent? {
        guard previous?.isActive == true, !current.isActive else { return nil }
        if case .error = current {
            return .tunnelHealthLost
        }
        return .tunnelStoppedByUser
    }

    private func observeTunnelState() {
        TunneldManager.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                let previous = self.lastObservedTunnelState
                self.lastObservedTunnelState = state
                self.updateTunnelRunning(state.isActive, force: true)

                if state.isActive, previous?.isActive != true {
                    Task { await self.refreshDevices() }
                    self.onTunnelActiveChanged?(true)
                } else if let loss = Self.tunnelLossEvent(previous: previous, current: state) {
                    self.onLocationSessionLoss?(loss)
                    self.onTunnelActiveChanged?(false)
                }
            }
            .store(in: &cancellables)
    }

    private func startStatusPolling() {
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.checkTunneldStatus() }
            }
            .store(in: &cancellables)
    }

    private func setupReliabilityManager() {
        reliabilityManager.onReconnect = { [weak self] in
            guard let self = self else { return false }
            await self.refreshDevices()
            return self.isDeviceReady
        }

        reliabilityManager.onConnectionLost = { [weak self] in
            Task { @MainActor in
                self?.connectionStatus = .disconnected
                if let stableDeviceID = self?.selectedDevice?.id {
                    self?.onLocationSessionLoss?(.selectedDeviceLost(stableDeviceID: stableDeviceID))
                }
                self?.onConnectionLost?()
            }
        }

        reliabilityManager.onReconnectionFailed = { [weak self] reason in
            Task { @MainActor in
                self?.connectionStatus = .error
                self?.onReconnectionFailed?(reason)
            }
        }

        reliabilityManager.$recoveryState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.recoveryState = state
            }
            .store(in: &cancellables)
    }

    private func setupUSBFallback() {
        usbFallbackManager.$isUSBConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.updateUSBConnected(connected)
            }
            .store(in: &cancellables)

        usbFallbackManager.$preferUSB
            .assign(to: &$preferUSBConnection)
    }

    // MARK: Debounced Updates

    private func updateTunnelRunning(_ newValue: Bool, force: Bool = false) {
        let now = Date()
        let shouldUpdate = force || now.timeIntervalSince(lastTunnelStateChange) >= stateDebounceInterval

        guard shouldUpdate else { return }

        if isTunneldRunning != newValue {
            isTunneldRunning = newValue
            lastTunnelStateChange = now
        }
    }

    private func updateUSBConnected(_ newValue: Bool, force: Bool = false) {
        let now = Date()
        let shouldUpdate = force || now.timeIntervalSince(lastUSBStateChange) >= stateDebounceInterval

        guard shouldUpdate else { return }

        if isUSBConnected != newValue {
            isUSBConnected = newValue
            lastUSBStateChange = now
        }
    }

    // MARK: Device Management

    /// Refresh available devices from all transports.
    func refreshDevices() async {
        await deviceManager.refreshDevices()
    }

    /// Poll tunnel and transport availability.
    func checkTunneldStatus() async {
        await deviceManager.checkTunneldStatus()
        let tunnelManager = TunneldManager.shared
        if deviceManager.isTunneldRunning && !tunnelManager.isRunning {
            // Only auto-adopt from a neutral state. If adoption previously failed and put
            // the manager in `.error`, retrying here every poll causes a visible
            // "Connecting…" loop without a new privileged launch.
            if case .idle = tunnelManager.state {
                await tunnelManager.adoptRunningTunnelIfPresent()
            }
        }
        // A connection the location helper already holds (opened by Move, or kept by
        // Preserve and Quit) is the tunnel: report it rather than "stopped".
        if !tunnelManager.isRunning, !tunnelManager.isStarting, let selectedDevice {
            await tunnelManager.adoptHelperConnectionIfPresent(
                deviceId: selectedDevice.id,
                transport: selectedDevice.connectionType == .usb ? .usb : .wifi
            )
        }
        await refreshTransportAvailabilityIfNeeded()

        updateUSBConnected(deviceManager.usbTransportAvailable, force: true)
        isWiFiTransportAvailable = deviceManager.wifiTransportAvailable
        usbDirectDeviceIds = deviceManager.usbDirectDeviceIds
        wifiDirectDeviceIds = deviceManager.wifiDirectDeviceIds
        updateTunnelRunning(deviceManager.isTunneldRunning)

        if tunnelManager.isRunning {
            updateTunnelRunning(true, force: true)
        } else if case .error = tunnelManager.state {
            // The process list can be stale for a short period after failure. Honor the
            // authoritative manager error state so UI readiness does not stick "connected".
            updateTunnelRunning(false, force: true)
        }

        if !isTunneldRunning && !isWiFiTransportAvailable {
            usbFallbackManager.wirelessFailed()
        } else {
            usbFallbackManager.wirelessRestored()
        }
    }

    /// Refresh usbmux transport visibility when it is actionable and not too recent.
    ///
    /// The `--udid` vs `--rsd` routing decision reads `usbDirectDeviceIds` /
    /// `wifiDirectDeviceIds`, so visibility is refreshed only while a device is selected
    /// or the tunnel is running, and never more often than `transportRefreshInterval`.
    /// `now` is injectable so tests can cross the interval without sleeping.
    func refreshTransportAvailabilityIfNeeded(now: Date = Date()) async {
        let shouldRefresh = (selectedDevice != nil || isTunneldRunning)
            && now.timeIntervalSince(lastTransportRefresh) >= transportRefreshInterval

        guard shouldRefresh else { return }

        // Stamped before the await so an interleaved poll tick cannot double-spawn.
        lastTransportRefresh = now
        await deviceManager.refreshTransportAvailability()
    }

    /// Resolves the same stable device over a currently verified transport and advances generation.
    func establishRecoverySession(
        previous: LocationSessionIdentity
    ) async throws -> LocationSessionIdentity {
        isResolvingRecoverySession = true
        defer { isResolvingRecoverySession = false }
        await refreshDevices()

        guard let device = availableDevices.first(where: { $0.id == previous.stableDeviceID }) else {
            throw DeviceError.deviceNotFound
        }

        let transport: LocationTransport
        if preferUSBConnection && usbDirectDeviceIds.contains(device.id) {
            transport = .usb
        } else if wifiDirectDeviceIds.contains(device.id) {
            transport = .wifi
        } else if usbDirectDeviceIds.contains(device.id) {
            transport = .usb
        } else if isTunneldRunning,
                  TunneldManager.shared.tunnelInfo?.isUsable == true {
            transport = .wifi
        } else {
            throw DeviceError.connectionFailed("No verified transport is available")
        }

        self.selectedDevice = Device(
            id: device.id,
            displayName: device.displayName,
            connectionType: transport == .usb ? .usb : .wifi,
            productType: device.productType,
            productVersion: device.productVersion
        )
        onDeviceSelected?(self.selectedDevice!)

        // The endpoint class is the provider's to state: the location helper picks its
        // own lane (userspace RSD first, usbmux direct as fallback). A class guessed here
        // from usbmux visibility rejected every recovery reapply (review 2026-11-01).
        return LocationSessionIdentity(
            stableDeviceID: previous.stableDeviceID,
            transport: transport,
            endpointClass: .unresolved,
            generation: previous.generation &+ 1
        )
    }

    /// Make a device active.
    func selectDevice(_ device: Device) {
        selectedDevice = device
        onDeviceSelected?(device)
        connectionStatus = .connected
        reliabilityManager.connectionEstablished()
    }

    /// Report that the connection was lost, starting the recovery cycle.
    func connectionLost() {
        if let stableDeviceID = selectedDevice?.id {
            onLocationSessionLoss?(.selectedDeviceLost(stableDeviceID: stableDeviceID))
        }
        reliabilityManager.connectionLost()
    }
}
