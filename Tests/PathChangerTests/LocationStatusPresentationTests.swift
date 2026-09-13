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

}
