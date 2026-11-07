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
/// - **Tunnel management**: Monitor and manage secure tunnels for capability-compatible iOS
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
/// The user chooses one of two connection modes (owner decision 2026-11-06); there is
/// no automatic failover between them:
///
/// | Mode | Description |
/// |------|-------------|
/// | USB Only | Only discover USB-connected devices |
/// | WiFi Only | Only discover WiFi-connected devices |
///
/// ```swift
/// deviceManager.connectionMode = .usb
/// await deviceManager.refreshDevices()
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
/// - ``isScanning``
/// - ``lastError``
/// - ``connectionMode``
///
/// ### Device Discovery
///
/// - ``refreshDevices()``
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
    @Published var isScanning: Bool = false
    @Published var lastError: DeviceError?
    @Published var connectionMode: ConnectionMode = .wifi
    /// True when usbmux reports a USB attachment. Independent of tunnel state.
    @Published private(set) var usbTransportAvailable: Bool = false
    /// True when usbmux reports a Network/Wi-Fi attachment. Independent of tunnel state.
    @Published private(set) var wifiTransportAvailable: Bool = false
    /// Exact UDIDs currently reported on each direct usbmux transport.
    @Published private(set) var usbDirectDeviceIds: Set<String> = []
    @Published private(set) var wifiDirectDeviceIds: Set<String> = []
    /// UDIDs mobdev2 Bonjour advertised, each held through fewer than
    /// `transportMissThreshold` browses in a row that did not see it.
    @Published private(set) var networkAdvertisedDeviceIds: Set<String> = []

    private var usbTransportMisses: Int = 0
    private var wifiTransportMisses: Int = 0
    /// Consecutive browses that missed each retained UDID. Per device, not per set:
    /// Bonjour sees the whole LAN, so a run that sees only another phone is a miss for ours.
    private var networkAdvertisedMisses: [String: Int] = [:]
    /// Retained UDIDs the next Bonjour observation decides outright (`letTheNextBrowseDecide`).
    private var networkAdvertisedAwaitingFreshObservation: Set<String> = []
    /// The Bonjour browse in flight, joined by any overlapping caller so one browse is
    /// one observation (the 120 s discovery and the 15 s transport refresh can overlap).
    private var mobdev2BrowseInFlight: Task<[Device], Never>?
    private let transportMissThreshold: Int = 3

    // MARK: Connection Mode
    /// USB or Wi-Fi, chosen by the user (owner decision 2026-11-06). The raw values are
    /// the stored ones earlier builds wrote, so a saved choice stays readable.
    enum ConnectionMode: String, CaseIterable {
        case usb = "USB Only"
        case wifi = "WiFi Only"

        /// The tunnel mode this connection mode sets; the two settings always agree.
        var tunnelMode: TunnelMode {
            switch self {
            case .usb: return .usb
            case .wifi: return .wifi
            }
        }
    }

    // MARK: Device Cache (PERF-003)
    private let deviceCache = DeviceCache()

    lazy var preparationService = DevicePreparationService(records: .standard()) { [weak self] arguments, timeout in
        guard let self else {
            throw DeviceError.commandFailed("Device manager is unavailable")
        }
        return try await self.runPython(arguments: arguments, timeout: timeout)
    }

    // MARK: Private Properties
    private let sessionController = SessionController()
    private var refreshTask: Task<Void, Never>?
    private var latestRefreshGeneration: UInt64 = 0
    private var autoRefreshEnabled: Bool = true
    private let autoRefreshInterval: TimeInterval = 120.0  // Reduced tunnel status check frequency to stabilize connection mode display

    private struct DiscoveryAttempt {
        let devices: [Device]
        let errorMessage: String?

        var succeeded: Bool { errorMessage == nil }
    }

    // MARK: Tool Paths - Now unified to pymobiledevice3
    private var python3Path: String { PythonPathResolver.path }

    /// Runs a read-only process-listing command (executable, arguments) and returns
    /// its stdout. Injectable so tunnel-status tests never spawn processes.
    lazy var processListing: (_ executable: String, _ arguments: [String]) async throws -> String = { [weak self] executable, arguments in
        guard let self else {
            throw DeviceError.commandFailed("Device manager is unavailable")
        }
        return try await self.runCommand(executable, arguments: arguments)
    }

    // MARK: Tunnel State Observation (Task 31: Cache Race Condition Fix)
    private var tunnelStateObserver: AnyCancellable?

    /// Where the connection mode is stored (`AppPreferences.store`
    /// unless injected), so tests never write the app's own preferences domain.
    let settings: UserDefaults

    // MARK: Initialization
    init(startBackgroundServices: Bool = true, settings: UserDefaults = AppPreferences.store) {
        self.settings = settings
        if let saved = Self.loadConnectionMode(from: settings) {
            connectionMode = saved
        }
        guard startBackgroundServices else { return }
        setupTunnelStateObserver()
        Task {
            await refreshDevices()
            startAutoRefresh()
        }
    }

    /// The stored connection mode, read only after the connection settings migration
    /// has rewritten both stored settings to one transport.
    static func loadConnectionMode(from settings: UserDefaults) -> ConnectionMode? {
        ConnectionSettingsMigration.prepare(settings)
        return settings.string(forKey: ConnectionSettingsMigration.connectionModeKey)
            .flatMap(ConnectionMode.init(rawValue:))
    }

    /// Whether live usbmux reports the device over USB or Network — exactly when
    /// the direct `--udid` DVT path is available (see LocationConnectionArguments.make).
    func isDirectlyReachable(_ udid: String) -> Bool {
        usbDirectDeviceIds.contains(udid) || wifiDirectDeviceIds.contains(udid)
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
                        // Do not clear the selected device merely because an optional
                        // RemoteXPC tunnel stopped. usbmux may still expose the same phone
                        // directly over USB or Network/Wi-Fi. Refreshing below reconciles
                        // the real transports and only drops a device that actually vanished.
                        await self.refreshDevices()
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
                }
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshEnabled = false
        refreshTask?.cancel()
    }

    // MARK: Wi-Fi Preparation

    /// Bootstrap a trusted USB device for repeatable Network/Wi-Fi discovery.
    func prepareWiFi(for device: Device) async throws {
        guard DevicePreparationPlanner.canPrepareWiFi(
            deviceId: device.id,
            usbDeviceIds: usbDirectDeviceIds
        ) else {
            throw DeviceError.connectionFailed(
                "Connect the trusted device by USB once to prepare Wi-Fi pairing."
            )
        }

        try await preparationService.prepareWiFi(deviceId: device.id)
        AppPreferences.store.set(device.id, forKey: "lastPreparedDeviceUDID")

        await refreshTransportAvailability()
        await refreshDevices()
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

    // MARK: Device Discovery - Unified pymobiledevice3
    func refreshDevices() async {
        latestRefreshGeneration &+= 1
        let refreshGeneration = latestRefreshGeneration
        isScanning = true
        let startTime = Date()
        defer {
            if refreshGeneration == latestRefreshGeneration {
                isScanning = false
            }
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
        async let mobdev2DevicesTask = discoverMobdev2Devices()

        let usbAttempt = await usbDevicesTask
        let mobdev2Devices = await mobdev2DevicesTask
        let knownWiFiDevices = discoverKnownRemotePairingDevices()

        let discoveredDevices = mergeDiscoverySources(
            knownWiFiDevices: knownWiFiDevices,
            mobdev2Devices: mobdev2Devices,
            usbmuxDevices: usbAttempt.devices,
            mode: connectionMode
        )
        let rawDeviceCount = knownWiFiDevices.count
            + mobdev2Devices.count
            + usbAttempt.devices.count
        Logger.debug(
            "Device discovery collapsed \(rawDeviceCount) raw entries to \(discoveredDevices.count) canonical device(s)",
            category: .device
        )

        commitDiscoverySnapshot(
            discoveredDevices,
            scanSucceeded: usbAttempt.succeeded,
            generation: refreshGeneration,
            latestGeneration: latestRefreshGeneration,
            errorMessage: usbAttempt.errorMessage
        )
    }

    private func commitDiscoverySnapshot(
        _ discoveredDevices: [Device],
        scanSucceeded: Bool,
        generation: UInt64,
        latestGeneration: UInt64,
        errorMessage: String?
    ) {
        guard generation == latestGeneration else {
            Logger.debug(
                "Ignoring stale device refresh generation \(generation); latest is \(latestGeneration)",
                category: .device
            )
            return
        }
        guard scanSucceeded else {
            lastError = .commandFailed(errorMessage ?? "Device discovery failed")
            return
        }

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

    #if DEBUG
    func commitDiscoverySnapshotForTesting(
        _ discoveredDevices: [Device],
        scanSucceeded: Bool,
        generation: UInt64,
        latestGeneration: UInt64,
        errorMessage: String?
    ) {
        commitDiscoverySnapshot(
            discoveredDevices,
            scanSucceeded: scanSucceeded,
            generation: generation,
            latestGeneration: latestGeneration,
            errorMessage: errorMessage
        )
    }
    #endif

    private func mergeDiscoverySources(
        knownWiFiDevices: [Device],
        mobdev2Devices: [Device],
        usbmuxDevices: [Device],
        mode: ConnectionMode
    ) -> [Device] {
        let directUSBDevices = usbmuxDevices.filter { $0.connectionType == .usb }
        let directNetworkDevices = usbmuxDevices.filter { $0.connectionType == .wifi }
        let liveDeviceIds = Set(
            (mobdev2Devices + usbmuxDevices).map(\.id)
        )
        let corroboratedKnownWiFiDevices = knownWiFiDevices.filter {
            liveDeviceIds.contains($0.id)
        }
        let rankedSources: [[Device]]
        switch mode {
        case .usb:
            rankedSources = [directUSBDevices]
        case .wifi:
            rankedSources = [
                corroboratedKnownWiFiDevices,
                mobdev2Devices,
                directNetworkDevices,
            ]
        }

        var devicesById: [String: Device] = [:]
        var firstSeenIds: [String] = []
        for source in rankedSources {
            for device in source {
                if let existing = devicesById[device.id] {
                    devicesById[device.id] = mergeDevice(device, with: existing)
                } else {
                    firstSeenIds.append(device.id)
                    devicesById[device.id] = device
                }
            }
        }

        let rankedDevices = firstSeenIds.compactMap { devicesById[$0] }
        return deduplicatePhysicalDevices(rankedDevices)
    }

    #if DEBUG
    func mergedDiscoverySourcesForTesting(
        knownWiFiDevices: [Device],
        mobdev2Devices: [Device],
        usbmuxDevices: [Device],
        mode: ConnectionMode
    ) -> [Device] {
        mergeDiscoverySources(
            knownWiFiDevices: knownWiFiDevices,
            mobdev2Devices: mobdev2Devices,
            usbmuxDevices: usbmuxDevices,
            mode: mode
        )
    }
    #endif

    /// Collapse multiple discovery identifiers (UDID + IPv4/IPv6 endpoint IDs) that
    /// represent the same physical phone into one canonical device record.
    private func deduplicatePhysicalDevices(_ devices: [Device]) -> [Device] {
        guard !devices.isEmpty else { return [] }

        let udidDevices = devices.filter { ArgumentSanitizer.isValidDeviceUDID($0.id) }
        var udidsByFingerprint: [String: Set<String>] = [:]
        for device in udidDevices {
            guard let fingerprint = physicalFingerprint(for: device) else { continue }
            udidsByFingerprint[fingerprint, default: []].insert(device.id)
        }
        let udidByFingerprint = udidsByFingerprint.compactMapValues { deviceIds in
            deviceIds.count == 1 ? deviceIds.first : nil
        }
        let soleUDID = udidDevices.count == 1 ? udidDevices[0] : nil

        var mergedByCanonicalId: [String: Device] = [:]
        var firstSeenOrder: [String: Int] = [:]

        for (index, device) in devices.enumerated() {
            let canonicalId: String = {
                if ArgumentSanitizer.isValidDeviceUDID(device.id) {
                    return device.id
                }
                if let fingerprint = physicalFingerprint(for: device),
                   let matchedUDID = udidByFingerprint[fingerprint] {
                    return matchedUDID
                }
                if let soleUDID, resembles(device, soleUDID) {
                    return soleUDID.id
                }
                return device.id
            }()

            if firstSeenOrder[canonicalId] == nil {
                firstSeenOrder[canonicalId] = index
            }

            let remapped = remapDevice(device, to: canonicalId)
            if let existing = mergedByCanonicalId[canonicalId] {
                mergedByCanonicalId[canonicalId] = mergeDevice(existing, with: remapped)
            } else {
                mergedByCanonicalId[canonicalId] = remapped
            }
        }

        return mergedByCanonicalId
            .sorted { (lhs, rhs) in
                let leftOrder = firstSeenOrder[lhs.key] ?? Int.max
                let rightOrder = firstSeenOrder[rhs.key] ?? Int.max
                return leftOrder < rightOrder
            }
            .map(\.value)
    }

    private func physicalFingerprint(for device: Device) -> String? {
        let identityName = (device.deviceName ?? device.displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let productType = (device.productType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let productVersion = (device.productVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !identityName.isEmpty || !productType.isEmpty || !productVersion.isEmpty else {
            return nil
        }
        return "\(identityName)|\(productType)|\(productVersion)"
    }

    private func resembles(_ lhs: Device, _ rhs: Device) -> Bool {
        if let lhsName = lhs.deviceName, let rhsName = rhs.deviceName,
           !lhsName.isEmpty, !rhsName.isEmpty, lhsName == rhsName {
            return true
        }
        return lhs.displayName == rhs.displayName
            || (lhs.productType == rhs.productType && lhs.productVersion == rhs.productVersion)
    }

    private func remapDevice(_ device: Device, to id: String) -> Device {
        Device(
            id: id,
            displayName: device.displayName,
            connectionType: device.connectionType,
            productType: device.productType,
            productVersion: device.productVersion,
            deviceName: device.deviceName
        )
    }

    private func mergeDevice(_ preferred: Device, with candidate: Device) -> Device {
        let isPreferredGeneric = preferred.displayName == "Paired iOS Device"
            || preferred.displayName == "iOS Device"
        let displayName = isPreferredGeneric ? candidate.displayName : preferred.displayName

        let deviceName = preferred.deviceName ?? candidate.deviceName
        let productType = preferred.productType ?? candidate.productType
        let productVersion = preferred.productVersion ?? candidate.productVersion
        let connectionType: ConnectionType = preferred.connectionType == .usb || candidate.connectionType == .usb
            ? .usb
            : preferred.connectionType

        return Device(
            id: preferred.id,
            displayName: displayName,
            connectionType: connectionType,
            productType: productType,
            productVersion: productVersion,
            deviceName: deviceName
        )
    }

    #if DEBUG
    func deduplicatedDevicesForTesting(_ devices: [Device]) -> [Device] {
        deduplicatePhysicalDevices(devices)
    }
    #endif

    /// Discover devices known to pymobiledevice3 even before Bonjour/usbmux advertises
    /// them. Only filenames are read; pairing secrets never leave the record.
    private func discoverKnownRemotePairingDevices() -> [Device] {
        let recordsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pymobiledevice3", isDirectory: true)

        guard let filenames = try? FileManager.default.contentsOfDirectory(atPath: recordsDirectory.path) else {
            return []
        }

        return filenames.compactMap { filename in
            guard let deviceId = DevicePreparationPlanner.remotePairingDeviceId(from: filename) else {
                return nil
            }
            return Device(
                id: deviceId,
                displayName: "Paired iOS Device",
                connectionType: .wifi,
                productType: nil,
                productVersion: nil,
                deviceName: nil
            )
        }
    }

    /// Discover paired Network devices over Apple's `_apple-mobdev2._tcp` Bonjour service.
    ///
    /// This is independent of usbmux and is the supported pymobiledevice3 bridge for devices
    /// visible to CoreDevice/FlowDeck while usbmux has not created a Network entry.
    /// It runs in USB mode too (owner decision 2026-11-06): the Preferred Connection is
    /// not an exclusive transport restriction, and Wi-Fi visibility must stay known.
    private func discoverMobdev2Devices() async -> [Device] {
        await observeMobdev2()
    }

    /// One Bonjour observation: browse once and apply the result once. A caller that
    /// arrives while a browse is in flight joins it instead of spawning a second one.
    private func observeMobdev2() async -> [Device] {
        if let inFlight = mobdev2BrowseInFlight {
            return await inFlight.value
        }
        let browse = Task { [weak self] () -> [Device] in
            guard let self else { return [] }
            let output = await self.browseMobdev2()
            self.mobdev2BrowseInFlight = nil
            return self.applyMobdev2Observation(output)
        }
        mobdev2BrowseInFlight = browse
        return await browse.value
    }

    /// One `bonjour mobdev2` browse; nil when the command failed.
    private func browseMobdev2() async -> String? {
        let recordsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pymobiledevice3", isDirectory: true)
            .path
        let arguments = DevicePreparationPlanner.mobdev2BrowseArguments(
            pairingRecordsPath: recordsPath
        )

        do {
            return try await runPython(arguments: arguments, timeout: 10)
        } catch {
            Logger.debug(
                "mobdev2 discovery failed: \(error.localizedDescription)",
                category: .device
            )
            return nil
        }
    }

    /// Parses one mobdev2 browse result and records what it advertised, with per-device
    /// hysteresis: every UDID the run saw is kept and its miss count reset; every retained
    /// UDID it did not see (the run was empty, failed, or saw only other devices) counts a
    /// miss, and only `transportMissThreshold` misses in a row drop it. A UDID marked by
    /// `letTheNextBrowseDecide` is dropped by its first miss instead, and this run consumes
    /// every mark. Returns this run's devices, not the retained set.
    private func applyMobdev2Observation(_ output: String?) -> [Device] {
        let devices = output.map { parseDeviceListJSON($0, connectionType: .wifi) } ?? []
        let seen = Set(devices.map(\.id))
        var retained = networkAdvertisedDeviceIds
        for id in retained.subtracting(seen) {
            let misses = (networkAdvertisedMisses[id] ?? 0) + 1
            if misses >= transportMissThreshold || networkAdvertisedAwaitingFreshObservation.contains(id) {
                retained.remove(id)
                networkAdvertisedMisses[id] = nil
            } else {
                networkAdvertisedMisses[id] = misses
            }
        }
        networkAdvertisedAwaitingFreshObservation = []
        for id in seen {
            networkAdvertisedMisses[id] = nil
        }
        retained.formUnion(seen)
        if retained != networkAdvertisedDeviceIds {
            networkAdvertisedDeviceIds = retained
        }
        return devices
    }

    #if DEBUG
    func applyMobdev2ObservationForTesting(_ output: String?) -> [Device] {
        applyMobdev2Observation(output)
    }
    #endif

    /// Let the next Bonjour observation alone decide whether `deviceID` stays advertised:
    /// unseen, it is dropped at once instead of counting one hysteresis miss. Used when the
    /// transport browse resumes for the selected device after skipped refreshes, during
    /// which its entry aged only on the 120 s discovery browse (review 2026-11-01 v3).
    func letTheNextBrowseDecide(_ deviceID: String) {
        networkAdvertisedAwaitingFreshObservation.insert(deviceID)
    }

    // MARK: Helper connect hint

    /// The phones automatic reconnect counts as visible again. In USB mode a phone seen
    /// only by mobdev2 Bonjour is left out (owner decision 2026-11-06, until the Part C
    /// recovery design): the helper connects over USB there (`helperConnectTransport`), so
    /// counting it would start USB attempts that cannot succeed.
    nonisolated static func reconnectVisibleDeviceIDs(
        usb: Set<String>,
        network: Set<String>,
        bonjour: Set<String>,
        mode: ConnectionMode
    ) -> Set<String> {
        let direct = usb.union(network)
        switch mode {
        case .usb: return direct
        case .wifi: return direct.union(bonjour)
        }
    }

    /// The transport hint for opening the location helper's connection to `deviceID`. It
    /// decides whether the helper may try its mobdev2 (Bonjour, Wi-Fi) lane, so it follows
    /// the connection mode, as Start does: USB Only asks for USB and never crosses to
    /// Wi-Fi; Wi-Fi Only asks for Network. The row's type is not used: it stays `.usb`
    /// until discovery relabels it (up to 120 s after the cable is pulled), review
    /// 2026-11-01 v3.
    func helperConnectTransport(for deviceID: String) -> LocationTransport {
        switch connectionMode {
        case .usb: return .usb
        case .wifi: return .wifi
        }
    }

    // MARK: USB Device Discovery (pymobiledevice3 usbmux list)
    private func discoverUSBDevices() async -> DiscoveryAttempt {
        do {
            let output = try await runPython(arguments: [
                "-m", "pymobiledevice3",
                "usbmux", "list"
            ])

            applyUsbmuxTransportObservation(output)
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

            return DiscoveryAttempt(devices: devices, errorMessage: nil)
        } catch {
            Logger.error(
                "Authoritative usbmux discovery failed: \(error.localizedDescription)",
                category: .device
            )
            return DiscoveryAttempt(
                devices: [],
                errorMessage: "usbmux discovery failed: \(error.localizedDescription)"
            )
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

                    if let existingIndex = devices.firstIndex(where: { $0.id == udid }) {
                        if connType == .usb && devices[existingIndex].connectionType != .usb {
                            devices[existingIndex] = device
                        }
                    } else {
                        devices.append(device)
                        Logger.debug("Found device: \(displayName) [\(udid)] via \(connType)", category: .device)
                    }
                }
            }
        } catch {
            Logger.debug("Failed to parse device JSON: \(error)", category: .device)
        }

        return devices
    }

    // MARK: Connection Management
    func disconnect() async {
        await sessionController.endSession()
        connectionState = .disconnected
    }

    // MARK: Developer Mode Check
    func checkDeveloperMode(for device: Device) async -> Bool {
        do {
            var args = ["-m", "pymobiledevice3", "developer", "dvt", "ls"]
            let connection = await MainActor.run {
                TunneldManager.shared.locationConnectionArguments(for: device.id)
            }
            args.append(contentsOf: connection)
            args.append("/")

            let output = try await runPython(arguments: args, timeout: 15.0)
            return !output.contains("DeveloperModeError")
        } catch {
            // A failed DVT probe is not proof that Developer Mode is off.
            return true
        }
    }

    // MARK: Python Command Execution
    /// Run Python command with proper timeout protection
    func runPython(arguments: [String], timeout: TimeInterval = 30.0) async throws -> String {
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
                    // Close both read-ends: this is the highest-volume subprocess path
                    // (usbmux discovery polling); drained-but-unclosed handles leaked
                    // thousands of pipe fds until the process hit EMFILE.
                    outputPipe.fileHandleForReading.closeFile()
                    errorPipe.fileHandleForReading.closeFile()

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

                    // Drain and close BOTH pipe read-ends on every exit path: the error
                    // pipe was never read, and neither handle was ever closed, so every
                    // pgrep/usbmux poll leaked 2-3 pipe fds — thousands under the test
                    // suite's polling, until the process hit EMFILE.
                    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                    _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    pipe.fileHandleForReading.closeFile()
                    errorPipe.fileHandleForReading.closeFile()

                    resumeLock.lock()
                    defer { resumeLock.unlock() }

                    guard !hasResumed else { return }
                    hasResumed = true

                    if didTimeout {
                        continuation.resume(throwing: DeviceError.commandFailed("Command timed out after \(timeout) seconds"))
                        return
                    }

                    let output = String(data: outputData, encoding: .utf8) ?? ""

                    continuation.resume(returning: output)
                } catch {
                    pipe.fileHandleForReading.closeFile()
                    errorPipe.fileHandleForReading.closeFile()

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

    /// Sets the connection mode and the tunnel mode it names, so the two stored settings
    /// always agree. A changed tunnel mode restarts a running tunnel.
    func setConnectionMode(_ mode: ConnectionMode) {
        connectionMode = mode
        settings.set(mode.rawValue, forKey: ConnectionSettingsMigration.connectionModeKey)
        let tunnelMode = mode.tunnelMode
        Task { @MainActor in
            let manager = TunneldManager.shared
            let previous = manager.preferredMode
            manager.preferredMode = tunnelMode
            if Self.switchRestartsTunnel(from: previous, to: tunnelMode,
                                         tunnelRunning: manager.isRunning || manager.isStarting) {
                await manager.restartTunnel()
            }
            await refreshDevices()
        }
    }

    /// A new tunnel mode restarts a running (or starting) tunnel; the same mode does not.
    /// The restart ends a held location (AppState treats it as a Stop).
    nonisolated static func switchRestartsTunnel(from previous: TunnelMode, to next: TunnelMode, tunnelRunning: Bool) -> Bool {
        previous != next && tunnelRunning
    }

    /// Refresh every live transport source on the same cadence: usbmux (USB and Network
    /// sets) first, then, in either connection mode, the mobdev2 Bonjour set when
    /// `browseBonjour` says this refresh's usbmux result leaves it something to decide.
    /// usbmux is applied before the ~5 s browse starts, so the browse never delays it, and
    /// the browse decision reads fresh usbmux sets rather than the previous refresh's.
    /// A skipped browse is neither a hit nor a miss.
    func refreshTransportAvailability(
        browseBonjour shouldBrowse: (_ usbmuxUSB: Set<String>, _ usbmuxNetwork: Set<String>) -> Bool = { _, _ in true }
    ) async {
        await refreshUsbmuxTransport()
        guard shouldBrowse(usbDirectDeviceIds, wifiDirectDeviceIds) else { return }
        _ = await observeMobdev2()
    }

    private func refreshUsbmuxTransport() async {
        do {
            let output = try await runPython(arguments: [
                "-m", "pymobiledevice3", "usbmux", "list",
            ])
            applyUsbmuxTransportObservation(output)
        } catch {
            applyUsbmuxTransportObservation("[]")
        }
    }

    /// Update USB/Wi-Fi availability from usbmux JSON. Requires several misses before dropping a link.
    private func applyUsbmuxTransportObservation(_ output: String) {
        var sawUSB = false
        var sawWiFi = false
        var observedUSBDeviceIds = Set<String>()
        var observedWiFiDeviceIds = Set<String>()

        if let jsonStart = output.firstIndex(of: "["),
           let jsonEnd = output.lastIndex(of: "]"),
           let data = String(output[jsonStart...jsonEnd]).data(using: .utf8),
           let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for item in items {
                let type = (item["ConnectionType"] as? String ?? "").lowercased()
                let deviceId = item["UniqueDeviceID"] as? String
                    ?? item["Identifier"] as? String
                if type.contains("usb") {
                    sawUSB = true
                    if let deviceId { observedUSBDeviceIds.insert(deviceId) }
                } else if type.contains("network") || type.contains("wifi") {
                    sawWiFi = true
                    if let deviceId { observedWiFiDeviceIds.insert(deviceId) }
                }
            }
        }

        if sawUSB {
            usbTransportMisses = 0
            usbTransportAvailable = true
            usbDirectDeviceIds = observedUSBDeviceIds
        } else {
            usbTransportMisses += 1
            if usbTransportMisses >= transportMissThreshold {
                usbTransportAvailable = false
                usbDirectDeviceIds = []
            }
        }

        if sawWiFi {
            wifiTransportMisses = 0
            wifiTransportAvailable = true
            wifiDirectDeviceIds = observedWiFiDeviceIds
        } else {
            wifiTransportMisses += 1
            if wifiTransportMisses >= transportMissThreshold {
                wifiTransportAvailable = false
                wifiDirectDeviceIds = []
            }
        }
    }
}
