# PathChanger — Operating Protocol (ALWAYS LOAD)

This file defines **how work is performed on PathChanger**. It is binding for every task in this repository unless a more specific, user-approved governance contract narrows the scope further.

**CRITICAL: Read this file completely before writing code, changing configuration, running the app, touching a physical device, mutating Git state, or dispatching implementation work.**

`CLAUDE.md` defines project **HOW**. `PRODUCT_REQUIREMENTS.md` defines required product behavior and acceptance outcomes. Accepted governance and evidence define authorized scope and durable decisions. Repository files, Git state, processes, remote state, and fresh tool output establish observed reality. ByteRover provides durable project memory when available. The task tool tracks current work.

## 0. Project identity and authority map

PathChanger is a macOS 14+ SwiftUI application that simulates location on trusted iOS 17+ devices. It discovers devices, manages pymobiledevice3 tunnels, and drives teleport, route, and joystick workflows through a native GUI.

| Source | Role and authority |
|---|---|
| **User instructions** | Define current intent and final approval. Explicit safety and scope decisions have highest authority. |
| **`PRODUCT_REQUIREMENTS.md`** | Defines the stable functional contract, five-mode behavior, persistence semantics, connection recovery, state truth, and acceptance matrix. It does not itself authorize privileged or physical-device execution. |
| **Accepted governance contracts** | Define authorized files, branches, commands, evidence, review, and acceptance gates for a governed run. A contract may narrow execution scope but may not silently weaken the product requirements or broaden user authorization. **Stage 1 (WP-1.0, WP-1.1, and WP-1.2) is closed.** Stage 2 remains explicitly unauthorized. The five-mode persistence product contract and implementation plan are owner-authorized for the Git operations listed in Task 0–1 and Task 19 sections. |
| **Accepted evidence records** | Establish completed gates, verified findings, and owner decisions. The private `abyssbugg/PathChanger-Evidence` repository is authoritative when a task references a governed run. |
| **`PRODUCT_REQUIREMENTS.md`** | Owner-approved product contract under the authorized five-mode implementation plan. It is binding for all engineering decisions in this repository. |
| **Repository evidence** | Files, Git state, worktrees, processes, remotes, and fresh command output establish current observed state. |
| **`CLAUDE.md`** | Defines the stable operating method for this repository. It is not a backlog or current-status ledger. |
| **ByteRover** | Stores durable decisions, patterns, facts, and gotchas when available. It does not override fresh repository or accepted evidence. |
| **Task tool** | Tracks current scope, dependencies, ownership, and progress. |

Do not smooth over contradictions. State each conflicting claim, cite its source, and use the hierarchy above. If authority or permitted mutation remains uncertain, stop and ask the user.

### Stable project facts

- Primary language and UI: Swift 5.9, SwiftUI, macOS 14+.
- Project generation: `project.yml` is the authored XcodeGen manifest; generated `PathChanger.xcodeproj` changes must be regenerated and reviewed separately.
- Swift package manifest: `Package.swift`; Sparkle is pinned exactly.
- Device/tunnel dependency: Python plus pymobiledevice3.
- Main application entry: `PathChanger/PathChangerApp.swift`.
- Test target: `Tests/PathChangerTests`.
- User-facing behavior is accepted only when verified through the GUI as well as the underlying service path.
- The binding product priority is reliability → correct functionality → truthful state synchronization → connection stability → GUI consistency.
- The five required user modes are Teleport, Jump Teleport, Two-Spot, Multi-Spot, and Joystick.
- A successfully applied spoofed location must remain active until explicit Clear/Reset or an unavoidable external loss that the GUI reports honestly.

### Permanent protocols

Two protocols are always active:

1. **Interruption Recovery Protocol** — reconcile state after a real interruption before resuming.
2. **Lead Engineer Orchestration Protocol** — govern planning, delegation, execution, verification, review, and Git boundaries.

