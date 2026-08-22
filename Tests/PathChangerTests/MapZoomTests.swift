import XCTest
import MapKit
@testable import PathChanger

final class MapZoomTests: XCTestCase {
    func testScaledZoomsInRelativeToCurrentSpan() {
        let start = MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
        let once = MapZoom.scaled(start, factor: 0.8)
        let twice = MapZoom.scaled(once, factor: 0.8)
        XCTAssertEqual(once.latitudeDelta, 0.048, accuracy: 0.0001)
        XCTAssertLessThan(twice.latitudeDelta, once.latitudeDelta)
        XCTAssertNotEqual(twice.latitudeDelta, once.latitudeDelta, accuracy: 0.00001)
    }

    func testScaledZoomsOutManyTimesUntilClamp() {
        var span = MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
        var previous = span.latitudeDelta
        var steps = 0
        while steps < 20 {
            span = MapZoom.scaled(span, factor: 1.25)
            if span.latitudeDelta >= MapZoom.maxDelta - 0.0001 { break }
            XCTAssertGreaterThan(span.latitudeDelta, previous)
            previous = span.latitudeDelta
            steps += 1
        }
        XCTAssertGreaterThan(steps, 3)
        let clamped = MapZoom.scaled(MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 80), factor: 1.25)
        XCTAssertEqual(clamped.latitudeDelta, MapZoom.maxDelta, accuracy: 0.0001)
    }

    func testScaledDoesNotRequireAPinnedLocation() {
        let start = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        let next = MapZoom.scaled(start, factor: 0.8)
        XCTAssertEqual(next.latitudeDelta, 0.016, accuracy: 0.0001)
    }
}
