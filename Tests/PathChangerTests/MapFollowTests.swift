//
//  MapFollowTests.swift
//  PathChangerTests
//
//  The map follows the spoofed position without changing the user's zoom
//  (PRODUCT_REQUIREMENTS §3.5, owner decision 2026-11-02).
//

import XCTest
import MapKit
@testable import PathChanger

final class MapFollowTests: XCTestCase {
    private let visible = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.3187, longitude: -82.4610),
        span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.006)
    )

    func testFollowRegionCentersOnThePointAndKeepsTheUsersSpan() {
        let point = CLLocationCoordinate2D(latitude: 35.4000, longitude: -82.5000)

        let region = MapFollow.region(centeredOn: point, keeping: visible)

        XCTAssertEqual(region.center.latitude, point.latitude, accuracy: 1e-12)
        XCTAssertEqual(region.center.longitude, point.longitude, accuracy: 1e-12)
        XCTAssertEqual(region.span.latitudeDelta, visible.span.latitudeDelta, accuracy: 1e-12)
        XCTAssertEqual(region.span.longitudeDelta, visible.span.longitudeDelta, accuracy: 1e-12)
    }

    func testRepeatedFollowNeverDriftsTheZoom() {
        var region = visible
        for step in 1...200 {
            let point = CLLocationCoordinate2D(latitude: 35.3187 + Double(step) * 0.001, longitude: -82.4610)
            region = MapFollow.region(centeredOn: point, keeping: region)
        }
        XCTAssertEqual(region.span.latitudeDelta, visible.span.latitudeDelta, accuracy: 1e-12)
        XCTAssertEqual(region.span.longitudeDelta, visible.span.longitudeDelta, accuracy: 1e-12)
    }

    func testPointInsideTheInnerAreaDoesNotMoveTheCamera() {
        XCTAssertFalse(MapFollow.needsRecentering(visible.center, in: visible))
        // 20% of the span from the centre, inside the middle half on both axes.
        let near = CLLocationCoordinate2D(
            latitude: visible.center.latitude + visible.span.latitudeDelta * 0.2,
            longitude: visible.center.longitude - visible.span.longitudeDelta * 0.2
        )
        XCTAssertFalse(MapFollow.needsRecentering(near, in: visible))
    }

    func testPointLeavingTheInnerAreaMovesTheCamera() {
        let northEdge = CLLocationCoordinate2D(
            latitude: visible.center.latitude + visible.span.latitudeDelta * 0.3,
            longitude: visible.center.longitude
        )
        let westEdge = CLLocationCoordinate2D(
            latitude: visible.center.latitude,
            longitude: visible.center.longitude - visible.span.longitudeDelta * 0.3
        )
        let elsewhere = CLLocationCoordinate2D(latitude: 6.4474, longitude: 3.3903)

        XCTAssertTrue(MapFollow.needsRecentering(northEdge, in: visible))
        XCTAssertTrue(MapFollow.needsRecentering(westEdge, in: visible))
        XCTAssertTrue(MapFollow.needsRecentering(elsewhere, in: visible))
    }

    func testLongitudeDistanceWrapsAcrossTheAntimeridian() {
        let dateLine = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -16.5, longitude: 179.99),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        let acrossTheLine = CLLocationCoordinate2D(latitude: -16.5, longitude: -179.99)

        XCTAssertFalse(MapFollow.needsRecentering(acrossTheLine, in: dateLine), "0.02° east, not 359.98° west")
    }

    func testUnusableVisibleRegionAlwaysRecenters() {
        let empty = MKCoordinateRegion(center: visible.center, span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0))
        XCTAssertTrue(MapFollow.needsRecentering(visible.center, in: empty))
    }

    func testUnusableSpanFallsBackToTheDefaultSpan() {
        let empty = MKCoordinateRegion(center: visible.center, span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: .nan))

        let region = MapFollow.region(centeredOn: visible.center, keeping: empty)

        XCTAssertEqual(region.span.latitudeDelta, MapFollow.defaultSpan.latitudeDelta, accuracy: 1e-12)
        XCTAssertEqual(region.span.longitudeDelta, MapFollow.defaultSpan.longitudeDelta, accuracy: 1e-12)
    }
}
