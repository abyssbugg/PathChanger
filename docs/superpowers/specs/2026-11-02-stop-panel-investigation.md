# Stop-by-Stop panel: investigation, wiring audit and redesign (2026-11-02)

Lane: `feat/stop-panel` (worktree `~/.config/superpowers/worktrees/PathChanger/stop-panel`, base `main` 98d4448).
Scope: the mounted mode card (`PathChanger/UI/ModeContextCard.swift`, placed by `ContentView.mapChrome`),
its text model (`StopTravelCardText`), the stop engine in `AppState` (`startStopMove`, `runStops`,
`driveStopRun`, `endStopRun`), the planner (`StopTravelPlan.swift`) and the road router seam.
Out of scope (parallel lane): Clear, `DevLocationBridge`, `LocationSessionCoordinator`, transport,
discovery, tunnels. Unmounted legacy views (`InspectorPanel`, `SidebarView`, `OrganicRail`) are not touched.

Evidence labels follow `CLAUDE.md` §2: **Confirmed** (reproduced by a test or traced to exact code and
proven by a test), **Suspected**, **Unknown**.

Screenshots under review:

- A: `docs/superpowers/specs/2026-11-02-stop-panel-screenshot-A-jump.png` (Jump mode, Walking 1.6 m/s,
  Getting there = Jump, Jump timing = Realistic, At each stop = 5 s, One stop per Move, One way;
  Distance 718 m, Hop 1/3, Next stop 2 of 3, Time left 3:07; the Stop / Pause / Reset Route buttons are cut
  off at the bottom edge).
- B: `docs/superpowers/specs/2026-11-02-stop-panel-screenshot-B-travel.png` (Travel; Jump timing hidden,
  which is intended).

---

## A. Investigation report

### A.1 How the panel is built (traced)

- `ContentView.mapChrome` puts the card in a `ZStack(alignment: .topLeading)` that fills the map area,
  with `.padding(.leading, 16)` and `.padding(.top, 70)` and no bottom constraint
  (`PathChanger/UI/ContentView.swift`, `else if cardOpen { ModeContextCard(...) }`).
- `ModeContextCard.body` is `VStack { header; ScrollView { blocks }; footer }` with
  `.frame(width: 336)` and `.fixedSize(horizontal: false, vertical: true)`.
- In stop modes the scroll content is: ROUTE block, TRAVEL MODE block (`motionBlock`), STOPS block
  (`stopOptionsBlock`), `metricsBlock` (Distance; Duration for Two-Spot/Multi-Spot; Hop for Jump).
  The footer is `stopProgressReadout` (Next stop / Time left / hold / notes) plus the buttons
  Move-or-Stop, Pause/Resume (only while `stopProgress != nil`), Reset Route, and the disabled reason.
- The stop options are segmented `Picker`s (`.pickerStyle(.segmented)`, AppKit `NSSegmentedControl`),
  so their selected segment uses the system accent colour (blue in both screenshots), not the Organic
  orange.
- Settings are per mode in `RouteStateManager.stopTravelSettingsByMode` (persisted under
  `PathChanger.stopTravelSettings.<mode>`), read and written only through
  `AppState.stopTravelSettings(for:)` / `setStopTravelSettings(_:for:)`; the card binds through
  `AppState.stopSettingBinding` / `stopHoldBinding` (`StopTravelCardText.swift`).
- Speed: `SimulationStateManager.effectiveMetersPerSecond` = preset speed when `autoSpeed`, else
  `customSpeedMps`. The card's travel buttons call `AppState.setSpeed` (which only copies the preset to
  `customSpeedMps` when `autoSpeed` is on); the Speed slider binds `customSpeedMps` and is disabled while
  Auto is on (`OrganicSliderRow`).

### A.2 Confirmed defects

Each item lists: observed problem · reproduction · exact location · why · user impact · smallest correction ·
how it is tested. "RED/GREEN" evidence is recorded in section E.

**D1. The footer (Stop / Pause / Reset Route) is pushed below the visible card; the content never scrolls.**

