//
//  RoadRouterTests.swift
//  PathChangerTests
//
//  Real-road leg routing (PRODUCT_REQUIREMENTS §3.6). Every test injects the directions
//  function, so nothing here reaches Apple Maps or the network.
//

import MapKit
import XCTest
@testable import PathChanger

final class RoadRouterTests: XCTestCase {

    // About 1.1 km apart in central Tokyo.
    private let origin = LocationCoordinate(latitude: 35.6812, longitude: 139.7671)
    private let destination = LocationCoordinate(latitude: 35.6895, longitude: 139.7745)

    // MARK: - Transport mapping

    func testTravelModesMapToAppleMapsTransports() {
        XCTAssertEqual(RoadTransport(travel: .walking), .walking)
        XCTAssertEqual(RoadTransport(travel: .cycling), .cycling)
        XCTAssertEqual(RoadTransport(travel: .fast), .automobile, "Riding uses automobile directions")
        XCTAssertEqual(RoadTransport(travel: .driving), .automobile)
        XCTAssertEqual(RoadTransport(travel: .running), .automobile)
        XCTAssertEqual(RoadTransport(travel: .teleport), .automobile)
    }

    func testRoadTransportsMapToMapKitTransportTypes() {
        XCTAssertEqual(RoadTransport.walking.mapKitTransportType, .walking)
        XCTAssertEqual(RoadTransport.cycling.mapKitTransportType, .cycling)
        XCTAssertEqual(RoadTransport.automobile.mapKitTransportType, .automobile)
    }

    func testRequestCarriesTheTransportForEachTravelMode() async {
        let expected: [SimulationSpeed: RoadTransport] = [
            .walking: .walking, .cycling: .cycling, .fast: .automobile,
            .driving: .automobile, .running: .automobile, .teleport: .automobile
        ]
        for (travel, transport) in expected {
            let directions = FakeDirections(result: .success(roadPath()))
            let router = MapKitRoadRouter(directions: directions.function)

            _ = await router.route(from: origin, to: destination, travel: travel)

            let requests = await directions.requests
            XCTAssertEqual(requests.map(\.transport), [transport], "travel mode \(travel)")
        }
    }

    // MARK: - Polyline use

    func testRoadPolylineIsUsedAndPinnedToTheEndpoints() async {
        // Polyline ends ~50 m away from the requested endpoints (snapped to the road).
        let snappedStart = LocationCoordinate(latitude: 35.6816, longitude: 139.7671)
        let middle = LocationCoordinate(latitude: 35.6850, longitude: 139.7700)
        let snappedEnd = LocationCoordinate(latitude: 35.6891, longitude: 139.7745)
        let directions = FakeDirections(result: .success(.init(coordinates: [snappedStart, middle, snappedEnd], distance: 1_400)))
        let router = MapKitRoadRouter(directions: directions.function)

        let route = await router.route(from: origin, to: destination, travel: .walking)

        XCTAssertTrue(route.followsRoads)
        XCTAssertNil(route.note)
        XCTAssertEqual(route.points, [origin, snappedStart, middle, snappedEnd, destination])
        XCTAssertEqual(route.distanceMeters, 1_400, accuracy: 0.001)
    }

    func testPolylineEndsWithinOneMetreAreReplacedByTheExactEndpoints() async {
        let almostStart = LocationCoordinate(latitude: origin.latitude + 0.000002, longitude: origin.longitude)
        let middle = LocationCoordinate(latitude: 35.6850, longitude: 139.7700)
        let almostEnd = LocationCoordinate(latitude: destination.latitude, longitude: destination.longitude + 0.000002)
        let directions = FakeDirections(result: .success(.init(coordinates: [almostStart, middle, almostEnd], distance: 1_300)))
        let router = MapKitRoadRouter(directions: directions.function)

        let route = await router.route(from: origin, to: destination, travel: .driving)

        XCTAssertEqual(route.points, [origin, middle, destination])
    }

