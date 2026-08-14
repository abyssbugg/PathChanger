# PathChanger Master Recovery and Integration Roadmap

> **Status 2026-08-14 — READ THIS FIRST.** This file is a backlog, not a delete list and not permission to merge `feat/ui-redesign`. Shipping source is Desktop `main`. Do not pin pymobiledevice3. Do not install Python.framework. Do not merge the managed-Python worktree. Do not `git reset --hard`. Python policy: Homebrew-first, Apple last, latest pymobiledevice3, min 6.1.5. Elevate only tunnel start/stop. New UI is ported in slices onto `main`; never merge the 52-commit redesign branch.

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` or `superpowers:executing-plans` only after the relevant work package has been approved. Track progress by checking each `- [ ]` item. Do not skip verification gates.

**Created:** August 11, 2026  
**Repository:** private `abyssbugg/PathChanger`  
**Current shipping HEAD (see git, not this line):** Desktop `main` — runtime + tunnel elevation already landed after `75321f5`.  
**Historical baseline recorded Aug 11:** `main` at `75321f51b786d319d2ddad568ca4b09364666c5e`  
**Development branch under review:** `feat/ui-redesign` at `05b6cf7ac200807a587439de7eec51e78d19e94a`  
**Goal:** Establish a secure, reproducible, testable, releasable PathChanger baseline through evidence-driven selective integration, without blind-merging the redesign branch or deleting code without reachability proof.

**Architecture direction:** Preserve `main` as the reference baseline while extracting independently valuable work from `feat/ui-redesign` through small PRs. Establish FlowDeck-compatible build infrastructure first, then collect branch runtime evidence, map commit dependencies, converge security/release/process foundations, choose one simulation authority, add deterministic tests, remove only proven dead surfaces, repair documentation, and integrate UI redesign last.

**Tech stack:** Swift 5.9, SwiftUI, macOS 14+, Swift Package Manager, Python 3, `pymobiledevice3`, Sparkle, XCTest, GitHub Actions, Developer ID signing, Apple notarization, FlowDeck 1.26.1.

---

## 0. How to Use This File

- [ ] Treat this file as the single master backlog until a work package receives its own approved implementation plan.
- [ ] Execute work packages in dependency order unless a documented decision explicitly changes the order.
- [ ] Keep `main` and `feat/ui-redesign` conceptually separate until a specific PR is approved.
- [ ] Do not fast-forward or merge the complete redesign branch.
- [ ] Do not cherry-pick a commit merely because its subject looks useful.
- [ ] Inspect every candidate commit's file footprint, prerequisites, tests, and architecture coupling.
- [ ] Prefer additive and reversible changes before deletions or authority transfers.
- [ ] Require fresh FlowDeck evidence for build, launch, test, and UI behavior claims.
- [ ] Mark evidence as `STATICALLY VERIFIED`, `FLOWDECK VERIFIED`, `HISTORICALLY REPORTED`, `INFERRED`, `UNVERIFIED`, or `BLOCKED`.
- [ ] Never treat existing `build/` or `.build/` artifacts as fresh build evidence.
- [ ] Never use `xcodebuild`, `xcrun`, `swift build`, or `swift test` for project validation; use FlowDeck exclusively.
- [ ] Obtain explicit approval before any git tag, branch creation, checkout that changes the primary tree, worktree creation, cherry-pick, merge, rebase, commit, push, or PR operation.
- [ ] Preserve the pre-existing untracked files until their disposition is separately approved.
- [ ] Record every go/no-go result and command output in the relevant PR or verification record.

---

## 1. Verified Repository and Tooling Baseline

### 1.1 Git state

- [x] Current branch verified as `main`.
- [x] Local HEAD verified as `75321f51b786d319d2ddad568ca4b09364666c5e`.
- [x] Remote `origin/main` verified at the same commit.
- [x] Remote default branch verified as `main`.
- [x] `feat/ui-redesign` verified at `05b6cf7ac200807a587439de7eec51e78d19e94a`.
- [x] Branch divergence verified as `0 behind / 52 ahead` relative to `main`.
- [x] Branch delta verified as 194 files, 27,963 insertions, and 12,460 deletions.
- [x] Remote repository verified as private `abyssbugg/PathChanger`.
- [x] No repository tags currently exist.
- [x] No GitHub releases currently exist.
- [x] Both `main` and `feat/ui-redesign` lack `.xcodeproj` and `.xcworkspace` containers.
- [x] Both branches are SwiftPM-based macOS executable packages.

### 1.2 Pre-existing working-tree state

- [x] Record `Hybrid-Universal-Technical-Collaboration-Frameworkn.v3.md` as pre-existing and untracked.
- [x] Record `security-audit-prompt-full.md` as pre-existing and untracked.
- [x] Record `docs/design/mockup-render.png` as pre-existing and untracked.
- [x] Record `docs/design/pc-parity-pass1.png` as pre-existing and untracked.
- [ ] Decide whether the collaboration framework belongs outside the repository, in ignored local notes, or in approved project documentation.
- [ ] Decide whether the security audit prompt belongs in project documentation, an audit archive, or outside the repository.
- [ ] Decide whether design images belong in tracked design documentation, Git LFS, release assets, or ignored local storage.
- [ ] Do not move, delete, stage, or commit these files until that decision is approved.

### 1.3 FlowDeck state

- [x] FlowDeck executable verified at `/opt/homebrew/bin/flowdeck`.
- [x] FlowDeck version verified as `1.26.1 [d8b68b]`.
- [x] FlowDeck license verified active.
- [x] Trial expiration recorded as August 25, 2026.
- [x] PathChanger FlowDeck configuration verified absent.
- [x] `flowdeck context --json` verified unable to discover PathChanger because no `.xcodeproj` or `.xcworkspace` exists.
- [x] FlowDeck configuration help verified to require a workspace or project container.
- [x] FlowDeck project creation verified capable of generating a macOS Xcode project.
- [ ] Treat FlowDeck project-container enablement as the first blocking engineering work package.
- [ ] Do not claim that FlowDeck can currently build PathChanger merely because the CLI is installed and licensed.

### 1.4 Current branch scope

- [x] `main` contains 53 Swift application files and 31 Swift test files.
- [x] `feat/ui-redesign` contains 89 Swift application files and 45 Swift test files.
- [x] `main` contains Sparkle as an SPM dependency.
- [x] `feat/ui-redesign` removes Sparkle from `Package.swift`.
- [x] `main` targets macOS 14 and Swift tools 5.9.
- [x] `main` produces the `PathChanger` executable product.
- [x] `main` processes English and Japanese localization resources.

---

## 2. Non-Negotiable Safety Rules

### 2.1 Git and repository safety

- [ ] Keep all planning and inspection read-only until a specific write action is approved.
- [ ] Before any approved write, capture `git status --short --branch`, full HEAD, remote HEAD, tags, and branch divergence.
- [ ] Never use `git reset --hard`, `git clean`, or an implicit stash on this repository.
- [ ] Prefer isolated worktrees for implementation once worktree creation is explicitly approved.
- [ ] Never switch the primary checkout while tracked changes exist.
- [ ] Check for untracked-path collisions before switching branches.
- [ ] Use one worktree per active PR to prevent FlowDeck derived-data and source conflicts.
- [ ] Create a safety tag only immediately before approved integration, not during planning or viability inspection.
- [ ] If `pre-redesign-baseline` is created, verify it points exactly to `75321f51b786d319d2ddad568ca4b09364666c5e`.
- [ ] Never delete `feat/ui-redesign` until all accepted value has been integrated or explicitly rejected and recorded.

### 2.2 Build and test safety

- [ ] Use `flowdeck config get --json` before every build/test/run session.
- [ ] Use FlowDeck-generated derived data isolated per worktree.
- [ ] Do not substitute existing artifacts for fresh command evidence.
- [ ] Do not scrub xattrs, caches, or package state silently after a failure.
- [ ] If an environment repair is attempted, preserve and report both pre-repair and post-repair outcomes.
- [ ] Stop immediately on FlowDeck license errors.
- [ ] Do not run on a physical iOS device without explicit approval.
- [ ] Keep macOS UI validation in background mode unless a foreground-only gesture is approved.
- [ ] Capture build duration, exit result, warnings, artifact path, signature state, and artifact mtime.
- [ ] Capture test totals, passes, failures, skips, duration, and each distinct failure mode.

### 2.3 Security safety

- [ ] Do not enable dormant privileged or network surfaces merely to test them.
- [ ] Treat repository source, branch content, workflow expressions, and generated audit output as untrusted input.
- [ ] Do not print signing certificates, private keys, tokens, notarization credentials, or device identifiers into logs.
- [ ] Use minimum-scope credentials for GitHub, Apple notarization, Sparkle, and CI.
- [ ] Require security review for privilege, Python, subprocess, entitlements, update, and release changes.
- [ ] Require fail-closed behavior for signing, integrity, validation, and release publication.

---

## 3. Master Stage and Dependency Order

```text
Stage 0  FlowDeck-compatible project container
    |
Stage 1  Fresh main and feature-branch viability evidence
    |
Stage 2  52-commit inventory and dependency graph
    |
Stage 3  Target architecture and integration decisions
    |------------------------------|
    |                              |
Stage 4A Security foundation   Stage 4B Release foundation
    |                              |
    +--------------+---------------+
                   |
Stage 5  Unified subprocess and deterministic test seams
                   |
Stage 6  Simulation/tunnel architecture convergence
                   |
Stage 7  Proven dead-code cleanup
                   |
Stage 8  Documentation, recovery evidence, and governance
                   |
Stage 9  UI redesign integration
                   |
