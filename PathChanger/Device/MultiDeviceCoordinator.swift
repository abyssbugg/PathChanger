//
//  MultiDeviceCoordinator.swift
//  PathChanger
//
//  Manages simultaneous location simulation on multiple devices
//  Supports device groups, synchronized operations, and per-device state
//

import Foundation
import Combine

// MARK: - Device Group

/// A group of devices that can be operated on together
struct DeviceGroup: Identifiable, Codable {
    let id: UUID
    var name: String
    var deviceIds: [String]
    var color: GroupColor
    var createdAt: Date

    enum GroupColor: String, CaseIterable, Codable {
        case blue
        case green
        case orange
        case purple
        case red

        var displayName: String {
            rawValue.capitalized
        }
    }

    init(name: String, deviceIds: [String] = [], color: GroupColor = .blue) {
        self.id = UUID()
        self.name = name
        self.deviceIds = deviceIds
        self.color = color
        self.createdAt = Date()
    }
}

// MARK: - Device Simulation State

/// Per-device simulation state
class DeviceSimulationState: ObservableObject, Identifiable {
    let deviceId: String

    @Published var isActive: Bool = false
    @Published var currentCoordinate: LocationCoordinate?
    @Published var simulationMode: SimulationModeType = .teleport
    @Published var speed: SimulationSpeed = .driving
    @Published var routeProgress: Double = 0
    @Published var lastUpdateTime: Date?
    @Published var error: String?

    var id: String { deviceId }

    init(deviceId: String) {
        self.deviceId = deviceId
    }

    func reset() {
        isActive = false
        currentCoordinate = nil
        routeProgress = 0
        lastUpdateTime = nil
        error = nil
    }
}

// MARK: - Multi-Device Coordinator

/// Coordinates location simulation across multiple devices
@MainActor
class MultiDeviceCoordinator: ObservableObject {

    // MARK: Singleton
    static let shared = MultiDeviceCoordinator()

    // MARK: Published State

    /// All device groups
    @Published var groups: [DeviceGroup] = []

    /// Per-device simulation states
    @Published private(set) var deviceStates: [String: DeviceSimulationState] = [:]

    /// Currently selected devices for batch operations
    @Published var selectedDeviceIds: Set<String> = []

    /// Whether synchronized mode is enabled (all selected devices get same location)
    @Published var synchronizedMode: Bool = true

    /// Active batch operation
    @Published var isBatchOperationInProgress: Bool = false

    /// Maximum concurrent device operations
    let maxConcurrentOperations: Int = 5

    // MARK: Private Properties

    private let locationBridge: DevLocationBridge
    private var cancellables = Set<AnyCancellable>()
    private let persistenceKey = "multiDeviceGroups"

    // MARK: Initialization

    private init(locationBridge: DevLocationBridge = DevLocationBridge()) {
        self.locationBridge = locationBridge
        loadGroups()
    }

    // MARK: Device State Management

    /// Get or create state for a device
    func getState(for deviceId: String) -> DeviceSimulationState {
        if let existing = deviceStates[deviceId] {
            return existing
        }

        let state = DeviceSimulationState(deviceId: deviceId)
        deviceStates[deviceId] = state
        return state
    }

    /// Get states for selected devices
    func getSelectedStates() -> [DeviceSimulationState] {
        selectedDeviceIds.compactMap { deviceStates[$0] }
    }

    /// Get states for a group
    func getGroupStates(groupId: UUID) -> [DeviceSimulationState] {
        guard let group = groups.first(where: { $0.id == groupId }) else { return [] }
        return group.deviceIds.map { getState(for: $0) }
    }

    // MARK: Selection Management

    /// Toggle device selection
    func toggleSelection(deviceId: String) {
        if selectedDeviceIds.contains(deviceId) {
            selectedDeviceIds.remove(deviceId)
        } else {
            selectedDeviceIds.insert(deviceId)
            // Ensure state exists
            _ = getState(for: deviceId)
        }
    }

    /// Select all devices in a group
    func selectGroup(_ group: DeviceGroup) {
        for deviceId in group.deviceIds {
            selectedDeviceIds.insert(deviceId)
            _ = getState(for: deviceId)
        }
    }