Neither replaces safety, TDD, accepted governance, independent review, or explicit Git-write approval.

---

## 1. Interruption Recovery Protocol

Use this protocol only after a genuine interruption. Recovery is read-only reconciliation, not implementation.

### Read-only recovery sequence

Before changing anything:

1. Establish the repository root, branch, `HEAD`, and status.
2. Inspect staged, unstaged, ignored-relevant, and untracked paths without changing them.
3. Inspect every active worktree and its branch, `HEAD`, and status.
4. Check FlowDeck jobs, UI sessions, app processes, log streams, and other commands that may have survived.
5. When remote operations were authorized, inspect remote branches, commits, reviews, checks, tags, and merge state read-only.
6. Recover the last user-confirmed report, accepted governance record, task state, and terminal result.
7. Compare chat claims, task state, filesystem state, Git state, process state, evidence records, and remote state.
8. Recompute important hashes or counts instead of copying them from prose.

### Decision gate

- **State matches:** report a concise status and resume at the first incomplete authorized step.
- **State differs:** stop and report the discrepancy before any mutation.
- **Outcome or authority is uncertain:** stop and ask the user; do not guess.

### Recovery prohibitions

During recovery, never:

- edit, format, generate, move, delete, or restore files;
- run tests, builds, project generation, or commands that may alter the worktree;
- reset, revert, checkout, clean, stash, rebase, cherry-pick, or merge;
- repeat a commit, push, tag, acceptance, installation, or other potentially completed write;
- accept a subagent or prior report as proof without checking the underlying state;
- expand the previously approved scope.

---

## 2. Lead Engineer Orchestration Protocol

Operate as the lead coordinator and final integrator. Maintain one coherent system model, delegate bounded work, inspect actual outputs, and keep the user as final authority for commits and remote mutations.

### Sources of truth and memory

- Use the task tool for active work and dependency order.
- Query ByteRover before non-trivial work when it is available; curate only durable, verified lessons after substantial work.
- If ByteRover is unavailable, do not invent remembered facts. Continue from accepted governance, repository evidence, and fresh tools when those are sufficient. Stop only when missing memory creates an unresolved authority or safety ambiguity.
- Do not create ad hoc coordination Markdown files. Create documentation only when the user explicitly requests it or an accepted governance contract requires an evidence artifact.
- Do not put transient commit hashes, current stage status, open tasks, or session logs in `CLAUDE.md`.

A non-trivial task includes a feature, bug fix, refactor, behavior change, multi-file investigation, security/privilege work, device/tunnel work, signing/packaging work, or Git-history mutation.

### Work isolation and ownership

- Do not implement directly on `main`. Use the branch or worktree authorized by the user or active governance contract.
- Shared lifecycle state, device identity, privilege boundaries, bridge protocols, generated-project ownership, and cross-cutting behavior remain controller-owned and sequential.
- Delegate bounded tasks with explicit files, dependencies, safety limits, and acceptance criteria.
- Parallelize independent read-only investigation. Do not parallelize overlapping writes or coupled state transitions.
- Never assign two implementation agents to the same files or generated-project boundary.
- Treat subagent output as untrusted until the controller checks files, diffs, hashes, tests, process state, and repository state.
- A fresh review agent must not repair the work it reviews. Report failures and return them to the implementation lane.
- If a subagent is interrupted, silent, or inconsistent, inspect its lane and surviving processes before redispatching.

### Session continuity

For a normal new session or routine resume:

1. Read `CLAUDE.md` completely.
2. Read the active accepted governance/evidence records when the task belongs to a governed run.
3. Query ByteRover when available for non-trivial work.
4. Inspect the task list and relevant repository state.
5. Load every applicable skill before execution.
6. Use Sequential Thinking for every non-trivial problem.
7. Preserve accepted decisions; do not repeat closed work without contradictory evidence.
8. Do not automatically pull, switch branches, commit, push, tag, merge, install, or run a device mutation.
9. Use the Interruption Recovery Protocol after a genuine interruption.

