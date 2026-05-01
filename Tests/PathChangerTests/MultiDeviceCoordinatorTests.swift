//
//  MultiDeviceCoordinatorTests.swift
//  PathChangerTests
//
//  Tests for multi-device coordination and group management
//

import XCTest
@testable import PathChanger

// MARK: - Device Group Tests

final class DeviceGroupTests: XCTestCase {
    
    func testGroupInitialization() {
        let group = DeviceGroup(name: "Test Group", deviceIds: ["device1", "device2"])
        
        XCTAssertEqual(group.name, "Test Group")
        XCTAssertEqual(group.deviceIds.count, 2)
        XCTAssertEqual(group.color, .blue)
        XCTAssertNotNil(group.id)
        XCTAssertNotNil(group.createdAt)
    }
    
    func testGroupWithCustomColor() {
        let group = DeviceGroup(name: "Red Group", color: .red)
        
        XCTAssertEqual(group.color, .red)
    }
    
    func testGroupIdentifiable() {
        let group1 = DeviceGroup(name: "Group 1")
        let group2 = DeviceGroup(name: "Group 2")
        
        XCTAssertNotEqual(group1.id, group2.id)
    }
    
    func testGroupCodable() throws {
        let group = DeviceGroup(name: "Codable Test", deviceIds: ["d1", "d2"], color: .purple)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(group)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DeviceGroup.self, from: data)
        
        XCTAssertEqual(decoded.name, group.name)
        XCTAssertEqual(decoded.deviceIds, group.deviceIds)
        XCTAssertEqual(decoded.color, group.color)
    }
}

// MARK: - Group Color Tests

final class GroupColorTests: XCTestCase {
    
    func testAllColorsHaveDisplayNames() {
        for color in DeviceGroup.GroupColor.allCases {
            XCTAssertFalse(color.displayName.isEmpty, "\(color) should have display name")
        }
    }
    
    func testColorCount() {
        XCTAssertEqual(DeviceGroup.GroupColor.allCases.count, 5)
    }
    
    func testColorCodable() throws {
        for color in DeviceGroup.GroupColor.allCases {
            let encoder = JSONEncoder()
            let data = try encoder.encode(color)
            
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(DeviceGroup.GroupColor.self, from: data)
            
            XCTAssertEqual(decoded, color)
        }
    }
}

// MARK: - Device Simulation State Tests

final class DeviceSimulationStateTests: XCTestCase {
    
    func testStateInitialization() {
        let state = DeviceSimulationState(deviceId: "test-device-123")
        
        XCTAssertEqual(state.deviceId, "test-device-123")
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.currentCoordinate)
        XCTAssertEqual(state.simulationMode, .teleport)
        XCTAssertEqual(state.speed, .driving)
        XCTAssertEqual(state.routeProgress, 0)
        XCTAssertNil(state.lastUpdateTime)
        XCTAssertNil(state.error)
    }
    
    func testStateId() {
        let state = DeviceSimulationState(deviceId: "my-device")
        XCTAssertEqual(state.id, "my-device")
    }
    
    func testStateReset() {
        let state = DeviceSimulationState(deviceId: "device")
        
        // Set some values
        state.isActive = true
        state.currentCoordinate = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        state.routeProgress = 0.5
        state.lastUpdateTime = Date()
        state.error = "Some error"
        
        // Reset
        state.reset()
        
        // Verify reset
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.currentCoordinate)
        XCTAssertEqual(state.routeProgress, 0)
        XCTAssertNil(state.lastUpdateTime)
        XCTAssertNil(state.error)
    }
}

// MARK: - Multi Device Coordinator Tests

@MainActor
final class MultiDeviceCoordinatorTests: XCTestCase {
    
    var coordinator: MultiDeviceCoordinator!
    
    override func setUp() async throws {
        coordinator = MultiDeviceCoordinator.shared
        coordinator.deselectAll()
        
        // Clear any existing groups for test isolation
        for group in coordinator.groups {
            coordinator.deleteGroup(id: group.id)
        }
    }
    
