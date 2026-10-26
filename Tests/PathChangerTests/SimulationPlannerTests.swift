//
//  SimulationPlannerTests.swift
//  PathChangerTests
//
//  Decide what Play should do for Teleport / Multi-Spot / Joystick.
//

import XCTest
@testable import PathChanger

final class SimulationPlannerTests: XCTestCase {

    private let tokyo = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
    private let nearby = LocationCoordinate(latitude: 35.6772, longitude: 139.6513)
    private let farther = LocationCoordinate(latitude: 35.6800, longitude: 139.6550)

    func testTeleportRequiresTarget() {
        let plan = SimulationPlanner.plan(
            mode: .teleport,
            targetLocation: nil,
            currentLocation: tokyo,
            route: [],
            speed: .walking
        )

        XCTAssertEqual(plan, .failed("No target location selected"))
    }

    func testTeleportUsesTarget() {
        let plan = SimulationPlanner.plan(
            mode: .teleport,
            targetLocation: tokyo,
            currentLocation: nil,
            route: [],
            speed: .walking
        )

        XCTAssertEqual(plan, .teleport(tokyo))
    }

    func testRouteRequiresTwoSpots() {
        let plan = SimulationPlanner.plan(
            mode: .route,
            targetLocation: tokyo,
            currentLocation: nil,
            route: [tokyo],
            speed: .walking
        )

        XCTAssertEqual(plan, .failed("Add at least two spots on the map"))
    }

    func testRouteInterpolatesPlaybackPoints() {
        let plan = SimulationPlanner.plan(
            mode: .route,
            targetLocation: nil,
            currentLocation: nil,
            route: [tokyo, nearby, farther],
            speed: .walking
        )

        guard case .route(let points) = plan else {
            return XCTFail("Expected interpolated route, got \(plan)")
        }

        XCTAssertGreaterThan(points.count, 3)
        XCTAssertEqual(points.first?.latitude ?? 0, tokyo.latitude, accuracy: 1e-9)
        XCTAssertEqual(points.last?.latitude ?? 0, farther.latitude, accuracy: 1e-9)
    }

    func testJoystickPrefersTargetLocation() {
        let plan = SimulationPlanner.plan(
            mode: .joystick,
            targetLocation: nearby,
            currentLocation: tokyo,
            route: [],
            speed: .walking
        )

        XCTAssertEqual(plan, .joystick(nearby))
    }

    func testJoystickFallsBackToCurrent() {
        let plan = SimulationPlanner.plan(
            mode: .joystick,
            targetLocation: nil,
            currentLocation: tokyo,
            route: [],
            speed: .walking
        )

        XCTAssertEqual(plan, .joystick(tokyo))
    }

    func testJoystickRequiresAStartLocation() {
        let plan = SimulationPlanner.plan(
            mode: .joystick,
            targetLocation: nil,
            currentLocation: nil,
            route: [tokyo, nearby],
            speed: .walking
        )

        XCTAssertEqual(plan, .failed("Tap the map to set a starting location"))
    }

    func testSettingsModeUsesTeleportRules() {
        let plan = SimulationPlanner.plan(
            mode: .settings,
            targetLocation: tokyo,
            currentLocation: nil,
            route: [],
            speed: .walking
        )

        XCTAssertEqual(plan, .teleport(tokyo))
    }

    func testJumpTeleportsTheCurrentHop() {
        let plan = SimulationPlanner.plan(
            mode: .jump,
            targetLocation: farther,
            currentLocation: tokyo,
            route: [nearby, farther],
            speed: .walking,
            jumpIndex: 0
        )

        XCTAssertEqual(plan, .teleport(nearby))
    }

    func testJumpAdvancesToTheNextHop() {
        let plan = SimulationPlanner.plan(
            mode: .jump,
            targetLocation: farther,
            currentLocation: tokyo,
            route: [nearby, farther],
            speed: .walking,
            jumpIndex: 1
        )

        XCTAssertEqual(plan, .teleport(farther))
    }

    func testJumpFailsWhenHopsAreDone() {
        let plan = SimulationPlanner.plan(
            mode: .jump,
            targetLocation: farther,
            currentLocation: tokyo,
            route: [nearby],
            speed: .walking,
            jumpIndex: 1
        )

        XCTAssertEqual(plan, .failed("All hops done — add another or clear"))
    }

    func testTwoSpotBuildsARouteFromCurrentAndDestination() {
        let plan = SimulationPlanner.plan(
            mode: .twospot,
            targetLocation: nearby,
            currentLocation: tokyo,
            route: [nearby],
            speed: .walking
        )

        guard case .route(let points) = plan else {
            return XCTFail("Expected two-spot route, got \(plan)")
        }

        XCTAssertGreaterThanOrEqual(points.count, 2)
        XCTAssertEqual(points.first?.latitude ?? 0, tokyo.latitude, accuracy: 1e-9)
        XCTAssertEqual(points.last?.latitude ?? 0, nearby.latitude, accuracy: 1e-9)
    }

    func testTwoSpotRequiresBothEnds() {
        let plan = SimulationPlanner.plan(
            mode: .twospot,
            targetLocation: nil,
            currentLocation: nil,
            route: [tokyo],
            speed: .walking
        )

        XCTAssertEqual(plan, .failed("Add a start and a destination"))
    }


    func testJumpIndexAdvancesOnlyForOneAcknowledgedHop() {
        XCTAssertEqual(SimulationPlanner.jumpIndexAfterAcknowledging(currentIndex: 0, routeCount: 2), 1)
        XCTAssertEqual(SimulationPlanner.jumpIndexAfterAcknowledging(currentIndex: 1, routeCount: 2), 2)
        XCTAssertEqual(SimulationPlanner.jumpIndexAfterAcknowledging(currentIndex: 2, routeCount: 2), 2)
    }
}
