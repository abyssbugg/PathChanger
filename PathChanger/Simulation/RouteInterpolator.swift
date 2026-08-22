//
//  RouteInterpolator.swift
//  PathChanger
//
//  Utility for route coordinate generation and interpolation
//  Extracted from SimulationEngine.swift for better maintainability
//

import Foundation

/// Utility for route coordinate generation and interpolation
struct RouteInterpolator {

    /// Maximum allowed distance for a single move (prevents erratic jumps) - 100km
    private static let maxDistanceMeters: Double = 100_000

    /// Generate interpolated points for an entire route
    static func interpolateRoute(waypoints: [LocationCoordinate], speed: SimulationSpeed) -> [LocationCoordinate] {
        guard waypoints.count > 1 else { return waypoints }

        // Filter out invalid coordinates
        let validWaypoints = waypoints.filter { $0.isValid }
        guard validWaypoints.count > 1 else { return [] }

        var allPoints: [LocationCoordinate] = []

        for waypointIndex in 0..<validWaypoints.count - 1 {
            let segment = interpolate(
                from: validWaypoints[waypointIndex],
                to: validWaypoints[waypointIndex + 1],
                speed: speed
            )
            allPoints.append(contentsOf: segment)
        }

        // Add final waypoint
        if let last = validWaypoints.last {
            allPoints.append(last)
        }

        return allPoints
    }

    /// Generate interpolated points between two coordinates
    static func interpolate(
        from start: LocationCoordinate,
        to end: LocationCoordinate,
        speed: SimulationSpeed
    ) -> [LocationCoordinate] {
        // Validate inputs
        guard start.isValid, end.isValid else { return [] }

        let distance = haversineDistance(from: start, to: end)

        // Guard against extreme distances that could cause performance issues
        guard distance > 0, distance < maxDistanceMeters else {
            return distance == 0 ? [start] : []
        }

        let duration = distance / speed.metersPerSecond
        let steps = max(1, Int(duration / speed.updateInterval))

        guard steps > 1 else { return [start] }

        var points: [LocationCoordinate] = []

        for stepIndex in 0..<steps {
            let fraction = Double(stepIndex) / Double(steps)
            let lat = start.latitude + (end.latitude - start.latitude) * fraction
            let lon = start.longitude + (end.longitude - start.longitude) * fraction
            points.append(LocationCoordinate(latitude: lat, longitude: lon))
        }

        return points
    }

    /// Calculate haversine distance between two coordinates (in meters)
    /// Returns 0 if either coordinate is invalid
    static func haversineDistance(from: LocationCoordinate, to: LocationCoordinate) -> Double {
        guard from.isValid, to.isValid else { return 0 }
        return Geo.distance(from: from, to: to)
    }

    /// Move a coordinate by distance and bearing
    /// Returns the original coordinate if inputs are invalid
    static func moveCoordinate(
        from: LocationCoordinate,
        distanceMeters: Double,
        bearingDegrees: Double
    ) -> LocationCoordinate {
        // Validate inputs
        guard from.isValid else { return from }
        guard distanceMeters >= 0, distanceMeters < maxDistanceMeters else { return from }

        let result = Geo.move(
            from: from,
            distanceMeters: distanceMeters,
            bearingDegrees: bearingDegrees
        )

        // Verify result is valid (edge case: near poles)
        return result.isValid ? result : from
    }

    /// Calculate bearing between two coordinates (in degrees)
    /// Returns 0 if either coordinate is invalid
    static func bearing(from: LocationCoordinate, to: LocationCoordinate) -> Double {
        guard from.isValid, to.isValid else { return 0 }
        return Geo.bearing(from: from, to: to)
    }
}
