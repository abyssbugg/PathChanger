//
//  StopPanelLayoutTests.swift
//  PathChangerTests
//
//  The mounted mode card laid out the way ContentView places it, in an offscreen
//  window at fixed sizes: its footer (Move/Stop, Pause/Resume, Reset Route) must stay
//  inside the area the window gives the card, and content that does not fit scrolls.
//  GUI automation is blocked in agent sessions, so this is the hosted substitute.
//
//  PNG snapshots are written only when the marker file
//  `docs/superpowers/specs/stop-panel-snapshots/tmp_rovodev_write_snapshots` exists, so
//  ordinary test runs never touch the worktree.
//

import XCTest
import SwiftUI
import AppKit
@testable import PathChanger

/// Acknowledges every application at once.
private actor PanelAckInjector: LocationInjecting {
    func apply(_ request: LocationApplicationRequest) async throws -> LocationInjectionReceipt {
        LocationInjectionReceipt(
            requestID: request.id,
            session: UUID(),
            coordinate: request.coordinate,
            transport: request.target.transport,
            actualChannel: request.target.transport == .usb ? .usbLockdown : .networkLockdown,
            endpointClass: .direct,
            sessionGeneration: request.sessionGeneration ?? 1,
            completedAt: Date(),
            outcome: .applied
        )
    }

    func clear(target: LocationInjectionTarget, session: LocationSessionIdentity?) async throws {}
    func events() async -> AsyncStream<LocationBridgeEvent> { AsyncStream { _ in } }
}

