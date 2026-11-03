//
//  StopTravelPlan.swift
//  PathChanger
//
//  The stop-by-stop plan shared by Jump, Two-Spot and Multi-Spot
//  (PRODUCT_REQUIREMENTS 3.2-3.4 and 3.6, owner decisions 2026-11-02).
//
//  Pure: no AppState, no device. AppState runs the steps one leg at a time, fetching
//  each leg's road path just before that leg.
//

import Foundation

/// How a mode gets from stop to stop. One set of options for every stop mode; each
/// mode has its own defaults (`defaults(for:)`).
struct StopTravelSettings: Equatable, Codable, Sendable {
    /// Getting there: move along the leg at the travel speed, or teleport to the stop.
    enum Arrival: String, Codable, Sendable, CaseIterable { case travel, jump }
    /// How long a jump waits: the At each stop time, or the trip time at the travel speed.
    enum JumpTiming: String, Codable, Sendable, CaseIterable { case fixed, realistic }
    /// Go through: every stop after one Move, or one stop per Move.
    enum Progression: String, Codable, Sendable, CaseIterable { case automatic, onePerMove }
    /// One way, loop back to the first stop, or back and forth.
    enum RepeatMode: String, Codable, Sendable, CaseIterable { case oneWay, loop, backAndForth }

    static let holdRange: ClosedRange<Double> = 0...60

    var arrival: Arrival
    var jumpTiming: JumpTiming
    /// At each stop: seconds to hold a reached stop before continuing (0 = at once).
    var holdSeconds: Double {
        didSet { holdSeconds = Self.clampedHold(holdSeconds) }
    }
    var progression: Progression
    var repeatMode: RepeatMode

    init(
        arrival: Arrival,
        jumpTiming: JumpTiming,
        holdSeconds: Double,
        progression: Progression,
        repeatMode: RepeatMode
    ) {
        self.arrival = arrival
        self.jumpTiming = jumpTiming
        self.holdSeconds = Self.clampedHold(holdSeconds)
        self.progression = progression
        self.repeatMode = repeatMode
    }

    private enum CodingKeys: String, CodingKey {
        case arrival, jumpTiming, holdSeconds, progression, repeatMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            arrival: try container.decode(Arrival.self, forKey: .arrival),
            jumpTiming: try container.decode(JumpTiming.self, forKey: .jumpTiming),
            holdSeconds: try container.decode(Double.self, forKey: .holdSeconds),
            progression: try container.decode(Progression.self, forKey: .progression),
            repeatMode: try container.decode(RepeatMode.self, forKey: .repeatMode)
        )
    }

    /// Jump: Jump, Fixed, 5 s, one stop per Move, One way (PRODUCT_REQUIREMENTS 3.2).
    /// Two-Spot and Multi-Spot: Travel, 0 s, every stop automatically, One way (3.3, 3.4).
    static func defaults(for mode: AppMode) -> StopTravelSettings {
        switch mode {
        case .jump:
            return StopTravelSettings(arrival: .jump, jumpTiming: .fixed, holdSeconds: 5, progression: .onePerMove, repeatMode: .oneWay)
        case .twospot, .route, .teleport, .joystick, .settings:
            return StopTravelSettings(arrival: .travel, jumpTiming: .fixed, holdSeconds: 0, progression: .automatic, repeatMode: .oneWay)
        }
    }

    private static func clampedHold(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return holdRange.lowerBound }
        return min(max(seconds, holdRange.lowerBound), holdRange.upperBound)
    }
}

/// The path of one leg: the road route, or a straight line when there is none.
struct LegPath: Equatable, Sendable {
    var points: [LocationCoordinate]
    var followsRoads: Bool
    /// Why the leg is not on roads, for the GUI (nil when it follows roads).
    var note: String?

    static func straight(from: LocationCoordinate, to: LocationCoordinate, note: String? = nil) -> LegPath {
        LegPath(points: [from, to], followsRoads: false, note: note)
    }

    var distanceMeters: Double { Geo.totalDistance(of: points) }
}

/// Where a stop run stands between Moves: the next stop to reach and, for back and
/// forth, whether the run is heading back toward the first stop.
struct StopCursor: Equatable, Codable, Sendable {
    var nextIndex: Int
    var reversed: Bool

