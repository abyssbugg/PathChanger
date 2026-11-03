//
//  RouteStateManager.swift
//  PathChanger
//
//  Owns route contents, waypoint editing and playback position.
//  Part of the AppState decomposition (ARCH-002).
//
//  Unlike the device and simulation managers, this type was *richer* than the AppState code
//  it replaces: named routes, a playback state machine, skip controls, total distance and
//  ETA all existed here and were tested. Those are kept. What has been added is everything
//  AppState had and this did not: jump indexing, waypoint editing, and a GPX import that
//  reads routes and waypoints rather than tracks alone.
//
//  Playback itself deliberately does not live here. AppState still drives route playback
//  until the simulation engine takes it over, so that there is exactly one playback loop in
//  the codebase at any time.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Route Playback State

/// Current state of route playback
enum RoutePlaybackState: Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case completed
    case error(String)

    var isActive: Bool {
        switch self {
        case .playing, .paused:
            return true
        default:
            return false
        }
    }

    var displayText: String {
        switch self {
        case .idle: return "No route loaded"
        case .loading: return "Loading route..."
        case .ready: return "Ready to play"
        case .playing: return "Playing..."
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .error(let message): return "Error: \(message)"
        }
    }
}

// MARK: - Route State Manager

@MainActor
final class RouteStateManager: ObservableObject {

    // MARK: Published Properties

    /// Current route coordinates: the stops of the active mode (`stopsMode`). Each mode
    /// keeps its own stops (`switchStops(to:)`), so the GUI reads one list.
    @Published var currentRoute: [LocationCoordinate] = [] {
        // A change to the stops starts the active stop mode's progress over, except
        // appending stops (owner rule 2026-11-03; `keepsStopProgress`). Loading another
        // mode's stops is not a change to them.
        didSet {
            if currentRoute != oldValue, stopListChange == .edit { applyStopEdit(from: oldValue, to: currentRoute) }
        }
    }

    /// What the change to `currentRoute` being published is, for observers that see it
    /// before it lands (`$currentRoute` fires on willSet).
    enum StopListChange: Equatable {
        /// The user's stops changed (click, remove, move, reverse, import, Reset Route).
        case edit
        /// Another mode's stops are being shown; nobody edited a stop.
        case modeSwitch
    }
    private(set) var stopListChange: StopListChange = .edit

    /// The mode whose stops `currentRoute` is.
    private(set) var stopsMode: AppMode = .teleport

    /// The stops of every mode not shown now (the shown mode's are `currentRoute`).
    private struct StopSlot {
        var stops: [LocationCoordinate]
        var name: String?
    }
    private var stopSlots: [AppMode: StopSlot] = [:]

    /// Playback progress (0.0 to 1.0)
    @Published var progress: Double = 0

    /// Current playback state
    @Published var playbackState: RoutePlaybackState = .idle

    /// Current position index in route
    @Published var currentIndex: Int = 0

    /// Route name for display
    @Published var routeName: String?

    /// Total route distance in meters
    @Published var totalDistance: Double = 0

    /// Estimated remaining time
    @Published var estimatedRemainingTime: TimeInterval = 0

    /// Loop playback enabled
    @Published var loopEnabled: Bool = false

    /// Reverse direction on loop
    @Published var reverseOnLoop: Bool = false

    /// Index of the next hop in Jump mode
    @Published var jumpIndex: Int = 0 {
        // At the first stop the direction makes no difference; resetting it here keeps
        // every "back to the first hop" reset (a stop edit, Reset, Clear) a clean restart.
        didSet { if jumpIndex == 0 { jumpReversed = false } }
    }

    /// Jump's back-and-forth direction (heading back toward the first stop).
    @Published var jumpReversed: Bool = false

    /// Two-Spot and Multi-Spot: each mode's next stop and direction. Advances only on an
    /// acknowledged arrival; a stop edit, Reset Route or a confirmed Clear resets it. One
    /// entry per mode, like the stops (`stopSlots`).
    @Published private(set) var routeStopCursors: [AppMode: StopCursor] = [:]

    /// Stop-by-stop options per mode (PRODUCT_REQUIREMENTS 3.6); a missing entry means the
    /// mode's defaults.
    @Published private(set) var stopTravelSettingsByMode: [AppMode: StopTravelSettings] = [:]

    // MARK: Dependencies

