import XCTest
@testable import PathChanger

@MainActor
final class LocationStatusPresentationTests: XCTestCase {
    private let coordinate = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
    private let session = LocationSessionIdentity(stableDeviceID: "private-udid", transport: .wifi, endpointClass: .remoteServiceDiscovery, generation: 7)

    func testConnectedTransportDoesNotImplySpoofing() {
        var state = LocationSessionState(desiredLocation: coordinate)
        state.connection = .ready(identity: session)
        let presentation = LocationStatusPresentation(state: state, deviceVisible: true)
        XCTAssertEqual(presentation.connectionLabel, "Ready over Wi-Fi")
        XCTAssertEqual(presentation.applicationLabel, "Idle")
        XCTAssertFalse(presentation.isSpoofing)
        XCTAssertEqual(presentation.appliedCoordinateLabel, "—")
        XCTAssertEqual(presentation.desiredCoordinateLabel, coordinate.formattedShort)
    }

    func testOnlyCurrentGenerationAppliedReceiptCanSaySpoofing() {
        let requestID = UUID()
        let receipt = LocationInjectionReceipt(requestID: requestID, session: UUID(), coordinate: coordinate, transport: .wifi, endpointClass: .remoteServiceDiscovery, sessionGeneration: 7, completedAt: Date(timeIntervalSince1970: 1), outcome: .applied)
        var state = LocationSessionState(desiredLocation: coordinate, lastAcknowledgedReceipt: receipt, connection: .ready(identity: session), application: .active(receipt: receipt), movement: .completed(.multiSpot))
        var presentation = LocationStatusPresentation(state: state, deviceVisible: true)
        XCTAssertTrue(presentation.isSpoofing)
        XCTAssertEqual(presentation.applicationLabel, "Active / Held")
        XCTAssertEqual(presentation.movementLabel, "Completed")
        XCTAssertEqual(presentation.appliedCoordinateLabel, coordinate.formattedShort)
        state.connection = .ready(identity: LocationSessionIdentity(stableDeviceID: "private-udid", transport: .wifi, endpointClass: .remoteServiceDiscovery, generation: 8))
        presentation = LocationStatusPresentation(state: state, deviceVisible: true)
        XCTAssertFalse(presentation.isSpoofing)
        XCTAssertEqual(presentation.appliedCoordinateLabel, "Uncertain")
    }

    func testApplyingMovingPausedReconnectingLostClearingAndFailedLabelsAreExplicit() {
        var state = LocationSessionState(desiredLocation: coordinate)
        state.application = .applying(requestID: UUID(), coordinate: coordinate)
        XCTAssertEqual(LocationStatusPresentation(state: state, deviceVisible: true).applicationLabel, "Applying")
        state.application = .clearing
        XCTAssertEqual(LocationStatusPresentation(state: state, deviceVisible: true).applicationLabel, "Clearing")
        state.application = .failed("queue_overflow")
        XCTAssertEqual(LocationStatusPresentation(state: state, deviceVisible: true).applicationLabel, "Failed")
        state.connection = .reconnecting(previousGeneration: 7, attempt: 2)
        state.application = .uncertain(lastReceipt: nil, reason: "transport loss")
        var p = LocationStatusPresentation(state: state, deviceVisible: true)
        XCTAssertEqual(p.connectionLabel, "Reconnecting")
        XCTAssertEqual(p.applicationLabel, "Uncertain")
        state.connection = .failed("lost")
        p = LocationStatusPresentation(state: state, deviceVisible: true)
        XCTAssertEqual(p.connectionLabel, "Lost")
        state.movement = .moving(.joystick)
        XCTAssertEqual(LocationStatusPresentation(state: state, deviceVisible: true).movementLabel, "Moving")
        state.movement = .paused(.joystick)
        XCTAssertEqual(LocationStatusPresentation(state: state, deviceVisible: true).movementLabel, "Paused")
    }