    init(nextIndex: Int = 0, reversed: Bool = false) {
        self.nextIndex = nextIndex
        self.reversed = reversed
    }
}

/// What the GUI shows about a running stop run (PRODUCT_REQUIREMENTS 3.6).
struct StopProgress: Equatable, Sendable {
    /// What the run is doing now, so the GUI names the phase instead of a bare countdown.
    enum Phase: String, Equatable, Sendable {
        /// Asking for the leg's road route; nothing is sent meanwhile.
        case findingRoute
        /// Applying the points of a travelled leg.
        case travelling
        /// Waiting a Realistic jump's trip time before teleporting.
        case waitingToJump
        /// The teleport to the stop is being applied.
        case jumping
        /// Holding a reached stop for the At each stop time.
        case holding
    }

    /// The stop the run is heading to (while holding: the one after the held stop).
    var nextStopIndex: Int
    var totalStops: Int
    /// Estimated seconds left in the current leg (travel, or a realistic jump's wait).
    var legSecondsLeft: TimeInterval?
    /// Seconds left while holding a reached stop; nil when not holding.
    var holdSecondsLeft: TimeInterval?
    /// The stop being held, while holding.
    var heldStopIndex: Int?
    /// The current leg goes in a straight line because the router found no road route
    /// (it said why); a same-place leg that needed no route is not a fallback.
    var usesStraightLineFallback: Bool
    /// The leg path's note for the straight-line fallback.
    var fallbackNote: String?
    var isPaused: Bool
    /// An informational note about the current leg's road route (a long route or a
    /// detour); nil when there is nothing to say or the leg is a straight line.
    var routeNote: String? = nil
    var phase: Phase = .travelling

    var isHolding: Bool { holdSecondsLeft != nil }
}

/// One leg of a run: from where the run stands to the next stop.
struct StopTravelLeg: Equatable, Sendable {
    /// Nil when the run starts at this stop (the first stop is placed, not travelled to).
    let from: LocationCoordinate?
    let to: LocationCoordinate
    let stopIndex: Int
    /// The cursor once `stopIndex` is reached (and acknowledged).
    let cursorAfter: StopCursor
    /// The Move ends at this stop: one stop per Move, or the last stop of a one-way run.
    let endsMove: Bool
}

/// What a run does, in order.
enum StopTravelStep: Equatable, Sendable {
    /// Apply these points one per update; the last one reaches `stop`.
    case travel(points: [LocationCoordinate], stop: Int)
    /// Wait `waitBefore` seconds (the realistic trip time), then teleport to `stop`.
    case jump(to: LocationCoordinate, stop: Int, waitBefore: TimeInterval)
    /// Hold the reached `stop` before continuing.
    case hold(stop: Int, seconds: TimeInterval)
}

enum StopTravelPlanError: Error, Equatable, Sendable {
    case tooManyPoints
    /// The leg from the held location to the next stop (1-based `stop`) is over the
    /// point cap: a fresh run starts from the held location (owner rule 2026-11-03).
    case tooFarFromHeld(stop: Int, meters: Double)
    case message(String)

    var message: String {
        switch self {
        case .tooManyPoints: return StopTravelPlanner.tooManyPointsMessage
        case .tooFarFromHeld(let stop, let meters): return StopTravelPlanner.tooFarFromHeldMessage(stop: stop, meters: meters)
        case .message(let text): return text
        }
    }
}

enum StopTravelPlanner {
    static let tooManyPointsMessage =
        "This route has too many points for the chosen speed and update frequency. Raise the speed, lower Update frequency in Settings, or use fewer or closer stops."

    /// Says which stop is too far from the held location and what to do instead.
    static func tooFarFromHeldMessage(stop: Int, meters: Double) -> String {
        let distance = meters < 1_000
            ? "\(Int(meters)) m"
            : String(format: meters < 10_000 ? "%.1f km" : "%.0f km", meters / 1_000)
        return "Stop \(stop) is \(distance) from the held location: too far to travel at this speed. Choose Jump in Getting there, or Clear first."
    }

    // MARK: Stops

