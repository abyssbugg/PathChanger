//
//  StopTravelCardText.swift
//  PathChanger
//
//  What the mode card shows for the stop-by-stop options of Jump, Two-Spot and
//  Multi-Spot (PRODUCT_REQUIREMENTS 3.2-3.4 and 3.6), chosen without the view so it
//  can be tested.
//

import SwiftUI

enum StopTravelCardText {
    /// One stop option row in the card, in display order.
    enum Control: String, CaseIterable, Identifiable {
        case arrival, jumpTiming, hold, progression, repeatMode

        var id: String { rawValue }

        var label: String {
            switch self {
            case .arrival: return "Getting there"
            case .jumpTiming: return "Jump timing"
            case .hold: return "At each stop"
            case .progression: return "Go through"
            case .repeatMode: return "Repeat"
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .arrival: return "location.stops.arrival"
            case .jumpTiming: return "location.stops.jumpTiming"
            case .hold: return "location.stops.hold"
            case .progression: return "location.stops.progression"
            case .repeatMode: return "location.stops.repeat"
            }
        }
    }

    static let progressIdentifier = "location.stops.progress"
    static let pauseIdentifier = "location.action.pauseMovement"

    static let holdRange: ClosedRange<Double> = StopTravelSettings.holdRange
    static let holdStep: Double = 1

    static let jumpTimingCaption =
        "Realistic waits the trip time at the travel speed (road distance when known)."
    static let defaultFallbackNote = "No road route found; travelling in a straight line"

    /// What the chosen Jump timing does, said for the choice the user sees selected. Fixed
    /// names At each stop only when it applies (Go through is Automatically): under one
    /// stop per Move the slider is dimmed and each jump happens when Move is pressed.
    static func jumpTimingCaption(for settings: StopTravelSettings) -> String {
        switch settings.jumpTiming {
        case .fixed:
            return holdApplies(settings)
                ? "Jumps at once; At each stop sets the pause between stops."
                : "Jumps at once when you press Move."
        case .realistic:
            return "Waits the trip time at the travel speed: road distance when known, else a straight line."
        }
    }

    // MARK: When an option applies

    /// At each stop holds a reached stop before the run continues; with one stop per Move
    /// nothing continues (each stop is held until the next Move), so it has no effect.
    static func holdApplies(_ settings: StopTravelSettings) -> Bool {
        settings.progression == .automatic
    }

    /// Why At each stop is inactive, shown under the dimmed slider.
    static func holdNote(_ settings: StopTravelSettings) -> String? {
        holdApplies(settings) ? nil : "Used between stops when Go through is Automatically."
    }

    /// When the travel speed matters, or that a running Move keeps its speed.
    static func speedNote(settings: StopTravelSettings, isRunActive: Bool) -> String? {
        if isRunActive { return "Speed changes apply from the next Move." }
        guard settings.arrival == .jump else { return nil }
        switch settings.jumpTiming {
        case .fixed: return "Fixed jumps do not use the speed."
        case .realistic: return "Realistic jumps wait the trip time at this speed."
        }
    }

    // MARK: Travel mode

    /// The travel-mode header: the preset's name, or Custom while the speed is manual
    /// (a manual speed is what the run uses, whichever preset was last chosen).
    static func travelModeTitle(_ speed: SimulationSpeed, autoSpeed: Bool) -> String {
        guard autoSpeed else { return "Custom" }
        return travelName(speed)
    }

    static func travelName(_ speed: SimulationSpeed) -> String {
        switch speed {
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .driving: return "Driving"
        case .fast: return "Riding"
        default: return speed.displayName
        }
    }

    // MARK: Where the run stands

    /// The stop the phone holds: the stop the cursor last stepped past, if the held
    /// (acknowledged) coordinate is that stop. Nil before the first stop, after Clear, or
    /// when the phone is somewhere else.
    static func reachedStop(
        stops: [LocationCoordinate],
        cursor: StopCursor,
        repeatMode: StopTravelSettings.RepeatMode,
        held: LocationCoordinate?
    ) -> Int? {
        let count = stops.count
        guard count > 0, let held else { return nil }
        let candidate: Int?
        switch repeatMode {
        case .oneWay:
            candidate = cursor.nextIndex - 1
        case .loop:
            // A fresh cursor and a wrapped one look alike; the held stop tells them apart.
            candidate = (cursor.nextIndex - 1 + count) % count
        case .backAndForth:
            candidate = cursor.reversed ? cursor.nextIndex + 1 : cursor.nextIndex - 1
        }
        guard let index = candidate.map({ min($0, count - 1) }), index >= 0, stops[index] == held else { return nil }
        return index
    }

    static func atStopValue(reached: Int?, total: Int) -> String {
        guard let reached else { return "—" }
        return "\(reached + 1) of \(total)"
    }

