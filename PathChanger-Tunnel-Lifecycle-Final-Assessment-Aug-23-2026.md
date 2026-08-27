PathChanger Tunnel Lifecycle — Final Assessment

Executive assessment

PathChanger has a viable product foundation and substantial working functionality, but the tunnel subsystem is not yet production-safe or end-to-end certified.

Current status

•  Build stability: passing
•  Automated regression baseline: 857 tests, 0 failures, 10 expected skips
•  Release compilation: passing
•  Device deduplication: verified live; four raw records collapse to one canonical device
•  Tunnel-button readiness conflation: corrected
•  Infinite Connecting loop: corrected; failed starts now reach a stable error state
•  Wi‑Fi tunnel establishment: not yet successful
•  USB tunnel: not yet physically certified
•  Failover: not implemented
•  All five modes over USB/Wi‑Fi: not certified
•  Privileged tunnel security: not production-safe
•  Persistent bridge reliability: contains critical concurrency defects

The project is stabilized enough for structured remediation, but it should not be treated as shippable or fully functional yet.

Principal architectural cause

Device identity, transport readiness, process existence, endpoint availability, tunnel lifecycle, and GUI status are published by different layers as overlapping versions of “connection truth.”

This caused both confirmed GUI failures:

•  one phone appearing as four devices,
•  transport readiness replacing the Start Tunnel action.

The immediate faulty lines differed, but both defects came from source-specific observations being treated as canonical application state.

Principal security cause

The current privileged tunnel path executes the resolver-selected Homebrew Python interpreter and pymobiledevice3 package tree as root.

Verified runtime:

•  Python: /opt/homebrew/bin/python3.13
•  Version: 3.13.15
•  pymobiledevice3: 10.7.4
•  Package tree: /opt/homebrew/lib/python3.13/site-packages
•  Default remote-tunnel protocol: TCP

The Homebrew interpreter, symlink, prefix, and package tree are user-owned. Administrator approval therefore promotes mutable user-owned Python code to root execution.

Principal reliability cause

The lifecycle has a state machine, but its asynchronous effects, process callbacks, endpoint polling, health monitoring, and persistent bridge requests do not share an attempt/session generation identity or serialized execution model.

The persistent bridge additionally contains two critical defects:

•  its ready wait can resume a checked continuation twice,
•  concurrent requests overwrite a single stored pending continuation.



Verified strengths

The audit confirmed several sound foundations:

•  Strict allowlisting of privileged tunnel commands
•  Validated UDID suffixes
•  Coordinate, port, and command-structure validation
•  Restricted subprocess PATH and removal of Python override variables
•  Output-size limits
•  PID tracking rather than unrestricted pkill
•  Formal tunnel transition model
•  Stable terminal error after failed tunnel startup
•  No active state with an empty endpoint or port zero
•  Direct/tunnel-dependent held-session classification
•  Separate route and joystick queue strategies
•  Exact Sparkle dependency pin
•  Test-host detection that prevents privileged startup during tests
•  Canonical device reconciliation before GUI publication

These should be retained while the unsafe and duplicated components are replaced.



Phase results

Phase 0 — Architecture comprehension

Delivered in:

•  Architecture-Note-Aug-23-2026.md

Results

The active GUI and its control paths were mapped from SwiftUI to device processes.

The current active UI consists of:

•  PathChangerApp
•  ContentView
•  OrganicTitleBar
•  SimulationView
•  ModeContextCard
•  OrganicSettingsSheet

Compiled but unmounted alternate UI remains:

•  SidebarView
•  DeviceListView
•  InspectorPanel
•  FloatingControlPanel

These dormant views contain alternate connection and simulation interpretations, creating future wiring ambiguity.

Device discovery findings

Four enumeration paths were identified:

1. usbmux
2. Bonjour mobdev2
3. tunneld HTTP API
4. RemotePairing record files

The four-device bug was caused by the same phone being published as:

•  one UDID record,
•  one IPv4 record,
•  two IPv6 records.

