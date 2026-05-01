//
//  SimulationTypes.swift
//  PathChanger
//
//  Shared simulation type definitions
//

import Foundation
import SwiftUI

// MARK: - Simulation Mode Type

/// Available simulation modes
public enum SimulationModeType: String, CaseIterable {
    case teleport
    case route
    case joystick

    public var displayName: String {
        switch self {
        case .teleport: return "Teleport Mode"
        case .route: return "Route Playback"
        case .joystick: return "Joystick Control"
        }
    }

    public var icon: String {
        switch self {
        case .teleport: return "location.fill"
        case .route: return "map.fill"
        case .joystick: return "gamecontroller.fill"
        }
    }

    public var shortcutKey: KeyEquivalent {
        switch self {
        case .teleport: return "1"
        case .route: return "2"
        case .joystick: return "3"
        }
    }
}