    /// The run's headline: what it is doing now, in words.
    static func phaseTitle(_ progress: StopProgress) -> String {
        if progress.isPaused { return "Paused" }
        let next = min(max(progress.nextStopIndex, 0) + 1, max(progress.totalStops, 1))
        switch progress.phase {
        case .findingRoute: return "Finding a road route to stop \(next)"
        case .travelling: return "Travelling to stop \(next)"
        case .waitingToJump: return "Waiting to jump to stop \(next)"
        case .jumping: return "Jumping to stop \(next)"
        case .holding:
            let held = (progress.heldStopIndex ?? max(progress.nextStopIndex - 1, 0)) + 1
            return "Holding at stop \(held)"
        }
    }

    /// After a run of this mode completed and its last stop is still held.
    static func completionLine(
        movement: LocationMovementPhase,
        mode: AppMode,
        isHeld: Bool,
        reachedStop: Int?,
        totalStops: Int
    ) -> String? {
        guard isHeld, case .completed(let completedMode) = movement, completedMode == mode.locationMode else { return nil }
        guard let reachedStop else { return "Done · holding the last location" }
        return "Done · holding stop \(reachedStop + 1) of \(totalStops)"
    }

    // MARK: Which controls show

    /// Teleport and Joystick have no stops; only Jump, Two-Spot and Multi-Spot do.
    static func showsStopOptions(for mode: AppMode) -> Bool {
        RouteStateManager.stopModes.contains(mode)
    }

    /// The rows to show: Jump timing only applies when Getting there is Jump.
    static func visibleControls(for mode: AppMode, settings: StopTravelSettings) -> [Control] {
        guard showsStopOptions(for: mode) else { return [] }
        return Control.allCases.filter { $0 != .jumpTiming || settings.arrival == .jump }
    }

    // MARK: Option titles

    static func title(_ arrival: StopTravelSettings.Arrival) -> String {
        switch arrival {
        case .travel: return "Travel"
        case .jump: return "Jump"
        }
    }

    static func title(_ timing: StopTravelSettings.JumpTiming) -> String {
        switch timing {
        case .fixed: return "Fixed"
        case .realistic: return "Realistic"
        }
    }

    static func title(_ progression: StopTravelSettings.Progression) -> String {
        switch progression {
        case .automatic: return "Automatically"
        case .onePerMove: return "One stop per Move"
        }
    }

    static func title(_ repeatMode: StopTravelSettings.RepeatMode) -> String {
        switch repeatMode {
        case .oneWay: return "One way"
        case .loop: return "Loop"
        case .backAndForth: return "Back and forth"
        }
    }

    // MARK: At each stop

    static func holdLabel(_ seconds: Double) -> String {
        let whole = wholeSeconds(seconds)
        return whole == 0 ? "No wait" : "\(whole) s"
    }

    static func holdAccessibilityValue(_ seconds: Double) -> String {
        switch wholeSeconds(seconds) {
        case 0: return "0 seconds, no wait"
        case 1: return "1 second"
        case let whole: return "\(whole) seconds"
        }
    }

    private static func wholeSeconds(_ seconds: Double) -> Int {
        guard seconds.isFinite else { return 0 }
        return Int(seconds.rounded())
    }

    // MARK: Live readout

    struct ProgressLine: Equatable, Identifiable {
        enum Kind: String, Equatable {
            case paused, holding, nextStop, timeLeft, fallback, routeNote
        }

        let kind: Kind
        let text: String

        var id: String { kind.rawValue }
    }

    /// One line per fact, each its own accessibility element: Paused, the hold
    /// countdown, the next stop (1-based), the time left in the leg, the straight-line
    /// note when the leg has no road route, and the road route's own note (a detour or
    /// a long route) when it has one.
    static func progressLines(_ progress: StopProgress) -> [ProgressLine] {
        var lines: [ProgressLine] = []
        if progress.isPaused {
            lines.append(ProgressLine(kind: .paused, text: "Paused"))
        }
        if let holdLeft = progress.holdSecondsLeft {
            let held = (progress.heldStopIndex ?? max(progress.nextStopIndex - 1, 0)) + 1
            lines.append(ProgressLine(kind: .holding, text: "Holding stop \(held): \(roundedUpSeconds(holdLeft))s"))
        }
        let total = max(progress.totalStops, 0)
        let next = min(max(progress.nextStopIndex, 0) + 1, max(total, 1))
        lines.append(ProgressLine(kind: .nextStop, text: "Next stop: \(next) of \(total)"))
        if let legLeft = progress.legSecondsLeft {
            let label = progress.phase == .waitingToJump ? "Jump in" : "Time left"
            lines.append(ProgressLine(kind: .timeLeft, text: "\(label): \(clock(legLeft))"))
        }
        if progress.usesStraightLineFallback {
            lines.append(ProgressLine(kind: .fallback, text: progress.fallbackNote ?? defaultFallbackNote))
        }
        if let routeNote = progress.routeNote, !routeNote.isEmpty {
            lines.append(ProgressLine(kind: .routeNote, text: routeNote))
        }
        return lines
    }