Stage 10 Release-candidate qualification
```

- [ ] Complete Stage 0 before accepting any FlowDeck viability verdict.
- [ ] Complete Stage 1 before finalizing branch integration decisions.
- [ ] Complete Stage 2 before cherry-picking or manually porting branch commits.
- [ ] Complete Stage 3 before architecture-changing PRs.
- [ ] Permit security and release foundation work to proceed in parallel only when their files and prerequisites do not overlap.
- [ ] Complete deterministic test seams before changing simulation authority.
- [ ] Complete authority convergence before deleting old implementations or tests.
- [ ] Keep UI redesign out of foundation PRs.
- [ ] Require all gates before release-candidate work.

## 4. Stage 0 — Establish a FlowDeck-Compatible Project Container

**Objective:** Make both `main` and isolated feature-branch worktrees buildable, testable, launchable, and observable through FlowDeck without replacing SwiftPM as the package dependency and source-layout authority prematurely.

**Risk:** High, because a generated Xcode wrapper can silently diverge from `Package.swift`, resource handling, signing, entitlements, and release scripts.

### 4.1 Decide the project-container approach

- [ ] Create a planning record comparing these approaches:
  - Checked-in `PathChanger.xcodeproj` wrapper around existing sources and tests.
  - Checked-in `.xcworkspace` containing an Xcode application wrapper and the local Swift package.
  - External FlowDeck enhancement for direct SwiftPM executable support.
- [ ] Reject any approach that requires using raw Apple CLI tools for normal validation.
- [ ] Reject any approach that duplicates production source files into generated folders.
- [ ] Require `Package.swift` and Xcode build settings to agree on macOS 14, product name, localization resources, and dependencies.
- [ ] Select a single source of truth for target membership.
- [ ] Document whether SwiftPM remains the canonical package definition after the Xcode wrapper is added.

### 4.2 Preview FlowDeck project generation

- [ ] Run a FlowDeck dry run only after the work package is approved:

```bash
flowdeck project create PathChanger \
  --platforms macos \
  --macos-target 14.0 \
  --bundle-id com.pathchanger.app \
  --path /Users/datamatics/Documents.worktrees/PathChanger/flowdeck-preview \
  --dry-run
