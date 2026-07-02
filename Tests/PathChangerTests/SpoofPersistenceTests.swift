//
//  SpoofPersistenceTests.swift
//  PathChangerTests
//
//  Regression: a held Teleport spoof silently reset to the device default when
//  the background daemon recreated its tunnel and the RSD (address/port)
//  rotated. The bridge's cached DVT session was bound to the old RSD, so the
//  device reverted while the app still showed "connected". Route/Joystick
//  self-heal because they re-inject every tick with the fresh RSD; Teleport
//  holds a static session and must be re-applied when the RSD changes.
//

import XCTest
@testable import PathChanger

final class SpoofPersistenceTests: XCTestCase {

    func testTeleportReappliesWhenRsdRotates() {
        XCTAssertTrue(AppState.shouldReapplyAfterRsdChange(
            isSimulating: true,
            isPaused: false,
            mode: .teleport,
            hasCurrentLocation: true,
            previousRsdKey: "fdad:734:7f2b::1:55108",
            currentRsdKey: "fd67:dedc:fd27::1:55183"
        ))
    }

    func testTeleportDoesNotReapplyWhenRsdUnchanged() {
        XCTAssertFalse(AppState.shouldReapplyAfterRsdChange(
            isSimulating: true,
            isPaused: false,
            mode: .teleport,
            hasCurrentLocation: true,
            previousRsdKey: "fd67:dedc:fd27::1:55183",
            currentRsdKey: "fd67:dedc:fd27::1:55183"
        ))
    }

    func testRouteDoesNotReapply_selfHealsViaContinuousInjection() {
        XCTAssertFalse(AppState.shouldReapplyAfterRsdChange(
            isSimulating: true,
            isPaused: false,
            mode: .route,
            hasCurrentLocation: true,
            previousRsdKey: "a:1",
            currentRsdKey: "b:2"
        ))
    }

    func testJoystickDoesNotReapply_selfHealsViaContinuousInjection() {
        XCTAssertFalse(AppState.shouldReapplyAfterRsdChange(
            isSimulating: true,
            isPaused: false,
            mode: .joystick,
            hasCurrentLocation: true,
            previousRsdKey: "a:1",
            currentRsdKey: "b:2"
        ))
    }

    func testNoReapplyWhenNotSimulating() {
        XCTAssertFalse(AppState.shouldReapplyAfterRsdChange(
            isSimulating: false,
            isPaused: false,
            mode: .teleport,
            hasCurrentLocation: true,
            previousRsdKey: "a:1",
            currentRsdKey: "b:2"
        ))
    }

    func testNoReapplyWhenPaused() {
        XCTAssertFalse(AppState.shouldReapplyAfterRsdChange(
            isSimulating: true,
            isPaused: true,
            mode: .teleport,
            hasCurrentLocation: true,
            previousRsdKey: "a:1",
            currentRsdKey: "b:2"
        ))
    }

    func testNoReapplyWhenNoUsableRsdNow() {
        XCTAssertFalse(AppState.shouldReapplyAfterRsdChange(
            isSimulating: true,
            isPaused: false,
            mode: .teleport,
            hasCurrentLocation: true,
            previousRsdKey: "a:1",
            currentRsdKey: nil
        ))
    }

    func testNoReapplyWhenNoCurrentLocation() {
        XCTAssertFalse(AppState.shouldReapplyAfterRsdChange(
            isSimulating: true,
            isPaused: false,
            mode: .teleport,
            hasCurrentLocation: false,
            previousRsdKey: "a:1",
            currentRsdKey: "b:2"
        ))
    }
}