### Acceptance language

Always distinguish:

- **Confirmed:** independently supported by current evidence.
- **Documented but asserted:** stated in a record but not independently reproduced.
- **Suspected:** evidence suggests it, but another cause remains possible.
- **Unknown:** insufficient evidence.

Never report fixed, passing, safe, launchable, releasable, or complete without fresh evidence for that exact claim.

---

## 3. Think before acting — Sequential Thinking MCP

Use Sequential Thinking before every non-trivial task and before changing implementation:

1. Requested outcome or observed behavior.
2. Evidence and reproducibility.
3. Root cause or governing requirement.
4. Affected files, contracts, generated artifacts, and runtime boundaries.
5. Dependency and ownership order.
6. Minimal root-cause strategy.
7. GUI impact and physical-device/privilege risk.
8. Verification, review, Git, and cleanup gates.

If Sequential Thinking is unavailable, stop and report that the required reasoning tool is unavailable. Do not silently bypass it.

Do not re-plan approved work after interruption unless new evidence contradicts the plan. Recover and continue at the first incomplete gate.

---

## 4. Select tools and skills deliberately

| Capability | Required use |
|---|---|
| **Skills** | Load mandatory procedures for brainstorming, debugging, TDD, Apple tooling, verification, and review before acting. |
| **Sequential Thinking MCP** | Structure non-trivial reasoning before implementation. |
| **FlowDeck** | All Apple project discovery, package resolution, build, test, run, logs, UI automation, simulator, and device operations. |
| **Subagents** | Independent research, bounded implementation, or fresh-session review with non-overlapping ownership. |
| **Workspace file tools** | Prefer for reading and precise edits over shell-based file mutation. |
| **Desktop Commander or approved connector** | Read approved external files when direct workspace tools cannot access them; never use it to bypass an explicit safety boundary. |
| **ByteRover** | Retrieve and curate durable verified project memory when available. |
| **Task tool** | Track multi-step work and mark completed gates immediately. |
| **Commands** | Targeted evidence gathering only when a purpose-built tool does not cover the operation. |

Never use raw `xcodebuild`, `xcrun`, `simctl`, `devicectl`, `xcode-select`, or `instruments`. Do not manually parse or hand-edit `project.pbxproj`; change `project.yml` or another approved source and regenerate through XcodeGen.

Use `codesign` and `spctl` only for read-only signing inspection when an accepted plan requires it. They do not replace FlowDeck build/run verification.

---

## 5. Understand and reproduce before changing

The first deliverable in an unfamiliar area is comprehension:

- Trace the GUI action through state, service, process, and device boundaries.
- Read complete errors and structured tool output.
- Reproduce the failure under the same configuration and artifact path.
- Separate a source defect from stale DerivedData, a generated artifact, signing state, environment state, or an installed-app mismatch.
- Inspect recent accepted changes and compare against a known working path.
- Treat a previous working build as a behavioral oracle only after identifying its exact artifact/source and reproducing its behavior; do not invent a historical reference commit.
- Trace invalid state or data to its authoritative writer.
- State one evidence-based root-cause hypothesis before changing anything.

Never stack a workaround on an unknown defect. A temporary workaround must be labeled temporary, explain why it is unavoidable, state its removal condition, and include a verification path.

The GUI is the contract. A service or script-only success is insufficient when the user workflow is GUI-driven.

---

## 6. Test-driven development is mandatory

For features, fixes, refactors, and behavior changes:

1. Write one focused behavioral test.
2. Run it through FlowDeck and observe the expected failure.
3. Implement the smallest production change that addresses the root cause.
4. Run the focused test and observe it pass.
5. Run the affected group and relevant regression suite.
6. Run the full suite when the changed boundary can affect lifecycle, discovery, signing, simulation, or shared state.
7. Verify the GUI flow when behavior is user-visible.
8. Refactor only while all accepted gates remain green.

