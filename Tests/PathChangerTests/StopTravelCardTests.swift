//
//  StopTravelCardTests.swift
//  PathChangerTests
//
//  The mode card's stop-by-stop controls for Jump, Two-Spot and Multi-Spot
//  (PRODUCT_REQUIREMENTS 3.2-3.4 and 3.6): which controls show, their text, the live
//  run readout, the Pause/Resume button, and that each control writes the right mode.
//

import XCTest
@testable import PathChanger

@MainActor
final class StopTravelCardTests: XCTestCase {
    private func settings(
        _ arrival: StopTravelSettings.Arrival = .travel,
        timing: StopTravelSettings.JumpTiming = .fixed,
        hold: Double = 0,
        progression: StopTravelSettings.Progression = .automatic,
        repeat repeatMode: StopTravelSettings.RepeatMode = .oneWay
    ) -> StopTravelSettings {
        StopTravelSettings(arrival: arrival, jumpTiming: timing, holdSeconds: hold, progression: progression, repeatMode: repeatMode)
    }

    private func progress(
        next: Int = 0,
        total: Int = 3,
        legLeft: TimeInterval? = nil,
        holdLeft: TimeInterval? = nil,
        held: Int? = nil,
        fallback: Bool = false,
        note: String? = nil,
        paused: Bool = false
    ) -> StopProgress {
        StopProgress(
            nextStopIndex: next,
            totalStops: total,
            legSecondsLeft: legLeft,
            holdSecondsLeft: holdLeft,
            heldStopIndex: held,
            usesStraightLineFallback: fallback,
            fallbackNote: note,
            isPaused: paused
        )
    }

    // MARK: Which controls show

    func testStopOptionsShowOnlyInStopModes() {
        XCTAssertTrue(StopTravelCardText.showsStopOptions(for: .jump))
        XCTAssertTrue(StopTravelCardText.showsStopOptions(for: .twospot))
        XCTAssertTrue(StopTravelCardText.showsStopOptions(for: .route))
        XCTAssertFalse(StopTravelCardText.showsStopOptions(for: .teleport))
        XCTAssertFalse(StopTravelCardText.showsStopOptions(for: .joystick))
        XCTAssertFalse(StopTravelCardText.showsStopOptions(for: .settings))
    }

    func testJumpTimingShowsOnlyWhenGettingThereIsJump() {
        XCTAssertEqual(
            StopTravelCardText.visibleControls(for: .route, settings: settings(.travel)),
            [.arrival, .hold, .progression, .repeatMode]
        )
        XCTAssertEqual(
            StopTravelCardText.visibleControls(for: .jump, settings: settings(.jump)),
            [.arrival, .jumpTiming, .hold, .progression, .repeatMode]
        )
        XCTAssertEqual(
            StopTravelCardText.visibleControls(for: .twospot, settings: settings(.jump, timing: .realistic)),
            [.arrival, .jumpTiming, .hold, .progression, .repeatMode]
        )
    }

    func testTeleportAndJoystickShowNoStopControls() {
        for mode in [AppMode.teleport, .joystick, .settings] {
            XCTAssertEqual(StopTravelCardText.visibleControls(for: mode, settings: settings(.jump)), [], "\(mode)")
        }
    }

    // MARK: Option text

    func testOptionTitles() {
        XCTAssertEqual(StopTravelSettings.Arrival.allCases.map(StopTravelCardText.title), ["Travel", "Jump"])
        XCTAssertEqual(StopTravelSettings.JumpTiming.allCases.map(StopTravelCardText.title), ["Fixed", "Realistic"])
        XCTAssertEqual(
            StopTravelSettings.Progression.allCases.map(StopTravelCardText.title),
            ["Automatically", "One stop per Move"]
        )
        XCTAssertEqual(
            StopTravelSettings.RepeatMode.allCases.map(StopTravelCardText.title),
            ["One way", "Loop", "Back and forth"]
        )
    }

    func testControlLabelsAreHumanTextAndIdentifiersAreStable() {
        let expected: [(StopTravelCardText.Control, String, String)] = [
            (.arrival, "Getting there", "location.stops.arrival"),
            (.jumpTiming, "Jump timing", "location.stops.jumpTiming"),
            (.hold, "At each stop", "location.stops.hold"),
            (.progression, "Go through", "location.stops.progression"),
            (.repeatMode, "Repeat", "location.stops.repeat"),
        ]
        for (control, label, identifier) in expected {
            XCTAssertEqual(control.label, label)
            XCTAssertEqual(control.accessibilityIdentifier, identifier)
            XCTAssertNotEqual(control.label, control.accessibilityIdentifier, "a label must never be the identifier")
        }
        XCTAssertEqual(StopTravelCardText.progressIdentifier, "location.stops.progress")
    }