The post-discovery canonicalization now collapses these to one device, but the long-term model still needs one canonical identity at ingestion rather than post-merge repair.

State-divergence findings

Eleven divergence points were recorded, including:

•  three tunnel-running representations,
•  direct readiness conflicting with tunnel state,
•  one Device.connectionType unable to represent both transports,
•  selection being treated as connection,
•  direct Wi‑Fi allowed by one layer but rejected by another,
•  status text disagreeing with readiness,
•  active transport being inferred rather than observed,
•  multiple error/status writers,
•  active and dormant simulation implementations,
•  label-only settings,
•  duplicate settings systems.

Phase 0 conclusion

The root-cause hypothesis was confirmed: source-specific state is being treated as canonical truth.



Phase 1 — Tunnel lifecycle architecture

Delivered in:

•  Tunnel-Lifecycle-Architecture-Aug-23-2026.md

Current lifecycle mapped

The following flows were documented:

•  explicit start
•  external-process adoption
•  endpoint acquisition
•  active monitoring
•  health failure
•  stop/teardown
•  app relaunch
•  direct transport without an external tunnel

Current core components

•  TunnelStateMachine
•  TunneldManager
•  TunnelHealthMonitor
•  DeviceManager
•  DeviceStateManager
•  PrivilegedTunnelCommand
•  DevLocationBridge
•  PersistentLocationBridge

Required independent states

Transport readiness:

•  none
•  USB ready
•  Wi‑Fi ready
•  both ready

Tunnel lifecycle:

•  idle
•  starting
•  active
•  degraded
•  reconnecting
•  failed
•  stopping

Required canonical artifacts

•  CanonicalDeviceID
•  TransportReadinessSnapshot
•  TunnelAttempt
•  TunnelSession
•  TunnelHealthObservation
•  DeviceSessionRoute
•  TeardownReport

Phase 1 conclusion

TunnelStateMachine nominally owns lifecycle state, but process existence, endpoints, readiness, copied running status, and GUI projection remain distributed across multiple components.

The lifecycle requires one generation-scoped controller and an entirely separate readiness store.



Phase 2 — Dependencies and integrations

Delivered in:

•  Tunnel-Dependencies-Integrations-Audit-Aug-23-2026.md

Verified dependencies

•  macOS 14+
•  Swift 5.9
•  Sparkle 2.8.1
•  Homebrew Python 3.13.15
•  pymobiledevice3 10.7.4
•  usbmuxd / lockdownd
•  RemotePairing
•  Bonjour
•  RemoteXPC
•  TUN/TAP
•  NSAppleScript administrator authorization
•  local tunneld API at 127.0.0.1:49151

Major dependency findings

•  Declared pymobiledevice3 minimum 6.1.5 does not match modern 10.x APIs the code assumes.
•  GUI installs unpinned latest pymobiledevice3.
•  Full transitive Python graph is uncontrolled.
•  Default protocol changes with Python version.
•  Current Python 3.13 selects TCP; Apple Python 3.9 would select QUIC.
•  Human-formatted tunnel output is parsed despite supported --script-mode.
•  Daemon API is queried during one-shot modes where it should not exist.
•  location_bridge.py is not a consistent Swift/Xcode resource.
•  Manual packaging and development builds use different bridge-resource paths.
•  build-app-bundle.sh overwrites /Applications/PathChanger.app and removes other dev artifacts.

Userspace-tunnel finding

Current pymobiledevice3 supports automatic no-root userspace tunnels for iOS 17.4+ developer commands.

Implications:

•  one-shot Teleport may not require a privileged external tunnel,
•  persistent route/joystick mode currently does not implement UserspaceRsdTunnel,
•  standard and performance modes have different hidden connection requirements.

Phase 2 conclusion

Validation, installation, discovery, privileged launch, and persistent bridge execution are not guaranteed to use one immutable, tested dependency identity.



Phase 3 — Functional modules and data flows

Delivered in:

•  Tunnel-Functional-Modules-Data-Flows-Aug-23-2026.md

Functional modules

