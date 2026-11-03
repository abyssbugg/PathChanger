//
//  RoutePreview.swift
//  PathChanger
//
//  The planned route the map draws for Jump, Two-Spot and Multi-Spot (owner ask
//  2026-11-03, PRODUCT_REQUIREMENTS 3.6). With Getting there = Travel each leg shows the
//  road path from the same router and directions the run uses, so the run's own legs hit
//  the router's cache. With Getting there = Jump the legs are thin dashed connectors.
//

import Foundation

/// What the preview depends on. A new key is the only thing that refetches.
struct RoutePreviewKey: Equatable, Sendable {
    /// The run's stops, in order (valid stops only).
    let stops: [LocationCoordinate]
    /// The Apple Maps directions the run asks for.
    let transport: RoadTransport
    let arrival: StopTravelSettings.Arrival
    let repeatMode: StopTravelSettings.RepeatMode
    /// The leg the next Move drives first: the held location to the next stop not yet
    /// reached (a finished One way run starts over at stop 1). Nil with nothing held
    /// (the stop is placed), at that stop, or while the run is moving.
    var nextMoveLeg: RoutePreviewLegSpec? = nil
}

/// One drawn leg, before its path is known.
struct RoutePreviewLegSpec: Equatable, Sendable {
    let from: LocationCoordinate
    let to: LocationCoordinate
    /// The Loop leg from the last stop back to the first.
    let returnsToStart: Bool
}

/// How a leg is drawn.
enum RoutePreviewLegStyle: Equatable, Sendable {
    /// Solid: the road path Apple Maps returned.
    case road
    /// Dashed: no road route, the run travels this leg in a straight line.
    case straight
    /// Faint dotted: the road path is not known yet.
    case loading
    /// Thin dashed: Getting there = Jump teleports, no path is travelled.
    case jump
}

enum RoutePreviewPlanner {
    /// The preview of `mode`'s run, or nil when there is nothing to draw. Mirrors
    /// `StopTravelPlanner.runStops`: Two-Spot draws its two endpoints, or the held
    /// location and its one spot; Jump and Multi-Spot draw all their stops. With
    /// `origin` (the held location the next Move leaves from; nil while nothing is held
    /// or the run is moving) it adds the leg the planner's `firstLeg` drives from there
    /// at `cursor`, so Jump with one stop has a preview too.
    static func key(
        mode: AppMode,
        stops: [LocationCoordinate],
        held: LocationCoordinate?,
        settings: StopTravelSettings,
        travel: SimulationSpeed,
        origin: LocationCoordinate? = nil,
        cursor: StopCursor = StopCursor()
    ) -> RoutePreviewKey? {
        var valid = stops.filter(\.isValid)
        switch mode {
        case .twospot:
            if valid.count >= 2 {
                valid = Array(valid.prefix(2))
            } else if let start = held, start.isValid, let destination = valid.first, start != destination {
                valid = [start, destination]
            }
        case .jump, .route:
            break
        case .teleport, .joystick, .settings:
            return nil
        }
        var nextMoveLeg: RoutePreviewLegSpec?
        if mode == .jump || valid.count >= 2, let origin, origin.isValid,
           let leg = StopTravelPlanner.firstLeg(stops: valid, origin: origin, cursor: cursor, settings: settings),
           let from = leg.from {
            nextMoveLeg = RoutePreviewLegSpec(from: from, to: leg.to, returnsToStart: false)
        }
        guard valid.count >= 2 || nextMoveLeg != nil else { return nil }
        return RoutePreviewKey(
            stops: valid,
            transport: RoadTransport(travel: travel),
            arrival: settings.arrival,
            repeatMode: settings.repeatMode,
            nextMoveLeg: nextMoveLeg
        )
    }

    /// The leg the next Move drives (when it is not one of the others), the legs between
    /// consecutive stops, plus the leg back to the first stop when the run loops. Back
    /// and forth returns along the same legs, so only the forward legs are drawn.
    /// Same-place legs are skipped.
    static func legs(for key: RoutePreviewKey) -> [RoutePreviewLegSpec] {
        let stops = key.stops
        var legs: [RoutePreviewLegSpec] = []
        if stops.count >= 2 {
            for index in 1..<stops.count where stops[index - 1] != stops[index] {
                legs.append(RoutePreviewLegSpec(from: stops[index - 1], to: stops[index], returnsToStart: false))
            }
            if key.repeatMode == .loop, let first = stops.first, let last = stops.last, first != last {
                legs.append(RoutePreviewLegSpec(from: last, to: first, returnsToStart: true))
            }
        }
        if let next = key.nextMoveLeg, next.from != next.to,
           !legs.contains(where: { $0.from == next.from && $0.to == next.to }) {
            legs.insert(next, at: 0)
        }
        return legs
    }

    /// A jump is never drawn as a road; a travelled leg is loading until the router
    /// answers, then a road or a straight line.
    static func style(arrival: StopTravelSettings.Arrival, route: RoadRoute?) -> RoutePreviewLegStyle {
        guard arrival == .travel else { return .jump }
        guard let route else { return .loading }
        return route.followsRoads ? .road : .straight
    }

