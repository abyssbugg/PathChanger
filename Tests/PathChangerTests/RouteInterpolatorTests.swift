//
//  RouteInterpolatorTests.swift
//  PathChangerTests
//
//  Unit tests for RouteInterpolator
//

import XCTest
@testable import PathChanger

final class RouteInterpolatorTests: XCTestCase {

    // MARK: - Haversine Distance Tests

    func testHaversineDistanceSamePoint() {
        let coord = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        let distance = RouteInterpolator.haversineDistance(from: coord, to: coord)
        XCTAssertEqual(distance, 0, accuracy: 0.001)
    }

    func testHaversineDistanceKnownPoints() {
        // Tokyo to New York is approximately 10,850 km
        let tokyo = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        let newYork = LocationCoordinate(latitude: 40.7128, longitude: -74.0060)

        let distance = RouteInterpolator.haversineDistance(from: tokyo, to: newYork)
        let distanceKm = distance / 1000

        // Should be between 10,500 and 11,000 km
        XCTAssertGreaterThan(distanceKm, 10500)
        XCTAssertLessThan(distanceKm, 11000)
    }

    func testHaversineDistanceInvalidCoordinates() {
        let valid = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        let invalid = LocationCoordinate(latitude: 91.0, longitude: 0.0)

        let distance = RouteInterpolator.haversineDistance(from: valid, to: invalid)
        XCTAssertEqual(distance, 0, "Invalid coordinates should return 0 distance")
    }

    // MARK: - Bearing Tests

    func testBearingNorth() {
        let from = LocationCoordinate(latitude: 0.0, longitude: 0.0)
        let to = LocationCoordinate(latitude: 1.0, longitude: 0.0)

        let bearing = RouteInterpolator.bearing(from: from, to: to)
        XCTAssertEqual(bearing, 0, accuracy: 0.1, "Bearing north should be ~0 degrees")
    }

    func testBearingEast() {
        let from = LocationCoordinate(latitude: 0.0, longitude: 0.0)
        let to = LocationCoordinate(latitude: 0.0, longitude: 1.0)

        let bearing = RouteInterpolator.bearing(from: from, to: to)
        XCTAssertEqual(bearing, 90, accuracy: 0.1, "Bearing east should be ~90 degrees")
    }

    func testBearingSouth() {
        let from = LocationCoordinate(latitude: 1.0, longitude: 0.0)
        let to = LocationCoordinate(latitude: 0.0, longitude: 0.0)

        let bearing = RouteInterpolator.bearing(from: from, to: to)
        XCTAssertEqual(bearing, 180, accuracy: 0.1, "Bearing south should be ~180 degrees")
    }

    func testBearingWest() {
        let from = LocationCoordinate(latitude: 0.0, longitude: 1.0)
        let to = LocationCoordinate(latitude: 0.0, longitude: 0.0)

        let bearing = RouteInterpolator.bearing(from: from, to: to)
        XCTAssertEqual(bearing, 270, accuracy: 0.1, "Bearing west should be ~270 degrees")
    }

    func testBearingInvalidCoordinates() {
        let valid = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        let invalid = LocationCoordinate(latitude: 91.0, longitude: 0.0)

        let bearing = RouteInterpolator.bearing(from: valid, to: invalid)
        XCTAssertEqual(bearing, 0, "Invalid coordinates should return 0 bearing")
    }

    // MARK: - Move Coordinate Tests

    func testMoveCoordinateNorth() {
        let start = LocationCoordinate(latitude: 0.0, longitude: 0.0)
        // Use 55km (within the 100km limit) - should move ~0.5 degrees north
        let result = RouteInterpolator.moveCoordinate(from: start, distanceMeters: 55500, bearingDegrees: 0)

        // Moving 55.5km north from equator should increase latitude by ~0.5 degrees
        XCTAssertEqual(result.latitude, 0.5, accuracy: 0.01)
        XCTAssertEqual(result.longitude, 0.0, accuracy: 0.01)
    }