    func testJumpTimingCaptionExplainsRealistic() {
        let caption = StopTravelCardText.jumpTimingCaption
        XCTAssertTrue(caption.contains("Realistic"))
        XCTAssertTrue(caption.contains("travel speed"))
        XCTAssertTrue(caption.contains("road distance"))
    }

    // MARK: At each stop

    func testHoldLabelShowsSecondsOrNoWait() {
        XCTAssertEqual(StopTravelCardText.holdLabel(0), "No wait")
        XCTAssertEqual(StopTravelCardText.holdLabel(1), "1 s")
        XCTAssertEqual(StopTravelCardText.holdLabel(5), "5 s")
        XCTAssertEqual(StopTravelCardText.holdLabel(60), "60 s")
        XCTAssertEqual(StopTravelCardText.holdLabel(7.4), "7 s")
    }

    func testHoldAccessibilityValueReadsSeconds() {
        XCTAssertEqual(StopTravelCardText.holdAccessibilityValue(0), "0 seconds, no wait")
        XCTAssertEqual(StopTravelCardText.holdAccessibilityValue(1), "1 second")
        XCTAssertEqual(StopTravelCardText.holdAccessibilityValue(12), "12 seconds")
    }

    func testHoldSliderRangeAndStepMatchTheEngine() {
        XCTAssertEqual(StopTravelCardText.holdRange, StopTravelSettings.holdRange)
        XCTAssertEqual(StopTravelCardText.holdStep, 1)
    }

    // MARK: Live readout

    func testReadoutShowsNextStopOneBasedAndTimeLeft() {
        let lines = StopTravelCardText.progressLines(progress(next: 1, total: 4, legLeft: 75))
        XCTAssertEqual(lines.map(\.text), ["Next stop: 2 of 4", "Time left: 1:15"])
        XCTAssertEqual(lines.map(\.kind), [.nextStop, .timeLeft])
    }

    func testReadoutRoundsTimeLeftUp() {
        XCTAssertEqual(StopTravelCardText.clock(0), "0:00")
        XCTAssertEqual(StopTravelCardText.clock(4.2), "0:05")
        XCTAssertEqual(StopTravelCardText.clock(59.9), "1:00")
        XCTAssertEqual(StopTravelCardText.clock(3600), "60:00")
        XCTAssertEqual(StopTravelCardText.clock(-3), "0:00")
    }

    func testReadoutShowsHoldCountdown() {
        let lines = StopTravelCardText.progressLines(progress(next: 2, total: 3, holdLeft: 4.5, held: 1))
        XCTAssertEqual(lines.map(\.text), ["Holding stop 2: 5s", "Next stop: 3 of 3"])
    }

    func testReadoutShowsPausedFirst() {
        let lines = StopTravelCardText.progressLines(progress(next: 0, total: 2, legLeft: 10, paused: true))
        XCTAssertEqual(lines.first?.text, "Paused")
        XCTAssertEqual(lines.first?.kind, .paused)
    }

    func testReadoutShowsStraightLineFallbackNote() {
        let noted = StopTravelCardText.progressLines(
            progress(fallback: true, note: "No road route found; travelling in a straight line")
        )
        XCTAssertEqual(noted.last?.text, "No road route found; travelling in a straight line")
        XCTAssertEqual(noted.last?.kind, .fallback)

        let unnoted = StopTravelCardText.progressLines(progress(fallback: true, note: nil))
        XCTAssertEqual(unnoted.last?.text, StopTravelCardText.defaultFallbackNote)

        let onRoads = StopTravelCardText.progressLines(progress(fallback: false, note: "ignored"))
        XCTAssertFalse(onRoads.contains { $0.kind == .fallback })
    }

    func testReadoutClampsNextStopToTheStopCount() {
        let lines = StopTravelCardText.progressLines(progress(next: 5, total: 3))
        XCTAssertEqual(lines.first?.text, "Next stop: 3 of 3")
    }

    func testReadoutShowsTheRoadRouteNoteAsItsOwnLine() {
        var onRoads = progress(next: 1, total: 2, legLeft: 30)
        onRoads.routeNote = "Road route is more than 4 times the straight-line distance"
        let lines = StopTravelCardText.progressLines(onRoads)
        XCTAssertEqual(lines.map(\.kind), [.nextStop, .timeLeft, .routeNote])
        XCTAssertEqual(lines.last?.text, "Road route is more than 4 times the straight-line distance")
        XCTAssertFalse(lines.contains { $0.kind == .fallback }, "a road route is not a straight-line fallback")
        XCTAssertEqual(Set(lines.map(\.id)).count, lines.count, "each line is its own element")
    }

    // MARK: Jump Move gating (review 2026-11-02, finding 6)

