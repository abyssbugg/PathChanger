//
//  DeviceManager.swift
//  PathChanger
//
//  Device discovery, connection management, and session control
//

import Foundation
import Combine

// MARK: - Device Cache (PERF-003)

/// A thread-safe cache for device information with automatic TTL management.
///
/// `DeviceCache` provides efficient storage and retrieval of device information
/// to minimize expensive device discovery operations. It uses time-to-live (TTL)
/// values to automatically invalidate stale entries.
///
/// ## Overview
///
/// The device cache improves performance by:
/// - Caching device information after discovery
/// - Tracking cache hit/miss statistics
/// - Automatically evicting expired entries
/// - Limiting maximum cache size
///
/// ## Usage
///
/// ```swift
/// let cache = DeviceCache()
///
/// // Cache a device
/// await cache.cacheDevice(device, source: .usb)
///
/// // Retrieve cached device
/// if let cachedDevice = await cache.getCachedDevice(udid: device.id) {
///     print("Cache hit: \(cachedDevice.name)")
/// }
///
/// // Check if full discovery is needed
/// if await cache.needsFullDiscovery() {
///     // Perform expensive device discovery
/// }
/// ```
///
/// ## Configuration
///
/// Use ``CacheConfig`` to customize TTL and capacity:
///
/// ```swift
/// let config = DeviceCache.CacheConfig(
///     deviceInfoTTL: 120.0,  // 2 minutes
///     deviceListTTL: 60.0,   // 1 minute
///     maxEntries: 100
/// )
/// let cache = DeviceCache(config: config)
/// ```
///
/// ## Statistics
///
/// Track cache performance with built-in statistics:
///
/// ```swift
/// let summary = await cache.getStatsSummary()
/// print(summary)
/// // Discovery Stats:
/// // - Total discoveries: 42
/// // - Cache hit rate: 87.5%
/// // - Average discovery time: 0.35s
/// ```
actor DeviceCache {
    /// Cached device entry with timestamp
    struct CachedDevice {
        let device: Device
        let cachedAt: Date
        let source: CacheSource
    }

    enum CacheSource: String {
        case usb = "USB"
        case tunnel = "Tunnel"
        case lockdown = "Lockdown"
    }

    /// Cache TTL configuration
    struct CacheConfig {
        /// Time-to-live for cached device info (default: 60 seconds)
        let deviceInfoTTL: TimeInterval
        /// Time-to-live for device list (default: 30 seconds)
        let deviceListTTL: TimeInterval
        /// Maximum cache entries
        let maxEntries: Int

        static let `default` = CacheConfig(
            deviceInfoTTL: 60.0,
            deviceListTTL: 30.0,
            maxEntries: 50
        )
    }

    private var cache: [String: CachedDevice] = [:]
    private var lastDiscoveryTime: Date?
    private let config: CacheConfig

    // MARK: - Discovery Statistics
    private(set) var stats = DiscoveryStats()

    struct DiscoveryStats {
        var totalDiscoveries: Int = 0
        var cacheHits: Int = 0
        var cacheMisses: Int = 0
        var averageDiscoveryTime: TimeInterval = 0
        private var discoveryTimes: [TimeInterval] = []

        var hitRate: Double {
            let total = cacheHits + cacheMisses
            return total > 0 ? Double(cacheHits) / Double(total) : 0
        }

        mutating func recordDiscovery(duration: TimeInterval) {
            totalDiscoveries += 1
            discoveryTimes.append(duration)
            // Keep last 100 measurements
            if discoveryTimes.count > 100 {
                discoveryTimes.removeFirst()
            }
            averageDiscoveryTime = discoveryTimes.reduce(0, +) / Double(discoveryTimes.count)
        }

        mutating func recordHit() { cacheHits += 1 }
        mutating func recordMiss() { cacheMisses += 1 }
    }

    init(config: CacheConfig = .default) {
        self.config = config
    }

    // MARK: - Cache Operations

    /// Get cached device if valid
    func getCachedDevice(udid: String) -> Device? {
        guard let entry = cache[udid] else {
            stats.recordMiss()
            return nil
        }

        let age = Date().timeIntervalSince(entry.cachedAt)
        if age < config.deviceInfoTTL {
            stats.recordHit()
            return entry.device
        }

        // Expired
        cache.removeValue(forKey: udid)
        stats.recordMiss()
        return nil
    }

    /// Cache device information
    func cacheDevice(_ device: Device, source: CacheSource) {
        // Enforce max entries
        if cache.count >= config.maxEntries {
            evictOldestEntry()
        }

        cache[device.id] = CachedDevice(
            device: device,
            cachedAt: Date(),
            source: source
        )
    }

    /// Check if full discovery is needed based on TTL
    func needsFullDiscovery() -> Bool {
        guard let lastTime = lastDiscoveryTime else { return true }
        return Date().timeIntervalSince(lastTime) >= config.deviceListTTL
    }

    /// Mark discovery completed
    func markDiscoveryComplete() {
        lastDiscoveryTime = Date()
    }

    /// Record a discovery operation with its duration
    func recordDiscoveryDuration(_ duration: TimeInterval) {
        stats.recordDiscovery(duration: duration)
    }

    /// Invalidate specific device cache
    func invalidate(udid: String) {
        cache.removeValue(forKey: udid)
    }

    /// Invalidate all cache entries
    func invalidateAll() {
        cache.removeAll()
        lastDiscoveryTime = nil
    }

    /// Get all cached devices (for incremental updates)
    func getAllCachedDevices() -> [Device] {
        let now = Date()
        return cache.values
            .filter { now.timeIntervalSince($0.cachedAt) < config.deviceInfoTTL }
            .map { $0.device }
    }

    /// Get cache statistics summary
    func getStatsSummary() -> String {
        """
        Discovery Stats:
        - Total discoveries: \(stats.totalDiscoveries)
        - Cache hit rate: \(String(format: "%.1f%%", stats.hitRate * 100))
        - Average discovery time: \(String(format: "%.2fs", stats.averageDiscoveryTime))
        - Cache entries: \(cache.count)/\(config.maxEntries)
        """
    }

    private func evictOldestEntry() {
        guard let oldest = cache.min(by: { $0.value.cachedAt < $1.value.cachedAt }) else { return }
        cache.removeValue(forKey: oldest.key)
    }
}

