# PathChanger Five-Mode Persistence and Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `subagent-driven-development` (recommended) or `executing-plans` to execute this plan task-by-task. Use `using-git-worktrees`, `test-driven-development`, `systematic-debugging`, `flowdeck`, `verification-before-completion`, and `requesting-code-review` at their required gates.

**Goal:** Make Teleport, Jump Teleport, Two-Spot, Multi-Spot, and Joystick apply and retain real-device spoofed location over USB and Wi-Fi while the GUI reports only verified connection, injection, and recovery state.

**Architecture:** Introduce one explicit location-session domain model and one `@MainActor` coordinator that owns desired location, acknowledged receipts, connection generation, movement state, and recovery. Keep `TunneldManager.shared` as tunnel lifecycle authority, adapt `DevLocationBridge` behind a typed protocol, make persistent-bridge termination observable, and make every mode advance only after an acknowledged injection. Separate movement stop from explicit location clear.

**Tech Stack:** Swift 5.9, SwiftUI, Foundation, CoreLocation, XCTest, Python 3 with pymobiledevice3, XcodeGen via `project.yml`, and FlowDeck for all Apple build/test/run/UI work.

**Product contract:** `PRODUCT_REQUIREMENTS.md`

**Plan status:** Owner-authorized for subagent-driven execution and all Git operations explicitly named in this plan. Task 0 is complete: Stage 1 closed, source `main` normalized to `ea5a3b5a1b222729a0a8d186dee51610d8485e4b`, and completion tag `stage1-complete-stage1-20260827T165113Z-a22b889fcfc8` resolves to cleanup receipt `43096c8bbdc6f96cc3135ce5cd4483f1dd42788d`. Task 1 is complete through the reviewed documentation integration; this execution-record commit preserves that fact without rewriting earlier commits. Canonical Stage 2 remains unauthorized as a separate audit program. Privilege/elevation and physical-device mutation remain reserved gates.

---

## Execution principles

1. Follow RED → GREEN → REFACTOR. Never change production behavior before a test has failed for the intended reason.
2. Do not edit `PathChanger.xcodeproj/project.pbxproj` by hand. Change `project.yml` and regenerate with XcodeGen only when project membership changes.
3. Use FlowDeck, never raw Apple developer CLIs.
4. Run routine engineering and automated review autonomously after the owner explicitly authorizes this plan and its named Git operations.
5. Ask again only for a destructive history operation, remote default-branch update not listed here, privilege/elevation, physical-device mutation outside the approved matrix, account/payment action, or scope expansion.
6. Commit only green, reviewed states. Do not commit a deliberately failing RED state; preserve RED output in the task evidence.
7. Never mix documentation, generated project changes, domain-state changes, transport changes, mode behavior, and GUI changes in one commit.
8. Keep Stage 0 and Stage 1 tags and accepted commits immutable. Do not rebase, squash, amend, or cherry-pick them into a replacement history.

## Recorded baseline and current execution refs

| Ref/state | Recorded value | Meaning |
|---|---|---|
| Stage 1 source baseline | `ea5a3b5a1b222729a0a8d186dee51610d8485e4b` | Accepted source tree before documentation landing |
| Stage 1 integration | `stage1/integration` at `ea5a3b5a…` | Immutable historical integration ref |
| Stage 1 evidence-repository completion tag | `stage1-complete-stage1-20260827T165113Z-a22b889fcfc8` | Resolves to cleanup receipt `43096c8b…` |
| Documentation branch | `docs/product-contract` | Contains the atomic contract, plan, correction, and execution-record commits |
| Documentation integration | Fast-forwarded to `main` through `0d300bc…`; this commit records completion | No squash, rebase, amend, or cherry-pick |
| Root checkout role | Recovery checkout only | Product implementation occurs in external worktrees |
| Implementation worktree root | `$HOME/.config/superpowers/worktrees/PathChanger/` | Required external location |

At every later task, verify live refs and worktrees afresh. If they differ from the expected accepted head, stop history operations and reconcile before implementing.

## Clean Git-history design

- Keep the repository-root checkout as the documentation/recovery checkout.
- Use external worktrees under `$HOME/.config/superpowers/worktrees/PathChanger/`; do not create `.worktrees/`, `worktrees/`, or paths inside `.git/`.
- Complete the existing Stage 1 closing report, acceptance, cleanup receipt, and source merge decision before new product work.
- If the accepted Stage 1 decision authorizes it, fast-forward `main` through existing ancestry to `stage1/integration`; do not squash or cherry-pick.
- Land the three guidance documents as documentation-only commits after the source baseline is normalized.
- Create `feature/five-mode-reliability` from that documented main baseline.
- Create sequential topic branches from the feature integration branch. Merge each topic with `--no-ff` only after its tests and automated review pass.
- Keep default `main` stable while the feature is in progress. Merge the feature integration branch to `main` once at the final accepted gate.
- Preserve historical branches until final closure. Branch cleanup is optional and requires explicit owner approval.

## Task 0: Close Stage 1 and establish one source baseline

**Files:**
- Inspect only: accepted Stage 1 governance/evidence records
- Inspect only: Git refs, tags, worktrees, and remotes
- Do not modify product files

- [x] **Step 1: Reconcile current refs without mutating them**

Run:

```bash
git status --short
git worktree list --porcelain
git for-each-ref --format='%(refname:short)|%(objectname)|%(upstream:short)|%(upstream:track)' refs/heads
git ls-remote --heads origin
git show-ref --tags
```

Verified: repository facts table updated to execution-time state. All refs synchronized; docs worktree created; existing commits e44905e and cd0d0fe confirmed.

- [x] **Step 2: Complete the accepted Stage 1 closing sequence**

Confirm the durable record contains the Stage 1 closing report, verified owner acceptance, closing tag, cleanup receipt, and explicit source-main decision. Do not infer authorization from accepted work-packet tags.

- [x] **Step 3: Normalize `main` only if explicitly authorized by the Stage 1 closing decision**

In a global external worktree created for `main`, verify ancestry first:

```bash
git merge-base --is-ancestor origin/main stage1/integration
git merge-base --is-ancestor main stage1/integration
git diff --stat origin/main..stage1/integration
git diff --check origin/main..stage1/integration
```

When the accepted closing decision says YES, fast-forward only:

```bash
git merge --ff-only stage1/integration
```

Expected: no rebase, squash, cherry-pick, force-push, or rewritten commit. Any remote update occurs only under the accepted closing authorization.

- [x] **Step 4: Record the normalized baseline**

Record the exact `main` commit/tree, Stage 1 integration commit/tree, remote head, tags, and clean worktree status. The feature plan must refer to commit hashes, not only branch names.

## Task 1: Land the product contract and plan as atomic documentation history

**Files:**
- Create: `CLAUDE.md`
- Create: `PRODUCT_REQUIREMENTS.md`
- Create: `docs/superpowers/plans/2026-09-12-five-mode-persistence-reliability.md`
- Do not modify product source

- [x] **Step 1: Preserve the validated authoring copies**

Before copying, record and compare their SHA-256 values. At planning time:

```text
CLAUDE.md: e1b64fe73a1c4d2048735d417e26550a1922c537e780cebe7d6d53b678c56b47
PRODUCT_REQUIREMENTS.md: e416a8f45848a227692f648e1b2c191249737fa213b44aa3e58b21c179febe54
```

Recomputed after plan updates: verified at execution; documentation authority table updated for WP-1.2 closure and Stage 2 authorization state. Root copies preserved and updated; worktree copies synchronized.

- [x] **Step 2: Create a global documentation worktree**

Use the normalized `main` as the base:

```bash
git worktree add "$HOME/.config/superpowers/worktrees/PathChanger/docs-product-contract" -b docs/product-contract main
```

Expected: the original checkout and its untracked documents remain untouched.

- [x] **Step 3: Copy and verify the three documentation files**

Copy the exact validated files into the documentation worktree, then compare SHA-256 values byte-for-byte. Do not edit during copying.

- [x] **Step 4: Commit two atomic documentation topics after direct owner authorization of this plan's Git operations**

First commit:

```bash
git add CLAUDE.md PRODUCT_REQUIREMENTS.md
git commit -m "docs: define five-mode persistence product contract"
```

Second commit:

```bash
git add docs/superpowers/plans/2026-09-12-five-mode-persistence-reliability.md
git commit -m "docs: add five-mode reliability implementation plan"
```

Expected: both commits contain documentation only. Review `git show --stat --oneline HEAD~2..HEAD` and `git diff --check HEAD~2..HEAD` before any merge or push.

- [x] **Step 5: Integrate documentation without rewriting history**

`docs/product-contract` was fast-forwarded to normalized `main` through `0d300bc935dbe8d10aea60f4c82d52efc57f97d5`; this execution-record commit follows without rewriting history.

## Task 2: Create the isolated feature integration worktree

**Files:**
- No product files changed in setup

- [ ] **Step 1: Create the feature integration branch and worktree**

```bash
git worktree add "$HOME/.config/superpowers/worktrees/PathChanger/five-mode-reliability" -b feature/five-mode-reliability main
```

- [ ] **Step 2: Configure FlowDeck for the new worktree**

Run `flowdeck config get --json` first. If no worktree-specific config exists, run `flowdeck context --json`, select the PathChanger scheme and `My Mac`, and save that selection once. Do not overwrite another worktree's existing selection.

- [ ] **Step 3: Verify the clean baseline**

Run:

```bash
flowdeck project packages resolve
flowdeck test discover
flowdeck build -C ReleaseTesting
flowdeck test
```

Expected: package resolution succeeds, ReleaseTesting builds, and the full baseline is classified. Record existing failures or flakes; do not fix them during setup.

- [ ] **Step 4: Establish branch conventions**

Use these sequential branches from `feature/five-mode-reliability`:

```text
feature/location-session-model
feature/injection-receipts
feature/session-recovery
feature/five-mode-semantics
feature/gui-state-truth
test/mode-transport-matrix
fix/packaging-and-runtime
```

Each topic branch must start from the accepted head of the feature integration branch. Never branch a later topic from an unmerged earlier topic.

## Task 3: Freeze false-active and clear-versus-hold behavior with tests

**Branch:** `feature/location-session-model`

- [ ] **Step 0: Identify any usable previous-build behavioral oracle**

Inventory available installed artifacts, tags, archived evidence, and source refs without executing an untrusted manual bundle. Record an artifact hash and source provenance before treating anything as known-good. If no source-linked working artifact exists, record `reference unavailable` and use `PRODUCT_REQUIREMENTS.md` plus current-behavior tests; never invent a historical baseline.

**Files:**
- Modify: `Tests/PathChangerTests/AppStateSimulationTests.swift`
- Modify: `Tests/PathChangerTests/StateManagerTests.swift`
- Test only; no production change in this task

- [ ] **Step 1: Add a characterization test for cooldown rejection**

Add a test proving the current ordering can announce simulation before `setLocation` accepts the request. The desired assertion is:

```swift
XCTAssertFalse(state.locationApplication.isActive)
XCTAssertEqual(state.desiredLocation, target)
XCTAssertNil(state.lastAcknowledgedReceipt)
```

Run the exact test after discovering its FlowDeck identifier:

```bash
flowdeck test discover
flowdeck test --only PathChangerTests/AppStateSimulationTests/testCooldownRejectionNeverMarksLocationActive
```

Expected RED: the existing boolean becomes active without an acknowledgement.

- [ ] **Step 2: Add a test separating stop movement from clear location**

Test that route completion, pause, and stop movement preserve the last acknowledged coordinate, while explicit clear removes it. Expected RED: `AppState.stopSimulation()` currently calls `clearLocation()`.

- [ ] **Step 3: Add a test for tunnel-loss stale GUI state**

Drive the existing tunnel-state callback to a non-active state. Assert that the location state becomes uncertain/lost and the GUI cannot remain active. Expected RED: the held bridge is stopped without synchronizing simulation truth.

- [ ] **Step 4: Add a test for joystick disengage semantics**

Assert that releasing joystick movement leaves the last coordinate held but changes movement—not location application—to idle/paused. Expected RED: current boolean state cannot represent this distinction.

- [ ] **Step 5: Preserve the RED tests and continue directly to Task 4**

If the tests initially fail to compile because the new domain API does not exist, preserve that compiler output as RED evidence and keep the tests unchanged and uncommitted. Task 4 must add only the minimum domain types needed to make the tests compile and fail on behavior; do not revert or weaken the assertions.

## Task 4: Introduce five-mode and location-session domain types

**Branch:** `feature/location-session-model`

**Files:**
- Create: `PathChanger/Models/LocationSessionState.swift`
- Create: `PathChanger/Device/LocationInjecting.swift`
- Modify: `PathChanger/UI/ContentView.swift` only to map existing `AppMode` cases to the domain mode
- Create: `Tests/PathChangerTests/LocationSessionStateTests.swift`
- Regenerate from `project.yml` only if target membership is not automatic

- [ ] **Step 1: Write compiling-intent tests for the five domain modes**

The test must require exactly these cases:

```swift
XCTAssertEqual(Set(LocationMode.allCases), Set([
    .teleport, .jumpTeleport, .twoSpot, .multiSpot, .joystick
]))
```

Expected RED: `LocationMode` does not exist.

- [ ] **Step 2: Write transition tests for independent state dimensions**

Cover these facts independently:

```swift
XCTAssertEqual(state.desiredLocation, target)
XCTAssertEqual(state.movement, .idle)
XCTAssertEqual(state.application, .idle)
XCTAssertNil(state.lastAcknowledgedReceipt)
```

Then test applying, acknowledged-active, movement paused/completed, connection uncertain, recovery, and explicit clear. Desired location must survive every transition except explicit clear.

- [ ] **Step 3: Add the minimal domain types**

Use this shape, refining names only if the compiling implementation demands it:

```swift
enum LocationMode: String, CaseIterable, Codable, Sendable {
    case teleport
    case jumpTeleport
    case twoSpot
    case multiSpot
    case joystick
}

enum LocationTransport: String, Codable, Sendable {
    case usb
    case wifi
}

enum LocationEndpointClass: String, Codable, Sendable {
    case direct
    case remoteServiceDiscovery
}

struct LocationSessionIdentity: Equatable, Codable, Sendable {
    let stableDeviceID: String
    let transport: LocationTransport
    let endpointClass: LocationEndpointClass
    let generation: UInt64
}

enum LocationInjectionOutcome: Equatable, Codable, Sendable {
    case applied
    case queued
    case failed(code: String)
}

struct LocationInjectionReceipt: Equatable, Codable, Sendable {
    let requestID: UUID
    let session: LocationSessionIdentity
    let coordinate: LocationCoordinate
    let completedAt: Date
    let outcome: LocationInjectionOutcome
}

enum LocationConnectionPhase: Equatable, Sendable {
    case unavailable
    case ready(LocationSessionIdentity)
    case reconnecting(previousGeneration: UInt64?, attempt: Int)
    case failed(String)
}

enum LocationApplicationPhase: Equatable, Sendable {
    case idle
    case applying(requestID: UUID, coordinate: LocationCoordinate)
    case active(LocationInjectionReceipt)
    case uncertain(lastReceipt: LocationInjectionReceipt?, reason: String)
    case lost(lastReceipt: LocationInjectionReceipt?, reason: String)
    case clearing
    case failed(String)
}

enum LocationMovementPhase: Equatable, Sendable {
    case idle
    case moving(LocationMode)
    case paused(LocationMode)
    case completed(LocationMode)
}

struct LocationSessionState: Equatable, Sendable {
    var desiredLocation: LocationCoordinate?
    var lastAcknowledgedReceipt: LocationInjectionReceipt?
    var connection: LocationConnectionPhase = .unavailable
    var application: LocationApplicationPhase = .idle
    var movement: LocationMovementPhase = .idle
}

extension LocationApplicationPhase {
    var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}

struct LocationInjectionTarget: Equatable, Sendable {
    let stableDeviceID: String
    let transport: LocationTransport
}

struct LocationApplicationRequest: Equatable, Sendable {
    let id: UUID
    let target: LocationInjectionTarget
    let coordinate: LocationCoordinate
    let mode: LocationMode
}

protocol LocationInjecting: Sendable {
    func apply(_ request: LocationApplicationRequest) async throws
        -> LocationInjectionReceipt
    func clear(
        target: LocationInjectionTarget,
        session: LocationSessionIdentity?
    ) async throws
}
```

If synthesized `Codable` for associated-value enums is not needed by production/evidence, remove that conformance rather than adding custom serialization prematurely.

- [ ] **Step 4: Map UI mode to domain mode without making settings a spoofing mode**

Keep `.settings` as navigation-only. Add an explicit `AppMode.locationMode: LocationMode?` mapping for the five functional cases. Exhaustive tests must fail if a new functional mode lacks a mapping.

- [ ] **Step 5: Run focused and full tests**

Use discovered identifiers, then:

```bash
flowdeck build -C ReleaseTesting
flowdeck test
```

Expected GREEN: domain tests pass and the existing baseline count does not decrease without an explained accepted reason.

- [ ] **Step 6: Commit the green domain types**

```bash
git add PathChanger/Models/LocationSessionState.swift PathChanger/Device/LocationInjecting.swift PathChanger/UI/ContentView.swift Tests/PathChangerTests/LocationSessionStateTests.swift project.yml PathChanger.xcodeproj/project.pbxproj PathChanger.xcodeproj/xcshareddata/xcschemes/PathChanger.xcscheme
git commit -m "feat(state): define truthful location session model"
```

Stage only files that actually changed. A generated project diff without a corresponding `project.yml` membership change is rejected.

## Task 5: Add the single location-session coordinator

**Branch:** `feature/location-session-model`

**Files:**
- Create: `PathChanger/Core/StateManagers/LocationSessionCoordinator.swift`
- Create: `Tests/PathChangerTests/LocationSessionCoordinatorTests.swift`
- Modify: `PathChanger/PathChangerApp.swift` only to construct the coordinator

- [ ] **Step 1: Write RED tests for acknowledgement-gated activity**

Test this sequence:

```swift
coordinator.select(target, mode: .teleport)
XCTAssertEqual(coordinator.state.desiredLocation, target)
XCTAssertFalse(coordinator.state.application.isActive)

let request = coordinator.beginApplication()
XCTAssertEqual(coordinator.state.application, .applying(
    requestID: request.id,
    coordinate: target
))
XCTAssertFalse(coordinator.state.application.isActive)

coordinator.accept(receipt)
XCTAssertEqual(coordinator.state.application, .active(receipt))
```

Expected RED: no coordinator exists and current state activates before acknowledgement.

- [ ] **Step 2: Write RED tests for stale receipt rejection**

A receipt whose session generation differs from the current connection must transition to `.uncertain` and must never set `.active`.

- [ ] **Step 3: Write RED tests for hold, loss, and clear**

Assert:

- pause/stop/completion change only `movement`;
- transport loss preserves `desiredLocation` and the last receipt but makes application uncertain;
- explicit clear enters `.clearing`, calls the clear dependency, and only then removes desired/acknowledged state;
- failed clear reports failure and retains enough state to retry honestly.

- [ ] **Step 4: Implement the minimal coordinator**

Use `@MainActor final class LocationSessionCoordinator: ObservableObject`. It is the sole writer of `LocationSessionState`; `AppState`, mode engines, bridge adapters, and GUI controls submit events instead of setting booleans directly. Its initializer requires an `any LocationInjecting` dependency and stores it privately, so `clear()` and application requests cannot bypass the tested adapter.

Required public operations:

```swift
func select(_ coordinate: LocationCoordinate, mode: LocationMode)
func beginApplication() throws -> LocationApplicationRequest
func accept(_ receipt: LocationInjectionReceipt)
func reject(requestID: UUID, error: Error)
func beginMovement(_ mode: LocationMode)
func pauseMovement()
func stopMovement()
func completeMovement()
func connectionReady(_ session: LocationSessionIdentity)
func connectionLost(reason: String)
func beginRecovery(attempt: Int)
func clear() async
```

- [ ] **Step 5: Make illegal transitions explicit**

Return typed state-transition errors for application without a desired coordinate, receipt/request mismatch, stale generation, and clear without a device/session. Do not silently ignore them.

- [ ] **Step 6: Run focused tests and full suite, then commit green**

```bash
git add PathChanger/Core/StateManagers/LocationSessionCoordinator.swift PathChanger/PathChangerApp.swift Tests/PathChangerTests/LocationSessionCoordinatorTests.swift project.yml PathChanger.xcodeproj/project.pbxproj PathChanger.xcodeproj/xcshareddata/xcschemes/PathChanger.xcscheme
git commit -m "feat(state): centralize acknowledged spoofing truth"
```

- [ ] **Step 7: Automated review and topic integration**

Verify the coordinator is the only location-session-state writer, then merge `feature/location-session-model` into `feature/five-mode-reliability` with `--no-ff` after the execution plan's Git authorization is in force.

## Task 6: Extend the injection contract with events and a deterministic fake

**Branch:** `feature/injection-receipts`

**Files:**
- Modify: `PathChanger/Device/LocationInjecting.swift`
- Create: `Tests/PathChangerTests/LocationInjectionReceiptTests.swift`
- Create: `Tests/PathChangerTests/Fakes/FakeLocationInjector.swift`
- Modify: `PathChanger/Core/StateManagers/LocationSessionCoordinator.swift`

- [ ] **Step 1: Write RED tests for request/receipt identity**

Require a request to contain request ID, stable device ID, coordinate, and mode. Require a successful receipt to echo the request ID and coordinate and to add transport, endpoint class, session generation, completion time, and `.applied` outcome. The production stable device ID is an internal correlation key and must never enter ordinary logs, screenshots, or exported evidence. UI/evidence uses a run-local alias such as `device-001`; any reversible alias map stays only in the protected evidence staging area and is omitted from manifested public-facing artifacts.

- [ ] **Step 2: Write RED tests for queued and stale outcomes**

A queued/rate-limited result is not active. A receipt from generation N is stale after the coordinator has accepted generation N+1.

- [ ] **Step 3: Add the protocol and event contract**

```swift
enum LocationBridgeEvent: Equatable, Sendable {
    case sessionReady(LocationSessionIdentity)
    case sessionLost(LocationSessionIdentity?, reason: String)
    case processTerminated(exitCode: Int32)
}

protocol LocationInjecting: Sendable {
    func apply(_ request: LocationApplicationRequest) async throws
        -> LocationInjectionReceipt
    func clear(
        target: LocationInjectionTarget,
        session: LocationSessionIdentity?
    ) async throws
    func events() async -> AsyncStream<LocationBridgeEvent>
}
```

