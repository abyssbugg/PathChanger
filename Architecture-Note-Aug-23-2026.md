# PathChanger Architecture Note — Aug 23, 2026

## Scope and phase gate

This is the Phase 0 comprehension deliverable requested by `Todo-aug-23-2026.md`.
It documents the current system as it exists in the working tree after the
already-completed stabilization work. No application behavior was changed while
producing this note.

The current root UI is the map-first SwiftUI shell:

- `PathChanger/PathChangerApp.swift:13` creates the shared `AppState`,
  `TunneldManager`, and `DependencyValidator`.
- `PathChanger/PathChangerApp.swift:21` selects `DependencyErrorView` or
  `ContentView`.
- `PathChanger/UI/ContentView.swift:57` is the active main screen.
- `PathChanger/UI/OrganicChrome.swift:14` is the active title bar.
- `PathChanger/UI/SimulationView.swift:11` is the active map canvas.
- `PathChanger/UI/ModeContextCard.swift:10` is the active mode panel.
- `PathChanger/UI/OrganicSettingsSheet.swift:10` is the in-app settings overlay.

Several older UI surfaces are still compiled but are not mounted by the current
root screen: `SidebarView`, `DeviceListView`, `InspectorPanel`, and
`FloatingControlPanel`. They remain relevant to the later wiring audit because
they contain alternate controls and alternate interpretations of connection
state.

## Runtime composition and ownership

`AppState` is currently a composition root, but not yet a thin one:

- `DeviceStateManager` owns device-list, selection, readiness, and copied tunnel
  status.
- `RouteStateManager` owns route data and route-library operations.
- `SimulationStateManager` owns published simulation configuration and location
  state.
- `AppState` still owns and runs the active route and joystick loops.
- `SimulationEngine` exists and is initialized, but does not own the primary
  route/joystick execution path.
- `TunneldManager.shared` owns the formal tunnel state machine and privileged
  tunnel lifecycle.
- `DeviceManager` independently discovers devices and independently detects
  tunnel processes with `pgrep`.

Relevant composition points:

- `PathChanger/PathChangerApp.swift:330-382`
- `PathChanger/PathChangerApp.swift:498-553`
- `PathChanger/PathChangerApp.swift:632-732`
- `PathChanger/Core/StateManagers/DeviceStateManager.swift:20-126`
- `PathChanger/Core/StateManagers/SimulationStateManager.swift:76-126`
- `PathChanger/Device/TunneldManager.swift:325-452`

## GUI map and control call paths

### Application shell

#### Dependency gate

- App appears → `DependencyValidator.validationStatus`
  → `DependencyErrorView` when invalid.
- **Install pymobiledevice3**
  → `DependencyValidator.installLatestPymobiledevice3()`.
- **Check Again**
  → `DependencyValidator.validateAll()`.
- Source: `PathChanger/UI/DependencyErrorView.swift:12-145`.

#### App menu commands

- **Check for Updates**
  → `AppDelegate.updaterController.checkForUpdates()`.
- **Set Location…**
  → `AppState.showLocationInput = true`.
  The current map-first shell does not visibly consume this flag, so this is a
  candidate dead command.
- **Clear Location**
  → `AppState.clearLocation()`
  → `SimulationStateManager.clearLocation()`
  → `DevLocationBridge.clearLocation(for:)`
  → held-process termination or pymobiledevice3 DVT clear.
- **Refresh Devices**
  → `AppState.refreshDevices()`
  → `DeviceStateManager.refreshDevices()`
  → `DeviceManager.refreshDevices()`.
- **Start Simulation**
  → `AppState.startSimulation()`
  → `SimulationPlanner.plan(...)`
  → teleport injection, active route loop, or active joystick loop.
- **Pause / Stop / Speed**
  → `SimulationStateManager` flags or `AppState.stopSimulation()`.
- Source: `PathChanger/PathChangerApp.swift:35-101`.

### Active title bar

Source: `PathChanger/UI/OrganicChrome.swift:14-379`.

#### Device selector

- Click device cluster
  → toggles `showDeviceMenu`.