    func testSharedInstanceExists() {
        XCTAssertNotNil(MultiDeviceCoordinator.shared)
    }
    
    func testInitialState() {
        XCTAssertTrue(coordinator.selectedDeviceIds.isEmpty)
        XCTAssertTrue(coordinator.synchronizedMode)
        XCTAssertFalse(coordinator.isBatchOperationInProgress)
    }
    
    func testGetStateCreatesNewState() {
        let state = coordinator.getState(for: "new-device")
        
        XCTAssertEqual(state.deviceId, "new-device")
        XCTAssertFalse(state.isActive)
    }
    
    func testGetStateReturnsExistingState() {
        let state1 = coordinator.getState(for: "device-x")
        state1.isActive = true
        
        let state2 = coordinator.getState(for: "device-x")
        
        XCTAssertTrue(state1 === state2) // Same instance
        XCTAssertTrue(state2.isActive)
    }
    
    // MARK: Selection Tests
    
    func testToggleSelection() {
        XCTAssertFalse(coordinator.selectedDeviceIds.contains("device-a"))
        
        coordinator.toggleSelection(deviceId: "device-a")
        XCTAssertTrue(coordinator.selectedDeviceIds.contains("device-a"))
        
        coordinator.toggleSelection(deviceId: "device-a")
        XCTAssertFalse(coordinator.selectedDeviceIds.contains("device-a"))
    }
    
    func testSelectSingle() {
        coordinator.toggleSelection(deviceId: "device-1")
        coordinator.toggleSelection(deviceId: "device-2")
        
        XCTAssertEqual(coordinator.selectedDeviceIds.count, 2)
        
        coordinator.selectSingle(deviceId: "device-3")
        
        XCTAssertEqual(coordinator.selectedDeviceIds.count, 1)
        XCTAssertTrue(coordinator.selectedDeviceIds.contains("device-3"))
    }
    
    func testDeselectAll() {
        coordinator.toggleSelection(deviceId: "device-1")
        coordinator.toggleSelection(deviceId: "device-2")
        
        coordinator.deselectAll()
        
        XCTAssertTrue(coordinator.selectedDeviceIds.isEmpty)
    }
    
    // MARK: Group Tests
    
    func testCreateGroup() {
        let group = coordinator.createGroup(
            name: "Test Group",
            deviceIds: ["d1", "d2"],
            color: .green
        )
        
        XCTAssertEqual(group.name, "Test Group")
        XCTAssertEqual(group.deviceIds, ["d1", "d2"])
        XCTAssertEqual(group.color, .green)
        XCTAssertTrue(coordinator.groups.contains(where: { $0.id == group.id }))
    }
    
    func testUpdateGroup() {
        let group = coordinator.createGroup(name: "Original", deviceIds: [])
        
        coordinator.updateGroup(id: group.id, name: "Updated", color: .purple)
        
        guard let updated = coordinator.groups.first(where: { $0.id == group.id }) else {
            XCTFail("Group not found")
            return
        }
        
        XCTAssertEqual(updated.name, "Updated")
        XCTAssertEqual(updated.color, .purple)
    }
    
    func testDeleteGroup() {
        let group = coordinator.createGroup(name: "To Delete", deviceIds: [])
        let groupId = group.id
        
        XCTAssertTrue(coordinator.groups.contains(where: { $0.id == groupId }))
        
        coordinator.deleteGroup(id: groupId)
        
        XCTAssertFalse(coordinator.groups.contains(where: { $0.id == groupId }))
    }
    
    func testAddToGroup() {
        let group = coordinator.createGroup(name: "Empty Group", deviceIds: [])
        
        coordinator.addToGroup(deviceId: "new-device", groupId: group.id)
        
        guard let updated = coordinator.groups.first(where: { $0.id == group.id }) else {
            XCTFail("Group not found")
            return
        }
        
        XCTAssertTrue(updated.deviceIds.contains("new-device"))
    }
    