    let routeLibrary: RouteLibraryManager
    weak var simulationStateManager: SimulationStateManager?
    /// Where stop settings persist; nil keeps them in memory (tests, previews).
    private let settingsDefaults: UserDefaults?

    private var cancellables = Set<AnyCancellable>()

    // MARK: Computed Properties

    /// Whether a route is loaded and ready
    var isRouteLoaded: Bool {
        !currentRoute.isEmpty
    }

    /// Whether the route is currently loading
    var isLoading: Bool {
        playbackState == .loading
    }

    /// Number of waypoints in route
    var waypointCount: Int {
        currentRoute.count
    }

    /// Whether playback can be started
    var canStartPlayback: Bool {
        isRouteLoaded && playbackState != .playing
    }

    /// Current waypoint coordinate
    var currentWaypoint: LocationCoordinate? {
        guard currentIndex < currentRoute.count else { return nil }
        return currentRoute[currentIndex]
    }

    // MARK: Initialization

    init(routeLibrary: RouteLibraryManager, settingsDefaults: UserDefaults? = nil) {
        self.routeLibrary = routeLibrary
        self.settingsDefaults = settingsDefaults
        if let settingsDefaults {
            for mode in Self.stopModes {
                guard let data = settingsDefaults.data(forKey: Self.settingsKey(for: mode)),
                      let settings = try? JSONDecoder().decode(StopTravelSettings.self, from: data) else { continue }
                stopTravelSettingsByMode[mode] = settings
            }
        }
    }

    // MARK: Stop Settings

    static let stopModes: [AppMode] = [.jump, .twospot, .route]

    static func settingsKey(for mode: AppMode) -> String {
        "PathChanger.stopTravelSettings.\(mode.rawValue)"
    }

    func stopTravelSettings(for mode: AppMode) -> StopTravelSettings {
        stopTravelSettingsByMode[mode] ?? .defaults(for: mode)
    }

    func setStopTravelSettings(_ settings: StopTravelSettings, for mode: AppMode) {
        guard stopTravelSettings(for: mode) != settings else { return }
        stopTravelSettingsByMode[mode] = settings
        if let settingsDefaults, let data = try? JSONEncoder().encode(settings) {
            settingsDefaults.set(data, forKey: Self.settingsKey(for: mode))
        }
    }

    // MARK: Stop Progress

    /// Where `mode`'s stop run stands: Jump's hop index and direction, or the Two-Spot /
    /// Multi-Spot cursor.
    func stopCursor(for mode: AppMode) -> StopCursor {
        mode == .jump
            ? StopCursor(nextIndex: jumpIndex, reversed: jumpReversed)
            : routeStopCursors[mode] ?? StopCursor()
    }

    func setStopCursor(_ cursor: StopCursor, for mode: AppMode) {
        if mode == .jump {
            jumpIndex = cursor.nextIndex
            jumpReversed = cursor.reversed
        } else {
            routeStopCursors[mode] = cursor
        }
    }

    /// Every stop mode starts over at stop 1 (a confirmed Clear).
    func resetStopProgress() {
        jumpIndex = 0
        jumpReversed = false
        if !routeStopCursors.isEmpty { routeStopCursors = [:] }
    }

    /// `mode` starts over at stop 1: its stops changed, were reset or were seeded.
    func resetStopProgress(for mode: AppMode) {
        if mode == .jump {
            jumpIndex = 0
            jumpReversed = false
        } else if routeStopCursors[mode] != nil {
            routeStopCursors[mode] = nil
        }
    }

    /// Whether `mode`'s stop progress survives the stops changing from `old` to `new`.
    /// Only appending stops keeps it (owner rule 2026-11-03: the next Move continues to
    /// the next unreached stop, which may be the new one); a remove, move, insert,
    /// reverse or import starts over. Two-Spot runs its first two stops, so it keeps
    /// progress only when those were already set: with one spot it began at the held
    /// location, and a second spot changes the run's stops.
    static func keepsStopProgress(_ mode: AppMode, from old: [LocationCoordinate], to new: [LocationCoordinate]) -> Bool {
        guard !old.isEmpty, new.count > old.count, Array(new.prefix(old.count)) == old else { return false }
        return mode == .twospot ? old.filter(\.isValid).count >= 2 : true
    }

