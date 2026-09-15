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

    /// Current route coordinates
    @Published var currentRoute: [LocationCoordinate] = []

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
    @Published var jumpIndex: Int = 0

    /// Whether Jump mode advances automatically
    @Published var autoJump: Bool = false

    // MARK: Dependencies

    let routeLibrary: RouteLibraryManager
    weak var simulationStateManager: SimulationStateManager?

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

    init(routeLibrary: RouteLibraryManager) {
        self.routeLibrary = routeLibrary
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

    /// Clear the current route
    func clearRoute() {
        stopPlayback()
        currentRoute = []
        routeName = nil
        progress = 0
        currentIndex = 0
        jumpIndex = 0
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
        playbackState = .playing
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
