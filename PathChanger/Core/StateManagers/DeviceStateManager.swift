//
//  DeviceStateManager.swift
//  PathChanger
//
//  Domain-specific state manager for device-related state.
//  Part of AppState decomposition (ARCH-002).
//

import Foundation
import Combine
import SwiftUI

// MARK: - Device State Manager

/// Manages device-related state including selection, connection, and tunnel status.
///
/// `DeviceStateManager` is responsible for:
/// - Device discovery and selection
/// - Connection state tracking
/// - Tunnel status monitoring
/// - USB fallback management
///
/// ## Thread Safety
///
/// This class is marked `@MainActor` for safe SwiftUI integration.
/// All published properties update on the main thread.
///
/// ## Usage
///
/// ```swift
/// @StateObject private var deviceState = DeviceStateManager()
///
/// // Access selected device
/// if let device = deviceState.selectedDevice {
///     print("Selected: \(device.name)")
/// }
///
/// // Refresh devices
/// Task {
///     await deviceState.refreshDevices()
/// }
/// ```
@MainActor
class DeviceStateManager: ObservableObject {
    
    // MARK: Published Properties
    
    /// Currently selected device for location spoofing
    @Published var selectedDevice: Device?
    
    /// All available devices discovered
    @Published var availableDevices: [Device] = []
    
    /// Whether the tunneld daemon is running
    @Published var isTunneldRunning: Bool = false
    
    /// Current connection status
    @Published var connectionStatus: ConnectionStatus = .disconnected
    
    /// Whether USB connection is active
    @Published var isUSBConnected: Bool = false
    
    /// User preference for USB connection
    @Published var preferUSBConnection: Bool = false
    
    /// Connection recovery state
    @Published var recoveryState: ConnectionRecoveryState = .disconnected
    
    // MARK: Internal Managers
    
    let deviceManager: DeviceManager
    let reliabilityManager: ReliabilityManager
    let usbFallbackManager: USBFallbackManager
    
    // MARK: Debouncing
    
    private var lastTunnelStateChange: Date = .distantPast
    private var lastUSBStateChange: Date = .distantPast
    private let stateDebounceInterval: TimeInterval = AppConstants.Tunnel.stateDebounceInterval
    
    // MARK: Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var statusCheckTimer: AnyCancellable?
    
    // MARK: Initialization
    
    init(
        deviceManager: DeviceManager,
        reliabilityManager: ReliabilityManager,
        usbFallbackManager: USBFallbackManager
    ) {
        self.deviceManager = deviceManager
        self.reliabilityManager = reliabilityManager
        self.usbFallbackManager = usbFallbackManager
        
        setupBindings()
        setupReliabilityManager()
        setupUSBFallback()
        startStatusChecks()
    }
    
    // MARK: Setup
    
    private func setupBindings() {
        // Sync with TunneldManager state
        TunneldManager.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                self.updateTunnelRunning(state.isActive, force: true)
                
                if state.isActive {
                    Task { await self.refreshDevices() }
                }
            }
            .store(in: &cancellables)
        
        // Sync recovery state from reliability manager
        reliabilityManager.$recoveryState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.recoveryState = state
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
            }
        }
        
        reliabilityManager.onReconnectionFailed = { [weak self] _ in
            Task { @MainActor in
                self?.connectionStatus = .error
            }
        }
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
    
    private func startStatusChecks() {
        statusCheckTimer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.checkTunneldStatus() }
            }
    }
    
    // MARK: Debounced Updates
    
    func updateTunnelRunning(_ newValue: Bool, force: Bool = false) {
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
    
    /// Refresh available devices from all sources
    func refreshDevices() async {
        await deviceManager.refreshDevices()
        
        // Deduplicate devices by UDID
        var seenUDIDs = Set<String>()
        var uniqueDevices: [Device] = []
        
        for device in deviceManager.devices {
            if !seenUDIDs.contains(device.id) {
                uniqueDevices.append(device)
                seenUDIDs.insert(device.id)
            }
        }
        
        // Only update if devices changed
        let currentDeviceIds = Set(availableDevices.map { $0.id })
        let newDeviceIds = Set(uniqueDevices.map { $0.id })
        
        if currentDeviceIds != newDeviceIds {
            availableDevices = uniqueDevices
        } else {
            availableDevices = uniqueDevices
        }
        
        // Auto-select first device if none selected
        if selectedDevice == nil, let first = availableDevices.first {
            selectDevice(first)
        }
        
        // Update connection status
        connectionStatus = selectedDevice != nil ? .connected : .disconnected
        
        if connectionStatus == .connected {
            reliabilityManager.connectionEstablished()
        }
    }
    
    /// Check tunneld daemon status
    func checkTunneldStatus() async {
        await deviceManager.checkTunneldStatus()
        updateTunnelRunning(deviceManager.isTunneldRunning)
        
        if !isTunneldRunning && !TunneldManager.shared.isStarting {
            await TunneldManager.shared.autoStart()
            updateTunnelRunning(TunneldManager.shared.isRunning, force: true)
        }
        
        // Notify USB fallback manager
        if !isTunneldRunning {
            usbFallbackManager.wirelessFailed()
        } else {
            usbFallbackManager.wirelessRestored()
        }
    }
    
    /// Select a device for location spoofing
    func selectDevice(_ device: Device) {
        selectedDevice = device
        connectionStatus = .connected
        reliabilityManager.connectionEstablished()
    }
    
    /// Notify that connection was lost
    func connectionLost() {
        reliabilityManager.connectionLost()
        connectionStatus = .disconnected
    }
    
    // MARK: Computed Properties
    
    /// Whether a device is ready for simulation
    var isDeviceReady: Bool {
        selectedDevice != nil && isTunneldRunning
    }
}
