# GUI arrangement (2026-11-04)

Branch `feat/gui-arrangement`, worktree `$HOME/.config/superpowers/worktrees/PathChanger/gui-design`, based on
`feat/live-test-integration` at `00c92c5` (the brief named `9f8db0c`, which does not exist in this repository;
`00c92c5` was the tip of `feat/live-test-integration` when the lane started).

Owner brief (2026-11-04): the design is beautiful and professional, but the dressing and arrangement are not; the
final look is a little messy. Keep the visual language (Organic palette and fonts, sage accents, the map) and improve
arrangement, alignment, spacing rhythm, grouping, hierarchy, sizing consistency and states, in five areas. Behaviour
and state truth do not change: connection, location application and movement stay three states; a location shows as
applied only after its receipt; Clear stays explicit; every existing action stays reachable.

## Commits

| Commit | Area |
|---|---|
| `4f8ea89` | Harness: offscreen window, settings, device and tunnel snapshots; render counters in the GUI benchmark |
| `4d42961` | 5. Tunnel pill and notice |
| `8d5b5f0` | 4. Phone discovery and the USB / Wi‑Fi choice |
| `95b0618` | 2. One location panel: search, modes, Connection / Location / Movement, Clear |
| `d200889` | 1. The Jump / Two-Spot / Multi-Spot card and the live run panel |
| `5ceea02` | 3. Settings as a centred panel |

## Where the snapshots are

The 56 PNGs (about 39 MB) are not in the repository: evidence lives outside it (CLAUDE.md §7). They are archived at `~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/` on the owner's Mac (copy for the private `PathChanger-Evidence` repository). The links below point there. `gui-arrangement-snapshots/.gitignore` keeps rendered PNGs out of commits; regenerate them with the marker described below.

## How the snapshots are made

`GUIArrangementSnapshotTests` (in `Tests/PathChangerTests/StopPanelLayoutTests.swift`, next to the stop-panel
harness) hosts views in an offscreen borderless `NSWindow`, with fixture `AppState`s (no device, no tunnel, an
injector that acknowledges at once and route delays held by a gate so a run stays mid-wait). App storage for the
hosted views is a throwaway `UserDefaults` suite (removed in `tearDown`), so the app's own appearance preference is
never written. PNGs (2×) are written only while the marker
`docs/superpowers/specs/gui-arrangement-snapshots/tmp_rovodev_write_snapshots` exists; it was removed after the
final render. Ordinary runs only check that each state renders (and that the waiting and running states are still
under way when drawn).

`ContentView(initialState:)` opens a given mode, card or Settings for the snapshots (the app always opens in
Teleport with the card closed, as before). The device picker is a popover, which an offscreen window does not draw,
so it is rendered beside the title bar with the popover's rounded edge and shadow. The tunnel pill is drawn from a
value (`TunnelPillModel`), so every phase renders without a running tunnel; the before shots of the pill come from
a verbatim extraction of the old pill face (`4f8ea89`), drawn exactly as before.

Fixtures: a Wi‑Fi phone ("Ada's iPhone", iOS 17.6, seen by usbmux over the network) selected, a USB phone ("Test
iPhone", iOS 17.4) listed; stops about 100 m apart in Tokyo coordinates; the Two-Spot destination about 200 m
away, so its Realistic jump at walking speed waits 2:06 (the owner's run waited 141 s).

## 1. Jump, Two-Spot and Multi-Spot card

| State | Before | After |
|---|---|---|
| Jump, 3 stops, idle | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-window-jump-idle-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-window-jump-idle-dark.png) | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-window-jump-idle-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-window-jump-idle-dark.png) |
| Jump, Realistic, waiting to jump | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-window-jump-waiting-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-window-jump-waiting-dark.png) | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-window-jump-waiting-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-window-jump-waiting-dark.png) |
| Two-Spot, Getting there = Jump, Realistic, waiting | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-window-twospot-waiting-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-window-twospot-waiting-dark.png) | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-window-twospot-waiting-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-window-twospot-waiting-dark.png) |
| Multi-Spot, running | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-window-multispot-running-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-window-multispot-running-dark.png) | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-window-multispot-running-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-window-multispot-running-dark.png) |
| Teleport | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-window-teleport-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-window-teleport-dark.png) | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-window-teleport-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-window-teleport-dark.png) |
| Joystick | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-window-joystick-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-window-joystick-dark.png) | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-window-joystick-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-window-joystick-dark.png) |

Before: three tinted boxes inside the card (ROUTE in accent, TRAVEL MODE and STOPS in cream), each with a tracked
uppercase label, and the Stops box holding the travel options that belong with Getting there. Jump's rows read
Start, Stop 1, Finish beside badges 1, 2, 3. Two-Spot's destination showed its coordinate twice. A Realistic wait
read "Waiting to jump to stop 2 · 2:06" with nothing about what the wait is or what follows, so a long wait looked
stuck.

After:

- One gutter (14 pt) for header, sections and footer. Sections are separated by hairlines instead of boxed, each with
  a sentence-case title, in the order a run is set up: Stops, Getting there (Jump timing beside it when the stops are
  jumped to), Travel mode and speed, At the stops (At each stop, Go through, Repeat), then the totals side by side in
  one row (Distance, Est. time or At stop).
