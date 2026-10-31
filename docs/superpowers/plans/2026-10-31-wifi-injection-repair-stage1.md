# Wi-Fi Injection Repair — Stage 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Teleport work end-to-end through the GUI on Wi-Fi: device injection actually applies and holds, the app acknowledges it truthfully, and Clear returns to real GPS.

**Architecture:** Three fixes on one lane: (1) the Swift/Python acknowledgement key mismatch that discards successful injections, (2) Developer Disk Image mounting as an explicit device-preparation step (the root cause of silent non-application on iOS 27.2), (3) rewiring the Python helper to the proven direct-`--udid` lane (usbmux + pymobiledevice3's internal no-root userspace tunnel fallback) with tunnel-generation-keyed RSD as fallback only.

**Tech Stack:** Swift 5.9 / SwiftUI (macOS 14+), XCTest via FlowDeck (ReleaseTesting config), Python 3.13 managed venv with pymobiledevice3 11.49.1 (`~/Library/Application Support/PathChanger/runtime/location`).

**Working tree:** `/Users/datamatics/.config/superpowers/worktrees/PathChanger/wifi-injection-repair` (branch `fix/wifi-injection-repair` off `main` @ `f631141`). All paths below are relative to that worktree root.

**Spec:** `docs/superpowers/plans/` companion spec `docs/superpowers/specs/2026-10-31-wifi-injection-repair-design.md`.

**Verification commands (all through FlowDeck — never raw xcodebuild):**
```bash
# From the worktree directory:
flowdeck test discover
flowdeck test -w PathChanger.xcodeproj -s PathChanger -D "My Mac" --only <exact-identifier-from-discovery>
flowdeck test -w PathChanger.xcodeproj -s PathChanger -D "My Mac"     # full suite
flowdeck build -w PathChanger.xcodeproj -s PathChanger -D "My Mac"
```
Note: the scheme's test action runs the ReleaseTesting configuration (release-derived with testability), not shipping Release — always state this caveat when reporting "tests green".

---

### Task 0: Baseline on the new branch

**Files:** none (verification only)

- [ ] **Step 1: Record the baseline suite state**

Run from the worktree:
```bash
flowdeck test discover
flowdeck test -w PathChanger.xcodeproj -s PathChanger -D "My Mac"
```
Expected: suite passes with ~1075 tests (merge record says 1075 / 0 failed, three consecutive runs, 2026-10-25). Record the exact discovered count in the worktree — it is the "no unexplained decrease" reference for every later gate.

- [ ] **Step 2: Record baseline artifact**

```bash
flowdeck build -w PathChanger.xcodeproj -s PathChanger -D "My Mac"
shasum -a 256 ~/Library/Developer/FlowDeck/DerivedData/PathChanger-*/Build/Products/Debug/PathChanger.app/Contents/MacOS/PathChanger
```
Expected: green build; record the hash prefix in the task notes.

---

### Task 1: Acknowledgement key fix + golden-fixture contract test (defect 1)

**Files:**
- Modify: `PathChanger/Device/PersistentLocationBridge.swift` (struct `PersistentBridgeWireResponse`, ~line 818-855)
- Modify: `Tests/PathChangerTests/PersistentLocationBridgeTests.swift` (fixture ~line 708-723 pins the wrong key; append new golden-fixture test)
- Test: `Tests/PathChangerTests/PersistentLocationBridgeTests.swift`

- [ ] **Step 1: Write the failing golden-fixture test**

Append to `Tests/PathChangerTests/PersistentLocationBridgeTests.swift`:

```swift
func testSocketSuccessResponseGoldenFixtureDecodesToAcknowledgement() throws {
    // Pins the EXACT JSON scripts/location_bridge.py emits on a successful
    // socket set_location: the success payload (location_bridge.py:208-212)
    // plus the validate_request echo and helper_id added by the socket
    // writer. If Python or Swift changes the wire shape, this test fails.
    let json = """
    {"success": true, "actual_channel": "explicitRSD",
     "endpoint_class": "remoteServiceDiscovery",
     "request_id": "D81A6845-7B11-43EF-9D19-A3149FD0D097",
     "session_generation": 1, "helper_id": "golden-fixture"}
    """
    let response = try JSONDecoder().decode(
        PersistentBridgeWireResponse.self, from: Data(json.utf8))
    let acknowledgement = try response.acknowledgement(physicalTransport: .wifi)
    XCTAssertEqual(acknowledgement.requestID.uuidString,
                   "D81A6845-7B11-43EF-9D19-A3149FD0D097")
    XCTAssertEqual(acknowledgement.sessionGeneration, 1)
    XCTAssertEqual(acknowledgement.channel, .explicitRSD)
    XCTAssertEqual(acknowledgement.endpointClass, .remoteServiceDiscovery)
}
```

Note for the implementer: confirm the `LocationDVTChannel` case spelling for `"explicitRSD"` in `PathChanger/Models/LocationSessionState.swift` (search `LocationDVTChannel`); adjust the asserted case name if it differs, never the fixture string (the fixture is the contract).

- [ ] **Step 2: Run it — observe the expected failure**

```bash
flowdeck test -w PathChanger.xcodeproj -s PathChanger -D "My Mac" \
  --only PathChangerTests/PersistentLocationBridgeTests/testSocketSuccessResponseGoldenFixtureDecodesToAcknowledgement
```
Expected: FAIL — decode yields `channel == nil`, so `acknowledgement()` throws "Missing or inconsistent provider acknowledgement". This failing test IS the live bug reproduced.

- [ ] **Step 3: Fix the CodingKey**

In `PathChanger/Device/PersistentLocationBridge.swift`, add an explicit `CodingKeys` to `PersistentBridgeWireResponse` (keep the stored property name `channel` so `acknowledgement()` and `wireResponse()` are untouched):

```swift
struct PersistentBridgeWireResponse: Codable, Sendable {
    let success: Bool
    var request_id: UUID?
    var session_generation: UInt64?
    var error: String?
    var code: String?
    var message: String?
    var ready: Bool?
    var channel: String?
    var endpoint_class: String?

    /// The Python helper emits `actual_channel` on socket responses
    /// (scripts/location_bridge.py set_location/clear_location success
    /// payloads). The Swift property stays `channel`; only the wire key
    /// changes. Pinned by the golden-fixture test.
    enum CodingKeys: String, CodingKey {
        case success
        case request_id
        case session_generation
        case error
        case code
        case message
        case ready
        case channel = "actual_channel"
        case endpoint_class
    }

    // ... invalidatesManagedHelperState and acknowledgement() unchanged ...
}
```

- [ ] **Step 4: Correct the stale fixture**

In `Tests/PathChangerTests/PersistentLocationBridgeTests.swift` (~line 708-723), the fixture JSON builds the response with `"channel": "nativeRSD"`. Change that one key to `"actual_channel": "nativeRSD"` so the fixture matches the real wire. If that fixture feeds a decode assertion that relied on the old key, update the assertion message only — semantics unchanged.

- [ ] **Step 5: Run the focused test — expect PASS, then the full file**

```bash
flowdeck test -w PathChanger.xcodeproj -s PathChanger -D "My Mac" \
  --only PathChangerTests/PersistentLocationBridgeTests/testSocketSuccessResponseGoldenFixtureDecodesToAcknowledgement
flowdeck test -w PathChanger.xcodeproj -s PathChanger -D "My Mac" \
  --only PathChangerTests/PersistentLocationBridgeTests
```
Expected: PASS both.

- [ ] **Step 6: Commit**

```bash
git add PathChanger/Device/PersistentLocationBridge.swift Tests/PathChangerTests/PersistentLocationBridgeTests.swift
git commit -m "fix(bridge): decode actual_channel acknowledgement key; pin wire contract with golden fixture"
```

---

### Task 2: Helper lane rewiring — direct-udid first, proven tunnel fallback (defects 12/5, Python side)

**Files:**
- Modify: `scripts/location_bridge.py` (`_get_or_create_service` ~line 88-143, `_open_preferred_rsd` ~line 145-180)
- Create: `scripts/verify_bridge_lane.py` (temporary verification script, `tmp_rovodev_` naming not required for a durable script but delete-or-keep decision at review)
- Test: live device verification script (owner-supervised session) + journal inspection

Context for the implementer (from the 2026-10-31 live session): the CLI command
`pymobiledevice3 developer dvt simulate-location set --udid <UDID> -- LAT LNG`
is PROVEN to apply location on the target phone (iOS 27.2) over Wi-Fi. Its internal fallback logs:
`Trying again over a no-root userspace tunnel since it is a developer command on an iOS 17+ device`
and then `userspace RSD established (no root)`. The helper must reach the same service construction. The helper's existing `_open_preferred_rsd` already wraps `PreferredRsdTunnel` (`pymobiledevice3.remote.rsd_tunnel.PreferredRsdTunnel`).

- [ ] **Step 1: Read the CLI fallback to find the exact mechanism**

```bash
python3_bin="$HOME/Library/Application Support/PathChanger/runtime/location/bin/python3"
"$python3_bin" -c "import pymobiledevice3, pathlib; print(pathlib.Path(pymobiledevice3.__file__).parent)"
grep -rn "no-root userspace tunnel" <that-path>/cli/ <that-path>/remote/ | head -5
```
Read the function that emits that warning. Identify the exact call it makes to establish the no-root userspace tunnel and the RSD endpoint it yields (likely `PreferredRsdTunnel` or a userspace tunnel service class). Record the exact callable and its signature in the task notes.

- [ ] **Step 2: Write the failing lane-verification script**

Create `scripts/verify_bridge_lane.py`:

```python
"""Prove the helper's service-construction path applies location.
Run with the managed runtime python while the phone is unlocked.
Success = exit 0 with APPLIED lines; the owner observes the map move."""
import argparse, asyncio, sys

async def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", required=True)
    parser.add_argument("--lat", type=float, required=True)
    parser.add_argument("--lng", type=float, required=True)
    parser.add_argument("--hold", type=float, default=30.0)
    args = parser.parse_args()

    sys.path.insert(0, __file__.rsplit("/", 1)[0])
    from location_bridge import LocationServicePool  # adjust to the real class name in location_bridge.py

    pool = LocationServicePool()
    udid, rsd_address, rsd_port, connection_type = args.udid, None, None, None
    location = await pool.open_location(udid, rsd_address, rsd_port, connection_type)
    await location.set(args.lat, args.lng)
    print(f"APPLIED {args.lat},{args.lng} — holding {args.hold}s", flush=True)
    for remaining in range(int(args.hold), 0, -10):
        await asyncio.sleep(min(10, remaining))
        print(f"held {int(args.hold) - remaining + 10}s", flush=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
```

Implementer notes: open_location must call the SAME construction the server uses after the rewiring in Step 3 (extract the shared construction into a method on the pool if it is not already one, so the verification script cannot drift from the server). If `location_bridge.py`'s real class/method names differ, adapt — the contract is: one code path for both.

- [ ] **Step 3: Rewire `_get_or_create_service` to usbmux-first**

In `scripts/location_bridge.py`, change `_get_or_create_service` so that the direct usbmux attempt happens FIRST and, when it cannot serve an iOS 17+ developer command, falls back to the same no-root userspace tunnel mechanism the CLI uses (from Step 1), then to explicit RSD only when the caller supplied rsd_address/port AND usbmux is absent:

```python
async def _get_or_create_service(
    self, udid, rsd_address, rsd_port, connection_type,
):
    """Get a cached DVT service, usbmux-first (proven lane on iOS 17+),
    then the no-root userspace tunnel, then explicit RSD. Report the
    channel actually opened."""
    if connection_type not in (None, "USB", "Network"):
        raise ValueError("connection_type must be USB or Network")
    cache_key = f"{udid}:{rsd_address}:{rsd_port}:{connection_type}"
    cached = self._service_cache.get(cache_key)
    if cached is not None:
        return (cached["dvt"], cached["location"],
                cached["channel"], cached["endpoint_class"])

    # Lane 1 (proven live 2026-10-31): direct usbmux. On iOS 17+ the
    # library may require a tunnel for developer services; delegate to
    # the SAME fallback mechanism the pymobiledevice3 CLI uses.
    try:
        provider = await self._open_usbmux_with_cli_fallback(udid, connection_type)
        channel, endpoint_class = "usbmuxDirect", "direct"
    except Exception:
        # Lane 2: no-root userspace tunnel (what the CLI fallback does).
        provider = await self._open_usbmux_with_cli_fallback(
            udid, connection_type, force_userspace_tunnel=True)
        channel, endpoint_class = "userspaceRSD", "remoteServiceDiscovery"
    # Lane 3 (unchanged behavior): explicit RSD when the caller supplied it.
    ...
```

Implementer notes: `_open_usbmux_with_cli_fallback` is a NEW method wrapping the CLI-mechanism discovery from Step 1 — do not invent a different tunnel implementation; reuse pymobiledevice3's own (import path recorded in Step 1). The old `_open_preferred_rsd` logic merges into this chain (its `PreferredRsdTunnel` usage is likely exactly the Lane-2 mechanism). Keep eviction-on-error and the cache key unchanged. Preserve the existing response fields (`actual_channel`, `endpoint_class`) — new channel strings (`usbmuxDirect`, `userspaceRSD`) must be handled by the Swift `LocationDVTChannel` decoding (add cases if missing — that is Task 4's Step 2).

