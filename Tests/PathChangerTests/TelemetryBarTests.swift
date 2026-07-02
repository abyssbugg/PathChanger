//
//  TelemetryBarTests.swift
//  PathChangerTests
//
//  Tests for the pure formatting helpers backing the TelemetryBar component
//  (mockup `.telemetry-bar` port).
//

import XCTest
@testable import PathChanger

final class TelemetryBarTests: XCTestCase {

    func testCoordinateTextFormatsSixDecimalPlaces() {
        let coordinate = LocationCoordinate(latitude: 37.7749, longitude: -122.4194)
        XCTAssertEqual(TelemetryBar.coordinateText(coordinate), "37.774900, -122.419400")
    }

    func testCoordinateTextNilShowsPlaceholder() {
        XCTAssertEqual(TelemetryBar.coordinateText(nil), "—")
    }

    func testCoordinateTextNegativeZeroBoundaries() {
        let coordinate = LocationCoordinate(latitude: 0, longitude: 0)
        XCTAssertEqual(TelemetryBar.coordinateText(coordinate), "0.000000, 0.000000")
    }
}
