//
//  LocationSessionStateTests.swift
//  PathChangerTests
//
//  Created by Rovo Dev on 2026-09-12.
//

import XCTest
@testable import PathChanger

final class LocationSessionStateTests: XCTestCase {

    // MARK: - Deterministic Test Fixtures

    let deterministicUUID = UUID(uuidString: "12345678-1234-1234-1234-123456789012")!
    let deterministicDate = Date(timeIntervalSince1970: 1000000)
    let deterministicSessionID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    let deterministicReceiptID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!

    func makeCoordinate(lat: Double = 37.7749, lon: Double = -122.4194) -> LocationCoordinate {
        LocationCoordinate(latitude: lat, longitude: lon)
    }

    func makeReceipt(requestID: UUID? = nil, outcome: LocationInjectionOutcome = .applied) -> LocationInjectionReceipt {
        LocationInjectionReceipt(
            requestID: requestID ?? deterministicReceiptID,
            session: deterministicSessionID,
            coordinate: makeCoordinate(),
            completedAt: deterministicDate,
            outcome: outcome
        )
    }

    func makeIdentity(generation: UInt64 = 1) -> LocationSessionIdentity {
        LocationSessionIdentity(
            stableDeviceID: "device123",
            transport: .wifi,
            endpointClass: .direct,
            generation: generation
        )
    }

    // MARK: - Test 1: LocationMode raw values and AppMode mapping

    func testLocationModeRawValuesAndAppModeMapping() {
        // Exact ordered raw values
        let modeRawValues = LocationMode.allCases.map(\.rawValue)
        XCTAssertEqual(
            modeRawValues,
            ["teleport", "jumpTeleport", "twoSpot", "multiSpot", "joystick"],
            "LocationMode allCases must have exact ordered raw values"
        )

        XCTAssertEqual(AppMode.teleport.locationMode, .teleport)
        XCTAssertEqual(AppMode.jump.locationMode, .jumpTeleport)
        XCTAssertEqual(AppMode.twospot.locationMode, .twoSpot)
        XCTAssertEqual(AppMode.route.locationMode, .multiSpot)
        XCTAssertEqual(AppMode.joystick.locationMode, .joystick)
        XCTAssertNil(AppMode.settings.locationMode)
    }

    // MARK: - Test 2: Initial LocationSessionState with desired coordinate

    func testInitialLocationSessionStateWithDesiredCoordinate() {
        let desired = makeCoordinate(lat: 51.5074, lon: -0.1278)
        var state = LocationSessionState()
        state.desiredLocation = desired

        XCTAssertEqual(state.desiredLocation, desired, "desiredLocation must be set")
        XCTAssertNil(state.lastAcknowledgedReceipt, "lastAcknowledgedReceipt must start nil")
        XCTAssertEqual(state.connection, .unavailable, "connection must default to unavailable")
        XCTAssertEqual(state.application, .idle, "application must default to idle")
        XCTAssertEqual(state.movement, .idle, "movement must default to idle")
    }

    // MARK: - Test 3: applying(requestID, coordinate) preserves desired, isActive false

    func testApplyingPreservesDesiredAndIsActiveFalse() {
        var state = LocationSessionState()
        let desired = makeCoordinate(lat: 48.8566, lon: 2.3522)
        state.desiredLocation = desired

        state.application = .applying(requestID: deterministicUUID, coordinate: makeCoordinate())
        XCTAssertEqual(state.desiredLocation, desired, "desiredLocation survives .applying")

        if case .applying(let reqID, let coord) = state.application {
            XCTAssertEqual(reqID, deterministicUUID)
            XCTAssertEqual(coord.latitude, 37.7749)
        } else {
            XCTFail("application should be .applying")
        }
    }

    // MARK: - Test 4: acknowledged active(receipt) records lastAcknowledgedReceipt, isActive true

    func testAcknowledgedActiveRecordsReceiptAndIsActiveTrue() {
        var state = LocationSessionState()
        let desired = makeCoordinate()
        state.desiredLocation = desired

        let receipt = makeReceipt()
        state.lastAcknowledgedReceipt = receipt
        state.application = .active(receipt: receipt)

        XCTAssertEqual(state.lastAcknowledgedReceipt, receipt, "lastAcknowledgedReceipt must be recorded")
        XCTAssertEqual(state.desiredLocation, desired, "desiredLocation survives .active")
        XCTAssertTrue(state.application.isActive, "isActive must be true for .active case")
        
        if case .active(let r) = state.application {
            XCTAssertEqual(r.requestID, receipt.requestID)
        } else {
            XCTFail("application should be .active")
        }
    }

