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
        XCTAssertFalse(StopTravelCardText.jumpCanMove(stops: stops, cursor: finished, settings: settings(.jump, repeat: .oneWay)))
        XCTAssertTrue(
            StopTravelCardText.jumpCanMove(stops: stops, cursor: finished, settings: settings(.jump, repeat: .loop)),
            "a finished one-way Jump switched to Loop continues"
        )
        XCTAssertTrue(StopTravelCardText.jumpCanMove(stops: stops, cursor: finished, settings: settings(.jump, repeat: .backAndForth)))
        XCTAssertTrue(StopTravelCardText.jumpCanMove(stops: stops, cursor: StopCursor(nextIndex: 1), settings: settings(.jump)))
        XCTAssertFalse(StopTravelCardText.jumpCanMove(stops: [], cursor: StopCursor(), settings: settings(.jump, repeat: .loop)))
        XCTAssertFalse(
            StopTravelCardText.jumpCanMove(stops: [stops[0]], cursor: StopCursor(nextIndex: 1), settings: settings(.jump, repeat: .loop)),
            "one stop has nothing to loop to"
        )
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
}
