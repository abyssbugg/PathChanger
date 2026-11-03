//
//  StopTravelPlanTests.swift
//  PathChangerTests
//
//  The stop-by-stop planner shared by Jump, Two-Spot and Multi-Spot
//  (PRODUCT_REQUIREMENTS 3.2-3.4 and 3.6, owner decisions 2026-11-02).
//

import XCTest
@testable import PathChanger

final class StopTravelPlanTests: XCTestCase {

    private let a = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
    private let b = LocationCoordinate(latitude: 35.6772, longitude: 139.6513)
    private let c = LocationCoordinate(latitude: 35.6800, longitude: 139.6550)

    private func settings(
        _ arrival: StopTravelSettings.Arrival,
        timing: StopTravelSettings.JumpTiming = .fixed,
        hold: Double = 0,
        progression: StopTravelSettings.Progression = .automatic,
        repeat repeatMode: StopTravelSettings.RepeatMode = .oneWay
    ) -> StopTravelSettings {
        StopTravelSettings(
            arrival: arrival,
            jumpTiming: timing,
            holdSeconds: hold,
            progression: progression,
            repeatMode: repeatMode
        )
    }

    private func plan(
        _ stops: [LocationCoordinate],
        origin: LocationCoordinate? = nil,
        cursor: StopCursor = StopCursor(),
        settings: StopTravelSettings,
        metersPerSecond: Double = 1.6,
        updateHz: Double = 5,
        maxLegs: Int = 100,
        legPath: (LocationCoordinate, LocationCoordinate) -> LegPath = { LegPath.straight(from: $0, to: $1) }
    ) -> Result<[StopTravelStep], StopTravelPlanError> {
        StopTravelPlanner.plan(
            stops: stops,
            origin: origin,
            cursor: cursor,
            settings: settings,
            metersPerSecond: metersPerSecond,
            updateHz: updateHz,
            maxLegs: maxLegs,
            legPath: legPath
        )
    }

    private func steps(_ result: Result<[StopTravelStep], StopTravelPlanError>, file: StaticString = #filePath, line: UInt = #line) -> [StopTravelStep] {
        switch result {
        case .success(let steps): return steps
        case .failure(let error):
            XCTFail("unexpected refusal: \(error.message)", file: file, line: line)
            return []
        }
    }

    /// The stop each arrival step reaches, holds excluded.
    private func reachedStops(_ steps: [StopTravelStep]) -> [Int] {
        steps.compactMap { step in
            switch step {
            case .travel(_, let stop), .jump(_, let stop, _): return stop
            case .hold: return nil
            }
        }
    }

    /// Every coordinate the run applies, in order.
    private func appliedPoints(_ steps: [StopTravelStep]) -> [LocationCoordinate] {
        steps.flatMap { step -> [LocationCoordinate] in
            switch step {
            case .travel(let points, _): return points
            case .jump(let to, _, _): return [to]
            case .hold: return []
            }
        }
    }

    // MARK: - Settings

    func testDefaultsFollowTheOwnerDecisionPerMode() {
        XCTAssertEqual(StopTravelSettings.defaults(for: .jump), settings(.jump, hold: 5, progression: .onePerMove))
        for mode in [AppMode.twospot, .route] {
            XCTAssertEqual(StopTravelSettings.defaults(for: mode), settings(.travel, hold: 0, progression: .automatic), "\(mode)")
        }
    }