For build/test configuration defects where tests cannot compile, preserve before evidence of the compile blocker, apply the minimal configuration fix, and prove that discovery and execution are restored without deleting, weakening, or force-skipping tests.

Do not write production behavior before a failing test. Do not weaken assertions to accommodate an implementation. Use mocks/fakes only at genuine external boundaries and prefer deterministic clocks, processes, and device adapters.

Device- and privilege-dependent tests are opt-in. Never set `PATHCHANGER_RUN_DEVICE_TESTS=1`, accept an administrator prompt, start a tunnel, pair a device, or inject location without explicit user authorization and an approved evidence plan.

---

## 7. Git, branch, and commit safety

- Inspect branch, `HEAD`, worktrees, and status before and after scoped work.
- Never overwrite, normalize, restore, or include unrelated user work.
- Do not switch branches, reset, clean, stash, rebase, cherry-pick, merge, or delete a worktree unless explicitly authorized.
- Never assume an untracked file is disposable or a modified file belongs to the current task.
- Do not commit, push, tag, open/modify a pull request, merge, or deploy without fresh explicit user approval or the exact owner decision required by an accepted governance contract.
- Implementation approval is not commit approval. Review approval is not human acceptance.
- Before requesting commit approval, report exact files, authored versus generated changes, tests, GUI evidence, reviews, residual risks, and anything not verified.
- Never amend, force-push, move an accepted tag, or rewrite shared history unless the user explicitly authorizes that exact action.
- Re-fetch and compare expected remote `HEAD` immediately before any remote write. If it changed, stop, reconcile the new commit, and obtain any required revised approval before retrying.
- Use fast-forward-only promotion when the accepted plan requires it; never let an unreviewed commit hitchhike.

Temporary files created for iteration must use the `tmp_rovodev_` prefix and be removed before completion. Evidence staging belongs outside the audited repository unless an accepted contract states otherwise.

---

## 8. PathChanger architecture

### Application composition

- `PathChanger/PathChangerApp.swift` — app entry and `AppState` composition root.
- `PathChanger/UI/ContentView.swift` and `PathChanger/UI/OrganicChrome.swift` — active GUI composition; verify the mounted path before changing a view.
- `PathChanger/Core/StateManagers/DeviceStateManager.swift` — device selection/readiness-facing state.
- `PathChanger/Core/StateManagers/RouteStateManager.swift` — route loading and route-facing state.
- `PathChanger/Core/StateManagers/SimulationStateManager.swift` — simulation-mode and simulation-facing state.

`AppState` remains the composition boundary. Domain managers must not become independent lifecycle authorities.

### Device discovery and tunnel lifecycle

- `PathChanger/Device/DeviceManager.swift` — ingests and reconciles device observations from multiple discovery sources.
- `PathChanger/Device/TunneldManager.swift` — `TunneldManager.shared` is the concrete canonical tunnel lifecycle owner. Start/stop/error/cleanup behavior must not be duplicated in UI or discovery code.
- `PathChanger/Device/TunnelStateMachine.swift` — explicit lifecycle transition model; keep transitions and side effects separate.
- `PathChanger/Device/TunnelHealthMonitor.swift` — liveness/health evidence, not a second lifecycle authority.
- `PathChanger/Device/MultiDeviceCoordinator.swift` — multi-device coordination; never let one device’s state overwrite another’s identity or lifecycle.
- `PathChanger/Device/PrivilegedTunnelCommand.swift` — privilege boundary. Treat command construction, authorization, environment, and cleanup as security-sensitive.

### Location and simulation

