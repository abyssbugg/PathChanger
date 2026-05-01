//
//  LocationCoordinate.swift
//  PathChanger
//
//  Location coordinate model
//

import Foundation
import CoreLocation

/// Represents a GPS coordinate with strict validation
struct LocationCoordinate: Equatable, Hashable, Codable {
    let latitude: Double
    let longitude: Double

    /// Initialize with validation
    /// - Parameters:
    ///   - latitude: Latitude (-90 to 90)
    ///   - longitude: Longitude (-180 to 180)
    /// - Note: Use `validated()` or call ArgumentSanitizer for strict validation
    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Initialize from CoreLocation coordinate
    init(from clLocation: CLLocationCoordinate2D) {
        self.latitude = clLocation.latitude
        self.longitude = clLocation.longitude
    }

    /// Initialize with validation, throwing error if invalid
    /// - Parameters:
    ///   - latitude: Latitude (-90 to 90)
    ///   - longitude: Longitude (-180 to 180)
    /// - Throws: ValidationError if coordinates are out of bounds or invalid
    init(validatedLatitude latitude: Double, validatedLongitude longitude: Double) throws {
        try ArgumentSanitizer.validateCoordinateBounds(latitude: latitude, longitude: longitude)
        self.latitude = latitude
        self.longitude = longitude
    }

    var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Check if coordinates are within valid bounds
    /// Validates:
    /// - Latitude: -90 to 90
    /// - Longitude: -180 to 180
    /// - Both values are finite (not NaN or Infinity)
    var isValid: Bool {
        guard latitude.isFinite && longitude.isFinite else {
            return false
        }

        guard latitude >= -90.0 && latitude <= 90.0 else {
            return false
        }

        guard longitude >= -180.0 && longitude <= 180.0 else {
            return false
        }

        return true
    }

    /// Validate using ArgumentSanitizer and throw error if invalid
    /// - Throws: ValidationError if coordinates are invalid
    func validated() throws {
        try ArgumentSanitizer.validateCoordinateBounds(latitude: latitude, longitude: longitude)
    }

    var formattedString: String {
        String(format: "%.6f, %.6f", latitude, longitude)
    }

    var formattedShort: String {
        String(format: "%.4f, %.4f", latitude, longitude)
    }

    var dmsString: String {
        let latDMS = toDMS(latitude, isLatitude: true)
        let lonDMS = toDMS(longitude, isLatitude: false)
        return "\(latDMS), \(lonDMS)"
    }

    private func toDMS(_ decimal: Double, isLatitude: Bool) -> String {
        let direction = isLatitude ? (decimal >= 0 ? "N" : "S") : (decimal >= 0 ? "E" : "W")
        let absolute = abs(decimal)
        let degrees = Int(absolute)
        let minutesDecimal = (absolute - Double(degrees)) * 60
        let minutes = Int(minutesDecimal)
        let seconds = (minutesDecimal - Double(minutes)) * 60
        return String(format: "%d°%d'%.2f\"%@", degrees, minutes, seconds, direction)
    }
}

/// Preset locations for quick access
enum PresetLocation: String, CaseIterable, Identifiable {
    case tokyoTower = "Tokyo Tower"
    case eiffelTower = "Eiffel Tower"
    case statueOfLiberty = "Statue of Liberty"
    case sydneyOperaHouse = "Sydney Opera House"
    case applePark = "Apple Park"
    case timesSquare = "Times Square"
    case bigBen = "Big Ben"
    case colosseum = "Colosseum"

    var id: String { rawValue }

    var coordinate: LocationCoordinate {
        switch self {
        case .tokyoTower: return LocationCoordinate(latitude: 35.6586, longitude: 139.7454)
        case .eiffelTower: return LocationCoordinate(latitude: 48.8584, longitude: 2.2945)
        case .statueOfLiberty: return LocationCoordinate(latitude: 40.6892, longitude: -74.0445)
        case .sydneyOperaHouse: return LocationCoordinate(latitude: -33.8568, longitude: 151.2153)
        case .applePark: return LocationCoordinate(latitude: 37.3346, longitude: -122.0090)
        case .timesSquare: return LocationCoordinate(latitude: 40.7580, longitude: -73.9855)
        case .bigBen: return LocationCoordinate(latitude: 51.5007, longitude: -0.1246)
        case .colosseum: return LocationCoordinate(latitude: 41.8902, longitude: 12.4922)
        }
    }
}