// MARK: - Device Error Types

/// Error types for device operations
enum DeviceError: Error, LocalizedError {
    case deviceNotFound
    case connectionFailed(String)
    case tunneldNotRunning
    case developerModeDisabled
    case commandFailed(String)
    case timeout
    case pairingRequired
    case trustRequired

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "No iOS device found. Connect a device via USB or ensure it's on the same Wi-Fi network."
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .tunneldNotRunning:
            return "Tunnel is not running. Start it from PathChanger."
        case .developerModeDisabled:
            return "Developer Mode is not enabled. Go to Settings > Privacy & Security > Developer Mode on your device."
        case .commandFailed(let reason):
            return "Command failed: \(reason)"
        case .timeout:
            return "Connection timed out. Check that the device is reachable."
        case .pairingRequired:
            return "Device needs to be paired. Connect via USB first."
        case .trustRequired:
            return "Trust this computer on your device when prompted."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .tunneldNotRunning:
            return "Open PathChanger Settings and choose Start Tunnel."
        case .developerModeDisabled:
            return "1. Open Settings on your iPhone\n2. Go to Privacy & Security\n3. Scroll down and tap Developer Mode\n4. Enable Developer Mode and restart"
        case .pairingRequired, .trustRequired:
            return "1. Connect your device via USB cable\n2. Unlock your device\n3. Tap 'Trust' when prompted\n4. Enter your device passcode"
        default:
            return nil
        }
    }
}

// MARK: - Device Connection State

/// Connection state for a device
enum DeviceConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var statusColor: String {
        switch self {
        case .disconnected: return "gray"
        case .connecting: return "orange"
        case .connected: return "green"
        case .error: return "red"
        }
    }
}

// MARK: - Session Controller

/// Manages an active session with a device
actor SessionController {
    private var device: Device?
    private var isActive: Bool = false
    private var lastHeartbeat: Date?
    private let heartbeatInterval: TimeInterval = 5.0

    func startSession(with device: Device) async throws {
        self.device = device
        self.isActive = true
        self.lastHeartbeat = Date()
    }

    func endSession() {
        self.device = nil
        self.isActive = false
        self.lastHeartbeat = nil
    }

    func heartbeat() -> Bool {
        guard isActive else { return false }
        lastHeartbeat = Date()
        return true
    }

    func isSessionValid() -> Bool {
        guard isActive, let lastBeat = lastHeartbeat else { return false }
        return Date().timeIntervalSince(lastBeat) < heartbeatInterval * 2
    }

    var currentDevice: Device? {
        return device
    }
}

