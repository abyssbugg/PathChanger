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
        speed: SimulationSpeed
    ) -> SimulationStartPlan {
        switch mode {
        case .route:
            return planRoute(route: route, speed: speed)
        case .joystick:
            return planJoystick(targetLocation: targetLocation, currentLocation: currentLocation)
        case .teleport, .settings:
            return planTeleport(targetLocation: targetLocation)
        }
    }

    private static func planTeleport(targetLocation: LocationCoordinate?) -> SimulationStartPlan {
        guard let target = targetLocation else {
            return .failed("No target location selected")
        }
        return .teleport(target)
    }

    private static func planRoute(route: [LocationCoordinate], speed: SimulationSpeed) -> SimulationStartPlan {
        let waypoints = route.filter(\.isValid)
        guard waypoints.count >= 2 else {
            return .failed("Add at least two spots on the map")
        }

        let points = RouteInterpolator.interpolateRoute(waypoints: waypoints, speed: speed)
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
