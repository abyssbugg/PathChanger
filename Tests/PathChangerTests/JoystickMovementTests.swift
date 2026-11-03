//
//  JoystickMovementTests.swift
//  PathChangerTests
//
//  Joystick vector → next GPS coordinate.
//

import XCTest
@testable import PathChanger

final class JoystickMovementTests: XCTestCase {

    private let origin = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
    private let speed = 10.0
    private let dt = 1.0

    func testZeroDirectionDoesNotMove() {
        let next = JoystickMovement.nextCoordinate(
            from: origin,
            direction: .zero,
            speedMetersPerSecond: speed,
            deltaTime: dt
        )

        XCTAssertEqual(next.latitude, origin.latitude, accuracy: 1e-9)
        XCTAssertEqual(next.longitude, origin.longitude, accuracy: 1e-9)
    }

    func testTinyDirectionIsTreatedAsStop() {
        let next = JoystickMovement.nextCoordinate(
            from: origin,
            direction: CGPoint(x: 0.01, y: 0.01),
            speedMetersPerSecond: speed,
            deltaTime: dt
        )

        XCTAssertEqual(next.latitude, origin.latitude, accuracy: 1e-9)
        XCTAssertEqual(next.longitude, origin.longitude, accuracy: 1e-9)
    }

    func testNorthIncreasesLatitude() {
        let next = JoystickMovement.nextCoordinate(
            from: origin,
            direction: CGPoint(x: 0, y: 1),
            speedMetersPerSecond: speed,
            deltaTime: dt
        )

        XCTAssertGreaterThan(next.latitude, origin.latitude)
        XCTAssertEqual(next.longitude, origin.longitude, accuracy: 1e-6)
    }

    func testEastIncreasesLongitude() {
        let next = JoystickMovement.nextCoordinate(
            from: origin,
            direction: CGPoint(x: 1, y: 0),
            speedMetersPerSecond: speed,
            deltaTime: dt
        )

        XCTAssertGreaterThan(next.longitude, origin.longitude)
        XCTAssertEqual(next.latitude, origin.latitude, accuracy: 1e-6)
    }

    func testSouthDecreasesLatitude() {
        let next = JoystickMovement.nextCoordinate(
            from: origin,
            direction: CGPoint(x: 0, y: -1),
            speedMetersPerSecond: speed,
            deltaTime: dt
        )

        XCTAssertLessThan(next.latitude, origin.latitude)
    }

    func testFullStickTravelsExpectedDistance() {
        let next = JoystickMovement.nextCoordinate(
            from: origin,
            direction: CGPoint(x: 0, y: 1),
            speedMetersPerSecond: speed,
            deltaTime: dt
        )

        let traveled = RouteInterpolator.haversineDistance(from: origin, to: next)
        XCTAssertEqual(traveled, speed * dt, accuracy: 0.5)
    }

    func testHalfStickTravelsHalfDistance() {
        let full = JoystickMovement.nextCoordinate(
            from: origin,
            direction: CGPoint(x: 0, y: 1),
            speedMetersPerSecond: speed,
            deltaTime: dt
        )
        let half = JoystickMovement.nextCoordinate(
            from: origin,
            direction: CGPoint(x: 0, y: 0.5),
            speedMetersPerSecond: speed,
            deltaTime: dt
        )

        let fullDistance = RouteInterpolator.haversineDistance(from: origin, to: full)
        let halfDistance = RouteInterpolator.haversineDistance(from: origin, to: half)
        XCTAssertEqual(halfDistance, fullDistance / 2, accuracy: 0.5)
    }

    func testDiagonalDoesNotMoveFasterThanCardinal() {
        let north = JoystickMovement.nextCoordinate(
            from: origin,
            direction: CGPoint(x: 0, y: 1),
            speedMetersPerSecond: speed,
            deltaTime: dt
        )
        let northeast = JoystickMovement.nextCoordinate(
            from: origin,
            direction: CGPoint(x: 1, y: 1),
            speedMetersPerSecond: speed,
            deltaTime: dt
        )

        let northDistance = RouteInterpolator.haversineDistance(from: origin, to: north)
        let diagonalDistance = RouteInterpolator.haversineDistance(from: origin, to: northeast)
        XCTAssertEqual(diagonalDistance, northDistance, accuracy: 0.5)
    }


    func testLatestDirectionCanBeAppliedFromLastAcknowledgedCoordinate() {
        let unchangedOrigin = origin
        let firstProposal = JoystickMovement.nextCoordinate(
            from: origin,
            direction: CGPoint(x: 1, y: 0),
            speedMetersPerSecond: speed,
            deltaTime: dt
        )
        let latestProposal = JoystickMovement.nextCoordinate(
            from: origin,
            direction: CGPoint(x: -1, y: 0),
            speedMetersPerSecond: speed,
            deltaTime: dt
        )
        XCTAssertGreaterThan(firstProposal.longitude, origin.longitude)
        XCTAssertLessThan(latestProposal.longitude, origin.longitude)
        XCTAssertEqual(origin, unchangedOrigin)
    }

    // MARK: - Date line

    /// East across 180 used to give a longitude over 180, which is invalid, so the move
    /// returned the start and the joystick stalled at the line.
    func testMovingEastAcrossTheDateLineContinuesFromMinus180() {
        let start = LocationCoordinate(latitude: 10, longitude: 179.9999)
        let next = JoystickMovement.nextCoordinate(from: start, direction: CGPoint(x: 1, y: 0), speedMetersPerSecond: 30, deltaTime: 1)

        XCTAssertTrue(next.isValid)
        XCTAssertNotEqual(next, start)
        XCTAssertLessThan(next.longitude, -179.999)
        XCTAssertEqual(Geo.distance(from: start, to: next), 30, accuracy: 0.01)
    }

    func testMovingWestAcrossTheDateLineContinuesFrom180() {
        let start = LocationCoordinate(latitude: -10, longitude: -179.9999)
        let next = JoystickMovement.nextCoordinate(from: start, direction: CGPoint(x: -1, y: 0), speedMetersPerSecond: 30, deltaTime: 1)

        XCTAssertTrue(next.isValid)
        XCTAssertNotEqual(next, start)
        XCTAssertGreaterThan(next.longitude, 179.999)
        XCTAssertEqual(Geo.distance(from: start, to: next), 30, accuracy: 0.01)
    }

    func testRepeatedEastwardTicksKeepMovingThroughTheDateLine() {
        var position = LocationCoordinate(latitude: 0, longitude: 179.9990)
        var previousUnwrapped = position.longitude
        for _ in 0..<20 {
            let next = JoystickMovement.nextCoordinate(from: position, direction: CGPoint(x: 1, y: 0), speedMetersPerSecond: 10, deltaTime: 1)
            XCTAssertTrue(next.isValid)
            let unwrapped = next.longitude < 0 ? next.longitude + 360 : next.longitude
            XCTAssertGreaterThan(unwrapped, previousUnwrapped)
            previousUnwrapped = unwrapped
            position = next
        }
        XCTAssertLessThan(position.longitude, 0, "20 × 10 m from 179.999 ends past the line")
    }
}
