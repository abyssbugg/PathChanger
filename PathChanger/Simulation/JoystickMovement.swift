//
//  JoystickMovement.swift
//  PathChanger
//
//  Convert an on-screen joystick vector into the next GPS coordinate.
//

import Foundation
import CoreGraphics

enum JoystickMovement {
    /// Ignore stick noise so a released or centered knob does not drift.
    static let deadZone: CGFloat = 0.05

    /// Advance `from` by a joystick vector.
    ///
    /// - Parameters:
    ///   - from: Current spoofed coordinate.
    ///   - direction: Unit-ish vector, x = east, y = north, magnitude 0...1.
    ///   - speedMetersPerSecond: Full-stick speed.
    ///   - deltaTime: Seconds since the last tick.
    static func nextCoordinate(
        from: LocationCoordinate,
        direction: CGPoint,
        speedMetersPerSecond: Double,
        deltaTime: TimeInterval
    ) -> LocationCoordinate {
        guard from.isValid, speedMetersPerSecond > 0, deltaTime > 0 else {
            return from
        }

        let dirX = Double(direction.x)
        let dirY = Double(direction.y)
        let magnitude = hypot(dirX, dirY)
        guard magnitude >= Double(deadZone) else {
            return from
        }

        let scale = min(magnitude, 1.0)
        let bearing = atan2(dirX, dirY) * 180 / .pi
        let distance = speedMetersPerSecond * deltaTime * scale

        return RouteInterpolator.moveCoordinate(
            from: from,
            distanceMeters: distance,
            bearingDegrees: bearing
        )
    }
}
