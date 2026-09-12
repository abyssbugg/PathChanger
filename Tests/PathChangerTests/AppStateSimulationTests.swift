//
//  AppStateSimulationTests.swift
//  PathChangerTests
//
//  Multi-Spot waypoint editing and Play dispatch without a live device.
//

import XCTest
@testable import PathChanger

@MainActor
final class AppStateSimulationTests: XCTestCase {

    private func makeState() -> AppState {
        AppState(startBackgroundServices: false)
    }

    private let first = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
    private let second = LocationCoordinate(latitude: 35.6772, longitude: 139.6513)

    func testAddRouteWaypointAppendsWithoutInjecting() {
        let state = makeState()

        state.addRouteWaypoint(first)
        state.addRouteWaypoint(second)

        XCTAssertEqual(state.currentRoute, [first, second])
        XCTAssertEqual(state.targetLocation, second)
        XCTAssertFalse(state.isSimulating)
    }

    func testRemoveLastRouteWaypoint() {
        let state = makeState()
        state.addRouteWaypoint(first)
        state.addRouteWaypoint(second)

        state.removeLastRouteWaypoint()

        XCTAssertEqual(state.currentRoute, [first])
        XCTAssertEqual(state.routeProgress, 0)
    }

    func testClearRouteEmptiesWaypoints() {
        let state = makeState()
        state.addRouteWaypoint(first)
        state.addRouteWaypoint(second)
        state.routeProgress = 0.4

        state.clearRoute()

        XCTAssertTrue(state.currentRoute.isEmpty)
        XCTAssertEqual(state.routeProgress, 0)
    }

    func testStartSimulationWithoutDeviceDoesNotMarkSimulating() async {
        let state = makeState()
        state.activeMode = .route
        state.addRouteWaypoint(first)
        state.addRouteWaypoint(second)

        await state.startSimulation()

        XCTAssertFalse(state.isSimulating)
    }

    func testStartSimulationRouteWithoutTwoSpotsSetsError() async {
        let state = makeState()
        state.selectedDevice = Device(id: "00000000-0000000000000000", displayName: "Test")
        state.isTunneldRunning = true
        state.activeMode = .route
        state.addRouteWaypoint(first)

        await state.startSimulation()

        XCTAssertEqual(state.lastError, "Add at least two spots on the map")
        XCTAssertFalse(state.isSimulating)
    }

    func testStartSimulationJoystickWithoutStartSetsError() async {
        let state = makeState()
        state.selectedDevice = Device(id: "00000000-0000000000000000", displayName: "Test")
        state.isTunneldRunning = true
        state.activeMode = .joystick

        await state.startSimulation()

        XCTAssertEqual(state.lastError, "Tap the map to set a starting location")
        XCTAssertFalse(state.isSimulating)
    }

    func testUpdateJoystickDirectionStoresVector() {
        let state = makeState()
        let direction = CGPoint(x: 0.4, y: -0.6)

        state.updateJoystickDirection(direction)

        XCTAssertEqual(state.joystickDirection.x, direction.x, accuracy: 1e-9)
        XCTAssertEqual(state.joystickDirection.y, direction.y, accuracy: 1e-9)
    }

    func testStageTeleportUpdatesTargetWithoutStartingSimulation() {
        let state = makeState()

        state.stageLocation(first, for: .teleport)

        XCTAssertEqual(state.targetLocation, first)
        XCTAssertEqual(state.currentRoute, [first])
        XCTAssertFalse(state.isSimulating)
        XCTAssertNil(state.currentLocation)
    }

    func testStageJumpAppendsWithoutStartingSimulation() {
        let state = makeState()

        state.stageLocation(first, for: .jump)
        state.stageLocation(second, for: .jump)

        XCTAssertEqual(state.currentRoute, [first, second])
        XCTAssertEqual(state.targetLocation, second)
        XCTAssertFalse(state.isSimulating)
    }

    func testHistoryEligibilityRequiresConnectionAndValidPlan() {
        let accepted = SimulationStartPlan.teleport(first)
        let rejected = SimulationStartPlan.failed("No target")

        XCTAssertTrue(LocationHistoryPolicy.shouldRecord(canStartSimulation: true, plan: accepted))
        XCTAssertFalse(LocationHistoryPolicy.shouldRecord(canStartSimulation: false, plan: accepted))
        XCTAssertFalse(LocationHistoryPolicy.shouldRecord(canStartSimulation: true, plan: rejected))
    }

    func testMockTravelSpeedsMatchCanonicalValues() {
        let state = makeState()

        XCTAssertEqual(state.mockMetersPerSecond(for: .walking), 1.6)
        XCTAssertEqual(state.mockMetersPerSecond(for: .cycling), 5.4)
        XCTAssertEqual(state.mockMetersPerSecond(for: .fast), 11.2)
        XCTAssertEqual(state.mockMetersPerSecond(for: .driving), 15.6)
    }