/// Holds every route delay (a countdown tick) until released, so a run stays mid-wait.
@MainActor
private final class DelayGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var held = true

    func wait() async {
        guard held else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func releaseAll() {
        held = false
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

@MainActor
private final class PanelFrameRecorder {
    var cardFrame: CGRect = .zero
}

/// The map area as ContentView lays it out: the card at the top leading corner with the
/// same insets, over a stand-in for the map.
private struct PanelHost: View {
    let appState: AppState
    let mode: AppMode
    let insets: EdgeInsets
    let recorder: PanelFrameRecorder

    var body: some View {
        ZStack(alignment: .topLeading) {
            Organic.neutral300
            ModeContextCard(
                mode: .constant(mode),
                latitudeInput: .constant(""),
                longitudeInput: .constant(""),
                address: "Tap the map",
                onClose: {},
                onMove: {},
                onCommitCoords: {}
            )
            .background(
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named("panelHost"))
                    Color.clear
                        .onAppear { recorder.cardFrame = frame }
                        .onChange(of: frame) { _, newFrame in recorder.cardFrame = newFrame }
                }
            )
            .padding(insets)
        }
        .coordinateSpace(name: "panelHost")
        .environmentObject(appState)
        .environmentObject(TunneldManager.shared)
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
final class StopPanelLayoutTests: XCTestCase {
    /// "before" for snapshots of the unmodified card, "after" once the fix lands.
    private static let snapshotPhase = "after"
    /// ContentView's placement of the card in the map area.
    private static let insets = ModeContextCard.placementInsets
    /// The map area of the smallest window (760 pt minus the 56 pt title bar), a smaller
    /// one, and a tall one.
    private static let minimumMapHeight: CGFloat = 704
    private static let smallMapHeight: CGFloat = 506
    private static let tallMapHeight: CGFloat = 986
    private static let mapWidth: CGFloat = 368

    // About 100 m apart: north, then east.
    private let s0 = LocationCoordinate(latitude: 35.68000, longitude: 139.76000)
    private let s1 = LocationCoordinate(latitude: 35.68090, longitude: 139.76000)
    private let s2 = LocationCoordinate(latitude: 35.68090, longitude: 139.76110)

    private var gates: [DelayGate] = []
    private var runs: [Task<Void, Never>] = []
    private var states: [AppState] = []
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for state in states { await state.stopSimulation() }
        gates.forEach { $0.releaseAll() }
        for run in runs { await run.value }
        windows.forEach { $0.close() }
        gates = []; runs = []; states = []; windows = []
        try await super.tearDown()
    }

    // MARK: Harness

    private func makeState(mode: AppMode, stops: [LocationCoordinate], settings: StopTravelSettings?) -> AppState {
        let gate = DelayGate()
        gates.append(gate)
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: PanelAckInjector(),
            routeDelay: { _ in await gate.wait() }
        )
        states.append(state)
        state.selectedDevice = Device(id: "panel-device", displayName: "Panel Device", connectionType: .wifi)
        state.isTunneldRunning = true
        state.activeMode = mode
        state.autoSpeed = true
        state.setSpeed(.walking)
        for stop in stops { state.stageLocation(stop, for: mode) }
        if let settings { state.setStopTravelSettings(settings, for: mode) }
        state.locationSessionCoordinator.connectionReady(
            LocationSessionIdentity(stableDeviceID: "panel-device", transport: .wifi, endpointClass: .unresolved, generation: 1)
        )
        return state
    }

    private var realisticJump: StopTravelSettings {
        var settings = StopTravelSettings.defaults(for: .jump)
        settings.jumpTiming = .realistic
        return settings
    }

    /// Jump, Realistic, one stop per Move: stop 1 placed, then a Move waiting the trip
    /// time before jumping to stop 2 (screenshot A).
    private func makeActiveJump(paused: Bool = false) async -> AppState {
        let state = makeState(mode: .jump, stops: [s0, s1, s2], settings: realisticJump)
        await state.startSimulation()
        XCTAssertEqual(state.jumpIndex, 1, "harness: stop 1 placed")
        let run = Task { await state.startSimulation() }
        runs.append(run)
        await waitUntil { state.stopProgress != nil }
        if paused {
            state.pauseMovement()
            await waitUntil { state.stopProgress?.isPaused == true }
        }
        return state
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("condition not reached", file: file, line: line)
    }

    private struct Layout {
        let view: NSView
        let card: CGRect
        let mapSize: CGSize
        /// The bottom edge the card must not pass.
        var availableBottom: CGFloat { mapSize.height - StopPanelLayoutTests.insets.bottom }
        var availableHeight: CGFloat { availableBottom - StopPanelLayoutTests.insets.top }
    }

    private func layOut(_ state: AppState, mode: AppMode, mapHeight: CGFloat) async -> Layout {
        let recorder = PanelFrameRecorder()
        let size = CGSize(width: Self.mapWidth, height: mapHeight)
        let hosting = NSHostingView(rootView: PanelHost(appState: state, mode: mode, insets: Self.insets, recorder: recorder))
        // The window decides the size, as the user-sized app window does; the content's
        // ideal size must not grow the host (it did, hiding the overflow).
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        // A plain fixed-size container stands in for the user-sized window: the host is
        // pinned to it, so the card's ideal height can never grow what is shown.
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        window.contentView = container
        windows.append(window)
        window.setContentSize(size)
        container.frame = NSRect(origin: .zero, size: size)
        hosting.frame = container.bounds
        // Measured heights re-render; give layout a few passes to settle.
        for _ in 0..<6 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            await Task.yield()
        }
        XCTAssertEqual(hosting.bounds.size, size, "harness: the host keeps the window's size")
        return Layout(view: container, card: recorder.cardFrame, mapSize: size)
    }

    private func snapshot(_ layout: Layout, name: String) {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/superpowers/specs/stop-panel-snapshots")
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("tmp_rovodev_write_snapshots").path) else { return }
        let view = layout.view
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return XCTFail("no bitmap for \(name)")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return XCTFail("no PNG for \(name)") }
        let height = Int(layout.availableHeight.rounded())
        let file = directory.appendingPathComponent("\(Self.snapshotPhase)-\(name)-336x\(height).png")
        XCTAssertNoThrow(try png.write(to: file))
    }

    private func assertCardFits(_ layout: Layout, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(layout.card.height, 100, "harness: the card was measured (\(what))", file: file, line: line)
        XCTAssertLessThanOrEqual(
            layout.card.maxY, layout.availableBottom + 0.5,
            "\(what): the card (and its footer, its last element) must end inside the map area; " +
            "card \(layout.card), available bottom \(layout.availableBottom)",
            file: file, line: line
        )
    }

    // MARK: - Layout

    func testActiveJumpCardKeepsItsFooterInsideTheSmallestWindow() async {
        let state = await makeActiveJump()
        let layout = await layOut(state, mode: .jump, mapHeight: Self.minimumMapHeight)
        snapshot(layout, name: "jump-active")
        assertCardFits(layout, "Jump running, smallest window")
    }

    func testActiveJumpCardKeepsItsFooterInsideASmallerWindow() async {
        let state = await makeActiveJump()
        let layout = await layOut(state, mode: .jump, mapHeight: Self.smallMapHeight)
        snapshot(layout, name: "jump-active")
        assertCardFits(layout, "Jump running, small window")
        XCTAssertEqual(layout.card.height, layout.availableHeight, accuracy: 1, "content taller than the window fills the area and scrolls")
    }

    func testPausedJumpCardKeepsItsFooterInside() async {
        let state = await makeActiveJump(paused: true)
        let layout = await layOut(state, mode: .jump, mapHeight: Self.minimumMapHeight)
        snapshot(layout, name: "jump-paused")
        assertCardFits(layout, "Jump paused")
    }

    func testExpandedJumpTimingCardKeepsItsFooterInside() async {
        let state = makeState(mode: .jump, stops: [s0, s1, s2], settings: realisticJump)
        for height in [Self.minimumMapHeight, Self.smallMapHeight] {
            let layout = await layOut(state, mode: .jump, mapHeight: height)
            snapshot(layout, name: "jump-expanded")
            assertCardFits(layout, "Jump timing shown, map height \(height)")
        }
    }

    func testIdleJumpAndTravelCardsKeepTheirFooterInside() async {
        let jump = makeState(mode: .jump, stops: [s0, s1, s2], settings: nil)
        let jumpLayout = await layOut(jump, mode: .jump, mapHeight: Self.minimumMapHeight)
        snapshot(jumpLayout, name: "jump-idle")
        assertCardFits(jumpLayout, "Jump idle")

        let travel = makeState(mode: .route, stops: [s0, s1, s2], settings: nil)
        for height in [Self.minimumMapHeight, Self.smallMapHeight] {
            let layout = await layOut(travel, mode: .route, mapHeight: height)
            snapshot(layout, name: "travel-idle")
            assertCardFits(layout, "Multi-Spot travel idle, map height \(height)")
        }
    }

    func testATallWindowShowsTheWholeRunningCardWithoutStretchingIt() async {
        let state = await makeActiveJump()
        let layout = await layOut(state, mode: .jump, mapHeight: Self.tallMapHeight)
        snapshot(layout, name: "jump-active")
        assertCardFits(layout, "Jump running, tall window")
    }

    func testAShortCardHugsItsContentInsteadOfFillingTheWindow() async {
        let state = makeState(mode: .teleport, stops: [], settings: nil)
        let layout = await layOut(state, mode: .teleport, mapHeight: Self.minimumMapHeight)
        snapshot(layout, name: "teleport-idle")
        assertCardFits(layout, "Teleport idle")
        XCTAssertLessThan(layout.card.height, layout.availableHeight - 150, "a short card must not stretch to the window (the old maxHeight regression)")
    }
}

