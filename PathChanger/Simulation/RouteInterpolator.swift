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
        
        for i in 0..<validWaypoints.count - 1 {
            let segment = interpolate(
                from: validWaypoints[i],
                to: validWaypoints[i + 1],
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
        
        for i in 0..<steps {
            let fraction = Double(i) / Double(steps)
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
        
        let R = 6371000.0 // Earth radius in meters
        
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        
        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1) * cos(lat2) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        
        return R * c
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
        
        // Normalize bearing to 0-360
        let normalizedBearing = bearingDegrees.truncatingRemainder(dividingBy: 360)
        let bearing = (normalizedBearing < 0 ? normalizedBearing + 360 : normalizedBearing) * .pi / 180
        
        let R = 6371000.0 // Earth radius in meters
        
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        
        let lat2 = asin(sin(lat1) * cos(distanceMeters/R) +
                       cos(lat1) * sin(distanceMeters/R) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(distanceMeters/R) * cos(lat1),
                                cos(distanceMeters/R) - sin(lat1) * sin(lat2))
        
        let result = LocationCoordinate(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
        
        // Verify result is valid (edge case: near poles)
        return result.isValid ? result : from
    }
    
    /// Calculate bearing between two coordinates (in degrees)
    /// Returns 0 if either coordinate is invalid
    static func bearing(from: LocationCoordinate, to: LocationCoordinate) -> Double {
        guard from.isValid, to.isValid else { return 0 }
        
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}
