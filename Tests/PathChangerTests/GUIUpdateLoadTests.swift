//
//  GUIUpdateLoadTests.swift
//  PathChangerTests
//
//  How much main-thread work a running route costs the GUI (owner report 2026-11-03:
//  "there's a lag when I click the GUI buttons"; a live `sample` during a 5 Hz Multi-Spot
//  run showed the main thread busy in SwiftUI updates most of the time).
//
//  The benchmark drives AppState through a real-time Multi-Spot travel run with an
//  injector that acknowledges each point after a short delay (the helper's round trip),
//  while the mounted views are laid out once per display frame in an offscreen window.
//  It counts AppState's change notifications, the renders of a view observing AppState,
//  LocationStatusPresentation constructions, and the main thread's CPU time. Results are
//  written to the test host's temporary directory (`pathchanger-gui-bench.txt`).
//

import XCTest
import SwiftUI
import AppKit
import Combine
import MapKit
@testable import PathChanger

/// Acknowledges every application after `roundTrip`, as the helper does.
private actor DelayedAckInjector: LocationInjecting {
    private let roundTripNanoseconds: UInt64
    private(set) var applied: [LocationCoordinate] = []

    init(roundTrip: TimeInterval) {
        roundTripNanoseconds = UInt64(roundTrip * 1_000_000_000)
    }

    func apply(_ request: LocationApplicationRequest) async throws -> LocationInjectionReceipt {
        if roundTripNanoseconds > 0 { try await Task.sleep(nanoseconds: roundTripNanoseconds) }
        applied.append(request.coordinate)
        return LocationInjectionReceipt(
            requestID: request.id,
            session: UUID(),
            coordinate: request.coordinate,
            transport: request.target.transport,
            actualChannel: .networkLockdown,
            endpointClass: .direct,
            sessionGeneration: request.sessionGeneration ?? 1,
            completedAt: Date(),
            outcome: .applied
        )
    }

    func clear(target: LocationInjectionTarget, session: LocationSessionIdentity?) async throws {}
    func events() async -> AsyncStream<LocationBridgeEvent> { AsyncStream { _ in } }
}

/// Stands in for clicks: every 10 ms a background timer enqueues a block on the main
/// queue and records how long it waited to run.
private final class ClickProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var waits: [Double] = []
    private var timer: DispatchSourceTimer?

    var waitsMs: [Double] { lock.withLock { waits } }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            let enqueued = DispatchTime.now().uptimeNanoseconds
            DispatchQueue.main.async {
                let waited = Double(DispatchTime.now().uptimeNanoseconds - enqueued) / 1_000_000
                self?.lock.withLock { self?.waits.append(waited) }
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}

@MainActor
private final class RenderCounter {
    var renders = 0
}

/// A view that observes AppState like every mounted view does; its body runs once per
/// AppState-driven render.
private struct RenderProbe: View {
    @EnvironmentObject var appState: AppState
    let counter: RenderCounter

    var body: some View {
        counter.renders += 1
        return Color.clear.frame(width: 1, height: 1)
    }
}

/// The owner's screen during the measured run: the whole window, plus the map and the
/// mode card in Multi-Spot (ContentView opens in Teleport with the card closed).
private struct BenchHost: View {
    let appState: AppState
    let counter: RenderCounter

    var body: some View {
        HStack(spacing: 0) {
            ContentView()
                .frame(width: 1180, height: 760)
            ZStack(alignment: .topLeading) {
                SimulationView(
                    mode: .route,
                    mapStyle: .constant(.standard),
                    latitudeInput: .constant(""),
                    longitudeInput: .constant(""),
                    addressText: .constant("")
                )
                ModeContextCard(
                    mode: .constant(.route),
                    latitudeInput: .constant(""),
                    longitudeInput: .constant(""),
                    address: "Tap the map",
                    onClose: {},
                    onMove: {},
                    onCommitCoords: {}
                )
                .padding(ModeContextCard.placementInsets)
                RenderProbe(counter: counter)
            }
            .frame(width: 420, height: 760)
        }
        .environmentObject(appState)
        .environmentObject(TunneldManager.shared)
        // The benchmark never depends on the user's real preferences: every @AppStorage
        // under this host (map style, layers, follow, coordinates overlay) reads the
        // application's shared store, which the app-hosted test process replaces with a
        // throwaway suite (review 2026-11-07).
        .defaultAppStorage(AppPreferences.store)
    }
}