- [ ] **Step 4: Run the lane verification against the live device (SUPERVISED)**

```bash
python3_bin="$HOME/Library/Application Support/PathChanger/runtime/location/bin/python3"
timeout 60 "$python3_bin" scripts/verify_bridge_lane.py \
  --udid 00008130-000C5144019A001C --lat 37.7665 --lng -122.4281 --hold 40
```
Expected: `APPLIED …` lines with no exceptions; owner confirms the map moves and holds. Then inspect the journal channel:
```bash
python3 -c "import json;d=json.load(open('$HOME/Library/Application Support/PathChanger/location-helper/helper.json'));print([r.get('actual_channel') for r in d.get('recent_results',[])][-3:])"
```
Expected: the new channel string appears (e.g. `usbmuxDirect` or `userspaceRSD`), never `None` on success.

- [ ] **Step 5: Commit**

```bash
git add scripts/location_bridge.py scripts/verify_bridge_lane.py
git commit -m "fix(bridge): helper dials proven direct-udid lane with CLI-equivalent no-root tunnel fallback"
```

---

### Task 3: DDI mount as device preparation (defect 11, Swift side)

**Files:**
- Modify: `PathChanger/Device/DevicePreparationPlanner.swift` (add DDI commands next to `wifiBootstrapCommands` ~line 14-57)
- Create: `PathChanger/Device/DeveloperDiskImagePreparer.swift`
- Modify: `PathChanger/PathChangerApp.swift` (call the preparer before first injection; ~line 893 `applyPlannedLocation`)
- Test: `Tests/PathChangerTests/DeveloperDiskImagePreparerTests.swift` (new)

