//
//  JoystickPolishTests.swift
//  PathChangerTests
//
//  Joystick polish (PRODUCT_REQUIREMENTS 3.5, owner decision 2026-11-02): the last
//  heading stays shown after the stick is released until the next movement or Clear,
//  and Joystick speed comes only from its own speed control.
//

import XCTest
@testable import PathChanger

@MainActor
final class JoystickPolishTests: XCTestCase {
    private let start = LocationCoordinate(latitude: 35.68000, longitude: 139.76000)
    private let session = LocationSessionIdentity(
        stableDeviceID: "joystick-polish-device",
        transport: .usb,
        endpointClass: .direct,
        generation: 1
    )

    private func makeState(
        injector: FakeLocationInjector,
        direction: CGPoint = CGPoint(x: 1, y: 0),
        defaults: UserDefaults? = nil
    ) -> AppState {
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: injector,
            stopTravelSettingsDefaults: defaults,
            routeDelay: { _ in }
        )
        state.selectedDevice = Device(id: "joystick-polish-device", displayName: "Joystick Device", connectionType: .usb)
        state.isTunneldRunning = true
        state.activeMode = .joystick
        state.stageLocation(start, for: .joystick)
        state.joystickDirection = direction
        state.locationSessionCoordinator.connectionReady(session)
        return state
    }

    /// Engages the joystick and acknowledges its start point; the first step is then pending.
    private func engage(_ state: AppState, _ fake: FakeLocationInjector) async {
        let engagement = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        await fake.releaseNextApplication(session: session)
        await engagement.value
        await fake.waitUntilApplicationPending()
    }

    private func appliedRequests(_ fake: FakeLocationInjector) async -> [LocationApplicationRequest] {
        await fake.calls().compactMap { call -> LocationApplicationRequest? in
            if case .apply(let request) = call { return request }
            return nil
        }
    }

    // MARK: - Heading readout (pure)

    func testHeadingTextPrefersTheLiveStickThenTheLastHeading() {
        XCTAssertEqual(JoystickReadout.headingText(live: CGPoint(x: 1, y: 0), last: nil), "90°")
        XCTAssertEqual(JoystickReadout.headingText(live: CGPoint(x: 0, y: 1), last: 200), "0°", "an engaged stick wins over the last heading")
        XCTAssertEqual(JoystickReadout.headingText(live: .zero, last: 45), "45°")
        XCTAssertEqual(JoystickReadout.headingText(live: CGPoint(x: 0.01, y: 0.01), last: 270), "270°", "a stick inside the dead zone is released")
        XCTAssertEqual(JoystickReadout.headingText(live: .zero, last: 359.7), "0°", "a heading rounds within 0-359")
        XCTAssertEqual(JoystickReadout.headingText(live: .zero, last: nil), "—")
    }

    func testHeadingAccessibilityLabelIsHumanText() {
        XCTAssertEqual(JoystickReadout.headingAccessibilityLabel(live: .zero, last: 45), "Heading 45 degrees")
        XCTAssertEqual(JoystickReadout.headingAccessibilityLabel(live: CGPoint(x: -1, y: 0), last: nil), "Heading 270 degrees")
        XCTAssertEqual(JoystickReadout.headingAccessibilityLabel(live: .zero, last: nil), "Heading not set")
    }

    func testHeadingDegreesFollowsCompassBearings() {
        XCTAssertEqual(JoystickReadout.degrees(CGPoint(x: 0, y: 1)), 0, accuracy: 1e-9)
        XCTAssertEqual(JoystickReadout.degrees(CGPoint(x: 1, y: 0)), 90, accuracy: 1e-9)
        XCTAssertEqual(JoystickReadout.degrees(CGPoint(x: 0, y: -1)), 180, accuracy: 1e-9)
        XCTAssertEqual(JoystickReadout.degrees(CGPoint(x: -1, y: 0)), 270, accuracy: 1e-9)
    }

    // MARK: - Last heading (AppState)

    func testAcknowledgedStepKeepsItsHeadingAfterReleaseAndDisengage() async {
        let fake = FakeLocationInjector()
        let state = makeState(injector: fake, direction: CGPoint(x: 1, y: 0))
        await engage(state, fake)
        XCTAssertNil(state.lastJoystickHeadingDegrees, "the start point is not a movement step")

        await fake.releaseNextApplication(session: session)  // step 1, east
        await fake.waitUntilApplicationPending()               // step 2 sent: step 1 processed
        XCTAssertEqual(state.lastJoystickHeadingDegrees ?? -1, 90, accuracy: 1e-6)

        state.updateJoystickDirection(.zero)  // the stick is released
        XCTAssertEqual(state.lastJoystickHeadingDegrees ?? -1, 90, accuracy: 1e-6)
        XCTAssertEqual(JoystickReadout.headingText(live: state.joystickDirection, last: state.lastJoystickHeadingDegrees), "90°")

        state.disengageJoystick()
        XCTAssertEqual(state.joystickDirection, .zero)
        XCTAssertEqual(state.lastJoystickHeadingDegrees ?? -1, 90, accuracy: 1e-6, "disengage holds the last heading")
        XCTAssertEqual(JoystickReadout.headingText(live: state.joystickDirection, last: state.lastJoystickHeadingDegrees), "90°")
        await fake.releaseNextApplication(session: session)
    }

    func testFailedStepDoesNotRecordItsHeading() async {
        let fake = FakeLocationInjector()
        let state = makeState(injector: fake, direction: CGPoint(x: 1, y: 0))
        state.smoothTurns = false
        await engage(state, fake)

        // Step 1 (east) is already computed and pending; step 2 reads the new direction.
        state.updateJoystickDirection(CGPoint(x: 0, y: 1))
        await fake.failNextApplication(code: "timeout")  // step 1 is not acknowledged
        await fake.waitUntilApplicationPending()          // step 2 sent: step 1 processed
        XCTAssertNil(state.lastJoystickHeadingDegrees, "an unacknowledged step must not show as the heading")

        await fake.releaseNextApplication(session: session)  // step 2, north, acknowledged
        await fake.waitUntilApplicationPending()
        XCTAssertEqual(state.lastJoystickHeadingDegrees ?? -1, 0, accuracy: 1e-6)

        state.disengageJoystick()
        await fake.releaseNextApplication(session: session)
    }

    func testRecordedHeadingIsTheSmoothedDirectionActuallyApplied() async {
        let fake = FakeLocationInjector()
        let state = makeState(injector: fake, direction: CGPoint(x: 1, y: 0))
        state.smoothTurns = true
        await engage(state, fake)

        // Step 1 (east, no previous heading) is already computed; step 2 reads north.
        state.updateJoystickDirection(CGPoint(x: 0, y: 1))
        await fake.releaseNextApplication(session: session)
        await fake.waitUntilApplicationPending()               // step 2, blended toward north
        await fake.releaseNextApplication(session: session)
        await fake.waitUntilApplicationPending()

        // 90° blended 35 % toward 0°: 58.5°, not the raw stick's 0°.
        XCTAssertEqual(state.lastJoystickHeadingDegrees ?? -1, 58.5, accuracy: 1e-6)
        state.disengageJoystick()
        await fake.releaseNextApplication(session: session)
    }

    func testSuccessfulClearForgetsTheLastHeading() async {
        let fake = FakeLocationInjector()
        let state = makeState(injector: fake)
        await engage(state, fake)
        await fake.releaseNextApplication(session: session)
        await fake.waitUntilApplicationPending()
        state.disengageJoystick()
        await fake.releaseNextApplication(session: session)
        XCTAssertNotNil(state.lastJoystickHeadingDegrees)

        await state.clearLocation()

        XCTAssertTrue(state.locationSessionCoordinator.state.application == .idle)
        XCTAssertNil(state.lastJoystickHeadingDegrees)
        XCTAssertEqual(JoystickReadout.headingText(live: state.joystickDirection, last: state.lastJoystickHeadingDegrees), "—")
    }

    func testFailedClearKeepsTheLastHeading() async {
        let fake = FakeLocationInjector()
        let state = makeState(injector: fake)
        await engage(state, fake)
        await fake.releaseNextApplication(session: session)
        await fake.waitUntilApplicationPending()
        state.disengageJoystick()
        await fake.releaseNextApplication(session: session)
        let heading = state.lastJoystickHeadingDegrees
        XCTAssertNotNil(heading)

        await fake.setShouldFailClear(true)
        await state.clearLocation()

        XCTAssertEqual(state.lastJoystickHeadingDegrees, heading, "the spoof is still held, so its heading stays")
    }

    func testMoveInAnotherModeForgetsTheLastHeading() async {
        let fake = FakeLocationInjector()
        let state = makeState(injector: fake)
        await engage(state, fake)
        await fake.releaseNextApplication(session: session)
        await fake.waitUntilApplicationPending()
        state.disengageJoystick()
        await fake.releaseNextApplication(session: session)
        XCTAssertNotNil(state.lastJoystickHeadingDegrees)

        state.activeMode = .teleport
        XCTAssertNotNil(state.lastJoystickHeadingDegrees, "changing mode alone is not a movement")
        state.stageLocation(LocationCoordinate(latitude: 35.69, longitude: 139.77), for: .teleport)
        let move = Task { await state.startSimulation() }
        await fake.waitUntilApplicationPending()
        XCTAssertNil(state.lastJoystickHeadingDegrees)
        await fake.releaseNextApplication(session: session)
        await move.value
        XCTAssertNil(state.lastJoystickHeadingDegrees)
    }

    // MARK: - Joystick speed

    func testJoystickStepUsesJoystickSpeedNotTheTravelMode() async {
        let fake = FakeLocationInjector()
        let state = makeState(injector: fake, direction: CGPoint(x: 0, y: 1))
        state.autoSpeed = true
        state.simulationSpeed = .driving  // 15.6 m/s travel preset
        state.updateFrequencyHz = 5
        state.joystickSpeed = 10
        await engage(state, fake)

        let requests = await appliedRequests(fake)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].coordinate, start)
        XCTAssertEqual(Geo.distance(from: start, to: requests[1].coordinate), 10 * 0.2, accuracy: 0.02)
        state.disengageJoystick()
        await fake.releaseNextApplication(session: session)
    }

    func testJoystickStepUsesJoystickSpeedNotTheCustomTravelSpeed() async {
        let fake = FakeLocationInjector()
        let state = makeState(injector: fake, direction: CGPoint(x: 0, y: 1))
        state.autoSpeed = false
        state.customSpeedMps = 1
        state.updateFrequencyHz = 4
        state.joystickSpeed = 8
        await engage(state, fake)

        let requests = await appliedRequests(fake)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(Geo.distance(from: start, to: requests[1].coordinate), 8 * 0.25, accuracy: 0.02)
        state.disengageJoystick()
        await fake.releaseNextApplication(session: session)
    }

    func testJoystickSpeedAndTravelSpeedAreIndependent() {
        let state = AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector())
        state.autoSpeed = false
        state.customSpeedMps = 4
        state.updateFrequencyHz = 5
        state.joystickSpeed = 20
        XCTAssertEqual(state.routeStepMeters, 0.8, accuracy: 1e-9, "joystick speed must not change route steps")
        XCTAssertEqual(state.effectiveMetersPerSecond, 4, accuracy: 1e-9, "joystick speed must not change stop-run speed")

        state.joystickSpeed = 7
        state.autoSpeed = true
        state.simulationSpeed = .driving
        state.setSpeed(.cycling)
        state.autoSpeed = false
        state.customSpeedMps = 12
        XCTAssertEqual(state.joystickSpeed, 7, accuracy: 1e-9, "travel settings must not change joystick speed")
    }

    func testJoystickSpeedDefaultsClampsAndPersists() throws {
        let suite = "PathChangerTests.JoystickSpeed.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector(), stopTravelSettingsDefaults: defaults)
        XCTAssertEqual(first.joystickSpeed, 5, accuracy: 1e-9)
        first.joystickSpeed = 100
        XCTAssertEqual(first.joystickSpeed, 30, accuracy: 1e-9)
        first.joystickSpeed = 0.2
        XCTAssertEqual(first.joystickSpeed, 1, accuracy: 1e-9)
        first.joystickSpeed = .nan
        XCTAssertEqual(first.joystickSpeed, 1, accuracy: 1e-9, "a non-finite value is ignored")
        first.joystickSpeed = 12.5
        XCTAssertEqual(defaults.double(forKey: "joystickSpeedMps"), 12.5, accuracy: 1e-9)

        let second = AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector(), stopTravelSettingsDefaults: defaults)
        XCTAssertEqual(second.joystickSpeed, 12.5, accuracy: 1e-9)

        defaults.set(99.0, forKey: "joystickSpeedMps")
        let third = AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector(), stopTravelSettingsDefaults: defaults)
        XCTAssertEqual(third.joystickSpeed, 30, accuracy: 1e-9, "a stored value out of range is clamped")

        let memoryOnly = AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector())
        memoryOnly.joystickSpeed = 9
        XCTAssertEqual(memoryOnly.joystickSpeed, 9, accuracy: 1e-9)
        let fresh = AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector())
        XCTAssertEqual(fresh.joystickSpeed, 5, accuracy: 1e-9, "tests keep joystick speed in memory")
    }

    func testShownSpeedIsJoystickSpeedOnlyWhileTheJoystickMoves() async {
        let fake = FakeLocationInjector()
        let state = makeState(injector: fake, direction: CGPoint(x: 0, y: 1))
        state.autoSpeed = false
        state.customSpeedMps = 1
        state.joystickSpeed = 10
        XCTAssertEqual(state.shownMovementSpeedMetersPerSecond, 0, "nothing moves yet")

        await engage(state, fake)
        XCTAssertEqual(state.locationSessionCoordinator.state.movement, .moving(.joystick))
        XCTAssertEqual(state.shownMovementSpeedMetersPerSecond, 10, accuracy: 1e-9)

        state.disengageJoystick()
        XCTAssertEqual(state.shownMovementSpeedMetersPerSecond, 0)
        await fake.releaseNextApplication(session: session)
    }

    // MARK: - Card wiring (source)

    func testJoystickCardUsesItsOwnSpeedAndHumanHeadingLabel() throws {
        let card = try sourceFile("PathChanger/UI/ModeContextCard.swift")
        let blockStart = try XCTUnwrap(card.range(of: "private var joystickBlock: some View {"))
        let rest = card[blockStart.upperBound...]
        let blockEnd = try XCTUnwrap(rest.range(of: "private var toggleBlock"))
        let block = String(rest[..<blockEnd.lowerBound])

        XCTAssertTrue(block.contains("$appState.joystickSpeed"), "the joystick slider binds joystick speed")
        XCTAssertFalse(block.contains("customSpeedMps"), "the joystick card must not read the travel speed")
        XCTAssertFalse(block.contains("effectiveMetersPerSecond"), "the joystick SPEED readout must not show the travel speed")
        XCTAssertFalse(block.contains("isAuto"), "travel modes do not apply to Joystick, so no Auto toggle")
        XCTAssertTrue(block.contains("appState.joystickSpeed : 0"), "SPEED shows joystick speed while moving, else 0")
        XCTAssertTrue(card.contains("JoystickReadout.headingText(live: appState.joystickDirection, last: appState.lastJoystickHeadingDegrees)"))
        XCTAssertTrue(card.contains("JoystickReadout.headingAccessibilityLabel(live: appState.joystickDirection, last: appState.lastJoystickHeadingDegrees)"))

        let chrome = try sourceFile("PathChanger/UI/OrganicChrome.swift")
        XCTAssertTrue(chrome.contains("appState.shownMovementSpeedMetersPerSecond"), "the telemetry bar shows the speed of the movement under way")
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

// MARK: - Arrow keys while the Settings panel is shown (review 2026-11-04 round 2 issue 8)

/// The centred Settings panel dims the window, yet the joystick's app-local arrow-key
/// monitor kept steering the phone behind it. While the panel is shown the keys go to the
/// panel; a key still held from before is released once, so the phone stops.
final class JoystickKeyRouterTests: XCTestCase {
    private let up: UInt16 = 126
    private let left: UInt16 = 123

    func testArrowKeysSteerWhileNoPanelIsShown() {
        var router = JoystickKeyRouter()
        XCTAssertEqual(router.handle(keyCode: up, isKeyDown: true, settingsPanelShown: false),
                       .steer(CGPoint(x: 0, y: 1)))
        XCTAssertEqual(router.handle(keyCode: up, isKeyDown: false, settingsPanelShown: false), .release)
        XCTAssertEqual(router.handle(keyCode: 0, isKeyDown: true, settingsPanelShown: false), .passThrough,
                       "other keys are not the joystick's")
    }

    func testArrowKeysNeverSteerWhileTheSettingsPanelIsShown() {
        var router = JoystickKeyRouter()
        XCTAssertEqual(router.handle(keyCode: up, isKeyDown: true, settingsPanelShown: true), .passThrough)
        XCTAssertEqual(router.handle(keyCode: left, isKeyDown: true, settingsPanelShown: true), .passThrough)
        XCTAssertEqual(router.handle(keyCode: left, isKeyDown: false, settingsPanelShown: true), .passThrough)
        XCTAssertTrue(router.heldKeys.isEmpty)
    }

    func testAKeyHeldWhenThePanelOpensStopsThePhoneOnce() {
        var router = JoystickKeyRouter()
        XCTAssertEqual(router.handle(keyCode: up, isKeyDown: true, settingsPanelShown: false),
                       .steer(CGPoint(x: 0, y: 1)))
        // Key repeat after the panel opened: released, then left to the panel.
        XCTAssertEqual(router.handle(keyCode: up, isKeyDown: true, settingsPanelShown: true), .release)
        XCTAssertEqual(router.handle(keyCode: up, isKeyDown: true, settingsPanelShown: true), .passThrough)
        XCTAssertEqual(router.handle(keyCode: up, isKeyDown: false, settingsPanelShown: true), .passThrough)
    }

    func testAKeyReleasedAfterThePanelClosedStillStopsThePhone() {
        var router = JoystickKeyRouter()
        _ = router.handle(keyCode: up, isKeyDown: true, settingsPanelShown: false)
        XCTAssertEqual(router.handle(keyCode: up, isKeyDown: false, settingsPanelShown: true), .release,
                       "the held key's release always reaches the joystick")
        XCTAssertTrue(router.heldKeys.isEmpty)
    }
}

/// The window's location and simulation menu shortcuts (⌘L, ⌘K, ⌘R, ⌘Space, ⌘P, ⌘Esc)
/// acted behind the Settings panel.
@MainActor
final class SettingsPanelShortcutTests: XCTestCase {
    func testWindowShortcutsAreOffWhileTheSettingsPanelIsShown() {
        let state = AppState(startBackgroundServices: false)
        XCTAssertTrue(state.acceptsWindowShortcuts)
        state.isSettingsPanelShown = true
        XCTAssertFalse(state.acceptsWindowShortcuts)
        state.isSettingsPanelShown = false
        XCTAssertTrue(state.acceptsWindowShortcuts)
    }
}
