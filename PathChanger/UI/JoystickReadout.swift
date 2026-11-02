//
//  JoystickReadout.swift
//  PathChanger
//
//  What the Joystick card shows for the heading (PRODUCT_REQUIREMENTS 3.5, owner
//  decision 2026-11-02): an engaged stick shows its live direction; a released stick
//  keeps showing the heading of the last acknowledged step until the next movement or
//  Clear. Chosen without the view so it can be tested.
//

import CoreGraphics
import Foundation

enum JoystickReadout {
    /// Compass bearing of a stick vector (x = east, y = north), 0..<360 degrees.
    static func degrees(_ direction: CGPoint) -> Double {
        Geo.normalizedDegrees(atan2(Double(direction.x), Double(direction.y)) * 180 / .pi)
    }

    /// The live stick when engaged, else the last acknowledged heading, else "—".
    static func headingText(live: CGPoint, last: Double?) -> String {
        heading(live: live, last: last).map { "\($0)°" } ?? "—"
    }

    /// The same heading for VoiceOver, as words.
    static func headingAccessibilityLabel(live: CGPoint, last: Double?) -> String {
        heading(live: live, last: last).map { "Heading \($0) degrees" } ?? "Heading not set"
    }

    /// Whole degrees, 0...359.
    private static func heading(live: CGPoint, last: Double?) -> Int? {
        let degrees: Double
        if hypot(live.x, live.y) > JoystickMovement.deadZone {
            degrees = Self.degrees(live)
        } else if let last, last.isFinite {
            degrees = last
        } else {
            return nil
        }
        return Int(Geo.normalizedDegrees(degrees.rounded()))
    }
}