struct GUIUpdateLoadSample: CustomStringConvertible {
    var acknowledgedPoints = 0
    var appStateSends = 0
    var probeRenders = 0
    var presentationBuilds = 0
    var mapContentBuilds = 0
    /// Body evaluations of the window, the title bar, the mode cards and the status panel.
    var contentViewRenders = 0
    var titleBarRenders = 0
    var modeCardRenders = 0
    var statusPanelRenders = 0
    var framesWithWork = 0
    var frames = 0
    var mainThreadCPUSeconds = 0.0
    var frameCPUSeconds = 0.0
    var wallSeconds = 0.0
    var idleCPUPerSecond = 0.0
    /// How long a main-queue block (what a click is) waited during the run, in ms.
    var clickWaitsMs: [Double] = []

    func clickWait(percentile: Double) -> Double {
        guard !clickWaitsMs.isEmpty else { return 0 }
        let sorted = clickWaitsMs.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * percentile))]
    }

    /// Main-thread CPU the run added over the idle GUI.
    var addedCPUSeconds: Double { max(0, mainThreadCPUSeconds - idleCPUPerSecond * wallSeconds) }

    func perPoint(_ value: Int) -> Double { Double(value) / Double(max(acknowledgedPoints, 1)) }

    var description: String {
        String(
            format: "points %d · AppState sends %d (%.2f/point) · probe renders %d (%.2f/point) · " +
                "presentation builds %d (%.2f/point) · map content builds %d (%.2f/point) · " +
                "renders: window %d (%.2f/point) title bar %d (%.2f/point) mode cards %d (%.2f/point) status panel %d (%.2f/point) · " +
                "frames with work %d of %d · " +
                "main-thread CPU %.3f s of %.3f s wall (%.0f%%) · idle %.0f%% · added by the run %.3f s (%.0f%%) · frame CPU %.3f s · " +
                "click wait p50 %.1f ms p95 %.1f ms max %.1f ms (%d probes)",
            acknowledgedPoints, appStateSends, perPoint(appStateSends), probeRenders, perPoint(probeRenders),
            presentationBuilds, perPoint(presentationBuilds), mapContentBuilds, perPoint(mapContentBuilds),
            contentViewRenders, perPoint(contentViewRenders), titleBarRenders, perPoint(titleBarRenders),
            modeCardRenders, perPoint(modeCardRenders), statusPanelRenders, perPoint(statusPanelRenders),
            framesWithWork, frames,
            mainThreadCPUSeconds, wallSeconds, 100 * mainThreadCPUSeconds / max(wallSeconds, 0.001),
            100 * idleCPUPerSecond, addedCPUSeconds, 100 * addedCPUSeconds / max(wallSeconds, 0.001),
            frameCPUSeconds,
            clickWait(percentile: 0.5), clickWait(percentile: 0.95), clickWait(percentile: 1), clickWaitsMs.count
        )
    }
}

@MainActor
final class GUIUpdateLoadTests: XCTestCase {
    private let s0 = LocationCoordinate(latitude: 35.68000, longitude: 139.76000)
    private let s1 = LocationCoordinate(latitude: 35.68090, longitude: 139.76000)
    private let s2 = LocationCoordinate(latitude: 35.68090, longitude: 139.76110)

    private var windows: [NSWindow] = []
    private var cancellables = Set<AnyCancellable>()

    override func tearDown() async throws {
        windows.forEach { $0.close() }
        windows = []
        cancellables = []
        try await super.tearDown()
    }