    // MARK: - Test 5: paused then completed movement carries mode; desired and receipt held

    func testMovementPausedThenCompletedCarriesModeWithDesiredAndReceiptHeld() {
        var state = LocationSessionState()
        let desired = makeCoordinate()
        let receipt = makeReceipt()

        state.desiredLocation = desired
        state.lastAcknowledgedReceipt = receipt
        state.application = .active(receipt: receipt)

        // Transition to paused
        state.movement = .paused(.twoSpot)
        XCTAssertEqual(state.desiredLocation, desired, "desiredLocation survives .paused")
        XCTAssertEqual(state.lastAcknowledgedReceipt?.requestID, receipt.requestID)

        if case .paused(let mode) = state.movement {
            XCTAssertEqual(mode, .twoSpot, "paused must carry twoSpot mode")
        } else {
            XCTFail("movement should be .paused")
        }

        // Transition to completed
        state.movement = .completed(.twoSpot)
        XCTAssertEqual(state.desiredLocation, desired, "desiredLocation survives .completed")
        XCTAssertEqual(state.lastAcknowledgedReceipt?.requestID, receipt.requestID)

        if case .completed(let mode) = state.movement {
            XCTAssertEqual(mode, .twoSpot, "completed must carry twoSpot mode")
        } else {
            XCTFail("movement should be .completed")
        }
    }

    // MARK: - Test 6: connection ready→reconnecting; application uncertain; desired/receipt preserved

    func testConnectionTransitionsPreserveDesiredAndReceipt() {
        var state = LocationSessionState()
        let desired = makeCoordinate(lat: 35.6762, lon: 139.6503)
        let receipt = makeReceipt()
        let identity = makeIdentity()

        state.desiredLocation = desired
        state.lastAcknowledgedReceipt = receipt
        state.connection = .ready(identity: identity)

        // Ready state: desired and receipt held
        XCTAssertEqual(state.desiredLocation, desired)
        XCTAssertEqual(state.lastAcknowledgedReceipt?.requestID, receipt.requestID)

        // Transition to reconnecting
        state.connection = .reconnecting(previousGeneration: 1, attempt: 1)
        XCTAssertEqual(state.desiredLocation, desired, "desiredLocation survives .reconnecting")
        XCTAssertEqual(state.lastAcknowledgedReceipt?.requestID, receipt.requestID)

        // Application uncertain preserves receipt context
        state.application = .uncertain(lastReceipt: receipt, reason: "network issue")
        XCTAssertEqual(state.desiredLocation, desired, "desiredLocation survives .uncertain")
        XCTAssertEqual(state.lastAcknowledgedReceipt?.requestID, receipt.requestID)
    }

    // MARK: - Test 7: lost/failed application preserve desired, isActive false

    func testLostAndFailedApplicationPreserveDesiredWithIsActiveFalse() {
        var state = LocationSessionState()
        let desired = makeCoordinate()
        state.desiredLocation = desired

        // Lost application
        state.application = .lost("device offline")
        XCTAssertEqual(state.desiredLocation, desired, "desiredLocation survives .lost")
        XCTAssertFalse(state.application.isActive, "isActive must be false for .lost")

        if case .lost(let reason) = state.application {
            XCTAssertEqual(reason, "device offline")
        } else {
            XCTFail("application should be .lost")
        }

        // Failed application
        state.application = .failed("injection timeout")
        XCTAssertEqual(state.desiredLocation, desired, "desiredLocation survives .failed")
        XCTAssertFalse(state.application.isActive, "isActive must be false for .failed")

        if case .failed(let error) = state.application {
            XCTAssertEqual(error, "injection timeout")
        } else {
            XCTFail("application should be .failed")
        }
    }

    // MARK: - Test 8: recovery to ready preserves desired/receipt and generation identity

    func testRecoveryToReadyPreservesDesiredReceiptAndIdentity() {
        var state = LocationSessionState()
        let desired = makeCoordinate(lat: 48.8566, lon: 2.3522)
        let receipt = makeReceipt()
        let identity = makeIdentity(generation: 1)

        state.desiredLocation = desired
        state.lastAcknowledgedReceipt = receipt
        state.connection = .failed("timeout")

        // Recovery back to ready
        state.connection = .ready(identity: identity)
        XCTAssertEqual(state.desiredLocation, desired, "desiredLocation preserved after recovery")
        XCTAssertEqual(state.lastAcknowledgedReceipt?.requestID, receipt.requestID, "receipt preserved after recovery")

        if case .ready(let recoveredIdentity) = state.connection {
            XCTAssertEqual(recoveredIdentity.generation, 1, "generation identity preserved")
        } else {
            XCTFail("connection should be .ready after recovery")
        }
    }