    func testAddToGroupPreventsDuplicates() {
        let group = coordinator.createGroup(name: "Group", deviceIds: ["device-1"])
        
        coordinator.addToGroup(deviceId: "device-1", groupId: group.id)
        
        guard let updated = coordinator.groups.first(where: { $0.id == group.id }) else {
            XCTFail("Group not found")
            return
        }
        
        XCTAssertEqual(updated.deviceIds.filter { $0 == "device-1" }.count, 1)
    }
    
    func testRemoveFromGroup() {
        let group = coordinator.createGroup(name: "Group", deviceIds: ["device-1", "device-2"])
        
        coordinator.removeFromGroup(deviceId: "device-1", groupId: group.id)
        
        guard let updated = coordinator.groups.first(where: { $0.id == group.id }) else {
            XCTFail("Group not found")
            return
        }
        
        XCTAssertFalse(updated.deviceIds.contains("device-1"))
        XCTAssertTrue(updated.deviceIds.contains("device-2"))
    }
    
    func testSelectGroup() {
        let group = coordinator.createGroup(name: "Group", deviceIds: ["d1", "d2", "d3"])
        
        coordinator.selectGroup(group)
        
        XCTAssertTrue(coordinator.selectedDeviceIds.contains("d1"))
        XCTAssertTrue(coordinator.selectedDeviceIds.contains("d2"))
        XCTAssertTrue(coordinator.selectedDeviceIds.contains("d3"))
    }
    
    func testGetGroupStates() {
        let group = coordinator.createGroup(name: "Group", deviceIds: ["d1", "d2"])
        
        let states = coordinator.getGroupStates(groupId: group.id)
        
        XCTAssertEqual(states.count, 2)
    }
}

// MARK: - Batch Operation Result Tests

final class BatchOperationResultTests: XCTestCase {
    
    func testFullSuccess() {
        let results: [String: Result<Void, Error>] = [
            "device1": .success(()),
            "device2": .success(()),
            "device3": .success(())
        ]
        
        let result = BatchOperationResult(results: results)
        
        XCTAssertEqual(result.totalDevices, 3)
        XCTAssertEqual(result.successCount, 3)
        XCTAssertEqual(result.failureCount, 0)
        XCTAssertTrue(result.isFullSuccess)
        XCTAssertFalse(result.isPartialSuccess)
        XCTAssertFalse(result.isFullFailure)
    }
    
    func testPartialSuccess() {
        let results: [String: Result<Void, Error>] = [
            "device1": .success(()),
            "device2": .failure(LocationInjectionError.deviceNotFound),
            "device3": .success(())
        ]
        
        let result = BatchOperationResult(results: results)
        
        XCTAssertEqual(result.totalDevices, 3)
        XCTAssertEqual(result.successCount, 2)
        XCTAssertEqual(result.failureCount, 1)
        XCTAssertFalse(result.isFullSuccess)
        XCTAssertTrue(result.isPartialSuccess)
        XCTAssertFalse(result.isFullFailure)
    }
    
    func testFullFailure() {
        let results: [String: Result<Void, Error>] = [
            "device1": .failure(LocationInjectionError.deviceNotFound),
            "device2": .failure(LocationInjectionError.rateLimited)
        ]
        
        let result = BatchOperationResult(results: results)
        
        XCTAssertEqual(result.totalDevices, 2)
        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.failureCount, 2)
        XCTAssertFalse(result.isFullSuccess)
        XCTAssertFalse(result.isPartialSuccess)
        XCTAssertTrue(result.isFullFailure)
    }
    
    func testSummaryMessages() {
        let successResults: [String: Result<Void, Error>] = [
            "d1": .success(()),
            "d2": .success(())
        ]
        let successResult = BatchOperationResult(results: successResults)
        XCTAssertTrue(successResult.summary.contains("Successfully"))
        
        let partialResults: [String: Result<Void, Error>] = [
            "d1": .success(()),
            "d2": .failure(LocationInjectionError.deviceNotFound)
        ]
        let partialResult = BatchOperationResult(results: partialResults)
        XCTAssertTrue(partialResult.summary.contains("1/2"))
        
        let failureResults: [String: Result<Void, Error>] = [
            "d1": .failure(LocationInjectionError.deviceNotFound)
        ]
        let failureResult = BatchOperationResult(results: failureResults)
        XCTAssertTrue(failureResult.summary.contains("Failed"))
    }
}