- `PathChanger/Device/PersistentLocationBridge.swift` — long-lived location bridge and request/response boundary.
- `PathChanger/Device/DevLocationBridge.swift` — development location service path.
- `PathChanger/Simulation/SimulationEngine.swift` — simulation orchestration.
- `PathChanger/Simulation/SimulationPlanner.swift`, `RouteInterpolator.swift`, `JoystickMovement.swift`, and `MovementPhysics.swift` — planning and movement calculations.
- `PathChanger/GPX` — GPX parsing and route library.
- `PathChanger/MapLayer/MapService.swift` — map integration.

### Supporting boundaries

- `PathChanger/Core` — preferences, dependency validation, logging, rate limiting, telemetry, health, environment, and Python resolution.
- `scripts/location_bridge.py` — Python bridge used by location workflows; never execute it as a substitute for GUI verification.
- `PathChangerCompanion` — companion target and connection service; treat its protocol as a separate integration boundary.
- `Resources/Info.plist` and `Resources/PathChanger.entitlements` — bundle identity and signing inputs.
- `project.yml` — source of truth for generated Xcode project settings.
- `Package.swift` and both `Package.resolved` files — SwiftPM dependency contract; changes require explicit ownership and lockfile reconciliation.

### Architectural invariants

1. **The GUI is the contract.** Trace every user action through state and services; verify the visible result.
2. **Lifecycle is not readiness.** USB/Wi-Fi reachability, trust, discovery, and prepared-device status must not be presented as tunnel-running state. FlowDeck/CoreDevice visibility does not establish simultaneous visibility through pymobiledevice3 usbmux, mobdev2, or RemotePairing; verify each required discovery source independently.
3. **One canonical device identity.** Merge aliases deterministically; do not append duplicate rows from each discovery source.
4. **One tunnel lifecycle owner.** UI controls and transport changes call the lifecycle API; they do not publish competing state.
5. **Applied means acknowledged and healthy.** Never report spoofing active before injection succeeds or after the required retained session/connection is lost.
6. **Movement and spoof persistence are separate.** Pause, movement stop, route completion, joystick disengage, and mode changes hold the last acknowledged location. Only explicit Clear/Reset intentionally returns to real GPS.
7. **Recovery restores desired state.** Preserve the last desired coordinate across temporary USB/Wi-Fi/session loss, report uncertainty, rebuild the channel, and reapply successfully before reporting active.
8. **Safe Mode/cooldown are subordinate.** They must not silently block an injection after active state is published, drift a coordinate without explicit opt-in, clear location, or terminate the spoof session. Remove them if they cannot satisfy the product contract cleanly.
9. **Privilege is explicit.** Unprivileged discovery/preparation and privileged tunnel work remain separated and reviewable.
10. **Generated files are outputs.** Change `project.yml`, regenerate, and review generated differences; do not hand-edit `project.pbxproj`.
11. **Installed and built artifacts are distinct.** Record the exact product path and hash. Success of an isolated build says nothing about an older `/Applications` copy.
12. **Clean artifact evidence matters.** Use fresh isolated DerivedData for root-cause verification and snapshot product hashes around governed FlowDeck invocations.

---

## 9. FlowDeck build, test, run, and GUI workflow

FlowDeck is mandatory for all Apple project discovery, build, test, run, logs, UI automation, simulator, physical-device, package-resolution, and provisioning tasks.

### Preflight

```bash
flowdeck config get --json
flowdeck context --json
```

Respect an existing saved target. Do not reset or overwrite saved configuration unless the user explicitly requests a different target. Governed runs should use an external config and isolated DerivedData rather than changing the user’s saved configuration.

### Build and package resolution

```bash
flowdeck project packages resolve
flowdeck build
flowdeck build -C Release
```

Package updates are dependency changes, not routine resolution. Do not run package update/clear operations without explicit scope.

### Test discovery and execution

```bash
flowdeck test discover
flowdeck test
flowdeck test --only PathChangerTests/TunneldManagerTests/testDeadTunnelProcessClearsRunningState
```

Use the exact identifier returned by discovery for focused tests. Do not guess class/test filters. Run a failing focused reproduction first, then the affected group, then broader verification.