- [ ] **Step 1: Write the failing preparer test**

```swift
import XCTest
@testable import PathChanger

final class DeveloperDiskImagePreparerTests: XCTestCase {
    func testMountStatusEmptyArrayMeansNotMounted() async throws {
        let preparer = DeveloperDiskImagePreparer(
            runner: { _ in "[]" })   // fake subprocess runner
        let mounted = try await preparer.isDeveloperDiskImageMounted(udid: "00008130-001234567890ABCD")
        XCTAssertFalse(mounted)
    }

    func testMountStatusWithEntryMeansMounted() async throws {
        let preparer = DeveloperDiskImagePreparer(
            runner: { _ in "[{\"image\":\"DeveloperDiskImage\"}]" })
        let mounted = try await preparer.isDeveloperDiskImageMounted(udid: "00008130-001234567890ABCD")
        XCTAssertTrue(mounted)
    }

    func testEnsureMountedRunsAutoMountWhenNotMounted() async throws {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(runner: { command in
            commands.append(command)
            if command.contains("list") { return "[]" }
            return "DeveloperDiskImage mounted successfully"
        })
        try await preparer.ensureMounted(udid: "00008130-001234567890ABCD")
        XCTAssertTrue(commands.contains { $0.contains("auto-mount") })
    }

    func testEnsureMountedSkipsAutoMountWhenAlreadyMounted() async throws {
        var commands: [[String]] = []
        let preparer = DeveloperDiskImagePreparer(runner: { command in
            commands.append(command)
            if command.contains("list") { return "[{\"image\":\"DeveloperDiskImage\"}]" }
            return ""
        })
        try await preparer.ensureMounted(udid: "00008130-001234567890ABCD")
        XCTAssertFalse(commands.contains { $0.contains("auto-mount") })
    }
}
```