// MARK: - GUI arrangement snapshots (2026-11-04)

/// The whole window and its sections in fixture states (no device, no tunnel), rendered
/// offscreen in light and dark. PNGs are written only when the marker
/// `docs/superpowers/specs/gui-arrangement-snapshots/tmp_rovodev_write_snapshots` exists;
/// ordinary runs only check that each state renders.
@MainActor
final class GUIArrangementSnapshotTests: XCTestCase {
    /// "before" for the arrangement as it was, "after" once the redesign lands.
    static let snapshotPhase = "after"
    static let windowSize = CGSize(width: 1280, height: 800)

    private let s0 = LocationCoordinate(latitude: 35.68000, longitude: 139.76000)
    private let s1 = LocationCoordinate(latitude: 35.68090, longitude: 139.76000)
    private let s2 = LocationCoordinate(latitude: 35.68090, longitude: 139.76110)
    /// About 200 m north of `s0`: a Realistic jump at walking speed waits about 2:20.
    private let far = LocationCoordinate(latitude: 35.68180, longitude: 139.76000)

    private var gates: [DelayGate] = []
    private var runs: [Task<Void, Never>] = []
    private var states: [AppState] = []
    private var windows: [NSWindow] = []
    private var suites: [String] = []

    override func tearDown() async throws {
        for state in states { await state.stopSimulation() }
        gates.forEach { $0.releaseAll() }
        for run in runs { await run.value }
        windows.forEach { $0.close() }
        for suite in Set(suites) {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            // removePersistentDomain empties the domain but leaves its plist behind.
            let plist = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(suite).plist")
            try? FileManager.default.removeItem(at: plist)
        }
        gates = []; runs = []; states = []; windows = []; suites = []
        try await super.tearDown()
    }