The PathChanger scheme’s test action uses `ReleaseTesting`, a release-derived configuration with testability and DEBUG-only hooks. It is not the shipping Release configuration. Always state this caveat when reporting “Release tests.” Discover and report the current test count; do not assume a historical count.

### macOS launch and GUI observation

```bash
flowdeck apps --json
flowdeck run
flowdeck ui mac session start --app "PathChanger" --json
flowdeck ui mac find "Start tunnel" --app "PathChanger" --json
flowdeck ui mac session stop
```

- Agent-initiated macOS runs and element-targeted background UI actions are non-disruptive.
- Pass `--background` on every macOS UI action.
- Start a UI session before interaction. Read its screenshot and accessibility tree paths.
- Verify the screenshot/tree after every action; do not chain blind interactions.
- Prefer accessibility identifiers, then unique labels. Do not use coordinates unless background targeting fails and the user approves any required foreground operation.
- Stop UI sessions, logs, and app processes during cleanup and prove they ended.

Do not click `Start tunnel`, pairing, preparation, transport restart, location, route, or joystick controls during an idle-observation task.

### Evidence discipline

When a governed run requires evidence:

- Use machine-readable output where a follow-up step consumes fields.
- Use a unique external DerivedData path.
- Snapshot the product tree and executable before and after every build/test/run invocation required by the contract.
- Store complete command, exit, duration, configuration, test classification, and cleanup records.
- Redact home paths, hostnames, email, UDIDs, serials, license/customer identifiers, and device names according to the active evidence policy.
- Create `MANIFEST.sha256` only after redaction and finalization.
- Fresh-clone and rehash evidence before claiming the packet is complete.

---

## 10. Device, privilege, signing, and packaging safety

### Physical device and tunnel hard stops

Without explicit user authorization and a governing test/evidence plan, never:

- start, stop, or restart a tunnel;
- accept an administrator or authorization prompt;
- pair, prepare, mount, erase, reboot, or modify a physical device;
- inject, clear, or simulate location;
- run device-dependent tests;
- change USB/Wi-Fi transport state;
- install an app or helper;
- run a command as root or through AppleScript elevation.

Read-only discovery does not authorize mutation. If the app auto-starts a privileged/device operation, stop it immediately and record the behavior.

### Signing inspection

A local FlowDeck product and an installed app are separate artifacts. Always record which one is inspected.

When authorized, classify independently:

- strict signature verification;
- sealed resources;
- Info.plist binding;
- signature identifier;
- embedded entitlements;
- Team ID;
- Gatekeeper assessment;
- launch/PID stability;
- GUI evidence.

Ad-hoc local signing can support development launch but does not prove Team ID, Gatekeeper, notarization, or release readiness.

### Prohibited packaging scripts

While these scripts remain present and their fail-open/destructive behavior remains unremediated, do not execute them:

- `build-app-bundle.sh`
- `build.sh`
- `install.sh`

Known hazards include suppressed signing failures, non-fatal verification, false success reporting, direct `/Applications` mutation, conflicting staged-app expectations, and deletion of generated products. Treat any later removal of this prohibition as a separately verified governance change.

The current CI workflow contains legacy raw Apple commands and invokes the unsafe bundler. Do not copy CI commands into an agent workflow and do not treat a CI job as authoritative without inspecting its actual checks and known limitations.

---

## 11. Review and completion gates

### Routine engineering autonomy

An explicitly approved scope may come from the user’s direct instruction or an active accepted governance contract. Within that scope, proceed independently through routine analysis, design choices, test writing, implementation, non-destructive verification, and defect correction. Use the existing architecture, `PRODUCT_REQUIREMENTS.md`, tests, and accepted evidence to choose sensible details. Do not ask the user to review every file, intermediate hypothesis, or ordinary technical decision; report at meaningful phase and risk boundaries.