    func testHoldIsClampedToZeroToSixtySeconds() throws {
        XCTAssertEqual(settings(.travel, hold: 90).holdSeconds, 60)
        XCTAssertEqual(settings(.travel, hold: -3).holdSeconds, 0)
        XCTAssertEqual(settings(.travel, hold: .nan).holdSeconds, 0)
        var value = settings(.travel, hold: 4)
        value.holdSeconds = 120
        XCTAssertEqual(value.holdSeconds, 60)

        let json = #"{"arrival":"jump","jumpTiming":"realistic","holdSeconds":500,"progression":"onePerMove","repeatMode":"backAndForth"}"#
        let decoded = try JSONDecoder().decode(StopTravelSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, settings(.jump, timing: .realistic, hold: 60, progression: .onePerMove, repeat: .backAndForth))
        let roundTrip = try JSONDecoder().decode(StopTravelSettings.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(roundTrip, decoded)
    }

    // MARK: - Stop order

    func testRepeatModesVisitStopsInTheirOrder() {
        func order(_ repeatMode: StopTravelSettings.RepeatMode, legs: Int) -> [Int] {
            reachedStops(steps(plan([a, b, c], settings: settings(.jump, repeat: repeatMode), maxLegs: legs)))
        }
        XCTAssertEqual(order(.oneWay, legs: 20), [0, 1, 2], "one way ends at the last stop")
        XCTAssertEqual(order(.loop, legs: 7), [0, 1, 2, 0, 1, 2, 0], "loop goes home to the first stop and continues")
        XCTAssertEqual(order(.backAndForth, legs: 7), [0, 1, 2, 1, 0, 1, 2], "back and forth reverses at each end")
    }

    func testLoopTravelsHomeTheSameWayAsTheOtherLegs() {
        let result = steps(plan([a, b, c], settings: settings(.travel, repeat: .loop), metersPerSecond: 50, maxLegs: 4))
        XCTAssertEqual(reachedStops(result), [0, 1, 2, 0])
        guard case .travel(let home, 0) = result.last else {
            return XCTFail("the home leg is travelled, got \(String(describing: result.last))")
        }
        XCTAssertGreaterThan(home.count, 1)
        XCTAssertEqual(home.last, a)
        XCTAssertLessThan(Geo.distance(from: home[0], to: c), 50 / 5 + 0.01, "the home leg starts one step from the last stop")
    }

    func testAFinishedCursorWrapsWhenTheRunRepeats() {
        let finished = StopCursor(nextIndex: 3)
        let loop = StopTravelPlanner.firstLeg(stops: [a, b, c], origin: c, cursor: finished, settings: settings(.jump, repeat: .loop))
        XCTAssertEqual(loop?.stopIndex, 0)
        let backAndForth = StopTravelPlanner.firstLeg(stops: [a, b, c], origin: c, cursor: finished, settings: settings(.jump, repeat: .backAndForth))
        XCTAssertEqual(backAndForth?.stopIndex, 1)
    }

    /// Owner rule 2026-11-03 (3): a finished One way run starts over at stop 1, reached
    /// from the held location per Getting there; with nothing held, stop 1 is placed.
    /// (It used to return nil: "All hops done".)
    func testAFinishedOneWayRunStartsOverAtTheFirstStop() {
        let finished = StopCursor(nextIndex: 3)
        for arrival in StopTravelSettings.Arrival.allCases {
            for progression in StopTravelSettings.Progression.allCases {
                let options = settings(arrival, progression: progression)
                let label = "\(arrival) \(progression)"
                let fromHeld = StopTravelPlanner.firstLeg(stops: [a, b, c], origin: c, cursor: finished, settings: options)
                XCTAssertEqual(fromHeld?.stopIndex, 0, label)
                XCTAssertEqual(fromHeld?.from, c, "reached from the held location, not placed (\(label))")
                XCTAssertEqual(fromHeld?.cursorAfter, StopCursor(nextIndex: 1), label)
                XCTAssertEqual(fromHeld?.endsMove, progression == .onePerMove, label)

                let placed = StopTravelPlanner.firstLeg(stops: [a, b, c], origin: nil, cursor: finished, settings: options)
                XCTAssertEqual(placed?.stopIndex, 0, label)
                XCTAssertNil(placed?.from, "nothing held: stop 1 is placed (\(label))")
            }
        }
        // One stop: the run starts over at it.
        XCTAssertEqual(
            StopTravelPlanner.firstLeg(stops: [a], origin: a, cursor: StopCursor(nextIndex: 1), settings: settings(.jump, repeat: .loop))?.stopIndex,
            0
        )
        XCTAssertNil(StopTravelPlanner.firstLeg(stops: [], origin: a, cursor: StopCursor(), settings: settings(.jump)), "no stops, no leg")
    }

    func testAStartOverIsTravelledFromTheHeldLocation() {
        let result = steps(plan([a, b], origin: b, cursor: StopCursor(nextIndex: 2), settings: settings(.travel, progression: .onePerMove), metersPerSecond: 50))
        guard case .travel(let points, 0) = result.first, result.count == 1 else {
            return XCTFail("one travelled leg to stop 1, got \(result)")
        }
        XCTAssertGreaterThan(points.count, 1, "never a silent teleport")
        XCTAssertEqual(points.last, a)
        XCTAssertLessThan(Geo.distance(from: points[0], to: b), 50 / 5 + 0.01)
    }

    // MARK: - Run log lines (no coordinates)

    func testRunLogLinesNameTheLegWithoutCoordinates() {
        XCTAssertEqual(
            StopRunLog.legStart(stop: 2, of: 5, arrival: .travel, path: LegPath(points: [a, b, c], followsRoads: true, note: nil), distanceMeters: 812.4, seconds: 50.6),
            "[StopRun] Leg to stop 3 of 5 (travel, road route, 812 m, 51 s)"
        )
        XCTAssertEqual(
            StopRunLog.legStart(stop: 0, of: 2, arrival: .travel, path: .straight(from: a, to: b, note: MapKitRoadRouter.straightLineNote), distanceMeters: 140, seconds: 7),
            "[StopRun] Leg to stop 1 of 2 (travel, straight line: \(MapKitRoadRouter.straightLineNote), 140 m, 7 s)"
        )
        XCTAssertEqual(
            StopRunLog.legStart(stop: 1, of: 3, arrival: .jump, path: nil, distanceMeters: 99.6, seconds: 0),
            "[StopRun] Leg to stop 2 of 3 (jump, straight line, 100 m, 0 s)"
        )
        XCTAssertEqual(StopRunLog.placed(stop: 0, of: 3), "[StopRun] Leg to stop 1 of 3 (jump, placed, 0 m, 0 s)")
        XCTAssertEqual(StopRunLog.reached(stop: 2, of: 3), "[StopRun] Reached stop 3 of 3")
        XCTAssertEqual(StopRunLog.ended("Stop"), "[StopRun] Run ended: Stop")
    }

    // MARK: - Travel

    func testOneWayTravelAppliesTheSamePointsAsTheRouteInterpolator() {
        // Default Two-Spot / Multi-Spot behaviour must not change: the first stop is
        // placed, then each leg is walked at speed / update rate, ending on its stop.
        let result = steps(plan([a, b, c], settings: .defaults(for: .route)))
        XCTAssertEqual(reachedStops(result), [0, 1, 2])
        guard case .jump(a, 0, 0) = result.first else {
            return XCTFail("the first stop is placed with no wait, got \(String(describing: result.first))")
        }
        XCTAssertEqual(appliedPoints(result), RouteInterpolator.interpolateRoute(waypoints: [a, b, c], stepMeters: 1.6 / 5))
        XCTAssertFalse(result.contains { if case .hold = $0 { return true }; return false }, "no holds by default")
    }

    func testTravelFollowsTheRoadPathAtTheShownSpeed() {
        let corner = LocationCoordinate(latitude: a.latitude, longitude: b.longitude)
        let road = LegPath(points: [a, corner, b], followsRoads: true, note: nil)
        let result = steps(plan([b], origin: a, settings: settings(.travel), metersPerSecond: 10, updateHz: 2, legPath: { _, _ in road }))
        guard case .travel(let points, 0) = result.first, result.count == 1 else {
            return XCTFail("one travelled leg, got \(result)")
        }
        XCTAssertEqual(points.last, b)
        // The path turns at the corner instead of cutting across.
        let nearCorner = points.map { Geo.distance(from: $0, to: corner) }.min() ?? .infinity
        XCTAssertLessThan(nearCorner, 5.01)
        // 5 m of road per update; only the step across the corner is a shorter chord.
        let spacings = zip([a] + points.dropLast(), points.dropLast()).map { Geo.distance(from: $0, to: $1) }
        XCTAssertTrue(spacings.allSatisfy { $0 <= 5.01 }, "\(spacings)")
        XCTAssertLessThanOrEqual(spacings.filter { abs($0 - 5) > 0.01 }.count, 1, "\(spacings)")
        let roadLength = Geo.totalDistance(of: road.points)
        XCTAssertEqual(Double(points.count), (roadLength / 5).rounded(.up), accuracy: 1)
    }

    func testARoadPathIsAnchoredAtBothStops() {
        let offset = LocationCoordinate(latitude: a.latitude + 0.0001, longitude: a.longitude)
        let road = LegPath(points: [offset, b], followsRoads: true, note: nil)
        let points = StopTravelPlanner.anchoredPoints(of: road, from: a, to: c)
        XCTAssertEqual(points, [a, offset, b, c])
    }

    // MARK: - Holds and waits

    func testHoldsAtEveryReachedStopExceptTheEndOfAOneWayRun() {
        let result = steps(plan([a, b, c], settings: settings(.travel, hold: 3), metersPerSecond: 50))
        let holds = result.compactMap { step -> Int? in if case .hold(let stop, 3) = step { return stop }; return nil }
        XCTAssertEqual(holds, [0, 1])
        let looped = steps(plan([a, b, c], settings: settings(.travel, hold: 3, repeat: .loop), metersPerSecond: 50, maxLegs: 3))
        guard case .hold(2, 3) = looped.last else {
            return XCTFail("a repeating run holds the last stop too, got \(String(describing: looped.last))")
        }
    }

    func testAutoJumpDefaultsHoldEachStopForThePause() {
        // Default Auto jump: a fixed jump waits the At each stop time, which is the hold.
        var auto = StopTravelSettings.defaults(for: .jump)
        auto.progression = .automatic
        auto.holdSeconds = 7
        XCTAssertEqual(steps(plan([a, b, c], settings: auto)), [
            .jump(to: a, stop: 0, waitBefore: 0),
            .hold(stop: 0, seconds: 7),
            .jump(to: b, stop: 1, waitBefore: 0),
            .hold(stop: 1, seconds: 7),
            .jump(to: c, stop: 2, waitBefore: 0),
        ])
    }

    func testRealisticJumpWaitsTheStraightLineTripTime() {
        let result = steps(plan([a, b], settings: settings(.jump, timing: .realistic), metersPerSecond: 10))
        guard case .jump(b, 1, let wait) = result.last else { return XCTFail("\(result)") }
        XCTAssertEqual(wait, Geo.distance(from: a, to: b) / 10, accuracy: 1e-9)
        guard case .jump(a, 0, 0) = result.first else { return XCTFail("placing the first stop needs no trip") }
    }

    func testRealisticJumpUsesTheRoadDistanceWhenTheLegFollowsRoads() {
        let corner = LocationCoordinate(latitude: a.latitude, longitude: b.longitude)
        let road = LegPath(points: [a, corner, b], followsRoads: true, note: nil)
        let result = steps(plan([b], origin: a, settings: settings(.jump, timing: .realistic, hold: 2, progression: .onePerMove), metersPerSecond: 10, legPath: { _, _ in road }))
        XCTAssertEqual(result.count, 1, "one stop per Move ends at the stop: no timed hold")
        guard case .jump(b, 0, let wait) = result.first else { return XCTFail("\(result)") }
        XCTAssertEqual(wait, Geo.totalDistance(of: [a, corner, b]) / 10, accuracy: 1e-9)
        XCTAssertGreaterThan(wait, Geo.distance(from: a, to: b) / 10)
    }

    func testFixedJumpNeedsNoPathAndRealisticOrTravelDoes() {
        let leg = StopTravelPlanner.firstLeg(stops: [a, b], origin: a, cursor: StopCursor(nextIndex: 1), settings: settings(.jump))!
        XCTAssertFalse(StopTravelPlanner.needsPath(leg, settings: settings(.jump)))
        XCTAssertTrue(StopTravelPlanner.needsPath(leg, settings: settings(.jump, timing: .realistic)))
        XCTAssertTrue(StopTravelPlanner.needsPath(leg, settings: settings(.travel)))
        let placement = StopTravelPlanner.firstLeg(stops: [a, b], origin: nil, cursor: StopCursor(), settings: settings(.travel))!
        XCTAssertNil(placement.from)
        XCTAssertFalse(StopTravelPlanner.needsPath(placement, settings: settings(.travel)))
    }

    // MARK: - One stop per Move

    func testOnePerMoveGoesToTheNextStopAndEndsThere() {
        let travel = steps(plan([a, b, c], origin: a, cursor: StopCursor(nextIndex: 1), settings: settings(.travel, hold: 5, progression: .onePerMove), metersPerSecond: 50))
        XCTAssertEqual(reachedStops(travel), [1])
        guard case .travel(let points, 1) = travel.first else { return XCTFail("\(travel)") }
        XCTAssertEqual(points.last, b)
        let jump = StopTravelPlanner.firstLeg(stops: [a, b, c], origin: a, cursor: StopCursor(nextIndex: 1), settings: settings(.jump, progression: .onePerMove))!
        XCTAssertTrue(jump.endsMove)
        XCTAssertEqual(jump.cursorAfter, StopCursor(nextIndex: 2))
        XCTAssertTrue(StopTravelPlanner.isSingleImmediateJump(jump, settings: settings(.jump, progression: .onePerMove)))
        XCTAssertFalse(StopTravelPlanner.isSingleImmediateJump(jump, settings: settings(.jump, timing: .realistic, progression: .onePerMove)))
        XCTAssertFalse(StopTravelPlanner.isSingleImmediateJump(jump, settings: settings(.travel, progression: .onePerMove)))
    }

    func testOnePerMoveBackAndForthKeepsItsDirectionBetweenMoves() {
        let settings = settings(.jump, progression: .onePerMove, repeat: .backAndForth)
        var cursor = StopCursor(nextIndex: 2)
        var visited: [Int] = []
        for _ in 0..<4 {
            guard let leg = StopTravelPlanner.firstLeg(stops: [a, b, c], origin: b, cursor: cursor, settings: settings) else {
                return XCTFail("back and forth never ends")
            }
            visited.append(leg.stopIndex)
            cursor = leg.cursorAfter
        }
        XCTAssertEqual(visited, [2, 1, 0, 1])
    }

    // MARK: - Stops per mode

    func testRunStopsPerMode() {
        XCTAssertEqual(StopTravelPlanner.runStops(mode: .twospot, route: [a, b, c], held: nil, target: nil), .success([a, b]))
        XCTAssertEqual(StopTravelPlanner.runStops(mode: .twospot, route: [b], held: a, target: b), .success([a, b]), "a held location and one spot")
        XCTAssertEqual(StopTravelPlanner.runStops(mode: .twospot, route: [], held: nil, target: b), .failure(.message("Add a start and a destination")))
        XCTAssertEqual(StopTravelPlanner.runStops(mode: .route, route: [a], held: a, target: a), .failure(.message("Add at least two spots on the map")))
        XCTAssertEqual(StopTravelPlanner.runStops(mode: .route, route: [a, b, c], held: nil, target: nil), .success([a, b, c]))
        XCTAssertEqual(StopTravelPlanner.runStops(mode: .jump, route: [a, b], held: c, target: nil), .success([a, b]))
    }

    // MARK: - Point cap

    func testALegOverThePointCapIsRefusedWithThePlainMessage() {
        // ~44.5 km in one leg at 0.32 m per update needs ~139,000 points.
        let far = LocationCoordinate(latitude: a.latitude + 0.4, longitude: a.longitude)
        guard case .failure(let error) = plan([a, far], settings: .defaults(for: .twospot)) else {
            return XCTFail("an over-long leg must be refused, not sped up")
        }
        XCTAssertEqual(error, .tooManyPoints)
        XCTAssertEqual(error.message, StopTravelPlanner.tooManyPointsMessage)
        XCTAssertEqual(
            StopTravelPlanner.tooManyPointsMessage,
            "This route has too many points for the chosen speed and update frequency. Raise the speed, lower Update frequency in Settings, or use fewer or closer stops."
        )
        XCTAssertEqual(
            StopTravelPlanner.straightLineRefusal(stops: [a, far], origin: nil, cursor: StopCursor(), settings: .defaults(for: .twospot), metersPerSecond: 1.6, updateHz: 5),
            .tooManyPoints
        )
    }

    func testTheCapIsPerLegNotPerRoute() {
        // Four ~11 km legs need ~139,000 points in total but ~35,000 each.
        let stops = (0...4).map { LocationCoordinate(latitude: a.latitude + Double($0) * 0.1, longitude: a.longitude) }
        XCTAssertEqual(reachedStops(steps(plan(stops, settings: .defaults(for: .route)))), [0, 1, 2, 3, 4])
        XCTAssertNil(StopTravelPlanner.straightLineRefusal(stops: stops, origin: nil, cursor: StopCursor(), settings: .defaults(for: .route), metersPerSecond: 1.6, updateHz: 5))
    }

    func testAJumpRunIsNeverRefusedForPoints() {
        let far = LocationCoordinate(latitude: a.latitude + 0.4, longitude: a.longitude)
        XCTAssertEqual(reachedStops(steps(plan([a, far], settings: settings(.jump, timing: .realistic)))), [0, 1])
    }

    // MARK: - Interpolation

    func testPathInterpolationMatchesTheRouteInterpolatorOnAStraightLeg() {
        let path = RouteInterpolator.interpolatePath([a, c], stepMeters: 3)
        XCTAssertEqual(path.count, RouteInterpolator.interpolateRoute(waypoints: [a, c], stepMeters: 3).count)
        XCTAssertEqual(path.count, RouteInterpolator.steppedPathPointCount([a, c], stepMeters: 3))
        for (lhs, rhs) in zip(path, RouteInterpolator.interpolateRoute(waypoints: [a, c], stepMeters: 3)) {
            XCTAssertEqual(lhs.latitude, rhs.latitude, accuracy: 1e-12)
            XCTAssertEqual(lhs.longitude, rhs.longitude, accuracy: 1e-12)
        }
    }

    func testTheStraightLineLegPathCarriesItsNote() {
        let straight = LegPath.straight(from: a, to: b, note: "No road route; going in a straight line")
        XCTAssertEqual(straight.points, [a, b])
        XCTAssertFalse(straight.followsRoads)
        XCTAssertEqual(straight.note, "No road route; going in a straight line")
        XCTAssertEqual(straight.distanceMeters, Geo.distance(from: a, to: b), accuracy: 1e-9)
    }
}