- Observed: screenshot A, the action buttons are cut off at the bottom of the window.
- Reproduce: Jump mode with 3 stops, Getting there = Jump (Jump timing row shown), a run active; window at
  its minimum height (760 pt, map area 704 pt, so 634 pt below the card's 70 pt top inset). Hosted test
  `StopPanelLayoutTests` lays the card out in the same placement and measures it (section E).
- Location: `ModeContextCard.body`, `.fixedSize(horizontal: false, vertical: true)`; placement in
  `ContentView.mapChrome` (no bottom inset).
- Why: `fixedSize(vertical:)` replaces the height the parent offers with the card's *ideal* height. The
  ideal height of a `ScrollView` is its full content height, so the card always takes header + all
  content + footer. Once the STOPS block was added (2026-11-02) that total exceeds the map area, so the card
  extends past the window bottom and the window clips it. The ScrollView is never shorter than its content,
  so it never scrolls. History: commit 5f52309 replaced `.frame(maxHeight: 560)` (which made the greedy
  ScrollView stretch short cards to 560 pt) with `fixedSize` (which hugs content but has no ceiling).
- Impact: Stop, Pause/Resume and Reset Route, the live readout and the Move-disabled reason can be
  unreachable during a run; the user cannot stop or pause from the card.
- Smallest correction: let the card take the height it is offered and give the ScrollView a ceiling equal to
  its measured content height (a preference-key measurement), so short cards still hug their content and tall
  cards scroll with the header and footer pinned; add a bottom inset to the placement.
- Test: `StopPanelLayoutTests` (hosted `NSHostingView` in an offscreen window at fixed sizes): the card's
  bottom stays inside the available area and, when content is taller, the card fills the area and scrolls.

**D2. Jump's "Hop" metric shows the next stop index, not the stop reached, and is wrong for Loop and Back and forth.**

- Observed: `Hop` shows `min(jumpIndex, count)/count`. `jumpIndex` is the cursor's *next* stop. With Loop,
  after the third of three stops is reached the cursor wraps to 0 and the card reads "Hop 0/3" while the
  phone holds stop 3. With Back and forth, after stop 3 the cursor is (1, reversed) and the card reads
  "Hop 1/3".
- Reproduce: Jump, 3 stops, One stop per Move, Loop; press Move three times (engine test with the
  auto-acknowledging injector).
- Location: `ModeContextCard.metricsBlock` (`metricRow(... title: "Hop", value: ...)`).
- Why: the label derives "hops done" from the cursor, which only equals "stops reached" in One way.
- Impact: the panel contradicts the map and the "Next stop" line; the user cannot tell where the run stands.
- Smallest correction: a pure function `StopTravelCardText.reachedStop(...)` that inverts the cursor step for
  the repeat mode and confirms it against the held (acknowledged) coordinate; the row reads "At stop k of n"
  (or "—" when the phone is not at a stop of this run).
- Test: `StopTravelCardTests` (pure, every repeat mode) and an engine test driving Loop to the wrap.

**D3. "At each stop" looks active but does nothing when Go through = One stop per Move.**

- Observed: screenshot A shows At each stop = 5 s with One stop per Move. The planner adds a hold step only
  when the Move continues after the stop (`StopTravelPlanner.steps`, `if !leg.endsMove, settings.holdSeconds > 0`),
  and with One stop per Move every leg ends the Move. The slider still moves and shows "5 s".
- Reproduce: plan test `testRealisticJumpUsesTheRoadDistanceWhenTheLegFollowsRoads` already proves a One stop
  per Move leg has no hold step; the card shows the slider enabled regardless.
- Location: `ModeContextCard.stopHoldRow`; `StopTravelCardText.visibleControls`.
- Why: the card has no notion of when the hold applies.
- Impact: the user believes each stop is held 5 s before continuing; nothing continues automatically, so the
  value has no effect (the stop is simply held until the next Move). Owner rule: never make a setting look
  functional when it does not affect the simulation.
- Smallest correction: `StopTravelCardText.holdApplies(_:)` (true only for Go through = Automatically); the card
  dims and disables the slider (keeping the stored value) and says when it applies.
- Test: `StopTravelCardTests` (pure), plus the existing planner tests.

**D4. Travel mode buttons do not change the speed while the speed is manual (Auto off).**

- Observed: with Auto off, tapping Cycling highlights Cycling and the header says "Cycling", but
  `effectiveMetersPerSecond` stays the custom value, and the road directions are chosen from that custom speed
  (`SimulationSpeed.directionsTravel(autoSpeed: false, ...)` ignores the preset).
- Reproduce: AppState test: `autoSpeed = false`, `customSpeedMps = 3`, tap Driving → effective speed 3 m/s.
- Location: `ModeContextCard.motionBlock` button action `appState.setSpeed(speed)`;
  `SimulationStateManager.setSpeed` (copies the preset only when `autoSpeed`).
- Why: the travel mode and the Auto flag are two separate pieces of state; the button changes only one of them.
- Impact: the panel says "Driving" while the run walks at the custom speed; Realistic jump timing uses the
  custom speed too.
- Smallest correction: the travel buttons call a new `AppState.selectTravelMode(_:)` that turns Auto on and
  selects the preset (choosing Walking means walking speed). Manual speed stays available through the Auto
  toggle and slider; while manual, the header reads "Custom" and no preset is shown selected.
- Test: `StopTravelCardTests` (AppState, no device).

**D5. Speed changes during a run are silently ignored by that run.**

- Observed: `runStops` freezes the speed and update rate in `StopRunPace` at Move (deliberate, review
  2026-11-01). The STOPS block tells the user that changing a stop option ends the run, but the travel block
  says nothing, so dragging Speed or picking another travel mode mid-run looks like it applies and does not.
- Location: `AppState.runStops` (`StopRunPace`), `ModeContextCard.motionBlock`.
- Impact: the shown speed and the travelled speed disagree until the next Move.
- Smallest correction: keep the engine as it is (no behaviour change) and show
  "Speed changes apply from the next Move." in the travel block while a run is active
  (`StopTravelCardText.speedChangeNote`).
- Test: `StopTravelCardTests` (pure).

**D6. The live readout does not say which phase the run is in.**

- Observed: in screenshot A (Jump, Realistic, One stop per Move) the run is *waiting before the jump* for the
  trip time; the readout says "Time left: 3:07", the same words it uses for a travelled leg. While a road route
  is being fetched it shows only "Next stop". Holding reads "Holding stop 2: 5s".
- Location: `StopProgress` has no phase; `driveStopRun.publish` knows it (route fetch, travel point, jump
  countdown, jump apply, hold) but does not record it.
- Impact: the user cannot tell whether the phone is moving, waiting to jump or holding.
- Smallest correction: add `StopProgress.phase` (`findingRoute`, `travelling`, `waitingToJump`, `jumping`,
  `holding`), set at each existing `publish` call, and phase-specific wording ("Jumping in 3:07",
  "Finding a road route…"); travelled legs keep "Time left".
- Test: engine test (Realistic jump wait publishes `waitingToJump`; travel publishes `travelling`), card text tests.

**D7. A finished run leaves no trace on the card.**

- Observed: when a run completes, `stopProgress` becomes nil and the card shows nothing about it; the owner
  requires the completed state to say the last acknowledged location is still held.
- Location: `ModeContextCard.footer` reads only `appState.stopProgress`.
- Smallest correction: `StopTravelCardText.completionLine(movement:mode:held:)` reads the coordinator's
  `.completed(mode)` movement phase with an active application and says "Done · holding stop k".
- Test: `StopTravelCardTests` (pure).

### A.3 Potential defects (suspected, documented, not changed here)

- P1 (Suspected, already in AGENTS.md): Teleport and Joystick Moves do not await an unwinding stop run
  (`startSimulation` one-shot path calls `stopSimulation()` but not `unwindingEngineTask`). Not a stop-panel
  change; outside this lane's files of concern.
- P2 (Suspected): during the wait before the first jump of a Move (Realistic timing) the movement dimension is
  still Idle/Completed, because `driveStopRun` begins movement only on the first acknowledged apply; the card
  shows a countdown and Stop. Pausing during that wait pauses the countdown (proven by
  `testPauseMidHoldStopsTheCountdownUntilResume`-style tests) but the Movement chip does not read Paused.
  Changing it touches the coordinator lifecycle (parallel lane), so it is recorded only.
- P3 (Confirmed behaviour, owner question): a Realistic wait has no upper bound; a 500 km leg at walking speed
  waits about 87 h. It is finite and never negative (distance ≥ 0, speed clamped to ≥ 0.01 m/s, custom speed
  1–30 m/s).
- P4 (Known, AGENTS.md): dragging the At each stop slider mid-run ends the run on its first tick.
- P5 (Owner question, AGENTS.md): Realistic wait = trip time, then the At each stop hold in Automatically
  (trip + hold).
- P6 (Confirmed, labelled): "Distance" and "Duration" are straight-line sums of the stops, not road distance
  and without holds; the redesign labels them as estimates.

### A.4 Correct existing behaviour (verified by reading and existing tests)

- Jump timing shows only for Getting there = Jump (`visibleControls`; `testJumpTimingShowsOnlyWhenGettingThereIsJump`).
- Travel follows the leg's road path at the frozen travel speed; a leg path is fetched just before its leg
  (`testEachLegPathIsFetchedJustBeforeItsLeg`); a straight-line fallback is labelled only when the router said why.
- Jump arrival teleports; Fixed waits nothing before the jump and holds the At each stop time between stops;
  Realistic waits road (or straight-line) distance / speed (`testRealisticJump*`).
- The stop index advances only on an acknowledged arrival (`commitAcknowledgedReceipt`,
  `testTheStopIndexAdvancesOnlyOnAcknowledgedArrivals`); a failed step ends the run without advancing
  (`testAFailedStepEndsMovementWithoutAPhantomPause`).
- Pause holds and stops a countdown; Resume continues; Stop ends the run and holds; Clear wins over a hold or a
  route fetch; editing stops/options/mode ends the run and holds; a new Move waits for the unwinding run
  (`StopTravelEngineTests`).
- Joystick speed is separate (`joystickSpeed`); the stop engine reads only `effectiveMetersPerSecond`.

### A.5 Visual improvements

- Segmented pickers use the system blue accent; the Organic palette uses warm orange for selection.
- "One stop per Move" and "Back and forth" crowd their segments; Repeat's three segments are uneven.
- Hidden accessibility of the visible labels is fine, but the STOPS block has no grouping between "how to
  travel" and "what to do at stops".
- The live readout sits in the footer as plain lines; it needs a phase headline and a clear countdown.
- The Jump timing row appears and disappears without animation, pushing the rest of the block.

---

## B. Settings wiring matrix

Path for every stop option: card control → `AppState.stopSettingBinding` / `stopHoldBinding`
(`StopTravelCardText.swift`) → `AppState.setStopTravelSettings` (ends a run of that mode, holds) →
`RouteStateManager.stopTravelSettingsByMode` (persisted per mode) → read once at Move by `startStopMove`
and frozen in `StopRun.settings` → `StopTravelPlanner.firstLeg` / `leg(after:)` / `steps(for:)` →
`driveStopRun` → `applyPlannedLocation` → `commitAcknowledgedReceipt` (cursor moves only on an
acknowledged arrival) → `stopProgress` / cursor → card.

| UI control | State owner | Planner / runtime consumer | Status | Evidence |
|---|---|---|---|---|
| Travel mode buttons (Walking 1.6, Cycling 5.4, Riding 11.2, Driving 15.6) | `SimulationStateManager.simulationSpeed`, `autoSpeed`, `customSpeedMps` | `effectiveMetersPerSecond` frozen in `StopRunPace` at Move; `SimulationSpeed.directionsTravel` picks the Apple Maps transport | **Fixed (D4)**: buttons now call `selectTravelMode` (Auto on + preset). Before, with Auto off they changed only the label | `testChoosingATravelModeSetsItsSpeedEvenWhenTheSpeedWasManual`, `testPresetSpeedKeepsItsDirectionsTransport`, `testCustomSpeedChoosesTheDirectionsTransportFromTheSpeed` |
| Speed slider + Auto toggle (custom 1–30 m/s) | `customSpeedMps`, `autoSpeed` | same as above | Correct; slider disabled while Auto. Mid-run changes apply from the next Move, now said in the card (**D5**) | `testSpeedNoteSaysWhenTheSpeedIsUsed`; engine freezes pace (review 2026-11-01) |
| Joystick speed | `SimulationStateManager.joystickSpeed` | Joystick loop only | Correct: never read by the stop engine | `testJoystickSpeedNeverChangesAStopRun` (new), `JoystickPolishTests` |
| Getting there = Travel | `StopTravelSettings.arrival` | `steps` → `.travel(points:)` along the leg path (road or straight line) at speed / update rate; leg path fetched just before the leg; straight-line fallback labelled | Correct | `testJumpTravelArrivalMovesAlongTheRoadAndAdvancesOnlyOnArrival`, `testEachLegPathIsFetchedJustBeforeItsLeg`, `testStopProgressReportsTheLegAndTheStraightLineFallback`, `testRoadNotesReachTheReadoutOnlyWhenTheRouterHadOne` |
| Getting there = Jump | `arrival` | `steps` → one `.jump(to:waitBefore:)` per stop: one discrete injection, never the continuous path | Correct | `testMultiSpotJumpArrivalTeleportsAfterTheRealisticTripTime`, `testTwoSpotFixedJumpWaitsTheStopTime` |
| Jump timing (shown only for Jump) | `jumpTiming` | Fixed: `waitBefore = 0` (the pause between stops is the At each stop hold). Realistic: `waitBefore = Geo.totalDistance(anchored path) / max(speed, 0.01)`; road distance when the leg follows roads, else straight line; 0 for a same-place or placed first stop; never negative or infinite | Correct; caption now describes the selected choice | `testRealisticJumpWaitsTheStraightLineTripTime`, `testRealisticJumpUsesTheRoadDistanceWhenTheLegFollowsRoads`, `testFixedJumpNeedsNoPathAndRealisticOrTravelDoes`, `testJumpTimingCaptionFollowsTheChoice`, `testARealisticJumpWaitIsPublishedAsTheWaitBeforeTheJump` (new) |
| At each stop 0–60 s | `holdSeconds` (clamped, whole seconds) | `.hold(stop:seconds:)` only when the Move continues after the stop (Go through = Automatically, and not the end of a one-way run); countdown in ≤1 s ticks, stops while paused, ends on cancellation | Behaviour correct; **D3 fixed**: the card dims and disables it with One stop per Move, where it has no effect | `testHoldIsClampedToZeroToSixtySeconds`, `testHoldsAtEveryReachedStopExceptTheEndOfAOneWayRun`, `testPauseMidHoldStopsTheCountdownUntilResume`, `testAtEachStopAppliesOnlyWhenTheMoveContinuesAutomatically` |
| Go through | `progression` | `makeLeg.endsMove`; one stop per Move continues from the cursor (Jump: `jumpIndex`/`jumpReversed`; Two-Spot/Multi-Spot: `routeStopCursor` + remembered run stops) | Correct for Jump, Two-Spot and Multi-Spot independently | `testOnePerMoveGoesToTheNextStopAndEndsThere`, `testOneStopPerMoveInMultiSpot`, `testAFreshOneStopPerMoveRunStillPlacesItsStop`, `testTheStopIndexAdvancesOnlyOnAcknowledgedArrivals`, `testAFailedStepEndsMovementWithoutAPhantomPause` |
| Repeat | `repeatMode` | `StopTravelPlanner.cursor(after:)`: One way ends; Loop wraps (home leg travelled the same way); Back and forth reverses at the ends; never clears between laps | Correct | `testRepeatModesVisitStopsInTheirOrder`, `testLoopTravelsHomeAndContinuesUntilStop`, `testOneJumpPerMoveBackAndForthKeepsItsDirection`, `testTwoSpotLoopOneStopPerMoveTravelsHomeOnTheWrap`, `testTwoSpotBackAndForthOneStopPerMoveTravelsBack`, `testMultiSpotLoopOneStopPerMoveTravelsTheWrapLeg` |
| Pause / Resume | `SimulationStateManager.isPaused` (+ coordinator movement) | `waitWhilePaused` before every apply and tick; Resume releases waiters | Correct | `testPauseMidLegHoldsAndResumeContinuesFromTheAcknowledgedPoint`, `testPauseMidHoldStopsTheCountdownUntilResume`, `testAPointLandingWhilePausedKeepsRoutePlaybackPaused` |
| Move / Stop | `isMovementEngineRunning`, `stopRun` | `stopSimulation` cancels the run, holds; a new Move awaits the unwinding run | Correct | `testStopMidLegEndsTheRunAndHoldsTheLastAppliedPoint`, `testMoveAfterARunEndingEditWaitsForTheOldApplyToFinish`, `testStopDuringARoadFetchEndsTheRunAndTheLatePathWritesNothing` |
| Live readout: phase, next stop, countdown | `AppState.stopProgress` (published by `driveStopRun.publish`) | Card footer | **D6 fixed**: phase recorded and named | `testTravelAndHoldArePublishedAsTheirPhases`, `testFetchingALegPathIsPublishedAsFindingTheRoute`, `testReadoutNamesTheWaitBeforeAJump` |
| At stop (was Hop) | Jump cursor + acknowledged coordinate | Card metric | **D2 fixed** | `testReachedStopInvertsTheCursorForEveryRepeatMode`, `testTheReachedJumpStopSurvivesALoopWrap` |
| Completion line | Coordinator `.completed(mode)` + applied coordinate | Card footer | **D7 added** | `testCompletionLineSaysTheLastLocationIsStillHeld` |
| Distance / Est. time | Card (straight-line sum of the stops) | Display only | Labelled "(straight line)"; not road distance, no holds (P6) | Visual |

## C. Root causes

- **D1 (layout).** What: the card's footer leaves the window. Why: `.fixedSize(horizontal: false, vertical: true)`
  sizes the card to its ideal height, and a ScrollView's ideal height is its whole content; there was no
  ceiling, and `ContentView` gave the card no bottom inset. Where: `ModeContextCard.body`, `ContentView.mapChrome`.
  Fix: `ContentHuggingLayout` (a 10-line `Layout`) wraps the ScrollView and returns
  `min(child ideal height, offered height)`; `fixedSize` removed; `ContentView` uses
  `ModeContextCard.placementInsets` (top 70, leading 16, bottom 16). Short cards still hug their content
  (guarded by `testAShortCardHugsItsContentInsteadOfFillingTheWindow`); tall cards fill the area and scroll
  between the pinned header and footer.
- **D2 (At stop).** What: Hop showed the cursor. Why: the cursor is the *next* stop and wraps/reverses in
  Loop/Back and forth. Where: `metricsBlock`. Fix: `StopTravelCardText.reachedStop` inverts the cursor step and
  confirms it against the acknowledged coordinate; row renamed "At stop" ("3 of 3" or "—").
- **D3 (At each stop inert).** Why: the planner only holds when the Move continues. Fix: `holdApplies` /
  `holdNote`; slider dimmed and disabled (value kept), note "Used between stops when Go through is Automatically."
- **D4 (travel buttons inert while manual).** Why: `setSpeed` copies the preset only when Auto is on. Fix:
  `AppState.selectTravelMode` (Auto on + preset); header reads "Custom" while manual and no preset shows selected.
- **D5 (speed edits mid-run).** Why: deliberate freeze at Move, but unexplained. Fix: `speedNote` in the travel
  block ("Speed changes apply from the next Move."); also explains when the speed matters for Jump
  ("Fixed jumps do not use the speed." / "Realistic jumps wait the trip time at this speed.").
- **D6 (phase).** Why: `StopProgress` had no phase. Fix: `StopProgress.Phase` set at each existing `publish`
  call in `driveStopRun` (no new timers, no change to what is applied or when); the card headline names it
  ("Waiting to jump to stop 2 · 1:03"); the line reads "Jump in" instead of "Time left" for that wait.
- **D7 (completion).** Fix: `completionLine` from the coordinator's movement phase; "Done · holding stop k of n".

## D. Redesign ("Route Control Center")

Kept: the mounted card, its header, the ROUTE block, the Organic tokens (deep charcoal surfaces, warm orange
selection, sage secondary), every accessibility identifier, the bindings, the engine.

1. **Travel configuration.** Four travel-mode tiles with icon and name (Walking, Cycling, Riding, Driving),
   selected only when that preset is the speed in use; header shows the preset or "Custom"; Speed row with Auto;
   a context note (Fixed jumps ignore speed / Realistic uses it / mid-run changes apply next Move).
2. **Stop behaviour.** The segmented pickers (system blue, crowded) are replaced by Organic choice tiles (icon
   over label, equal widths, orange selected state, `isSelected` trait, one VoiceOver group per option with the
   existing identifier). Getting there and Jump timing form the first group; a divider separates At each stop,
   Go through and Repeat. Jump timing slides in with a 0.18 s animation. The selected timing has its own
   caption. At each stop is dimmed with the reason when it cannot apply. The run-edit note stays.
3. **Live route information** (footer, always visible): a tinted panel with a phase icon, the phase headline
   (Finding a road route / Travelling to stop n / Waiting to jump to stop n / Jumping / Holding at stop n /
   Paused) and a large countdown (hold or leg), then Next stop and any road-route note. Paused uses a neutral
   panel with the countdown greyed. A finished run shows a sage "Done · holding stop k of n" line.
4. **Persistent action footer.** Move/Stop, Pause/Resume, Reset Route stay pinned under the scrolling content.

Snapshots (hosted `NSHostingView` in an offscreen dark-appearance window; map area = window minus the 56 pt
title bar; card area = map area minus the 70/16 pt insets; 2× PNG):

| State | Before | After |
|---|---|---|
| Jump running (Realistic, waiting) at the minimum window (618 pt) | `stop-panel-snapshots/before-jump-active-336x618.png` | `stop-panel-snapshots/after-jump-active-336x618.png` |
| Jump running, small window (420 pt) | `before-jump-active-336x420.png` | `after-jump-active-336x420.png` |
| Jump running, tall window (900 pt) | `before-jump-active-336x900.png` | `after-jump-active-336x900.png` |
| Jump paused | `before-jump-paused-336x618.png` | `after-jump-paused-336x618.png` |
| Jump expanded (Jump timing shown), idle | `before-jump-expanded-336x618.png`, `-336x420.png` | `after-jump-expanded-336x618.png`, `-336x420.png` |
| Jump idle (defaults) | `before-jump-idle-336x618.png` | `after-jump-idle-336x618.png` |
| Travel (Multi-Spot defaults), idle | `before-travel-idle-336x618.png`, `-336x420.png` | `after-travel-idle-336x618.png`, `-336x420.png` |
| Teleport (short card, hugs content) | `before-teleport-idle-336x618.png` | `after-teleport-idle-336x618.png` |

Before: at 618 pt and 420 pt the card is taller than the area; SwiftUI centres the overflow, so both the header
and the footer (Stop / Pause / Reset Route) are outside the visible area and nothing scrolls (same defect as
screenshot A). After: header and footer stay visible at every size; the content scrolls between them.

## E. Test report

Commands (FlowDeck only; the scheme's test action runs the `ReleaseTesting` configuration, a release-derived
configuration with testability and DEBUG-only hooks, not shipping Release):

```
flowdeck test -w PathChanger.xcodeproj -s PathChanger -D "My Mac" --only PathChangerTests/<Class> --json
flowdeck test -w PathChanger.xcodeproj -s PathChanger -D "My Mac" --json
flowdeck build -w PathChanger.xcodeproj -s PathChanger -D "My Mac" -C Debug --json
flowdeck build -w PathChanger.xcodeproj -s PathChanger -D "My Mac" -C Release --json
xcodegen generate && python3 scripts/validate-xcode-wrapper.py
```

RED (observed before any production change):

- `StopPanelLayoutTests` on the unmodified card: 2 passed, 5 failed. Example: "Jump running, smallest window:
  card (16, 70, 336, 850), available bottom 688" (the card needs 850 pt, the area has 618 pt); Jump paused 866 pt;
  Multi-Spot idle at a 420 pt area 700 pt. The tall-window and short Teleport cases passed (no overflow there).
- `StopTravelCardTests` / `StopTravelEngineTests` with the new tests: compile failure, 63 errors (no
  `reachedStop`, `StopProgress.phase`, `completionLine`, `holdApplies`, `speedNote`, `selectTravelMode`, …).
  D2's behavioural evidence is in `testTheReachedJumpStopSurvivesALoopWrap`: after three Loop Moves
  `jumpIndex == 0` while the phone holds stop 3 (the old Hop row read "0/3").

GREEN:

- `StopPanelLayoutTests` 7/7; `StopTravelCardTests` 35/35 (25 existing + 10 new); `StopTravelEngineTests` 36/36
  (31 existing + 5 new); `LegacyLocationSemanticsPresentationTests` 13/13 (source-text checks of the card);
  `JoystickPolishTests` 15/15; `LocationStatusPresentationTests` 13/13.
- Full suite: **1516 tests, 1506 passed, 0 failed, 10 skipped** (main 98d4448: 1494 / 0 failed / 10 skipped;
  +22 new tests, no test removed). One run, no infrastructure error, no FileDescriptorLeakTests variance.
- Debug build: succeeded. Release build: succeeded. Wrapper parity: passed.

Tests added:

- `StopPanelLayoutTests` (new file): footer inside the area for Jump running (618 / 420 / 900 pt), paused,
  expanded Jump timing (618 / 420), idle Jump and Multi-Spot travel (618 / 420); at 420 pt the card fills the area
  (content scrolls); a short Teleport card hugs its content. Snapshots are written only when the marker
  `docs/superpowers/specs/stop-panel-snapshots/tmp_rovodev_write_snapshots` exists (removed after use).
- `StopTravelCardTests`: reached stop for every repeat mode and its nil cases; "At stop" value; At each stop
  applicability; per-choice Jump timing caption; speed note; travel mode selection for all four presets with a
  manual speed; "Custom" title; phase headline and "Jump in" wording; completion line.
- `StopTravelEngineTests`: Realistic wait published as `waitingToJump` with nothing sent and no hold in One stop
  per Move; travel and hold phases; road fetch phase; reached stop after a Loop wrap; joystick speed never
  changes a stop run.

Test updated intentionally: `LegacyLocationSemanticsPresentationTests.testTeleportCardUsesCompactTargetOnlySemantics`
asserted `.fixedSize(horizontal: false, vertical: true)` in the card (the cause of D1). It now asserts the
`ContentHuggingLayout` ceiling, that the card frame is no longer followed by `fixedSize`, that ContentView uses
`ModeContextCard.placementInsets`, and still that `.frame(maxHeight: 560)` is absent.

Owner-listed cases already covered by existing tests (reused, not duplicated): Travel→Jump timing hidden/shown,
Fixed/Realistic timing, road vs straight-line distance, hold 0/5/60 clamp, one stop per Move, Automatically,
One way/Loop/Back and forth, failed injection does not advance, Pause/Resume, Stop holds, Clear wins (explicit
path), edits/mode change end the run and hold, a new Move waits for the unwinding run, preset/custom directions.

Not verified here:

- The live app GUI (the agent must not launch it; GUI automation is blocked in agent sessions). The hosted
  snapshots render in an inactive offscreen window, so AppKit controls (Slider) show inactive tint.
- VoiceOver reading order and keyboard (Tab / Space) operation of the new choice tiles and travel tiles.
- The Jump timing slide-in animation in motion.
- Live Apple Maps routing and real-device timing (MKDirections, Wi-Fi/USB latency).

Physical-device checks still needed (owner): Jump Realistic One stop per Move, wait counts down then the phone
jumps and holds; Pause during the wait stops the countdown, Resume continues; Multi-Spot Travel with At each
stop 5 s holds each stop; Loop wrap shows "At stop 3 of 3"; changing Speed mid-run shows the note and the run
keeps its speed; Stop/Clear distinct.

## F. Change summary

Behaviour / truth fixes (D2–D7):

- `PathChanger/Simulation/StopTravelPlan.swift`: `StopProgress.Phase` and `phase` (default `.travelling`).
- `PathChanger/PathChangerApp.swift`: `driveStopRun.publish` takes the phase at its five existing call sites;
  read-only `displayStopCursor(for:)`. No change to what is applied, when, or to Stop/Pause/Clear.
- `PathChanger/UI/StopTravelCardText.swift`: `jumpTimingCaption(for:)`, `holdApplies`, `holdNote`, `speedNote`,
  `travelModeTitle`, `travelName`, `reachedStop`, `atStopValue`, `phaseTitle`, `completionLine`, "Jump in"
  wording, `AppState.selectTravelMode`.

Layout fix (D1):

- `PathChanger/UI/ModeContextCard.swift`: `ContentHuggingLayout`, `placementInsets`, body wraps the ScrollView
  in the layout with `.scrollBounceBehavior(.basedOnSize)`, `fixedSize` removed.
- `PathChanger/UI/ContentView.swift`: card placement uses `ModeContextCard.placementInsets` (adds the 16 pt
  bottom inset).

Redesign:

- `PathChanger/UI/ModeContextCard.swift`: travel tiles with names and `selectTravelMode`; `caption` helper;
  Organic choice tiles replacing segmented pickers (`stopChoices`, option icons); grouped STOPS block with
  divider and animated Jump timing; At each stop dimmed with its note; live panel (phase, countdown, next stop,
  notes) and completion line in the footer; "At stop" metric; "(straight line)" metric labels; Pause button
  drawn inside its label; duplicate private `travelName` removed.

Tests / docs / generated:

- `Tests/PathChangerTests/StopPanelLayoutTests.swift` (new), `StopTravelCardTests.swift`,
  `StopTravelEngineTests.swift`, `UIComponentTests.swift` (one intentional assertion update).
- `PathChanger.xcodeproj/project.pbxproj`: regenerated by XcodeGen for the new test file (4 lines).
- `docs/superpowers/specs/2026-11-02-stop-panel-investigation.md` (this report),
  `docs/superpowers/specs/stop-panel-snapshots/{before,after}-*.png` (20 files), plus the two owner screenshots.

Splitting note: `ModeContextCard.swift` carries both the layout fix and the redesign. The layout hunks are the
`ContentHuggingLayout` struct, `placementInsets` and the `body` change; everything else in that file is the
redesign (stage with `git add -p`).
