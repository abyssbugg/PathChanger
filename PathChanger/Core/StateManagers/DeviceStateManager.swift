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

    // MARK: Debouncing

    private var lastTunnelStateChange: Date = .distantPast
    private var lastUSBStateChange: Date = .distantPast
    private let stateDebounceInterval: TimeInterval = 2.5

    private var cancellables = Set<AnyCancellable>()

    // MARK: Computed

    /// Whether a device is ready to receive location updates.
    var isDeviceReady: Bool {
        selectedDevice != nil && isTunneldRunning
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

        guard startBackgroundServices else { return }

        observeTunnelState()
        startStatusPolling()
        setupReliabilityManager()
        setupUSBFallback()
    }

    // MARK: Setup

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
            return self.selectedDevice != nil && self.isTunneldRunning
        }

        reliabilityManager.onConnectionLost = { [weak self] in
            Task { @MainActor in
                self?.connectionStatus = .disconnected
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

        // Deduplicate by UDID: discovery can report the same device over USB and tunnel.
        var seenUDIDs = Set<String>()
        var uniqueDevices: [Device] = []

        for device in deviceManager.devices where !seenUDIDs.contains(device.id) {
            uniqueDevices.append(device)
            seenUDIDs.insert(device.id)
        }

        availableDevices = uniqueDevices

        if selectedDevice == nil, let first = availableDevices.first {
            selectedDevice = first
            onDeviceSelected?(first)
        }

        updateUSBConnected(deviceManager.usbTransportAvailable, force: true)
        isWiFiTransportAvailable = deviceManager.wifiTransportAvailable

        connectionStatus = selectedDevice != nil ? .connected : .disconnected

        if connectionStatus == .connected {
            reliabilityManager.connectionEstablished()
        }
    }

    /// Poll tunnel and transport availability.
    func checkTunneldStatus() async {
        await deviceManager.checkTunneldStatus()
        await deviceManager.refreshTransportAvailability()

        updateUSBConnected(deviceManager.usbTransportAvailable, force: true)
        isWiFiTransportAvailable = deviceManager.wifiTransportAvailable
        updateTunnelRunning(deviceManager.isTunneldRunning)

        if TunneldManager.shared.isRunning {
            updateTunnelRunning(true, force: true)
        }

        if !isTunneldRunning {
            usbFallbackManager.wirelessFailed()
        } else {
            usbFallbackManager.wirelessRestored()
        }
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
        reliabilityManager.connectionLost()
    }
}
