# PathChanger Product Requirements

> **Status:** Owner-approved product contract under the authorized five-mode persistence implementation plan. This document defines required behavior and acceptance outcomes that are binding for all engineering decisions. It does not itself authorize privileged commands or physical-device mutation. The owner separately authorized execution of the implementation plan and all Git operations explicitly named by it; the plan’s reserved human gates remain binding.

## 1. Product objective and priority

PathChanger must be a reliable, integrated location-spoofing application, not merely a redesigned interface. The system must behave as one path:

**GUI → application state → pymobiledevice3 adapter → connection layer → iOS device → spoofed location**

Priorities, in order:

1. Reliability
2. Correct functionality
3. Truthful state synchronization
4. Connection stability and recovery
5. GUI consistency

The primary success condition is:

> After PathChanger successfully applies a spoofed location, the device remains at that location until the user explicitly changes or clears it, or until an external platform limitation makes continued spoofing impossible and the application reports that loss honestly.

## 2. Scope and terminology

### 2.1 Required user modes

The product has exactly five primary user modes:

1. Teleport
2. Jump Teleport, shown as **Jump** in the current GUI
3. Two-Spot Mode
4. Multi-Spot Mode
5. Joystick

The implementation may reuse shared technical engines. Jump may use discrete teleport operations, and Two-Spot/Multi-Spot may share route playback. Shared implementation does not reduce the requirement for separate behavior contracts and end-to-end tests for all five user modes.

### 2.2 Canonical dependency name

The Python dependency is `pymobiledevice3`. “PyMobile3” in informal discussion means `pymobiledevice3`; source, documentation, logs, and tests should use the canonical name.

### 2.3 Location terms

- **Desired location:** the coordinate the user most recently asked PathChanger to maintain.
- **Acknowledged location:** the latest coordinate for which the device adapter returned success.
- **Spoof session:** the retained process/service/session that keeps iOS simulated location active.
- **Movement:** repeated coordinate updates used by routes or joystick control.
- **Hold:** stop movement while keeping the latest spoofed coordinate active.
- **Clear/Reset:** the explicit user action that ends spoofing and allows the device to return to real GPS.
- **Uncertain:** PathChanger has lost enough connection/session evidence that it cannot honestly claim the desired location is still active.

## 3. Five mode contracts

### 3.1 Teleport

- The user selects one valid coordinate and explicitly applies it.
- The GUI must not report active spoofing until injection succeeds.
- After success, PathChanger must retain the spoof session and hold that coordinate.
- Selecting another coordinate replaces the desired location only after the new injection succeeds.
- A cooldown may delay a request only if the GUI clearly reports that no injection occurred. It must not mark the mode active, advance history, or silently ignore the request.
- Only explicit Clear/Reset may intentionally return the device to real GPS.

### 3.2 Jump Teleport

- The user creates an ordered list of discrete destinations.
- Each explicit Move action applies exactly one next destination.
- The jump index advances only after successful injection.
- The most recently successful jump remains active while waiting for the next action.
- Reaching the final destination holds that destination; it does not clear spoofing.
- Cooldown behavior, if retained, must never create a false successful jump or a false active state.

### 3.3 Two-Spot Mode

- The user defines exactly two effective endpoints.
- Starting movement traverses from the start/current point to the destination using the selected speed.
- Pause holds the latest successfully applied coordinate.
- Stop ends movement but holds the latest successfully applied coordinate.
- Normal completion holds the destination.
- Looping, if enabled, repeats between the endpoints without clearing location between cycles.
- Clear/Reset is separate from Pause, Stop, and completion.

### 3.4 Multi-Spot Mode

- The user defines an ordered route containing at least two valid waypoints.
- Starting movement traverses the complete ordered route.
- Pause and resume continue from the current progress without resetting location.
- Stop ends movement but holds the latest successfully applied coordinate.
- Normal completion holds the final waypoint.
- Looping restarts from the defined route policy without returning to real GPS between loops.
- Route progress may advance only for acknowledged coordinate updates.

### 3.5 Joystick

- The user establishes a valid starting location before movement.
- Engaging the joystick applies movement updates from the latest acknowledged coordinate.
- Releasing/disengaging the joystick stops movement and holds the latest successfully applied coordinate.
- Pause holds the current coordinate; resume continues from it.
- Connection loss must stop movement immediately, preserve the desired coordinate, and enter an uncertain/reconnecting state.
- Successful recovery must reapply the last desired coordinate before movement can resume.
- Clear/Reset is the only normal action that intentionally returns the device to real GPS.