- [ ] **Step 2: Run it — expect FAIL (type does not exist)**

```bash
flowdeck test -w PathChanger.xcodeproj -s PathChanger -D "My Mac" \
  --only PathChangerTests/DeveloperDiskImagePreparerTests
```
Expected: compile FAIL — `DeveloperDiskImagePreparer` not found.

- [ ] **Step 3: Implement the preparer**

Create `PathChanger/Device/DeveloperDiskImagePreparer.swift`:

```swift
import Foundation

/// Ensures the personalized Developer Disk Image is mounted on the device.
/// Live-established 2026-10-31: on iOS 27.2 with no DDI mounted, DVT
/// location injection completes without error but silently does not
/// apply. `mounter auto-mount` fixes it (~30 s incl. cryptex download).
actor DeveloperDiskImagePreparer {
    enum PreparationError: Error {
        case mountFailed(String)
        case statusUnparseable(String)
    }

    private let runner: ([String]) async throws -> String
    private var mountedUDIDs: Set<String> = []

    init(runner: @escaping ([String]) async throws -> String) {
        self.runner = runner
    }

    /// Production runner: managed-runtime python, hardened environment,
    /// 240 s timeout (cryptex download observed ~30 s live).
    static func live() -> DeveloperDiskImagePreparer {
        DeveloperDiskImagePreparer { command in
            try await DeviceManager.shared.runPythonForPreparation(
                arguments: command, timeout: 240)
        }
    }

    private func mounterCommand(_ subcommand: String, udid: String) -> [String] {
        ["-m", "pymobiledevice3", "mounter", subcommand, "--udid", udid]
    }

    func isDeveloperDiskImageMounted(udid: String) async throws -> Bool {
        if mountedUDIDs.contains(udid) { return true }
        let output = try await runner(mounterCommand("list", udid: udid))
        guard let data = output.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw PreparationError.statusUnparseable(String(output.prefix(200)))
        }
        return !entries.isEmpty
    }

    func ensureMounted(udid: String) async throws {
        guard try await !isDeveloperDiskImageMounted(udid: udid) else { return }
        let output = try await runner(mounterCommand("auto-mount", udid: udid))
        guard output.contains("mounted successfully") else {
            throw PreparationError.mountFailed(String(output.suffix(300)))
        }
        mountedUDIDs.insert(udid)
    }
}
```