    /// The shown mode's stops changed: reset its progress unless the change keeps it.
    /// Other modes' stops did not change, so their progress stays.
    private func applyStopEdit(from old: [LocationCoordinate], to new: [LocationCoordinate]) {
        guard Self.stopModes.contains(stopsMode), !Self.keepsStopProgress(stopsMode, from: old, to: new) else { return }
        resetStopProgress(for: stopsMode)
    }

    // MARK: Per-mode Stops

    /// The stops of `mode`, shown or not.
    func stops(for mode: AppMode) -> [LocationCoordinate] {
        if mode == stopsMode { return currentRoute }
        return mode == .joystick ? [] : stopSlots[mode]?.stops ?? []
    }

    /// Shows `mode`'s stops: the GUI's mode change. Each mode keeps its own stops, so a
    /// round trip through other modes keeps a stop mode's stops and progress (owner rule
    /// 2026-11-03; the shared list used to be truncated to the new mode's stop limit,
    /// which reset every stop mode). A mode's first visit starts from the stops being
    /// left, as many as it holds (the old truncation), at stop 1. Joystick has no stops;
    /// Settings keeps the current mode's.
    /// - Returns: whether `mode` was seeded (its progress was reset).
    @discardableResult
    func switchStops(to mode: AppMode) -> Bool {
        guard mode != stopsMode, mode != .settings else { return false }
        if stopsMode != .joystick {
            stopSlots[stopsMode] = StopSlot(stops: currentRoute, name: routeName)
        }
        let seeded = mode != .joystick && stopSlots[mode] == nil
        let slot = mode == .joystick
            ? StopSlot(stops: [], name: nil)
            : stopSlots[mode] ?? StopSlot(stops: Array(currentRoute.prefix(mode.maxStops)), name: nil)
        stopsMode = mode
        stopListChange = .modeSwitch
        currentRoute = slot.stops
        stopListChange = .edit
        routeName = slot.name
        progress = 0
        currentIndex = 0
        totalDistance = Geo.totalDistance(of: slot.stops)
        estimatedRemainingTime = 0
        playbackState = slot.stops.isEmpty ? .idle : .ready
        if seeded { resetStopProgress(for: mode) }
        return seeded
    }

    /// Set the simulation state manager reference
    func setSimulationStateManager(_ manager: SimulationStateManager) {
        self.simulationStateManager = manager
    }

    // MARK: Route Loading

    /// Load a route from coordinates
    func loadRoute(from coordinates: [LocationCoordinate], name: String? = nil) {
        guard !coordinates.isEmpty else {
            playbackState = .error("Empty route")
            return
        }

        currentRoute = coordinates
        routeName = name
        progress = 0
        currentIndex = 0
        playbackState = .ready
        totalDistance = Geo.totalDistance(of: coordinates)
    }

    /// Load a route from GPX data.
    ///
    /// Uses `allCoordinates`, which spans tracks *and* routes. An earlier version read only
    /// track segments and silently dropped `<rte>` data.
    func loadRoute(from gpxData: Data, name: String? = nil) throws {
        playbackState = .loading

        do {
            let parsed = try GPXParser().parse(data: gpxData)
            let coordinates = parsed.allCoordinates

            if coordinates.isEmpty {
                playbackState = .error("No coordinates in GPX file")
                return
            }

            loadRoute(from: coordinates, name: name ?? parsed.name)
        } catch {
            playbackState = .error(error.localizedDescription)
            throw error
        }
    }

    /// Import a route from a GPX file on disk.
    /// - Returns: the number of coordinates imported.
    @discardableResult
    func importRoute(from url: URL) throws -> Int {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let coordinates = try GPXParser().parse(fileURL: url).allCoordinates
        guard coordinates.count >= 2 else {
            throw RouteLibraryError.emptyRoute
        }

        loadRoute(from: coordinates)
        return coordinates.count
    }

    /// Load a route from the library by ID
    func loadRoute(withId id: UUID) {
        playbackState = .loading

        if let savedRoute = routeLibrary.routes.first(where: { $0.id == id }) {
            loadRoute(from: savedRoute.coordinates, name: savedRoute.name)
        } else {
            playbackState = .error("Route not found")
        }
    }

    /// Clear the current route (Reset Route): the shown mode's stops, and its progress.
    func clearRoute() {
        stopPlayback()
        currentRoute = []
        routeName = nil
        progress = 0
        currentIndex = 0
        resetStopProgress(for: stopsMode)
        totalDistance = 0
        estimatedRemainingTime = 0
        playbackState = .idle
    }