## 4. State model and GUI truth

Connection, spoofing, and movement are different state dimensions and must not be collapsed into one Boolean.

### 4.1 Connection state

At minimum, represent:

- unavailable
- discovering
- ready
- reconnecting
- error

USB/Wi-Fi visibility, pymobiledevice3 service availability, and tunnel/RSD health are separate facts. One source reporting a device does not prove another source has a usable location-injection channel.

### 4.2 Location application state

At minimum, represent:

- idle
- applying
- active
- uncertain
- lost
- clearing
- error

“Active” means the latest injection was acknowledged and the required retained session/connection is currently healthy. If iOS or pymobiledevice3 provides no authoritative location readback, the GUI must explain the narrower evidence instead of claiming direct device-location proof.

### 4.3 Movement state

At minimum, represent:

- idle
- running
- paused
- completed
- error

Movement may be idle, paused, or completed while the spoofed location remains active.

### 4.4 Required synchronization rules

- Never report spoofing before injection succeeds.
- Never report connected solely because a stale device entry exists.
- Never report a mode as running after its worker/task/session has ended.
- On transport/session loss, immediately stop movement and mark location state uncertain or lost.
- After recovery, report active only after rebuilding the required session and successfully reapplying the desired coordinate.
- Preserve the last desired coordinate separately from the last acknowledged coordinate.

## 5. Persistence, hold, stop, and clear

### 5.1 Default persistence

A successful spoof must persist during normal operation. The application must not intentionally call `clear_location`, terminate the process that keeps simulated location alive, or discard the desired coordinate merely because:

- movement completed;
- movement was paused or stopped;
- the joystick was released;
- the user changed modes;
- a cooldown began;
- the GUI was minimized;
- a temporary USB or Wi-Fi interruption occurred;
- a tunnel health check failed and recovery remains possible.

### 5.2 Explicit reset boundary

Returning to real GPS is a distinct, destructive product action. It requires an explicit Clear/Reset command or an unavoidable external event such as device reboot or platform termination of the simulation service.

Pause, Stop Movement, Disconnect Transport, Stop Tunnel, and Clear Location must not be presented as equivalent operations. If stopping a tunnel necessarily ends a tunnel-backed spoof session, the GUI must warn that location persistence will be lost and must update state truthfully after the stop.

### 5.3 App termination and relaunch

The application must not promise persistence across app termination unless the underlying retained service is proven to survive. On relaunch, PathChanger may discover/adopt an existing session or offer to reapply the previous desired location, but it must not silently claim active spoofing from stored UI state alone.

## 6. Safe Mode and cooldown

Safe Mode and cooldown are not primary product modes. Their existence must be justified by measured safety or platform constraints.

Current disposition:

- They must not clear location, terminate the spoof session, or return the device to real GPS.
- They must not change the requested coordinate through random drift unless the user explicitly enables and understands that behavior.
- They must not silently reject an injection after the GUI has declared simulation active.
- They must default to off until their behavior is tested across all five modes and both transports.
- If retained, cooldown is a transparent request-throttling policy, not a location-reset policy.
- If these constraints cannot be met cleanly, remove the user-facing Safe Mode/cooldown features rather than layering workarounds over the core modes.

## 7. USB and Wi-Fi transport requirements

### 7.1 Shared requirements

- Both transports must expose truthful readiness, injection, and recovery state.
- Device entries must be deduplicated by stable identity while retaining per-transport facts.
- The transport selected for a command must be recorded in diagnostics.
- A successful injection response must identify which transport/session accepted it.
- Each acknowledgement must produce a structured receipt containing the stable device identity, selected transport/channel, session generation or endpoint class, request identity, requested coordinate, completion time, and result; redact sensitive identifiers in diagnostics.
- A receipt from an older session generation cannot prove that spoofing remains active after reconnect or failover.
- Transport switching must not clear the desired or acknowledged coordinate.

### 7.2 USB

- USB should be preferred when it is healthy and supports the required developer service.
- Cable removal must stop movement, preserve desired location, and mark the applied state uncertain if session health is lost.
- Reconnection must rediscover the same device, rebuild the service/session, and reapply the desired coordinate before reporting active.
- No stale USB flag may override live service failure.

### 7.3 Wi-Fi