    /// Deselect all devices
    func deselectAll() {
        selectedDeviceIds.removeAll()
    }

    /// Select a single device (clears other selections)
    func selectSingle(deviceId: String) {
        selectedDeviceIds = [deviceId]
        _ = getState(for: deviceId)
    }

    // MARK: Group Management

    /// Create a new device group
    func createGroup(name: String, deviceIds: [String], color: DeviceGroup.GroupColor = .blue) -> DeviceGroup {
        let group = DeviceGroup(name: name, deviceIds: deviceIds, color: color)
        groups.append(group)
        saveGroups()
        return group
    }

    /// Update an existing group
    func updateGroup(id: UUID, name: String? = nil, deviceIds: [String]? = nil, color: DeviceGroup.GroupColor? = nil) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }

        if let name = name {
            groups[index].name = name
        }
        if let deviceIds = deviceIds {
            groups[index].deviceIds = deviceIds
        }
        if let color = color {
            groups[index].color = color
        }

        saveGroups()
    }

    /// Delete a group
    func deleteGroup(id: UUID) {
        groups.removeAll { $0.id == id }
        saveGroups()
    }

    /// Add device to group
    func addToGroup(deviceId: String, groupId: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }

        if !groups[index].deviceIds.contains(deviceId) {
            groups[index].deviceIds.append(deviceId)
            saveGroups()
        }
    }

    /// Remove device from group
    func removeFromGroup(deviceId: String, groupId: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }

        groups[index].deviceIds.removeAll { $0 == deviceId }
        saveGroups()
    }

    // MARK: Batch Operations

    /// Set location on all selected devices
    func setLocationOnSelected(
        coordinate: LocationCoordinate,
        devices: [Device]
    ) async -> [String: Result<Void, Error>] {
        guard !selectedDeviceIds.isEmpty else { return [:] }

        isBatchOperationInProgress = true
        defer { isBatchOperationInProgress = false }

        var results: [String: Result<Void, Error>] = [:]

        // Filter to selected devices only
        let targetDevices = devices.filter { selectedDeviceIds.contains($0.id) }

        // Process in batches to avoid overwhelming the system
        let chunks = targetDevices.chunked(into: maxConcurrentOperations)

        for chunk in chunks {
            await withTaskGroup(of: (String, Result<Void, Error>).self) { group in
                for device in chunk {
                    group.addTask {
                        do {
                            // Legacy fire-and-forget path: acknowledgement intentionally not consumed (receipts govern the five-mode path; PRODUCT_REQUIREMENTS.md §7).
                            let _ = try await self.locationBridge.setLocation(coordinate, for: device)

                            // Update device state
                            await MainActor.run {
                                let state = self.getState(for: device.id)
                                state.currentCoordinate = coordinate
                                state.lastUpdateTime = Date()
                                state.error = nil
                            }

                            return (device.id, .success(()))
                        } catch {
                            await MainActor.run {
                                let state = self.getState(for: device.id)
                                state.error = error.localizedDescription
                            }
                            return (device.id, .failure(error))
                        }
                    }
                }

                for await result in group {
                    results[result.0] = result.1
                }
            }
        }

        return results
    }

    /// Set location on a specific group
    func setLocationOnGroup(
        groupId: UUID,
        coordinate: LocationCoordinate,
        devices: [Device]
    ) async -> [String: Result<Void, Error>] {
        guard let group = groups.first(where: { $0.id == groupId }) else { return [:] }

        // Temporarily set selection to group devices
        let previousSelection = selectedDeviceIds
        selectedDeviceIds = Set(group.deviceIds)

        let results = await setLocationOnSelected(coordinate: coordinate, devices: devices)

        // Restore previous selection
        selectedDeviceIds = previousSelection

        return results
    }

    /// Clear location on all selected devices
    func clearLocationOnSelected(devices: [Device]) async -> [String: Result<Void, Error>] {
        guard !selectedDeviceIds.isEmpty else { return [:] }

        isBatchOperationInProgress = true
        defer { isBatchOperationInProgress = false }

        var results: [String: Result<Void, Error>] = [:]

        let targetDevices = devices.filter { selectedDeviceIds.contains($0.id) }

        await withTaskGroup(of: (String, Result<Void, Error>).self) { group in
            for device in targetDevices {
                group.addTask {
                    do {
                        try await self.locationBridge.clearLocation(for: device)

                        await MainActor.run {
                            let state = self.getState(for: device.id)
                            state.reset()
                        }

                        return (device.id, .success(()))
                    } catch {
                        return (device.id, .failure(error))
                    }
                }
            }

            for await result in group {
                results[result.0] = result.1
            }
        }

        return results
    }

    // MARK: Synchronized Simulation

    /// Start synchronized simulation on all selected devices
    func startSynchronizedRoute(
        waypoints: [LocationCoordinate],
        speed: SimulationSpeed,
        devices: [Device]
    ) async {
        guard synchronizedMode else { return }

        for deviceId in selectedDeviceIds {
            let state = getState(for: deviceId)
            state.isActive = true
            state.simulationMode = .route
            state.speed = speed
            state.routeProgress = 0
        }

        // Note: Actual synchronized simulation would require a timer-based
        // coordinator that updates all devices at once. This is a placeholder
        // for the architecture.
    }

    // MARK: Persistence

    private func saveGroups() {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    private func loadGroups() {
        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let decoded = try? JSONDecoder().decode([DeviceGroup].self, from: data) {
            groups = decoded
        }
    }
}