    /// The map footer's one-line key for the lines shown; nil when no leg is drawn.
    static func legendText(for styles: [RoutePreviewLegStyle]) -> String? {
        guard !styles.isEmpty else { return nil }
        if styles.allSatisfy({ $0 == .jump }) { return "Dashed line: jump, not a road" }
        var text = "Solid line: road route · Dashed: straight line"
        if styles.contains(.loading) { text += " · Dotted: finding route" }
        return text
    }
}

extension RoadTransport {
    /// A travel mode that asks for these directions (`RoadTransport(travel:)` maps it back).
    var representativeTravel: SimulationSpeed {
        switch self {
        case .walking: return .walking
        case .cycling: return .cycling
        case .automobile: return .driving
        }
    }
}

/// Fetches and holds the drawn legs. Owned by AppState with the app's road router (nil
/// in tests and previews, so nothing reaches Apple Maps there). Fetches run one leg at a
/// time after a short debounce, never block the UI, and a newer key cancels them.
@MainActor
final class RoutePreviewModel: ObservableObject {
    struct Leg: Equatable, Identifiable {
        let id: Int
        let points: [LocationCoordinate]
        let style: RoutePreviewLegStyle
    }

    private struct ResolvedKey: Hashable {
        let from: LocationCoordinate
        let to: LocationCoordinate
        let transport: RoadTransport
    }

    @Published private(set) var legs: [Leg] = []

    private let router: (any RoadRouting)?
    private let debounceNanoseconds: UInt64
    private let resolvedCapacity: Int
    private var currentKey: RoutePreviewKey?
    private var fetchTask: Task<Void, Never>?
    /// Road paths already drawn, so an edit redraws known legs at once. Only road paths
    /// are kept: the router decides when a failed leg is asked for again.
    private var resolved: [ResolvedKey: RoadRoute] = [:]
    /// Least recently stored first.
    private var resolvedOrder: [ResolvedKey] = []

    init(router: (any RoadRouting)?, debounceNanoseconds: UInt64 = 300_000_000, resolvedCapacity: Int = 128) {
        self.router = router
        self.debounceNanoseconds = debounceNanoseconds
        self.resolvedCapacity = max(0, resolvedCapacity)
    }

    /// Shows `key`'s legs now (known road paths, else loading) and fetches the missing
    /// ones. The same key again does nothing; nil clears the preview.
    func update(_ key: RoutePreviewKey?) {
        guard key != currentKey else { return }
        currentKey = key
        fetchTask?.cancel()
        fetchTask = nil
        guard let key else {
            legs = []
            return
        }

        let specs = RoutePreviewPlanner.legs(for: key)
        legs = specs.enumerated().map { index, spec in
            let route = key.arrival == .travel ? resolved[resolvedKey(spec, key)] : nil
            return Leg(
                id: index,
                points: route?.points ?? [spec.from, spec.to],
                style: RoutePreviewPlanner.style(arrival: key.arrival, route: route)
            )
        }

        let missing = legs.indices.filter { legs[$0].style == .loading }
        guard let router, !missing.isEmpty else { return }
        let debounce = debounceNanoseconds
        fetchTask = Task { [weak self] in
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: debounce)
            }
            for index in missing {
                guard !Task.isCancelled else { return }
                let spec = specs[index]
                let route = await router.route(from: spec.from, to: spec.to, travel: key.transport.representativeTravel)
                // A cancelled request comes back as a straight line: it says nothing.
                guard !Task.isCancelled, let self, self.currentKey == key else { return }
                self.show(route, at: index, spec: spec, key: key)
            }
        }
    }

    /// Waits until no fetch is in flight (tests).
    func settled() async {
        while let task = fetchTask {
            await task.value
            if fetchTask == task { return }
        }
    }

    private func show(_ route: RoadRoute, at index: Int, spec: RoutePreviewLegSpec, key: RoutePreviewKey) {
        guard legs.indices.contains(index) else { return }
        if route.followsRoads { remember(route, for: resolvedKey(spec, key)) }
        legs[index] = Leg(
            id: index,
            points: route.points.count >= 2 ? route.points : [spec.from, spec.to],
            style: RoutePreviewPlanner.style(arrival: key.arrival, route: route)
        )
    }

    private func resolvedKey(_ spec: RoutePreviewLegSpec, _ key: RoutePreviewKey) -> ResolvedKey {
        ResolvedKey(from: spec.from, to: spec.to, transport: key.transport)
    }

    private func remember(_ route: RoadRoute, for key: ResolvedKey) {
        guard resolvedCapacity > 0 else { return }
        if resolved.updateValue(route, forKey: key) != nil {
            resolvedOrder.removeAll { $0 == key }
        }
        resolvedOrder.append(key)
        while resolvedOrder.count > resolvedCapacity {
            resolved.removeValue(forKey: resolvedOrder.removeFirst())
        }
    }
}