    private static func threadCPUSeconds() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1_000_000_000
    }

    private func makeRouteState(injector: any LocationInjecting, realTime: Bool) -> AppState {
        let state: AppState
        if realTime {
            state = AppState(startBackgroundServices: false, locationInjector: injector)
        } else {
            state = AppState(startBackgroundServices: false, locationInjector: injector, routeDelay: { _ in await Task.yield() })
        }
        state.selectedDevice = Device(id: "bench-device", displayName: "Bench Device", connectionType: .wifi)
        state.isTunneldRunning = true
        state.activeMode = .route
        state.autoSpeed = false
        state.customSpeedMps = 40
        state.updateFrequencyHz = 5
        for stop in [s0, s1, s2] { state.stageLocation(stop, for: .route) }
        state.setStopTravelSettings(
            StopTravelSettings(arrival: .travel, jumpTiming: .fixed, holdSeconds: 0, progression: .automatic, repeatMode: .oneWay),
            for: .route
        )
        state.locationSessionCoordinator.connectionReady(LocationSessionIdentity(
            stableDeviceID: "bench-device", transport: .wifi, endpointClass: .unresolved, generation: 1
        ))
        return state
    }

    private func host(_ state: AppState, counter: RenderCounter) -> NSHostingView<BenchHost> {
        let size = CGSize(width: 1600, height: 760)
        let hosting = NSHostingView(rootView: BenchHost(appState: state, counter: counter))
        hosting.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        windows.append(window)
        return hosting
    }

    private func record(_ sample: GUIUpdateLoadSample, name: String) {
        recordLine("[GUIBench] \(name): \(sample)")
    }

    private func recordLine(_ line: String) {
        print(line)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pathchanger-gui-bench.txt")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
        let attachment = XCTAttachment(string: line)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The mounted GUI during a real-time 5 Hz Multi-Spot run, laid out at 60 frames a
    /// second.
    func testAMultiSpotRunRebuildsThePresentationAndTheMapsOnlyForWhatTheyShow() async throws {
        let injector = DelayedAckInjector(roundTrip: 0.03)
        let state = makeRouteState(injector: injector, realTime: true)
        let counter = RenderCounter()
        let hosting = host(state, counter: counter)
        for _ in 0..<5 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        // ContentView's first appearance selects Teleport; the measured run is Multi-Spot.
        state.activeMode = .route
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(counter.renders, 0, "harness: the probe rendered")

        var sample = GUIUpdateLoadSample()
        // The idle cost of the same frames (the maps draw on the main thread whether or
        // not anything changes), subtracted from the run's.
        let idleStart = Self.threadCPUSeconds()
        let idleWallStart = Date()
        for _ in 0..<120 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 16_000_000)
        }
        sample.idleCPUPerSecond = (Self.threadCPUSeconds() - idleStart) / Date().timeIntervalSince(idleWallStart)

        state.objectWillChange.sink { sample.appStateSends += 1 }.store(in: &cancellables)
        let rendersBefore = counter.renders
        let buildsBefore = LocationStatusPresentation.debugBuildCount
        let mapBuildsBefore = SimulationMapCanvas.debugBuildCount
        let rendersAtStart = (GUIRenderCounts.contentView, GUIRenderCounts.titleBar, GUIRenderCounts.modeCard, GUIRenderCounts.statusPanel)
        let cpuStart = Self.threadCPUSeconds()
        let wallStart = Date()

        var finished = false
        let clicks = ClickProbe()
        clicks.start()
        let run = Task { @MainActor in
            await state.startSimulation()
            finished = true
        }
        while !finished {
            let renders = counter.renders
            let builds = LocationStatusPresentation.debugBuildCount
            let frameStart = Self.threadCPUSeconds()
            hosting.layoutSubtreeIfNeeded()
            sample.frameCPUSeconds += Self.threadCPUSeconds() - frameStart
            sample.frames += 1
            if counter.renders != renders || LocationStatusPresentation.debugBuildCount != builds {
                sample.framesWithWork += 1
            }
            try await Task.sleep(nanoseconds: 16_000_000)
        }
        await run.value
        clicks.stop()
        sample.clickWaitsMs = clicks.waitsMs
        hosting.layoutSubtreeIfNeeded()

        sample.wallSeconds = Date().timeIntervalSince(wallStart)
        sample.mainThreadCPUSeconds = Self.threadCPUSeconds() - cpuStart
        sample.acknowledgedPoints = await injector.applied.count
        sample.probeRenders = counter.renders - rendersBefore
        sample.presentationBuilds = LocationStatusPresentation.debugBuildCount - buildsBefore
        sample.mapContentBuilds = SimulationMapCanvas.debugBuildCount - mapBuildsBefore
        sample.contentViewRenders = GUIRenderCounts.contentView - rendersAtStart.0
        sample.titleBarRenders = GUIRenderCounts.titleBar - rendersAtStart.1
        sample.modeCardRenders = GUIRenderCounts.modeCard - rendersAtStart.2
        sample.statusPanelRenders = GUIRenderCounts.statusPanel - rendersAtStart.3
        record(sample, name: "hosted 5 Hz Multi-Spot run")

        XCTAssertEqual(state.currentLocation, s2, "harness: the run reached its last stop")
        XCTAssertGreaterThan(sample.acknowledgedPoints, 15, "harness: the run sent many points")
        // Each render reads the presentation once (memoized per state change), not once
        // per view and property that shows it.
        XCTAssertLessThanOrEqual(
            sample.presentationBuilds, sample.acknowledgedPoints * 3 + 10,
            "the presentation was rebuilt on every read: \(sample)"
        )
        // SwiftUI renders once per run-loop turn: a step's send and its receipt are two
        // turns, so about two renders per point. More means something publishes in turns
        // of its own.
        XCTAssertLessThanOrEqual(
            sample.probeRenders, sample.acknowledgedPoints * 3 + 10,
            "AppState observers re-rendered more often than the run's steps and receipts: \(sample)"
        )
        // The host shows two maps (ContentView's and the Multi-Spot one). Each changes once
        // per acknowledged point (the dot, the trail); a step being sent, the run's
        // countdown and the card change nothing on the map, so they must not rebuild it.
        XCTAssertLessThanOrEqual(
            sample.mapContentBuilds, sample.acknowledgedPoints * 2 + 10,
            "the maps were rebuilt for changes they do not show: \(sample)"
        )
        // The title bar shows the phone, its connection choice and the tunnel; a running
        // route changes none of them (GUI arrangement 2026-11-04: it rendered with every
        // AppState change, 2.15 times per point).
        XCTAssertLessThanOrEqual(sample.titleBarRenders, 5, "the title bar re-rendered for route changes: \(sample)")
    }

    /// The same run without the GUI and without real time: how many change notifications
    /// AppState sends per acknowledged point.
    func testAHeadlessMultiSpotRunCountsAppStateNotifications() async throws {
        let injector = DelayedAckInjector(roundTrip: 0)
        let state = makeRouteState(injector: injector, realTime: false)
        var sample = GUIUpdateLoadSample()
        state.objectWillChange.sink { sample.appStateSends += 1 }.store(in: &cancellables)
        let cpuStart = Self.threadCPUSeconds()
        let wallStart = Date()
        await state.startSimulation()
        sample.wallSeconds = Date().timeIntervalSince(wallStart)
        sample.mainThreadCPUSeconds = Self.threadCPUSeconds() - cpuStart
        sample.acknowledgedPoints = await injector.applied.count
        record(sample, name: "headless run")

        XCTAssertEqual(state.currentLocation, s2, "harness: the run reached its last stop")
        XCTAssertGreaterThan(sample.acknowledgedPoints, 15, "harness: the run sent many points")
    }

    // MARK: - The location presentation
    // MARK: - The location presentation

    /// Every view and property that shows the location status read `locationPresentation`,
    /// and each read built it again (with a new ISO 8601 formatter): about 25 builds per
    /// render in the benchmark. It is built once per change of what it shows.
    func testReadingThePresentationBuildsItOncePerChangeOfWhatItShows() {
        let state = AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector())
        let start = LocationStatusPresentation.debugBuildCount
        let first = state.locationPresentation
        for _ in 0..<10 { _ = state.locationPresentation }
        XCTAssertEqual(LocationStatusPresentation.debugBuildCount - start, 1, "unchanged state is built once")
        XCTAssertEqual(first.deviceLifecycleLabel, "No visible device")

        state.selectedDevice = Device(id: "bench-device", displayName: "Bench Device", connectionType: .wifi)
        XCTAssertEqual(state.locationPresentation.deviceLifecycleLabel, "Device visible", "a device change shows at once")
        let session = LocationSessionIdentity(stableDeviceID: "bench-device", transport: .wifi, endpointClass: .unresolved, generation: 1)
        state.locationSessionCoordinator.connectionReady(session)
        let ready = state.locationPresentation
        XCTAssertEqual(ready, LocationStatusPresentation(
            state: state.locationSessionCoordinator.state,
            deviceVisible: true
        ), "a session change shows at once and matches a fresh build")
        for _ in 0..<10 { _ = state.locationPresentation }
        XCTAssertEqual(LocationStatusPresentation.debugBuildCount - start, 4, "one build per change, plus the fresh one above")
    }

    // MARK: - Forwarding the managers' changes

    /// AppState re-sends every manager's change, synchronously (about 17 per acknowledged
    /// point in the benchmark). Measured 2026-11-04: a re-send costs a few microseconds,
    /// and SwiftUI renders once per run-loop turn however many arrive in it (about 2.2
    /// renders per point), so the count of re-sends is not what loads the main thread;
    /// this keeps the forwarding complete and synchronous.
    func testEveryManagersChangeReachesAppStateObserversSynchronously() {
        let state = AppState(startBackgroundServices: false, locationInjector: FakeLocationInjector())
        XCTAssertTrue(state.objectWillChange === state.objectWillChange, "AppState has one change publisher")
        var heard = 0
        state.objectWillChange.sink { heard += 1 }.store(in: &cancellables)
        state.simulation.currentLocation = s0
        XCTAssertEqual(heard, 1, "the simulation's change reaches AppState's observers")
        state.travelTrail.record(s1, mode: .route, after: s0)
        XCTAssertEqual(heard, 2, "the trail's change reaches them")
        state.route.progress = 0.5
        XCTAssertEqual(heard, 3, "the route's change reaches them")
        state.locationSessionCoordinator.select(s2, mode: .multiSpot)
        XCTAssertEqual(heard, 4, "the session's change reaches them, synchronously")

        let sends = 20_000
        let start = Self.threadCPUSeconds()
        for _ in 0..<sends { state.simulation.objectWillChange.send() }
        let perSend = (Self.threadCPUSeconds() - start) * 1_000_000 / Double(sends)
        recordLine(String(format: "[GUIBench] forwarding: %.2f µs of main-thread CPU per forwarded manager change", perSend))
        XCTAssertEqual(heard, 4 + sends)
    }

    // MARK: - The main thread stays free

    /// Every acknowledged point refreshes the helper connection: it read the token, the
    /// helper record (tens of KB of JSON) and hashed the Python and bridge files on the
    /// main thread, five times a second during a run (a live sample showed the bridge's
    /// setLocation on the main thread). That file work runs off the main thread.
    func testRefreshingTheHelperConnectionReadsItsFilesOffTheMainThread() async throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("pathchanger-refresh-offmain-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let python = root.appendingPathComponent("python3")
        let bridge = root.appendingPathComponent("location_bridge.py")
        try Data("python stand-in".utf8).write(to: python)
        try Data("bridge stand-in".utf8).write(to: bridge)
        let fileManager = ThreadRecordingFileManager()
        let controller = ManagedLocationHelperController(
            paths: ManagedLocationHelperPaths(baseDirectory: root.appendingPathComponent("helper", isDirectory: true)),
            pythonPath: python.path,
            bridgePath: bridge.path,
            fileManager: fileManager
        )

        do {
            _ = try await controller.refreshConnection()
            XCTFail("harness: there is no helper record, so the refresh fails")
        } catch ManagedLocationHelperController.ControllerError.invalidRecord {
            // Expected: the files were read, then the missing record ended the refresh.
        }
        XCTAssertGreaterThan(fileManager.callCount, 0, "harness: the refresh used the file manager")
        XCTAssertEqual(fileManager.mainThreadCalls, [], "the helper files were read on the main thread")
    }
}