- Select one row
  → `AppState.selectDevice(_:)`
  → `DeviceStateManager.selectDevice(_:)`
  → selected device callback
  → `SimulationEngine.setDevice(_:)`.
- Device count reads `AppState.availableDevices`.
- Device subtitle currently renders the word `trusted` unconditionally. It does
  not read a trust state.

#### USB-C / Wi-Fi transport chips

- USB-C
  → `DeviceManager.setConnectionMode(.usb)`
  → persists `connectionMode`
  → maps to `TunnelMode.usb`
  → restarts a running/starting tunnel if mode changed
  → refreshes devices.
- Wi-Fi
  → the same path with `.wifi`.
- Source: `PathChanger/UI/OrganicChrome.swift:102-119` and
  `PathChanger/Device/DeviceManager.swift:1452-1480`.

#### Tunnel button

- Idle
  → label `Start tunnel`
  → `AppState.startSelectedTunnel()`
  → `AppState.tunnelTargetDeviceId()`
  → `TunneldManager.startTunnel(deviceId:)`.
- Starting
  → label `Connecting…`; click is ignored.
- Running
  → label `Tunnel live`
  → `TunneldManager.stopTunnel()`.
- Error
  → label `Tunnel error`; click retries through
  `AppState.startSelectedTunnel()`.
- The action label now reads only `TunneldManager.state`; direct transport
  readiness is used only in help text.
- Source: `PathChanger/UI/OrganicChrome.swift:169-202,319-378` and
  `PathChanger/PathChangerApp.swift:437-498`.

#### Safe Mode

- Title-bar shield
  → sets both `safeModeTeleport` and `safeModeJoystick`.
- It changes two simulation flags; it does not represent five independent
  per-mode policies.
- Source: `PathChanger/UI/OrganicChrome.swift:150-168`.

#### Appearance and settings

- Sun/moon
  → writes `PathChanger.Appearance`.
- Settings
  → opens `OrganicSettingsSheet`.

#### Prepare Wi-Fi

- Device popover **Prepare Wi-Fi**
  → `AppState.prepareSelectedDeviceForWiFi()`
  → `DeviceManager.prepareWiFi(for:)`
  → `DevicePreparationService.prepareWiFi(deviceId:)`
  → sequential commands:
  1. `lockdown wifi-connections --state on --udid <UDID>`
  2. `lockdown remotepairing --pair --udid <UDID>`
  → stores `lastPreparedDeviceUDID`
  → refreshes transport and device discovery.
- Source: `PathChanger/UI/OrganicChrome.swift:263-282`,
  `PathChanger/PathChangerApp.swift:418-435`, and
  `PathChanger/Device/DeviceManager.swift:564-584`.

### Main map shell

Source: `PathChanger/UI/ContentView.swift:57-564` and
`PathChanger/UI/SimulationView.swift:11-286`.

#### Search

- Type
  → `LocationSearchService.searchText`
  → service-published search results.
- Submit / arrow / result row
  → `ContentView.applyPlace(...)`
  → updates input text
  → `AppState.stageLocation(_:for:)`.
- This stages local planning state only; it does not inject until **Move**.

#### Map tap

- MapKit screen point
  → `SimulationView.handleMapTap`
  → coordinate validation
  → `ContentView.applyPlace`
  → `AppState.stageLocation`.
- Route modes append or constrain route points according to `AppMode`.
- Double-click route marker
  → `AppState.removeRouteWaypoint(at:)`.

#### Map controls

- Center button
  → changes local `MapCameraPosition`.
- Zoom + / -
  → `MapZoom.scaled(...)`
  → changes local camera region.
- Coordinate overlay
  → reads `showCoordinatesOnMap` and current/target location.
- Map style is carried by `ContentView.mapStyle`; the visible shell currently
  has no mounted control calling the unused `cycleMapStyle()` helper.

#### Mode picker

- Teleport / Jump / Two-spot / Multi-Spot / Joystick
  → changes `ContentView.selectedMode`
  → writes `AppState.activeMode`
  → resets jump index
  → constrains route point count
  → clears route when entering joystick
  → opens `ModeContextCard`.