    // MARK: - Test 9: explicit clear by setting desiredLocation nil

    func testExplicitClearBySettingDesiredLocationNil() {
        var state = LocationSessionState()
        let desired = makeCoordinate()
        let receipt = makeReceipt()

        state.desiredLocation = desired
        state.lastAcknowledgedReceipt = receipt
        state.application = .active(receipt: receipt)

        // Explicit clear: set desiredLocation to nil
        state.desiredLocation = nil
        XCTAssertNil(state.desiredLocation, "desiredLocation must be nil after explicit clear")
        
        // lastAcknowledgedReceipt persists unless spec requires erasure
        XCTAssertEqual(state.lastAcknowledgedReceipt?.requestID, receipt.requestID, "receipt persists unless spec explicitly requires erasure")
    }

    // MARK: - Test 10: isActive false for all non-active cases, true only for active

    func testIsActiveFalseExceptForActiveApplication() {
        var state = LocationSessionState()
        let receipt = makeReceipt()

        // Idle: isActive false
        state.application = .idle
        XCTAssertFalse(state.application.isActive, "isActive must be false for .idle")

        // Applying: isActive false
        state.application = .applying(requestID: deterministicUUID, coordinate: makeCoordinate())
        XCTAssertFalse(state.application.isActive, "isActive must be false for .applying")

        // Uncertain: isActive false
        state.application = .uncertain(lastReceipt: receipt, reason: "test")
        XCTAssertFalse(state.application.isActive, "isActive must be false for .uncertain")

        // Active: isActive true
        state.application = .active(receipt: receipt)
        XCTAssertTrue(state.application.isActive, "isActive must be true for .active")

        // Lost: isActive false
        state.application = .lost("offline")
        XCTAssertFalse(state.application.isActive, "isActive must be false for .lost")

        // Clearing: isActive false
        state.application = .clearing
        XCTAssertFalse(state.application.isActive, "isActive must be false for .clearing")

        // Failed: isActive false
        state.application = .failed("error")
        XCTAssertFalse(state.application.isActive, "isActive must be false for .failed")
    }

    // MARK: - Bonus: Desired survives every non-clear transition

    func testDesiredSurvivesEveryNonClearTransition() {
        var state = LocationSessionState()
        let desired = makeCoordinate(lat: 51.5074, lon: -0.1278)
        state.desiredLocation = desired
        let identity = makeIdentity()
        let receipt = makeReceipt()

        // Connection transitions
        state.connection = .ready(identity: identity)
        XCTAssertEqual(state.desiredLocation, desired, "desired survives connection.ready")

        state.connection = .reconnecting(previousGeneration: 1, attempt: 1)
        XCTAssertEqual(state.desiredLocation, desired, "desired survives connection.reconnecting")

        state.connection = .failed("lost")
        XCTAssertEqual(state.desiredLocation, desired, "desired survives connection.failed")

        // Application transitions
        state.application = .applying(requestID: deterministicUUID, coordinate: makeCoordinate())
        XCTAssertEqual(state.desiredLocation, desired, "desired survives application.applying")

        state.application = .active(receipt: receipt)
        XCTAssertEqual(state.desiredLocation, desired, "desired survives application.active")

        state.application = .uncertain(lastReceipt: receipt, reason: "checking")
        XCTAssertEqual(state.desiredLocation, desired, "desired survives application.uncertain")

        state.application = .lost("device lost")
        XCTAssertEqual(state.desiredLocation, desired, "desired survives application.lost")

        state.application = .clearing
        XCTAssertEqual(state.desiredLocation, desired, "desired survives application.clearing")

        state.application = .failed("failed")
        XCTAssertEqual(state.desiredLocation, desired, "desired survives application.failed")

        // Movement transitions
        state.movement = .moving(.teleport)
        XCTAssertEqual(state.desiredLocation, desired, "desired survives movement.moving")

        state.movement = .paused(.twoSpot)
        XCTAssertEqual(state.desiredLocation, desired, "desired survives movement.paused")

        state.movement = .completed(.multiSpot)
        XCTAssertEqual(state.desiredLocation, desired, "desired survives movement.completed")
    }
}