/// Main-thread time of the helper refresh every acknowledged point makes, against a real
/// helper process (no device: the helper only answers its socket).
@MainActor
final class HelperRefreshLoadTests: XCTestCase {
    func testTheHelperRefreshAfterEachPointBarelyUsesTheMainThread() async throws {
        guard FileManager.default.isExecutableFile(atPath: PythonPathResolver.managedPythonPath) else {
            throw XCTSkip("Managed Python runtime is unavailable")
        }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bridgeScript = repositoryRoot.appendingPathComponent("scripts/location_bridge.py")
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("pathchanger-refresh-load-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ManagedLocationHelperController(
            paths: ManagedLocationHelperPaths(baseDirectory: root),
            pythonPath: PythonPathResolver.managedPythonPath,
            bridgePath: bridgeScript.path
        )
        let bridge = PersistentLocationBridge(helperController: controller)
        do {
            try await bridge.start()
            try await bridge.refreshAdoptedHelperSessions()
            let refreshes = 50
            let cpuStart = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1_000_000_000
            let wallStart = Date()
            for _ in 0..<refreshes { try await bridge.refreshAdoptedHelperSessions() }
            let mainCPU = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1_000_000_000 - cpuStart
            let wall = Date().timeIntervalSince(wallStart)
            let line = String(
                format: "[GUIBench] helper refresh: %d refreshes · main-thread CPU %.2f ms per refresh · wall %.2f ms per refresh",
                refreshes, mainCPU * 1000 / Double(refreshes), wall * 1000 / Double(refreshes)
            )
            print(line)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pathchanger-gui-bench.txt")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(Data((line + "\n").utf8)); try? handle.close()
            } else {
                try? Data((line + "\n").utf8).write(to: url)
            }
            add(XCTAttachment(string: line))
        } catch {
            try? await controller.shutdown()
            throw error
        }
        try? await controller.shutdown()
    }
}