Thirteen modules were defined:

1. Canonical device target resolution
2. Transport readiness observation
3. Runtime capability preflight
4. Tunnel strategy selection
5. Lifecycle state kernel
6. Privileged process adapter
7. Endpoint acquisition
8. Session publication
9. Health observation
10. Adoption/reconciliation
11. Teardown
12. Device-session routing
13. GUI projection

Data flows documented

•  USB one-shot tunnel
•  Wi‑Fi one-shot tunnel
•  daemon tunneld
•  direct userspace route
•  persistent high-frequency bridge
•  relaunch adoption
•  health degradation
•  explicit stop
•  failure classification and GUI propagation

Confirmed daemon-mode mismatch

One-shot mode succeeds by producing one RSD host/port.

Daemon mode succeeds by:

•  providing a live HTTP API,
•  discovering the target UDID,
•  providing a per-device route.

Current startup logic expects the one-shot endpoint model for both.

TunneldManager.queryTunneldAPI() also does not populate its declared per-device tunnel cache, so the daemon integration is incomplete.

Phase 3 conclusion

The code needs three explicit seams:

•  lifecycle
•  transport readiness
•  session routing

Simulation state must remain independent of all three.



Phase 4 — Security and reliability

Delivered in:

•  Tunnel-Security-Reliability-Audit-Aug-23-2026.md

Critical security findings

User-owned Python executes as root

The privileged path elevates mutable Homebrew Python and packages.

Status: release blocker.

Root log redirection is raceable

Root opens a user-controlled tunnel.log path after a user-side remove/create sequence.

There is no no-follow descriptor or helper-owned output pipe.

Status: release blocker.

Root stop trusts numeric PIDs

Tracked PIDs are killed as root without verifying:

•  executable
•  owner
•  arguments
•  start time
•  attempt generation

PID reuse could target an unrelated process.

Status: release blocker.

Pairing record permissions are too broad

Verified:

•  directory 0755
•  records 0644

These files should be treated as secrets.

Unpinned packages later execute with privilege

The runtime dependency installer can change privileged code without a PathChanger release.



Critical reliability findings

Persistent bridge continuation race

waitForReady() can resume its checked continuation twice after cancellation.

Persistent bridge request corruption

Only one pendingContinuation exists. Concurrent requests overwrite one another.

Lifecycle effects are not serialized

Each state transition starts an independent effect task. Actions from adjacent transitions can interleave.

No attempt/session generation identity

Stale launch, endpoint, adoption, health, or cleanup callbacks are not structurally rejected.

Pipe deadlock exposure

Several process paths wait for child exit before draining output. A full pipe can block both sides before output limits run.

Health checks do not test tunnel health

Current health is based on:

•  endpoint object presence
•  /bin/ps -p PID

The reported latency is local process lookup latency, not RSD/DVT latency.

Degraded/reconnecting are not real lifecycle states

The monitor can report degradation while lifecycle remains running, then jumps directly to error.

Tests miss critical behavior

The green suite does not exercise:

•  exact-once continuation behavior
•  concurrent bridge request correlation
•  stale generation rejection
•  symlink-safe output
•  PID reuse
•  daemon startup model
•  endpoint health
•  teardown resource proof



Current release posture

Approved for

•  continued development
•  architecture consolidation
•  deterministic unit testing
•  controlled unprivileged userspace experiments
•  isolated dev-app GUI testing

Not approved for

•  production privileged tunneling
•  signed public release
•  unattended tunnel recovery
•  USB/Wi‑Fi failover certification
•  claims that all five modes work
•  claims that tunnel health or latency is measured correctly



Target architecture

Transport readiness store

Owns only:

•  canonical device ID
•  USB availability
•  Wi‑Fi availability
•  same-network state
•  fallback availability
•  observation timestamps

It never publishes tunnel-active state.

Tunnel lifecycle controller

Owns only:

•  idle
•  starting
•  active
•  degraded
•  reconnecting
•  failed
•  stopping

It also owns:

•  attempt generation
•  active session
•  typed failures
•  bounded retry state