#### Saved & History

- Calendar button
  → opens `SavedPlacesCard`.
- Favorites / Places / Recent tabs
  → read `LocationFavoritesManager.shared`.
- Select item
  → `ContentView.applyPlace`
  → stages the location.
- Remove / Clear
  → matching `LocationFavoritesManager` mutation.
- Source: `PathChanger/UI/SavedPlacesCard.swift:14-186`.

#### Live simulation pill

- Appears when `AppState.isSimulating`.
- Displays `SimulationStateManager.statusText` and current/target coordinate.
- **Reset**
  → `AppState.stopSimulation()`
  → cancels tasks
  → `clearLocation()`.

### Mode context card

Source: `PathChanger/UI/ModeContextCard.swift:10-595`.

#### Shared Move path

- **Move**
  → `ContentView.performMove()`
  → `SimulationPlanner.plan(...)`
  → records recent/history when eligible
  → `AppState.startSimulation()`.
- Route/Two-spot while already active
  → `AppState.stopSimulation()`.

#### Teleport

- Coordinate fields submit
  → `ContentView.commitTeleport()`
  → validates
  → `applyPlace`
  → stages target.
- Move
  → planner `.teleport`
  → `SimulationStateManager.setLocation(...)`
  → `DevLocationBridge.setLocation(...)`.
- Cooldown UI and guard read the shared
  `SimulationStateManager.cooldownRemaining`.

#### Jump

- Map taps append route hops.
- Move
  → planner uses `jumpIndex`
  → returns one teleport coordinate
  → injection
  → increments `jumpIndex` when current location equals the requested hop.
- `autoJump` is exposed by the mode card but is not consumed by the active
  `AppState.startSimulation()` path. It is currently a label/toggle without an
  active execution loop.

#### Two-spot

- Map taps stage at most two endpoints.
- Move
  → planner returns route points
  → `AppState.playRoute`.
- Stop
  → `AppState.stopSimulation`.
- Repeat
  → `loopRoute`, consumed when route playback completes.

#### Multi-Spot

- Map taps append waypoints.
- Reorder controls exist in `InspectorPanel`, but `InspectorPanel` is not
  mounted in the current root. The active `ModeContextCard` does not expose
  drag-to-reorder.
- Save stops
  → writes all stops to favorites.
- Swap
  → reverses current route.
- Remove
  → route mutation.
- Move
  → planner route
  → `AppState.playRoute`.
- Import GPX is exposed by the unmounted `InspectorPanel`; the active card does
  not expose import.

#### Joystick

- Drag knob
  → normalized vector
  → `AppState.updateJoystickDirection`.
- First engaged vector
  → `AppState.startSimulation()`
  → planner joystick start
  → `AppState.startJoystick`.
- Arrow key down
  → starts simulation when inactive
  → updates direction.
- Arrow key up / drag release
  → direction zero.
- **Reset to real location**
  → `AppState.clearLocation()`.
- Source: `PathChanger/UI/JoystickControlView.swift:10-98`.

#### Shared speed, cooldown, and realism controls

- Travel preset
  → `AppState.setSpeed`
  → `SimulationStateManager.setSpeed`.
- Speed slider
  → `customSpeedMps`.
- Cooldown slider
  → `cooldownSeconds`.
- Repeat
  → `loopRoute`.
- Realistic pace
  → `addGPSDrift`.
- These are shared state, not five independent per-mode policies.

### Organic settings overlay

Source: `PathChanger/UI/OrganicSettingsSheet.swift:10-416`.

- Appearance
  → `PathChanger.Appearance`.
- Forget paired device
  → sets only `AppState.selectedDevice = nil`; it does not delete pairing
  records or disconnect the backend session.
- Update frequency
  → `AppState.updateFrequencyHz`; route/joystick loops read it.
- Reconnect automatically
  → writes only `@AppStorage("autoReconnectDevice")`.
  No active connection to `ReliabilityManager` was found.
- Units
  → writes `unitsMetric`; current route metrics still render fixed metric
  labels.