    func testRoadDistanceIsReported() async {
        let directions = FakeDirections(result: .success(roadPath(distance: 2_345.5)))
        let router = MapKitRoadRouter(directions: directions.function)

        let route = await router.route(from: origin, to: destination, travel: .cycling)

        XCTAssertTrue(route.followsRoads)
        XCTAssertEqual(route.distanceMeters, 2_345.5, accuracy: 0.001)
    }

    // MARK: - Fallbacks

    func testTimeoutFallsBackToStraightLineAndCancelsTheRequest() async {
        let directions = FakeDirections(result: .hang)
        let router = MapKitRoadRouter(timeout: 0.1, directions: directions.function)
        let started = Date()

        let route = await router.route(from: origin, to: destination, travel: .walking)

        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "the request must be bounded by the timeout")
        assertStraightLineFallback(route)
        let sawCancellation = await waitUntil { await directions.cancelled }
        XCTAssertTrue(sawCancellation, "the timed-out request must be cancelled")
    }

    func testTimeoutIsBoundedEvenWhenTheRequestIgnoresCancellation() async {
        let directions = FakeDirections(result: .hangIgnoringCancellation(seconds: 3))
        let router = MapKitRoadRouter(timeout: 0.1, directions: directions.function)
        let started = Date()

        let route = await router.route(from: origin, to: destination, travel: .walking)

        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        assertStraightLineFallback(route)
    }

    func testDirectionsErrorFallsBackToStraightLine() async {
        let directions = FakeDirections(result: .failure)
        let router = MapKitRoadRouter(directions: directions.function)

        let route = await router.route(from: origin, to: destination, travel: .driving)

        assertStraightLineFallback(route)
    }

    func testEmptyPolylineFallsBackToStraightLine() async {
        let directions = FakeDirections(result: .success(.init(coordinates: [], distance: 1_000)))
        let router = MapKitRoadRouter(directions: directions.function)

        let route = await router.route(from: origin, to: destination, travel: .walking)

        assertStraightLineFallback(route)
    }

    func testPolylineWithNonFiniteCoordinateFallsBackToStraightLine() async {
        let bad = LocationCoordinate(latitude: .nan, longitude: 139.77)
        let directions = FakeDirections(result: .success(.init(coordinates: [origin, bad, destination], distance: 1_000)))
        let router = MapKitRoadRouter(directions: directions.function)

        let route = await router.route(from: origin, to: destination, travel: .walking)

        assertStraightLineFallback(route)
    }

    func testPolylineWithOutOfRangeCoordinateFallsBackToStraightLine() async {
        let bad = LocationCoordinate(latitude: 95, longitude: 139.77)
        let directions = FakeDirections(result: .success(.init(coordinates: [origin, bad, destination], distance: 1_000)))
        let router = MapKitRoadRouter(directions: directions.function)

        let route = await router.route(from: origin, to: destination, travel: .walking)

        assertStraightLineFallback(route)
    }

    func testInvalidDistanceFallsBackToStraightLine() async {
        let directions = FakeDirections(result: .success(roadPath(distance: .infinity)))
        let router = MapKitRoadRouter(directions: directions.function)

        let route = await router.route(from: origin, to: destination, travel: .walking)

        assertStraightLineFallback(route)
    }

    func testFailedRouteIsNotCachedSoTheNextRequestRetries() async {
        let directions = FakeDirections(result: .failure)
        let router = MapKitRoadRouter(directions: directions.function)

        _ = await router.route(from: origin, to: destination, travel: .walking)
        await directions.setResult(.success(roadPath()))
        let route = await router.route(from: origin, to: destination, travel: .walking)

        XCTAssertTrue(route.followsRoads)
        let count = await directions.requests.count
        XCTAssertEqual(count, 2)
    }

    // MARK: - Same endpoints

    func testInvalidEndpointsFallBackWithoutARequest() async {
        let directions = FakeDirections(result: .success(roadPath()))
        let router = MapKitRoadRouter(directions: directions.function)
        let invalid = LocationCoordinate(latitude: 91, longitude: 0)

        let route = await router.route(from: origin, to: invalid, travel: .walking)

        XCTAssertFalse(route.followsRoads)
        XCTAssertEqual(route.points, [origin, invalid])
        XCTAssertEqual(route.note, "No road route found; travelling in a straight line")
        let count = await directions.requests.count
        XCTAssertEqual(count, 0)
    }

    func testSameEndpointsReturnTwoPointPathWithoutARequest() async {
        let directions = FakeDirections(result: .success(roadPath()))
        let router = MapKitRoadRouter(directions: directions.function)
        let nearby = LocationCoordinate(latitude: origin.latitude + 0.000005, longitude: origin.longitude) // ~0.55 m

        let route = await router.route(from: origin, to: nearby, travel: .walking)

        XCTAssertEqual(route.points, [origin, nearby])
        XCTAssertLessThan(route.distanceMeters, 1)
        XCTAssertNil(route.note)
        let count = await directions.requests.count
        XCTAssertEqual(count, 0)
    }

    // MARK: - Cache

    func testCacheHitAvoidsASecondRequest() async {
        let directions = FakeDirections(result: .success(roadPath()))
        let router = MapKitRoadRouter(directions: directions.function)

        let first = await router.route(from: origin, to: destination, travel: .walking)
        let second = await router.route(from: origin, to: destination, travel: .walking)

        XCTAssertEqual(first, second)
        let count = await directions.requests.count
        XCTAssertEqual(count, 1)
    }

    func testCacheHitWithinRoundingIsRepinnedToTheNewEndpoints() async {
        let directions = FakeDirections(result: .success(roadPath()))
        let router = MapKitRoadRouter(directions: directions.function)
        let shiftedOrigin = LocationCoordinate(latitude: origin.latitude + 0.000001, longitude: origin.longitude)

        _ = await router.route(from: origin, to: destination, travel: .walking)
        let route = await router.route(from: shiftedOrigin, to: destination, travel: .walking)

        XCTAssertEqual(route.points.first, shiftedOrigin)
        XCTAssertEqual(route.points.last, destination)
        let count = await directions.requests.count
        XCTAssertEqual(count, 1)
    }

    func testCacheIsKeyedByTransport() async {
        let directions = FakeDirections(result: .success(roadPath()))
        let router = MapKitRoadRouter(directions: directions.function)

        _ = await router.route(from: origin, to: destination, travel: .walking)
        _ = await router.route(from: origin, to: destination, travel: .driving)
        _ = await router.route(from: origin, to: destination, travel: .fast) // automobile again: cache hit

        let transports = await directions.requests.map(\.transport)
        XCTAssertEqual(transports, [.walking, .automobile])
    }

    func testCacheIsKeyedByDirection() async {
        let directions = FakeDirections(result: .success(roadPath()))
        let router = MapKitRoadRouter(directions: directions.function)

        _ = await router.route(from: origin, to: destination, travel: .walking)
        _ = await router.route(from: destination, to: origin, travel: .walking)

        let count = await directions.requests.count
        XCTAssertEqual(count, 2)
    }

    func testCacheIsBoundedAndEvictsTheLeastRecentlyUsedLeg() async {
        let directions = FakeDirections(result: .success(roadPath()))
        let router = MapKitRoadRouter(cacheCapacity: 2, directions: directions.function)
        let legB = LocationCoordinate(latitude: 35.70, longitude: 139.78)
        let legC = LocationCoordinate(latitude: 35.71, longitude: 139.79)

        _ = await router.route(from: origin, to: destination, travel: .walking) // A (request 1)
        _ = await router.route(from: origin, to: legB, travel: .walking)        // B (request 2)
        _ = await router.route(from: origin, to: destination, travel: .walking) // A hit, now most recent
        _ = await router.route(from: origin, to: legC, travel: .walking)        // C (request 3) evicts B
        _ = await router.route(from: origin, to: destination, travel: .walking) // A still cached
        _ = await router.route(from: origin, to: legB, travel: .walking)        // B evicted (request 4)

        let count = await directions.requests.count
        XCTAssertEqual(count, 4)
    }

    // MARK: - Very long legs

    func testRoadRouteMuchLongerThanTheStraightLineIsKeptWithANote() async {
        let straight = Geo.distance(from: origin, to: destination)
        let directions = FakeDirections(result: .success(roadPath(distance: straight * 5)))
        let router = MapKitRoadRouter(directions: directions.function)

        let route = await router.route(from: origin, to: destination, travel: .driving)

        XCTAssertTrue(route.followsRoads)
        XCTAssertEqual(route.distanceMeters, straight * 5, accuracy: 0.001)
        XCTAssertNotNil(route.note)
    }

    func testRoadRouteLongerThan500KilometresIsKeptWithANote() async {
        let osaka = LocationCoordinate(latitude: 34.6937, longitude: 135.5023)
        let directions = FakeDirections(result: .success(.init(coordinates: [origin, osaka], distance: 510_000)))
        let router = MapKitRoadRouter(directions: directions.function)

        let route = await router.route(from: origin, to: osaka, travel: .driving)

        XCTAssertTrue(route.followsRoads)
        XCTAssertEqual(route.distanceMeters, 510_000, accuracy: 0.001)
        XCTAssertNotNil(route.note)
    }

    func testOrdinaryRoadRouteHasNoNote() async {
        let straight = Geo.distance(from: origin, to: destination)
        let directions = FakeDirections(result: .success(roadPath(distance: straight * 1.5)))
        let router = MapKitRoadRouter(directions: directions.function)

        let route = await router.route(from: origin, to: destination, travel: .driving)

        XCTAssertTrue(route.followsRoads)
        XCTAssertNil(route.note)
    }

    // MARK: - Helpers

    private func roadPath(distance: Double = 1_500) -> DirectionsPath {
        DirectionsPath(
            coordinates: [origin, LocationCoordinate(latitude: 35.6850, longitude: 139.7700), destination],
            distance: distance
        )
    }

    private func assertStraightLineFallback(_ route: RoadRoute, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(route.followsRoads, file: file, line: line)
        XCTAssertEqual(route.points, [origin, destination], file: file, line: line)
        XCTAssertEqual(route.distanceMeters, Geo.distance(from: origin, to: destination), accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(route.note, "No road route found; travelling in a straight line", file: file, line: line)
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async -> Bool {
        for _ in 0..<100 {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return await condition()
    }
}

// MARK: - Fake directions

private struct DirectionsPath: Sendable {
    let coordinates: [LocationCoordinate]
    let distance: Double
}

private actor FakeDirections {
    enum Result: Sendable {
        case success(DirectionsPath)
        case failure
        case hang
        case hangIgnoringCancellation(seconds: Double)
    }

    struct Request: Sendable {
        let from: LocationCoordinate
        let to: LocationCoordinate
        let transport: RoadTransport
    }

    struct Failure: Error {}

    private var result: Result
    private(set) var requests: [Request] = []
    private(set) var cancelled = false

    init(result: Result) {
        self.result = result
    }

    func setResult(_ result: Result) {
        self.result = result
    }

    nonisolated var function: MapKitRoadRouter.DirectionsFunction {
        { from, to, transport in
            try await self.respond(from: from, to: to, transport: transport)
        }
    }

    private func respond(
        from: LocationCoordinate,
        to: LocationCoordinate,
        transport: RoadTransport
    ) async throws -> (coordinates: [LocationCoordinate], distance: Double) {
        requests.append(Request(from: from, to: to, transport: transport))
        switch result {
        case .success(let path):
            return (path.coordinates, path.distance)
        case .failure:
            throw Failure()
        case .hang:
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            } catch {
                cancelled = true
                throw error
            }
            throw Failure()
        case .hangIgnoringCancellation(let seconds):
            // A wait that cancellation cannot shorten.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { continuation.resume() }
            }
            throw Failure()
        }
    }
}
