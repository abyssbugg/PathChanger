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
    let tunnelHealthMonitor: TunnelHealthMonitor

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

    private var cancellables = Set<AnyCancellable>()
    private var isResolvingRecoverySession = false

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
        tunnelHealthMonitor: TunnelHealthMonitor? = nil,
        startBackgroundServices: Bool = true
    ) {
        self.deviceManager = deviceManager ?? DeviceManager()
        self.reliabilityManager = reliabilityManager ?? ReliabilityManager()
        self.usbFallbackManager = usbFallbackManager ?? USBFallbackManager()
        self.tunnelHealthMonitor = tunnelHealthMonitor ?? TunnelHealthMonitor()

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

    private func observeTunnelState() {
        TunneldManager.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.updateTunnelRunning(state.isActive, force: true)

                if state.isActive {
                    self.tunnelHealthMonitor.startMonitoring()
                    Task { await self.refreshDevices() }
                } else {
                    self.tunnelHealthMonitor.stopMonitoring()
                    self.onLocationSessionLoss?(.tunnelHealthLost)
                }

                self.onTunnelActiveChanged?(state.isActive)
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
        await deviceManager.refreshTransportAvailability()

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
        let endpointClass: LocationEndpointClass
        if preferUSBConnection && usbDirectDeviceIds.contains(device.id) {
            transport = .usb
            endpointClass = .direct
        } else if wifiDirectDeviceIds.contains(device.id) {
            transport = .wifi
            endpointClass = .direct
        } else if usbDirectDeviceIds.contains(device.id) {
            transport = .usb
            endpointClass = .direct
        } else if isTunneldRunning,
                  TunneldManager.shared.getRsdInfo(for: device.id) != nil {
            transport = .wifi
            endpointClass = .remoteServiceDiscovery
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

        return LocationSessionIdentity(
            stableDeviceID: previous.stableDeviceID,
            transport: transport,
            endpointClass: endpointClass,
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
