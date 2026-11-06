//
//  MapFollowTests.swift
//  PathChangerTests
//
//  The map follows the spoofed position without changing the user's zoom
//  (PRODUCT_REQUIREMENTS §3.5, owner decision 2026-11-02).
//

import XCTest
import MapKit
import SwiftUI
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

// MARK: - Camera preservation (MapKit Phase 1, 2026-11-06)

/// A recenter or zoom must keep the camera's distance, heading and pitch; only the
/// requested part changes. The distance bounds mirror `MapZoom`'s span clamps.
final class MapCameraStateTests: XCTestCase {
    private let center = CLLocationCoordinate2D(latitude: 6.4527, longitude: 3.3958)
    private let lagos = CLLocationCoordinate2D(latitude: 6.4474, longitude: 3.3903)
    private let pitched = MapCameraState(
        centerCoordinate: CLLocationCoordinate2D(latitude: 6.4527, longitude: 3.3958),
        distance: 1_500, heading: 42, pitch: 55
    )

    func testMovedToANewCenterKeepsDistanceHeadingAndPitch() {
        let moved = pitched.moved(to: lagos)

        XCTAssertEqual(moved.centerCoordinate.latitude, lagos.latitude, accuracy: 1e-12)
        XCTAssertEqual(moved.centerCoordinate.longitude, lagos.longitude, accuracy: 1e-12)
        XCTAssertEqual(moved.distance, 1_500, accuracy: 1e-9)
        XCTAssertEqual(moved.heading, 42, accuracy: 1e-9)
        XCTAssertEqual(moved.pitch, 55, accuracy: 1e-9)
    }

    func testZoomedInShrinksTheDistanceByTheFactor() {
        // The same factor direction as MapZoom: below 1 zooms in.
        let zoomed = pitched.zoomed(byFactor: 0.8)

        XCTAssertEqual(zoomed.distance, 1_200, accuracy: 1e-9)
        XCTAssertEqual(zoomed.heading, 42, accuracy: 1e-9)
        XCTAssertEqual(zoomed.pitch, 55, accuracy: 1e-9)
        XCTAssertEqual(zoomed.centerCoordinate.latitude, pitched.centerCoordinate.latitude, accuracy: 1e-12)
    }

    func testZoomedOutGrowsTheDistanceByTheFactor() {
        let zoomed = pitched.zoomed(byFactor: 1.25)

        XCTAssertEqual(zoomed.distance, 1_875, accuracy: 1e-9)
    }

    func testZoomClampsAtTheMinimumDistance() {
        let close = MapCameraState(centerCoordinate: center, distance: 90, heading: 0, pitch: 30)

        XCTAssertEqual(close.zoomed(byFactor: 0.5).distance, MapCameraState.minDistance, accuracy: 1e-6)
    }

    func testZoomClampsAtTheMaximumDistance() {
        let far = MapCameraState(centerCoordinate: center, distance: 8_000_000, heading: 0, pitch: 30)

        XCTAssertEqual(far.zoomed(byFactor: 10).distance, MapCameraState.maxDistance, accuracy: 1e-6)
    }

    func testAFlatNorthUpCameraIsEffectivelyFlat() {
        let flat = MapCameraState(centerCoordinate: center, distance: 1_500)
        XCTAssertTrue(flat.isEffectivelyFlat, "the region path already produces this camera, so it is used")
        // Below the half-degree tolerances counts as flat too.
        let nearlyFlat = MapCameraState(centerCoordinate: center, distance: 1_500, heading: 0.3, pitch: 0.2)
        XCTAssertTrue(nearlyFlat.isEffectivelyFlat)
    }

    func testAPitchedOrRotatedCameraIsNotFlat() {
        XCTAssertFalse(pitched.isEffectivelyFlat)
        let rotatedOnly = MapCameraState(centerCoordinate: center, distance: 1_500, heading: 90, pitch: 0)
        XCTAssertFalse(rotatedOnly.isEffectivelyFlat)
    }

    func testReadsAllFourFactsFromAMapCamera() {
        let camera = MapCamera(centerCoordinate: center, distance: 2_500, heading: 130, pitch: 45)

        let state = MapCameraState(camera)

        XCTAssertEqual(state, MapCameraState(centerCoordinate: center, distance: 2_500, heading: 130, pitch: 45))
    }

    func testCameraPositionCarriesTheCamera() {
        let position = pitched.cameraPosition

        XCTAssertEqual(position.camera?.distance ?? 0, 1_500, accuracy: 1e-9)
        XCTAssertEqual(position.camera?.heading ?? -1, 42, accuracy: 1e-9)
        XCTAssertEqual(position.camera?.pitch ?? -1, 55, accuracy: 1e-9)
    }
}

// MARK: - Follow mode transitions (MapKit Phase 1, 2026-11-06)

final class MapFollowModeTests: XCTestCase {
    func testUserMovingTheCameraPausesFollowing() {
        XCTAssertEqual(MapFollowMode.following.afterUserMovedCamera(), .pausedByUser)
    }

    func testUserMovingTheCameraLeavesPausedAndOffAlone() {
        XCTAssertEqual(MapFollowMode.pausedByUser.afterUserMovedCamera(), .pausedByUser)
        XCTAssertEqual(MapFollowMode.off.afterUserMovedCamera(), .off)
    }

    func testOnlyFollowingActs() {
        XCTAssertTrue(MapFollowMode.following.isFollowing)
        XCTAssertFalse(MapFollowMode.pausedByUser.isFollowing)
        XCTAssertFalse(MapFollowMode.off.isFollowing)
    }