Keep `Device` out of the cross-actor protocol. Construct `LocationInjectionTarget` from the canonical selected device before calling the injector.

- [ ] **Step 4: Implement a deterministic fake**

The fake must support controlled acknowledgement, queued result, failure, session loss, process termination, generation changes, and an ordered call log. Do not sleep in unit tests; inject a clock where retry timing matters.

- [ ] **Step 5: Update coordinator tests to use the fake**

Prove no application state becomes active before `FakeLocationInjector` releases its acknowledgement.

- [ ] **Step 6: Run focused/full tests and commit green**

```bash
git add PathChanger/Device/LocationInjecting.swift PathChanger/Core/StateManagers/LocationSessionCoordinator.swift Tests/PathChangerTests/LocationInjectionReceiptTests.swift Tests/PathChangerTests/Fakes/FakeLocationInjector.swift project.yml PathChanger.xcodeproj/project.pbxproj PathChanger.xcodeproj/xcshareddata/xcschemes/PathChanger.xcscheme
git commit -m "test(device): define session-bound injection receipts"
```

## Task 7: Adapt `DevLocationBridge` to return truthful receipts

**Branch:** `feature/injection-receipts`

**Files:**
- Modify: `PathChanger/Device/DevLocationBridge.swift`
- Modify: `PathChanger/Device/LocationConnectionArguments.swift`
- Modify: `PathChanger/Device/TunneldManager.swift` only if endpoint classification cannot be obtained through the existing accessor
- Modify: `Tests/PathChangerTests/DevLocationBridgeSecurityTests.swift`
- Create: `Tests/PathChangerTests/DevLocationBridgeReceiptTests.swift`

- [ ] **Step 1: Write RED tests for direct and RSD receipt classification**

Given direct `--udid` arguments, expect `.usb/.direct` or `.wifi/.direct` from the selected device transport. Given `--rsd`, expect the retained physical transport plus `.remoteServiceDiscovery`. Never infer the transport from a log string.

- [ ] **Step 2: Write RED tests for rate-limit truth**

When a request is queued, return/throw a typed queued result and leave application state non-active. Queue completion must emit its own receipt tied to the original request ID; do not let the original caller assume immediate application.

- [ ] **Step 3: Track a monotonic generation per stable device/session**

Increment generation whenever the held subprocess, persistent Python process, endpoint tuple, or selected transport is replaced after loss. Resetting process statistics must not reset generation.

- [ ] **Step 4: Return a receipt only after the selected path has accepted the coordinate**

Change the adapter API from `async throws -> Void` to `async throws -> LocationInjectionReceipt`. For the held subprocess path, `.applied` requires the process to remain running and ownership to be retained. For the persistent path, `.applied` requires a decoded success response.

- [ ] **Step 5: Remove false fallback semantics**

A persistent-bridge failure may fall back to the subprocess only while preserving the same request ID and recording a new session identity. If both fail, return the terminal error; do not record success statistics.

- [ ] **Step 6: Run focused/full tests and commit green**

```bash
git add PathChanger/Device/DevLocationBridge.swift PathChanger/Device/LocationConnectionArguments.swift PathChanger/Device/TunneldManager.swift Tests/PathChangerTests/DevLocationBridgeSecurityTests.swift Tests/PathChangerTests/DevLocationBridgeReceiptTests.swift project.yml PathChanger.xcodeproj/project.pbxproj PathChanger.xcodeproj/xcshareddata/xcschemes/PathChanger.xcscheme
git commit -m "feat(device): return transport-bound injection receipts"
```

Stage only changed files. `TunneldManager.swift` is excluded if no production edit was required.

## Task 8: Serialize the persistent bridge and expose lifecycle events

**Branch:** `feature/injection-receipts`

**Files:**
- Modify: `PathChanger/Device/PersistentLocationBridge.swift`
- Modify: `scripts/location_bridge.py`
- Modify: `Tests/PathChangerTests/PersistentLocationBridgeTests.swift`
- Create: `Tests/PathChangerTests/PersistentBridgeLifecycleTests.swift`

- [ ] **Step 1: Write RED tests for concurrent requests**

Start request A and attempt request B before A responds. The bridge must queue through one tested serialization boundary or reject B with a typed `requestInProgress`; it must never overwrite `pendingContinuation`.

- [ ] **Step 2: Write RED tests for real readiness**

`start()` cannot set `isRunning` from a fixed 500 ms delay. It must wait for the Python `{\"ready\": true}` response and fail on timeout/process exit.

- [ ] **Step 3: Add request identity to the JSON protocol**

Add `request_id` and `session_generation` to requests and responses in both Swift and Python. A response with the wrong request ID is invalid and cannot resume the pending caller.

- [ ] **Step 4: Publish termination and session-loss events**

On process termination, resume any pending request exactly once, clear pipe handlers, and emit `.processTerminated(exitCode:)` followed by session loss. Intentional stop must be distinguishable from unexpected exit.

- [ ] **Step 5: Verify service-cache invalidation**

Python tests must prove an injection error removes the corresponding cached service and that a later request rebuilds it. Do not import or execute real tunnel code in unit tests.

- [ ] **Step 6: Run focused/full tests and commit green**

```bash
git add PathChanger/Device/PersistentLocationBridge.swift scripts/location_bridge.py Tests/PathChangerTests/PersistentLocationBridgeTests.swift Tests/PathChangerTests/PersistentBridgeLifecycleTests.swift project.yml PathChanger.xcodeproj/project.pbxproj PathChanger.xcodeproj/xcshareddata/xcschemes/PathChanger.xcscheme
git commit -m "fix(device): serialize bridge requests and report termination"
```

- [ ] **Step 7: Review and integrate the receipt topic**

Verify Swift/Python protocol parity, continuation single-resume safety, no sensitive identifiers in normal logs, and no off-topic tunnel lifecycle edits. Merge `feature/injection-receipts` to `feature/five-mode-reliability` after green review.

## Task 9: Implement reconnect-and-reapply without clearing desired state

**Branch:** `feature/session-recovery`

**Files:**
- Modify: `PathChanger/Core/StateManagers/LocationSessionCoordinator.swift`
- Modify: `PathChanger/Core/StateManagers/DeviceStateManager.swift`
- Modify: `PathChanger/Core/ReliabilityManager.swift`
- Modify: `PathChanger/Device/DeviceManager.swift`
- Modify: `PathChanger/Device/TunnelStateMachine.swift`
- Modify: `PathChanger/PathChangerApp.swift`
- Create: `Tests/PathChangerTests/LocationSessionRecoveryTests.swift`
- Modify: `Tests/PathChangerTests/TunnelStateMachineTests.swift`
- Modify: `Tests/PathChangerTests/StateManagerTests.swift`

- [ ] **Step 1: Write RED tests for USB reconnect**

Apply coordinate C over USB generation 1, lose the transport, and restore the same stable device on generation 2. Assert movement stops, desired C remains, the old receipt becomes uncertain, C is reapplied, and `.active` occurs only after the generation-2 receipt.

- [ ] **Step 2: Write RED tests for Wi-Fi/RSD reconnect**

Lose tunnel/RSD health, rebuild the endpoint, and reapply C. Device refresh alone is not recovery success.

- [ ] **Step 3: Write RED tests for transport failover**

When USB disappears but verified Wi-Fi is available, use the same stable device identity, establish a new session generation, reapply C, and only then report active. Never clear C during switching.