- The header names the mode and says what it does ("Two-Spot · Travel between two points"); card titles match the
  mode switcher (Two-Spot, Multi-Spot).
- Stops: badges as on the map (Jump 1–n, Two-Spot and Multi-Spot a start marker then 1…); Jump rows read Stop 1–n,
  Two-Spot rows Start and Destination; the header shows "3 of 12"; an empty list is a dashed slot with one sentence.
  Each row's favorite and remove buttons have spoken labels.
- Choice tiles (Travel / Jump, Fixed / Realistic, Go through, Repeat, travel presets) share one tile (42 pt).
- The live run panel: the phase in words, the countdown at 22 pt with what it counts to ("Jump in", "Leaves in",
  "Arrives in"), a bar for how far the countdown has come, and what happens next. A Realistic wait says: "Realistic
  timing waits the trip time at Walking speed, then jumps to stop 2. Nothing is sent until then; the iPhone keeps its
  current location." A hold says which stop is held and what follows; a paused run says the countdown stopped.
  The engine now publishes the countdown's whole length (`StopProgress.phaseSecondsTotal`) so the bar is true;
  nothing else about the run changes.
- Footer: a wide Move (or Stop), then Pause/Resume and Reset Route at their own width, one 36 pt height; the Next
  Move line and the Move-disabled reason sit above and below them as before.

## 2. Search, status and modes as one panel

Before ([light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-window-teleport-light.png)): four separate capsules across the
map's top (search, four status chips, Clear, the mode pill), which at 1280 pt truncated every value ("Ready
over…", "35.6800, 13…") and every mode ("Tel…", "Ju…").

After ([light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-window-teleport-light.png),
[dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-window-teleport-dark.png)): one panel on the card's left edge, at most
820 pt wide. Top row: the search field and the five modes at full length (44 pt, the current mode tinted even with its
card closed, Saved & History at the end). Second row: Connection, Location, Movement and Applied split by hairlines,
each a dot in its state's tone, a small label and the value; Reapply location (only when offered) and Clear at the
row's end. Applied keeps its place and reads "None" until a receipt. The three states stay separate cells, with the
same identifiers, labels and values as before. The mode card is placed 12 pt under the panel
(`ModeContextCard.placementInsets` from `LocationPanelMetrics`).

## 3. Settings

Before ([light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-window-settings-light.png),
[dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-window-settings-dark.png)): a full-height panel on the right.

After ([light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-window-settings-light.png),
[dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-window-settings-dark.png)): a centred panel over the dimmed window, 600 pt
wide, at most 720 pt tall and 40 pt from the window's edges (the content scrolls inside). It closes with Esc, the
close button or a click outside, and reads as a modal to VoiceOver. Sections (Appearance, Connection, Movement, Map,
Saved data) are titled groups of rows split by hairlines; every choice is the shared segmented control; switches use
the sage tint; Clear history and Clear favorites use the danger colour. Connect over offers all five modes here. A
footer links the Settings window (`SettingsLink`) for the tunnel mode, diagnostics and shortcuts. Every setting and
action that was there remains, with the same effect; Forget is disabled when no phone is selected (it did nothing
then).

## 4. Phone discovery and USB or Wi‑Fi

| Before | After |
|---|---|
| [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-devices-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-devices-dark.png) | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-devices-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-devices-dark.png) |

Before: the title-bar capsule truncated the reachability ("iOS 17.6 · read…"), carried a green device-count badge
beside the name, and its USB‑C / Wi‑Fi chips highlighted a guessed transport in Auto. The picker was a list with a
tracked uppercase header and Prepare Wi‑Fi; Auto, Random and Background daemon were only in the Settings window.

After: the capsule shows the phone's name over a reachability dot and words, then a USB | Wi‑Fi segmented choice
that shows the setting in use (`ConnectionChoice`); a secondary mode in use shows as a third segment (Auto, Random,
Daemon). The picker leads with Connect over (USB and Wi‑Fi large, with one sentence on what the choice does, and
Other modes in a menu), then one row per phone (transport icon, name, iOS, a reachability dot and words, the selected
row tinted with a check), then Prepare for Wi‑Fi. A refresh button runs the existing device refresh. Each choice
goes through the same calls as before: `DeviceManager.setConnectionMode` (which still restarts a running tunnel when
the tunnel mode changes) or `TunneldManager.preferredMode = .daemon`, as the Settings window does.

## 5. Tunnel pill

| State | Before | After |
|---|---|---|
| Idle | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-tunnel-idle-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-tunnel-idle-dark.png) | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-tunnel-idle-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-tunnel-idle-dark.png) |
| Starting | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-tunnel-starting-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-tunnel-starting-dark.png) | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-tunnel-starting-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-tunnel-starting-dark.png) |
| Waiting for the iPhone | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-tunnel-waiting-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-tunnel-waiting-dark.png) | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-tunnel-waiting-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-tunnel-waiting-dark.png) |
| Running | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-tunnel-running-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-tunnel-running-dark.png) | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-tunnel-running-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-tunnel-running-dark.png) |
| Reconnecting (with Last attempt) | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-tunnel-reconnecting-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-tunnel-reconnecting-dark.png) | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-tunnel-reconnecting-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-tunnel-reconnecting-dark.png) |
| Error | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-tunnel-error-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/before-tunnel-error-dark.png) | [light](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-tunnel-error-light.png) · [dark](~/.local/state/pathchanger/worktree-archive/2026-11-04/gui-arrangement-snapshots/after-tunnel-error-dark.png) |