Add to `DevicePreparationPlanner.swift` (next to `wifiBootstrapCommands`) so the commands are documented in one place:

```swift
/// `mounter auto-mount` mounts the personalized Developer Disk Image —
/// required for DVT location injection on iOS 17+; silently missing on
/// CLI-only devices (live root cause 2026-10-31).
static func ddiMountStatusCommand(udid: String) -> [String] {
    ["-m", "pymobiledevice3", "mounter", "list", "--udid", udid]
}
static func ddiMountCommand(udid: String) -> [String] {
    ["-m", "pymobiledevice3", "mounter", "auto-mount", "--udid", udid]
}
```

Implementer notes: `DeviceManager.runPythonForPreparation` may not exist — reuse the existing hardened `runPython(arguments:timeout:)` (`DeviceManager.swift:1502`) via whatever internal accessor is idiomatic; the runner abstraction exists so tests inject a fake. If a public shared instance is not idiomatic, make `live()` take the manager explicitly. Do not weaken `ProcessEnvironment.configured()` usage.

- [ ] **Step 4: Run the focused tests — expect PASS**

```bash
flowdeck test -w PathChanger.xcodeproj -s PathChanger -D "My Mac" \
  --only PathChangerTests/DeveloperDiskImagePreparerTests
```

- [ ] **Step 5: Wire it into the injection path**