// MARK: - Device Selection View Model Tests

@MainActor
final class DeviceSelectionViewModelTests: XCTestCase {
    
    var viewModel: DeviceSelectionViewModel!
    
    override func setUp() async throws {
        viewModel = DeviceSelectionViewModel()
        viewModel.devices = [
            Device(id: "device-1", displayName: "Device 1", connectionType: .usb),
            Device(id: "device-2", displayName: "Device 2", connectionType: .wifi)
        ]
    }
    
    func testInitialState() {
        XCTAssertEqual(viewModel.selectedCount, 0)
        XCTAssertFalse(viewModel.canCreateGroup)
    }
    
    func testToggleDevice() {
        viewModel.toggleDevice(viewModel.devices[0])
        XCTAssertEqual(viewModel.selectedCount, 1)
        
        viewModel.toggleDevice(viewModel.devices[0])
        XCTAssertEqual(viewModel.selectedCount, 0)
    }
    
    func testCanCreateGroup() {
        XCTAssertFalse(viewModel.canCreateGroup)
        
        // Need at least 2 devices and a name
        viewModel.toggleDevice(viewModel.devices[0])
        viewModel.toggleDevice(viewModel.devices[1])
        viewModel.groupName = "Test Group"
        
        XCTAssertTrue(viewModel.canCreateGroup)
    }
    
    func testCannotCreateGroupWithEmptyName() {
        viewModel.toggleDevice(viewModel.devices[0])
        viewModel.toggleDevice(viewModel.devices[1])
        viewModel.groupName = ""
        
        XCTAssertFalse(viewModel.canCreateGroup)
    }
    
    func testCannotCreateGroupWithOneDevice() {
        viewModel.toggleDevice(viewModel.devices[0])
        viewModel.groupName = "Solo Group"
        
        XCTAssertFalse(viewModel.canCreateGroup)
    }
    
    func testDeselectAll() {
        viewModel.toggleDevice(viewModel.devices[0])
        viewModel.toggleDevice(viewModel.devices[1])
        
        viewModel.deselectAll()
        
        XCTAssertEqual(viewModel.selectedCount, 0)
    }
}

// MARK: - Array Chunking Tests

final class ArrayChunkingTests: XCTestCase {
    
    func testChunkingEvenDivision() {
        let array = [1, 2, 3, 4, 5, 6]
        let chunks = array.chunked(into: 2)
        
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0], [1, 2])
        XCTAssertEqual(chunks[1], [3, 4])
        XCTAssertEqual(chunks[2], [5, 6])
    }
    
    func testChunkingUnevenDivision() {
        let array = [1, 2, 3, 4, 5]
        let chunks = array.chunked(into: 2)
        
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0], [1, 2])
        XCTAssertEqual(chunks[1], [3, 4])
        XCTAssertEqual(chunks[2], [5])
    }
    
    func testChunkingSingleChunk() {
        let array = [1, 2, 3]
        let chunks = array.chunked(into: 10)
        
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], [1, 2, 3])
    }
    
    func testChunkingEmptyArray() {
        let array: [Int] = []
        let chunks = array.chunked(into: 2)
        
        XCTAssertTrue(chunks.isEmpty)
    }
    
    func testChunkingSizeOne() {
        let array = [1, 2, 3]
        let chunks = array.chunked(into: 1)
        
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0], [1])
        XCTAssertEqual(chunks[1], [2])
        XCTAssertEqual(chunks[2], [3])
    }
}