Before: the pill showed one phrase that was sometimes a state ("Tunnel live", whose click stops it) and sometimes an
action ("Reconnect tunnel"), and the notice sat in the map's search row.

After: the pill reads the state, a hairline, then what a click does: Tunnel live | Stop, Connecting… (spinner, no
action), Waiting for iPhone… | Cancel, Reconnecting… | Stop, Tunnel failed | Reconnect; a stopped tunnel is one
filled Start tunnel button, the title bar's only filled call to action. VoiceOver reads the action, then the state.
The click still resolves through `TunnelPillAction` when pressed (Stop still asks first when a location is held).
The notice is a strip right under the title bar: the first line says what is happening and a reconnect's Last attempt
line carries its own label.

## Main-thread load (GUIUpdateLoadTests)

The benchmark runs a real-time 5 Hz Multi-Spot route (27 acknowledged points) with the whole window and a Multi-Spot
card laid out every frame. Render counts are new in `4f8ea89` (`GUIRenderCounts`, DEBUG only).

| | Before (3 runs at `4f8ea89`/`00c92c5`) | After (3 runs at `5ceea02`, the last inside the full suite) |
|---|---|---|
| Title bar renders | 58 (2.15 per point) | 0 |
| Status panel renders | — (part of the window) | 23 (0.85 per point) |
| Window / mode card shell renders | 58 / 58 (2.15 per point) | 58 / 58 (2.15 per point) |
| Main-thread CPU during the run | 2.005, 1.917, 1.997 s | 1.931\*, 1.790, 1.908 s |
| Added by the run over idle | 1.453, 1.462, 1.612 s | 1.543\*, 1.356, 1.342 s |
| Frame layout CPU | 0.111, 0.121, 0.075 s | 0.183\*, 0.100, 0.149 s |
| Click wait p95 | 24.0, 20.4, 23.2 ms | 23.1\*, 19.5, 21.3 ms |

\* measured after area 5 only.

The title bar observes the device, tunnel and reconnect state instead of AppState and compares equal across window
renders; the status row, the card's sections and its run panel are equatable value views, so they redraw only when
what they show changes. The window and the card shell still observe AppState and render about twice per point;
moving them off AppState needs the composition of `ContentView` to change and was not done here. The CPU and wait
differences are within the run-to-run spread of these measurements and are not claimed as a gain. The benchmark now
asserts that the title bar renders at most 5 times during the run.

## Tests

New: `TunnelPillModelTests`, `ConnectionChoiceTests`, `SettingsPresentationTests` (UIComponentTests.swift),
`StopRunPanelTextTests` (StopTravelCardTests.swift), two engine tests for the countdown's whole length
(StopTravelEngineTests.swift), `GUIArrangementSnapshotTests`, and the title-bar render assertion. Each new model test
was observed failing (missing symbols) before its implementation.

Intentionally updated source-text tests (UIComponentTests.swift, `LegacyLocationSemanticsPresentationTests`): the
search width `360` became the panel's `LocationPanelMetrics.maxWidth`; the status cells are built with
`.init(titleKey: …)` instead of `statusChip(titleKey: …)` calls in `ContentView`; the travel header is "Travel mode"
instead of "TRAVEL MODE"; the device-count badge assertion became the picker's count and the grey dot without a
phone; the transport block is found by `OrganicSegmented(`.

Gates at `5ceea02` (FlowDeck; the scheme's test action runs the `ReleaseTesting` configuration, a release-derived
configuration with testability and DEBUG-only hooks, not shipping Release): full suite 1879 tests, 1869 passed,
0 failed, 10 skipped; Debug and Release builds succeeded; `scripts/validate-xcode-wrapper.py` passed (no files were
added, so `project.yml` and the generated project are unchanged).

## Not verified

- The live app: no clicks, no hover, no keyboard operation, no window resizing in a real window. The agent must not
  launch the app (the owner's instance was running), and the snapshots render in an inactive offscreen window.
- VoiceOver reading order and the modal behaviour of the Settings panel (focus staying inside it).
- The device picker as a real popover (it is rendered beside the title bar in the snapshot).
- The Settings window link (`SettingsLink`) opening the Settings window.
- Animations (the panel's appearance, Jump timing sliding in, the progress bar per countdown tick).
- Rendering artefacts of the harness, not of the app: inactive-window controls (switches read off, sliders grey),
  and a 1 px vertical clip at the left and right ends of some capsules in `cacheDisplay` output (also present in the
  before shots).
- Map overlays (route lines, the trail, stop markers) do not appear in the offscreen snapshots; the map tiles do.
- Physical-device behaviour of anything here.