In `PathChanger/PathChangerApp.swift`, at the top of `applyPlannedLocation` (~line 893), before any bridge work:

```swift
do {
    try await ddiPreparer.ensureMounted(udid: device.id)
} catch {
    Logger.error("[Preparation] DDI mount failed: \(error)", category: .device)
    // Surface as an honest failed receipt via the existing error mapping
    // used for injection failures (connection-loss classification must
    // NOT swallow this: it is a preparation failure, not a lost tunnel).
    throw error
}
```

`ddiPreparer` is a stored `DeveloperDiskImagePreparer.live()` on `AppState` (composition root — one instance). If the surrounding function cannot `throw`, map to the existing failure-receipt path used by `LocationSessionCoordinator.reject`. Keep the three-dimension model: this is a device-readiness fact, not a connection fact.

- [ ] **Step 6: Run the full suite; commit**

```bash
flowdeck test -w PathChanger.xcodeproj -s PathChanger -D "My Mac"
git add PathChanger/Device/DevicePreparationPlanner.swift PathChanger/Device/DeveloperDiskImagePreparer.swift PathChanger/PathChangerApp.swift Tests/PathChangerTests/DeveloperDiskImagePreparerTests.swift
git commit -m "feat(preparation): mount Developer Disk Image before injection; honest failure on mount errors"
```

---

### Task 4: Swift-side lane plumbing — new channel cases + generation-keyed RSD guard (defects 12/5, Swift side)