    func testTunnelTargetUsesSelectedUDIDWhenAlreadyCanonical() {
        let state = makeState()
        let udid = "00008130-000C5144019A001C"
        state.selectedDevice = Device(
            id: udid,
            displayName: "🖇️ (iOS 27.0)",
            connectionType: .wifi,
            productType: "iPhone16,2",
            productVersion: "27.0",
            deviceName: "🖇️"
        )

        XCTAssertEqual(state.tunnelTargetDeviceId(), udid)
    }

    func testTunnelTargetFallsBackToMatchingDiscoveredUDID() {
        let state = makeState()
        let udid = "00008130-000C5144019A001C"
        state.selectedDevice = Device(
            id: "192.168.8.138",
            displayName: "🖇️ (iOS 27.0)",
            connectionType: .wifi,
            productType: "iPhone16,2",
            productVersion: "27.0",
            deviceName: "🖇️"
        )
        state.availableDevices = [
            state.selectedDevice!,
            Device(
                id: udid,
                displayName: "🖇️ (iOS 27.0)",
                connectionType: .wifi,
                productType: "iPhone16,2",
                productVersion: "27.0",
                deviceName: "🖇️"
            ),
        ]

        XCTAssertEqual(state.tunnelTargetDeviceId(), udid)
    }

    func testTunnelTargetFallsBackToSingleVisibleUDID() {
        let state = makeState()
        let udid = "00008130-000C5144019A001C"
        state.selectedDevice = Device(
            id: "2c0f:f5c0:600:ac13:1839:d9a8:fd2b:a7ad",
            displayName: "Paired iOS Device",
            connectionType: .wifi
        )
        state.availableDevices = [
            state.selectedDevice!,
            Device(id: udid, displayName: "Paired iOS Device", connectionType: .wifi),
        ]

        XCTAssertEqual(state.tunnelTargetDeviceId(), udid)
    }

    // MARK: - Task 3: Location Session Model Tests

    @MainActor
    func testCooldownCannotCreateFalseActiveState() {
        let state = makeState()
        let target = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)

        state.locationSessionCoordinator.select(target, mode: .teleport)

        XCTAssertFalse(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, target)
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
    }


    private func makeAcknowledgementState(
        injector: FakeLocationInjector,
        mode: AppMode
    ) -> (AppState, LocationSessionIdentity) {
        let state = AppState(startBackgroundServices: false, locationInjector: injector)
        state.selectedDevice = Device(id: "ack-device", displayName: "Ack Device", connectionType: .usb)
        state.isTunneldRunning = true
        state.activeMode = mode
        let session = LocationSessionIdentity(
            stableDeviceID: "ack-device",
            transport: .usb,
            endpointClass: .direct,
            generation: 1
        )
        state.locationSessionCoordinator.connectionReady(session)
        return (state, session)
    }

    func testTeleportDoesNotBecomeActiveBeforeAcknowledgement() async {
        let fake = FakeLocationInjector()
        let (state, session) = makeAcknowledgementState(injector: fake, mode: .teleport)
        state.stageLocation(first, for: .teleport)

        let application = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()

        XCTAssertFalse(state.isSimulating)
        XCTAssertNil(state.currentLocation)
        XCTAssertFalse(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, first)

        await fake.releaseNextApplication(session: session)
        await application.value

        XCTAssertTrue(state.isSimulating)
        XCTAssertEqual(state.currentLocation, first)
        XCTAssertTrue(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.locationSessionCoordinator.state.lastAcknowledgedReceipt?.coordinate, first)
    }

    func testJumpAdvancesExactlyOneHopAfterAcknowledgement() async {
        let fake = FakeLocationInjector()
        let (state, session) = makeAcknowledgementState(injector: fake, mode: .jump)
        state.stageLocation(first, for: .jump)
        state.stageLocation(second, for: .jump)

        let application = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()

        XCTAssertEqual(state.jumpIndex, 0)
        XCTAssertNil(state.currentLocation)
        XCTAssertFalse(state.isSimulating)

        await fake.releaseNextApplication(session: session)
        await application.value

        XCTAssertEqual(state.jumpIndex, 1)
        XCTAssertEqual(state.currentLocation, first)
        XCTAssertTrue(state.isSimulating)
        let calls = await fake.calls()
        XCTAssertEqual(calls.filter { if case .apply = $0 { return true }; return false }.count, 1)
    }

    func testQueuedJumpDoesNotAdvanceProgressOrClaimActiveLocation() async {
        let fake = FakeLocationInjector()
        let (state, session) = makeAcknowledgementState(injector: fake, mode: .jump)
        state.stageLocation(first, for: .jump)

        let application = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session, outcome: .queued)
        await application.value

        XCTAssertEqual(state.jumpIndex, 0)
        XCTAssertNil(state.currentLocation)
        XCTAssertFalse(state.isSimulating)
        XCTAssertFalse(state.locationSessionCoordinator.state.application.isActive)
        XCTAssertEqual(state.locationSessionCoordinator.state.desiredLocation, first)
        XCTAssertNil(state.locationSessionCoordinator.state.lastAcknowledgedReceipt)
        XCTAssertNotNil(state.statusMessage)
    }
}