/// Records which file-manager calls ran on the main thread.
private final class ThreadRecordingFileManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var onMain: [String] = []

    var callCount: Int { lock.withLock { calls } }
    var mainThreadCalls: [String] { lock.withLock { onMain } }

    private func record(_ name: String) {
        let isMain = Thread.isMainThread
        lock.withLock {
            calls += 1
            if isMain { onMain.append(name) }
        }
    }

    override func fileExists(atPath path: String) -> Bool {
        record("fileExists")
        return super.fileExists(atPath: path)
    }

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        record("attributesOfItem")
        return try super.attributesOfItem(atPath: path)
    }

    override func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        record("setAttributes")
        try super.setAttributes(attributes, ofItemAtPath: path)
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        record("createDirectory")
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
}

/// The lower bound the benchmark's rebuild ceiling does not give (review 2026-11-04
/// issue 10): an `==` that wrongly returned true would skip a rebuild and leave the map
/// drawing stale content. Every input the canvas draws must make it unequal.
@MainActor
final class SimulationMapCanvasEqualityTests: XCTestCase {
    private func canvas(
        marker: LocationMarker? = LocationMarker(
            coordinate: LocationCoordinate(latitude: 35.6762, longitude: 139.6503), style: .spoofed),
        mode: AppMode = .route,
        legs: [RoutePreviewModel.Leg] = [RoutePreviewModel.Leg(
            id: 0,
            points: [LocationCoordinate(latitude: 35.0, longitude: 139.0),
                     LocationCoordinate(latitude: 35.1, longitude: 139.1)],
            style: .road)],
        trailSegments: [[LocationCoordinate]] = [[LocationCoordinate(latitude: 35.0, longitude: 139.0)]],
        routeStops: [LocationCoordinate] = [LocationCoordinate(latitude: 35.1, longitude: 139.1)],
        mapStyle: MapStyleType = .standard,
        mapLayer: MapLayerConfiguration = .default,
        cameraPosition: MapCameraPosition = .automatic
    ) -> SimulationMapCanvas {
        SimulationMapCanvas(
            marker: marker, mode: mode, legs: legs, trailSegments: trailSegments, routeStops: routeStops,
            mapStyle: mapStyle, mapLayer: mapLayer, cameraPosition: cameraPosition, position: .constant(cameraPosition),
            onCameraChangeEnd: { _, _ in }, onTap: { _ in }, onRemoveStop: { _ in }
        )
    }

