//
//  SimulationPlanner.swift
//  PathChanger
//
//  Decide what Play should inject for each sidebar mode.
//

import Foundation

enum SimulationStartPlan: Equatable {
    case teleport(LocationCoordinate)
    case route([LocationCoordinate])
    case joystick(LocationCoordinate)
    case failed(String)
}

enum SimulationPlanner {
    static func plan(
        mode: AppMode,
        targetLocation: LocationCoordinate?,
        currentLocation: LocationCoordinate?,
        route: [LocationCoordinate],
        speed: SimulationSpeed,
        jumpIndex: Int = 0,
        stepMeters: Double? = nil
    ) -> SimulationStartPlan {
        switch mode {
        case .route:
            return planRoute(route: route, speed: speed, stepMeters: stepMeters)
        case .twospot:
            return planTwoSpot(
                targetLocation: targetLocation,
                currentLocation: currentLocation,
                route: route,
                speed: speed,
                stepMeters: stepMeters
            )
        case .jump:
            return planJump(targetLocation: targetLocation, route: route, jumpIndex: jumpIndex)
        case .joystick:
            return planJoystick(targetLocation: targetLocation, currentLocation: currentLocation)
        case .teleport, .settings:
            return planTeleport(targetLocation: targetLocation)
        }
    }

    static func jumpIndexAfterAcknowledging(currentIndex: Int, routeCount: Int) -> Int {
        min(max(currentIndex, 0) + 1, max(routeCount, 0))
    }

    private static func planTeleport(targetLocation: LocationCoordinate?) -> SimulationStartPlan {
        guard let target = targetLocation else {
            return .failed("No target location selected")
        }
        return .teleport(target)
    }

    private static func planJump(
        targetLocation: LocationCoordinate?,
        route: [LocationCoordinate],
        jumpIndex: Int
    ) -> SimulationStartPlan {
        let hops = route.filter(\.isValid)
        if hops.isEmpty {
            return planTeleport(targetLocation: targetLocation)
        }
        guard jumpIndex < hops.count else {
            return .failed("All hops done — add another or clear")
        }
        return .teleport(hops[jumpIndex])
    }

    private static func planTwoSpot(
        targetLocation: LocationCoordinate?,
        currentLocation: LocationCoordinate?,
        route: [LocationCoordinate],
        speed: SimulationSpeed,
        stepMeters: Double?
    ) -> SimulationStartPlan {
        let stops = route.filter(\.isValid)
        if stops.count >= 2 {
            return planRoute(route: Array(stops.prefix(2)), speed: speed, stepMeters: stepMeters)
        }
        if let start = currentLocation ?? (stops.count == 2 ? stops.first : nil),
           let dest = stops.last ?? targetLocation,
           start != dest {
            return planRoute(route: [start, dest], speed: speed, stepMeters: stepMeters)
        }
        return .failed("Add a start and a destination")
    }

    /// - Parameter stepMeters: distance per playback update (shown speed / update rate).
    ///   When nil, the preset's legacy spacing is used.
    private static func planRoute(
        route: [LocationCoordinate],
        speed: SimulationSpeed,
        stepMeters: Double? = nil
    ) -> SimulationStartPlan {
        let waypoints = route.filter(\.isValid)
        guard waypoints.count >= 2 else {
            return .failed("Add at least two spots on the map")
        }

        // Never widen the step to fit a long route: that would move faster than shown.
        let pointCount = stepMeters.map {
            RouteInterpolator.steppedPointCount(waypoints: waypoints, stepMeters: $0)
        } ?? RouteInterpolator.speedPointCount(waypoints: waypoints, speed: speed)
        if pointCount > RouteInterpolator.maxRoutePoints {
            return .failed(StopTravelPlanner.tooManyPointsMessage)
        }

        let points = stepMeters.map {
            RouteInterpolator.interpolateRoute(waypoints: waypoints, stepMeters: $0)
        } ?? RouteInterpolator.interpolateRoute(waypoints: waypoints, speed: speed)
        guard points.count >= 2 else {
            return .failed("Route is too short to play")
        }
        return .route(points)
    }

    private static func planJoystick(
        targetLocation: LocationCoordinate?,
        currentLocation: LocationCoordinate?
    ) -> SimulationStartPlan {
        guard let start = targetLocation ?? currentLocation else {
            return .failed("Tap the map to set a starting location")
        }
        return .joystick(start)
    }
}

enum LocationHistoryPolicy {
    static func shouldRecord(
        canStartSimulation: Bool,
        plan: SimulationStartPlan
    ) -> Bool {
        guard canStartSimulation else { return false }
        if case .failed = plan { return false }
        return true
    }

    static func coordinate(for plan: SimulationStartPlan) -> LocationCoordinate? {
        switch plan {
        case .teleport(let coordinate), .joystick(let coordinate):
            return coordinate
        case .route(let points):
            return points.last
        case .failed:
            return nil
        }
    }
}
