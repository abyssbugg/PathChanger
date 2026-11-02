//
//  RoadRouter.swift
//  PathChanger
//
//  Real-road paths for travelled legs (PRODUCT_REQUIREMENTS §3.6, owner decision 2026-11-02).
//  Paths come from Apple Maps directions; when no road route is available the leg is a
//  straight line and the route carries a short note for the GUI. Routing never throws.
//

import Foundation
import MapKit

/// One travelled leg: the path to follow, its length, and whether it follows roads.
struct RoadRoute: Equatable, Sendable {
    /// The path, starting exactly at the leg's start and ending exactly at its end.
    let points: [LocationCoordinate]
    /// Road distance from Apple Maps, or the straight-line distance for a straight leg.
    let distanceMeters: Double
    /// `true` only when the path came from a road route.
    let followsRoads: Bool
    /// Plain text for the GUI, e.g. why the leg is a straight line. `nil` when nothing to say.
    let note: String?
}

/// Supplies the path for one travelled leg. Never fails: a missing road route is a straight line.
protocol RoadRouting: Sendable {
    func route(from: LocationCoordinate, to: LocationCoordinate, travel: SimulationSpeed) async -> RoadRoute
}

/// Apple Maps directions transport used for a travel mode.
enum RoadTransport: String, Sendable, Hashable {
    case walking
    case cycling
    case automobile

    /// Walking and Cycling use their own directions; Riding (`.fast`), Driving and every
    /// other speed use automobile directions.
    init(travel: SimulationSpeed) {
        switch travel {
        case .walking: self = .walking
        case .cycling: self = .cycling
        case .fast, .driving, .running, .teleport: self = .automobile
        }
    }

    var mapKitTransportType: MKDirectionsTransportType {
        switch self {
        case .walking: return .walking
        case .cycling: return .cycling
        case .automobile: return .automobile
        }
    }
}