    func testAMovementStepKeepsTheHeldLocationShownWhileItsUpdateIsInFlight() {
        // Live 2026-11-01: every route/joystick step set Applying, so Location flipped
        // Applying <-> Active / Held, the Applied chip vanished and the pin jumped, up to
        // five times a second. While a step is in flight the last acknowledged location
        // is still held on a healthy session.
        let receipt = LocationInjectionReceipt(requestID: UUID(), session: UUID(), coordinate: coordinate, transport: .wifi, endpointClass: .remoteServiceDiscovery, sessionGeneration: 7, completedAt: Date(timeIntervalSince1970: 1), outcome: .applied)
        let next = LocationCoordinate(latitude: 35.6763, longitude: 139.6504)
        var state = LocationSessionState(desiredLocation: next, lastAcknowledgedReceipt: receipt, connection: .ready(identity: session), application: .applying(requestID: UUID(), coordinate: next), movement: .moving(.twoSpot), heldWhileApplying: receipt)

        let p = LocationStatusPresentation(state: state, deviceVisible: true)
        XCTAssertTrue(p.isSpoofing)
        XCTAssertEqual(p.applicationLabel, "Active / Held")
        XCTAssertEqual(p.appliedCoordinate, coordinate)
        XCTAssertEqual(p.appliedCoordinateLabel, coordinate.formattedShort)
        XCTAssertFalse(p.canApply, "a request in flight still blocks a second Apply")

        // After a failed step the helper closed the connection and the location ended:
        // a retry must not show the old receipt as held (review 2026-11-01).
        state.heldWhileApplying = nil
        XCTAssertEqual(LocationStatusPresentation(state: state, deviceVisible: true).applicationLabel, "Applying")
        XCTAssertFalse(LocationStatusPresentation(state: state, deviceVisible: true).isSpoofing)
        // The first application (nothing held yet) still says Applying.
        state.lastAcknowledgedReceipt = nil
        XCTAssertEqual(LocationStatusPresentation(state: state, deviceVisible: true).applicationLabel, "Applying")
        // A held receipt from an older session proves nothing.
        state.lastAcknowledgedReceipt = receipt
        state.heldWhileApplying = receipt
        state.connection = .ready(identity: LocationSessionIdentity(stableDeviceID: "private-udid", transport: .wifi, endpointClass: .remoteServiceDiscovery, generation: 8))
        XCTAssertEqual(LocationStatusPresentation(state: state, deviceVisible: true).applicationLabel, "Applying")
    }

    func testDiagnosticsRedactStableIdentifierAndExposeSafeMetadata() {
        var state = LocationSessionState(desiredLocation: coordinate, connection: .ready(identity: session))
        let receipt = LocationInjectionReceipt(requestID: UUID(uuidString: "00000000-0000-0000-0000-00000000ABCD")!, session: UUID(), coordinate: coordinate, transport: .wifi, endpointClass: .remoteServiceDiscovery, sessionGeneration: 7, completedAt: Date(), outcome: .applied)
        state.lastAcknowledgedReceipt = receipt
        let p = LocationStatusPresentation(state: state, deviceVisible: true)
        XCTAssertFalse(p.sessionDiagnostic.contains("private-udid"))
        XCTAssertTrue(p.sessionDiagnostic.contains("Device-"))
        XCTAssertTrue(p.sessionDiagnostic.contains("Wi-Fi"))
        XCTAssertTrue(p.sessionDiagnostic.contains("generation 7"))
        XCTAssertTrue(p.sessionDiagnostic.contains("ABCD"))
    }