    /// The ordered stops of a run in `mode`, with the plain message when there are not
    /// enough. Two-Spot: its two endpoints, or the held location and one spot. Jump
    /// returns its valid stops (possibly none: Move then applies the selected spot).
    static func runStops(
        mode: AppMode,
        route: [LocationCoordinate],
        held: LocationCoordinate?,
        target: LocationCoordinate?
    ) -> Result<[LocationCoordinate], StopTravelPlanError> {
        let stops = route.filter(\.isValid)
        switch mode {
        case .twospot:
            if stops.count >= 2 { return .success(Array(stops.prefix(2))) }
            if let start = held, let destination = stops.last ?? target, start != destination {
                return .success([start, destination])
            }
            return .failure(.message("Add a start and a destination"))
        case .route:
            guard stops.count >= 2 else { return .failure(.message("Add at least two spots on the map")) }
            return .success(stops)
        case .jump, .teleport, .joystick, .settings:
            return .success(stops)
        }
    }

    // MARK: Order

    /// The cursor once `cursor.nextIndex` is reached.
    static func cursor(after cursor: StopCursor, stopCount: Int, repeatMode: StopTravelSettings.RepeatMode) -> StopCursor {
        let index = cursor.nextIndex
        guard stopCount >= 2 else { return StopCursor(nextIndex: max(stopCount, index + 1)) }
        switch repeatMode {
        case .oneWay:
            return StopCursor(nextIndex: index + 1)
        case .loop:
            return StopCursor(nextIndex: (index + 1) % stopCount)
        case .backAndForth:
            if cursor.reversed {
                return index - 1 >= 0 ? StopCursor(nextIndex: index - 1, reversed: true) : StopCursor(nextIndex: index + 1)
            }
            return index + 1 < stopCount ? StopCursor(nextIndex: index + 1) : StopCursor(nextIndex: index - 1, reversed: true)
        }
    }

    static func isFinished(_ cursor: StopCursor, stopCount: Int) -> Bool {
        cursor.nextIndex >= stopCount
    }

    // MARK: Legs

    /// The first leg of a Move: from `origin` (the held location; nil to place the stop)
    /// to the next stop not yet reached. A finished One way run starts over at stop 1,
    /// reached from `origin` like any other stop (owner rule 2026-11-03); a finished
    /// cursor of a repeating run continues after the last stop. Nil only with no stops.
    static func firstLeg(
        stops: [LocationCoordinate],
        origin: LocationCoordinate?,
        cursor: StopCursor,
        settings: StopTravelSettings
    ) -> StopTravelLeg? {
        guard !stops.isEmpty else { return nil }
        let current = startCursor(cursor, stopCount: stops.count, repeatMode: settings.repeatMode)
        let target = stops[current.nextIndex]
        return makeLeg(
            from: origin == target ? nil : origin,
            stops: stops,
            cursor: current,
            settings: settings
        )
    }

    /// The cursor a Move starts from: the cursor itself while it has a stop left; once
    /// finished, stop 1 for One way (start over) or the stop after the last for Loop and
    /// Back and forth.
    static func startCursor(_ cursor: StopCursor, stopCount: Int, repeatMode: StopTravelSettings.RepeatMode) -> StopCursor {
        guard cursor.nextIndex >= 0 else { return StopCursor() }
        guard isFinished(cursor, stopCount: stopCount) else { return cursor }
        guard repeatMode != .oneWay, stopCount >= 2 else { return StopCursor() }
        return self.cursor(after: StopCursor(nextIndex: stopCount - 1), stopCount: stopCount, repeatMode: repeatMode)
    }

    /// The leg after `leg` within the same Move; nil when the Move ends at `leg`'s stop.
    static func leg(after leg: StopTravelLeg, stops: [LocationCoordinate], settings: StopTravelSettings) -> StopTravelLeg? {
        guard !leg.endsMove, leg.stopIndex < stops.count,
              !isFinished(leg.cursorAfter, stopCount: stops.count) else { return nil }
        return makeLeg(from: stops[leg.stopIndex], stops: stops, cursor: leg.cursorAfter, settings: settings)
    }

    private static func makeLeg(
        from: LocationCoordinate?,
        stops: [LocationCoordinate],
        cursor: StopCursor,
        settings: StopTravelSettings
    ) -> StopTravelLeg {
        let after = self.cursor(after: cursor, stopCount: stops.count, repeatMode: settings.repeatMode)
        return StopTravelLeg(
            from: from,
            to: stops[cursor.nextIndex],
            stopIndex: cursor.nextIndex,
            cursorAfter: after,
            endsMove: settings.progression == .onePerMove || isFinished(after, stopCount: stops.count)
        )
    }