Use subagents and automated reviewers without requesting permission when their work is read-only or already inside the approved scope. Do not invent additional human gates beyond this file and the active governance contract. Human confirmation remains mandatory for destructive Git actions, remote writes, privilege/elevation, physical-device or location mutation outside an approved test plan, foreground desktop control, payment/account actions, scope expansion, and accountable owner acceptance.

### Completion gate

The checklist below is the agent’s work, not a sequence of user approval prompts. Ask the user only at the explicit human boundaries defined above or by the active governance contract.

Before claiming work complete:

1. Re-read the user request and active governance contract.
2. Inspect final branch, `HEAD`, status, worktrees, and processes.
3. Confirm only authorized authored and generated files changed.
4. Confirm generated project output matches the authored manifest change.
5. Run the focused reproduction and observe the expected result.
6. Run affected and broader FlowDeck test/build gates.
7. Run the GUI path for user-visible behavior.
8. Verify no unauthorized device, privilege, installed-app, dependency, or remote mutation occurred.
9. Run an independent specification-compliance review.
10. Resolve accepted findings and rerun affected gates.
11. Run an independent quality/security review for high-risk changes.
12. Verify every review claim against files and fresh tool evidence.
13. Report confirmed results, suspected causes, unknowns, residual risks, and skipped/unverified gates.
14. Ask separately for commit and remote-write approval.
15. Perform bounded cleanup and prove temporary processes/artifacts ended.

A review agent’s PASS is not proof by itself. The controller independently verifies its inputs, outputs, scope, and claimed evidence. Reject reviews that changed the work, used prohibited tools, reused the wrong artifact path, skipped required duties, or relied on operator evidence instead of reproducing it.

For governed work, preserve the required sequence: implementation/evidence → fresh-session technical review → owner acceptance → authorized merge/promotion → cleanup receipt → completion tag.

---

## 12. Documentation and durable knowledge

- `CLAUDE.md` contains stable operating rules only.
- `PRODUCT_REQUIREMENTS.md` is the binding functional contract for five-mode behavior, spoof persistence, transport recovery, state truth, and product acceptance.
- `Consolidated-Source-Of-Truth-Aug-23-2026.md` is the repository’s reconciled historical documentation baseline; later user-approved requirements and accepted evidence may supersede its status or priority claims without rewriting history.
- Governance contracts and accepted evidence belong in the private PathChanger evidence repository when the user authorizes that workflow.
- Repository documentation must distinguish documented-and-evidenced, documented-but-asserted, suspected, unknown, and superseded claims.
- Do not edit accepted historical evidence to make a later result look cleaner. Add a correction or successor record.
- Record durable lessons in ByteRover only after verification; do not store secrets, transient task state, or unsupported hypotheses.

---

## 13. Standard workflow

```text
1. Protocol check       → interruption recovery when required
2. Authority check      → user scope, PRODUCT_REQUIREMENTS, accepted contract/evidence, repository state
3. Memory retrieval     → ByteRover when available; no invented fallback facts
4. Sequential Thinking  → evidence, root cause, files, dependencies, strategy, gates
5. Skill/tool selection → load required procedures; FlowDeck for Apple work
6. Comprehension        → trace GUI-to-device path and reproduce the behavior
7. Scope freeze         → branch/worktree, exact files, generated outputs, safety limits
8. RED                  → focused failure or before-state evidence
9. GREEN                → minimal root-cause implementation
10. Verify              → focused tests, broader tests, build, GUI, safety, cleanup
11. Review              → fresh specification review, then quality/security review
12. Reconcile           → inspect actual files and rerun evidence; reject overclaims
13. Report              → confirmed, asserted, suspected, unknown, residual risk
14. Approval            → explicit commit and remote-write permission
15. Complete            → accepted merge/promotion, cleanup proof, durable learning
```

Stop at any gate when scope, authority, safety, evidence, artifact identity, or repository state differs from the accepted plan.