    func testGUIExposesStableLocationAccessibilityIdentifiers() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let paths = [
            "PathChanger/UI/ContentView.swift",
            "PathChanger/UI/ModeContextCard.swift",
            "PathChanger/UI/OrganicChrome.swift"
        ]
        let source = try paths.map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }.joined()
        for identifier in [
            "location.mode.teleport", "location.mode.jump", "location.mode.twoSpot",
            "location.mode.multiSpot", "location.mode.joystick", "location.action.apply",
            "location.action.pauseMovement", "location.action.stopMovement", "location.action.clear",
            "location.status.connection", "location.status.application", "location.status.movement",
            "location.status.coordinate"
        ] {
            XCTAssertTrue(source.contains(identifier), "Missing accessibility identifier: \(identifier)")
        }
    }

    // MARK: Map location marker (PRODUCT_REQUIREMENTS 5.2)

    func testMarkerIsSpoofedOnlyForAnAppliedCoordinate() {
        let other = LocationCoordinate(latitude: 1, longitude: 2)
        XCTAssertEqual(
            LocationMarker.resolve(applied: coordinate, stagedStart: other, desired: other),
            LocationMarker(coordinate: coordinate, style: .spoofed)
        )
        XCTAssertEqual(LocationMarker(coordinate: coordinate, style: .spoofed).accessibilityLabel, "Spoofed location")
    }

    func testMarkerIsStagedWhenNothingIsApplied() {
        let other = LocationCoordinate(latitude: 1, longitude: 2)
        // A Clear's staged start is where the next Move leaves from; it wins over a
        // picked Two-Spot destination.
        XCTAssertEqual(
            LocationMarker.resolve(applied: nil, stagedStart: coordinate, desired: other),
            LocationMarker(coordinate: coordinate, style: .staged)
        )
        XCTAssertEqual(
            LocationMarker.resolve(applied: nil, stagedStart: nil, desired: other),
            LocationMarker(coordinate: other, style: .staged)
        )
        XCTAssertEqual(LocationMarker(coordinate: other, style: .staged).accessibilityLabel, "Staged location")
    }

    func testNoMarkerWithoutAnyCoordinate() {
        XCTAssertNil(LocationMarker.resolve(applied: nil, stagedStart: nil, desired: nil))
    }

    func testClearIsDisabledWhenOnlyAStagedPointExists() {
        var state = LocationSessionState(desiredLocation: coordinate)
        state.connection = .ready(identity: session)
        XCTAssertFalse(LocationStatusPresentation(state: state, deviceVisible: true).canClear,
                       "a staged point is not on the device; there is nothing to clear")
        XCTAssertTrue(LocationStatusPresentation(state: state, deviceVisible: true).canApply)
    }

    // MARK: Review 2026-11-02

    func testAnAppliedButUnconfirmedPointIsMarkedUncertainNotStaged() {
        let other = LocationCoordinate(latitude: 1, longitude: 2)
        XCTAssertEqual(
            LocationMarker.resolve(applied: nil, uncertain: coordinate, stagedStart: other, desired: other),
            LocationMarker(coordinate: coordinate, style: .uncertain)
        )
        XCTAssertEqual(
            LocationMarker.resolve(applied: other, uncertain: coordinate, stagedStart: nil, desired: nil),
            LocationMarker(coordinate: other, style: .spoofed),
            "a current applied receipt wins"
        )
        XCTAssertEqual(LocationMarker(coordinate: coordinate, style: .uncertain).accessibilityLabel, "Location uncertain")
    }

    func testWaitingForTheLostPhoneReadsReconnectingAndOffersClear() {
        let receipt = LocationInjectionReceipt(requestID: UUID(), session: UUID(), coordinate: coordinate, transport: .wifi, endpointClass: .remoteServiceDiscovery, sessionGeneration: 7, completedAt: Date(timeIntervalSince1970: 1), outcome: .applied)
        let state = LocationSessionState(desiredLocation: coordinate, lastAcknowledgedReceipt: receipt, connection: .failed("lost"), application: .uncertain(lastReceipt: receipt, reason: "lost"))

        let waiting = LocationStatusPresentation(state: state, deviceVisible: false, isAwaitingAutomaticReconnect: true)
        XCTAssertEqual(waiting.connectionLabel, "Reconnecting")
        XCTAssertTrue(waiting.canClear, "Clear stops the wait")
        XCTAssertFalse(waiting.canMove)

        let notWaiting = LocationStatusPresentation(state: state, deviceVisible: false)
        XCTAssertEqual(notWaiting.connectionLabel, "Lost")
        XCTAssertFalse(notWaiting.canClear)
    }

    func testATunnelErrorIsShownBeforeTheReconnectNotice() {
        XCTAssertEqual(
            TunnelNotice.resolve(isWaitingForDevice: false, automaticReconnectNotice: "Reconnecting…", tunnelError: "Tunnel failed"),
            TunnelNotice(text: "Tunnel failed\nReconnecting…", isError: true)
        )
        XCTAssertEqual(
            TunnelNotice.resolve(isWaitingForDevice: false, automaticReconnectNotice: nil, tunnelError: "Tunnel failed"),
            TunnelNotice(text: "Tunnel failed", isError: true)
        )
        XCTAssertEqual(
            TunnelNotice.resolve(isWaitingForDevice: false, automaticReconnectNotice: "Reconnecting…", tunnelError: nil),
            TunnelNotice(text: "Reconnecting…", isError: false)
        )
        XCTAssertEqual(
            TunnelNotice.resolve(isWaitingForDevice: true, automaticReconnectNotice: "Reconnecting…", tunnelError: "Tunnel failed"),
            TunnelNotice(text: TunnelNotice.waitingForDeviceText, isError: false)
        )
        XCTAssertNil(TunnelNotice.resolve(isWaitingForDevice: false, automaticReconnectNotice: nil, tunnelError: nil))
    }

}
