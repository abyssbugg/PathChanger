# PathChanger pctnhc In-Place Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the canonical pctnhc mock port inside the existing map-first SwiftUI application while preserving its working device-location and tunnel infrastructure.

**Architecture:** `ContentView` remains the composition root for the map-first experience. Visual state is driven by one persisted appearance value and semantic Organic tokens; interaction state continues through `AppState`, whose only location-delivery dependency remains `DevLocationBridge`. `TunneldManager` and `DeviceManager` retain tunnel and USB-C/Wi-Fi ownership.

**Tech Stack:** SwiftUI, MapKit, AppStorage/UserDefaults, XCTest, FlowDeck.

**Execution constraints:** Work in the current dirty tree, preserve unrelated edits, do not create a second app or worktree, do not commit, do not invoke `xcodebuild`, `xcrun`, or `simctl`, and do not alter the injection/tunnel ownership chain.

---

### Task 1: Lock the experience and protected backend boundary

**Files:**
- Modify: `docs/superpowers/plans/2026-08-16-pctnhc-in-place-port.md`
- Inspect only: `PathChanger/PathChangerApp.swift`
- Inspect only: `PathChanger/Device/DevLocationBridge.swift`
- Inspect only: `PathChanger/Device/PersistentLocationBridge.swift`
- Inspect only: `PathChanger/Device/TunneldManager.swift`
- Inspect only: `PathChanger/Device/DeviceManager.swift`

- [x] Confirm the dispatch chain remains exactly `ContentView.performMove()` → `AppState.startSimulation()` → `SimulationPlanner` → `AppState.setLocation/playRoute/startJoystick` → `DevLocationBridge.setLocation()`.
- [x] Confirm only `DevLocationBridge` selects between `PersistentLocationBridge` and the held pymobiledevice3 DVT process.
- [x] Confirm USB-C/Wi-Fi actions call `DeviceManager.setConnectionMode`, while tunnel actions call `TunneldManager.startTunnel/stopTunnel`.
- [x] Search for periodic password/elevation polling and remove none unless a regression is present; tunnel start/stop are the only UI actions allowed to elevate.

### Task 2: Add one persisted appearance source and exact Organic light/dark tokens

**Files:**
- Modify: `PathChanger/UI/DesignSystem.swift`
- Modify: `PathChanger/UI/ContentView.swift`
- Modify: `PathChanger/UI/OrganicChrome.swift`
- Modify: `PathChanger/UI/OrganicSettingsSheet.swift`
- Test: `Tests/PathChangerTests/UIComponentTests.swift`

- [x] Write a failing test proving `OrganicAppearance` raw values are stable (`light`, `dark`) and that decoding a missing/unknown value falls back to light.
- [x] Run the focused test with FlowDeck and verify RED because `OrganicAppearance` does not exist.
- [x] Add the minimal persisted appearance API:

```swift
enum OrganicAppearance: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    static func persisted(_ rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .light
    }
}
```

- [x] Replace every fixed Organic color with a semantic dynamic color whose light value matches the existing mock ramp and whose dark value matches the canonical `DARK` object (`bg #1a1714`, `surface/#neutral-100 #241f1b`, `text/#neutral-900 #f5ead8`, and the supplied neutral/accent/sage ramps).
- [x] Add `@AppStorage("PathChanger.Appearance")` once at the shell, bind both the title-bar moon/sun control and Settings Appearance to it, and set the shell color scheme from that value. Remove both hard-coded `.preferredColorScheme(.light)` modifiers.
- [x] Run the focused test with FlowDeck and verify GREEN.

### Task 3: Match the locked header and right-docked Settings sheet

**Files:**
- Modify: `PathChanger/UI/OrganicChrome.swift`
- Modify: `PathChanger/UI/OrganicSettingsSheet.swift`
- Modify: `PathChanger/UI/ContentView.swift`

- [x] Replace approximate header SF Symbols for mock-owned glyphs with small reusable stroked `Path` shapes using the canonical SVG path geometry; retain SF Symbols only where the mock does not specify artwork.
- [x] Match `01-theme-final.png`: 48-point header, traffic lights, centered device/transport cluster, tunnel control, Safe Mode, appearance, and settings controls in the same order and spacing.
- [x] Change `OrganicSettingsSheet` to a trailing overlay sheet with dimmed map backdrop, canonical width, full-height inset, header/close control, Appearance segment, and the mock section order: Connection, Movement, Map, Safety, Saved Data.
- [x] Bind existing settings rather than creating parallel values: transport, reconnect, update rate, units, default travel, drift, smooth turns, basemap, labels, coordinates, centering, Safe Mode, cooldown reminders, and saved-data clearing.
- [x] Ensure light/dark switching remints the sheet and underlying chrome immediately without cream surfaces in dark mode.