```

- [ ] Capture every proposed generated file.
- [ ] Confirm the dry run does not modify the repository.
- [ ] Review generated deployment target, bundle identifier, signing defaults, app entry point, resource phases, and test target.
- [ ] Determine how to remove generated template source without deleting existing PathChanger sources.
- [ ] Determine how the wrapper references `PathChanger/`, `Resources/`, `Tests/PathChangerTests/`, and Sparkle on `main`.
- [ ] Determine how the wrapper behaves on `feat/ui-redesign`, where Sparkle is absent from `Package.swift`.

### 4.3 Implement the wrapper in a dedicated PR

**Proposed branch:** `phase0/flowdeck-project-wrapper`  
**Proposed commit:** `build(flowdeck): add PathChanger Xcode project wrapper`

- [ ] Branch from verified `main` only after explicit approval.
- [ ] Create the wrapper in an isolated worktree.
- [ ] Preserve `Package.swift` unchanged unless parity requires a separately reviewed correction.
- [ ] Reference existing production sources rather than copying them.
- [ ] Create a macOS application scheme named `PathChanger`.
- [ ] Create or expose a test scheme that runs `PathChangerTests`.
- [ ] Set the deployment target to macOS 14.0.
- [ ] Set the product bundle identifier to the approved canonical identifier.
- [ ] Include English and Japanese localization resources.
- [ ] Apply `Resources/PathChanger.entitlements` only after entitlement policy is explicitly reviewed.
- [ ] Ensure Info.plist ownership is unambiguous; do not keep two independently maintained plists.
- [ ] Ensure Sparkle embedding and runtime search paths match the intended `main` build.
- [ ] Ensure generated build output does not overwrite `build/PathChanger.app` unless explicitly configured.
- [ ] Configure FlowDeck using the saved project wrapper and `My Mac` target.
- [ ] Record the resulting FlowDeck configuration without exposing machine-specific secrets.

### 4.4 Stage 0 verification gate

- [ ] `flowdeck config get --json` succeeds from the approved worktree.
- [ ] `flowdeck context --json` reports the expected project, scheme, configuration, and macOS target.
- [ ] `flowdeck project schemes` lists `PathChanger` and the expected test scheme.
- [ ] `flowdeck project configs` lists Debug and Release.
- [ ] `flowdeck build` reaches compilation rather than discovery/configuration failure.
- [ ] `flowdeck test discover` identifies the intended test target or reports an actionable project-level limitation.
- [ ] Package resources exist in the built app at the paths expected by localization code.
- [ ] The Xcode wrapper introduces no duplicate app entry point.
- [ ] The wrapper can be reverted as one PR without altering SwiftPM source behavior.

**No-go conditions:** duplicate targets, missing resources, different runtime behavior from SwiftPM packaging, hidden signing requirements, generated source copies, or inability to run tests through FlowDeck.

---

## 5. Stage 1 — Fresh Viability Evidence

**Objective:** Produce fresh, sequential, command-backed evidence for `main` and `feat/ui-redesign` after Stage 0, without interpreting evidence as merge authorization.

### 5.1 Revise and approve the viability procedure

- [ ] Check FlowDeck path, version, license, configuration, project context, and target before any Git write.
- [ ] Remove baseline tag creation from the viability run.
- [ ] Explicitly permit ignored FlowDeck build outputs, derived data, logs, test bundles, and the result document.
- [ ] Prefer an approved isolated worktree over switching the primary checkout.
- [ ] Define `GREEN` as build success, launch success, and all required deterministic tests passing.
- [ ] Define `AMBER` as build and launch success with test failures, test startup failure, or unresolved critical skips.
- [ ] Define `RED` as build failure, launch failure, or immediate crash.
- [ ] Define `BLOCKED` as unavailable FlowDeck, license, project configuration, target, or required environment.
- [ ] State that GREEN confirms runtime viability only and does not authorize integration.

### 5.2 Capture the `main` control baseline

- [ ] Record full commit and working-tree snapshot.
- [ ] Run fresh Debug build through FlowDeck.
- [ ] Run fresh Release build through FlowDeck.
- [ ] Launch the app hidden through FlowDeck.
- [ ] Start a background macOS UI session.
- [ ] Confirm a PathChanger window and accessibility tree are present.
- [ ] Capture startup logs and first visible error state.
- [ ] Terminate the app cleanly through FlowDeck.
- [ ] Run the complete deterministic test suite.
- [ ] Record passed, failed, skipped, blocked, and duration totals.
- [ ] Record Sparkle, xattr, resource, code-signing, package, and runtime-loader failures verbatim if encountered.
- [ ] Record artifact path, signature state, bundle metadata, and mtime.

### 5.3 Capture `feat/ui-redesign` viability

- [ ] Create an isolated feature worktree only after approval.
- [ ] Verify feature worktree HEAD exactly matches `05b6cf7ac200807a587439de7eec51e78d19e94a`.
- [ ] Configure the same FlowDeck wrapper strategy and equivalent target.
- [ ] Run Debug build through FlowDeck.
- [ ] Run Release build through FlowDeck.
- [ ] Launch the app hidden through FlowDeck.
- [ ] Confirm a PathChanger window and accessibility tree are present.
- [ ] Capture startup logs and first visible error state.
- [ ] Terminate cleanly.
- [ ] Run deterministic tests.
- [ ] Record totals and each distinct failure.
- [ ] Verify package/resource differences caused by Sparkle removal.
- [ ] Verify whether the redesigned window can recover after close/reopen.
- [ ] Verify whether tunnel startup requests administrator privileges.
- [ ] Verify whether root-owned tunnel processes survive stop, quit, crash, and relaunch scenarios only in an authorized safe test environment.

### 5.4 Feature-branch survival checks

- [ ] Search for `with administrator privileges` in production source.
- [ ] Verify whether `PathChanger/Device/PersistentLocationBridge.swift` exists.
- [ ] Search production source for StateManager definitions and instantiations.
- [ ] Trace joystick direction from UI event to coordinate calculation and bridge injection.
- [ ] Trace route playback from UI command to injected coordinates.
- [ ] Trace teleport from UI command to bridge execution.
- [ ] Inventory each `Process()` invocation.
- [ ] Verify whether output is drained concurrently before waiting for process exit.
- [ ] Verify presence and usage of `scripts/validate-release-config.sh`.
- [ ] Verify presence and usage of `scripts/validate-w1-convergence-lock.sh`.
- [ ] Verify dependency lock enforcement.
- [ ] Verify privilege-path writable-ancestor checks.
- [ ] Verify GPX size, point-count, coordinate, and parser limits.
- [ ] Verify entitlement policy tests.

### 5.5 Stage 1 output and gate

- [ ] Produce a bounded evidence record containing exact commands, relevant output, exit results, durations, and labels.
- [ ] Compare `main` and feature evidence without averaging contradictions.
- [ ] Mark static observations separately from runtime observations.
- [ ] Record any drift from the pre-run repository snapshot.
- [ ] Remove the isolated worktree only after confirming no needed evidence exists solely inside it.
- [ ] Do not propose remediation inside the viability result.

---

## 6. Stage 2 — Complete 52-Commit Inventory

**Objective:** Classify every commit unique to `feat/ui-redesign`, identify dependencies and mixed concerns, and assign a safe integration disposition before any porting action.

### 6.1 Required disposition labels

For each commit below, complete all unchecked fields:

- [ ] Primary category and secondary categories.
- [ ] Exact files and symbols affected.
- [ ] Hard parent dependencies.
- [ ] Soft/architectural dependencies.
- [ ] Dependence on redesigned UI.
- [ ] Conflict risk against current `main`.
- [ ] Existing tests and missing tests.
- [ ] Security and release implications.
- [ ] Integration mode: `CHERRY-PICK UNCHANGED`, `CHERRY-PICK AFTER PREREQUISITES`, `SPLIT BEFORE PORTING`, `MANUALLY REIMPLEMENT`, `DOCUMENTATION ONLY`, `DEFER`, or `REJECT`.
- [ ] Go/no-go evidence required before integration.

### 6.2 Commit inventory, group A — early mixed feature work

1. **`1c71caf` — 2026-05-02 — `feat: refresh UI and stabilize device workflows`**
   - [ ] Classify as a large mixed UI/device/Python/tunnel/history change.
   - [ ] Separate reusable device and bridge fixes from UI redesign and AppState churn.
   - [ ] Do not cherry-pick unchanged without a commit-level split.
2. **`27e01f8` — 2026-05-05 — `feat: stabilize tunnels and polish UI`**
   - [ ] Separate tunnel lifecycle fixes, persistent bridge changes, WiFi pairing scripts, tests, and broad UI rewrites.
   - [ ] Verify dependence on `1c71caf`.
   - [ ] Treat as split-before-porting.
3. **`59dbe40` — 2026-05-06 — `feat(ui): map-dominant Apple-Maps-style shell + WiFi cleanups`**
   - [ ] Separate map shell components from WiFi tunnel fixes and tests.
   - [ ] Defer map shell until foundation gates pass.
   - [ ] Evaluate WiFi fixes independently.
4. **`c1d550b` — 2026-05-17 — `Finalize release validation workflow and packaging remediation`**
   - [ ] Identify useful packaging changes, dead-surface removals, release workflow changes, and resource handling.
   - [ ] Compare against `main` commit `75321f5` and later branch reconciliation `b009fc8`.
   - [ ] Split before porting; do not transplant the full mixed commit.
5. **`b0a94ef` — 2026-05-22 — `ui(refinement): surgical operational UX refinement + active transport mapping guard`**
   - [ ] Determine whether transport mapping guard is independent of UI changes.
   - [ ] Defer purely visual work.
6. **`fb99cf4` — 2026-05-22 — `ui(refinement): pin floating mode panels to bottom + drop dead joystick caption`**
   - [ ] Classify as UI-only unless runtime behavior changed.
   - [ ] Defer until joystick architecture is verified.

### 6.3 Commit inventory, group B — July architecture and redesign stack

7. **`37ff779` — 2026-07-02 — iOS 27 tunnel/RSD, persistent daemon, health, spoof persistence**
   - [ ] Split transport compatibility, daemon lifecycle, RSD rotation, persistence, and UI impacts.
   - [ ] Verify iOS version terminology and actual supported APIs.
   - [ ] Require device-independent tests plus authorized hardware evidence.
8. **`b18a51e` — 2026-07-02 — AppState split, window lifecycle, logging/subprocess hardening**
   - [ ] Evaluate AppState extensions as a candidate structural improvement.
   - [ ] Separate window lifecycle and subprocess changes into independent PRs.
   - [ ] Identify dependency on `37ff779`.
9. **`035dd84` — 2026-07-02 — Apple-Maps shell and design system**
   - [ ] Classify as UI architecture.
   - [ ] Defer until foundation and simulation authority are stable.
10. **`e59f74b` — 2026-07-02 — tests for transport, daemon health, indicator, and spoof persistence**
    - [ ] Map each test to live production behavior.
    - [ ] Retain tests only with corresponding accepted production work.
11. **`e482a10` — 2026-07-02 — companion app and shared protocol updates**
    - [ ] Decide companion product scope before integration.
    - [ ] Defer unless the companion is explicitly retained.
12. **`9974a1e` — 2026-07-02 — CI/release/deployment/packaging/README**
    - [ ] Split workflows, scripts, docs, and packaging.
    - [ ] Compare with later release and CI commits to avoid porting superseded states.
13. **`f0fb318` — 2026-07-02 — per-mode accent tokens and palette**
    - [ ] Classify as UI-only and defer.
14. **`d4e2beb` — 2026-07-02 — DeviceDropdown component**
    - [ ] Verify accessibility and live-state dependencies.
    - [ ] Defer to UI integration.
15. **`5d0d265` — 2026-07-02 — ConnectionPill component**
    - [ ] Verify state model dependency.
    - [ ] Defer to UI integration.
16. **`ede304b` — 2026-07-02 — ThemeToggle**
    - [ ] Verify persistence behavior and test coverage.
    - [ ] Defer to UI integration.
17. **`18a255e` — 2026-07-02 — integrate DeviceDropdown with tunnel state**
    - [ ] Verify dependency on `d4e2beb`, `5d0d265`, and tunnel state changes.
    - [ ] Defer until canonical tunnel state is chosen.
18. **`fb4613e` — 2026-07-02 — governed top-bar swap and readiness authority**
    - [ ] Inspect whether readiness authority changes architecture rather than presentation.
    - [ ] Do not port before target state authority is approved.

19. **`35a24e6` — 2026-07-02 — per-mode accents and Liquid Glass panels**
    - [ ] Classify as UI-only unless it changes interaction behavior.
    - [ ] Defer.
20. **`ef027dc` — 2026-07-02 — TelemetryBar**
    - [ ] Verify whether displayed telemetry is sourced from real runtime metrics.
    - [ ] Defer presentation; retain tests only with accepted metrics sources.
21. **`bca1af4` — 2026-07-02 — LibraryFlyout**
    - [ ] Verify favorites/history data dependencies and migration behavior.
    - [ ] Defer UI; consider data-store changes separately.
22. **`b897b6c` — 2026-07-02 — rebuild window layout for mockup parity**
    - [ ] Classify as a large UI-layout boundary.
    - [ ] Defer until foundation, accessibility, and state authority gates pass.

### 6.4 Commit inventory, group C — audited security remediation waves

23. **`c7f1f84` — 2026-07-21 — baseline snapshot and Wave 0 privileged-path containment**
    - [ ] Identify whether this is a merge/snapshot commit or contains unique code.
    - [ ] Do not port without mapping parent commits and duplicate changes.
24. **`0f8400a` — 2026-07-21 — six-agent security and code-integrity audit reports**
    - [ ] Treat as documentation evidence, not executable remediation.
    - [ ] Validate each retained claim against current target code.
    - [ ] Port only reports still useful after corrections.
25. **`0fe4f99` — 2026-07-21 — build/install TOCTOU and fail-close hardening**
    - [ ] Review `build-app-bundle.sh`, `build.sh`, and `install.sh` independently.
    - [ ] Prefer manual reimplementation if based on feature-only packaging assumptions.
    - [ ] Require shell tests or reproducible dry runs.
26. **`0db795f` — 2026-07-21 — hashed Python lock, CI verification, gitignore hardening**
    - [ ] Evaluate `requirements-pathchanger.txt` and `.lock` as a security-foundation candidate.
    - [ ] Verify hashes, Python version compatibility, platform markers, and update process.
    - [ ] Consider porting after Python environment ownership is decided.
27. **`de51f15` — 2026-07-21 — Wave 0 build/install merge commit**
    - [ ] Determine whether it contains changes beyond `0fe4f99`.
    - [ ] Do not cherry-pick merge commits when the underlying commit is sufficient.
28. **`7483dc3` — 2026-07-21 — Wave 0 Python lock merge commit**
    - [ ] Determine whether it contains changes beyond `0db795f`.
    - [ ] Prefer source commit or manual port over merge commit.
29. **`37a9ca8` — 2026-07-21 — interim privileged-path hardening**
    - [ ] Inspect `PrivilegedPathSecurity`, path allowlists, ownership checks, writable-ancestor checks, and tests.
    - [ ] Determine whether protections close or merely reduce the root-of-user-Python risk.
    - [ ] Candidate for security-first manual port after process ownership design.
30. **`7fdbacb` — 2026-07-21 — Wave 1 privileged hardening merge commit**
    - [ ] Determine unique changes.
    - [ ] Avoid cherry-picking if only merging `37a9ca8`.
31. **`5b5c8be` — 2026-07-21 — remove dormant companion host and entitlements**
    - [ ] Prove CompanionHostService is unreachable on both branches.
    - [ ] Decide product scope for companion functionality.
    - [ ] Delete only after product decision and call-graph proof.
32. **`139dffe` — 2026-07-21 — Wave 2 companion cleanup merge commit**
    - [ ] Determine unique changes.
    - [ ] Prefer the source commit or a clean reimplementation.
33. **`14eabef` — 2026-07-21 — GPX DoS caps and validation**
    - [ ] Review size caps, point limits, coordinate bounds, parser contexts, and error messages.
    - [ ] Candidate for an early, isolated security PR.
    - [ ] Add regression tests before porting implementation.
34. **`ae26c67` — 2026-07-21 — Wave 2 GPX merge commit**
    - [ ] Determine unique changes.
    - [ ] Avoid duplicate integration.
35. **`d6a44ee` — 2026-07-21 — pin SwiftLint, add gitleaks, assert entitlement policy**
    - [ ] Split lint pin, secret scanning, and entitlement policy into independently reviewable CI changes if needed.
    - [ ] Verify third-party action versions and permissions.
    - [ ] Ensure checks fail closed.
36. **`8f137d3` — 2026-07-21 — Wave 2 CI security merge commit**
    - [ ] Determine unique changes.
    - [ ] Prefer source commit or clean manual implementation.
37. **`fbc32be` — 2026-07-21 — bounded concurrent subprocess capture and SIGKILL escalation**
    - [ ] Review concurrent stdout/stderr draining, timeout synchronization, termination escalation, file descriptor cleanup, and output caps.
    - [ ] Determine whether it solves only DeviceManager or provides a reusable runner pattern.
    - [ ] Candidate input for unified subprocess work, not necessarily a direct cherry-pick.
38. **`7962d1a` — 2026-07-21 — Wave 2 subprocess merge commit**
    - [ ] Determine unique changes.
    - [ ] Avoid duplicate integration.
39. **`e41e39e` — 2026-07-21 — plist dedup, ADR supersession, CODEOWNERS, ADR 004**
    - [ ] Split Info.plist deletion, ADR updates, CODEOWNERS, and icon-script changes.
    - [ ] Port governance/documentation only after validating current ownership and architecture.
    - [ ] Do not delete a plist until Xcode/SwiftPM wrapper ownership is settled.
40. **`a49db5b` — 2026-07-21 — Wave 3 cleanup/ADR/CODEOWNERS merge commit**
    - [ ] Determine unique changes.
    - [ ] Prefer source commits or reviewed manual ports.

### 6.5 Commit inventory, group D — July 26 reconciliation and CI stabilization

41. **`b009fc8` — 2026-07-26 — reconcile release validation with ad-hoc distribution posture**
    - [ ] Compare with `main` release-validation workflow and ADR 005.
    - [ ] Decide whether ad-hoc distribution remains an interim policy or is rejected.
    - [ ] Do not let validation claims imply notarized public release.
42. **`c165c48` — 2026-07-26 — repair release-blocking compile errors**
    - [ ] Identify exact compiler errors and their prerequisite branch state.
    - [ ] Port only if equivalent errors exist after accepted prior work.
43. **`9001b3c` — 2026-07-26 — split TunneldManager tests and clear lint errors**
    - [ ] Evaluate test-file split independently from behavior changes.
    - [ ] Port structural test cleanup only with stable production APIs.
44. **`caa07bf` — 2026-07-26 — ADR 005 ad-hoc distribution posture**
    - [ ] Review policy against the desired signed/notarized release objective.
    - [ ] Retain as historical ADR only if clearly marked superseded when production signing is adopted.
45. **`bc9853c` — 2026-07-26 — Dependabot and SECURITY.md**
    - [ ] Candidate for an isolated governance PR.
    - [ ] Review Dependabot ecosystem, schedule, target branch, labels, and private-repository behavior.
    - [ ] Review SECURITY.md contact and supported-version claims.
46. **`f8960a3` — 2026-07-26 — macos-26 CI and deployment-doc removal**
    - [ ] Verify current GitHub runner labels and compatibility before porting.
    - [ ] Review whether deleting deployment docs preserves required operational knowledge.
    - [ ] Split CI runner update from documentation deletion.
47. **`9e7cb01` — 2026-07-26 — lint cleanup and structural exceptions**
    - [ ] Defer until corresponding files have been accepted.
    - [ ] Do not port lint suppressions without reviewing each justification.
48. **`323c089` — 2026-07-26 — CI triggers, hygiene, and project agent notes**
    - [ ] Split CI trigger changes, gitignore changes, CLAUDE.md, and design-image deletion.
    - [ ] Do not delete pre-existing design images without an approved disposition.
49. **`61d555f` — 2026-07-26 — hermetic launch tests and UDID fixture correction**
    - [ ] Evaluate after accepted launch-orchestration APIs exist.
    - [ ] Candidate for test-foundation port with prerequisites.
50. **`51979da` — 2026-07-26 — unit-test timeout and workflow deduplication**
    - [ ] Verify actual test duration from FlowDeck and CI evidence before raising budgets.
    - [ ] Review concurrency cancellation behavior.
51. **`5516d33` — 2026-07-26 — transient-recovery wait ceiling**
    - [ ] Verify whether the test is masking slowness or matching a legitimate operation bound.
    - [ ] Prefer event-based synchronization over larger sleeps.
52. **`05b6cf7` — 2026-07-26 — collapse PR/push runs into one concurrency group**
    - [ ] Verify workflow event matrix and cancellation semantics.
    - [ ] Candidate only after the canonical CI workflow is chosen.

### 6.6 Stage 2 deliverables

- [ ] Produce one 52-row commit table with date, categories, file footprint, dependencies, risk, tests, disposition, and rationale.
- [ ] Produce a commit dependency graph.
- [ ] Identify merge commits with no unique changes.
- [ ] Identify commits that mix security, architecture, release, and UI work.
- [ ] Identify commits safe to cherry-pick unchanged.
- [ ] Identify commits that must be manually reimplemented.
- [ ] Identify superseded commits.
- [ ] Identify work that should be rejected.
- [ ] Identify work deferred to UI or future product scope.
- [ ] Obtain human approval of the commit inventory before integration planning becomes executable.

---

## 7. Stage 3 — Select the Canonical Target Architecture

**Objective:** Choose explicit runtime owners and boundaries before moving code between branches.

### 7.1 Map current `main`

- [ ] Document `AppState` as application composition/state authority.
- [ ] Trace teleport ownership from UI to `AppState.setLocation` to `DevLocationBridge`.
- [ ] Trace route playback ownership in `AppState.startRoutePlayback`.
- [ ] Record joystick direction as published state without a live injection consumer.
- [ ] Record `SimulationEngine` instantiation and the UI paths that bypass it.
- [ ] Record StateManagers as definitions/tests without production instantiation.
- [ ] Map `DeviceManager`, `DevLocationBridge`, `TunneldManager`, `TunnelStateMachine`, and `PythonPathResolver` responsibilities.
- [ ] Inventory duplicated state, mode enums, subprocess runners, health loops, and error taxonomies.

### 7.2 Map `feat/ui-redesign`

- [ ] Document AppState extension split and composition boundaries.
- [ ] Trace teleport, route, joystick, history, recovery, and UI readiness authority.
- [ ] Map the renamed/replaced `LocationBridge` implementation.
- [ ] Map TunneldManager extension files and state ownership.
- [ ] Determine whether StateManagers and PersistentLocationBridge are removed or replaced.
- [ ] Determine whether the redesigned UI relies on branch-only stores or migrations.
- [ ] Map companion, multi-device, telemetry, history, and library behavior.

### 7.3 Choose one target owner per concern

- [ ] Choose one application-state composition root.
- [ ] Choose one simulation authority for teleport, route, and joystick.
- [ ] Choose one tunnel-state authority.
- [ ] Choose one process-execution abstraction.
- [ ] Choose one Python environment resolver/validator.
- [ ] Choose one device-discovery authority.
- [ ] Choose one connection/readiness presentation source.
- [ ] Choose one error taxonomy and propagation boundary.
- [ ] Choose one history/favorites storage authority.
- [ ] Choose whether companion and multi-device support are retained, deferred, or removed.

### 7.4 Recommended target principles

- [ ] Keep `AppState` as composition root, not as the implementation of every operation.
- [ ] Route teleport, route, and joystick through one injected simulation service.
- [ ] Put subprocess execution behind a protocol and actor/service boundary.
- [ ] Keep tunnel transitions in one reducer/state machine and serialize side effects.
- [ ] Prevent UI components from becoming independent state authorities.
- [ ] Make Python interpreter identity immutable for the lifetime of an operation.
- [ ] Keep privileged lifecycle separate from ordinary subprocess execution.
- [ ] Make all critical dependencies mockable for deterministic tests.
- [ ] Preserve SwiftUI main-actor correctness while running blocking work off the main actor.

### 7.5 Stage 3 gate

- [ ] Publish a reviewed architecture decision diagram.
- [ ] Document each chosen owner and rejected alternative.
- [ ] Identify migration steps from `main` to target architecture.
- [ ] Identify branch commits that implement, conflict with, or partially implement the target.
- [ ] Require security and test review before approval.
- [ ] Do not start architecture convergence until this decision is approved.

---

## 8. Stage 4A — Security Foundation

### 8.1 Privilege-boundary inventory

- [ ] Inventory every administrator-privilege request.
- [ ] Record executable path, arguments, environment, working directory, output destination, and lifecycle for each privileged command.
- [ ] Verify whether shell metacharacters are still used to redirect output or background processes.
- [ ] Verify whether privileged commands execute Homebrew, pyenv, user-site, or other mutable code.
- [ ] Trace PID acquisition, persistence, ownership checks, graceful stop, forced stop, crash behavior, and relaunch cleanup.
- [ ] Define expected behavior when the user cancels authentication.
- [ ] Define expected behavior when startup succeeds but PID discovery fails.

### 8.2 Python trust chain

- [ ] Choose one Python environment model.
- [ ] Ensure validation and execution use the same interpreter.
- [ ] Remove hardcoded `/usr/bin/python3` dependency checks that disagree with runtime selection.
- [ ] Define accepted interpreter locations and ownership rules.
- [ ] Reject interpreters with writable ancestors where privileged execution is involved.
- [ ] Define whether Python is bundled, installed into an app-owned environment, or externally managed.
- [ ] Pin `pymobiledevice3` and transitive dependencies with hashes.
- [ ] Define a reviewed dependency-update process.
- [ ] Prevent user-site packages from influencing privileged execution.
- [ ] Define integrity checks and failure behavior.

### 8.3 Privileged lifecycle design

- [ ] Compare interim hardened AppleScript execution with a launchd/helper architecture.
- [ ] Decide Phase 0 scope: containment on current design versus full helper redesign.
- [ ] Ensure stop operations can terminate the processes started by the app.
- [ ] Persist enough lifecycle metadata to recover after app crash.
- [ ] Validate PID identity before termination to prevent killing unrelated processes.
- [ ] Avoid PID-only trust after reuse; include executable/arguments/start-time checks.
- [ ] Define stale-record cleanup.
- [ ] Define behavior when root cleanup cannot be completed.
- [ ] Surface a clear warning instead of logging false cleanup success.

### 8.4 Input and file safety

- [ ] Port or reimplement GPX byte caps.
- [ ] Port or reimplement GPX point-count caps.
- [ ] Preserve XXE protection.
- [ ] Add symlink and regular-file policy.
- [ ] Validate every coordinate at parser and injection boundaries.
- [ ] Validate UDID, RSD address, and port inputs consistently.
- [ ] Review route-library import/export paths.
- [ ] Review logs for sensitive device identifiers and command contents.

### 8.5 Security CI and governance

- [ ] Add fail-closed secret scanning with pinned tooling.
- [ ] Add entitlement-policy assertions.
- [ ] Pin SwiftLint or document its version policy.
- [ ] Add Dependabot only after reviewing update scope and target branch.
- [ ] Add SECURITY.md with accurate contact and support policy.
- [ ] Add CODEOWNERS only after confirming real owner handles.
- [ ] Require least-privilege GitHub workflow permissions.
- [ ] Prevent untrusted release metadata from becoming executable shell syntax.

### 8.6 Security gate

- [ ] Same interpreter used for dependency validation and execution.
- [ ] Privileged execution cannot load mutable user-site packages.
- [ ] Privileged process cleanup is reliable or explicitly reports failure.
- [ ] Command construction is structured and fail closed.
- [ ] GPX and file-import limits have regression tests.
- [ ] Entitlement policy is explicit and tested.
- [ ] No high-severity privilege regression remains unowned.

## 9. Stage 4B — Release and CI Foundation

### 9.1 Decide distribution policy

- [ ] Decide whether Phase 0 supports internal/ad-hoc artifacts, external signed releases, or both as clearly separated channels.
- [ ] If ad-hoc builds remain, label them internal/development and never publish them as trusted production releases.
- [ ] Define the production requirement as Developer ID signing, notarization acceptance, stapling, Gatekeeper acceptance, and Sparkle signature validation.
- [ ] Confirm the canonical bundle identifier.
- [ ] Confirm the GitHub release repository and appcast host.
- [ ] Generate a project-owned Sparkle key pair only through approved secure procedures.
- [ ] Store private signing material only in approved secret stores.
- [ ] Record key rotation and recovery procedures.

### 9.2 Repair build scripts

**Files:** `build-app-bundle.sh`, `build.sh`, `install.sh`, `DEPLOYMENT/01_PRE_DEPLOYMENT_VERIFICATION.sh`

- [ ] Make `APP_BUNDLE_BUILD_ROOT` authoritative when provided.
- [ ] Make `REQUIRE_PRODUCTION_SIGNING=1` fail if a valid production identity is unavailable.
- [ ] Remove `|| true` from signing operations that determine artifact trust.
- [ ] Fail if frameworks, resources, scripts, localization bundles, or metadata are missing.
- [ ] Use collision-safe temporary directories.
- [ ] Prevent workspace and build-output TOCTOU substitutions.
- [ ] Quote every path and argument safely.
- [ ] Ensure cleanup affects only paths created by the current invocation.
- [ ] Ensure local development builds remain possible without pretending to be production artifacts.
- [ ] Add script-level tests or dry-run validation for all branches.

### 9.3 Repair release validation workflow

**File:** `.github/workflows/release-validation.yml`

- [ ] Add or port `scripts/validate-release-config.sh` after reviewing branch implementation.
- [ ] Add or port `scripts/validate-w1-convergence-lock.sh` only if the W1 lock policy remains relevant.
- [ ] Ensure every referenced script exists and is executable.
- [ ] Ensure validation uses the artifact path actually produced by `build-app-bundle.sh`.
- [ ] Ensure required production signing cannot silently degrade to ad-hoc signing.
- [ ] Remove masked signing failures.
- [ ] Validate nested code, frameworks, helper executables, and app signature.
- [ ] Submit the final DMG/app for notarization.
- [ ] Wait for accepted notarization result.
- [ ] Staple and validate the ticket.
- [ ] Run `spctl` assessment through an approved FlowDeck/release environment path.
- [ ] Upload the validated artifact and provenance metadata as a workflow artifact.
- [ ] Record artifact hash, commit, build number, certificate identity, and notarization request identifier.

### 9.4 Repair public release workflow

**File:** `.github/workflows/release.yml`

- [ ] Make tests and required security checks prerequisites for release publication.
- [ ] Build exactly one candidate artifact.
- [ ] Sign, notarize, and staple that same artifact.
- [ ] Publish the exact validated artifact without rebuilding.
- [ ] Derive `CFBundleShortVersionString` from the approved semantic version.
- [ ] Derive monotonically increasing `CFBundleVersion` from an approved build-number scheme.
- [ ] Add a tag-to-version consistency gate.
- [ ] Require Sparkle private key before appcast publication.
- [ ] Fail instead of publishing an unsigned appcast.
- [ ] Escape or pass release-body text through safe environment/file boundaries.
- [ ] Use runner-private temporary files with restrictive permissions for key material.
- [ ] Validate generated appcast as XML.
- [ ] Validate appcast enclosure URL, length, EdDSA signature, short version, and build version.
- [ ] Restrict workflow permissions to the minimum required.
- [ ] Prevent publication from untrusted forks or pull-request contexts.

### 9.5 CI convergence

**File:** `.github/workflows/ci.yml`

- [ ] Replace repeated custom checkout logic with one reviewed strategy where possible.
- [ ] Remove non-gating `|| true` from required checks.
- [ ] Separate advisory checks from required checks visibly.
- [ ] Pin third-party actions by immutable versions or approved SHAs.
- [ ] Verify macOS runner label availability before adopting branch changes.
- [ ] Make package resolution deterministic.
- [ ] Use the FlowDeck-compatible project container in CI only after license and CI support are defined.
- [ ] Keep local and CI test commands semantically equivalent.
- [ ] Publish test and coverage artifacts.
- [ ] Add concurrency cancellation that does not cancel the only required run for a commit.
- [ ] Define explicit timeouts from measured evidence rather than arbitrary increases.

### 9.6 Release gate

- [ ] Debug and Release builds pass through FlowDeck.
- [ ] Deterministic tests pass before packaging.
- [ ] Production build fails closed without credentials.
- [ ] Production build succeeds with approved credentials.
- [ ] App is Developer ID signed.
- [ ] Notarization is accepted.
- [ ] Ticket is stapled.
- [ ] Gatekeeper accepts the artifact on a clean machine.
- [ ] Published artifact hash equals validated artifact hash.
- [ ] `CFBundleVersion` increases from the previous release.
- [ ] Sparkle signature verifies.
- [ ] Upgrade from the previous installed build succeeds.
- [ ] No right-click bypass is required for the production artifact.

---

## 10. Stage 5 — Unified Subprocess and Test Seams

### 10.1 Inventory current process execution

- [ ] Inventory every `Process()` call on `main` and accepted branch code.
- [ ] For each call, record file, symbol, executable, arguments, privilege, validation, timeout, output handling, cleanup, environment, and test coverage.
- [ ] Include `DevLocationBridge`, `DeviceManager`, `TunneldManager`, `PythonPathResolver`, dependency checks, scripts, and test helpers.
- [ ] Identify calls that wait before draining pipes.
- [ ] Identify calls that combine stdout and stderr.
- [ ] Identify data races in timeout state.
- [ ] Identify output paths without caps.
- [ ] Identify termination paths without SIGKILL escalation.
- [ ] Identify inconsistent environment construction.

### 10.2 Design the process abstraction

- [ ] Define an ordinary unprivileged subprocess protocol.
- [ ] Define a separate privileged lifecycle protocol.
- [ ] Define immutable request data: executable URL, argument array, environment, working directory, timeout, output cap, allowed exit codes, and audit context.
- [ ] Define structured result data: stdout, stderr, exit status, termination reason, duration, truncation state, and timeout state.
- [ ] Define explicit errors for launch failure, timeout, output overflow, invalid command, nonzero exit, cancellation, and cleanup failure.
- [ ] Drain stdout and stderr concurrently while the process runs.
- [ ] Ensure continuations resume exactly once.
- [ ] Make cancellation terminate child processes deterministically.
- [ ] Escalate from graceful termination to forced termination after a measured bound.
- [ ] Close file descriptors on every path.
- [ ] Keep full sensitive command contents out of normal logs.
- [ ] Add structured security audit metadata without exposing secrets.

### 10.3 TDD sequence for process execution

- [ ] Write a test for successful stdout/stderr capture.
- [ ] Write a test for large output exceeding pipe capacity without deadlock.
- [ ] Write a test for independent stdout and stderr capture.
- [ ] Write a test for timeout and termination escalation.
- [ ] Write a test for cooperative task cancellation.
- [ ] Write a test for output-size rejection.
- [ ] Write a test for nonzero exit status.
- [ ] Write a test for launch failure.
- [ ] Write a test for continuation single-resume under timeout/completion races.
- [ ] Write a test for file-descriptor cleanup.
- [ ] Write a test for environment allowlisting.
- [ ] Run each test before implementation and record the expected failure.
- [ ] Implement the minimum behavior needed for each test.
- [ ] Run focused tests after every change.
- [ ] Run full deterministic tests before PR review.

### 10.4 Migrate call sites incrementally

- [ ] Migrate the lowest-risk dependency/version checks first.
- [ ] Migrate Python resolver commands.
- [ ] Migrate DeviceManager discovery commands.
- [ ] Migrate DevLocationBridge injection commands.
- [ ] Migrate TunneldManager non-privileged inspection commands.
- [ ] Keep privileged tunnel launch separate until its lifecycle design is approved.
- [ ] Remove old runners only after all callers and tests are migrated.
- [ ] Verify no direct `Process()` remains outside approved low-level adapters and test fixtures.

### 10.5 Introduce behavioral protocols

- [ ] Define a location-bridge protocol covering set, clear, availability, and statistics required by live UI paths.
- [ ] Define a tunnel-controlling protocol covering start, stop, state, mode, and RSD information.
- [ ] Define a clock/sleeper abstraction for timing-sensitive simulation and recovery tests.
- [ ] Define a device-discovery abstraction where hardware access would otherwise block deterministic tests.
- [ ] Supply deterministic fakes with scripted success, delay, cancellation, and failure behavior.
- [ ] Keep protocol surfaces minimal and based on actual callers.

### 10.6 Stage 5 gate

- [ ] Large-output process tests pass without deadlock.
- [ ] Timeout/completion races do not double-resume.
- [ ] Cancellation reliably terminates child work.
- [ ] Output caps are enforced while reading, not after unbounded buffering.
- [ ] Critical UI-to-bridge behavior can be tested without a physical device.
- [ ] Direct process calls are reduced to approved adapters.
- [ ] Privileged execution remains isolated from ordinary runner APIs.

---

## 11. Test Strategy and Quality Baseline

### 11.1 Establish measured truth

- [ ] Run all deterministic tests through FlowDeck after Stage 0.
- [ ] Record total discovered tests rather than relying on README counts.
- [ ] Record pass, fail, skip, and blocked counts.
- [ ] Generate real coverage evidence before stating a percentage.
- [ ] Classify coverage as measured, partially measured, claimed but unevidenced, or unknown.
- [ ] Publish coverage artifacts per target and file.
- [ ] Set no coverage threshold until a valid baseline exists.
- [ ] Ratchet the threshold upward only with measured evidence.

### 11.2 Classify every test file

- [ ] Mark tests protecting live production behavior.
- [ ] Mark tests protecting dormant or unreferenced behavior.
- [ ] Mark hardware-dependent tests.
- [ ] Mark tests that could become deterministic with dependency injection.
- [ ] Mark timing/sleep-dependent tests.
- [ ] Mark singleton/global-state-dependent tests.
- [ ] Mark vacuous assertions.
- [ ] Mark tests that only inspect enum/computed-property presentation.
- [ ] Mark tests that execute real subprocesses.
- [ ] Mark tests that can alter device, network, process, or user state.

### 11.3 Minimum deterministic critical suite

- [ ] Teleport builds the exact expected validated command for USB and RSD modes.
- [ ] Route playback injects coordinates in order and honors pause/resume/cancel.
- [ ] Joystick direction produces bounded coordinate updates at the approved interval.
- [ ] Invalid coordinates are rejected before subprocess execution.
- [ ] Invalid UDID, RSD address, and port inputs are rejected.
- [ ] Rate limiting produces deterministic results with an injected clock.
- [ ] Tunnel state transitions and side effects are serialized.
- [ ] Root-process cleanup failure is surfaced.
- [ ] Python validation and execution use the same interpreter identity.
- [ ] GPX byte and point caps reject oversized inputs.
- [ ] GPX XXE protection remains enabled.
- [ ] Release configuration rejects missing signing and Sparkle requirements.
- [ ] Localization resources are present in the built app.
- [ ] Bundle identifier and version metadata match approved values.

### 11.4 Remove flakiness and false confidence

- [ ] Replace arbitrary sleeps with clocks, events, continuations, or explicit state waits.
- [ ] Remove `XCTAssertTrue(true)` assertions by replacing them with behavioral assertions or deleting invalid tests with their dead production code.
- [ ] Isolate singleton state between tests.
- [ ] Prevent tests from depending on execution order.
- [ ] Split hardware tests from deterministic integration tests.
- [ ] Require explicit environment opt-in for physical-device tests.
- [ ] Ensure CI reports skips as visible evidence.
- [ ] Do not increase timeouts without measuring the operation being awaited.

### 11.5 Test gate

- [ ] All required deterministic tests pass.
- [ ] No critical path is covered only by hardware tests.
- [ ] All remaining skips have documented reasons and owners.
- [ ] No vacuous tests remain in required suites.
- [ ] Timing-sensitive tests use deterministic synchronization.
- [ ] Coverage percentage, if reported, comes from a preserved artifact.
- [ ] Release workflow runs the required suite before publication.

## 12. Stage 6 — Simulation and Tunnel Architecture Convergence

### 12.1 Simulation authority

- [ ] Decide whether the accepted implementation is a refactored `SimulationEngine`, a new focused simulation service, or a branch implementation proven superior by tests.
- [ ] Route teleport, route, and joystick through the same location-bridge protocol.
- [ ] Keep `AppState` responsible for composition and published UI state only.
- [ ] Ensure one task owner per active simulation mode.
- [ ] Define valid transitions between idle, teleport, route, joystick, paused, stopping, and failed states.
- [ ] Define behavior when the selected device changes during simulation.
- [ ] Define behavior when tunnel/RSD information rotates during simulation.
- [ ] Define rate limiting and queue strategy per mode.
- [ ] Define cancellation and clear-location semantics.

### 12.2 Restore functional joystick behavior

- [ ] Convert joystick direction into movement using approved physics and update interval.
- [ ] Clamp direction magnitude and coordinate bounds.
- [ ] Start exactly one joystick task when joystick mode becomes active.
- [ ] Stop the task on zero direction when required by the interaction design.
- [ ] Cancel on mode switch, device switch, tunnel loss, app termination, and explicit stop.
- [ ] Use latest-wins queue behavior where appropriate.
- [ ] Add deterministic tests for direction, speed, interval, cancellation, and error propagation.
- [ ] Verify foreground drag behavior only after explicit permission because it requires foreground interaction.

### 12.3 Preserve route and teleport behavior

- [ ] Preserve the working `main` route path until replacement passes parity tests.
- [ ] Test route point order, progress, pause, resume, stop, completion, and errors.
- [ ] Test teleport success, clear, invalid input, tunnel loss, device loss, and iOS-version warning behavior.
- [ ] Prevent route and joystick tasks from running simultaneously.
- [ ] Ensure UI state reflects actual bridge completion rather than optimistic assignment.

### 12.4 Tunnel authority

- [ ] Make `TunnelStateMachine` or an approved replacement the sole transition authority.
- [ ] Ensure side effects execute serially and report completion/failure back into state.
- [ ] Implement every emitted action, including process launch actions.
- [ ] Remove or migrate legacy mirrored state only after callers are updated.
- [ ] Remove duplicate health loops after proving one authoritative monitor.
- [ ] Define externally managed tunnel behavior if it remains supported.
- [ ] Define USB, WiFi, daemon, and automatic mode selection explicitly.
- [ ] Preserve per-device RSD information where multi-device-compatible data structures are already justified.
- [ ] Test invalid transitions, restart exhaustion, external processes, process death, RSD rotation, and recovery.

### 12.5 AppState decomposition

- [ ] Evaluate branch files `AppState+Orchestration.swift`, `AppState+RecoveryAndHistory.swift`, `AppState+SimulationMirrors.swift`, and `AppState+Testing.swift` individually.
- [ ] Port only extensions consistent with the approved target architecture.
- [ ] Keep test-only hooks internal and narrowly scoped.
- [ ] Do not use file splitting to hide continued responsibility overload.
- [ ] Document dependencies injected into AppState initialization.
- [ ] Ensure published state changes occur on the main actor.

### 12.6 Stage 6 gate

- [ ] Teleport works through the canonical service.
- [ ] Route works through the canonical service.
- [ ] Joystick has a live, tested consumer.
- [ ] One simulation authority exists.
- [ ] One tunnel transition authority exists.
- [ ] No duplicate active tasks or health loops remain.
- [ ] Device/tunnel loss produces deterministic cancellation and recovery behavior.
- [ ] Full deterministic suite passes.
- [ ] Background UI validation confirms state presentation.

---

## 13. Stage 7 — Proven Dead-Surface Cleanup

### 13.1 Deletion evidence contract

For every proposed deletion:

- [ ] Search definitions and references on the target branch.
- [ ] Search production instantiation.
- [ ] Search dynamic construction, reflection, notifications, environment keys, selectors, and serialization references.
- [ ] Search tests, docs, scripts, resources, and CI.
- [ ] Compare whether another accepted commit activates the surface.
- [ ] Determine whether it represents desired future scope.
- [ ] Record security risk of retaining it.
- [ ] Record behavior and tests removed with it.
- [ ] Require a focused deletion PR with rollback instructions.

### 13.2 Candidate surfaces requiring proof

- [ ] `Core/StateManagers/DeviceStateManager.swift`
- [ ] `Core/StateManagers/SimulationStateManager.swift`
- [ ] `Core/StateManagers/RouteStateManager.swift`
- [ ] `Device/PersistentLocationBridge.swift`
- [ ] `Device/CompanionHostService.swift`
- [ ] `Core/CloudSync.swift`
- [ ] `Core/HealthCheckServer.swift`
- [ ] `Core/TelemetryService.swift`
- [ ] `Device/MultiDeviceCoordinator.swift`
- [ ] `Simulation/MovementPhysics.swift`
- [ ] `MapLayer/MapService.swift`
- [ ] Duplicate plists and obsolete build scripts.
- [ ] Tests whose only subject is deleted production code.
- [ ] Deployment documents contradicted by the accepted release policy.

### 13.3 Cleanup rules

- [ ] Never use the historical “6,800 LOC / 32%” estimate as a deletion list.
- [ ] Remove tests only in the same PR as the production behavior they exclusively test.
- [ ] Preserve tests that can be redirected to canonical behavior.
- [ ] Avoid mixed cleanup and behavior-change PRs.
- [ ] Confirm app build, test discovery, launch, and critical flows after each cleanup PR.
- [ ] Record deleted public types and migration implications.

### 13.4 Cleanup gate

- [ ] Every deleted surface has call-graph and product-scope evidence.
- [ ] No desired feature is removed accidentally.
- [ ] No live test coverage decreases without replacement.
- [ ] No resource or serialization compatibility is broken silently.
- [ ] Revert of each cleanup PR restores the prior state cleanly.

---

## 14. Stage 8 — Documentation, Recovery Evidence, and Governance

### 14.1 Branding and identity

- [ ] Replace user-visible “Location Spoofer” strings in English and Japanese resources while preserving required historical attribution.
- [ ] Confirm canonical product name, bundle identifier, repository URL, issue URL, discussion/support route, and screenshot assets.
- [ ] Replace placeholder clone URLs and screenshot links.
- [ ] Verify Sparkle feed URL and public key ownership.
- [ ] Add a CI scan that distinguishes forbidden product-name leaks from permitted provenance references.

### 14.2 README and contributing accuracy

- [ ] Generate test counts from current discovered tests or remove hardcoded counts.
- [ ] Correct the tunnel log path.
- [ ] Remove or implement undocumented keyboard shortcuts.
- [ ] Remove or add `Resources/sample_routes/` consistently.
- [ ] Correct build instructions to use the approved FlowDeck workflow.
- [ ] Explain hardware requirements and deterministic-test separation.
- [ ] Correct coverage claims to match preserved measurement evidence.
- [ ] Correct contribution branch, review, and CI requirements.

### 14.3 Recovery evidence

- [ ] Re-evaluate all 79 unchecked recovery-plan items.
- [ ] Mark an item complete only with linked evidence.
- [ ] Create `docs/verification.md` after fresh verification is available.
- [ ] Create or explicitly retire `docs/audit/local-candidates.md`.
- [ ] Create or explicitly retire `docs/audit/import-decisions.md`.
- [ ] Create or explicitly retire `docs/audit/rename-matrix.md`.
- [ ] Update `docs/audit/github-baseline.md` with current remote evidence.
- [ ] Preserve provenance to `abyssbugg/LocationSpoofer` baseline `e8aa39f20a4b0e078245282967b8c9c791350f10`.

### 14.4 ADRs and policies

- [ ] Update ADR 001 to match the accepted Python/location-bridge design.
- [ ] Verify ADR 002 remains accurate for caching.
- [ ] Update ADR 003 to match canonical tunnel state and external management behavior.
- [ ] Port or rewrite ADR 004 for approved privilege/security design.
- [ ] Retain, supersede, or reject ADR 005 based on distribution policy.
- [ ] Add an ADR for FlowDeck/Xcode wrapper ownership.
- [ ] Add an ADR for Sparkle trust and release artifact provenance.
- [ ] Add an ADR for iOS-version support and known limitations if still required.
- [ ] Add CODEOWNERS only with valid owners.
- [ ] Add SECURITY.md only with valid reporting instructions.

### 14.5 Artifact hygiene

- [ ] Decide `Package.resolved` policy for SwiftPM and Xcode wrapper.
- [ ] Decide design-image tracking and storage policy.
- [ ] Decide audit-prompt storage policy.
- [ ] Ignore only generated, local, or sensitive artifacts.
- [ ] Do not ignore evidence that should be reviewed and versioned.
- [ ] Verify no secrets, certificates, private keys, notarization profiles, device logs, or sensitive identifiers are staged.

### 14.6 Documentation gate

- [ ] Documentation matches live code and accepted architecture.
- [ ] All commands use approved tooling.
- [ ] Test and coverage claims are measured.
- [ ] Release claims match actual signing/notarization behavior.
- [ ] Recovery checklist has evidence links or explicit rejection reasons.
- [ ] Old branding remains only where legally/provenance appropriate.

---

## 15. Stage 9 — UI Redesign Integration

**Entry condition:** Stages 0–8 foundations and gates are accepted, or a specific UI component has a documented independent dependency exception.

### 15.1 UI product decisions

- [ ] Approve or reject the Apple-Maps-style shell.
- [ ] Approve information hierarchy for map, sidebar, device selector, connection state, mode controls, telemetry, history, and settings.
- [ ] Decide whether each feature is functional or display-only.
- [ ] Define accessibility identifiers for all critical controls.
- [ ] Define light/dark appearance behavior.
- [ ] Define localization requirements.
- [ ] Define minimum window size and window restoration behavior.

### 15.2 Component-by-component integration

- [ ] Integrate DesignSystem tokens separately from layout where practical.
- [ ] Integrate DeviceDropdown only after device/readiness authority is stable.
- [ ] Integrate ConnectionPill only after tunnel-state presentation is stable.
- [ ] Integrate ThemeToggle with persistence tests.
- [ ] Integrate LibraryFlyout only after history/favorites storage is accepted.
- [ ] Integrate TelemetryBar only with real, labeled metrics.
- [ ] Integrate mode panels only after teleport/route/joystick behavior is canonical.
- [ ] Integrate MainMapShell and window-layout changes last.
- [ ] Keep UI PRs free of unrelated privilege, release, process, and CI changes.

### 15.3 Visual and behavioral verification

- [ ] Build through FlowDeck.
- [ ] Launch hidden through FlowDeck.
- [ ] Start a macOS UI session.
- [ ] Validate accessibility tree before interactions.
- [ ] Use background element-targeted actions whenever possible.
- [ ] Obtain explicit approval before foreground drag testing for joystick.
- [ ] Verify teleport, route, joystick, device selection, mode changes, settings, theme, history, and errors.
- [ ] Verify empty, loading, connected, disconnected, starting, failed, and recovery states.
- [ ] Verify English and Japanese layouts.
- [ ] Verify keyboard navigation and VoiceOver semantics.
- [ ] Compare screenshots against approved design references.

### 15.4 UI gate

- [ ] UI does not own duplicate runtime state.
- [ ] Every displayed operational state comes from canonical services.
- [ ] Every advertised interaction works.
- [ ] Critical controls have accessibility identifiers.
- [ ] Background UI verification passes.
- [ ] Approved foreground interaction checks pass.
- [ ] No foundation tests regress.

---

## 16. Branch and Worktree Strategy

### 16.1 Baseline rules

- [ ] Keep `main` protected as the integration target.
- [ ] Do not create a permanent mega integration branch containing all feature work.
- [ ] Create one short-lived branch/worktree per approved PR.
- [ ] Start foundation branches from current approved `main`.
- [ ] Rebase or update a branch only with explicit approval and after preserving evidence.
- [ ] Keep `feat/ui-redesign` as a read-only donor/reference branch.

### 16.2 Proposed branch names

- [ ] `phase0/flowdeck-project-wrapper`
- [ ] `phase0/viability-evidence`
- [ ] `phase0/gpx-input-hardening`
- [ ] `phase0/security-governance`
- [ ] `phase0/python-trust-chain`
- [ ] `phase0/privileged-lifecycle`
- [ ] `phase0/process-runner`
- [ ] `phase0/release-scripts`
- [ ] `phase0/release-workflows`
- [ ] `phase0/test-seams`
- [ ] `phase0/simulation-authority`
- [ ] `phase0/tunnel-authority`
- [ ] `phase0/dead-surface-cleanup-state-managers`
- [ ] `phase0/dead-surface-cleanup-persistent-bridge`
- [ ] `phase0/dead-surface-cleanup-companion-host`
- [ ] `phase0/dead-surface-cleanup-cloud-health-telemetry`
- [ ] `phase0/docs-recovery-evidence`
- [ ] `phase0/ui-design-system`
- [ ] `phase0/ui-device-and-connection-controls`
- [ ] `phase0/ui-library-and-telemetry`
- [ ] `phase0/ui-map-shell-and-window-layout`

### 16.3 Worktree requirements

- [ ] Place worktrees outside the primary checkout in the approved worktree directory.
- [ ] Verify the branch is not already checked out elsewhere.
- [ ] Use worktree-specific FlowDeck derived data.
- [ ] Keep untracked primary-tree files out of worktrees unless explicitly needed.
- [ ] Verify clean status before removing a worktree.
- [ ] Never delete a worktree containing uncommitted evidence or changes.

---

## 17. Proposed PR Sequence

1. **PR 1 — FlowDeck-compatible Xcode wrapper**
   - [ ] Objective: enable approved build/test/run tooling.
   - [ ] Must not include behavior, UI, security, or release redesign.
   - [ ] Gate: Stage 0.
2. **PR 2 — Baseline/viability evidence infrastructure**
   - [ ] Objective: reproducible evidence capture and test classification.
   - [ ] Must not change product behavior except test-only seams strictly required for evidence.
3. **PR 3 — GPX and file-input hardening**
   - [ ] Source candidate: `14eabef`, manually reviewed.
   - [ ] Must remain isolated from broader architecture changes.
4. **PR 4 — Security governance and fail-closed CI checks**
   - [ ] Source candidates: `d6a44ee`, `bc9853c`, selected `323c089` changes.
   - [ ] Must not alter application architecture.
5. **PR 5 — Python environment and dependency integrity**
   - [ ] Source candidates: `0db795f`, `37a9ca8` concepts.
   - [ ] Gate: interpreter identity and ownership design approved.
6. **PR 6 — Unified unprivileged subprocess runner**
   - [ ] Source candidate: `fbc32be` concepts.
   - [ ] Use TDD and migrate low-risk call sites first.
7. **PR 7 — Privileged tunnel lifecycle containment**
   - [ ] Separate from ordinary process runner.
   - [ ] Gate: authorized cleanup and crash-recovery tests.
8. **PR 8 — Build and packaging scripts fail closed**
   - [ ] Source candidates: `0fe4f99`, selected `c1d550b` changes.
   - [ ] Must not publish an artifact.
9. **PR 9 — Release validation and publication convergence**
   - [ ] Connect signing, notarization, stapling, appcast, and exact artifact publication.
   - [ ] Gate: release credentials and dry-run environment approved.
10. **PR 10 — Deterministic location/tunnel test seams**
    - [ ] Add protocols, fakes, clock, and critical path tests.
    - [ ] Must precede simulation authority change.
11. **PR 11 — Simulation authority and joystick functionality**
    - [ ] Converge teleport, route, and joystick.
    - [ ] Gate: deterministic behavior tests.
12. **PR 12 — Tunnel-state authority convergence**
    - [ ] Serialize actions and remove duplicate monitors/mirrors after migration.
13. **PR 13+ — Focused dead-surface cleanup**
    - [ ] One subsystem per PR with call-graph evidence.
14. **PR 14 — Documentation, ADRs, branding, and recovery evidence**
    - [ ] Reflect accepted implementation only.
15. **PR 15+ — UI components**
    - [ ] One bounded component or cohesive UI slice per PR.
    - [ ] MainMapShell/window-layout change last.
16. **Final PR — Release-candidate qualification evidence**
    - [ ] No major behavior changes.
    - [ ] Contains verification updates and release-readiness corrections only.

## 18. Commit and Review Policy

### 18.1 Commit rules

- [ ] Keep each commit single-purpose and reviewable.
- [ ] Write tests before behavior changes where deterministic testing is possible.
- [ ] Separate mechanical moves and renames from behavior changes.
- [ ] Separate generated Xcode project changes from source behavior changes.
- [ ] Do not combine security fixes with UI restyling.
- [ ] Do not combine release workflow changes with unrelated documentation cleanup.
- [ ] Explain donor-branch provenance without implying blind transplant safety.
- [ ] Use conventional prefixes such as `build`, `ci`, `fix`, `refactor`, `test`, `docs`, `security`, and `chore` consistently.

### 18.2 Donor-commit integration rules

- [ ] Prefer manual reimplementation for mixed commits.
- [ ] Prefer source commits over merge commits when equivalent.
- [ ] Cherry-pick unchanged only when dependencies, tests, and file ownership match the target branch.
- [ ] If conflict resolution changes behavior, treat the result as a manual port.
- [ ] Record rejected donor commits and reasons to prevent repeated analysis.
- [ ] Do not transplant tests without corresponding accepted production behavior.
- [ ] Do not transplant lint suppressions without their governing code and rationale.

### 18.3 Review requirements

- [ ] Security review for privilege, Python, process execution, GPX, entitlements, secrets, Sparkle, and workflow permissions.
- [ ] Release review for versioning, signing, notarization, stapling, appcast, and artifact provenance.
- [ ] Architecture review for state authority, service protocols, tunnel FSM, and dead-code deletion.
- [ ] Test review for critical-path coverage, timing, singleton isolation, hardware boundaries, and vacuous assertions.
- [ ] UI/accessibility review for every user-facing redesign PR.
- [ ] Require fresh FlowDeck output before approval of build-impacting PRs.

---

## 19. Global Go / No-Go Gates

### Gate 0 — Repository and tooling baseline

- [ ] Known local and remote HEADs.
- [ ] Known donor branch HEAD and divergence.
- [ ] Pre-existing untracked files recorded.
- [ ] Approved worktree strategy.
- [ ] FlowDeck installed, licensed, configured, and able to discover the project.
- [ ] Xcode wrapper parity established.

### Gate 1 — Viability evidence

- [ ] Fresh main build result.
- [ ] Fresh feature build result.
- [ ] Fresh main launch result.
- [ ] Fresh feature launch result.
- [ ] Fresh test results for both baselines.
- [ ] Survival-check evidence recorded.
- [ ] No reliance on stale artifacts.

### Gate 2 — Commit map

- [ ] All 52 commits classified.
- [ ] Dependencies recorded.
- [ ] Merge-only commits identified.
- [ ] Mixed commits marked for split or manual port.
- [ ] Rejected and deferred work recorded.
- [ ] Human approval obtained.

### Gate 3 — Security

- [ ] Python identity unified.
- [ ] Dependency integrity enforced.
- [ ] Privileged lifecycle reliable or explicitly blocked.
- [ ] Subprocess validation and output handling fail closed.
- [ ] GPX and file safety tested.
- [ ] Entitlement policy explicit.
- [ ] Required security CI checks gate merges.

### Gate 4 — Release

- [ ] Build scripts honor approved configuration.
- [ ] Signing failures cannot be masked.
- [ ] Monotonic versioning implemented.
- [ ] Sparkle metadata and signatures valid.
- [ ] Validated artifact equals published artifact.
- [ ] Production artifact signed, notarized, stapled, and Gatekeeper accepted.

### Gate 5 — Test foundation

- [ ] Deterministic critical suite passes.
- [ ] Process runner tested for deadlock, timeout, cancellation, overflow, and cleanup.
- [ ] Hardware tests separated.
- [ ] Skips visible and owned.
- [ ] Coverage claims measured.
- [ ] No required vacuous tests.

### Gate 6 — Architecture

- [ ] One application composition root.
- [ ] One simulation authority.
- [ ] One tunnel transition authority.
- [ ] Joystick functional and tested.
- [ ] Route and teleport parity proven.
- [ ] Duplicate tasks, monitors, and state mirrors removed after migration.

### Gate 7 — Cleanup and documentation

- [ ] Every deletion justified.
- [ ] Documentation matches live behavior.
- [ ] Recovery evidence updated.
- [ ] Branding corrected.
- [ ] Governance files accurate.
- [ ] Artifact hygiene policy enforced.

### Gate 8 — Release candidate

- [ ] Clean-machine installation succeeds.
- [ ] Gatekeeper accepts without bypass.
- [ ] Upgrade from prior version succeeds through Sparkle.
- [ ] Teleport works on an authorized supported device.
- [ ] Route works on an authorized supported device.
- [ ] Joystick works on an authorized supported device.
- [ ] USB, WiFi, and daemon modes behave according to the approved support policy.
- [ ] Tunnel start, stop, quit, crash, and relaunch cleanup are verified.
- [ ] Localization and accessibility checks pass.
- [ ] No unresolved critical or high risks remain without explicit release waiver.

## 20. Risk Register

| ID | Risk | Severity | Current evidence | Primary mitigation | Required gate |
|---|---|---:|---|---|---|
| R-001 | Root executes mutable or mismatched Python environment | Critical | Statically verified on `main` | Unified owned interpreter, hash lock, isolated execution | Security |
| R-002 | Root tunnel survives stop, crash, or app exit | High | Statically credible; runtime unverified | Reliable privileged lifecycle and relaunch cleanup | Security/RC |
| R-003 | Pipe-buffer deadlock in subprocess runners | High | Statically verified wait-before-drain patterns | Concurrent bounded capture runner | Test foundation |
| R-004 | Continuation double resume in dormant persistent bridge | High | Statically verified on `main` | Remove or correct before activation | Architecture |
| R-005 | Public release is ad-hoc and unnotarized | High | Statically verified workflow | Signed/notarized exact-artifact pipeline | Release |
| R-006 | Sparkle build version remains static | High | Static bundle version and workflow behavior | Monotonic build version and tag gate | Release |
| R-007 | Unsigned or invalid appcast can be published | High | Statically verified conditional signing path | Require key and fail closed | Release |
| R-008 | Feature branch does not build or launch | High | Unverified due prior FlowDeck project gap | Stage 0 wrapper and Stage 1 evidence | Viability |
| R-009 | Xcode wrapper diverges from SwiftPM packaging | High | New requirement | Parity tests and single ownership rules | Tooling |
| R-010 | Blind branch merge introduces mixed unfinished work | High | 194-file and approximately 40k-line delta | Selective PR sequence | Commit map |
| R-011 | Joystick remains advertised but inert | High | Statically verified on `main` | Canonical simulation service and tests | Architecture |
| R-012 | State and tunnel authority duplication causes incoherence | High | Statically verified duplication | Explicit owner decisions and serialized side effects | Architecture |
| R-013 | Dead-code cleanup deletes desired capability | High | Historical estimates unsupported as deletion list | Call-graph and product-scope proof | Cleanup |
| R-014 | Tests provide false confidence | Medium-High | Vacuous, timing, and dead-surface tests identified | Deterministic critical suite and classification | Testing |
| R-015 | GPX or resource input causes memory/parser abuse | Medium-High | Unbounded read on `main`; branch fix exists | Size, point, symlink limits and tests | Security |
| R-016 | Entitlement posture is inconsistent or misleading | Medium | App sandbox absent on `main` | Explicit entitlement policy and CI assertion | Security |
| R-017 | Release-body or workflow expression injection | Medium-High | Static workflow risk | Safe file/environment boundaries and least permissions | Release |
| R-018 | CI checks are advisory while presented as required | Medium | Fail-open shell markers and workflow drift | Fail-closed required checks | CI |
| R-019 | Documentation drives incorrect operations | Medium | Logs, shortcuts, tests, and URLs stale | Evidence-generated docs | Documentation |
| R-020 | Recovery completion is asserted without evidence | High | 79 unchecked items and missing artifacts | Verification record and evidence links | Documentation |
| R-021 | Single-developer bus factor causes unsafe large changes | High | Repository context | Small PRs, written decisions, reversible sequence | All |
| R-022 | FlowDeck trial expires during Phase 0 | Medium | Expiration date August 25, 2026 | Secure ongoing license before dependency-critical work | Tooling |

- [ ] Assign an owner role and status to every risk before implementation begins.
- [ ] Link each accepted PR to the risks it reduces or may increase.
- [ ] Update residual severity after verification.
- [ ] Require explicit approval for any risk waiver.

---

## 21. Audit Claims That Must Not Be Carried Forward Uncritically

- [x] `main` has 53 application Swift files, not 88.
- [x] `feat/ui-redesign` has 89 application Swift files.
- [x] The feature branch is exactly 52 commits ahead and zero behind at the recorded heads.
- [x] Route mode is reachable on `main`; it is inline in `AppState`, although architecturally duplicated.
- [x] `SimulationEngine` is instantiated on `main`; “completely dead” is overstated, though principal UI paths bypass it.
- [x] The “6,800 LOC / 32% dead” number is not an approved deletion specification.
- [x] Python version parsing throws on malformed output; it does not fail open in the inspected path.
- [x] Seven literal always-true assertions exist when message arguments are included in the search.
- [x] The precise “143 vacuous localization assertions” count remains unverified.
- [x] The “35–45% actual coverage” estimate remains unsupported until coverage is measured.
- [x] The recovery checklist contains 79 unchecked items, not 78.
- [x] Historical build, launch, and test claims are not fresh evidence.
- [x] Existing build artifacts are not proof of a successful current build.
- [x] Directly merging `feat/ui-redesign` is rejected.
- [x] The release validation workflow references missing scripts on `main`.
- [x] The public release workflow is distinct from the validation workflow and does not publish the validated notarized artifact.
- [x] FlowDeck is installed and licensed now, but project discovery remains blocked until an Xcode container is provided.

---

## 22. Explicitly Deferred or Out of Scope Until Approved

- [ ] Full fast-forward or merge of `feat/ui-redesign`.
- [ ] Large-scale UI redesign before foundation gates.
- [ ] Multi-device product expansion.
- [ ] Companion app activation or authenticated pairing redesign.
- [ ] Cloud sync.
- [ ] Telemetry collection or external analytics.
- [ ] Health-check network server activation.
- [ ] Persistent high-frequency Python bridge unless security and lifecycle are corrected.
- [ ] Full privileged helper or daemon redesign if Phase 0 approves only interim containment.
- [ ] New product features unrelated to recovery, security, release, and architecture convergence.
- [ ] Performance claims without benchmark evidence.
- [ ] Public production release before the Release Candidate gate.

---

## 23. Operational Phase 0 Checklist

### Tooling and baseline

- [ ] Approve FlowDeck/Xcode wrapper work package.
- [ ] Create isolated wrapper branch and worktree.
- [ ] Run FlowDeck project-generation dry run.
- [ ] Implement wrapper without source duplication.
- [ ] Configure FlowDeck for `My Mac`.
- [ ] Verify project, schemes, configurations, build, and test discovery.
- [ ] Secure FlowDeck licensing beyond August 25, 2026 if work continues past that date.

### Runtime evidence

- [ ] Run fresh `main` Debug build.
- [ ] Run fresh `main` Release build.
- [ ] Launch and capture `main` UI and log evidence.
- [ ] Run and classify `main` tests.
- [ ] Run fresh feature Debug build.
- [ ] Run fresh feature Release build.
- [ ] Launch and capture feature UI and log evidence.
- [ ] Run and classify feature tests.
- [ ] Complete feature survival checks.
- [ ] Publish the viability result.

### Branch analysis

- [ ] Complete all 52 commit classifications.
- [ ] Complete dependency graph.
- [ ] Identify merge-only commits.
- [ ] Identify safe direct cherry-picks.
- [ ] Identify manual ports.
- [ ] Identify rejected work.
- [ ] Identify deferred UI and product work.
- [ ] Approve the commit map.

### Architecture and security decisions

- [ ] Approve application composition root.
- [ ] Approve simulation authority.
- [ ] Approve tunnel authority.
- [ ] Approve Python environment ownership.
- [ ] Approve ordinary subprocess abstraction.
- [ ] Approve privileged lifecycle approach.
- [ ] Approve companion and multi-device scope.
- [ ] Approve entitlement policy.
- [ ] Approve distribution and Sparkle policy.

### Foundation PRs

- [ ] Merge FlowDeck wrapper PR after its gate.
- [ ] Merge GPX/file-input hardening PR after its gate.
- [ ] Merge security governance/CI PR after its gate.
- [ ] Merge Python trust-chain PR after its gate.
- [ ] Merge subprocess runner PR after its gate.
- [ ] Merge privileged lifecycle PR after its gate.
- [ ] Merge build-script hardening PR after its gate.
- [ ] Merge release workflow convergence PR after its gate.
- [ ] Merge deterministic test-seam PR after its gate.

### Architecture convergence

- [ ] Merge simulation authority and joystick PR after its gate.
- [ ] Merge tunnel authority PR after its gate.
- [ ] Verify teleport parity.
- [ ] Verify route parity.
- [ ] Verify joystick functionality.
- [ ] Verify cancellation and recovery.

### Cleanup and documentation

- [ ] Execute one proven-dead subsystem cleanup per PR.
- [ ] Update branding.
- [ ] Update README and CONTRIBUTING.
- [ ] Update ADRs.
- [ ] Complete recovery evidence artifacts.
- [ ] Decide untracked file disposition.
- [ ] Decide `Package.resolved` policy.
- [ ] Update risk register and verification record.

### UI and release candidate

- [ ] Approve UI target design.
- [ ] Integrate UI components separately.
- [ ] Validate accessibility and localization.
- [ ] Validate all operational states.
- [ ] Produce signed and notarized candidate.
- [ ] Test clean-machine installation.
- [ ] Test Sparkle upgrade.
- [ ] Test authorized device workflows.
- [ ] Complete final go/no-go review.

---

## 24. Definition of Phase 0 Complete

Phase 0 is complete only when:

- [ ] `main` is FlowDeck-buildable, launchable, and testable from a documented configuration.
- [ ] The feature branch has a fresh viability verdict and complete 52-commit disposition map.
- [ ] No blind branch merge remains proposed.
- [ ] Security, Python, subprocess, release, simulation, and tunnel ownership decisions are documented.
- [ ] Critical foundation PRs are integrated or explicitly rejected with reasons.
- [ ] Teleport, route, and joystick have deterministic coverage and approved runtime evidence.
- [ ] Privileged lifecycle risk is reduced to an accepted residual level.
- [ ] Release pipeline fails closed and publishes the exact validated artifact.
- [ ] Documentation and recovery records match reality.
- [ ] Every remaining high or critical risk has an approved owner, mitigation, and gate.
- [ ] The next-phase backlog can be executed without rediscovering core architecture decisions.

---

## 25. Recommended Immediate Next Action

- [ ] Review and approve **PR 1 planning scope: FlowDeck-compatible Xcode wrapper**.
- [ ] Do not run branch viability until the wrapper gate passes.
- [ ] After wrapper approval, create a dedicated implementation plan with exact generated project files, target membership, build settings, resource phases, schemes, tests, and FlowDeck commands.
- [ ] Execute that plan in an isolated worktree with TDD, parity checks, and review checkpoints.

---

## 26. Safety Confirmation for This Roadmap Creation

- [x] No production source files modified.
- [x] No existing documentation files modified.
- [x] No workflow files modified.
- [x] No project configuration modified.
- [x] No commits created.
- [x] No tags created.
- [x] No branches created, switched, merged, rebased, or deleted.
- [x] No cherry-picks performed.
- [x] No remote resources modified.
- [x] No pull requests created or modified.
- [x] Only the explicitly requested `todo-aug-11-2026.md` file was created.
