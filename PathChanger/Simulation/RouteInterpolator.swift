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

    /// Upper bound on generated route points (about 5.5 h of updates at 5 Hz).
    static let maxRoutePoints = 100_000

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

    /// Generate points along a route so consecutive points are `stepMeters` apart
    /// (the final step of each leg may be shorter). Playback sends one point per update,
    /// so `stepMeters = speed / update rate` makes the travelled speed the shown one.
    static func interpolateRoute(waypoints: [LocationCoordinate], stepMeters: Double) -> [LocationCoordinate] {
        let validWaypoints = waypoints.filter { $0.isValid }
        guard validWaypoints.count > 1 else { return validWaypoints }
        // Bound the work on the main actor: a very long route at a slow speed is
        // spaced out to at most `maxRoutePoints` points (a coarser step, same path).
        var total = 0.0
        for index in 1..<validWaypoints.count {
            total += haversineDistance(from: validWaypoints[index - 1], to: validWaypoints[index])
        }
        let step = max(stepMeters, 0.01, total / Double(maxRoutePoints))

        var allPoints: [LocationCoordinate] = []
        for index in 0..<validWaypoints.count - 1 {
            let start = validWaypoints[index]
            let end = validWaypoints[index + 1]
            let distance = haversineDistance(from: start, to: end)
            guard distance > 0, distance < maxDistanceMeters else {
                if distance == 0 { allPoints.append(start) }
                continue
            }
            let steps = max(1, Int((distance / step).rounded(.up)))
            for stepIndex in 0..<steps {
                // Constant distance per step, the last one landing on the waypoint.
                let fraction = min(Double(stepIndex) * step / distance, 1)
                allPoints.append(LocationCoordinate(
                    latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                    longitude: start.longitude + (end.longitude - start.longitude) * fraction
                ))
            }
        }
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