- Default travel mode
  → `AppState.setSpeed`.
- GPS drift / smooth turns
  → active simulation flags.
- Street labels
  → writes `showStreetLabels`; `SimulationView` does not read it.
- Coordinate overlay / keep centered
  → `SimulationView` reads matching `@AppStorage` values.
- Safe Mode
  → sets the two combined safety flags.
- Cooldown reminder
  → `SimulationStateManager.cooldownReminder`.
- Saved data actions
  → `LocationFavoritesManager`.

### Standard macOS Settings scene

`PathChanger/PathChangerApp.swift:104-108` mounts `SettingsView` in the standard
macOS Settings scene. This is a second settings implementation in addition to
`OrganicSettingsSheet`.

It exposes:

- refresh preferences,
- connection mode,
- tunnel mode,
- Start/Stop Tunnel,
- auto-start,
- diagnostics,
- map display,
- advanced options.

Important alternate paths:

- Settings **Start Tunnel**
  → `TunneldManager.startTunnel()` without selected device ID.
- Diagnostics **Location Injection**
  → directly constructs and runs pymobiledevice3 arguments rather than using
  `DevLocationBridge`.
- Source: `PathChanger/UI/SettingsView.swift:10-304` and
  `PathChanger/UI/DiagnosticsView.swift:171-569`.

### Onboarding

Source: `PathChanger/UI/OnboardingView.swift:12-479`.

- Next / Back
  → advances local onboarding state.
- Dependency step
  → direct `PythonPathResolver` checks.
- Install
  → `DependencyValidator.installLatestPymobiledevice3()`.
- Re-check
  → `OnboardingViewModel.checkDependencies()`.
- Get Started
  → persists `onboardingCompleted`.
- Onboarding reports the pymobiledevice3 version using the minimum version
  constant as a placeholder, not the actual installed version.

### Error dialogs and recovery actions

- `ErrorHandler.currentError`
  → `ContentView` sheet.
- Retry
  → refresh devices.
- Start Tunnel
  → `AppState.startSelectedTunnel()`.
- Check Connection
  → `AppState.checkTunneldStatus()`.
- Enable Developer Mode
  → currently no action.
- Source: `PathChanger/UI/ErrorDialogView.swift:11-288` and
  `PathChanger/UI/ContentView.swift:544-563`.

### Compiled but unmounted alternate UI

These surfaces are not reachable from `ContentView`:

- `SidebarView`
- `DeviceListView`
- `InspectorPanel`
- `FloatingControlPanel`

They contain alternate connection labels and alternate mode controls. Keeping
them compiled increases wiring ambiguity because tests can pass against a view
that users cannot reach.

Examples:

- `SidebarView` treats every selected device as connected when
  `TunneldManager.isRunning`, regardless of per-device transport.
- `DeviceListView` treats `AppState.connectionStatus` as per-device truth.
- `InspectorPanel` has GPX import and route reordering that the active mode card
  lacks.

## Current tunnel lifecycle

### 1. Explicit start

1. GUI calls `AppState.startSelectedTunnel()`.
2. `AppState.tunnelTargetDeviceId()` resolves a canonical UDID when possible.
3. `TunneldManager.startTunnel(deviceId:)` rejects concurrent active or
   transitioning starts.
4. `TunnelStateMachine` receives `.startRequested(mode:)`:
   `idle → starting`.
5. `TunneldManager.detectRunningTunnel()` checks process patterns.
6. An existing process is adopted only if a usable RSD endpoint can be parsed.
7. Otherwise `attemptStart(mode:deviceId:)`:
   - verifies USB presence for USB mode,
   - validates Python and exact command arguments,
   - creates the tunnel log,
   - builds an allowlisted privileged shell command,
   - invokes the macOS administrator prompt,
   - captures or discovers the child PID.
8. State machine receives `.processLaunched(pid:)` and remains `starting`.
9. `TunnelStartupWaiter` polls until:
   - a usable RSD endpoint appears,
   - the process exits,
   - or timeout expires.
10. Success sends `.connectionEstablished(info:)`:
    `starting → running`.