    func testTheSameInputsAreEqual() {
        XCTAssertEqual(canvas(), canvas(), "the closures are not compared")
    }

    func testEveryDrawnInputMakesTheCanvasRebuild() {
        let base = canvas()
        let moved = LocationCoordinate(latitude: 35.6800, longitude: 139.6600)
        let changes: [(String, SimulationMapCanvas)] = [
            ("marker coordinate", canvas(marker: LocationMarker(coordinate: moved, style: .spoofed))),
            ("marker style", canvas(marker: LocationMarker(
                coordinate: LocationCoordinate(latitude: 35.6762, longitude: 139.6503), style: .uncertain))),
            ("no marker", canvas(marker: nil)),
            ("mode", canvas(mode: .jump)),
            ("legs", canvas(legs: [])),
            ("leg style", canvas(legs: [RoutePreviewModel.Leg(
                id: 0,
                points: [LocationCoordinate(latitude: 35.0, longitude: 139.0),
                         LocationCoordinate(latitude: 35.1, longitude: 139.1)],
                style: .straight)])),
            ("trail", canvas(trailSegments: [[LocationCoordinate(latitude: 35.0, longitude: 139.0), moved]])),
            ("stops", canvas(routeStops: [moved])),
            ("map style", canvas(mapStyle: .satellite)),
            ("map layer", canvas(mapLayer: MapLayerConfiguration(elevation3D: true, showsTraffic: true, showsPlaces: false))),
            ("camera position", canvas(cameraPosition: .region(MKCoordinateRegion(
                center: moved.clLocationCoordinate2D,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))))),
        ]
        for (input, changed) in changes {
            XCTAssertNotEqual(base, changed, "a changed \(input) must rebuild the map")
        }
    }
}