- Temporary Wi-Fi loss must enter reconnecting/uncertain state without intentionally clearing location.
- Recovery must use bounded retries/backoff and remain cancelable.
- After reconnection, rebuild pymobiledevice3/tunnel state as required and reapply the desired coordinate.
- If recovery is exhausted, report lost/error honestly and retain the desired coordinate for an explicit retry.
- Wi-Fi availability must not be inferred from a paired placeholder alone.

### 7.4 Transport failover

Automatic USB/Wi-Fi failover is allowed only when it preserves identity and desired state. A failover is successful only after the new channel acknowledges reapplication of the desired coordinate. Until then, the GUI reports reconnecting or uncertain, never active.

## 8. pymobiledevice3 and connection-layer contract

- Centralize location injection, clear, session retention, and connection-error translation behind one application-facing adapter boundary.
- Do not scatter direct pymobiledevice3 subprocess/service decisions through GUI or mode code.
- Serialize persistent bridge requests unless a tested request-ID protocol proves concurrent correctness.
- Bridge process termination must notify the application state owner.
- Invalidate stale service caches after connection errors.
- Reconnection must rebuild the service and reapply desired state; refreshing a device list alone is insufficient.
- Rate limiting must never report a queued/dropped coordinate as applied.
- Route progress and jump indices advance only after acknowledged injection.
- Preserve structured diagnostic context without leaking UDIDs, personal device names, home paths, credentials, or license identifiers.

## 9. Previous working build as reference

The previous working build is a behavioral reference, not automatically a source-code authority.

Before copying old code:

1. Identify the exact artifact, branch, tag, commit, or external source.
2. Reproduce its behavior on an authorized device and record the evidence.
3. Compare behavior at the GUI, application-state, pymobiledevice3, transport, and device levels.
4. Extract the smallest proven mechanism responsible for persistence or recovery.
5. Port that mechanism into the current architecture with current security and testing requirements.

Current Git history does not identify a separate five-mode known-good implementation. Do not invent one. If the prior working artifact cannot be tied to source, use it only as a black-box behavioral oracle.

## 10. Required test matrix

Each user mode must pass the complete workflow on both USB and Wi-Fi.

| Mode | USB | Wi-Fi | Required terminal behavior |
|---|---|---|---|
| Teleport | Required | Required | Selected coordinate remains held |
| Jump Teleport | Required | Required | Each acknowledged hop remains held until the next hop |
| Two-Spot | Required | Required | Destination remains held after completion/stop |
| Multi-Spot | Required | Required | Final acknowledged waypoint remains held after completion/stop |
| Joystick | Required | Required | Last acknowledged coordinate remains held after disengage |

For each of these ten mode/transport combinations, verify:

1. Mode selection
2. Device and transport readiness
3. Location application
4. Acknowledgement and truthful GUI state
5. Persistence during an observation window defined by the active test plan
6. Mode-specific movement/action
7. Temporary connection interruption
8. Reconnection and desired-location reapplication
9. Final location/session state
10. Explicit Clear/Reset behavior

### 10.1 Failure scenarios

Test at minimum:

- Wi-Fi disappears and returns.
- USB cable disconnects and reconnects.
- Tunnel/RSD health is lost.
- The persistent Python bridge exits unexpectedly.
- A location update is rate-limited or queued.
- A route update fails mid-route.
- The application is paused/minimized during spoofing.
- The user changes mode while holding a spoofed location.
- Clear/Reset fails after a connection change.

### 10.2 Test layers

1. Deterministic unit tests for planners, state transitions, cooldown decisions, route progress, and reapply policy.
2. Adapter tests with deterministic fake pymobiledevice3/session responses.
3. Integration tests for bridge process lifecycle and reconnection.
4. FlowDeck build and automated test execution.
5. FlowDeck-driven GUI verification through the real controls.
6. Explicitly authorized physical-device tests for the ten USB/Wi-Fi workflows.

A UI-only test is insufficient. A successful subprocess without matching GUI truth is also insufficient.

## 11. Product acceptance criteria

The core product is not complete until all of the following are true:

- All five user modes pass their separate contracts.
- All ten mode/transport paths are evidenced on supported hardware.
- Successful spoofing remains active through the required persistence window.
- Pause, movement stop, completion, and mode changes do not clear location.
- Explicit Clear/Reset reliably ends spoofing and updates state.
- Temporary connection loss produces reconnecting/uncertain state, not false active state.
- Successful recovery reapplies desired location before active state returns.
- Exhausted recovery reports failure without erasing the desired coordinate.
- GUI, application state, pymobiledevice3 state, connection health, and known device behavior agree within the limits of available readback.
- No accepted fix depends on an unexplained workaround, swallowed error, or false success state.