- [ ] **Step 4: Write RED tests for exhaustion and cancellation**

Use an injected clock/backoff policy. Prove retries are bounded and cancelable, terminal failure retains desired C, and explicit retry starts a new generation. Do not hard-code a retry count until product settings or existing policy supplies it.

- [ ] **Step 5: Wire observable loss sources into the coordinator**

Bridge termination, held subprocess exit, tunnel health loss, selected-device loss, endpoint replacement, and app cancellation must submit typed events. Remove direct simulation booleans from those callbacks.

- [ ] **Step 6: Reapply before resuming movement**

Route/joystick work remains paused through recovery. Resume movement only after the desired coordinate has a current-generation applied receipt.

- [ ] **Step 7: Run focused/full tests and commit green**

```bash
git add PathChanger/Core/StateManagers/LocationSessionCoordinator.swift PathChanger/Core/StateManagers/DeviceStateManager.swift PathChanger/Core/ReliabilityManager.swift PathChanger/Device/DeviceManager.swift PathChanger/Device/TunnelStateMachine.swift PathChanger/PathChangerApp.swift Tests/PathChangerTests/LocationSessionRecoveryTests.swift Tests/PathChangerTests/TunnelStateMachineTests.swift Tests/PathChangerTests/StateManagerTests.swift project.yml PathChanger.xcodeproj/project.pbxproj PathChanger.xcodeproj/xcshareddata/xcschemes/PathChanger.xcscheme
git commit -m "feat(recovery): reapply desired location after session loss"
```

- [ ] **Step 8: Review and integrate the recovery topic**

Review every path that can stop a held process. Each must either be explicit Clear/Reset or transition to uncertain/lost while preserving desired state. Merge after tests pass.

## Task 10: Remove Safe Mode and cooldown from spoofing correctness

**Branch:** `feature/five-mode-semantics`

**Files:**
- Modify: `PathChanger/Core/StateManagers/SimulationStateManager.swift`
- Modify: `PathChanger/Core/AppSettings.swift`
- Modify: `PathChanger/Simulation/SimulationEngine.swift`
- Modify: `PathChanger/UI/OrganicChrome.swift`
- Modify: `PathChanger/UI/OrganicSettingsSheet.swift`
- Modify: `Tests/PathChangerTests/StateManagerTests.swift`
- Modify: `Tests/PathChangerTests/AppStateSimulationTests.swift`
- Modify: `Tests/PathChangerTests/UIComponentTests.swift`

- [ ] **Step 1: Write RED tests for exact-coordinate application**

With legacy Safe Mode enabled in stored preferences, applying target T must request T exactly. Expected RED: current code can replace T with a random drift coordinate.

- [ ] **Step 2: Write RED tests for cooldown truth**

A repeated teleport can be accepted, queued with an explicit non-active state, or rejected with a visible error. It cannot leave the GUI active without a receipt. Expected RED: the manager returns early after callers have already announced activity.

- [ ] **Step 3: Remove Safe Mode random drift and automatic cooldown gating**

Remove Safe Mode and cooldown as user-visible location semantics. Ignore legacy persisted values during migration; do not let them alter coordinates or reset the location. Keep adapter-level rate limiting/backpressure, but expose queued/rejected results through the coordinator.

- [ ] **Step 4: Remove or replace affected UI controls**

Remove the Safe Mode and cooldown controls from active chrome/settings. If product copy still needs a connection-safety notice, make it informational and unrelated to location reset or coordinate mutation.

- [ ] **Step 5: Run focused/full tests and commit green**

```bash
git add PathChanger/Core/StateManagers/SimulationStateManager.swift PathChanger/Core/AppSettings.swift PathChanger/Simulation/SimulationEngine.swift PathChanger/UI/OrganicChrome.swift PathChanger/UI/OrganicSettingsSheet.swift Tests/PathChangerTests/StateManagerTests.swift Tests/PathChangerTests/AppStateSimulationTests.swift Tests/PathChangerTests/UIComponentTests.swift
git commit -m "fix(simulation): remove misleading safe-mode cooldown behavior"
```

## Task 11: Make Teleport and Jump acknowledgement-driven

**Branch:** `feature/five-mode-semantics`

**Files:**
- Modify: `PathChanger/Simulation/SimulationPlanner.swift`
- Modify: `PathChanger/PathChangerApp.swift`
- Modify: `Tests/PathChangerTests/SimulationPlannerTests.swift`
- Modify: `Tests/PathChangerTests/AppStateSimulationTests.swift`
- Create: `Tests/PathChangerTests/ModePersistenceTests.swift`

- [ ] **Step 1: Write RED Teleport tests**

Prove: selecting does not inject; Move creates one request; active appears only after its receipt; stop movement holds the coordinate; explicit Clear resets it.

- [ ] **Step 2: Write RED Jump tests**

Prove each action applies exactly one indexed waypoint and advances the index only after an applied receipt. A queued, failed, stale, or canceled request must not consume a hop.

- [ ] **Step 3: Route `AppState` through the coordinator**

Replace preemptive `isSimulating = true` and direct bridge-state mutation with coordinator operations. Keep compatibility computed properties only while old views migrate; they must derive from coordinator state and must not be independently writable.

- [ ] **Step 4: Make stop movement hold**

Replace the current stop path that calls `clearLocation()` with coordinator `stopMovement()`. Add a separate explicit clear operation for intentional return to real GPS.

- [ ] **Step 5: Run focused/full tests and commit green**

```bash
git add PathChanger/Simulation/SimulationPlanner.swift PathChanger/PathChangerApp.swift Tests/PathChangerTests/SimulationPlannerTests.swift Tests/PathChangerTests/AppStateSimulationTests.swift Tests/PathChangerTests/ModePersistenceTests.swift project.yml PathChanger.xcodeproj/project.pbxproj PathChanger.xcodeproj/xcshareddata/xcschemes/PathChanger.xcscheme
git commit -m "fix(modes): make teleport and jump receipt-driven"
```

## Task 12: Make Two-Spot and Multi-Spot hold the final coordinate

**Branch:** `feature/five-mode-semantics`

**Files:**
- Modify: `PathChanger/Simulation/SimulationPlanner.swift`
- Modify: `PathChanger/Simulation/SimulationEngine.swift`
- Modify: `PathChanger/Core/StateManagers/RouteStateManager.swift`
- Modify: `PathChanger/PathChangerApp.swift`
- Modify: `Tests/PathChangerTests/SimulationPlannerTests.swift`
- Modify: `Tests/PathChangerTests/SimulationEngineTests.swift`
- Modify: `Tests/PathChangerTests/StateManagerTests.swift`
- Modify: `Tests/PathChangerTests/ModePersistenceTests.swift`

- [ ] **Step 1: Write RED Two-Spot lifecycle tests**

Verify start → acknowledged first point → movement → acknowledged destination → `.completed(.twoSpot)` while application remains active at the destination. Pause and stop movement hold the last acknowledged point.

- [ ] **Step 2: Write RED Multi-Spot lifecycle tests**

Verify every route point advances only after an applied receipt, progress reflects acknowledged—not merely generated—points, interruption pauses at the last receipt, recovery reapplies desired position, and completion holds the final waypoint.

- [ ] **Step 3: Separate route generation from delivery**

Keep `SimulationPlanner`/`RouteInterpolator` pure. The engine proposes a next point; the coordinator/injector acknowledges it; only then does route state advance.

- [ ] **Step 4: Remove completion-as-clear behavior**

Completing or stopping playback cancels timers/tasks but does not call bridge clear or terminate the active held location session.

