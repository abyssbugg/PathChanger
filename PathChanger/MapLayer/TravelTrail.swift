//
//  TravelTrail.swift
//  PathChanger
//
//  The acknowledged positions each stop mode travelled through, for the map (owner ask
//  2026-11-03). Fed from acknowledged receipts only (PRODUCT_REQUIREMENTS 4). Jump,
//  Two-Spot and Multi-Spot each keep their own trail (owner decision 2026-11-03), which
//  lasts as long as that mode's stop progress: every Move of the sequence extends it; that
//  mode's stop edit (not an append), Reset Route or a load erases it, a confirmed Clear
//  erases every mode's, and travel in one mode never touches another's.
//
//  A trail is a list of lines: travel that leaves from somewhere other than the trail's
//  end (after a Teleport, a Joystick drive or a Jump arrival) starts a new line at the
//  point it left from, so the map never joins two travels with a line the phone did not
//  drive and still draws the first step.
//

import Foundation

@MainActor
final class TravelTrail: ObservableObject {
    /// Most points one mode's trail keeps across its segments; past it each segment is
    /// halved (keeping its first and newest point) and, if that is not enough, the oldest
    /// segments go.
    static let capacity = 2_000

    /// Each stop mode's segments; a mode with no trail has no entry.
    @Published private(set) var segmentsByMode: [AppMode: [[LocationCoordinate]]] = [:]

    /// Adds an acknowledged point `mode` travelled through, reached from `held` (the
    /// location held before it). It extends `mode`'s trail only when `held` is that
    /// trail's end; otherwise it starts a new segment at `held`, so the step the phone
    /// took from there is drawn too. Other modes' trails are untouched.
    func record(_ coordinate: LocationCoordinate, mode: AppMode, after held: LocationCoordinate?) {
        guard coordinate.isValid else { return }
        let segments = segmentsByMode[mode] ?? []
        let startsSegment = held == nil || held != segments.last?.last
        let updated = Self.appending(
            coordinate, to: segments, startsSegment: startsSegment, departure: held, capacity: Self.capacity
        )
        if updated != segments { segmentsByMode[mode] = updated }
    }

    /// The trail the map draws while `mode` is shown: that mode's own travel only.
    func segments(for mode: AppMode) -> [[LocationCoordinate]] {
        segmentsByMode[mode] ?? []
    }

    /// Every point of `mode`'s trail, in order.
    func points(for mode: AppMode) -> [LocationCoordinate] {
        segments(for: mode).flatMap { $0 }
    }

    /// `mode`'s progress reset: its trail goes, the others stay.
    func reset(_ mode: AppMode) {
        if segmentsByMode[mode] != nil { segmentsByMode[mode] = nil }
    }

    /// Every mode's progress reset (a confirmed Clear).
    func reset() {
        if !segmentsByMode.isEmpty { segmentsByMode = [:] }
    }

    /// `segments` with `coordinate` added: as a new segment when `startsSegment` (or
    /// there is none), beginning at `departure` when that is a different valid point the
    /// step left from, else to the last one (not when it repeats its last point). Past
    /// `capacity` points in all, every segment is halved, then the oldest segments are
    /// dropped until it fits; the newest point always stays.
    nonisolated static func appending(
        _ coordinate: LocationCoordinate,
        to segments: [[LocationCoordinate]],
        startsSegment: Bool,
        departure: LocationCoordinate? = nil,
        capacity: Int
    ) -> [[LocationCoordinate]] {
        var result = segments
        if startsSegment || result.isEmpty {
            if let departure, departure.isValid, departure != coordinate {
                result.append([departure, coordinate])
            } else {
                result.append([coordinate])
            }
        } else {
            guard result[result.count - 1].last != coordinate else { return segments }
            result[result.count - 1].append(coordinate)
        }
        let limit = max(capacity, 2)
        guard pointCount(result) > limit else { return result }
        result = result.map(downsampled)
        while pointCount(result) > limit, result.count > 1 { result.removeFirst() }
        if pointCount(result) > limit, let only = result.first { result = [downsampled(only)] }
        return result
    }

    nonisolated private static func pointCount(_ segments: [[LocationCoordinate]]) -> Int {
        segments.reduce(0) { $0 + $1.count }
    }

    /// Every other point, from the first, plus the last point.
    nonisolated static func downsampled(_ points: [LocationCoordinate]) -> [LocationCoordinate] {
        guard points.count > 2 else { return points }
        var result = stride(from: 0, to: points.count, by: 2).map { points[$0] }
        if let last = points.last, result.last != last { result.append(last) }
        return result
    }
}