    /// Whether the leg needs its path: travelled legs, and realistic jumps (road distance).
    static func needsPath(_ leg: StopTravelLeg, settings: StopTravelSettings) -> Bool {
        guard leg.from != nil else { return false }
        return settings.arrival == .travel || settings.jumpTiming == .realistic
    }

    /// The whole Move is one teleport with no wait (the classic single Jump hop).
    static func isSingleImmediateJump(_ leg: StopTravelLeg, settings: StopTravelSettings) -> Bool {
        guard leg.endsMove else { return false }
        return leg.from == nil || (settings.arrival == .jump && settings.jumpTiming == .fixed)
    }

    // MARK: Steps

    /// The steps of one leg: its arrival, then a hold when the Move continues after it.
    /// - Parameter path: the leg's path (nil = straight line).
    static func steps(
        for leg: StopTravelLeg,
        path: LegPath?,
        settings: StopTravelSettings,
        metersPerSecond: Double,
        updateHz: Double
    ) -> Result<[StopTravelStep], StopTravelPlanError> {
        var steps: [StopTravelStep] = []
        if let from = leg.from {
            let points = anchoredPoints(of: path ?? .straight(from: from, to: leg.to), from: from, to: leg.to)
            switch settings.arrival {
            case .travel:
                let stepMeters = metersPerSecond / max(updateHz, 1)
                guard pointCount(points, stepMeters: stepMeters) <= RouteInterpolator.maxRoutePoints else {
                    return .failure(.tooManyPoints)
                }
                var travelled = Array(interpolate(points, stepMeters: stepMeters).dropFirst())
                if travelled.isEmpty {
                    // Only a same-place leg has nothing to travel. Anything else would turn
                    // the travelled leg into a jump to its stop: refuse it instead.
                    guard Geo.totalDistance(of: points) == 0 else { return .failure(.tooManyPoints) }
                    travelled = [leg.to]
                }
                steps.append(.travel(points: travelled, stop: leg.stopIndex))
            case .jump:
                let wait = settings.jumpTiming == .realistic
                    ? Geo.totalDistance(of: points) / max(metersPerSecond, 0.01)
                    : 0
                steps.append(.jump(to: leg.to, stop: leg.stopIndex, waitBefore: wait))
            }
        } else {
            steps.append(.jump(to: leg.to, stop: leg.stopIndex, waitBefore: 0))
        }
        // A fixed jump waits the At each stop time: that wait is this hold.
        if !leg.endsMove, settings.holdSeconds > 0 {
            steps.append(.hold(stop: leg.stopIndex, seconds: settings.holdSeconds))
        }
        return .success(steps)
    }

    /// The leg path, starting at `from` and ending at `to` even if the road route
    /// begins or ends a little away from the stops.
    static func anchoredPoints(of path: LegPath, from: LocationCoordinate, to: LocationCoordinate) -> [LocationCoordinate] {
        var points = path.points.filter(\.isValid)
        if points.first != from { points.insert(from, at: 0) }
        if points.last != to { points.append(to) }
        return points
    }

    /// Points the run applies for a travelled leg if it were a straight line (the
    /// progress estimate before the road path is known).
    static func estimatedPointCount(
        for leg: StopTravelLeg,
        settings: StopTravelSettings,
        metersPerSecond: Double,
        updateHz: Double
    ) -> Int {
        guard let from = leg.from, settings.arrival == .travel else { return 1 }
        let stepMeters = metersPerSecond / max(updateHz, 1)
        return max(pointCount([from, leg.to], stepMeters: stepMeters) - 1, 1)
    }