/// Review 2026-11-04 round 2 issue 9: the title bar's `==` compared bindings, and the
/// parent's bindings read the same storage on both sides, so a changed device menu,
/// Settings highlight or theme always compared equal. The values the parent rendered
/// with are compared instead.
@MainActor
final class OrganicTitleBarEqualityTests: XCTestCase {
    private final class Storage {
        var showDeviceMenu = false
        var showSettings = false
        var appearanceRaw = OrganicAppearance.light.rawValue
    }

    private func titleBar(_ appState: AppState, _ storage: Storage) -> OrganicTitleBar {
        OrganicTitleBar(
            appState: appState,
            showDeviceMenu: Binding(get: { storage.showDeviceMenu }, set: { storage.showDeviceMenu = $0 }),
            showSettings: Binding(get: { storage.showSettings }, set: { storage.showSettings = $0 }),
            appearanceRaw: Binding(get: { storage.appearanceRaw }, set: { storage.appearanceRaw = $0 }),
            onRefresh: {}
        )
    }

    func testTheSameValuesAreEqual() {
        let state = AppState(startBackgroundServices: false)
        let storage = Storage()
        XCTAssertEqual(titleBar(state, storage), titleBar(state, storage), "the closures are not compared")
    }

    func testEveryValueChangeMakesTheTitleBarUnequal() {
        let state = AppState(startBackgroundServices: false)
        let changes: [(String, (Storage) -> Void)] = [
            ("device menu", { $0.showDeviceMenu = true }),
            ("Settings highlight", { $0.showSettings = true }),
            ("theme", { $0.appearanceRaw = OrganicAppearance.dark.rawValue }),
        ]
        for (input, change) in changes {
            let storage = Storage()
            let before = titleBar(state, storage)
            change(storage)
            let after = titleBar(state, storage)
            XCTAssertNotEqual(before, after, "a changed \(input) must redraw the title bar")
        }
    }
}
