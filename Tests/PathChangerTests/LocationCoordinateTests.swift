//
//  LocationCoordinateTests.swift
//  PathChangerTests
//
//  Unit tests for LocationCoordinate model
//

import XCTest
@testable import PathChanger

final class LocationCoordinateTests: XCTestCase {
    
    // MARK: - Validity Tests
    
    func testValidCoordinate() {
        let coord = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        XCTAssertTrue(coord.isValid)
    }
    
    func testInvalidLatitudeTooHigh() {
        let coord = LocationCoordinate(latitude: 91.0, longitude: 0.0)
        XCTAssertFalse(coord.isValid)
    }
    
    func testInvalidLatitudeTooLow() {
        let coord = LocationCoordinate(latitude: -91.0, longitude: 0.0)
        XCTAssertFalse(coord.isValid)
    }
    
    func testInvalidLongitudeTooHigh() {
        let coord = LocationCoordinate(latitude: 0.0, longitude: 181.0)
        XCTAssertFalse(coord.isValid)
    }
    
    func testInvalidLongitudeTooLow() {
        let coord = LocationCoordinate(latitude: 0.0, longitude: -181.0)
        XCTAssertFalse(coord.isValid)
    }
    
    func testBoundaryLatitude() {
        let north = LocationCoordinate(latitude: 90.0, longitude: 0.0)
        let south = LocationCoordinate(latitude: -90.0, longitude: 0.0)
        XCTAssertTrue(north.isValid)
        XCTAssertTrue(south.isValid)
    }
    
    func testBoundaryLongitude() {
        let east = LocationCoordinate(latitude: 0.0, longitude: 180.0)
        let west = LocationCoordinate(latitude: 0.0, longitude: -180.0)
        XCTAssertTrue(east.isValid)
        XCTAssertTrue(west.isValid)
    }
    
    // MARK: - Equality Tests
    
    func testEquality() {
        let coord1 = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        let coord2 = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        XCTAssertEqual(coord1, coord2)
    }
    
    func testInequality() {
        let coord1 = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        let coord2 = LocationCoordinate(latitude: 40.7128, longitude: -74.0060)
        XCTAssertNotEqual(coord1, coord2)
    }
    
    // MARK: - Formatting Tests
    
    func testFormattedString() {
        let coord = LocationCoordinate(latitude: 35.676200, longitude: 139.650300)
        XCTAssertEqual(coord.formattedString, "35.676200, 139.650300")
    }
    
    func testFormattedShort() {
        let coord = LocationCoordinate(latitude: 35.676234, longitude: 139.650345)
        XCTAssertEqual(coord.formattedShort, "35.6762, 139.6503")
    }
    
    // MARK: - Codable Tests
    
    func testCodable() throws {
        let original = LocationCoordinate(latitude: 35.6762, longitude: 139.6503)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LocationCoordinate.self, from: encoded)
        XCTAssertEqual(original, decoded)
    }
    
    // MARK: - Preset Location Tests
    
    func testPresetLocationsAreValid() {
        for preset in PresetLocation.allCases {
            XCTAssertTrue(preset.coordinate.isValid, "Preset \(preset.rawValue) should have valid coordinates")
        }
    }
}
