# PathChanger UI Refresh Design — Apple Maps-style
Date: 2026-05-07
Mockup: https://www.figma.com/design/ocAYNxv01vIgdHCxGM8jzr (file `ocAYNxv01vIgdHCxGM8jzr`)

## Executive Summary
PathChanger's macOS UI is currently a chrome-heavy, sidebar-led layout based on `NavigationSplitView` plus a custom dark navy palette (`pcBackground` `#0B1326` etc.). The map is one of several panels rather than the focus, and the same dark palette renders in light mode without adapting. This spec proposes a map-dominant, Apple-Maps-style refresh in which the map fills the window, a hybrid collapsible sidebar slides in over the map, a floating pill in the top-right anchors device + tunnel status, and a floating pill in the bottom-center anchors the primary action. The redesign follows system appearance (auto light/dark) and uses native materials.
Visual reference (3 frames in mockup): expanded light, expanded dark, collapsed dark.

## Current State (only what matters for this redesign)
`PathChanger/UI/ContentView.swift` wraps everything in `NavigationSplitView(columnVisibility:)` with `SidebarView` (`PathChanger/UI/SidebarView.swift`, ~428 lines) and a detail switch over `AppMode` (`teleport`, `route`, `joystick`, `settings`).
`PathChanger/UI/SimulationView.swift` (~1027 lines) is the per-mode detail view with the existing `MapView` and inline floating panels.
`PathChanger/UI/DesignSystem.swift` defines a single dark palette (`pcBackground`, `pcSurface`, `pcText`, `pcAccent`, `pcOutline` …) and a `appGlassPanel` modifier, plus `AppCapsuleButtonStyle`. Light mode is not specifically themed — the same hex constants render in both appearances.
`PathChanger/UI/FloatingControlPanel.swift` is a reusable glass card already used by simulation panels.
`PathChanger/UI/SettingsView.swift` (~705 lines) is opened as a `detail` content for `AppMode.settings`. Onboarding and error dialogs are sheets attached at `ContentView` level; toast notifications are attached via `withToasts()`.

## Confirmed Direction
Inspiration: Apple Maps on macOS — the map dominates, surfaces float as glass cards, and chrome is minimal.
Scope: full-app refresh (main window only — onboarding sheet, error dialogs and Settings sheet keep their current shapes for this iteration).
Layout: hybrid collapsible left sidebar (default expanded; ⌘\ toggle), floating top-right pill for device + tunnel status, floating bottom-center pill for the primary action. Mode-specific surfaces float around the action pill; nothing else is visible at rest besides the search bar inside the sidebar.
Theme: auto-follow system. Same accent (system blue) in both modes. Native `.regularMaterial` / `.ultraThinMaterial`.
Map: native `MapKit` (already used).

## Layout Structure
Window minimums stay at 760×560; ideal 1000×700 (matches `ContentView.frame`).
Z-order from bottom to top:
1. `MapView` — fills the entire window, ignores safe area.
2. Sidebar overlay (when expanded): 240pt wide, height fills window, anchored to leading edge, glass material.
3. Top-right device/tunnel pill: 280×56pt, 24pt insets from the trailing/top edges.
4. Bottom-center action pill: ~220×56pt (mode-dependent width), 28pt above the bottom.
5. When collapsed: a 40×40pt "open sidebar" floating button at top-left (16,56), in addition to (3) and (4).
6. Compatibility warning banner stays as-is, attached above the layout (or moves into the sidebar for this iteration — see Open Questions).

The sidebar slide-in/out is animated `.spring(response: 0.32, dampingFraction: 0.85)`.

### Sidebar Contents (when expanded)
Top: 56pt insets that allow the macOS traffic-light controls to coexist on the left.
Search bar (rounded 8pt rect, 32pt tall, glass): "Search a place" placeholder. Tied to the existing geocoder used by `SimulationView`.
Mode picker: 3-segment control (Teleport, Multi-Spot, Joystick). The 4th `AppMode.settings` mode moves to a footer cog (Settings opens as a sheet, not a sidebar route).
Section: `RECENT LOCATIONS` (uppercase tracked label) followed by the existing recent-location rows (already populated from history — confirm in `SidebarView.swift`).
Footer: cog icon + "Settings" label (opens existing `SettingsView` as a `.sheet`).