### Task 4: Preserve staged interaction and align saved/history semantics

**Files:**
- Modify: `PathChanger/UI/ContentView.swift`
- Modify: `PathChanger/UI/SimulationView.swift`
- Modify: `PathChanger/Models/LocationFavorites.swift`
- Test: `Tests/PathChangerTests/AppStateSimulationTests.swift`

- [x] Write a failing behavioral test around an extracted staging helper proving a map selection updates `targetLocation/currentRoute` but does not set `isSimulating` or invoke the location bridge.
- [x] Write a failing test proving recents are recorded only by an accepted Move/injection action, not by staging a map/search/saved selection.
- [x] Run focused tests with FlowDeck and verify RED for the missing staging/history policy.
- [x] Route all map, search, and saved selections through one staging method. Teleport stages one target; Jump appends up to 12 stops; Two-spot maintains a two-point route using current/start plus destination; Multi-spot appends up to 24; Joystick stages its start.
- [x] Move `recordRecent` from the selection path to `performMove` after dispatch is accepted, preserving favorites/places persistence.
- [x] Keep Move dispatching only through `AppState.startSimulation()`. Do not call `setLocation` directly from map/search/saved handlers.
- [x] Run focused tests and verify GREEN.

### Task 5: Complete mode card, saved card, handle, map, zoom, and joystick fidelity

**Files:**
- Modify: `PathChanger/UI/ModeContextCard.swift`
- Modify: `PathChanger/UI/SavedPlacesCard.swift`
- Modify: `PathChanger/UI/OrganicSlider.swift`
- Modify: `PathChanger/UI/JoystickControlView.swift`
- Modify: `PathChanger/UI/SimulationView.swift`
- Modify: `PathChanger/UI/ContentView.swift`
- Test: `Tests/PathChangerTests/MapZoomTests.swift`
- Test: `Tests/PathChangerTests/SimulationPlannerTests.swift`

- [x] Preserve the single-slot card state machine: Saved replaces mode card; the shared edge handle transitions Saved → mode card → closed and reopens the card when closed.
- [ ] Match the canonical content, sizing, typography, controls, and empty/running/cooldown states for Teleport, Jump Teleport, Two-spot, Multi-spot, and Joystick.
- [x] Retain planner semantics: Jump dispatches the next hop teleport, Two-spot dispatches the existing two-point route, Multi-spot dispatches its route, and Joystick calls existing live steering.
- [x] Keep real MapKit tiles visible, hide native map controls, apply muted standard/satellite styling for the selected appearance, render markers/routes above tiles, and never add an opaque tile-hiding overlay.
- [x] Keep zoom relative to `currentRegion`, clamped by `MapZoom.minDelta/maxDelta`; run `MapZoomTests` to verify each operation scales from the current span rather than resetting it.
- [x] Verify joystick drag/keyboard controls, heading, speed, coordinates, engage/disengage, and theme reminting while retaining `AppState.updateJoystickDirection` and `startJoystick`.

### Task 6: Build, install, launch, and visually verify the shipping app

**Files:**
- Verify: `/Applications/PathChanger.app`
- Verify: all modified source and test files above

- [x] Run the complete PathChanger test suite through FlowDeck and record the pass/fail counts.
- [x] Build the macOS scheme through FlowDeck. Do not use raw Apple build tools.
- [x] Build/install the shipping bundle using the repository-supported bundle script only if needed after the FlowDeck build; verify `/Applications/PathChanger.app` is the app launched for QA.
- [x] Check FlowDeck macOS UI permissions. If Accessibility is missing and automated interaction is required, ask once and run `flowdeck ui mac request-permissions`; otherwise perform the permitted launch/screenshot path.
- [ ] Capture and inspect light header, dark header, dark right Settings, each mode card, Saved, cooldown, map tiles, relative zoom, and joystick states against the named canonical screenshots.
- [x] Re-read every lock in this plan, inspect `git diff`, and report any remaining mismatch explicitly. Make no commit.

Verification note: FlowDeck passed 805 tests with 8 environment-dependent tests skipped when the live-device `LocationInjectionIntegrationTests` class was excluded. Light and dark installed-app map/header captures were inspected. Full interactive visual coverage remains open because macOS Accessibility permission was not granted after the single approved request; no second prompt was issued.