    func testJumpCanMoveWhenThePlannerHasANextLeg() {
        let stops = [
            LocationCoordinate(latitude: 35.0, longitude: 139.0),
            LocationCoordinate(latitude: 35.1, longitude: 139.1),
            LocationCoordinate(latitude: 35.2, longitude: 139.2),
        ]
        let finished = StopCursor(nextIndex: 3)
        // Owner rule 2026-11-03 (3): a finished One way run starts over at stop 1, so its
        // Move stays possible (it used to be disabled: "All hops done").
        XCTAssertTrue(StopTravelCardText.jumpCanMove(stops: stops, cursor: finished, settings: settings(.jump, repeat: .oneWay)))
        XCTAssertTrue(
            StopTravelCardText.jumpCanMove(stops: stops, cursor: finished, settings: settings(.jump, repeat: .loop)),
            "a finished one-way Jump switched to Loop continues"
        )
        XCTAssertTrue(StopTravelCardText.jumpCanMove(stops: stops, cursor: finished, settings: settings(.jump, repeat: .backAndForth)))
        XCTAssertTrue(StopTravelCardText.jumpCanMove(stops: stops, cursor: StopCursor(nextIndex: 1), settings: settings(.jump)))
        XCTAssertFalse(StopTravelCardText.jumpCanMove(stops: [], cursor: StopCursor(), settings: settings(.jump, repeat: .loop)))
        XCTAssertTrue(
            StopTravelCardText.jumpCanMove(stops: [stops[0]], cursor: StopCursor(nextIndex: 1), settings: settings(.jump, repeat: .loop)),
            "one reached stop starts over at itself"
        )
    }

    // MARK: - Next Move summary (owner rule 2026-11-03)

    private static let six: [LocationCoordinate] = (0..<6).map {
        LocationCoordinate(latitude: 35.0 + Double($0) * 0.01, longitude: 139.0)
    }
    private static let elsewhere = LocationCoordinate(latitude: 34.9, longitude: 139.0)

    private func summary(
        _ options: StopTravelSettings,
        cursor: StopCursor,
        held: LocationCoordinate? = StopTravelCardTests.elsewhere,
        stops: [LocationCoordinate] = StopTravelCardTests.six,
        mode: AppMode = .route,
        roads: Bool = true
    ) -> String? {
        StopTravelCardText.nextMoveSummary(mode: mode, stops: stops, cursor: cursor, settings: options, held: held, followsRoads: roads)
    }

    func testNextMoveSummaryForAnUnfinishedRun() {
        // Travel × every stop × One way, part way.
        XCTAssertEqual(summary(settings(.travel), cursor: StopCursor(nextIndex: 2)), "Next Move: travel by road to stop 3, then stops 4–6")
        XCTAssertEqual(summary(settings(.travel), cursor: StopCursor(nextIndex: 2), roads: false), "Next Move: travel to stop 3, then stops 4–6")
        XCTAssertEqual(summary(settings(.travel), cursor: StopCursor(nextIndex: 5)), "Next Move: travel by road to stop 6")
        // Travel × one per Move.
        XCTAssertEqual(summary(settings(.travel, progression: .onePerMove), cursor: StopCursor(nextIndex: 2)), "Next Move: travel by road to stop 3")
        // Jump × timing × progression.
        XCTAssertEqual(
            summary(settings(.jump, timing: .realistic, progression: .onePerMove), cursor: StopCursor(nextIndex: 1)),
            "Next Move: jump to stop 2 (waits the trip time)"
        )
        XCTAssertEqual(summary(settings(.jump, progression: .onePerMove), cursor: StopCursor(nextIndex: 1)), "Next Move: jump to stop 2")
        XCTAssertEqual(summary(settings(.jump, hold: 5), cursor: StopCursor(nextIndex: 4)), "Next Move: jump to stop 5, then stop 6")
        XCTAssertEqual(
            summary(settings(.jump, timing: .realistic), cursor: StopCursor(nextIndex: 1)),
            "Next Move: jump to stop 2 (waits the trip time), then stops 3–6"
        )
    }

