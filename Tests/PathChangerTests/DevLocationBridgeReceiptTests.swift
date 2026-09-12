import XCTest
@testable import PathChanger

final class DevLocationBridgeReceiptTests: XCTestCase {
    func testDirectAndRSDClassificationRetainsPhysicalTransport() {
        let usb = LocationConnectionArguments.describe(
            deviceId: "device", physicalTransport: .usb,
            isDaemonTunneld: false, rsdAddress: nil, rsdPort: nil
        )
        XCTAssertEqual(usb.arguments, ["--udid", "device"])
        XCTAssertEqual(usb.transport, .usb)
        XCTAssertEqual(usb.endpointClass, .direct)

        let rsd = LocationConnectionArguments.describe(
            deviceId: "device", physicalTransport: .wifi,
            isDaemonTunneld: false, rsdAddress: "fd00::1", rsdPort: 49155
        )
        XCTAssertEqual(rsd.arguments, ["--rsd", "fd00::1", "49155"])
        XCTAssertEqual(rsd.transport, .wifi)
        XCTAssertEqual(rsd.endpointClass, .remoteServiceDiscovery)
    }

    func testGenerationAdvancesOnlyAfterLossOrEndpointReplacement() {
        var tracker = LocationSessionGenerationTracker()
        let first = tracker.resolve(stableDeviceID: "device", transport: .usb, endpointClass: .direct)
        let same = tracker.resolve(stableDeviceID: "device", transport: .usb, endpointClass: .direct)
        XCTAssertEqual(same, first)

        tracker.markLost(stableDeviceID: "device")
        let afterLoss = tracker.resolve(stableDeviceID: "device", transport: .usb, endpointClass: .direct)
        XCTAssertEqual(afterLoss.generation, first.generation + 1)
        XCTAssertNotEqual(afterLoss.sessionID, first.sessionID)

        let rsd = tracker.resolve(stableDeviceID: "device", transport: .wifi, endpointClass: .remoteServiceDiscovery)
        XCTAssertEqual(rsd.generation, afterLoss.generation + 1)
    }

    func testReceiptEchoesAcceptedRequestAndSession() {
        let request = LocationApplicationRequest(
            id: UUID(),
            target: .init(stableDeviceID: "device", transport: .wifi),
            coordinate: .init(latitude: 35.0, longitude: 139.0),
            mode: .jumpTeleport
        )
        let session = LocationBridgeSession(sessionID: UUID(), generation: 4)
        let receipt = LocationInjectionReceipt.accepted(
            request: request, endpointClass: .remoteServiceDiscovery,
            session: session, outcome: .applied, completedAt: Date(timeIntervalSince1970: 42)
        )
        XCTAssertEqual(receipt.requestID, request.id)
        XCTAssertEqual(receipt.coordinate, request.coordinate)
        XCTAssertEqual(receipt.transport, request.target.transport)
        XCTAssertEqual(receipt.sessionGeneration, 4)
    }

    func testDevLocationBridgeConformsToLocationInjecting() {
        func requireLocationInjector<T: LocationInjecting>(_: T.Type) {}
        requireLocationInjector(DevLocationBridge.self)
    }

    func testQueuedAndCompletionReceiptsPreserveOriginalRequestTruth() {
        let request = LocationApplicationRequest(
            id: UUID(),
            target: LocationInjectionTarget(stableDeviceID: "queue-device", transport: .wifi),
            coordinate: LocationCoordinate(latitude: 51.5, longitude: -0.1),
            mode: .joystick
        )
        let session = LocationBridgeSession(sessionID: UUID(), generation: 3)
        let queued = LocationInjectionReceipt.accepted(
            request: request,
            endpointClass: .remoteServiceDiscovery,
            session: session,
            outcome: .queued,
            completedAt: Date(timeIntervalSince1970: 10)
        )
        let completed = LocationInjectionReceipt.accepted(
            request: request,
            endpointClass: .remoteServiceDiscovery,
            session: session,
            outcome: .applied,
            completedAt: Date(timeIntervalSince1970: 11)
        )

        XCTAssertEqual(queued.requestID, request.id)
        XCTAssertEqual(queued.outcome, .queued)
        XCTAssertEqual(completed.requestID, queued.requestID)
        XCTAssertEqual(completed.outcome, .applied)
        XCTAssertEqual(LocationBridgeEvent.receipt(completed), .receipt(completed))
    }
}