/// Routes legs along roads with `MKDirections`, with a per-request timeout and an in-memory cache.
actor MapKitRoadRouter: RoadRouting {
    /// Fetches a road path. Injected so tests never reach the network; the default asks Apple Maps.
    typealias DirectionsFunction = @Sendable (
        LocationCoordinate, LocationCoordinate, RoadTransport
    ) async throws -> (coordinates: [LocationCoordinate], distance: Double)

    static let straightLineNote = "No road route found; travelling in a straight line"
    static let longRouteNote = "Road route is over 500 km long"
    static let detourNote = "Road route is more than 4 times the straight-line distance"

    /// Endpoints closer than this are the same place: no request, a 2-point path.
    static let samePlaceMeters = 1.0
    static let longRouteMeters = 500_000.0
    static let detourFactor = 4.0

    private struct CacheKey: Hashable {
        let fromLatitude: Int64
        let fromLongitude: Int64
        let toLatitude: Int64
        let toLongitude: Int64
        let transport: RoadTransport

        /// Endpoints rounded to 1e-5° (about 1.1 m).
        init(from: LocationCoordinate, to: LocationCoordinate, transport: RoadTransport) {
            func rounded(_ degrees: Double) -> Int64 { Int64((degrees * 100_000).rounded()) }
            fromLatitude = rounded(from.latitude)
            fromLongitude = rounded(from.longitude)
            toLatitude = rounded(to.latitude)
            toLongitude = rounded(to.longitude)
            self.transport = transport
        }
    }

    /// A validated road path as Apple Maps returned it, before pinning to exact endpoints.
    private struct RoadPath {
        let coordinates: [LocationCoordinate]
        let distance: Double
    }

    private let timeout: TimeInterval
    private let cacheCapacity: Int
    private let failureRetryInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let directions: DirectionsFunction
    private var cache: [CacheKey: RoadPath] = [:]
    /// Least recently used first.
    private var cacheOrder: [CacheKey] = []
    /// Legs that failed or timed out, and when. A remembered leg falls back at once
    /// instead of waiting for Apple Maps again (a looping run offline would otherwise
    /// wait the full timeout on every leg) and does not add to MapKit throttling.
    private var failures: [CacheKey: Date] = [:]

    init(
        timeout: TimeInterval = 10,
        cacheCapacity: Int = 64,
        failureRetryInterval: TimeInterval = 120,
        now: @escaping @Sendable () -> Date = { Date() },
        directions: @escaping DirectionsFunction = MapKitRoadRouter.appleMapsDirections
    ) {
        self.timeout = timeout
        self.cacheCapacity = max(0, cacheCapacity)
        self.failureRetryInterval = max(0, failureRetryInterval)
        self.now = now
        self.directions = directions
    }

    func route(from: LocationCoordinate, to: LocationCoordinate, travel: SimulationSpeed) async -> RoadRoute {
        guard from.isValid, to.isValid else {
            return fallback(from: from, to: to, reason: "invalid endpoint")
        }
        let straightDistance = Geo.distance(from: from, to: to)
        if straightDistance < Self.samePlaceMeters {
            return RoadRoute(points: [from, to], distanceMeters: straightDistance, followsRoads: false, note: nil)
        }

        let transport = RoadTransport(travel: travel)
        let key = CacheKey(from: from, to: to, transport: transport)
        if let cached = cachedPath(for: key) {
            return roadRoute(cached, from: from, to: to, straightDistance: straightDistance)
        }
        if recentlyFailed(key) {
            return RoadRoute(points: [from, to], distanceMeters: straightDistance, followsRoads: false, note: Self.straightLineNote)
        }

        switch await requestWithTimeout(from: from, to: to, transport: transport) {
        case .path(let coordinates, let distance):
            guard let path = Self.validated(coordinates: coordinates, distance: distance) else {
                rememberFailure(key)
                return fallback(from: from, to: to, reason: "invalid road path (\(coordinates.count) points)", transport: transport)
            }
            failures.removeValue(forKey: key)
            store(path, for: key)
            return roadRoute(path, from: from, to: to, straightDistance: straightDistance)
        case .failed(let reason):
            rememberFailure(key)
            return fallback(from: from, to: to, reason: reason, transport: transport)
        case .timedOut:
            rememberFailure(key)
            return fallback(from: from, to: to, reason: "timed out after \(timeout) s", transport: transport)
        case .cancelled:
            // The run was stopped; that says nothing about the leg, so it is not remembered.
            return fallback(from: from, to: to, reason: "cancelled", transport: transport)
        }
    }

    // MARK: - Building routes

    private func roadRoute(
        _ path: RoadPath,
        from: LocationCoordinate,
        to: LocationCoordinate,
        straightDistance: Double
    ) -> RoadRoute {
        var points = path.coordinates
        if let first = points.first, Geo.distance(from: first, to: from) < Self.samePlaceMeters {
            points[0] = from
        } else {
            points.insert(from, at: 0)
        }
        if points.count > 1, let last = points.last, Geo.distance(from: last, to: to) < Self.samePlaceMeters {
            points[points.count - 1] = to
        } else {
            points.append(to)
        }

        let note: String?
        if path.distance > Self.longRouteMeters {
            note = Self.longRouteNote
        } else if path.distance > straightDistance * Self.detourFactor {
            note = Self.detourNote
        } else {
            note = nil
        }
        return RoadRoute(points: points, distanceMeters: path.distance, followsRoads: true, note: note)
    }

    /// Logged once per leg that falls back. No coordinates or device identifiers.
    private func fallback(
        from: LocationCoordinate,
        to: LocationCoordinate,
        reason: String,
        transport: RoadTransport? = nil
    ) -> RoadRoute {
        let valid = from.isValid && to.isValid
        let distance = valid ? Geo.distance(from: from, to: to) : 0
        let transportText = transport.map { " (\($0.rawValue))" } ?? ""
        Logger.info(
            "Road route unavailable\(transportText): \(reason); travelling a \(Int(distance.rounded())) m leg in a straight line",
            category: .general
        )
        return RoadRoute(points: [from, to], distanceMeters: distance, followsRoads: false, note: Self.straightLineNote)
    }

    private static func validated(coordinates: [LocationCoordinate], distance: Double) -> RoadPath? {
        guard !coordinates.isEmpty,
              coordinates.allSatisfy(\.isValid),
              distance.isFinite, distance >= 0 else {
            return nil
        }
        return RoadPath(coordinates: coordinates, distance: distance)
    }

    // MARK: - Cache (least recently used eviction)

    private func cachedPath(for key: CacheKey) -> RoadPath? {
        guard let path = cache[key] else { return nil }
        touch(key)
        return path
    }

    private func store(_ path: RoadPath, for key: CacheKey) {
        guard cacheCapacity > 0 else { return }
        cache[key] = path
        touch(key)
        while cacheOrder.count > cacheCapacity {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    private func touch(_ key: CacheKey) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    // MARK: - Remembered failures

    private func recentlyFailed(_ key: CacheKey) -> Bool {
        guard let failedAt = failures[key] else { return false }
        if now().timeIntervalSince(failedAt) < failureRetryInterval { return true }
        failures.removeValue(forKey: key)
        return false
    }

    private func rememberFailure(_ key: CacheKey) {
        guard failureRetryInterval > 0, cacheCapacity > 0 else { return }
        let current = now()
        failures = failures.filter { current.timeIntervalSince($0.value) < failureRetryInterval }
        failures[key] = current
        while failures.count > cacheCapacity,
              let oldest = failures.min(by: { $0.value < $1.value })?.key {
            failures.removeValue(forKey: oldest)
        }
    }

    // MARK: - Bounded request

    private enum RequestOutcome: Sendable {
        case path([LocationCoordinate], Double)
        case failed(String)
        case timedOut
        case cancelled
    }

    /// Runs the directions request, racing it against the timeout. Whichever finishes first
    /// decides the outcome and cancels the other, so the wait is bounded even when the
    /// request ignores cancellation.
    private func requestWithTimeout(
        from: LocationCoordinate,
        to: LocationCoordinate,
        transport: RoadTransport
    ) async -> RequestOutcome {
        let directions = self.directions
        let timeoutNanoseconds = UInt64(max(0, timeout) * 1_000_000_000)
        let gate = RequestGate<RequestOutcome>()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.install(continuation)
                gate.track(Task {
                    do {
                        let result = try await directions(from, to, transport)
                        gate.finish(.path(result.coordinates, result.distance))
                    } catch is CancellationError {
                        gate.finish(.cancelled)
                    } catch {
                        gate.finish(.failed("directions error \(type(of: error))"))
                    }
                })
                gate.track(Task {
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    gate.finish(.timedOut)
                })
            }
        } onCancel: {
            gate.finish(.cancelled)
        }
    }

    // MARK: - Apple Maps

    /// The live directions call. Cancelling the calling task cancels the `MKDirections` request.
    static let appleMapsDirections: DirectionsFunction = { from, to, transport in
        let request = MKDirections.Request()
        request.source = mapItem(at: from)
        request.destination = mapItem(at: to)
        request.transportType = transport.mapKitTransportType
        request.requestsAlternateRoutes = false

        let directions = UncheckedBox(MKDirections(request: request))
        let response = try await withTaskCancellationHandler {
            try await directions.value.calculate()
        } onCancel: {
            directions.value.cancel()
        }

        guard let route = response.routes.first else {
            throw RoadRouterError.noRoute
        }
        let polyline = route.polyline
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        return (coordinates.map(LocationCoordinate.init(from:)), route.distance)
    }

    private static func mapItem(at coordinate: LocationCoordinate) -> MKMapItem {
        if #available(macOS 26.0, *) {
            return MKMapItem(
                location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                address: nil
            )
        }
        return MKMapItem(placemark: MKPlacemark(coordinate: coordinate.clLocationCoordinate2D))
    }
}

enum RoadRouterError: Error {
    case noRoute
}

/// Resumes a continuation exactly once with the first outcome and cancels the tracked tasks.
private final class RequestGate<Outcome: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var outcome: Outcome?
    private var tasks: [Task<Void, Never>] = []

    func install(_ continuation: CheckedContinuation<Outcome, Never>) {
        lock.lock()
        if let outcome {
            lock.unlock()
            continuation.resume(returning: outcome)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func track(_ task: Task<Void, Never>) {
        lock.lock()
        if outcome != nil {
            lock.unlock()
            task.cancel()
        } else {
            tasks.append(task)
            lock.unlock()
        }
    }

    func finish(_ outcome: Outcome) {
        lock.lock()
        guard self.outcome == nil else {
            lock.unlock()
            return
        }
        self.outcome = outcome
        let continuation = self.continuation
        self.continuation = nil
        let tasks = self.tasks
        self.tasks = []
        lock.unlock()

        tasks.forEach { $0.cancel() }
        continuation?.resume(returning: outcome)
    }
}

/// Carries a non-Sendable MapKit object into a cancellation handler. `MKDirections.cancel()`
/// is documented as safe to call while a request is in flight.
private final class UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