    func testNextMoveSummaryForRepeatingRuns() {
        let four = Array(Self.six.prefix(4))
        XCTAssertEqual(
            summary(settings(.travel, repeat: .loop), cursor: StopCursor(nextIndex: 3), stops: four, roads: false),
            "Next Move: travel to stop 4, then back to stop 1 and repeat"
        )
        XCTAssertEqual(
            summary(settings(.travel, repeat: .loop), cursor: StopCursor(nextIndex: 1)),
            "Next Move: travel by road to stop 2, then stops 3–6, then back to stop 1 and repeat"
        )
        XCTAssertEqual(
            summary(settings(.travel, repeat: .backAndForth), cursor: StopCursor(nextIndex: 2)),
            "Next Move: travel by road to stop 3, then stops 4–6, then back through the stops to stop 1 and repeat"
        )
        XCTAssertEqual(
            summary(settings(.travel, repeat: .backAndForth), cursor: StopCursor(nextIndex: 3, reversed: true)),
            "Next Move: travel by road to stop 4, then stops 3–1, then forward again and repeat"
        )
        XCTAssertEqual(
            summary(settings(.travel, repeat: .backAndForth), cursor: StopCursor(nextIndex: 0, reversed: true)),
            "Next Move: travel by road to stop 1, then forward again and repeat"
        )
        // One per Move: only the next stop, also on the wrap home.
        XCTAssertEqual(
            summary(settings(.travel, progression: .onePerMove, repeat: .loop), cursor: StopCursor(), held: Self.six[5]),
            "Next Move: travel by road to stop 1"
        )
        XCTAssertEqual(
            summary(settings(.jump, progression: .onePerMove, repeat: .backAndForth), cursor: StopCursor(nextIndex: 4, reversed: true), held: Self.six[5]),
            "Next Move: jump to stop 5"
        )
    }

    func testNextMoveSummaryForAFinishedOneWayRun() {
        let finished = StopCursor(nextIndex: 6)
        XCTAssertEqual(
            summary(settings(.travel, progression: .onePerMove), cursor: finished, held: Self.six[5], roads: false),
            "Next Move: start over — travel to stop 1"
        )
        XCTAssertEqual(
            summary(settings(.travel), cursor: finished, held: Self.six[5]),
            "Next Move: start over — travel by road to stop 1, then stops 2–6"
        )
        XCTAssertEqual(
            summary(settings(.jump, progression: .onePerMove), cursor: finished, held: Self.six[5]),
            "Next Move: start over — jump to stop 1"
        )
        // Nothing held (the tunnel stop ended the location): stop 1 is placed.
        XCTAssertEqual(
            summary(settings(.travel, progression: .onePerMove), cursor: finished, held: nil),
            "Next Move: start over — place stop 1"
        )
    }

    func testNextMoveSummaryWhenNothingIsHeldOrTheRunStartsAtTheHeldStop() {
        XCTAssertEqual(summary(settings(.travel), cursor: StopCursor(), held: nil), "Next Move: place stop 1, then travel by road to stops 2–6")
        XCTAssertEqual(summary(settings(.jump), cursor: StopCursor(), held: nil), "Next Move: place stop 1, then jump to stops 2–6")
        XCTAssertEqual(summary(settings(.travel, progression: .onePerMove), cursor: StopCursor(), held: nil), "Next Move: place stop 1")
        // Not held, part way (a tunnel stop ended the location): the next stop is placed.
        XCTAssertEqual(summary(settings(.travel), cursor: StopCursor(nextIndex: 3), held: nil), "Next Move: place stop 4, then travel by road to stops 5–6")
        // Two-Spot with one spot: stop 1 is the held location itself.
        let held = Self.six[0]
        XCTAssertEqual(
            summary(settings(.travel), cursor: StopCursor(), held: held, stops: [held, Self.six[1]], mode: .twospot),
            "Next Move: start at stop 1, then travel by road to stop 2"
        )
    }

    func testNextMoveSummaryOnlyForStopModesWithStops() {
        XCTAssertNil(summary(settings(.travel), cursor: StopCursor(), mode: .teleport))
        XCTAssertNil(summary(settings(.travel), cursor: StopCursor(), mode: .joystick))
        XCTAssertNil(summary(settings(.travel), cursor: StopCursor(), stops: []))
        for mode in RouteStateManager.stopModes {
            XCTAssertNotNil(summary(settings(.travel), cursor: StopCursor(), mode: mode), "\(mode)")
        }
    }

    func testTheCardShowsTheNextMoveLineWhenIdle() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PathChanger/UI/ModeContextCard.swift"))
        XCTAssertTrue(source.contains("appState.nextMoveSummary(for: mode)"))
        XCTAssertTrue(source.contains("StopTravelCardText.nextMoveIdentifier"))
    }

    // MARK: Pause / Resume

    func testPauseButtonHiddenWithoutARun() {
        XCTAssertNil(StopTravelCardText.pauseButton(progress: nil, isPaused: false))
        XCTAssertNil(StopTravelCardText.pauseButton(progress: nil, isPaused: true))
    }

    func testPauseButtonTitleFollowsPausedState() {
        let running = StopTravelCardText.pauseButton(progress: progress(), isPaused: false)
        XCTAssertEqual(running?.title, "Pause")
        XCTAssertEqual(running?.systemImage, "pause.fill")
        XCTAssertEqual(running?.action, .pause)

        let paused = StopTravelCardText.pauseButton(progress: progress(paused: true), isPaused: true)
        XCTAssertEqual(paused?.title, "Resume")
        XCTAssertEqual(paused?.systemImage, "play.fill")
        XCTAssertEqual(paused?.action, .resume)
        XCTAssertEqual(StopTravelCardText.pauseIdentifier, "location.action.pauseMovement")
    }

    // MARK: Editing during a run

    func testRunEditNoteOnlyWhileARunIsActive() {
        XCTAssertNil(StopTravelCardText.runEditNote(isRunActive: false))
        let note = StopTravelCardText.runEditNote(isRunActive: true)
        XCTAssertNotNil(note)
        XCTAssertTrue(note?.contains("ends this run") == true)
    }
}