// MARK: - Device Manager

/// Manages iOS device discovery, connections, and session control.
///
/// `DeviceManager` is the primary interface for discovering and managing
/// iOS device connections using pymobiledevice3. It supports both USB and
/// WiFi connections with automatic device discovery and caching.
///
/// ## Overview
///
/// The device manager provides:
/// - **Device discovery**: Automatic USB and WiFi device detection
/// - **Connection management**: Track device connection states
/// - **Tunnel management**: Monitor and manage secure tunnels for iOS 17+
/// - **Caching**: Efficient device info caching to minimize discovery overhead
///
/// ## Getting Started
///
/// Create a device manager and observe its published properties:
///
/// ```swift
/// @StateObject private var deviceManager = DeviceManager()
///
/// var body: some View {
///     List(deviceManager.devices) { device in
///         DeviceRow(device: device)
///             .onTapGesture {
///                 deviceManager.selectDevice(device)
///             }
///     }
///     .task {
///         await deviceManager.refreshDevices()
///     }
/// }
/// ```
///
/// ## Connection Modes
///
/// The manager supports three connection modes:
///
/// | Mode | Description |
/// |------|-------------|
/// | Auto | Automatically use best available connection |
/// | USB Only | Only discover USB-connected devices |
/// | WiFi Only | Only discover WiFi-connected devices |
///
/// ```swift
/// deviceManager.connectionMode = .usb
/// await deviceManager.refreshDevices()
/// ```
///
/// ## Tunnel Management
///
/// For iOS 17+ devices, a tunnel is required for location simulation:
///
/// ```swift
/// if !deviceManager.isTunneldRunning {
///     // Show PathChanger's tunnel controls.
/// }
/// ```
///
/// ## Cache Management
///
/// Access cache statistics and manage cache lifecycle:
///
/// ```swift
/// // Get cache statistics
/// let stats = await deviceManager.getCacheStatistics()
/// print(stats)
///
/// // Invalidate cache when device state changes
/// await deviceManager.invalidateDeviceCache(udid: device.id)
/// ```
///
/// ## Thread Safety
///
/// `DeviceManager` is marked `@MainActor` for safe SwiftUI integration.
/// All published properties update on the main thread.
///
/// ## Topics
///
/// ### Published State
///
/// - ``devices``
/// - ``selectedDevice``
/// - ``connectionState``
/// - ``isTunneldRunning``
/// - ``isScanning``
/// - ``lastError``
/// - ``connectionMode``
///
/// ### Device Discovery
///
/// - ``refreshDevices()``
/// - ``selectDevice(_:)``
/// - ``checkTunneldStatus()``
///
/// ### Cache Management
///
/// - ``getCacheStatistics()``
/// - ``invalidateDeviceCache(udid:)``
/// - ``invalidateAllDeviceCache()``
@MainActor
class DeviceManager: ObservableObject {
    // MARK: Published Properties
    @Published var devices: [Device] = []
    @Published var selectedDevice: Device?
    @Published var connectionState: DeviceConnectionState = .disconnected
    @Published var isTunneldRunning: Bool = false
    @Published var isScanning: Bool = false
    @Published var lastError: DeviceError?
    @Published var connectionMode: ConnectionMode = .auto

    // MARK: Connection Mode
    enum ConnectionMode: String, CaseIterable {
        case auto = "Auto"
        case usb = "USB Only"
        case wifi = "WiFi Only"
    }

    // MARK: Device Cache (PERF-003)
    private let deviceCache = DeviceCache()

    // MARK: Private Properties
    private let sessionController = SessionController()
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshEnabled: Bool = true
    private let autoRefreshInterval: TimeInterval = 120.0  // Reduced tunnel status check frequency to stabilize connection mode display

    // MARK: Debouncing for UI Stability
    private var lastTunnelStateChange: Date = Date.distantPast
    private var stateDebounceInterval: TimeInterval { AppConstants.Tunnel.stateDebounceInterval }

    // MARK: Tool Paths - Now unified to pymobiledevice3
    private var python3Path: String { PythonPathResolver.path }

    // MARK: Tunnel State Observation (Task 31: Cache Race Condition Fix)
    private var tunnelStateObserver: AnyCancellable?

    // MARK: Initialization
    init() {
        setupTunnelStateObserver()
        Task {
            await checkTunneldStatus()
            await refreshDevices()
            startAutoRefresh()
        }
    }