    // MARK: Live run panel (GUI arrangement 2026-11-04)

    /// The countdown the panel shows big: a hold's, else the leg's (a Realistic wait's).
    static func countdown(_ progress: StopProgress) -> TimeInterval? {
        progress.holdSecondsLeft ?? progress.legSecondsLeft
    }

    /// The words beside the countdown.
    static func countdownCaption(_ progress: StopProgress) -> String? {
        guard countdown(progress) != nil else { return nil }
        switch progress.phase {
        case .waitingToJump: return "Jump in"
        case .holding: return "Leaves in"
        case .travelling: return "Arrives in"
        case .findingRoute, .jumping: return nil
        }
    }

    /// How far the current countdown has come, 0 to 1; nil when its length is unknown.
    static func phaseFraction(_ progress: StopProgress) -> Double? {
        guard let total = progress.phaseSecondsTotal, total > 0, let left = countdown(progress) else { return nil }
        return min(max(1 - left / total, 0), 1)
    }

    /// What is happening and what comes next, in one or two sentences; nil while
    /// travelling (the countdown and the next stop say it).
    static func phaseExplanation(_ progress: StopProgress, settings: StopTravelSettings, travelName: String) -> String? {
        let next = min(max(progress.nextStopIndex, 0) + 1, max(progress.totalStops, 1))
        if progress.isPaused {
            return "Paused: nothing is sent and the countdown stops. The iPhone keeps its current location."
        }
        switch progress.phase {
        case .waitingToJump:
            return "Realistic timing waits the trip time at \(travelName) speed, then jumps to stop \(next). "
                + "Nothing is sent until then; the iPhone keeps its current location."
        case .holding:
            let heldIndex = progress.heldStopIndex ?? max(progress.nextStopIndex - 1, 0)
            guard progress.nextStopIndex != heldIndex else {
                return "The iPhone stays at stop \(heldIndex + 1); the run then ends and keeps it."
            }
            let verb = settings.arrival == .jump ? "jumps" : "travels"
            return "The iPhone stays at stop \(heldIndex + 1), then \(verb) to stop \(next)."
        case .findingRoute:
            return "Asking Apple Maps for a road route. Nothing is sent meanwhile."
        case .jumping:
            return "Sending the jump. Stop \(next) counts once the iPhone confirms it."
        case .travelling:
            return nil
        }
    }