- [ ] **Step 5: Run focused/full tests and commit green**

```bash
git add PathChanger/Simulation/SimulationPlanner.swift PathChanger/Simulation/SimulationEngine.swift PathChanger/Core/StateManagers/RouteStateManager.swift PathChanger/PathChangerApp.swift Tests/PathChangerTests/SimulationPlannerTests.swift Tests/PathChangerTests/SimulationEngineTests.swift Tests/PathChangerTests/StateManagerTests.swift Tests/PathChangerTests/ModePersistenceTests.swift
git commit -m "fix(modes): hold route destinations after movement"
```

## Task 13: Make Joystick movement and hold state truthful

**Branch:** `feature/five-mode-semantics`

**Files:**
- Modify: `PathChanger/Simulation/SimulationEngine.swift`
- Modify: `PathChanger/Simulation/JoystickMovement.swift`
- Modify: `PathChanger/PathChangerApp.swift`
- Modify: `Tests/PathChangerTests/JoystickMovementTests.swift`
- Modify: `Tests/PathChangerTests/SimulationEngineTests.swift`
- Modify: `Tests/PathChangerTests/ModePersistenceTests.swift`

- [ ] **Step 1: Write RED engage/disengage tests**

Engage applies the selected/start coordinate before movement becomes active. Releasing the joystick stops updates but leaves application active at the last receipt.

- [ ] **Step 2: Write RED latest-wins/backpressure tests**

Rapid input may coalesce only coordinates not yet sent. Never discard an acknowledged receipt, never mark an unacknowledged coordinate active, and never let queue overflow silently advance displayed position.

- [ ] **Step 3: Write RED interruption tests**

Transport loss cancels movement updates, preserves desired/last acknowledged state, and enters uncertain. Recovery reapplies before new joystick movement.

- [ ] **Step 4: Implement minimal coordinator-backed joystick delivery**

The movement calculator stays pure; the coordinator owns application truth. Remove direct writes to `isSimulating/currentLocation` from joystick callbacks.

- [ ] **Step 5: Run focused/full tests and commit green**

```bash
git add PathChanger/Simulation/SimulationEngine.swift PathChanger/Simulation/JoystickMovement.swift PathChanger/PathChangerApp.swift Tests/PathChangerTests/JoystickMovementTests.swift Tests/PathChangerTests/SimulationEngineTests.swift Tests/PathChangerTests/ModePersistenceTests.swift
git commit -m "fix(modes): hold acknowledged joystick location"
```

- [ ] **Step 6: Review all five mode contracts and integrate**

Run the full suite twice. Verify exact-coordinate behavior, no implicit clear, no progress before receipt, and no Safe Mode/cooldown dependency. Merge `feature/five-mode-semantics` into `feature/five-mode-reliability` after review.

## Task 14: Make the GUI a projection of verified session state

**Branch:** `feature/gui-state-truth`

**Files:**
- Modify: `PathChanger/PathChangerApp.swift`
- Modify: `PathChanger/UI/ContentView.swift`
- Modify: `PathChanger/UI/OrganicChrome.swift`
- Modify: `PathChanger/UI/ModeContextCard.swift`
- Modify: `PathChanger/UI/FloatingControlPanel.swift`
- Modify: `PathChanger/UI/JoystickControlView.swift`
- Modify: `PathChanger/UI/DiagnosticsView.swift`
- Create: `PathChanger/Device/LocationInjectorFactory.swift`
- Modify: `PathChanger/Core/ProcessEnvironment.swift`
- Create: `Tests/PathChangerTests/LocationInjectorFactoryTests.swift`
- Modify: `Tests/PathChangerTests/UIComponentTests.swift`
- Modify: `Tests/PathChangerTests/AppStateSimulationTests.swift`
- Create: `Tests/PathChangerTests/LocationStatusPresentationTests.swift`

- [ ] **Step 1: Write RED presentation-state tests**

Require explicit labels for idle, applying, active/held, moving, paused, reconnecting/uncertain, lost, clearing, and failed. “Spoofing” is permitted only for `.active` with a current-generation applied receipt.

- [ ] **Step 2: Write RED readiness-versus-lifecycle tests**

A device may be visible over FlowDeck/CoreDevice while pymobiledevice3 is unavailable; the GUI must show those facts separately. A connected transport must not imply location active, and a tunnel-active state must not imply a coordinate was applied.

- [ ] **Step 3: Add stable accessibility identifiers**

At minimum:

```text
location.mode.teleport
location.mode.jump
location.mode.twoSpot
location.mode.multiSpot
location.mode.joystick
location.action.apply
location.action.pauseMovement
location.action.stopMovement
location.action.clear
location.status.connection
location.status.application
location.status.movement
location.status.coordinate
```

- [ ] **Step 4: Wire UI controls to coordinator intents**

Mode selection stages data only. Apply starts an injection request. Pause/Stop affect movement only. Clear is visually distinct, confirmation-protected, and the only normal action that returns to real GPS.

- [ ] **Step 5: Show uncertainty honestly**

During reconnect, show the desired coordinate and last acknowledged coordinate separately, mark actual device state uncertain, and disable new movement until reapplication succeeds. Do not display the desired coordinate as the current applied coordinate.

- [ ] **Step 6: Keep diagnostics privacy-safe**

Display transport, endpoint class, redacted stable device alias, session generation, request ID suffix, last acknowledgement time, and failure code. Do not show raw UDIDs, account data, or tunnel endpoints in normal UI/log evidence.

- [ ] **Step 7: Add a ReleaseTesting-only deterministic injector seam**

`LocationInjectorFactory` must return the real `DevLocationBridge` in shipping Release builds. Under the existing ReleaseTesting `DEBUG` compilation condition only, it may select a scripted fake when `ProcessEnvironment` contains `PATHCHANGER_TEST_LOCATION_INJECTOR=1`. Add tests proving Release ignores the variable and ReleaseTesting can exercise all UI states without a physical device. Keep the launch environment external to the repository.

- [ ] **Step 8: Run focused/full tests and commit green**

```bash
git add PathChanger/PathChangerApp.swift PathChanger/UI/ContentView.swift PathChanger/UI/OrganicChrome.swift PathChanger/UI/ModeContextCard.swift PathChanger/UI/FloatingControlPanel.swift PathChanger/UI/JoystickControlView.swift PathChanger/UI/DiagnosticsView.swift PathChanger/Device/LocationInjectorFactory.swift PathChanger/Core/ProcessEnvironment.swift Tests/PathChangerTests/LocationInjectorFactoryTests.swift Tests/PathChangerTests/UIComponentTests.swift Tests/PathChangerTests/AppStateSimulationTests.swift Tests/PathChangerTests/LocationStatusPresentationTests.swift project.yml PathChanger.xcodeproj/project.pbxproj
git commit -m "fix(ui): derive spoofing status from acknowledged state"
```

- [ ] **Step 9: Run background FlowDeck GUI verification**

Follow the macOS preflight: inspect `--help`, start a session, use `find` before actions, pass `--background`, and inspect the updated screenshot/tree after each action. No physical-device mutation is required for this step; use deterministic app dependencies.

- [ ] **Step 10: Review and integrate the GUI topic**

Reject any remaining writable duplicate boolean that can make the GUI disagree with coordinator state. Merge after unit, full-suite, and background GUI checks pass.

## Task 15: Build the deterministic five-mode × two-transport matrix

**Branch:** `test/mode-transport-matrix`

**Files:**
- Create: `Tests/PathChangerTests/ModeTransportMatrixTests.swift`
- Create: `Tests/PathChangerTests/ConnectionInterruptionTests.swift`
- Modify: `Tests/PathChangerTests/Fakes/FakeLocationInjector.swift`
- Modify: `Tests/PathChangerTests/LocationSessionRecoveryTests.swift`