// MARK: Write-through to AppState

extension StopTravelCardTests {
    private func makeState() -> AppState {
        AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector())
    }

    func testArrivalBindingWritesOnlyItsMode() {
        let state = makeState()
        let binding = state.stopSettingBinding(\.arrival, for: .route)
        XCTAssertEqual(binding.wrappedValue, .travel)
        binding.wrappedValue = .jump
        XCTAssertEqual(state.stopTravelSettings(for: .route).arrival, .jump)
        XCTAssertEqual(state.stopTravelSettings(for: .twospot), .defaults(for: .twospot))
        XCTAssertEqual(state.stopTravelSettings(for: .jump), .defaults(for: .jump))
    }

    func testEveryOptionBindingWritesThrough() {
        let state = makeState()
        state.stopSettingBinding(\.jumpTiming, for: .jump).wrappedValue = .realistic
        state.stopSettingBinding(\.progression, for: .jump).wrappedValue = .automatic
        state.stopSettingBinding(\.repeatMode, for: .jump).wrappedValue = .backAndForth
        state.stopSettingBinding(\.arrival, for: .jump).wrappedValue = .travel

        let jump = state.stopTravelSettings(for: .jump)
        XCTAssertEqual(jump.jumpTiming, .realistic)
        XCTAssertEqual(jump.progression, .automatic)
        XCTAssertEqual(jump.repeatMode, .backAndForth)
        XCTAssertEqual(jump.arrival, .travel)
        XCTAssertEqual(jump.holdSeconds, 5, "untouched options keep their value")
        XCTAssertEqual(state.stopTravelSettings(for: .route), .defaults(for: .route))
    }

    func testRepeatBindingInTwoSpotLeavesMultiSpotAlone() {
        let state = makeState()
        state.stopSettingBinding(\.repeatMode, for: .twospot).wrappedValue = .loop
        XCTAssertEqual(state.stopTravelSettings(for: .twospot).repeatMode, .loop)
        XCTAssertEqual(state.stopTravelSettings(for: .route).repeatMode, .oneWay)
    }

    func testHoldBindingRoundsToWholeSecondsAndAllowsZero() {
        let state = makeState()
        let hold = state.stopHoldBinding(for: .jump)
        XCTAssertEqual(hold.wrappedValue, 5)
        hold.wrappedValue = 7.4
        XCTAssertEqual(state.stopTravelSettings(for: .jump).holdSeconds, 7)
        hold.wrappedValue = 0
        XCTAssertEqual(state.stopTravelSettings(for: .jump).holdSeconds, 0, "0 = no wait (the Auto jump 1 s floor does not apply)")
        hold.wrappedValue = 90
        XCTAssertEqual(state.stopTravelSettings(for: .jump).holdSeconds, 60)
        XCTAssertEqual(state.stopTravelSettings(for: .route).holdSeconds, 0)
    }

    func testPauseButtonActionsAreNoOpsWithoutARun() {
        let state = makeState()
        XCTAssertNil(state.stopProgress)
        StopTravelCardText.perform(.pause, on: state)
        XCTAssertFalse(state.isPaused, "Pause without a stop run does nothing")
        StopTravelCardText.perform(.resume, on: state)
        XCTAssertFalse(state.isPaused)
    }

    // MARK: Reached stop (D2: "Hop" showed the next index, wrong after a Loop wrap)

    private var r0: LocationCoordinate { LocationCoordinate(latitude: 35.0, longitude: 139.0) }
    private var r1: LocationCoordinate { LocationCoordinate(latitude: 35.1, longitude: 139.1) }
    private var r2: LocationCoordinate { LocationCoordinate(latitude: 35.2, longitude: 139.2) }

    func testReachedStopInvertsTheCursorForEveryRepeatMode() {
        let stops = [r0, r1, r2]
        // One way: the cursor is one past the reached stop.
        XCTAssertEqual(StopTravelCardText.reachedStop(stops: stops, cursor: StopCursor(nextIndex: 1), repeatMode: .oneWay, held: r0), 0)
        XCTAssertEqual(StopTravelCardText.reachedStop(stops: stops, cursor: StopCursor(nextIndex: 3), repeatMode: .oneWay, held: r2), 2)
        // Loop: after the last stop the cursor wraps to 0 while the phone holds stop 3.
        XCTAssertEqual(StopTravelCardText.reachedStop(stops: stops, cursor: StopCursor(nextIndex: 0), repeatMode: .loop, held: r2), 2)
        // Back and forth: after stop 3 the cursor is (1, reversed); after stop 1 on the way back, (1, forward).
        XCTAssertEqual(StopTravelCardText.reachedStop(stops: stops, cursor: StopCursor(nextIndex: 1, reversed: true), repeatMode: .backAndForth, held: r2), 2)
        XCTAssertEqual(StopTravelCardText.reachedStop(stops: stops, cursor: StopCursor(nextIndex: 1), repeatMode: .backAndForth, held: r0), 0)
        XCTAssertEqual(StopTravelCardText.reachedStop(stops: stops, cursor: StopCursor(nextIndex: 2), repeatMode: .backAndForth, held: r1), 1)
    }

    func testReachedStopIsNilUnlessThePhoneHoldsThatStop() {
        let stops = [r0, r1, r2]
        XCTAssertNil(StopTravelCardText.reachedStop(stops: stops, cursor: StopCursor(), repeatMode: .oneWay, held: nil), "nothing reached yet")
        XCTAssertNil(StopTravelCardText.reachedStop(stops: stops, cursor: StopCursor(), repeatMode: .loop, held: r0), "a fresh Loop has reached nothing")
        XCTAssertNil(StopTravelCardText.reachedStop(stops: stops, cursor: StopCursor(nextIndex: 2), repeatMode: .oneWay, held: nil), "after Clear nothing is held")
        XCTAssertNil(
            StopTravelCardText.reachedStop(stops: stops, cursor: StopCursor(nextIndex: 2), repeatMode: .oneWay, held: LocationCoordinate(latitude: 1, longitude: 1)),
            "the phone is elsewhere (a Teleport), so it is at no stop of this run"
        )
        XCTAssertNil(StopTravelCardText.reachedStop(stops: [], cursor: StopCursor(nextIndex: 1), repeatMode: .oneWay, held: r0))
    }

    func testAtStopValueReadsTheReachedStop() {
        XCTAssertEqual(StopTravelCardText.atStopValue(reached: 2, total: 3), "3 of 3")
        XCTAssertEqual(StopTravelCardText.atStopValue(reached: nil, total: 3), "—")
    }

    // MARK: When options apply (D3, D5)

    func testAtEachStopAppliesOnlyWhenTheMoveContinuesAutomatically() {
        XCTAssertTrue(StopTravelCardText.holdApplies(settings(.travel, hold: 5, progression: .automatic)))
        XCTAssertFalse(StopTravelCardText.holdApplies(settings(.jump, hold: 5, progression: .onePerMove)))
        XCTAssertNotNil(StopTravelCardText.holdNote(settings(.jump, hold: 5, progression: .onePerMove)))
        XCTAssertNil(StopTravelCardText.holdNote(settings(.travel, hold: 5, progression: .automatic)))
    }

    func testJumpTimingCaptionFollowsTheChoice() {
        let realistic = StopTravelCardText.jumpTimingCaption(for: settings(.jump, timing: .realistic))
        XCTAssertTrue(realistic.contains("travel speed"), realistic)
        XCTAssertTrue(realistic.contains("road distance"), realistic)
        XCTAssertTrue(realistic.contains("straight line"), realistic)
        let fixed = StopTravelCardText.jumpTimingCaption(for: settings(.jump, timing: .fixed))
        XCTAssertTrue(fixed.contains("At each stop"), fixed)
    }

    /// Review 2026-11-02-163337 issue 6: under Jump's defaults (Fixed, One stop per Move)
    /// At each stop is dimmed with "Used between stops when Go through is Automatically";
    /// the caption above it must not say it sets the pause.
    func testFixedJumpCaptionDoesNotPromiseAHoldThatDoesNotApply() {
        let onePerMove = settings(.jump, timing: .fixed, hold: 5, progression: .onePerMove)
        XCTAssertFalse(StopTravelCardText.holdApplies(onePerMove))
        XCTAssertEqual(StopTravelCardText.jumpTimingCaption(for: onePerMove), "Jumps at once when you press Move.")
        XCTAssertEqual(
            StopTravelCardText.jumpTimingCaption(for: .defaults(for: .jump)),
            StopTravelCardText.jumpTimingCaption(for: settings(.jump, timing: .fixed, progression: .onePerMove)),
            "Jump's defaults read the one-stop-per-Move caption"
        )
        let automatic = settings(.jump, timing: .fixed, hold: 5, progression: .automatic)
        XCTAssertEqual(
            StopTravelCardText.jumpTimingCaption(for: automatic),
            "Jumps at once; At each stop sets the pause between stops."
        )
        XCTAssertEqual(
            StopTravelCardText.jumpTimingCaption(for: settings(.jump, timing: .realistic, progression: .onePerMove)),
            StopTravelCardText.jumpTimingCaption(for: settings(.jump, timing: .realistic, progression: .automatic)),
            "the Realistic trip-time wait does not depend on Go through"
        )
    }

    func testSpeedNoteSaysWhenTheSpeedIsUsed() {
        XCTAssertNil(StopTravelCardText.speedNote(settings: settings(.travel), isRunActive: false))
        XCTAssertEqual(
            StopTravelCardText.speedNote(settings: settings(.jump, timing: .fixed), isRunActive: false),
            "Fixed jumps do not use the speed."
        )
        XCTAssertEqual(
            StopTravelCardText.speedNote(settings: settings(.jump, timing: .realistic), isRunActive: false),
            "Realistic jumps wait the trip time at this speed."
        )
        XCTAssertEqual(
            StopTravelCardText.speedNote(settings: settings(.travel), isRunActive: true),
            "Speed changes apply from the next Move.",
            "the run froze its speed at Move"
        )
    }

    // MARK: Travel mode (D4)

    func testChoosingATravelModeSetsItsSpeedEvenWhenTheSpeedWasManual() {
        let state = makeState()
        state.autoSpeed = false
        state.customSpeedMps = 3
        state.selectTravelMode(.driving)
        XCTAssertTrue(state.autoSpeed)
        XCTAssertEqual(state.simulationSpeed, .driving)
        XCTAssertEqual(state.effectiveMetersPerSecond, 15.6, accuracy: 1e-9)
        for (mode, speed) in [(SimulationSpeed.walking, 1.6), (.cycling, 5.4), (.fast, 11.2), (.driving, 15.6)] {
            state.selectTravelMode(mode)
            XCTAssertEqual(state.effectiveMetersPerSecond, speed, accuracy: 1e-9, "\(mode)")
        }
    }

    func testTravelModeTitleReadsCustomWhileTheSpeedIsManual() {
        XCTAssertEqual(StopTravelCardText.travelModeTitle(.cycling, autoSpeed: true), "Cycling")
        XCTAssertEqual(StopTravelCardText.travelModeTitle(.fast, autoSpeed: true), "Riding")
        XCTAssertEqual(StopTravelCardText.travelModeTitle(.cycling, autoSpeed: false), "Custom")
    }

    // MARK: Phase (D6) and completion (D7)

    func testReadoutNamesTheWaitBeforeAJump() {
        var waiting = progress(next: 1, total: 3, legLeft: 63)
        waiting.phase = .waitingToJump
        XCTAssertEqual(StopTravelCardText.progressLines(waiting).map(\.text), ["Next stop: 2 of 3", "Jump in: 1:03"])
        XCTAssertEqual(StopTravelCardText.phaseTitle(waiting), "Waiting to jump to stop 2")

        var routing = progress(next: 1, total: 3)
        routing.phase = .findingRoute
        XCTAssertEqual(StopTravelCardText.phaseTitle(routing), "Finding a road route to stop 2")

        XCTAssertEqual(StopTravelCardText.phaseTitle(progress(next: 2, total: 3, legLeft: 9)), "Travelling to stop 3")

        var holding = progress(next: 2, total: 3, holdLeft: 4, held: 1)
        holding.phase = .holding
        XCTAssertEqual(StopTravelCardText.phaseTitle(holding), "Holding at stop 2")

        var paused = waiting
        paused.isPaused = true
        XCTAssertEqual(StopTravelCardText.phaseTitle(paused), "Paused")
    }

    func testCompletionLineSaysTheLastLocationIsStillHeld() {
        XCTAssertEqual(
            StopTravelCardText.completionLine(movement: .completed(.multiSpot), mode: .route, isHeld: true, reachedStop: 2, totalStops: 3),
            "Done · holding stop 3 of 3"
        )
        XCTAssertEqual(
            StopTravelCardText.completionLine(movement: .completed(.twoSpot), mode: .twospot, isHeld: true, reachedStop: nil, totalStops: 2),
            "Done · holding the last location"
        )
        XCTAssertNil(StopTravelCardText.completionLine(movement: .completed(.twoSpot), mode: .route, isHeld: true, reachedStop: 1, totalStops: 2), "another mode's run")
        XCTAssertNil(StopTravelCardText.completionLine(movement: .completed(.multiSpot), mode: .route, isHeld: false, reachedStop: 1, totalStops: 2), "nothing held (after Clear)")
        XCTAssertNil(StopTravelCardText.completionLine(movement: .moving(.multiSpot), mode: .route, isHeld: true, reachedStop: 1, totalStops: 2))
        XCTAssertNil(StopTravelCardText.completionLine(movement: .idle, mode: .route, isHeld: true, reachedStop: 1, totalStops: 2))
    }
}

