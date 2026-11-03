//
//  TravelTrail.swift
//  PathChanger
//
//  The acknowledged positions of the current (or last) travelled stop run, for the map
//  (owner ask 2026-11-03). Fed from acknowledged receipts only (PRODUCT_REQUIREMENTS 4);
//  erased by Clear and by editing the stops.
//

import Foundation

@MainActor
final class TravelTrail: ObservableObject {
    /// Most points kept; past it the trail is halved, keeping its first and newest point.
    static let capacity = 2_000

    @Published private(set) var points: [LocationCoordinate] = []
    private var runID: UUID?

    /// Adds an acknowledged point of `run`; a point of a new run starts a new trail.
    func record(_ coordinate: LocationCoordinate, run: UUID) {
        guard coordinate.isValid else { return }
        if runID != run {
            runID = run
            points = []
        }
        points = Self.appending(coordinate, to: points, capacity: Self.capacity)
    }

    func reset() {
        runID = nil
        if !points.isEmpty { points = [] }
    }

    /// `points` with `coordinate` added (not when it repeats the last point), halved
    /// when it would pass `capacity`.
    nonisolated static func appending(
        _ coordinate: LocationCoordinate,
        to points: [LocationCoordinate],
        capacity: Int
    ) -> [LocationCoordinate] {
        guard points.last != coordinate else { return points }
        var result = points
        result.append(coordinate)
        if result.count > max(capacity, 2) { result = downsampled(result) }
        return result
    }

    /// Every other point, from the first, plus the last point.
    nonisolated static func downsampled(_ points: [LocationCoordinate]) -> [LocationCoordinate] {
        guard points.count > 2 else { return points }
        var result = stride(from: 0, to: points.count, by: 2).map { points[$0] }
        if let last = points.last, result.last != last { result.append(last) }
        return result
    }
}