**Files:**
- Modify: `PathChanger/Models/LocationSessionState.swift` (`LocationDVTChannel` — add `usbmuxDirect`/`userspaceRSD` cases if missing)
- Modify: `PathChanger/Device/PersistentLocationBridge.swift` (`setLocation`/`clearLocation` request build ~line 1144-1166: drop stale RSD when the tunnel generation changed)
- Modify: `PathChanger/Device/TunneldManager.swift` (expose the running tunnel's PID on `TunnelInfo` if not already present)
- Test: `Tests/PathChangerTests/PersistentLocationBridgeTests.swift` (append), `Tests/PathChangerTests/TunneldManagerTests.swift` (append)

- [ ] **Step 1: Write the failing stale-RSD guard test**

```swift
func testSetLocationInvalidatesSessionWhenTunnelProcessChanges() async throws {
    // The 2026-10-24 live incident: after Reconnect replaced the tunnel
    // process, the bridge kept dialing the previous tunnel's RSD endpoint.
    // The guard: a cached tunnel-transport session whose tunnel PID no
    // longer matches the live tunnel is stale and must not be reused.
    // (Construct via the existing test scaffolding for bridge sessions;
    // assert currentSession is invalidated / usesTunnelTransport reset
    // when the injected TunneldManager reports a different tunnel PID.)
    // Full body mirrors the existing session-state tests in this file —
    // reuse their fixtures for identity construction.
}
```

Implementer notes: this test MUST be written against the real guard implemented in Step 3 — the assertion is "a changed tunnel PID invalidates the cached tunnel session before the request is built". If the existing scaffolding has no injectable tunnel-info source, extend the fake (pattern: `Fakes/` directory) rather than reaching into singletons.

- [ ] **Step 2: Add the new channel cases**

In `LocationDVTChannel` (search `LocationSessionState.swift`), add:

```swift
case usbmuxDirect
case userspaceRSD
```
if not present (`explicitRSD`, `nativeRSD`, `userspaceRSD`, `networkLockdown`, `usbLockdown` are the Python-side strings — align exactly with `location_bridge.py` channel values after Task 2).

- [ ] **Step 3: Implement the generation-keyed guard**

In `PersistentLocationBridge` (`setLocation`/`clearLocation` request build), before `request.rsd_address = rsdInfo?.rsdAddress`:

```swift
let liveTunnelPID = rsdInfo?.tunnelPID
if usesTunnelTransport, let current = currentSession,
   current.transport == .wifi || usesTunnelTransport,
   liveTunnelPID != cachedTunnelPID {
    // Tunnel process was replaced (reconnect/relaunch): the cached RSD
    // endpoint belongs to a dead tunnel. Live root cause 2026-10-24/31.
    Logger.warning("[PersistentBridge] Tunnel PID changed \(String(describing: cachedTunnelPID)) -> \(String(describing: liveTunnelPID)); invalidating stale RSD session", category: .device)
    currentSession = nil
    usesTunnelTransport = false
}
cachedTunnelPID = liveTunnelPID
```
with `private var cachedTunnelPID: pid_t?` state, and `TunnelInfo` gains `let tunnelPID: pid_t?` populated where `TunneldManager` parses RSD info (it knows the launched process PID; pgrep-adopted tunnels carry their PID from adoption). Prefer direct-usbmux first in the request: only set `rsd_address`/`rsd_port` when the device is NOT usbmux-visible (the helper now handles both; sending RSD unconditionally re-introduces the fragile lane).

- [ ] **Step 4: Run focused tests, then the full suite — commit**

```bash
flowdeck test -w PathChanger.xcodeproj -s PathChanger -D "My Mac" \
  --only PathChangerTests/PersistentLocationBridgeTests
flowdeck test -w PathChanger.xcodeproj -s PathChanger -D "My Mac"
git add PathChanger/Models/LocationSessionState.swift PathChanger/Device/PersistentLocationBridge.swift PathChanger/Device/TunneldManager.swift Tests/PathChangerTests/PersistentLocationBridgeTests.swift Tests/PathChangerTests/TunneldManagerTests.swift
git commit -m "fix(device): generation-keyed RSD guard kills stale tunnel endpoints; new channel cases for proven lanes"
```

---

### Task 5: Full gates + supervised GUI acceptance (Stage-1 exit gate)

**Files:** none (verification + evidence)

- [ ] **Step 1: Full gates**

```bash
flowdeck build -w PathChanger.xcodeproj -s PathChanger -D "My Mac"
flowdeck build -w PathChanger.xcodeproj -s PathChanger -C Release -D "My Mac" 2>/dev/null || flowdeck build -w PathChanger.xcodeproj -s PathChanger -D "My Mac" -C Release
flowdeck test -w PathChanger.xcodeproj -s PathChanger -D "My Mac"
```
Expected: Debug + Release green; suite green with count ≥ baseline (Task 0) plus the new tests; state any delta.

- [ ] **Step 2: Supervised GUI acceptance (owner present, phone unlocked, Auto-Lock Never, Wi-Fi)**

1. Launch the freshly built app (worktree build product; record path + sha256).
2. Select the phone (Wi-Fi transport), start tunnel through the GUI.
3. Teleport → target from Recent history → Move.
4. Owner observes: map on the phone moves to the target AND holds ≥ 3 minutes.
5. Press Clear → owner observes return to real GPS.
6. Capture: helper journal channel values, app logs (FileLogger now non-empty), fd counts before/after.

- [ ] **Step 3: Record evidence; request owner commit/promotion approval**

Report with acceptance language; the gate is the owner's observed map movement through the GUI.

---

## Self-review notes (writing-plans checklist)

- Spec coverage: Stage-1 scope = spec §6 Stage 1 (defects 1, 11, 12/5) — Tasks 1-4; Stage-1 gate = Task 5. Stages 2-3 have their own plans after this gate.
- Placeholders: Task 4 Step 1's test body is deliberately scaffolded with an explicit assertion contract (the implementer completes against real scaffolding) — the only such case, flagged inline.
- Type consistency: `DeveloperDiskImagePreparer` names match across Tasks 3 steps; `LocationDVTChannel` case strings align with `location_bridge.py` channel values (Task 2 Step 3 note + Task 4 Step 2 cross-reference).