11. Failure sends `.processExited` or `.errorOccurred`:
    `starting → error`.

Sources:

- `PathChanger/Device/TunneldManager.swift:582-698`
- `PathChanger/Device/TunneldManager.swift:775-858`
- `PathChanger/Device/TunnelStateMachine.swift:478-592`

### 2. Active state

- `TunneldManager.state == .running` is the formal active state.
- `TunnelHealthMonitor` monitors process/connectivity.
- Health failure sends `.healthCheckFailed`:
  `running → error`.
- Automatic privileged restart is intentionally not attempted. The user must
  explicitly retry.
- Source: `PathChanger/Device/TunneldManager.swift:1224-1268` and
  `PathChanger/Device/TunnelStateMachine.swift:611-677`.

### 3. Stop

1. GUI calls `TunneldManager.stopTunnel()`.
2. State machine receives `.stopRequested`:
   `running/starting/error → stopping`.
3. Only tracked PIDs are sent to the privileged stop command.
4. Local process/resources and RSD state are cleared.
5. `.processStopped` transitions to `idle`.
- Source: `PathChanger/Device/TunneldManager.swift:714-737` and
  `PathChanger/Device/TunnelStateMachine.swift:678-731`.

### 4. Relaunch adoption

1. `DeviceStateManager` polls every five seconds.
2. `DeviceManager.checkTunneldStatus()` runs `pgrep`.
3. If a process exists and `TunneldManager.state` is exactly idle,
   `adoptRunningTunnelIfPresent()` runs.
4. Adoption requires both a detected process and usable parsed RSD info.
5. Missing RSD info ends in stable error, not a new connecting loop.
- Source: `PathChanger/Core/StateManagers/DeviceStateManager.swift:137-149,251-294`
  and `PathChanger/Device/TunneldManager.swift:551-579`.

### 5. Direct transport without tunnel

`DeviceStateManager.isDeviceReady` is true when:

- a selected device is directly available on USB or Network usbmux, or
- the formal tunnel is running.

`DevLocationBridge` uses:

- `--rsd HOST PORT` for a parsed one-device tunnel,
- `--tunnel UDID` for daemon tunneld,
- `--udid UDID` otherwise.

Source: `PathChanger/Core/StateManagers/DeviceStateManager.swift:67-99`,
`PathChanger/Device/LocationConnectionArguments.swift:10-28`, and
`PathChanger/Device/DevLocationBridge.swift:671-746`.

## Current device-discovery lifecycle

### Entry and schedule

- `DeviceManager.init()` immediately checks tunnel status, refreshes devices,
  and starts a 120-second refresh loop.
- `AppState.init()` schedules another status check and refresh after two
  seconds.
- `DeviceStateManager` also polls tunnel/transport status every five seconds.
- GUI refresh controls can start additional refreshes.

There is no single discovery scheduler.

### Four enumeration paths

`DeviceManager.refreshDevices()` runs three live paths in parallel and then
adds one persistent-record path.

#### Path A: usbmux

- Command: `pymobiledevice3 usbmux list`.
- Returns USB and Network records.
- Identity source:
  `UniqueDeviceID`, falling back to `Identifier`.
- Transport source:
  `ConnectionType`.
- Name source:
  initial JSON fields, then `lockdown info --udid` enrichment.
- Also updates:
  `usbDirectDeviceIds`, `wifiDirectDeviceIds`,
  `usbTransportAvailable`, and `wifiTransportAvailable`.
- Source: `PathChanger/Device/DeviceManager.swift:887-985,1434-1486`.

#### Path B: Bonjour mobdev2

- Command:
  `pymobiledevice3 bonjour mobdev2 --timeout 5 --pair-records ~/.pymobiledevice3`.
- Identity source:
  `UniqueDeviceID`, falling back to `Identifier`.
- On the current iOS 27 device, `UniqueDeviceID` is null and `Identifier` is the
  discovered endpoint address.
- The same phone therefore arrives as separate IPv4 and IPv6 records.
- Name source:
  Bonjour `DeviceName`, with product type/version from the browse record.