/// GUI arrangement 2026-11-04: a Two-Spot "Jump, Realistic" run waited 141 s before its
/// jump and the owner stopped it after 54 s, likely thinking it was stuck. The live panel
/// says how long is left, how far the wait has come, and what happens next.
final class StopRunPanelTextTests: XCTestCase {
    private func progress(
        _ phase: StopProgress.Phase,
        next: Int = 1,
        total: Int = 2,
        legLeft: TimeInterval? = nil,
        holdLeft: TimeInterval? = nil,
        held: Int? = nil,
        phaseTotal: TimeInterval? = nil,
        paused: Bool = false
    ) -> StopProgress {
        var progress = StopProgress(
            nextStopIndex: next, totalStops: total, legSecondsLeft: legLeft, holdSecondsLeft: holdLeft,
            heldStopIndex: held, usesStraightLineFallback: false, fallbackNote: nil, isPaused: paused, phase: phase
        )
        progress.phaseSecondsTotal = phaseTotal
        return progress
    }

    private var realisticJump: StopTravelSettings {
        StopTravelSettings(arrival: .jump, jumpTiming: .realistic, holdSeconds: 0, progression: .automatic, repeatMode: .oneWay)
    }

    func testTheWaitSaysWhenTheJumpComesAndThatNothingIsSentUntilThen() {
        let wait = progress(.waitingToJump, legLeft: 87, phaseTotal: 141)
        XCTAssertEqual(StopTravelCardText.countdown(wait), 87)
        XCTAssertEqual(StopTravelCardText.countdownCaption(wait), "Jump in")
        let text = StopTravelCardText.phaseExplanation(wait, settings: realisticJump, travelName: "Walking")
        XCTAssertEqual(
            text,
            "Realistic timing waits the trip time at Walking speed, then jumps to stop 2. Nothing is sent until then; the iPhone keeps its current location."
        )
    }