Process adapter

Performs:

•  verified launch
•  PID/process identity capture
•  typed exit events
•  secure output collection

It exposes no GUI state.

Endpoint resolver

Separately validates:

•  one-shot script-mode host/port
•  daemon API and per-device route

Health probe

Measures:

•  process health
•  endpoint health
•  minimal DVT/RemoteXPC health
•  real latency

It reports facts; lifecycle/failover policy decides actions.

Device-session router

Selects one immutable route:

•  direct USB
•  direct Network
•  userspace RSD
•  external RSD
•  daemon tunnel

Simulation modes consume this route without owning transport logic.



Prioritized remediation plan

R0 — Preserve a clean baseline

Before further implementation:

1. Keep dev builds isolated from /Applications/PathChanger.app.
2. Do not use the current manual build script for routine development.
3. Preserve the current green test baseline.
4. Make small, reversible commits only when explicitly requested.
5. Keep hardware integration tests opt-in.

Exit gate

•  Installed app remains untouched.
•  Dev app launches only from DerivedData.
•  Full suite remains green.



R1 — Contain privileged security risk

This must precede further privileged tunnel certification.

Work

1. Prefer userspace tunnels for supported operations.
2. Stop elevating Homebrew/user-owned Python.
3. Replace AppleScript shell execution with a signed typed helper where privilege is truly required.
4. Use a root-owned verified runtime or implement privileged operations without Python.
5. Remove root redirection to user-controlled paths.
6. Capture stdout/stderr through secure helper pipes.
7. Bind process identity to helper-owned session metadata.
8. Validate process identity immediately before termination.
9. Restrict pairing directory/files to 0700/0600.
10. Pin pymobiledevice3 and its dependency graph with hashes.
11. Redact UDIDs, coordinates, and endpoints from persistent logs.

Exit gate

•  No user-writable code executes as root.
•  Symlink/canary output tests pass.
•  PID reuse cannot terminate unrelated processes.
•  Pairing records are private.
•  Privileged dependencies are reproducible.



R2 — Fix deterministic crash and concurrency defects

Work

1. Rewrite persistent bridge startup:
◦  wait for the real ready message,
◦  one continuation,
◦  exact-once resume,
◦  one timeout path.
2. Serialize persistent bridge requests or add request IDs.
3. Add deterministic fake-process tests.
4. Drain subprocess stdout/stderr concurrently.
5. Enforce streaming output limits.
6. Add attempt/session generation UUIDs.
7. Require matching generation on every callback.
8. Serialize lifecycle events and effects.
9. Remove or correctly implement the dead recovery transition.
10. Consolidate application termination to one teardown owner.

Exit gate

•  Continuation stress tests pass.
•  Concurrent request correlation is deterministic.
•  Rapid start/stop/restart rejects stale completions.
•  No pipe deadlocks.
•  App termination performs one teardown.



R3 — Establish canonical lifecycle and readiness state

Work

1. Implement the seven-state tunnel lifecycle.
2. Create immutable TunnelAttempt and TunnelSession.
3. Remove decision use of DeviceManager.isTunneldRunning.
4. Stop copying tunnel-running state into DeviceStateManager.
5. Create one per-device TransportReadinessSnapshot.
6. Represent both USB and Wi‑Fi simultaneously.
7. Add same-network state.
8. Add fallback availability and reasons.
9. Replace string errors with typed TunnelFailure.
10. Ensure GUI renders authoritative snapshots only.

Exit gate

•  One lifecycle publisher.
•  One readiness publisher.
•  Active requires a validated session.
•  Readiness never changes tunnel action state.
•  GUI displays stopping, degraded, reconnecting, and failed truthfully.



R4 — Repair integration contracts

Work