- [ ] **Step 1: Define the ten core cases in one typed table**

```swift
let cases: [(LocationMode, LocationTransport)] = LocationMode.allCases.flatMap { mode in
    [LocationTransport.usb, .wifi].map { (mode, $0) }
}
XCTAssertEqual(cases.count, 10)
```

Each case must verify selection → connection ready → application request → receipt → active/held state → mode action → movement stop/completion → final coordinate held.

- [ ] **Step 2: Verify mode-specific outcomes**

- Teleport holds its selected coordinate.
- Jump consumes exactly one acknowledged hop per action.
- Two-Spot ends at destination and holds it.
- Multi-Spot acknowledges every route point and holds the final waypoint.
- Joystick release stops movement and holds its final acknowledged coordinate.

- [ ] **Step 3: Add interruption/recovery cases**

For every mode/transport pair, inject loss before first acknowledgement, during movement, and after completion. Verify desired state persistence, uncertainty, session-generation rollover, reapplication, and no implicit clear.

- [ ] **Step 4: Add failure-truth cases**

Cover rate limiting, queue overflow, timeout, process death, stale endpoint, wrong request ID, stale generation, selected-device replacement, exhausted recovery, and failed explicit clear.

- [ ] **Step 5: Make timing deterministic**

Use injected clocks and event-driven fake acknowledgements. No arbitrary sleeps are permitted in these tests.

- [ ] **Step 6: Run the matrix twice and classify divergence**

```bash
flowdeck test discover
flowdeck test --only PathChangerTests/ModeTransportMatrixTests
flowdeck test --only PathChangerTests/ConnectionInterruptionTests
flowdeck test
flowdeck test
```

Expected: all ten core cases and interruption cases pass identically; any run divergence is a flake finding, not a retry-to-green.

- [ ] **Step 7: Commit and integrate test evidence**

```bash
git add Tests/PathChangerTests/ModeTransportMatrixTests.swift Tests/PathChangerTests/ConnectionInterruptionTests.swift Tests/PathChangerTests/Fakes/FakeLocationInjector.swift Tests/PathChangerTests/LocationSessionRecoveryTests.swift project.yml PathChanger.xcodeproj/project.pbxproj PathChanger.xcodeproj/xcshareddata/xcschemes/PathChanger.xcscheme
git commit -m "test(integration): cover five modes over usb and wifi"
```

Merge after an independent test-review verifies that the fake models receipt/session semantics rather than bypassing them.

## Task 16: Verify the complete GUI workflow in a controlled macOS run

**Branch:** `test/mode-transport-matrix`

**Files:**
- No source changes expected
- Evidence output: external run directory, never the source repository

- [ ] **Step 1: Verify FlowDeck state and current product hash**

```bash
flowdeck license status --json
flowdeck config get --json
flowdeck apps --json
flowdeck build -C ReleaseTesting --json
flowdeck test --json
flowdeck run --json
```

Use isolated DerivedData configured outside the repository. Snapshot the product hash before and after every FlowDeck invocation that can rebuild or launch.

- [ ] **Step 2: Start background macOS UI capture**

Run command-specific help first, then start the session:

```bash
flowdeck ui mac session start --app "PathChanger" --json
```

Capture `latest_screenshot` and `latest_tree`. Use identifier-based `find` and background actions. Verify after every action.

- [ ] **Step 3: Exercise all five modes with deterministic dependencies**

For each mode, verify staged selection, applying, acknowledged active, movement, pause/stop/completion, held final coordinate, explicit clear, loss, and recovery presentation. This confirms GUI integration without touching a phone.

- [ ] **Step 4: Prove no implicit clear in logs/events**

The event log for mode completion, stop movement, transport loss, and transport recovery must contain zero clear requests. Only the explicit Clear action may produce one.

- [ ] **Step 5: Tear down cleanly**

Stop the UI session and development app, close bounded log streams, verify zero PathChanger processes, verify product/source hashes, and delete only run-created external staging when retention policy permits.

## Task 17: Run one owner-approved physical-device matrix

**Branch:** `test/mode-transport-matrix`

**Files:**
- No source changes during acceptance execution
- Evidence output: external redacted run directory

This task requires one explicit owner authorization covering the complete listed hardware plan. After that authorization, do not interrupt the owner for routine choices between cases. Stop only for elevation, an unexpected mutation, a changed device, destructive action outside the plan, or an emergency clear.

- [ ] **Step 1: Freeze device, app, dependency, and network identity**

Record redacted device alias, iOS version, Mac/FlowDeck version, pymobiledevice3 version/lock state, source/product hashes, USB/Wi-Fi availability, and test coordinates. Do not record raw UDIDs or private endpoints.

- [ ] **Step 2: Execute the ten core cases**

For Teleport, Jump, Two-Spot, Multi-Spot, and Joystick over USB and Wi-Fi, record:

```text
mode selection → connection/session → location request → acknowledgement →
independent on-device location observation → hold interval → movement/action →
final on-device location observation → explicit cleanup only at case end
```

The hold interval and observation method must be declared before execution and applied consistently.

- [ ] **Step 3: Execute transport interruption cases**

- Wi-Fi: interrupt temporarily, verify uncertain/reconnecting state, restore, verify new session and automatic reapplication.
- USB: disconnect temporarily, verify uncertain/reconnecting or verified failover, reconnect, verify new session and reapplication.
- Never interpret a refreshed device list alone as recovery success.

- [ ] **Step 4: Verify state synchronization**

At each checkpoint compare GUI connection/application/movement status, latest receipt/session generation, bridge logs, and independent device observation. Any disagreement is a failure finding.

- [ ] **Step 5: Verify persistence and explicit reset**

For every successful case, confirm the spoof remains after movement ends and does not return to real GPS until the planned explicit Clear or an external iOS limitation is observed and documented.

- [ ] **Step 6: Clean up once per case**

Use explicit Clear, verify the device returns to real GPS, stop app/log/UI sessions, and preserve redacted artifacts and hashes. Do not leave a hidden spoof active after the approved test session.

- [ ] **Step 7: Classify all cases**

Each row is PASS, FAIL, BLOCKED, or NOT RUN with evidence. A GUI-only result cannot pass a physical-device row.

## Task 18: Make the runtime and packaging path reproducible and fail closed

**Branch:** `fix/packaging-and-runtime`

**Files:**
- Modify: `install.sh`
- Modify: `build-app-bundle.sh`
- Modify: `build.sh` if it remains a supported public entry point
- Create: `requirements-location.in`
- Create: `requirements-location.lock`
- Modify: `PathChanger/Core/PythonPathResolver.swift`
- Modify: `PathChanger/Core/DependencyValidator.swift`
- Modify: `Tests/PathChangerTests/PythonPathResolverTests.swift`
- Create: `Tests/PathChangerTests/DependencyLockTests.swift`
- Modify: `Resources/PathChanger.entitlements` and `project.yml` only if signing verification proves a mismatch

- [ ] **Step 1: Write RED dependency-policy tests**

Require an exact pymobiledevice3 version, complete transitive lock, hashes for downloaded artifacts, supported Python range, and deterministic managed environment location. Reject unpinned install commands.

- [ ] **Step 2: Write RED packaging fail-closed tests**

A failed build, copy, entitlements application, signing operation, signature verification, or Gatekeeper check must return non-zero and must not replace an existing installed app. Tests operate in temporary directories; never write `/Applications` during unit tests.