    /// A refusal known before anything is applied: a travelled leg of one pass through
    /// the stops is over the point cap even in a straight line (a road is never shorter).
    static func straightLineRefusal(
        stops: [LocationCoordinate],
        origin: LocationCoordinate?,
        cursor: StopCursor,
        settings: StopTravelSettings,
        metersPerSecond: Double,
        updateHz: Double
    ) -> StopTravelPlanError? {
        guard settings.arrival == .travel else { return nil }
        let stepMeters = metersPerSecond / max(updateHz, 1)
        var leg = firstLeg(stops: stops, origin: origin, cursor: cursor, settings: settings)
        var checked = 0
        while let current = leg, checked <= stops.count {
            if let from = current.from,
               pointCount([from, current.to], stepMeters: stepMeters) > RouteInterpolator.maxRoutePoints {
                // The first leg leaves from the held location (owner rule 2026-11-03):
                // say which stop is too far and what to do, not "too many points".
                if checked == 0, let origin, from == origin {
                    return .tooFarFromHeld(stop: current.stopIndex + 1, meters: Geo.distance(from: origin, to: current.to))
                }
                return .tooManyPoints
            }
            checked += 1
            leg = self.leg(after: current, stops: stops, settings: settings)
        }
        return nil
    }

    /// Every step of a run, for tests and previews. A repeating run is cut at `maxLegs`.
    static func plan(
        stops: [LocationCoordinate],
        origin: LocationCoordinate?,
        cursor: StopCursor,
        settings: StopTravelSettings,
        metersPerSecond: Double,
        updateHz: Double,
        maxLegs: Int,
        legPath: (LocationCoordinate, LocationCoordinate) -> LegPath = { LegPath.straight(from: $0, to: $1) }
    ) -> Result<[StopTravelStep], StopTravelPlanError> {
        var steps: [StopTravelStep] = []
        var leg = firstLeg(stops: stops, origin: origin, cursor: cursor, settings: settings)
        var legs = 0
        while let current = leg, legs < maxLegs {
            let path = needsPath(current, settings: settings) ? current.from.map { legPath($0, current.to) } : nil
            switch self.steps(for: current, path: path, settings: settings, metersPerSecond: metersPerSecond, updateHz: updateHz) {
            case .success(let legSteps): steps += legSteps
            case .failure(let error): return .failure(error)
            }
            legs += 1
            leg = self.leg(after: current, stops: stops, settings: settings)
        }
        return .success(steps)
    }

    // MARK: Interpolation

    /// A straight leg uses the route interpolator exactly as routes always did; a road
    /// path is walked at a constant step along its whole length.
    private static func interpolate(_ points: [LocationCoordinate], stepMeters: Double) -> [LocationCoordinate] {
        points.count <= 2
            ? RouteInterpolator.interpolateRoute(waypoints: points, stepMeters: stepMeters)
            : RouteInterpolator.interpolatePath(points, stepMeters: stepMeters)
    }

    private static func pointCount(_ points: [LocationCoordinate], stepMeters: Double) -> Int {
        points.count <= 2
            ? RouteInterpolator.steppedPointCount(waypoints: points, stepMeters: stepMeters)
            : RouteInterpolator.steppedPathPointCount(points, stepMeters: stepMeters)
    }
}

/// The run's log lines (category .session). They name stops by number only: never a
/// coordinate.
enum StopRunLog {
    /// At each leg start: how the stop is reached, on what path, how far and how long.
    static func legStart(
        stop: Int,
        of total: Int,
        arrival: StopTravelSettings.Arrival,
        path: LegPath?,
        distanceMeters: Double,
        seconds: TimeInterval
    ) -> String {
        let route: String
        if let path, path.followsRoads {
            route = "road route"
        } else if let note = path?.note, !note.isEmpty {
            route = "straight line: \(note)"
        } else {
            route = "straight line"
        }
        let arrivalName = arrival == .travel ? "travel" : "jump"
        return "[StopRun] Leg to stop \(stop + 1) of \(total) (\(arrivalName), \(route), \(whole(distanceMeters)) m, \(whole(seconds)) s)"
    }

    /// A leg with nothing to travel from: the stop is placed.
    static func placed(stop: Int, of total: Int) -> String {
        "[StopRun] Leg to stop \(stop + 1) of \(total) (jump, placed, 0 m, 0 s)"
    }

    /// An acknowledged arrival.
    static func reached(stop: Int, of total: Int) -> String {
        "[StopRun] Reached stop \(stop + 1) of \(total)"
    }

    static func ended(_ reason: String) -> String {
        "[StopRun] Run ended: \(reason)"
    }

    private static func whole(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        return Int(value.rounded())
    }
}
