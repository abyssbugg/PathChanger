//
//  AppStateTransientRecoveryTests.swift
//  PathChangerTests
//
//  Focused coverage for AppState-owned transient tunnel recovery and
//  same-UDID session restoration.
//

import XCTest
@testable import PathChanger

@MainActor
final class AppStateTransientRecoveryTests: XCTestCase {

    func testTransientRecoveryRestoresPausedRouteSessionForSameUDID() async throws {
        let appState = AppState()
        let device = Device(
            id: "RECOVERY-UDID-1",
            displayName: "Recovery iPhone",
            connectionType: .wifi,
            productVersion: "18.0"
        )
        let route = [
            LocationCoordinate(latitude: 37.3317, longitude: -122.0301),
            LocationCoordinate(latitude: 37.3327, longitude: -122.0311),
            LocationCoordinate(latitude: 37.3337, longitude: -122.0321)
        ]
        let current = LocationCoordinate(latitude: 37.3320, longitude: -122.0305)
        let reason = "Tunnel invalidated: No route to host"
        var observedReasons: [String] = []

        appState.selectDevice(device)
        appState.currentRoute = route
        appState.currentLocation = current
        appState.targetLocation = route.first
        appState.routeProgress = 0.45
        appState.isSimulating = true
        appState.isPaused = true
        appState.simulationSpeed = .walking
        appState.simulationEngine.currentMode = .route
        appState.simulationEngine.speed = .walking
        appState.testSetSkipsDeviceRefreshDuringTransientRecovery(true)
        appState.testSetTransientRecoveryHandler { recoveryReason in
            observedReasons.append(recoveryReason)
            return true
        }

        appState.testCaptureResumableSessionSnapshot(mode: .route)
        appState.testBeginTransientTransportRecovery(reason: reason)

        try await waitUntil {
            appState.statusMessage == "Session restored after tunnel recovery (paused)"
        }

        XCTAssertEqual(observedReasons, [reason])
        XCTAssertEqual(appState.selectedDevice?.id, device.id)
        XCTAssertEqual(appState.simulationEngine.currentMode, .route)
        XCTAssertEqual(appState.simulationEngine.state, .paused)
        XCTAssertTrue(appState.isSimulating)
        XCTAssertTrue(appState.isPaused)
        XCTAssertNil(appState.lastError)
        XCTAssertFalse(appState.testHasTransientRecoveryTask)
    }

    func testTransientRecoveryRequestsAreSerialized() async throws {
        let appState = AppState()
        let device = Device(
            id: "RECOVERY-UDID-2",
            displayName: "Recovery iPhone",
            connectionType: .wifi,
            productVersion: "18.0"
        )
        let current = LocationCoordinate(latitude: 37.3317, longitude: -122.0301)
        var recoveryCallCount = 0

        appState.selectDevice(device)
        appState.currentLocation = current
        appState.targetLocation = current
        appState.isSimulating = true
        appState.isPaused = true
        appState.simulationEngine.currentMode = .joystick
        appState.testSetSkipsDeviceRefreshDuringTransientRecovery(true)
        appState.testSetTransientRecoveryHandler { _ in
            recoveryCallCount += 1
            try? await Task.sleep(nanoseconds: 100_000_000)
            return true
        }

        appState.testCaptureResumableSessionSnapshot(mode: .joystick)
        appState.testBeginTransientTransportRecovery(reason: "Tunnel invalidated: No route to host")
        appState.testBeginTransientTransportRecovery(reason: "Tunnel invalidated: BrokenPipe")

        try await waitUntil {
            !appState.testHasTransientRecoveryTask
        }

        XCTAssertEqual(recoveryCallCount, 1)
        XCTAssertEqual(appState.simulationEngine.currentMode, .joystick)
        XCTAssertEqual(appState.simulationEngine.state, .paused)
        XCTAssertNil(appState.lastError)
    }

    private func waitUntil(
        timeout: TimeInterval = 2.0,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}