- This was the direct producer of the observed UDID + IPv4 + two IPv6
  four-entry display.
- Source: `PathChanger/Device/DeviceManager.swift:848-885,1083-1154`.

#### Path C: tunneld HTTP API

- Endpoint: `127.0.0.1:49151`.
- Identity source:
  JSON dictionary key, expected to be UDID.
- Name source:
  cached device data or `lockdown info --tunnel <UDID>`.
- Source: `PathChanger/Device/DeviceManager.swift:987-1081`.

#### Path D: RemotePairing records

- Source:
  filenames in `~/.pymobiledevice3`.
- Identity source:
  `remote_<UDID>.plist` filename.
- Name:
  literal fallback `Paired iOS Device`.
- This is persistent knowledge, not proof that the device is currently online.
- Source: `PathChanger/Device/DeviceManager.swift:824-847`.

### Merge and canonicalization

The current merge order is:

1. known pairing records,
2. mobdev2,
3. usbmux,
4. tunneld API.

Records are first keyed by their source-provided ID. A post-merge
`deduplicatePhysicalDevices` pass then maps endpoint IDs onto a canonical UDID
using:

- exact metadata fingerprint,
- a matching named UDID record,
- or the sole visible UDID when the metadata resembles it.

This fixed the current single-phone four-entry GUI bug. Runtime evidence showed:
`4 raw entries → 1 canonical device`.

It is still reconciliation after source enumeration rather than one canonical
identity being established at ingestion.

Source: `PathChanger/Device/DeviceManager.swift:642-822`.

### Device-name derivation

The displayed name can come from four different sources:

1. `DeviceName` in usbmux JSON.
2. `lockdown info` enrichment.
3. `DeviceName` in Bonjour mobdev2.
4. hardcoded `Paired iOS Device`.

Generic names are replaced with a product-model mapping. Non-generic values are
accepted as authoritative.

Current risks:

- A persistent pairing placeholder can temporarily display a generic name.
- Source merge order and asynchronous refresh can replace metadata.
- `Device.chromeTitle` strips duplicated ` (iOS ...)` text but does not verify
  authority.
- `DeviceStateManager.refreshDevices()` deduplicates again by ID after
  `DeviceManager` already canonicalized.

## GUI/backend state-divergence register

### D1 — Tunnel state exists in three live forms

1. `TunneldManager.state`:
   formal state-machine truth.
2. `DeviceManager.isTunneldRunning`:
   debounced `pgrep` result.
3. `DeviceStateManager.isTunneldRunning`:
   copied value fed by both of the above.

The title-bar button reads form 1. Simulation readiness and some status text
read form 3. Legacy views read mixtures of all three.

This is the primary tunnel GUI/backend divergence.

### D2 — Readiness and tunnel action were rendered in one control

`selectedDirectTransportAvailable` answers:
“Can this selected UDID be reached directly?”

`TunneldManager.state` answers:
“What is the RemoteXPC tunnel lifecycle?”

The old title-bar logic used direct readiness to replace the tunnel action label
with `Wi-Fi ready` or `USB ready`, making tunnel start inaccessible. These
signals are now separated in the button behavior, but there is not yet a
dedicated readiness UI as required by Phase 1.

### D3 — One `connectionType` cannot represent both transports

`Device` contains one enum value: `.usb` or `.wifi`.

A real phone may be reachable over both simultaneously. Merge currently
prefers USB for the canonical record while separate transport-ID sets preserve
some additional truth. The model cannot directly render “both ready” or say
which transport an active tunnel uses.

### D4 — Selection is treated as connection

`DeviceStateManager.refreshDevices()` sets:

- `.connected` whenever any selected device exists.

`selectDevice(_:)` also sets `.connected` without a handshake.

The device can therefore display connected while its source is only a pairing
record or an unreachable Bonjour endpoint.

### D5 — Direct Wi-Fi policy conflicts inside the backend

`DeviceStateManager.isDeviceReady` allows direct Network usbmux without a
tunnel.

`DevLocationBridge.performPreflight` also allows it.