    // MARK: Waypoint Editing

    /// Append a waypoint. Invalid coordinates are ignored.
    /// - Returns: whether the waypoint was added.
    @discardableResult
    func addWaypoint(_ coordinate: LocationCoordinate) -> Bool {
        guard coordinate.isValid else { return false }
        currentRoute.append(coordinate)
        progress = 0
        totalDistance = Geo.totalDistance(of: currentRoute)
        if playbackState == .idle {
            playbackState = .ready
        }
        return true
    }

    /// Remove the waypoint at an index, if it exists.
    @discardableResult
    func removeWaypoint(at index: Int) -> Bool {
        guard currentRoute.indices.contains(index) else { return false }
        currentRoute.remove(at: index)
        progress = 0
        totalDistance = Geo.totalDistance(of: currentRoute)
        return true
    }

    /// Reorder a waypoint.
    func moveWaypoint(from source: Int, to destination: Int) {
        guard currentRoute.indices.contains(source) else { return }
        let item = currentRoute.remove(at: source)
        let clamped = min(max(destination, 0), currentRoute.count)
        currentRoute.insert(item, at: clamped)
        totalDistance = Geo.totalDistance(of: currentRoute)
    }

    /// Remove the last waypoint.
    /// - Returns: the number of waypoints remaining, or nil if there was nothing to remove.
    @discardableResult
    func removeLastWaypoint() -> Int? {
        guard !currentRoute.isEmpty else { return nil }
        currentRoute.removeLast()
        progress = 0
        totalDistance = Geo.totalDistance(of: currentRoute)
        return currentRoute.count
    }

    /// Reverse the route direction without modifying stageLocation or cardinality.
    /// Resets playback progress and index.
    func reverseRoute() {
        guard !currentRoute.isEmpty else { return }
        currentRoute.reverse()
        progress = 0
        currentIndex = 0
    }

    // MARK: Playback Position

    /// Pause playback
    func pausePlayback() {
        playbackState = .paused
    }

    /// Resume playback
    func resumePlayback() {
        if playbackState == .paused {
            playbackState = .playing
        }
    }

    /// Stop playback and rewind to the start
    func stopPlayback() {
        currentIndex = 0
        progress = 0

        if isRouteLoaded {
            playbackState = .ready
        } else {
            playbackState = .idle
        }
    }

    /// Skip to a specific waypoint
    func skipToWaypoint(_ index: Int) {
        guard index >= 0 && index < currentRoute.count else { return }
        currentIndex = index
        progress = Double(index) / Double(currentRoute.count)
        updateEstimatedTime()
    }

    /// Skip forward by count waypoints
    func skipForward(_ count: Int = 10) {
        skipToWaypoint(min(currentIndex + count, currentRoute.count - 1))
    }

    /// Skip backward by count waypoints
    func skipBackward(_ count: Int = 10) {
        skipToWaypoint(max(currentIndex - count, 0))
    }

    /// Begin playback without claiming any progress before device acknowledgement.
    func beginAcknowledgedPlayback() {
        currentIndex = 0
        progress = 0
        playbackState = .playing
    }

    /// Advance route truth only after the corresponding device receipt is accepted.
    func acknowledgeWaypoint(at index: Int, totalCount: Int) {
        guard totalCount > 0, index >= 0, index < totalCount else { return }
        currentIndex = index + 1
        progress = Double(currentIndex) / Double(totalCount)
        // A point that lands while paused counts, but playback stays paused.
        if playbackState != .paused { playbackState = .playing }
        updateEstimatedTime()
    }

    /// Complete movement while preserving the acknowledged final coordinate externally.
    func completeAcknowledgedPlayback() {
        currentIndex = currentRoute.count
        progress = currentRoute.isEmpty ? 0 : 1
        playbackState = .completed
        estimatedRemainingTime = 0
    }

    // MARK: Private Helpers

    private func updateEstimatedTime() {
        guard let simState = simulationStateManager else { return }

        let remainingPoints = currentRoute.count - currentIndex
        let intervalPerPoint = simState.simulationSpeed.updateInterval
        estimatedRemainingTime = Double(remainingPoints) * intervalPerPoint
    }
}