1. Use pymobiledevice3 --script-mode.
2. Separate stdout from stderr.
3. Query port 49151 only in daemon mode.
4. Implement separate validators for:
◦  one-shot endpoint
◦  daemon/API session
5. Populate per-device daemon routes.
6. Bundle location_bridge.py as a real Swift/Xcode resource.
7. Resolve it only from Bundle.
8. Add dependency capability preflight:
◦  exact interpreter
◦  exact package version
◦  required CLI flags
◦  required Python imports
◦  operation capability
9. Pin tunnel protocol or expose it as a tested strategy.
10. Route every Start Tunnel control through one canonical selected-device API.

Exit gate

•  One-shot tunnel parses deterministic output.
•  Daemon mode becomes active using daemon-specific criteria.
•  Persistent bridge works outside repository working directory.
•  Every GUI entry uses the same start path.



R5 — Complete canonical device/readiness UI

Work

1. Establish stable DeviceIdentity.
2. Attach a transport set rather than one connection type.
3. Merge USB, Network, Bonjour, daemon, and pairing observations upstream.
4. Resolve name only from authoritative live metadata.
5. Represent unknown names honestly.
6. Add a separate status area for:
◦  USB Ready
◦  Wi‑Fi Ready
◦  Both Ready
◦  active transport
◦  same-network status
◦  fallback availability
7. Remove transport labels from the tunnel action.

Exit gate

•  One phone always appears once.
•  Two phones appear twice.
•  Names are correct.
•  Plug/unplug and Wi‑Fi changes do not create ghosts.
•  Readiness updates independently of tunnel lifecycle.



R6 — Certify USB, Wi‑Fi, and failover

Only after R1–R5.

Work

1. Verify standalone USB tunnel.
2. Verify standalone Wi‑Fi tunnel.
3. Verify simultaneous readiness.
4. Measure USB instability:
◦  disconnect count
◦  time window
◦  latency/error threshold
5. Define demotion and stability windows.
6. Implement USB → Wi‑Fi failover.
7. Implement Wi‑Fi → USB recovery.
8. Add bounded retry/backoff.
9. Preserve simulation session state.
10. Show active route and fallback events in GUI.

Exit gate

•  USB works independently.
•  Wi‑Fi works independently.
•  No tight reconnect loops.
•  No transport flapping.
•  Active state never survives a dead route.
•  Repeated cycles leak no process, port, task, or session.



R7 — Certify the five independent modes

Only after connection/failover is stable.

Prerequisite research

Document the correct meaning of:

•  safe mode
•  cooldown reminders

Define behavior separately for:

1. Teleport
2. Jump Teleport
3. Two-Spot
4. Multi-Spot
5. Joystick

Work

•  remove dormant/duplicate mode paths,
•  ensure each GUI mode reaches its intended implementation,
•  test every secondary function,
•  verify mode switching,
•  verify USB,
•  verify Wi‑Fi,
•  verify failover during each mode,
•  verify per-mode safety/cooldown logic.

Exit gate

The complete five-mode matrix passes through the real GUI.



R8 — Full wiring, deployment, and release certification

Work

1. Trace every GUI control to implementation.
2. Remove unmounted legacy UI or explicitly retain it.
3. Remove label-only settings.
4. Consolidate two settings systems.
5. Separate build and install scripts.
6. Never overwrite /Applications during build/test.
7. Enable production signing, notarization, and stapling.
8. Run dependency vulnerability scanning.
9. Add release artifact resource checks.
10. Run final security regression and hardware acceptance matrix.

Exit gate

•  No dead controls
•  No duplicate state paths
•  No undocumented workaround
•  No privileged critical findings
•  All hardware and GUI acceptance tests pass
•  Release artifact matches the verified dev behavior



Final recommendation

Proceed with remediation, but do not continue directly to five-mode hardware certification yet.

The correct next implementation sequence is:

1. remove critical privilege risks,
2. fix persistent bridge continuation/concurrency defects,
3. centralize lifecycle and readiness truth,
4. repair output/daemon/resource integration contracts,
5. then resume Wi‑Fi/USB hardware verification.

The codebase has enough working capability to complete this successfully. The remaining work is primarily consolidation, privilege containment, deterministic concurrency, and truthful state modeling—not rebuilding the product from scratch.