## 12. Implementation order

Use this dependency order unless an accepted governance contract narrows it further:

1. Define the independent connection, location-application, and movement state models.
2. Add regression tests for the known false-active and unintended-clear paths.
3. Make adapter/session termination and transport loss observable by the state owner.
4. Implement desired-location preservation and idempotent reapply after recovery.
5. Correct Teleport and Jump success/index semantics.
6. Correct Two-Spot and Multi-Spot completion, pause, stop, and progress semantics.
7. Correct Joystick disengage, interruption, and resume semantics.
8. Reevaluate or remove Safe Mode, random drift, and cooldown behavior.
9. Verify USB and Wi-Fi interruption/recovery end to end.
10. Align all GUI labels and indicators with the verified state model.

Do not fix GUI truth by hiding underlying connection or injection failures.

## 13. Current-code evidence motivating these requirements

These references describe the baseline inspected when this document was written; line numbers may move and must be re-resolved before implementation.

- `PathChanger/UI/ContentView.swift:12-22` defines the five user modes.
- `PathChanger/Simulation/SimulationPlanner.swift:25-40` maps them onto teleport, route, and joystick plans.
- `PathChanger/PathChangerApp.swift:520-556` can mark simulation active before injection and clears location during Stop.
- `PathChanger/Core/StateManagers/SimulationStateManager.swift:158-215` can reject a teleport during cooldown after higher-level state has already changed.
- `PathChanger/PathChangerApp.swift:355-366` stops tunnel-dependent sessions when tunnel state becomes inactive without synchronizing simulation truth.
- `PathChanger/PathChangerApp.swift:675-710` completes route movement without a distinct completed-versus-held state.
- `PathChanger/PathChangerApp.swift:731-773` disengages joystick while leaving held-location behavior separate from GUI activity.
- `PathChanger/Device/DevLocationBridge.swift:353-374` shows that terminating a held DVT session can end persistence.
- `PathChanger/Device/DevLocationBridge.swift:409-505` falls back between persistent and subprocess paths and may queue rate-limited requests.
- `PathChanger/Device/PersistentLocationBridge.swift:409-424` cleans up after bridge termination without a direct simulation-state callback.
- `PathChanger/Core/StateManagers/DeviceStateManager.swift:150-175` reconnects by refreshing devices/readiness, not by reapplying desired location.
- `PathChanger/Device/TunnelStateMachine.swift:623-670` enters an honest error state after tunnel health/process loss and requires explicit privileged restart.
- `scripts/location_bridge.py:76-132` caches pymobiledevice3 services and invalidates them on error but does not own application recovery state.

## 14. Engineering autonomy and required human gates

### 14.1 Proceed without routine confirmation

Within an explicitly approved task scope, agents should independently:

- inspect code and history;
- choose routine implementation details consistent with architecture;
- write tests and minimal fixes;
- run non-destructive builds, tests, and background GUI verification;
- use subagents for independent investigations and reviews;
- update plans and task tracking;
- fix ordinary defects discovered within the active scope;
- report meaningful results at phase or gate boundaries rather than after every file edit.

Do not invent extra approval steps beyond the active governance contract.

### 14.2 Confirmation remains mandatory

Ask before:

- destructive Git operations or discarding existing work;
- commit, push, merge, tag, or branch deletion unless the user explicitly authorized that exact action;
- privileged/elevated commands or administrator prompts;
- tunnel start/stop or physical-device mutation when not already explicitly authorized by the active test plan;
- location injection on a real device when not already explicitly authorized;
- payment, account, license, or credential actions;
- foreground automation that takes control of the user’s desktop;
- scope expansion beyond an accepted governance contract;
- accepting a gate or making an accountable human decision.

Human review is a safety boundary, not a substitute for routine engineering judgment.

## 15. Non-goals

- Do not preserve Safe Mode/cooldown merely because the current UI contains them.
- Do not declare success from UI selection alone.
- Do not treat device discovery as proof of an injection-ready channel.
- Do not clear location as a generic cleanup response.
- Do not copy an old implementation without proving its behavior and compatibility.
- Do not trade truthful state for optimistic status text.
- Do not make release/signing/packaging claims from a development-only artifact.