    // MARK: Fixtures

    static let wifiPhone = Device(
        id: "00008120-000A1B2C3D4E5F60", displayName: "Ada's iPhone", connectionType: .wifi,
        productType: "iPhone16,1", productVersion: "17.6", deviceName: "Ada's iPhone"
    )
    static let usbPhone = Device(
        id: "00008030-001122334455667A", displayName: "Test iPhone", connectionType: .usb,
        productType: "iPhone14,2", productVersion: "17.4", deviceName: "Test iPhone"
    )

    private func makeState(mode: AppMode, stops: [LocationCoordinate] = [], settings: StopTravelSettings? = nil) -> AppState {
        let gate = DelayGate()
        gates.append(gate)
        let state = AppState(
            startBackgroundServices: false,
            locationInjector: PanelAckInjector(),
            routeDelay: { _ in await gate.wait() }
        )
        states.append(state)
        state.availableDevices = [Self.wifiPhone, Self.usbPhone]
        state.selectedDevice = Self.wifiPhone
        state.device.wifiDirectDeviceIds = [Self.wifiPhone.id]
        state.device.usbDirectDeviceIds = [Self.usbPhone.id]
        state.isTunneldRunning = true
        state.activeMode = mode
        state.autoSpeed = true
        state.setSpeed(.walking)
        for stop in stops { state.stageLocation(stop, for: mode) }
        if let settings { state.setStopTravelSettings(settings, for: mode) }
        state.locationSessionCoordinator.connectionReady(
            LocationSessionIdentity(stableDeviceID: Self.wifiPhone.id, transport: .wifi, endpointClass: .unresolved, generation: 1)
        )
        return state
    }

    /// Applies `coordinate` through Teleport (acknowledged at once), then switches to `mode`.
    private func hold(_ coordinate: LocationCoordinate, on state: AppState, thenMode mode: AppMode) async {
        state.activeMode = .teleport
        state.stageLocation(coordinate, for: .teleport)
        await state.startSimulation()
        XCTAssertEqual(state.currentLocation, coordinate, "harness: the location is held")
        state.activeMode = mode
    }

    private func start(_ state: AppState, until condition: @escaping () -> Bool) async {
        let run = Task { await state.startSimulation() }
        runs.append(run)
        await waitUntil(condition)
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<3_000 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("condition not reached", file: file, line: line)
    }

    private func settings(_ mode: AppMode, _ change: (inout StopTravelSettings) -> Void) -> StopTravelSettings {
        var settings = StopTravelSettings.defaults(for: mode)
        change(&settings)
        return settings
    }

    // MARK: Rendering