    // MARK: - Tunnel State Observer (Task 31)
    /// Observes tunnel state changes to invalidate device cache when tunnel disconnects.
    /// This prevents serving stale cached data after device disconnection.
    private func setupTunnelStateObserver() {
        tunnelStateObserver = TunneldManager.shared.$state
            .dropFirst() // Skip initial value
            .sink { [weak self] newState in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }

                    // Invalidate cache when tunnel transitions to idle/error state
                    switch newState {
                    case .idle, .error:
                        Logger.info("🔄 Tunnel disconnected - invalidating device cache", category: .device)
                        await self.deviceCache.invalidateAll()
                        // Also clear selected device if tunnel is down
                        if self.selectedDevice != nil && !TunneldManager.shared.isRunning {
                            self.selectedDevice = nil
                            self.connectionState = .disconnected
                        }
                    case .running:
                        // Tunnel connected - trigger a fresh device discovery
                        Logger.info("🔄 Tunnel connected - refreshing devices", category: .device)
                        await self.refreshDevices()
                    default:
                        break
                    }
                }
            }
    }

    deinit {
        refreshTask?.cancel()
        tunnelStateObserver?.cancel()
    }

    // MARK: Auto Refresh
    private func startAutoRefresh() {
        refreshTask = Task {
            while !Task.isCancelled && autoRefreshEnabled {
                try? await Task.sleep(nanoseconds: UInt64(autoRefreshInterval * 1_000_000_000))
                if !Task.isCancelled {
                    await refreshDevices()
                    await checkTunneldStatus()
                }
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshEnabled = false
        refreshTask?.cancel()
    }

    // MARK: Cache Management (PERF-003)

    /// Get device cache statistics summary
    func getCacheStatistics() async -> String {
        await deviceCache.getStatsSummary()
    }

    /// Invalidate cache for a specific device
    func invalidateDeviceCache(udid: String) async {
        await deviceCache.invalidate(udid: udid)
    }

    /// Invalidate all cached device information
    func invalidateAllDeviceCache() async {
        await deviceCache.invalidateAll()
    }

    // MARK: Debounced State Updates

    private func updateTunnelRunning(_ newValue: Bool) {
        let now = Date()
        guard now.timeIntervalSince(lastTunnelStateChange) >= stateDebounceInterval else { return }

        if isTunneldRunning != newValue {
            isTunneldRunning = newValue
            lastTunnelStateChange = now
        }
    }

    // MARK: Tunnel Status
    /// Check for both lockdown tunnel (iOS 17.4+) and legacy remote tunneld
    func checkTunneldStatus() async {
        do {
            // Check for new lockdown tunnel first (iOS 17.4+ method)
            let lockdownOutput = try await runCommand("pgrep", arguments: ["-f", "pymobiledevice3 lockdown start-tunnel"])
            if !lockdownOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateTunnelRunning(true)
                return
            }

            // Fall back to checking legacy tunneld - with small delay to avoid race conditions
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s delay to let process state stabilize
            let tunneldOutput = try await runCommand("pgrep", arguments: ["-f", "pymobiledevice3 remote tunneld"])
            let isTunnelRunning = !tunneldOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            updateTunnelRunning(isTunnelRunning)
        } catch {
            updateTunnelRunning(false)
        }
    }

    // MARK: Device Discovery - Unified pymobiledevice3
    func refreshDevices() async {
        isScanning = true
        let startTime = Date()
        defer {
            isScanning = false
            // Record discovery statistics (PERF-003)
            let duration = Date().timeIntervalSince(startTime)
            Task {
                await deviceCache.recordDiscoveryDuration(duration)
                await deviceCache.markDiscoveryComplete()
                Logger.debug("Device discovery completed in \(String(format: "%.2f", duration))s", category: .device)
            }
        }

        // Discover devices from multiple sources in parallel
        async let usbDevicesTask = discoverUSBDevices()
        async let tunnelDevicesTask = discoverTunneldAPIDevices()

        let usbDevices = await usbDevicesTask
        let tunnelDevices = await tunnelDevicesTask

        // Merge devices, preferring tunnel devices for more complete info
        var deviceMap: [String: Device] = [:]
        for device in usbDevices {
            deviceMap[device.id] = device
        }
        for device in tunnelDevices {
            deviceMap[device.id] = device
        }

        let discoveredDevices = Array(deviceMap.values)

        // Only update if there's a change to prevent UI flickering
        let currentIds = Set(devices.map { $0.id })
        let newIds = Set(discoveredDevices.map { $0.id })

        if currentIds != newIds || devices.isEmpty {
            devices = discoveredDevices
        } else {
            for (index, device) in devices.enumerated() {
                if let updated = discoveredDevices.first(where: { $0.id == device.id }) {
                    devices[index] = updated
                }
            }
        }

        if let selected = selectedDevice {
            if !devices.contains(where: { $0.id == selected.id }) {
                selectedDevice = devices.first
                connectionState = .disconnected
            }
        } else if selectedDevice == nil && !devices.isEmpty {
            selectedDevice = devices.first
        }

        lastError = nil
    }

    // MARK: USB Device Discovery (pymobiledevice3 usbmux list)
    private func discoverUSBDevices() async -> [Device] {
        do {
            let output = try await runPython(arguments: [
                "-m", "pymobiledevice3",
                "usbmux", "list"
            ])

            let baseDevices = parseDeviceListJSON(output, connectionType: ConnectionType.usb)

            // For each USB device, fetch detailed lockdown info to get DeviceName
            // Use cache to avoid repeated lockdown queries (PERF-003)
            var devices: [Device] = []
            var fetchTasks: [Task<Device, Never>] = []

            for baseDevice in baseDevices {
                let task = Task {
                    // Check cache first (PERF-003)
                    if let cachedDevice = await self.deviceCache.getCachedDevice(udid: baseDevice.id) {
                        // Update connection type from base device (may have changed)
                        return Device(
                            id: cachedDevice.id,
                            displayName: cachedDevice.displayName,
                            connectionType: baseDevice.connectionType,
                            productType: cachedDevice.productType,
                            productVersion: cachedDevice.productVersion,
                            deviceName: cachedDevice.deviceName
                        )
                    }

                    // Cache miss - fetch lockdown info
                    if let enrichedDevice = await self.fetchUSBDeviceInfo(udid: baseDevice.id, baseDevice: baseDevice) {
                        // Cache the enriched device info
                        await self.deviceCache.cacheDevice(enrichedDevice, source: .usb)
                        return enrichedDevice
                    } else {
                        // Return base device if lockdown info fetch fails
                        return baseDevice
                    }
                }
                fetchTasks.append(task)
            }

            // Collect all enriched devices in parallel
            for task in fetchTasks {
                let device = await task.value
                devices.append(device)
            }

            return devices
        } catch {
            return []
        }
    }

    // MARK: Fetch USB Device Info via Lockdown
    private func fetchUSBDeviceInfo(udid: String, baseDevice: Device) async -> Device? {
        do {
            let output = try await runPython(arguments: [
                "-m", "pymobiledevice3",
                "lockdown", "info",
                "--udid", udid
            ], timeout: 10.0)

            var info: [String: String] = [:]
            for line in output.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    info[key] = value
                }
            }

            let deviceName = info["DeviceName"] ?? baseDevice.displayName
            let productType = info["ProductType"] ?? baseDevice.productType
            let productVersion = info["ProductVersion"] ?? baseDevice.productVersion
            let deviceClass = info["DeviceClass"]

            let displayName: String
            if deviceName == "iPhone" || deviceName == "iPad" || deviceName == "iOS Device" {
                let modelName = productType.map { Device.modelNameFrom(productType: $0) } ?? deviceClass ?? deviceName
                if let version = productVersion {
                    displayName = "\(modelName) (iOS \(version))"
                } else {
                    displayName = modelName
                }
            } else {
                if let version = productVersion {
                    displayName = "\(deviceName) (iOS \(version))"
                } else {
                    displayName = deviceName
                }
            }

            Logger.debug("Enriched USB device info: \(displayName) [\(udid)]", category: .device)

            return Device(
                id: udid,
                displayName: displayName,
                connectionType: baseDevice.connectionType,
                productType: productType,
                productVersion: productVersion,
                deviceName: deviceName
            )
        } catch {
            Logger.debug("Failed to fetch USB device lockdown info for \(udid): \(error)", category: .device)
            return nil
        }
    }

    // MARK: Tunneld API Device Discovery
    private var tunneldAPIEndpoint: String { AppConstants.Tunnel.tunneldAPIEndpoint }

    private func discoverTunneldAPIDevices() async -> [Device] {
        guard let url = URL(string: tunneldAPIEndpoint) else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                Logger.debug("Tunneld API returned non-200 status", category: .device)
                return []
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]] else {
                Logger.debug("Tunneld API returned invalid JSON format", category: .device)
                return []
            }

            Logger.debug("Tunneld API returned \(json.count) device(s)", category: .device)

            // Fetch device info for all UDIDs in parallel with caching (PERF-003)
            var fetchTasks: [Task<Device, Never>] = []

            for udid in json.keys {
                let task = Task {
                    // Check cache first (PERF-003)
                    if let cachedDevice = await self.deviceCache.getCachedDevice(udid: udid) {
                        // Return cached device with WiFi connection type
                        return Device(
                            id: cachedDevice.id,
                            displayName: cachedDevice.displayName,
                            connectionType: .wifi,
                            productType: cachedDevice.productType,
                            productVersion: cachedDevice.productVersion,
                            deviceName: cachedDevice.deviceName
                        )
                    }

                    // Cache miss - fetch detailed info
                    if let device = await self.fetchDeviceInfoViaTunnel(udid: udid) {
                        // Cache the device info
                        await self.deviceCache.cacheDevice(device, source: .tunnel)
                        return device
                    } else {
                        // Fallback to basic device with just UDID
                        return Device(
                            id: udid,
                            displayName: "iOS Device (Tunnel)",
                            connectionType: .wifi,
                            productType: nil,
                            productVersion: nil,
                            deviceName: nil
                        )
                    }
                }
                fetchTasks.append(task)
            }

            // Collect all results
            var devices: [Device] = []
            for task in fetchTasks {
                let device = await task.value
                if !device.id.isEmpty {
                    devices.append(device)
                }
            }

            Logger.info("✅ Discovered \(devices.count) device(s) via Tunneld API", category: .device)
            return devices
        } catch {
            Logger.debug("Failed to query tunneld API: \(error.localizedDescription)", category: .device)
            return []
        }
    }

    private func fetchDeviceInfoViaTunnel(udid: String) async -> Device? {
        do {
            let output = try await runPython(arguments: [
                "-m", "pymobiledevice3",
                "lockdown", "info",
                "--tunnel", udid
            ], timeout: 10.0)

            var info: [String: String] = [:]
            for line in output.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    info[key] = value
                }
            }

            let deviceName = info["DeviceName"] ?? "iOS Device"
            let productType = info["ProductType"]
            let productVersion = info["ProductVersion"]
            let deviceClass = info["DeviceClass"]

            let displayName: String
            if deviceName == "iPhone" || deviceName == "iPad" || deviceName == "iOS Device" {
                let modelName = productType.map { Device.modelNameFrom(productType: $0) } ?? deviceClass ?? deviceName
                if let version = productVersion {
                    displayName = "\(modelName) (iOS \(version))"
                } else {
                    displayName = modelName
                }
            } else {
                if let version = productVersion {
                    displayName = "\(deviceName) (iOS \(version))"
                } else {
                    displayName = deviceName
                }
            }

            Logger.debug("Fetched device info via tunnel: \(displayName) [\(udid)]", category: .device)

            return Device(
                id: udid,
                displayName: displayName,
                connectionType: .wifi,
                productType: productType,
                productVersion: productVersion,
                deviceName: deviceName
            )
        } catch {
            Logger.debug("Failed to fetch device info via tunnel for \(udid): \(error)", category: .device)
            return nil
        }
    }

    private func parseDeviceListJSON(_ output: String, connectionType: ConnectionType) -> [Device] {
        var devices: [Device] = []

        // Find JSON array in output (skip warnings)
        guard let jsonStart = output.firstIndex(of: "["),
              let jsonEnd = output.lastIndex(of: "]") else {
            Logger.debug("No JSON array found in device list output", category: .device)
            return []
        }

        let jsonString = String(output[jsonStart...jsonEnd])

        guard let jsonData = jsonString.data(using: .utf8) else {
            Logger.debug("Failed to convert JSON string to data", category: .device)
            return []
        }

        do {
            if let jsonArray = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                for item in jsonArray {
                    guard let udid = item["UniqueDeviceID"] as? String ?? item["Identifier"] as? String else {
                        continue
                    }

                    let deviceName = item["DeviceName"] as? String ?? "iOS Device"
                    let productType = item["ProductType"] as? String
                    let productVersion = item["ProductVersion"] as? String
                    let deviceClass = item["DeviceClass"] as? String

                    // Determine connection type from JSON if available
                    var connType = connectionType
                    if let jsonConnType = item["ConnectionType"] as? String {
                        // "Network" means connected via lockdown tunnel
                        connType = jsonConnType.lowercased().contains("usb") ? .usb : .wifi
                    }

                    // Build display name with device name and iOS version
                    // Show model name if device name is generic
                    let displayName: String
                    if deviceName == "iPhone" || deviceName == "iPad" || deviceName == "iOS Device" {
                        // Use model name derived from productType if available
                        let modelName = productType.map { Device.modelNameFrom(productType: $0) } ?? deviceClass ?? deviceName
                        if let version = productVersion {
                            displayName = "\(modelName) (iOS \(version))"
                        } else {
                            displayName = modelName
                        }
                    } else {
                        // Use custom device name
                        if let version = productVersion {
                            displayName = "\(deviceName) (iOS \(version))"
                        } else {
                            displayName = deviceName
                        }
                    }

                    let device = Device(
                        id: udid,
                        displayName: displayName,
                        connectionType: connType,
                        productType: productType,
                        productVersion: productVersion,
                        deviceName: deviceName
                    )

                    // Avoid duplicates by UDID
                    if !devices.contains(where: { $0.id == udid }) {
                        devices.append(device)
                        Logger.debug("Found device: \(displayName) [\(udid)]", category: .device)
                    }
                }
            }
        } catch {
            Logger.debug("Failed to parse device JSON: \(error)", category: .device)
        }

        return devices
    }

    private func extractUDID(from text: String) -> String? {
        // UDID is typically 40 hex chars (old) or 25 chars with dashes (new format)
        let patterns = [
            "[0-9a-fA-F]{40}",  // Old format
            "[0-9a-fA-F]{8}-[0-9a-fA-F]{16}"  // New format (00008xxx-xxxxxxxxxxxx)
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text) {
                return String(text[range])
            }
        }
        return nil
    }

    // MARK: WiFi/Tunneld Device Discovery
    private func discoverTunneldDevices() async -> [Device] {
        do {
            // Use pymobiledevice3 remote browse to find tunneld devices
            let output = try await runPython(arguments: [
                "-m", "pymobiledevice3",
                "remote", "browse"
            ], timeout: 5.0)

            // Try JSON parsing first
            let jsonDevices = parseDeviceListJSON(output, connectionType: ConnectionType.wifi)
            if !jsonDevices.isEmpty {
                return jsonDevices
            }

            // Fallback to text parsing for older versions
            return parseTextDeviceList(output, connectionType: ConnectionType.wifi)
        } catch {
            return []
        }
    }

    private func parseTextDeviceList(_ output: String, connectionType: ConnectionType) -> [Device] {
        var devices: [Device] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            if let udid = extractUDID(from: line) {
                // Avoid duplicates
                if !devices.contains(where: { $0.id == udid }) {
                    let device = Device(
                        id: udid,
                        displayName: "iOS Device (\(connectionType == .wifi ? "WiFi" : "USB"))",
                        connectionType: connectionType,
                        productType: nil,
                        productVersion: nil,
                        deviceName: nil
                    )
                    devices.append(device)
                }
            }
        }

        return devices
    }

    // MARK: Device Info (pymobiledevice3 lockdown info)
    private func getDeviceInfo(udid: String, viaUSB: Bool) async -> Device? {
        do {
            let args: [String]
            if !viaUSB && isTunneldRunning {
                args = ["-m", "pymobiledevice3", "lockdown", "info", "--tunnel", udid]
            } else {
                args = ["-m", "pymobiledevice3", "lockdown", "info", "--udid", udid]
            }

            let output = try await runPython(arguments: args, timeout: 10.0)

            var info: [String: String] = [:]
            for line in output.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    info[key] = value
                }
            }

            let deviceName = info["DeviceName"] ?? info["DeviceClass"] ?? "iOS Device"
            let productType = info["ProductType"]
            let productVersion = info["ProductVersion"]

            return Device(
                id: udid,
                displayName: "\(deviceName) (\(productVersion ?? "Unknown"))",
                connectionType: viaUSB ? .usb : .wifi,
                productType: productType,
                productVersion: productVersion,
                deviceName: deviceName
            )
        } catch {
            return nil
        }
    }

    // MARK: Connection Management
    func connect(to device: Device) async throws {
        connectionState = .connecting

        // Check if tunneld is running for iOS 17+
        await checkTunneldStatus()

        // For WiFi devices, tunneld must be running
        if device.connectionType == .wifi && !isTunneldRunning {
            connectionState = .error("tunneld not running")
            throw DeviceError.tunneldNotRunning
        }

        // Verify device is reachable via pymobiledevice3
        do {
            let args: [String]
            if device.connectionType == .wifi && isTunneldRunning {
                args = ["-m", "pymobiledevice3", "lockdown", "info", "--tunnel", device.id, "-k", "ProductVersion"]
            } else {
                args = ["-m", "pymobiledevice3", "lockdown", "info", "--udid", device.id, "-k", "ProductVersion"]
            }

            _ = try await runPython(arguments: args, timeout: 10.0)
            selectedDevice = device
            connectionState = .connected
            try await sessionController.startSession(with: device)
        } catch {
            connectionState = .error("Connection failed")
            throw DeviceError.connectionFailed(error.localizedDescription)
        }
    }

    func disconnect() async {
        await sessionController.endSession()
        connectionState = .disconnected
    }

    // MARK: Developer Mode Check
    func checkDeveloperMode(for device: Device) async -> Bool {
        do {
            let args: [String]
            if device.connectionType == .wifi {
                args = ["-m", "pymobiledevice3", "developer", "dvt", "ls", "--tunnel", device.id]
            } else {
                args = ["-m", "pymobiledevice3", "developer", "dvt", "ls", "--udid", device.id]
            }

            let output = try await runPython(arguments: args, timeout: 15.0)
            return !output.contains("DeveloperModeError") && !output.contains("ERROR")
        } catch {
            return false
        }
    }

    // MARK: Python Command Execution
    /// Run Python command with proper timeout protection
    private func runPython(arguments: [String], timeout: TimeInterval = 30.0) async throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: python3Path)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Set environment using centralized configuration
        process.environment = ProcessEnvironment.configured()

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let resumeLock = NSLock()

            DispatchQueue.global().async {
                do {
                    try process.run()

                    // Timeout handling with proper error throwing
                    var didTimeout = false
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        if process.isRunning {
                            didTimeout = true
                            process.terminate()
                        }
                    }

                    process.waitUntilExit()

                    resumeLock.lock()
                    defer { resumeLock.unlock() }

                    guard !hasResumed else { return }
                    hasResumed = true

                    if didTimeout {
                        continuation.resume(throwing: DeviceError.commandFailed("Command timed out after \(timeout) seconds"))
                        return
                    }

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                    // Combine output
                    continuation.resume(returning: output + errorOutput)
                } catch {
                    resumeLock.lock()
                    defer { resumeLock.unlock() }

                    guard !hasResumed else { return }
                    hasResumed = true

                    continuation.resume(throwing: DeviceError.commandFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: Legacy Command Execution (for pgrep etc)
    private func runCommand(_ command: String, arguments: [String] = [], timeout: TimeInterval = 10.0) async throws -> String {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = errorPipe

        // Set environment using centralized configuration
        process.environment = ProcessEnvironment.configured()

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let resumeLock = NSLock()

            DispatchQueue.global().async {
                do {
                    try process.run()

                    var didTimeout = false
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        if process.isRunning {
                            didTimeout = true
                            process.terminate()
                        }
                    }

                    process.waitUntilExit()

                    resumeLock.lock()
                    defer { resumeLock.unlock() }

                    guard !hasResumed else { return }
                    hasResumed = true

                    if didTimeout {
                        continuation.resume(throwing: DeviceError.commandFailed("Command timed out after \(timeout) seconds"))
                        return
                    }

                    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8) ?? ""

                    continuation.resume(returning: output)
                } catch {
                    resumeLock.lock()
                    defer { resumeLock.unlock() }

                    guard !hasResumed else { return }
                    hasResumed = true

                    continuation.resume(throwing: DeviceError.commandFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: Convenience Methods
    var hasDevices: Bool {
        !devices.isEmpty
    }

    var isConnected: Bool {
        connectionState.isConnected
    }

    func selectDevice(_ device: Device) async {
        do {
            try await connect(to: device)
        } catch {
            lastError = error as? DeviceError ?? .connectionFailed(error.localizedDescription)
        }
    }

    func setConnectionMode(_ mode: ConnectionMode) {
        connectionMode = mode
        Task {
            await refreshDevices()
        }
    }
}