    /// m:ss, rounded up so a countdown reaches 0:00 only when the time is up.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = roundedUpSeconds(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func roundedUpSeconds(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int((seconds - 1e-9).rounded(.up))
    }

    // MARK: Next Move

    static let nextMoveIdentifier = "location.stops.nextMove"

    /// One plain line saying what the next Move of a stop mode does, from where the run
    /// stands (owner rule 2026-11-03): which stop it goes to and how, what follows with
    /// Go through = Automatically, and whether it starts over. Uses the planner, so it
    /// says what the engine will do. Nil for Teleport and Joystick or without stops.
    /// - Parameters:
    ///   - stops: the run's stops (`AppState.nextMoveStops(for:)`).
    ///   - held: the location the phone holds (nil = the first stop is placed).
    ///   - followsRoads: travelled legs ask for a road route.
    static func nextMoveSummary(
        mode: AppMode,
        stops: [LocationCoordinate],
        cursor: StopCursor,
        settings: StopTravelSettings,
        held: LocationCoordinate?,
        followsRoads: Bool
    ) -> String? {
        guard showsStopOptions(for: mode),
              let first = StopTravelPlanner.firstLeg(stops: stops, origin: held, cursor: cursor, settings: settings) else { return nil }
        let count = stops.count
        let start = StopTravelPlanner.startCursor(cursor, stopCount: count, repeatMode: settings.repeatMode)
        let startsOver = settings.repeatMode == .oneWay && StopTravelPlanner.isFinished(cursor, stopCount: count)
        let arrival: String
        switch settings.arrival {
        case .travel: arrival = followsRoads ? "travel by road" : "travel"
        case .jump: arrival = "jump"
        }
        let placed = first.from == nil
        var line: String
        if placed {
            // Nothing held: the stop is placed. Held at that very stop: the run starts there.
            line = (held == nil ? "place stop " : "start at stop ") + "\(first.stopIndex + 1)"
        } else {
            let wait = settings.arrival == .jump && settings.jumpTiming == .realistic ? " (waits the trip time)" : ""
            line = "\(arrival) to stop \(first.stopIndex + 1)\(wait)"
        }

        guard settings.progression == .automatic else { return "Next Move: " + (startsOver ? "start over — " : "") + line }
        // Every stop automatically: the rest of this pass, then how the run repeats.
        let headsBack = settings.repeatMode == .backAndForth && start.reversed
        let following: [Int] = headsBack
            ? Array((0..<first.stopIndex).reversed())
            : Array((first.stopIndex + 1)..<max(count, first.stopIndex + 1))
        if let firstFollowing = following.first, let lastFollowing = following.last {
            let range = following.count == 1
                ? "stop \(firstFollowing + 1)"
                : "stops \(firstFollowing + 1)–\(lastFollowing + 1)"
            line += placed ? ", then \(arrival) to \(range)" : ", then \(range)"
        }
        switch settings.repeatMode {
        case .oneWay: break
        case .loop: line += ", then back to stop 1 and repeat"
        case .backAndForth:
            line += headsBack ? ", then forward again and repeat" : ", then back through the stops to stop 1 and repeat"
        }
        return "Next Move: " + (startsOver ? "start over — " : "") + line
    }

    // MARK: Move gating

    /// Jump's Move is possible while the planner has a next hop for these stops, which is
    /// whenever there is a valid stop: a finished One way run starts over at stop 1
    /// (PRODUCT_REQUIREMENTS §3.6.1), and Loop and Back and forth return home by design.
    static func jumpCanMove(stops: [LocationCoordinate], cursor: StopCursor, settings: StopTravelSettings) -> Bool {
        StopTravelPlanner.firstLeg(stops: stops.filter(\.isValid), origin: nil, cursor: cursor, settings: settings) != nil
    }

    // MARK: Pause / Resume

    struct PauseButton: Equatable {
        enum Action: Equatable { case pause, resume }

        let title: String
        let systemImage: String
        let action: Action
    }

    /// Shown only while a stop run is active (`stopProgress` is set).
    static func pauseButton(progress: StopProgress?, isPaused: Bool) -> PauseButton? {
        guard progress != nil else { return nil }
        return isPaused
            ? PauseButton(title: "Resume", systemImage: "play.fill", action: .resume)
            : PauseButton(title: "Pause", systemImage: "pause.fill", action: .pause)
    }

    @MainActor
    static func perform(_ action: PauseButton.Action, on appState: AppState) {
        switch action {
        case .pause: appState.pauseMovement()
        case .resume: appState.resumeMovement()
        }
    }

    // MARK: Editing during a run

    /// The options stay editable during a run. The engine runs on the options it took
    /// at Move (`StopRun.settings`), and `AppState.setStopTravelSettings` ends a run of
    /// that mode when its options change, holding the last acknowledged point
    /// (PRODUCT_REQUIREMENTS 3.2: turning Auto jump off ends the sequence and holds).
    /// That is safe, so the card says so instead of disabling the controls.
    static func runEditNote(isRunActive: Bool) -> String? {
        isRunActive ? "Changing an option ends this run and holds the current location." : nil
    }
}

extension AppState {
    /// Choosing a travel mode means its speed: Auto turns on and the preset applies
    /// (with a manual speed the buttons used to change only the label).
    func selectTravelMode(_ speed: SimulationSpeed) {
        autoSpeed = true
        setSpeed(speed)
    }

    /// A binding to one stop option of `mode`, written through `setStopTravelSettings`.
    func stopSettingBinding<Value>(
        _ keyPath: WritableKeyPath<StopTravelSettings, Value>,
        for mode: AppMode
    ) -> Binding<Value> {
        Binding(
            get: { self.stopTravelSettings(for: mode)[keyPath: keyPath] },
            set: { newValue in
                var settings = self.stopTravelSettings(for: mode)
                settings[keyPath: keyPath] = newValue
                self.setStopTravelSettings(settings, for: mode)
            }
        )
    }

    /// The card's "Next Move" line for `mode`; nil while a run of the mode is active (its
    /// live panel shows where it stands) and for modes without stops.
    func nextMoveSummary(for mode: AppMode) -> String? {
        guard StopTravelCardText.showsStopOptions(for: mode), !isStopRunActive(for: mode),
              case .success(let stops) = nextMoveStops(for: mode) else { return nil }
        return StopTravelCardText.nextMoveSummary(
            mode: mode,
            stops: stops,
            cursor: displayStopCursor(for: mode),
            settings: stopTravelSettings(for: mode),
            held: currentLocation,
            followsRoads: legPathProvider != nil
        )
    }

    /// The At each stop slider: whole seconds, 0-60 (0 = no wait).
    func stopHoldBinding(for mode: AppMode) -> Binding<Double> {
        let hold = stopSettingBinding(\.holdSeconds, for: mode)
        return Binding(
            get: { hold.wrappedValue },
            set: { hold.wrappedValue = $0.isFinite ? $0.rounded() : 0 }
        )
    }
}