- [ ] **Step 3: Generate the lock through an approved reproducible tool**

Generate `requirements-location.lock` with `uv pip compile --generate-hashes requirements-location.in --output-file requirements-location.lock` using the verified `$HOME/.local/bin/uv`. Record the `uv` version and verify all transitive versions/hashes. Do not hand-author dependency entries or upgrade unrelated packages.

- [ ] **Step 4: Use a managed user-level runtime**

Resolve the app's Python from its managed environment, not arbitrary PATH order. A privileged helper/tunnel path must never execute user-writable Python or packages. If typed privilege separation is not yet available, keep privileged execution blocked and report the release blocker rather than weakening ownership checks.

- [ ] **Step 5: Replace fail-open packaging**

Remove `|| true` and success-after-failure paths. Build into external staging, verify the complete bundle/signature/entitlements first, and replace an installed app only through an explicitly authorized atomic installation step with rollback.

- [ ] **Step 6: Verify the FlowDeck/Xcode product separately from the installed artifact**

A built product passing launch checks does not prove `/Applications/PathChanger.app` or the manual bundler is correct. Record hashes and signing matrix results for each artifact independently.

- [ ] **Step 7: Run tests/build/signing checks and commit green**

```bash
flowdeck project packages resolve
flowdeck test
flowdeck build -C Release
flowdeck run --json
```

Use temporary destinations for packaging tests. Commit only after unit/integration checks prove fail-closed behavior:

```bash
git add install.sh build-app-bundle.sh build.sh requirements-location.in requirements-location.lock PathChanger/Core/PythonPathResolver.swift PathChanger/Core/DependencyValidator.swift Tests/PathChangerTests/PythonPathResolverTests.swift Tests/PathChangerTests/DependencyLockTests.swift Resources/PathChanger.entitlements project.yml PathChanger.xcodeproj/project.pbxproj PathChanger.xcodeproj/xcshareddata/xcschemes/PathChanger.xcscheme
git commit -m "fix(release): pin location runtime and fail packaging closed"
```

Stage only changed files. Certificate-dependent Developer ID/Gatekeeper results may remain documented release blockers; they cannot be converted into pass without the real credential.

- [ ] **Step 8: Review and integrate packaging**

Require security review of ownership boundaries, lock generation, shell quoting, destructive paths, signing, and rollback. Merge only after no product/test regression and no privilege expansion.

## Task 19: Final integration, review, and one clean merge

**Branch:** `feature/five-mode-reliability`

**Files:**
- Verify all files changed by accepted topic branches
- Update: `PRODUCT_REQUIREMENTS.md` only with measured evidence/status, not weakened requirements
- Update: release/audit documentation only after results are known

- [ ] **Step 1: Verify topic history**

```bash
git log --graph --decorate --oneline main..feature/five-mode-reliability
git diff --stat main...feature/five-mode-reliability
git diff --check main...feature/five-mode-reliability
git status --short
```

Expected: documentation commits precede one feature integration branch; each topic is represented by reviewed green commits/merge; generated files correspond to `project.yml`; no evidence artifacts or secrets are in source history.

- [ ] **Step 2: Run the complete automated gate twice**

```bash
flowdeck project packages resolve
flowdeck test discover
flowdeck build -C ReleaseTesting
flowdeck test
flowdeck test
flowdeck build -C Release
```

Expected: no unexplained test-count decrease, no failure, no unclassified skip, and no run divergence. Existing accepted flakes remain explicit until causally resolved.

- [ ] **Step 3: Run background macOS GUI verification**

Launch through FlowDeck, start a background session, traverse all five modes by accessibility identifier using deterministic dependencies, verify every action from screenshots and trees, prove no implicit clear, then tear down cleanly.

- [ ] **Step 4: Complete the authorized physical-device matrix**

The ten USB/Wi-Fi cases and interruption/recovery cases must be classified with independent on-device observations. Any blocked or failed core case keeps the feature unmergeable unless the owner explicitly narrows the product requirement in a new revision.

- [ ] **Step 5: Perform independent code, security, and requirements review**

Review the full range against `PRODUCT_REQUIREMENTS.md`. Confirm one location-session-state writer, one tunnel lifecycle writer, typed bridge parity, no user-writable privileged runtime, no fail-open packaging, privacy-safe evidence, and no workaround that hides a failed acknowledgement.

- [ ] **Step 6: Produce a final requirements ledger**

For every requirement in `PRODUCT_REQUIREMENTS.md`, record PASS, FAIL, BLOCKED, or NOT APPLICABLE with test/evidence references. Do not edit historical Stage 0/1 claims.

- [ ] **Step 7: Merge once under explicit final authorization**

After the owner approves the final evidence and the named merge, merge `feature/five-mode-reliability` to normalized `main` without rebasing or squashing the accepted topic history. Push only the reviewed merge and annotated acceptance tag.

- [ ] **Step 8: Verify post-merge identity and clean up**

Re-run the automated gate from `main`, verify commit/tree/tag/remote identity, remove only run-created external worktrees after acceptance, and preserve historical branches until separate cleanup approval.

## Requirement-to-task traceability

| Requirement | Implemented by | Verified by |
|---|---|---|
| Five first-class modes | Tasks 4, 11–13 | Tasks 15–17 |
| Spoof persists until explicit clear | Tasks 5, 9, 11–13 | Tasks 14–17 |
| USB and Wi-Fi reliability | Tasks 7–9 | Tasks 15 and 17 |
| Reconnect and reapply | Tasks 8–9 | Tasks 15 and 17 |
| GUI reflects real known state | Tasks 5 and 14 | Tasks 15–17 |
| Safe Mode/cooldown removed from correctness | Task 10 | Tasks 15–17 |
| pymobiledevice3 integration truth | Tasks 6–9 | Tasks 15–17 |
| Prior behavior used only as evidence | Tasks 0 and 3 | Final requirements ledger |
| Reproducible professional build | Task 18 | Task 19 |
| Reduced routine human review | Execution principles and Task 17 single authorization | Final process review |
| Clean, understandable Git history | Tasks 0–2 and 19 | Task 19 history gate |

## Stop conditions

Stop the current task and report immediately if any of these occurs:

- a source/history ref differs from the recorded execution baseline;
- a file outside the current topic allowlist changes;
- `project.pbxproj` changes without the matching `project.yml`/XcodeGen action;
- a RED test fails for the wrong reason;
- test count decreases without explanation;
- a FlowDeck command uses default/stale DerivedData contrary to the run plan;
- a receipt/session mismatch is ignored;
- a clear/reset occurs without explicit user intent;
- a GUI claim cannot be tied to coordinator state;
- a physical-device action exceeds the approved matrix;
- privilege/elevation appears unexpectedly;
- a packaging step targets `/Applications` before full staged verification and installation authorization;
- secrets, raw device IDs, account data, or private endpoints appear in logs/evidence.

## Completion definition

This plan is complete only when:

1. the history baseline is explicit and old accepted history remains intact;
2. documentation and product commits are separate and reviewable;
3. all five modes pass deterministic and physical USB/Wi-Fi workflows;
4. the final coordinate remains spoofed until explicit Clear in every successful case;
5. reconnect creates a new session and reapplies the desired coordinate before active/movement resumes;
6. the GUI never claims more than acknowledged evidence supports;
7. Safe Mode/cooldown no longer drift, block, or clear location invisibly;
8. the full suite passes twice without unexplained divergence;
9. packaging and runtime resolution fail closed and are reproducible;
10. the final requirements ledger has no failed or silently waived core requirement;
11. default `main`, tags, remote, worktrees, and source tree are reconciled and clean.