    func testMoveCoordinateInvalidStart() {
        let invalid = LocationCoordinate(latitude: 91.0, longitude: 0.0)
        let result = RouteInterpolator.moveCoordinate(from: invalid, distanceMeters: 1000, bearingDegrees: 0)

        // Should return original (invalid) coordinate
        XCTAssertEqual(result.latitude, 91.0)
        XCTAssertEqual(result.longitude, 0.0)
    }

    func testMoveCoordinateNegativeDistance() {
        let start = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        let result = RouteInterpolator.moveCoordinate(from: start, distanceMeters: -100, bearingDegrees: 0)

        // Should return original coordinate for invalid distance
        XCTAssertEqual(result, start)
    }

    func testMoveCoordinateExcessiveDistance() {
        let start = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        let result = RouteInterpolator.moveCoordinate(from: start, distanceMeters: 200_000, bearingDegrees: 0)

        // Should return original coordinate for excessive distance (>100km)
        XCTAssertEqual(result, start)
    }

    func testMoveCoordinateNormalizeBearing() {
        let start = LocationCoordinate(latitude: 0.0, longitude: 0.0)

        // 360 degrees should be same as 0 degrees
        let result1 = RouteInterpolator.moveCoordinate(from: start, distanceMeters: 1000, bearingDegrees: 0)
        let result2 = RouteInterpolator.moveCoordinate(from: start, distanceMeters: 1000, bearingDegrees: 360)

        XCTAssertEqual(result1.latitude, result2.latitude, accuracy: 0.0001)
        XCTAssertEqual(result1.longitude, result2.longitude, accuracy: 0.0001)
    }

    // MARK: - Interpolate Route Tests

    func testInterpolateRouteEmptyArray() {
        let result = RouteInterpolator.interpolateRoute(waypoints: [], speed: .walking)
        XCTAssertTrue(result.isEmpty)
    }

