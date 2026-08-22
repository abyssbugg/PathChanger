//
//  Geo.swift
//  PathChanger
//
//  Single source of truth for spherical geodesic math.
//
//  Before this existed the haversine formula was implemented six times across
//  RouteInterpolator, RouteLibrary, CloudSync, MovementPhysics (twice) and
//  RouteStateManager, each with its own copy of the Earth radius. Callers now share one
//  implementation and one constant.
//
//  These are deliberately unguarded primitives: they perform no coordinate validation so
//  that callers can apply the validation policy appropriate to their context (for example
//  `RouteInterpolator` returns 0 for invalid input, whereas `RouteRecorder` assumes it has
//  already filtered). Validate before calling if the result matters.
//
//  Note: `MapService` and `GPXParser` use `CLLocation.distance(from:)` instead, which is
//  ellipsoidal rather than spherical and therefore returns slightly different values for
//  the same pair of points. Unifying those two is tracked separately.
//

import Foundation

enum Geo {

    /// Mean Earth radius in meters. Sourced from `AppConstants` so the value is declared once.
    static var earthRadiusMeters: Double {
        AppConstants.Simulation.earthRadiusMeters
    }

    /// Great-circle distance between two coordinates, in meters (haversine).
    static func distance(from: LocationCoordinate, to: LocationCoordinate) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLat = (to.latitude - from.latitude) * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180

        let haversineTerm = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let angularDistance = 2 * atan2(sqrt(haversineTerm), sqrt(1 - haversineTerm))

        return earthRadiusMeters * angularDistance
    }

    /// Total great-circle length of a polyline, in meters.
    static func totalDistance(of coordinates: [LocationCoordinate]) -> Double {
        guard coordinates.count > 1 else { return 0 }

        var total: Double = 0
        for index in 1..<coordinates.count {
            total += distance(from: coordinates[index - 1], to: coordinates[index])
        }
        return total
    }

    /// Initial bearing from one coordinate to another, normalized to 0..<360 degrees.
    static func bearing(from: LocationCoordinate, to: LocationCoordinate) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180

        let yComponent = sin(deltaLon) * cos(lat2)
        let xComponent = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)

        return normalizedDegrees(atan2(yComponent, xComponent) * 180 / .pi)
    }

    /// Project a coordinate along a bearing for a given distance.
    static func move(
        from: LocationCoordinate,
        distanceMeters: Double,
        bearingDegrees: Double
    ) -> LocationCoordinate {
        let angularDistance = distanceMeters / earthRadiusMeters
        let bearing = normalizedDegrees(bearingDegrees) * .pi / 180

        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180

        let lat2 = asin(
            sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearing)
        )
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return LocationCoordinate(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }

    /// Normalize an angle in degrees to 0..<360.
    static func normalizedDegrees(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }
}