But `DeviceManager.connect(to:)` still rejects every `.wifi` device when its
copied `isTunneldRunning` is false.

The same model can be ready in one layer and rejected in another.

### D6 — Simulation status text conflicts with simulation readiness

`SimulationStateManager.canStartSimulation` uses
`DeviceStateManager.isDeviceReady`, which accepts direct transport.

`SimulationStateManager.statusText` says `Tunnel not running` whenever the
copied tunnel flag is false, even when direct transport is ready.

### D7 — Active transport is inferred, not observed

The title bar's USB/Wi-Fi selection display is derived from:

- preferred connection mode, then
- aggregate transport booleans.

It is not derived from the running tunnel's actual established transport.
There is no current same-network state.

### D8 — Status and errors have multiple writers

`AppState.statusMessage`, `AppState.lastError`,
`SimulationStateManager.onStatusMessage`, `ErrorHandler.currentError`,
`TunneldManager.lastError`, and device/reliability callbacks can all publish
overlapping user-facing state.

The most recent writer wins. No single owner prioritizes messages.

### D9 — Active and dormant simulation implementations coexist

`AppState` owns the active `playRoute` and `startJoystick` loops.

`SimulationEngine` and mode implementations coexist, but the GUI does not
dispatch the five modes through one verified engine boundary.

This creates the risk that a test validates one implementation while the GUI
runs another.

### D10 — Settings contain label-only or partially wired controls

Confirmed examples:

- `Reconnect automatically` writes `AppStorage` but does not configure
  `ReliabilityManager`.
- `Street labels` writes `AppStorage` but is not read by `SimulationView`.
- Units do not change route metric rendering.
- Jump `autoJump` is exposed but not consumed by the active simulation path.
- The title bar accepts an `onRefresh` closure but exposes no refresh button
  that calls it.

### D11 — Two settings systems and unmounted UI retain alternate behavior

`OrganicSettingsSheet` and `SettingsView` are both active through different
entry points. They do not expose the same options or use the same handlers.

Compiled but unmounted views contain further alternate interpretations of
connection and simulation state.

## Root-cause hypothesis verdict

### Verdict: confirmed at the structural level

The four-device duplication and `Ready`-instead-of-`Start Tunnel` bugs did not
have the exact same immediate faulty line, but they share the same architectural
cause:

> Source-specific identity and readiness are published as if each were
> canonical application truth, while the GUI consumes mixed signals from
> whichever layer updated most recently.

For device duplication:

- usbmux published a UDID identity,
- mobdev2 published three endpoint identities,
- pairing records published another record,
- tunneld could publish another UDID record.

For the tunnel button:

- direct transport readiness,
- pgrep process existence,
- state-machine tunnel state,
- and copied/debounced tunnel state

were treated as interchangeable connection truth.

The current fixes mask neither symptom at the view-only level:

- device records are canonicalized in `DeviceManager` before publication,
- the tunnel button now reads the formal tunnel state only.

However, Phase 1 and Phase 2 still need to establish explicit canonical models
rather than relying on multiple parallel booleans and post-merge repair.

## Dependencies and order for the next phases

Phase 1 must define tunnel state and transport readiness as independent models
before adding the new readiness UI.

Phase 2 must define one canonical `DeviceIdentity` and attach a set of observed
transports to it. It should not repeat view-level deduplication.

Phase 3 depends on both:

- failover needs accurate per-device transport availability,
- active tunnel transport must be observed,
- same-network state must exist,
- and session state must be independent of the transport carrying it.

Phase 4 should not proceed until the transport/session boundary is stable. The
five mode implementations cannot be verified under failover while connection
truth remains duplicated.

## Phase 0 completion result

- GUI surfaces mapped.
- Active control call paths traced.
- Tunnel lifecycle documented.
- Four device-enumeration paths documented.
- Device identity and name derivation documented.
- GUI/backend divergence points identified.
- Shared root-cause hypothesis evaluated and confirmed.
- No application behavior changed during Phase 0.

The next gated action is Phase 1: define and implement separate transport
readiness and tunnel lifecycle models, then verify them through the fresh dev
GUI.