    private static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/superpowers/specs/gui-arrangement-snapshots")
    }

    private static var writesSnapshots: Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("tmp_rovodev_write_snapshots").path)
    }

    /// App storage for the hosted window, so the appearance never touches the app's own
    /// preferences.
    private func storage(dark: Bool) -> UserDefaults {
        let name = "tmp_rovodev.pathchanger.snapshots.\(dark ? "dark" : "light")"
        suites.append(name)
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(dark ? OrganicAppearance.dark.rawValue : OrganicAppearance.light.rawValue, forKey: "PathChanger.Appearance")
        defaults.set(true, forKey: "dismissedCoach")
        return defaults
    }

    @discardableResult
    private func render<V: View>(_ view: V, size: CGSize, dark: Bool, name: String) async -> NSView {
        let hosting = NSHostingView(rootView: view
            .defaultAppStorage(storage(dark: dark))
            .environment(\.colorScheme, dark ? .dark : .light))
        hosting.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        window.contentView = container
        windows.append(window)
        for _ in 0..<10 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
            await Task.yield()
        }
        XCTAssertEqual(hosting.bounds.size, size, "harness: the host keeps its size (\(name))")
        write(container, name: "\(name)-\(dark ? "dark" : "light")")
        return container
    }

    private func write(_ view: NSView, name: String) {
        guard Self.writesSnapshots else { return }
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return XCTFail("no bitmap for \(name)")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return XCTFail("no PNG for \(name)") }
        let file = Self.directory.appendingPathComponent("\(Self.snapshotPhase)-\(name).png")
        XCTAssertNoThrow(try png.write(to: file))
    }

    private func window(_ state: AppState, _ initial: ContentViewInitialState) -> some View {
        ContentView(initialState: initial)
            .environmentObject(state)
            .environmentObject(TunneldManager.shared)
    }

    private func renderWindow(_ state: AppState, _ initial: ContentViewInitialState, name: String) async {
        for dark in [false, true] {
            await render(window(state, initial), size: Self.windowSize, dark: dark, name: "window-\(name)")
        }
    }

    // MARK: Whole window, per mode

    func testWindowTeleport() async {
        let state = makeState(mode: .teleport)
        await hold(s0, on: state, thenMode: .teleport)
        state.stageLocation(s2, for: .teleport)
        await renderWindow(state, ContentViewInitialState(mode: .teleport, cardOpen: true), name: "teleport")
    }

    func testWindowJumpIdle() async {
        let state = makeState(mode: .jump, stops: [s0, s1, s2])
        await renderWindow(state, ContentViewInitialState(mode: .jump, cardOpen: true), name: "jump-idle")
    }

    /// Jump, Realistic, one stop per Move: stop 1 placed, then a Move waiting the trip time.
    func testWindowJumpWaiting() async {
        let state = makeState(mode: .jump, stops: [s0, s1, s2], settings: settings(.jump) { $0.jumpTiming = .realistic })
        await state.startSimulation()
        XCTAssertEqual(state.jumpIndex, 1, "harness: stop 1 placed")
        await start(state) { state.stopProgress?.phase == .waitingToJump }
        await renderWindow(state, ContentViewInitialState(mode: .jump, cardOpen: true), name: "jump-waiting")
        XCTAssertEqual(state.stopProgress?.phase, .waitingToJump, "the run is still under way in the snapshot")
    }

    /// Two-Spot, Getting there = Jump, Realistic: the owner's 2026-11-04 run that waited
    /// 141 s before its jump.
    func testWindowTwoSpotWaitingOnARealisticJump() async {
        let state = makeState(mode: .twospot, stops: [s0, far], settings: settings(.twospot) {
            $0.arrival = .jump
            $0.jumpTiming = .realistic
            $0.holdSeconds = 0
        })
        await start(state) { state.stopProgress?.phase == .waitingToJump }
        await renderWindow(state, ContentViewInitialState(mode: .twospot, cardOpen: true), name: "twospot-waiting")
        XCTAssertEqual(state.stopProgress?.phase, .waitingToJump, "the run is still under way in the snapshot")
    }

    func testWindowMultiSpotRunning() async {
        let state = makeState(mode: .route, stops: [s0, s1, s2])
        await start(state) { state.stopProgress?.phase == .travelling && state.currentLocation != nil }
        await renderWindow(state, ContentViewInitialState(mode: .route, cardOpen: true), name: "multispot-running")
        XCTAssertEqual(state.stopProgress?.phase, .travelling, "the run is still under way in the snapshot")
    }

    func testWindowJoystick() async {
        let state = makeState(mode: .joystick)
        await hold(s0, on: state, thenMode: .joystick)
        await renderWindow(state, ContentViewInitialState(mode: .joystick, cardOpen: true), name: "joystick")
    }

    // MARK: Settings

    func testSettingsPresentation() async {
        let state = makeState(mode: .teleport)
        await hold(s0, on: state, thenMode: .teleport)
        await renderWindow(state, ContentViewInitialState(mode: .teleport, cardOpen: false, showSettings: true), name: "settings")
    }

    // MARK: Device discovery

    func testDeviceDiscovery() async {
        let state = makeState(mode: .teleport)
        let view = VStack(spacing: 0) {
            OrganicTitleBar(
                appState: state,
                showDeviceMenu: .constant(false),
                showSettings: .constant(false),
                appearanceRaw: .constant(OrganicAppearance.light.rawValue),
                onRefresh: {}
            )
            HStack {
                Spacer()
                OrganicDevicePopover(isPresented: .constant(true), connectionMode: state.deviceManager.connectionMode)
                    .clipShape(RoundedRectangle(cornerRadius: Organic.radiusMD, style: .continuous))
                    .shadow(color: Organic.shadow.opacity(0.16), radius: 16, y: 8)
                Spacer()
            }
            .padding(.top, 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Organic.bg)
        .environmentObject(state)
        .environmentObject(TunneldManager.shared)
        for dark in [false, true] {
            await render(view, size: CGSize(width: 1280, height: 420), dark: dark, name: "devices")
        }
    }

    // MARK: Tunnel pill

    private struct TunnelFixture {
        let name: String
        let phase: TunnelPillPhase
        let notice: TunnelNotice?

        /// The pill for this phase with a selected phone (the flags `TunnelPillModel` reads).
        var model: TunnelPillModel {
            TunnelPillModel.resolve(
                isRunning: phase == .live, isWaitingForDevice: phase == .waitingForDevice,
                isStarting: phase == .connecting || phase == .waitingForDevice,
                isError: phase == .error || phase == .reconnecting,
                isAutoReconnecting: phase == .reconnecting, hasSelectedDevice: true
            )
        }
    }

    private var tunnelFixtures: [TunnelFixture] {
        [
            TunnelFixture(name: "idle", phase: .stopped, notice: nil),
            TunnelFixture(name: "starting", phase: .connecting, notice: nil),
            TunnelFixture(name: "waiting", phase: .waitingForDevice, notice: TunnelNotice.resolve(
                isWaitingForDevice: true, automaticReconnectNotice: nil, tunnelError: nil)),
            TunnelFixture(name: "running", phase: .live, notice: nil),
            TunnelFixture(name: "reconnecting", phase: .reconnecting, notice: TunnelNotice.resolve(
                isWaitingForDevice: false, isTunnelReconnecting: true,
                lastReconnectAttemptError: TunneldManager.wifiDeviceNotReachableMessage,
                automaticReconnectNotice: nil, tunnelError: nil)),
            TunnelFixture(name: "error", phase: .error, notice: TunnelNotice.resolve(
                isWaitingForDevice: false, automaticReconnectNotice: nil,
                tunnelError: TunneldManager.wifiUnlistedByUsbmuxMessage)),
        ]
    }

    func testTunnelPillStates() async {
        let state = makeState(mode: .teleport)
        for fixture in tunnelFixtures {
            let view = tunnelSection(fixture)
                .environmentObject(state)
                .environmentObject(TunneldManager.shared)
            for dark in [false, true] {
                await render(view, size: CGSize(width: 1280, height: 200), dark: dark, name: "tunnel-\(fixture.name)")
            }
        }
    }

    /// The tunnel section as the window shows it: the title bar's pill, and the notice strip
    /// right under the title bar.
    private func tunnelSection(_ fixture: TunnelFixture) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                TunnelPillFace(model: fixture.model)
                Spacer()
            }
            .frame(height: 56)
            .background(Organic.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(Organic.neutral400).frame(height: 1) }
            if let notice = fixture.notice {
                TunnelNoticeView(text: notice.text, isError: notice.isError)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Organic.bg)
    }
}