    func testTheCenterButtonAlwaysResumesFollowing() {
        XCTAssertEqual(MapFollowMode.off.afterCenterPressed, .following)
        XCTAssertEqual(MapFollowMode.pausedByUser.afterCenterPressed, .following)
        XCTAssertEqual(MapFollowMode.following.afterCenterPressed, .following)
    }
}

// MARK: - Map layer configuration (MapKit Phase 1, 2026-11-06)

/// The layers on top of the base style: realistic elevation, traffic and places, plus
/// the persisted base style. Preference round trips use isolated suites only; the
/// user's real preferences are never touched.
final class MapLayerConfigurationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.maplayer.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsAreFlatWithoutTrafficAndWithPlaces() {
        XCTAssertEqual(MapLayerConfiguration.read(from: defaults), MapLayerConfiguration.default)
        XCTAssertEqual(MapLayerConfiguration.default, MapLayerConfiguration(elevation3D: false, showsTraffic: false, showsPlaces: true))
    }

    func testWriteThenReadRoundTrips() {
        let config = MapLayerConfiguration(elevation3D: true, showsTraffic: true, showsPlaces: false)

        config.write(to: defaults)

        XCTAssertEqual(MapLayerConfiguration.read(from: defaults), config)
    }

    func testFlatStandardKeepsTheExistingMutedLook() {
        let recipe = MapLayerConfiguration.default.styleRecipe(for: .standard)

        XCTAssertEqual(recipe, MapStyleRecipe(base: .standard, elevationIsRealistic: false, showsPlaces: true, showsTraffic: false))
    }

    func testStandard3DUsesRealisticElevation() {
        let recipe = MapLayerConfiguration(elevation3D: true, showsTraffic: false, showsPlaces: true).styleRecipe(for: .standard)

        XCTAssertTrue(recipe.elevationIsRealistic)
        XCTAssertFalse(recipe.showsTraffic)
    }

    func testStandardCarriesTrafficAndCanHidePlaces() {
        let recipe = MapLayerConfiguration(elevation3D: false, showsTraffic: true, showsPlaces: false).styleRecipe(for: .standard)

        XCTAssertTrue(recipe.showsTraffic)
        XCTAssertFalse(recipe.showsPlaces)
        XCTAssertFalse(recipe.elevationIsRealistic)
    }

    func testHybridCarriesTheSameLayerOptions() {
        let config = MapLayerConfiguration(elevation3D: true, showsTraffic: true, showsPlaces: true)

        XCTAssertEqual(config.styleRecipe(for: .hybrid), MapStyleRecipe(base: .hybrid, elevationIsRealistic: true, showsPlaces: true, showsTraffic: true))
        XCTAssertEqual(MapLayerConfiguration.default.styleRecipe(for: .hybrid), MapStyleRecipe(base: .hybrid, elevationIsRealistic: false, showsPlaces: true, showsTraffic: false))
    }

    func testSatelliteDropsTrafficAndPlacesStructurally() {
        // Imagery has no traffic or place parameters; the recipe records them as off
        // so the on-map controls can show them as unavailable for Satellite.
        let eager = MapLayerConfiguration(elevation3D: true, showsTraffic: true, showsPlaces: true)

        XCTAssertEqual(eager.styleRecipe(for: .satellite), MapStyleRecipe(base: .satellite, elevationIsRealistic: true, showsPlaces: false, showsTraffic: false))
        _ = eager.mapStyle(for: .satellite) // smoke only: the imagery style still builds; MapStyle is not Equatable
    }

    func testTheRecipeProducesTheMatchingMapKitStyle() {
        // The one place recipe decisions become a MapStyle; MapStyle is not Equatable,
        // so this asserts the call compiles and returns (content is pinned by the recipe tests).
        let style = MapLayerConfiguration(elevation3D: true, showsTraffic: true, showsPlaces: false).mapStyle(for: .standard)
        _ = style
        let hybrid = MapLayerConfiguration.default.mapStyle(for: .hybrid)
        _ = hybrid
    }

    func testTrafficAndPlacesSupportFollowTheBaseStyle() {
        XCTAssertTrue(MapLayerConfiguration.supportsTraffic(.standard))
        XCTAssertTrue(MapLayerConfiguration.supportsTraffic(.hybrid))
        XCTAssertFalse(MapLayerConfiguration.supportsTraffic(.satellite))
        XCTAssertTrue(MapLayerConfiguration.supportsPlaces(.standard))
        XCTAssertTrue(MapLayerConfiguration.supportsPlaces(.hybrid))
        XCTAssertFalse(MapLayerConfiguration.supportsPlaces(.satellite))
    }

    func testBaseStyleRoundTrips() {
        MapLayerConfiguration.writeBaseStyle(.hybrid, to: defaults)
        XCTAssertEqual(MapLayerConfiguration.readBaseStyle(from: defaults), .hybrid)

        MapLayerConfiguration.writeBaseStyle(.standard, to: defaults)
        XCTAssertEqual(MapLayerConfiguration.readBaseStyle(from: defaults), .standard)
    }

    func testMissingOrUnknownBaseStyleReadsAsNil() {
        XCTAssertNil(MapLayerConfiguration.readBaseStyle(from: defaults), "nothing stored yet")

        defaults.set("Landscape", forKey: MapLayerConfiguration.baseStyleKey)
        XCTAssertNil(MapLayerConfiguration.readBaseStyle(from: defaults), "an unknown value is not a style")
    }
}
