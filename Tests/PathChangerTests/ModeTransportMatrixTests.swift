import XCTest
@testable import PathChanger

@MainActor
final class ModeTransportMatrixTests: XCTestCase {
    private struct MatrixCase {
        let mode: LocationMode
        let transport: LocationTransport
        var name: String { "\(mode.rawValue)-\(transport.rawValue)" }
    }

    private let start = LocationCoordinate(latitude: 37.774900, longitude: -122.419400)
    private let middle = LocationCoordinate(latitude: 37.774905, longitude: -122.419395)
    private let finish = LocationCoordinate(latitude: 37.774910, longitude: -122.419390)

    private var cases: [MatrixCase] {
        LocationMode.allCases.flatMap { mode in
            [LocationTransport.usb, .wifi].map { MatrixCase(mode: mode, transport: $0) }
        }
    }

    private func session(for testCase: MatrixCase, generation: UInt64 = 1) -> LocationSessionIdentity {
        LocationSessionIdentity(
            stableDeviceID: "matrix-device",
            transport: testCase.transport,
            endpointClass: testCase.transport == .usb ? .direct : .remoteServiceDiscovery,
            generation: generation
        )
    }

    private func actionCoordinates(for mode: LocationMode) throws -> [LocationCoordinate] {
        let appMode: AppMode
        let route: [LocationCoordinate]
        let target: LocationCoordinate?
        let current: LocationCoordinate?
        switch mode {
        case .teleport:
            appMode = .teleport; route = []; target = finish; current = nil
        case .jumpTeleport:
            appMode = .jump; route = [middle, finish]; target = finish; current = start
        case .twoSpot:
            appMode = .twospot; route = [start, finish]; target = finish; current = start
        case .multiSpot:
            appMode = .route; route = [start, middle, finish]; target = finish; current = start
        case .joystick:
            appMode = .joystick; route = []; target = start; current = nil
        }
        let plan = SimulationPlanner.plan(
            mode: appMode,
            targetLocation: target,
            currentLocation: current,
            route: route,
            speed: .walking
        )
        switch plan {
        case .teleport(let coordinate):
            return [coordinate]
        case .route(let points):
            return points
        case .joystick(let coordinate):
            return [coordinate, finish]
        case .failed(let reason):
            throw NSError(domain: "MatrixPlan", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
        }
    }

    private func acknowledge(
        _ coordinate: LocationCoordinate,
        mode: LocationMode,
        session: LocationSessionIdentity,
        coordinator: LocationSessionCoordinator,
        fake: FakeLocationInjector
    ) async throws -> LocationInjectionReceipt {
        coordinator.select(coordinate, mode: mode)
        let request = try coordinator.beginApplication()
        let apply = Task { try await fake.apply(request) }
        await fake.waitUntilApplicationPending()
        XCTAssertFalse(coordinator.state.application.isActive)
        await fake.releaseNextApplication(session: session)
        let receipt = try await apply.value
        XCTAssertNil(coordinator.accept(receipt))
        return receipt
    }

    func testTypedTableContainsEveryModeOverUSBAndWiFi() {
        XCTAssertEqual(cases.count, 10)
        XCTAssertEqual(Set(cases.map(\.mode)), Set(LocationMode.allCases))
        for mode in LocationMode.allCases {
            XCTAssertEqual(cases.filter { $0.mode == mode }.map(\.transport), [.usb, .wifi])
        }
    }

    func testTenCoreCasesAdvanceOnlyByReceiptAndHoldFinalCoordinate() async throws {
        for testCase in cases {
            let fake = FakeLocationInjector()
            let coordinator = LocationSessionCoordinator(injector: fake)
            let identity = session(for: testCase)
            coordinator.connectionReady(identity)
            let coordinates = try actionCoordinates(for: testCase.mode)
            XCTAssertFalse(coordinates.isEmpty, testCase.name)

            if testCase.mode != .teleport { coordinator.beginMovement(testCase.mode) }
            var lastReceipt: LocationInjectionReceipt?
            for coordinate in coordinates {
                lastReceipt = try await acknowledge(
                    coordinate,
                    mode: testCase.mode,
                    session: identity,
                    coordinator: coordinator,
                    fake: fake
                )
            }

            if testCase.mode == .joystick {
                coordinator.stopMovement()
                XCTAssertEqual(coordinator.state.movement, .idle, testCase.name)
            } else if testCase.mode != .teleport {
                coordinator.completeMovement()
                XCTAssertEqual(coordinator.state.movement, .completed(testCase.mode), testCase.name)
            }

            XCTAssertEqual(coordinator.state.desiredLocation, coordinates.last, testCase.name)
            XCTAssertEqual(coordinator.state.lastAcknowledgedReceipt, lastReceipt, testCase.name)
            XCTAssertEqual(lastReceipt?.coordinate, coordinates.last, testCase.name)
            XCTAssertTrue(coordinator.state.application.isActive, testCase.name)
            let calls = await fake.calls()
            XCTAssertFalse(calls.contains { if case .clear = $0 { true } else { false } }, testCase.name)
        }
    }

    func testJumpConsumesExactlyOneAcknowledgedHopPerAction() async throws {
        for transport in [LocationTransport.usb, .wifi] {
            let testCase = MatrixCase(mode: .jumpTeleport, transport: transport)
            let fake = FakeLocationInjector()
            let coordinator = LocationSessionCoordinator(injector: fake)
            let identity = session(for: testCase)
            coordinator.connectionReady(identity)
            let hops = try actionCoordinates(for: .jumpTeleport)
            XCTAssertEqual(hops, [middle])
            _ = try await acknowledge(middle, mode: .jumpTeleport, session: identity, coordinator: coordinator, fake: fake)
            XCTAssertEqual(coordinator.state.lastAcknowledgedReceipt?.coordinate, middle)
            let pendingCount = await fake.pendingApplicationCount()
            XCTAssertEqual(pendingCount, 0)
        }
    }
}