    func testTheWaitsProgressIsTheShareAlreadyWaited() {
        XCTAssertEqual(StopTravelCardText.phaseFraction(progress(.waitingToJump, legLeft: 141, phaseTotal: 141)) ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(StopTravelCardText.phaseFraction(progress(.waitingToJump, legLeft: 54, phaseTotal: 141)) ?? -1, 87.0 / 141, accuracy: 1e-9)
        XCTAssertEqual(StopTravelCardText.phaseFraction(progress(.holding, holdLeft: 0, held: 0, phaseTotal: 5)) ?? -1, 1, accuracy: 1e-9)
        XCTAssertNil(StopTravelCardText.phaseFraction(progress(.waitingToJump, legLeft: 54)), "no length, no bar")
        XCTAssertNil(StopTravelCardText.phaseFraction(progress(.findingRoute)), "nothing to count")
    }

    func testAHoldSaysWhatFollowsIt() {
        let travel = StopTravelSettings(arrival: .travel, jumpTiming: .fixed, holdSeconds: 5, progression: .automatic, repeatMode: .oneWay)
        let hold = progress(.holding, next: 2, total: 3, holdLeft: 3, held: 1, phaseTotal: 5)
        XCTAssertEqual(StopTravelCardText.countdownCaption(hold), "Leaves in")
        XCTAssertEqual(
            StopTravelCardText.phaseExplanation(hold, settings: travel, travelName: "Walking"),
            "The iPhone stays at stop 2, then travels to stop 3."
        )
        let last = progress(.holding, next: 2, total: 3, holdLeft: 3, held: 2, phaseTotal: 5)
        XCTAssertEqual(
            StopTravelCardText.phaseExplanation(last, settings: travel, travelName: "Walking"),
            "The iPhone stays at stop 3; the run then ends and keeps it."
        )
    }

    func testTheOtherPhasesSayWhatIsHappening() {
        XCTAssertEqual(StopTravelCardText.countdownCaption(progress(.travelling, legLeft: 30)), "Arrives in")
        XCTAssertNil(StopTravelCardText.phaseExplanation(progress(.travelling, legLeft: 30), settings: realisticJump, travelName: "Walking"))
        XCTAssertEqual(
            StopTravelCardText.phaseExplanation(progress(.findingRoute), settings: realisticJump, travelName: "Walking"),
            "Asking Apple Maps for a road route. Nothing is sent meanwhile."
        )
        XCTAssertEqual(
            StopTravelCardText.phaseExplanation(progress(.jumping, legLeft: 0), settings: realisticJump, travelName: "Walking"),
            "Sending the jump. Stop 2 counts once the iPhone confirms it."
        )
        XCTAssertEqual(
            StopTravelCardText.phaseExplanation(progress(.waitingToJump, legLeft: 50, phaseTotal: 141, paused: true), settings: realisticJump, travelName: "Walking"),
            "Paused: nothing is sent and the countdown stops. The iPhone keeps its current location."
        )
    }
}
