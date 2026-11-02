//
//  PlaceNameResolver.swift
//  PathChanger
//
//  The place or street name of the spoofed location, shown next to its coordinates
//  (PRODUCT_REQUIREMENTS 3.5, owner decision 2026-11-02). Lookups are throttled,
//  cached, and never block anything; a miss shows nothing rather than a wrong place.
//

import CoreLocation
import Foundation

/// The parts of a reverse-geocoded place the GUI can show. Independent of
/// `CLPlacemark` so the formatting and the resolver are testable without the network.
struct PlaceDescription: Equatable, Sendable {
    var name: String? = nil
    var subThoroughfare: String? = nil
    var thoroughfare: String? = nil
    var locality: String? = nil
    var administrativeArea: String? = nil
}

/// Why a lookup gave no place. Logged by kind only, never with the coordinate.
enum ReverseGeocodingError: Error, Equatable, Sendable {
    case network
    case throttled
    case noResult
    case cancelled
    case other
}

protocol ReverseGeocoding: Sendable {
    func reverseGeocode(_ coordinate: LocationCoordinate) async throws -> PlaceDescription
}

enum PlaceNameFormatter {
    /// "107 Forest Retreat Rd, Hendersonville" when a street is known, else the place
    /// name and its town or region, e.g. "Central Park, New York". Nil when nothing is usable.
    static func name(for place: PlaceDescription) -> String? {
        let street = [place.subThoroughfare, place.thoroughfare].compactMap(cleaned).joined(separator: " ")
        let parts: [String?] = cleaned(place.thoroughfare) != nil
            ? [street, cleaned(place.locality) ?? place.administrativeArea]
            : [place.name, place.locality, place.administrativeArea]

        var shown: [String] = []
        for part in parts.compactMap(cleaned) where !shown.contains(part) && shown.count < 2 {
            shown.append(part)
        }
        return shown.isEmpty ? nil : shown.joined(separator: ", ")
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Looks up the name of the applied (spoofed) coordinate.
///
/// - At most one request starts per `minimumInterval`; a point that arrives sooner waits
///   for the rest of the interval, and only the newest such point is looked up.
/// - A point within `minimumDistance` of the last looked-up point needs no new request.
/// - A newer point supersedes an in-flight lookup; its result is dropped.
/// - Names are cached by coordinate rounded to 1e-4° (about 11 m), least recently used out.
/// - A shown name stays only while the current point is within `fallbackRadius` of the
///   point it was found for; otherwise nothing is shown until a lookup succeeds.
@MainActor
final class PlaceNameResolver: ObservableObject {
    @Published private(set) var placeName: String?

    /// The lookup waiting for its turn or running, if any. Read by tests to await it.
    private(set) var pendingLookup: Task<Void, Never>?

    private let geocoder: any ReverseGeocoding
    private let minimumInterval: TimeInterval
    private let minimumDistance: Double
    private let fallbackRadius: Double
    private let cacheLimit: Int
    private let now: @MainActor () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void

    /// The point the latest lookup is for (requested, waiting, or answered).
    private var target: LocationCoordinate?
    /// The point the shown name was found for.
    private var namedPoint: LocationCoordinate?
    private var lastRequestStart: Date?
    private var cache: [CacheKey: String] = [:]
    private var cacheOrder: [CacheKey] = []

    private struct CacheKey: Hashable {
        let latitude: Int
        let longitude: Int

        init(_ coordinate: LocationCoordinate) {
            latitude = Int((coordinate.latitude * 10_000).rounded())
            longitude = Int((coordinate.longitude * 10_000).rounded())
        }
    }

    init(
        geocoder: any ReverseGeocoding,
        minimumInterval: TimeInterval = 4,
        minimumDistance: Double = 30,
        fallbackRadius: Double = 200,
        cacheLimit: Int = 64,
        now: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.geocoder = geocoder
        self.minimumInterval = minimumInterval
        self.minimumDistance = minimumDistance
        self.fallbackRadius = fallbackRadius
        self.cacheLimit = max(1, cacheLimit)
        self.now = now
        self.sleep = sleep
    }

    /// Call with the applied coordinate whenever it changes; nil when nothing is applied.
    func update(for coordinate: LocationCoordinate?) {
        guard let coordinate else {
            cancelPendingLookup()
            target = nil
            show(nil, for: nil)
            return
        }

        if let cached = cachedName(for: coordinate) {
            cancelPendingLookup()
            target = coordinate
            show(cached, for: coordinate)
            return
        }

        hideNameIfFar(from: coordinate)
        if let target, Geo.distance(from: target, to: coordinate) < minimumDistance { return }

        cancelPendingLookup()
        target = coordinate
        let wait = lastRequestStart.map { max(0, minimumInterval - now().timeIntervalSince($0)) } ?? 0
        pendingLookup = Task { [weak self] in
            await self?.lookUp(coordinate, after: wait)
        }
    }

    private func lookUp(_ coordinate: LocationCoordinate, after wait: TimeInterval) async {
        if wait > 0 {
            guard !Task.isCancelled else { return }
            await sleep(wait)
        }
        guard !Task.isCancelled, target == coordinate else { return }
        lastRequestStart = now()

        let result: Result<String, ReverseGeocodingError>
        do {
            let place = try await geocoder.reverseGeocode(coordinate)
            if let name = PlaceNameFormatter.name(for: place) {
                result = .success(name)
            } else {
                result = .failure(.noResult)
            }
        } catch let error as ReverseGeocodingError {
            result = .failure(error)
        } catch is CancellationError {
            result = .failure(.cancelled)
        } catch {
            result = .failure(.other)
        }

        if case .success(let name) = result { remember(name, for: coordinate) }
        // Newest wins: a cleared or superseded lookup changes nothing on screen.
        guard !Task.isCancelled, target == coordinate else { return }

        switch result {
        case .success(let name):
            show(name, for: coordinate)
        case .failure(let kind):
            // Let the next update try this point again (still throttled).
            target = nil
            hideNameIfFar(from: coordinate)
            if kind != .cancelled {
                Logger.debug("Place name lookup failed: \(kind)", category: .map)
            }
        }
    }

    private func cancelPendingLookup() {
        pendingLookup?.cancel()
        pendingLookup = nil
    }

    private func show(_ name: String?, for point: LocationCoordinate?) {
        namedPoint = name == nil ? nil : point
        if placeName != name { placeName = name }
    }

    private func hideNameIfFar(from coordinate: LocationCoordinate) {
        guard let namedPoint, Geo.distance(from: namedPoint, to: coordinate) > fallbackRadius else { return }
        show(nil, for: nil)
    }

    private func cachedName(for coordinate: LocationCoordinate) -> String? {
        let key = CacheKey(coordinate)
        guard let name = cache[key] else { return nil }
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        return name
    }

    private func remember(_ name: String, for coordinate: LocationCoordinate) {
        let key = CacheKey(coordinate)
        cache[key] = name
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > cacheLimit {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }
}

/// Apple's reverse geocoder. The only place `CLGeocoder` is used, so moving to
/// `MKReverseGeocodingRequest` (macOS 26+) later is a one-file change.
struct CLGeocoderReverseGeocoder: ReverseGeocoding {
    func reverseGeocode(_ coordinate: LocationCoordinate) async throws -> PlaceDescription {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks: [CLPlacemark]
        do {
            placemarks = try await withTaskCancellationHandler {
                try await geocoder.reverseGeocodeLocation(location)
            } onCancel: {
                geocoder.cancelGeocode()
            }
        } catch let error as CLError {
            switch error.code {
            case .network: throw ReverseGeocodingError.network
            case .geocodeFoundNoResult, .geocodeFoundPartialResult: throw ReverseGeocodingError.noResult
            case .geocodeCanceled: throw ReverseGeocodingError.cancelled
            default: throw ReverseGeocodingError.other
            }
        } catch {
            throw Task.isCancelled ? ReverseGeocodingError.cancelled : ReverseGeocodingError.other
        }
        guard let placemark = placemarks.first else { throw ReverseGeocodingError.noResult }
        return PlaceDescription(
            name: placemark.name,
            subThoroughfare: placemark.subThoroughfare,
            thoroughfare: placemark.thoroughfare,
            locality: placemark.locality,
            administrativeArea: placemark.administrativeArea
        )
    }
}
