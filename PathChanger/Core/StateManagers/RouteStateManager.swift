//
//  RouteStateManager.swift
//  PathChanger
//
//  Domain-specific state manager for route-related state.
//  Part of AppState decomposition (ARCH-002).
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

/// Manages route-related state including loading, playback, and progress.
///
/// `RouteStateManager` is responsible for:
/// - Loading and parsing routes
/// - Controlling route playback
/// - Tracking playback progress
/// - Managing route library
///
/// ## Thread Safety
///
/// This class is marked `@MainActor` for safe SwiftUI integration.
/// All published properties update on the main thread.
///
/// ## Usage
///
/// ```swift
/// @StateObject private var routeState = RouteStateManager()
///
/// // Load a route
/// routeState.loadRoute(from: coordinates)
///
/// // Start playback
/// Task {
///     await routeState.startPlayback()
/// }
/// ```
@MainActor
class RouteStateManager: ObservableObject {

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

    // MARK: Dependencies

    let routeLibrary: RouteLibraryManager
    weak var simulationStateManager: SimulationStateManager?

    // MARK: Private Properties

    private var playbackTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Computed Properties

    /// Whether route is loaded and ready
    var isRouteLoaded: Bool {
        !currentRoute.isEmpty
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

        // Calculate total distance
        totalDistance = calculateTotalDistance(coordinates)
    }

    /// Load a route from GPX data
    func loadRoute(from gpxData: Data, name: String? = nil) async throws {
        playbackState = .loading

        do {
            let parser = GPXParser()
            let parsed = try parser.parse(data: gpxData)

            let coordinates = parsed.tracks.flatMap { $0.segments.flatMap { $0.points.map { $0.coordinate } } }

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
        totalDistance = 0
        estimatedRemainingTime = 0
        playbackState = .idle
    }

    // MARK: Playback Control

    /// Start route playback
    func startPlayback() async {
        guard canStartPlayback else { return }
        guard let simState = simulationStateManager else {
            playbackState = .error("Simulation not available")
            return
        }

        playbackState = .playing

        playbackTask = Task {
            var index = currentIndex
            let total = currentRoute.count

            while index < total && !Task.isCancelled {
                // Handle pause state
                while playbackState == .paused && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }

                if Task.isCancelled { break }

                // Update location
                let coordinate = currentRoute[index]
                await simState.setLocation(coordinate)

                // Update progress
                currentIndex = index
                progress = Double(index + 1) / Double(total)
                updateEstimatedTime()

                index += 1

                // Wait based on speed
                let interval = simState.simulationSpeed.updateInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }

            if !Task.isCancelled {
                if loopEnabled && index >= total {
                    // Restart from beginning
                    if reverseOnLoop {
                        currentRoute.reverse()
                    }
                    currentIndex = 0
                    progress = 0
                    await startPlayback()
                } else {
                    playbackState = .completed
                }
            }
        }
    }

    /// Pause playback
    func pausePlayback() {
        playbackState = .paused
    }

    /// Resume playback
    func resumePlayback() async {
        if playbackState == .paused {
            playbackState = .playing
        }
    }

    /// Stop playback
    func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
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

    // MARK: Private Helpers

    private func calculateTotalDistance(_ coordinates: [LocationCoordinate]) -> Double {
        guard coordinates.count > 1 else { return 0 }

        var total: Double = 0
        for coordinateIndex in 1..<coordinates.count {
            total += coordinates[coordinateIndex - 1].distance(to: coordinates[coordinateIndex])
        }
        return total
    }

    private func updateEstimatedTime() {
        guard let simState = simulationStateManager else { return }

        let remainingPoints = currentRoute.count - currentIndex
        let intervalPerPoint = simState.simulationSpeed.updateInterval
        estimatedRemainingTime = Double(remainingPoints) * intervalPerPoint
    }
}

// MARK: - LocationCoordinate Distance Extension

private extension LocationCoordinate {
    /// Calculate distance to another coordinate in meters using Haversine formula
    func distance(to other: LocationCoordinate) -> Double {
        let earthRadius: Double = 6_371_000 // meters

        let lat1 = self.latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - self.latitude) * .pi / 180
        let deltaLon = (other.longitude - self.longitude) * .pi / 180

        let haversineTerm = sin(deltaLat / 2) * sin(deltaLat / 2) +
            cos(lat1) * cos(lat2) *
            sin(deltaLon / 2) * sin(deltaLon / 2)
        let angularDistance = 2 * atan2(sqrt(haversineTerm), sqrt(1 - haversineTerm))

        return earthRadius * angularDistance
    }
}