### Top-Right Device/Tunnel Pill
Avatar (32pt circle gradient, blue→indigo) with a 2-letter device label initial (e.g. "iP").
Two-line text stack: device name (semibold 13pt) and `Daemon · iOS 26.5` (regular 11pt) with a 8pt status dot — green when tunnel up, red when down, amber when starting/stopping. Source of truth: `TunneldManager.shared.isRunning` and `device.iosVersion`.
Tapping the pill opens a popover showing all available devices + a "Refresh" action (replaces today's device chooser dropdown in the sidebar).

### Bottom-Center Action Pill
Default state: gradient blue capsule, "▶ Set Location" or mode-specific label.
Per mode:
- Teleport: "▶ Set Location" — single tap to commit current map pin (lat/lon visible in a transient toast on success).
- Multi-Spot: "▶ Start Route" → "■ Stop Route" while running. Above the pill, a floating route panel (also glass, 320pt wide, height auto, max 360pt) lists the route stops with reorder handles and per-stop dwell time.
- Joystick: "■ Joystick" (replaces with the existing `JoystickControlView` content above the pill, anchored 28pt above the bottom).
Tunnel-down: pill becomes a destructive amber "⚠ Tunnel Required" with a single tap that triggers tunnel start (`TunneldManager.shared.autoStart`). Disabled state when no device is paired.

### Collapsed State
Sidebar entirely hidden. A 40×40pt rounded glass button shows a magnifier glyph at top-left; tapping (or ⌘\) re-expands. Top-right pill and bottom-center action pill remain.

## Theme & Tokens
Add a parallel light palette to `DesignSystem.swift` and gate via `Color(light: dark:)`-style helpers using `Color(NSColor)` or by reading `colorScheme` in views. Approach: add new tokens that resolve dynamically; do not delete the existing dark hex constants (they remain as fallbacks for previews and asset-missing).

Proposed semantic tokens (resolved dynamically):
- `Color.pcSurfaceMaterial` → `.regularMaterial` (window glass)
- `Color.pcSurfaceMaterialThin` → `.ultraThinMaterial` (pills)
- `Color.pcAccent` → keep system blue `#007AFF` in both modes
- `Color.pcTextDynamic` → primary label color (auto)
- `Color.pcTextMutedDynamic` → secondary label color (auto)
- `Color.pcOutlineDynamic` → adapts: light `rgba(0,0,0,0.06)`, dark `rgba(255,255,255,0.06)`

Action gradient: `LinearGradient` from `#0087FF` to `#0060EA` in both modes (matches the mockup).
Avatar gradient: blue (`#007AFF`) → indigo (`#5856D6`).

## Mockup → SwiftUI Mapping
- Light frame `1:2` → main window in `.light` color scheme.
- Dark frame `1:3` → main window in `.dark` color scheme.
- Collapsed frame `1:4` → state where `isSidebarExpanded == false` (whichever scheme).

The mockup pill text and shadow stack matches `appGlassPanel(cornerRadius: 14)` with `.ultraThinMaterial` background and a `.shadow` stack `(0, 6, 20, 0.12)` (light) / `(0, 6, 20, 0.5)` (dark). The action pill uses two stacked shadows (accent glow + neutral lift). These map to a new `AppCapsuleActionStyle` button style.

## Files To Add or Modify
New files:
- `PathChanger/UI/MainMapShell.swift` — the new top-level layout that replaces `NavigationSplitView` in `ContentView.body`. Exposes `@State isSidebarExpanded`, key binding ⌘\ via `.keyboardShortcut("\\", modifiers: .command)`.
- `PathChanger/UI/Components/CollapsibleSidebar.swift` — the slide-in glass panel that hosts search + mode picker + recents + footer cog.
- `PathChanger/UI/Components/DeviceTunnelPill.swift` — the top-right pill (binds to `appState.selectedDevice` and `TunneldManager.shared.isRunning`).
- `PathChanger/UI/Components/PrimaryActionPill.swift` — the bottom-center pill with mode-aware label and tunnel-required state.
- `PathChanger/UI/Components/SidebarToggleButton.swift` — the collapsed-state floating expand button.

Modified files:
- `PathChanger/UI/ContentView.swift` — replace `NavigationSplitView` with `MainMapShell`. Keep onboarding sheet, error sheet, and toasts attached at the same level.
- `PathChanger/UI/DesignSystem.swift` — add dynamic tokens (light/dark resolution) and `AppCapsuleActionStyle`. Keep all existing tokens.
- `PathChanger/UI/SidebarView.swift` — refactor body into the new collapsible layout (keep recent-locations data wiring intact). Remove the in-sidebar Settings row (becomes footer cog → sheet).
- `PathChanger/UI/SimulationView.swift` — remove the embedded action button (now provided by `PrimaryActionPill`); expose mode-specific overlays (route list, joystick) as separate floating subviews placed by `MainMapShell` above the action pill.

Files unchanged for this iteration: `OnboardingView.swift`, `SettingsView.swift` (only how it's invoked changes — sheet instead of sidebar route), `ErrorDialogView.swift`, `DiagnosticsView.swift`, `ToastView.swift`, `JoystickControlView.swift` (re-hosted but not rewritten), `Accessibility.swift`, `DependencyErrorView.swift`, `VisualComponents.swift`.

## State & Behavior
`AppMode.settings` is removed from the picker. Settings is opened by the footer cog into a `.sheet` at `ContentView`. The `AppMode` enum keeps `settings` for now (deprecation in a follow-up) so `ErrorHandler` paths that reference it don't break.
`columnVisibility` state (currently `NavigationSplitViewVisibility`) is replaced by a single `Bool` `isSidebarExpanded` (default `true`). Persist across launches in `AppPreferences` (mirror existing pattern).
Tunnel state: pill consumes `TunneldManager.shared.$isRunning` published value. The bottom action pill subscribes to the same source (avoids the `AppState` mirror that caused Bug 8 regressions).
Device name: pill consumes `appState.$selectedDevice`. The avatar 2-letter is `String(device.name.uppercased().prefix(2))`.
Compatibility warning banner: stays at top of window (above sidebar+map) for the first iteration to avoid losing visibility. Could move into the device popover later.

## Risks
- `NavigationSplitView` removal means we lose macOS sidebar collapse animation for free. We must reproduce it manually with a spring. Risk is low — SwiftUI handles overlay slide-ins well; we have prior art in `ToastView`.
- Light mode currently has no dedicated palette. Auto-themed `Color(NSColor.labelColor)` works for text, but accent surfaces need explicit dual-mode constants. Risk: visual inconsistencies on first pass; mitigation: build tokens before views.
- `SimulationView` is 1027 lines and tightly couples mode UI with the action button. Risk: route reorder + dwell-time editing must stay reachable. Mitigation: extract subviews `RouteListPanel` and `JoystickPanel` first, then re-host them in `MainMapShell`.
- Tests under `Tests/PathChangerTests/UI*.swift` (if any) may pin to the current container hierarchy. Mitigation: grep for `NavigationSplitView`, `selectedMode`, `columnVisibility`, and update accordingly. Don't touch backend tests.
- ⌘\ collides with… nothing in macOS standard chord set. Confirm via Settings > Keyboard. (Apple Maps uses ⌘\ for the same purpose.)

## Out of Scope
- Map zoom, terrain modes, search-result presentation polish (will follow once shell ships).
- Settings refactor (still a separate `SettingsView` sheet; redesigning it is its own scope).
- Onboarding redesign — keep `OnboardingView` as is.
- Diagnostics view restyle.
- New iconography or custom asset catalogs.
- Localization for new strings (English only this iteration; keep existing localizations intact for unchanged strings).

## Open Questions
1. Should the iOS-compatibility-warning banner stay window-top, or move into the device popover (out of sight at rest)? Default proposal: keep window-top this iteration.
2. Should the sidebar default-collapsed on first launch (Maps-style minimalism) or default-expanded (more discoverable)? Default proposal: expanded on first launch, persisted thereafter.
3. Mode-specific action pill width: fixed 220pt for all modes (current mockup), or 220 for Teleport / 240 for Multi-Spot / 200 for Joystick? Default proposal: fixed 220pt; revisit after first build looks.

## Acceptance Criteria
- Main window opens to the new layout with map dominant; sidebar visible by default.
- ⌘\ toggles the sidebar with a spring animation.
- Top-right pill renders device + tunnel state correctly in both schemes.
- Bottom-center action pill performs the correct action per mode (Teleport commit, Multi-Spot start/stop, Joystick toggle, Tunnel start when down).
- Light + dark mode follow system; no dark-on-dark or light-on-light text in either.
- Existing onboarding, error dialogs, toasts, and settings sheet all open and behave as before.
- All existing Swift tests still pass; new UI does not regress backend tests.
- Mockup parity: visual output matches the three Figma frames within typical SwiftUI rendering tolerances.

## Co-Authoring
Implemented with Oz <oz-agent@warp.dev>.