// MARK: - Array Chunking Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Device Selection View Model

/// View model for multi-device selection UI
@MainActor
class DeviceSelectionViewModel: ObservableObject {

    @Published var devices: [Device] = []
    @Published var selectedIds: Set<String> = []
    @Published var groupName: String = ""
    @Published var selectedColor: DeviceGroup.GroupColor = .blue

    private let coordinator: MultiDeviceCoordinator

    init(coordinator: MultiDeviceCoordinator? = nil) {
        // Resolve `.shared` inside the initializer body: as a default argument it would be
        // evaluated in the caller's (possibly nonisolated) context.
        let resolved = coordinator ?? .shared
        self.coordinator = resolved

        // Sync selection with coordinator
        resolved.$selectedDeviceIds
            .assign(to: &$selectedIds)
    }

    var selectedCount: Int {
        selectedIds.count
    }

    var canCreateGroup: Bool {
        !groupName.isEmpty && selectedIds.count >= 2
    }

    func toggleDevice(_ device: Device) {
        coordinator.toggleSelection(deviceId: device.id)
    }

    func selectAll() {
        for device in devices {
            coordinator.toggleSelection(deviceId: device.id)
        }
    }

    func deselectAll() {
        coordinator.deselectAll()
    }

    func createGroup() -> DeviceGroup? {
        guard canCreateGroup else { return nil }

        let group = coordinator.createGroup(
            name: groupName,
            deviceIds: Array(selectedIds),
            color: selectedColor
        )

        // Reset form
        groupName = ""
        selectedColor = .blue

        return group
    }
}

// MARK: - Batch Operation Result

/// Result of a batch operation across multiple devices
struct BatchOperationResult {
    let totalDevices: Int
    let successCount: Int
    let failureCount: Int
    let errors: [String: Error]

    var isFullSuccess: Bool {
        failureCount == 0
    }

    var isPartialSuccess: Bool {
        successCount > 0 && failureCount > 0
    }

    var isFullFailure: Bool {
        successCount == 0 && failureCount > 0
    }

    var summary: String {
        if isFullSuccess {
            return "Successfully updated \(successCount) device(s)"
        } else if isPartialSuccess {
            return "Updated \(successCount)/\(totalDevices) devices (\(failureCount) failed)"
        } else {
            return "Failed to update all \(totalDevices) device(s)"
        }
    }

    init(results: [String: Result<Void, Error>]) {
        self.totalDevices = results.count

        var successCount = 0
        var errors: [String: Error] = [:]

        for (deviceId, result) in results {
            switch result {
            case .success:
                successCount += 1
            case .failure(let error):
                errors[deviceId] = error
            }
        }

        self.successCount = successCount
        self.failureCount = results.count - successCount
        self.errors = errors
    }
}
