//
//  TravelTrail.swift
//  PathChanger
//
//  The acknowledged positions a stop mode travelled through, for the map (owner ask
//  2026-11-03). Fed from acknowledged receipts only (PRODUCT_REQUIREMENTS 4). It belongs
//  to one mode and lasts as long as that mode's stop progress: every Move of the
//  sequence extends it; a stop edit (not an append), Reset Route or a confirmed Clear
//  erases it, and another mode's travel starts a new one.
//

import Foundation

@MainActor
final class TravelTrail: ObservableObject {
    /// Most points kept; past it the trail is halved, keeping its first and newest point.
    static let capacity = 2_000

    @Published private(set) var points: [LocationCoordinate] = []
    /// The stop mode whose travel drew `points`; nil when there is no trail.
    private(set) var mode: AppMode?

    /// Adds an acknowledged point `mode` travelled through; a point of another mode
    /// starts a new trail.
    func record(_ coordinate: LocationCoordinate, mode: AppMode) {
        guard coordinate.isValid else { return }
        if self.mode != mode {
            self.mode = mode
            points = []
        }
        points = Self.appending(coordinate, to: points, capacity: Self.capacity)
    }

    func reset() {
        mode = nil
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