    func testInterpolateRouteSinglePoint() {
        let point = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        let result = RouteInterpolator.interpolateRoute(waypoints: [point], speed: .walking)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first, point)
    }

    func testInterpolateRouteTwoPoints() {
        let start = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        let end = LocationCoordinate(latitude: 35.6862, longitude: 139.6603)

        let result = RouteInterpolator.interpolateRoute(waypoints: [start, end], speed: .driving)

        // Should have more points than original 2
        XCTAssertGreaterThan(result.count, 2)

        // First should be near start, last should be end
        XCTAssertEqual(result.first?.latitude ?? 0, start.latitude, accuracy: 0.0001)
        XCTAssertEqual(result.last?.latitude ?? 0, end.latitude, accuracy: 0.0001)
    }

    func testInterpolateRouteFiltersInvalidCoordinates() {
        let valid1 = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        let invalid = LocationCoordinate(latitude: 91.0, longitude: 0.0) // Invalid
        let valid2 = LocationCoordinate(latitude: 35.6862, longitude: 139.6603)

        let result = RouteInterpolator.interpolateRoute(waypoints: [valid1, invalid, valid2], speed: .walking)

        // Should have interpolated points (invalid filtered out)
        XCTAssertGreaterThan(result.count, 0)

        // All results should be valid
        for coord in result {
            XCTAssertTrue(coord.isValid, "All interpolated coordinates should be valid")
        }
    }

    // MARK: - Stepped Route Tests

    func testSteppedPointCountMatchesTheBuiltRoute() {
        let start = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        let mid = LocationCoordinate(latitude: 35.6862, longitude: 139.6603)
        let far = LocationCoordinate(latitude: 37.6862, longitude: 139.6603) // ~222 km legs, counted
        let waypoints = [start, mid, mid, far, start]

        let points = RouteInterpolator.interpolateRoute(waypoints: waypoints, stepMeters: 5)

        XCTAssertGreaterThan(points.count, 80_000)
        XCTAssertEqual(RouteInterpolator.steppedPointCount(waypoints: waypoints, stepMeters: 5), points.count)
    }

    /// Legs of 100 km or more used to be skipped (the route jumped to their end).
    func testALongLegIsInterpolatedNotSkipped() {
        let start = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let end = LocationCoordinate(latitude: 36.35, longitude: 139.0) // ~150 km
        let distance = Geo.distance(from: start, to: end)
        XCTAssertGreaterThan(distance, 149_000)

        let points = RouteInterpolator.interpolateRoute(waypoints: [start, end], stepMeters: 3)

        XCTAssertEqual(points.count, Int((distance / 3).rounded(.up)) + 1)
        XCTAssertEqual(RouteInterpolator.steppedPointCount(waypoints: [start, end], stepMeters: 3), points.count)
        XCTAssertEqual(points.first, start)
        XCTAssertEqual(points.last, end)
        XCTAssertEqual(Geo.distance(from: points[0], to: points[1]), 3, accuracy: 0.01)
    }

    func testALongLegOverTheCapIsCountedAndRefused() {
        let start = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let end = LocationCoordinate(latitude: 37.0, longitude: 139.0) // ~222 km at 0.32 m: ~695,000 points
        XCTAssertGreaterThan(RouteInterpolator.steppedPointCount(waypoints: [start, end], stepMeters: 0.32), RouteInterpolator.maxRoutePoints)
        XCTAssertTrue(RouteInterpolator.interpolateRoute(waypoints: [start, end], stepMeters: 0.32).isEmpty)
    }

    func testAShortLegKeepsItsPoints() {
        let start = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        let end = LocationCoordinate(latitude: 35.6800, longitude: 139.6550)
        let distance = Geo.distance(from: start, to: end)

        let points = RouteInterpolator.interpolateRoute(waypoints: [start, end], stepMeters: 0.32)

        XCTAssertEqual(points.count, Int((distance / 0.32).rounded(.up)) + 1)
        let fraction = 10 * 0.32 / distance
        XCTAssertEqual(points[10].latitude, start.latitude + (end.latitude - start.latitude) * fraction, accuracy: 1e-12)
        XCTAssertEqual(points[10].longitude, start.longitude + (end.longitude - start.longitude) * fraction, accuracy: 1e-12)
    }

    func testTheSpeedRouteInterpolatesALongLeg() {
        let start = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let end = LocationCoordinate(latitude: 36.35, longitude: 139.0) // ~150 km at 5.56 m per update
        let points = RouteInterpolator.interpolateRoute(waypoints: [start, end], speed: .fast)
        XCTAssertGreaterThan(points.count, 20_000)
        XCTAssertLessThanOrEqual(points.count, RouteInterpolator.maxRoutePoints)
        XCTAssertEqual(RouteInterpolator.speedPointCount(waypoints: [start, end], speed: .fast), points.count)
        XCTAssertEqual(points.last, end)
    }

    func testTheSpeedRouteOverTheCapIsRefused() {
        let start = LocationCoordinate(latitude: 35.0, longitude: 139.0)
        let end = LocationCoordinate(latitude: 37.0, longitude: 139.0) // ~222 km at 1.4 m per update
        XCTAssertGreaterThan(RouteInterpolator.speedPointCount(waypoints: [start, end], speed: .walking), RouteInterpolator.maxRoutePoints)
        XCTAssertTrue(RouteInterpolator.interpolateRoute(waypoints: [start, end], speed: .walking).isEmpty)
    }

    func testSteppedRouteOverTheCapIsNotCoarsened() {
        // ~44.5 km at 0.32 m needs ~139,000 points. The step must never widen to fit
        // the cap (that moved faster than the shown speed); the route is refused.
        let waypoints = (0...4).map {
            LocationCoordinate(latitude: 35.6762 + Double($0) * 0.1, longitude: 139.6503)
        }

        XCTAssertGreaterThan(
            RouteInterpolator.steppedPointCount(waypoints: waypoints, stepMeters: 0.32),
            RouteInterpolator.maxRoutePoints
        )
        XCTAssertTrue(RouteInterpolator.interpolateRoute(waypoints: waypoints, stepMeters: 0.32).isEmpty)
    }
}
