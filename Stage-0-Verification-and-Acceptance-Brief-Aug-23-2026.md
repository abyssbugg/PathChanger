# Stage 0 Verification and Acceptance Brief — Aug. 23, 2026

> **For agentic workers:** Before executing this brief, load `executing-plans`, `flowdeck`, and `verification-before-completion`. Execute one work packet at a time and stop at every stated gate.

**Goal:** Produce reproducible baseline evidence for the current PathChanger repository, build/test state, active GUI contract, installed-app isolation, hardware inventory, and source ownership without changing code or exercising unresolved privileged tunnel paths.

**Architecture:** Stage 0 is an evidence-collection boundary, not remediation. It records one revision-bound run identity, uses FlowDeck for every Apple build/test/run/UI operation, gathers GUI evidence through the active macOS app surface, and stops before Stage 1 design or implementation.

**Tooling:** FlowDeck CLI, Swift Package Manager as invoked through the approved project workflow, Git read/write operations limited to the separate evidence repository, SHA-256 file identity, the private tamper-evident evidence repository, and Markdown/JSON evidence manifests.

**Status:** **Stage 0 execution is authorized exactly as bounded by this brief and the single-maintainer waiver.** Authorization does not extend to code changes, privileged testing, hardware mutation, location injection, Stage 1, or release/security approval. The waiver and tamper-evident storage downgrade expire after Stage 0.

---

## 1. Authority and decision constraints

This brief implements Stage 0 from `Consolidated-Source-Of-Truth-Aug-23-2026.md`, **G — Stage 0**, under the approved policies in **J.1**.

| Decision | Approved policy | Stage 0 effect |
|---|---|---|
| Execution authorization | **Stage 0 planning only** | This brief may be written; none of its procedures may run without a new authorization. |
| Privilege | **No-root plus signed helper** | Stage 0 performs no privileged tunnel operation and stops on any privilege prompt. |
| No-root scope | **Supported one-shot operations** | Inventory capability only; do not certify or implement operations. |
| Dependencies | **Managed locked runtime** | Inventory current state; do not install or select release versions. |
| Transport | **Healthy USB preference** | Record as future acceptance policy; do not exercise failover. |
| Failover | **1–3 second failover** | Record measurement definition; do not run failover tests. |
| Safety | **Enforced per-mode safety** | Record policy; numeric mode limits remain later specification work. |
| Persistent bridge | **Serialized persistent bridge requests** | Record one-in-flight contract; do not change bridge behavior. |
| Release matrix | **Declared support matrix** | Produce a concrete proposed inventory, not release certification. |
| Evidence/governance | **Stage-0 tamper-evident repository and single-maintainer waiver** | Use protected private GitHub history, SHA-256 manifests, archived Oz review, fresh-checkout verification, and time-separated identity-bound self-approval; do not represent these controls as independent or immutable. |

1. Stage 0 execution may observe, build, test, launch in the background, and capture evidence only after explicit authorization.
2. No source code, project configuration, dependency lock, original audit document, installed application, device state, or privilege policy may be changed.
3. No user-owned Python or package code may execute as root.
4. No privileged tunnel start, administrator prompt acceptance, pairing-record mutation, daemon installation, helper installation, or release installation is permitted.
5. The GUI is the acceptance surface. CLI evidence supports the GUI contract but cannot replace it.
6. FlowDeck is mandatory for Apple project discovery, build, test, run, logs, screenshots, and UI automation. Raw Apple build/simulator/device/log tools are prohibited.
7. The release direction remains no-root for supported one-shot operations plus a signed typed helper only where later capability analysis proves privilege unavoidable.
8. The future release runtime must be managed and exactly locked; Stage 0 inventories current dependencies but does not select or install the release runtime.
9. Healthy USB preference, 1–3 second failover, enforced per-mode safety, serialized persistent bridge requests, the declared support matrix, and later independent release/security approval remain recorded policies—not Stage 0 implementation work. The documented single-maintainer waiver governs Stage 0 evidence only.

## 2. Non-goals

Stage 0 does not:

- fix the readiness-label or duplicate-device defects;
- change lifecycle, readiness, identity, failover, persistent bridge, or simulation code;
- prove successful USB, Wi-Fi, daemon, userspace, or persistent tunnels;
- perform physical-device location injection;
- certify Teleport, Jump, Two-Spot, Multi-Spot, or Joystick;
- test privileged process launch or teardown;
- alter `/Applications/PathChanger.app`;
- clean, stash, reset, commit, or otherwise mutate the existing dirty Git workspace;
- resolve same-network semantics, Jump behavior, dormant UI disposition, or archival-banner permission;
- authorize Stage 1 design or implementation.

## 3. Stage 0 roles and single-maintainer waiver

### 3.1 Recorded assignments

| Function | Assigned identity | Status and boundary |
|---|---|---|
| Stage 0 operator | Shigeo (`datamatics`; GitHub `abyssbugg`) | **AUTHORIZED** to execute only the bounded packets in this brief on local hardware. |
| Product owner | Shigeo (`datamatics`; GitHub `abyssbugg`) | **AUTHORIZED** to assess the bounded GUI/hardware observations; cannot convert them into release certification. |
| Automated technical reviewer | Oz agent | **AUTHORIZED** to generate an archived completeness/hash/criteria review. This is automated evidence, not independent human accountability. |
| Accountable engineering approver | Shigeo in a separate review session | **STAGE-0 WAIVER**; may decide only after Oz’s report and fresh-checkout verification are complete. |
| Stage 0 security-waiver approver | Shigeo in the same later review session | **STAGE-0 WAIVER**; must use the exit checklist verbatim and cannot approve Stage 1 or release/security gates. |

### 3.2 Mandatory compensating controls

1. Collection and approval occur in separate sessions; no acceptance is allowed during the collection session.
2. Oz writes a review artifact into the evidence packet; chat-only review is invalid.
3. The later session retrieves a fresh checkout and reproduces packet and manifest hashes before approval.
4. Shigeo completes the exit checklist verbatim and records every result, deviation, and waiver.
5. Final acceptance is a distinct commit whose GitHub API `commit.verification.verified` value is `true`; the initial provisioning commits are unsigned and cannot serve as acceptance.
6. Each accepted packet receives an annotated tag `stage0-packet-0.N-accepted-<UTC-run-id>` pointing to the accepted commit.
7. This governance waiver expires after Stage 0. Stage 1 and release/security gates require a newly approved governance model and may not cite this waiver as independent review.

## 4. External staging and tamper-evident evidence contract

### 4.1 Provisioned local paths

| Purpose | Absolute path |
|---|---|
| Per-run staging | `/Users/datamatics/.rovodev/pathchanger-stage0/<run-id>/` |
| Per-run FlowDeck DerivedData | `/Users/datamatics/.rovodev/pathchanger-stage0/<run-id>/DerivedData` |
| Evidence repository checkout | `/Users/datamatics/.rovodev/evidence-checkouts/PathChanger-Evidence` |

Resolve `<run-id>` once as `stage0-YYYYMMDDTHHMMSSZ-<short-commit>` and record the absolute path in `manifest.json`. No evidence, temporary config, DerivedData, log, screenshot, or manifest may be written under the audited PathChanger repository root.

### 4.2 Provisioned evidence repository

| Field | Recorded contract |
|---|---|
| System | Private GitHub repository, ID `1343820956` |
| Repository | `https://github.com/abyssbugg/PathChanger-Evidence` |
| Packet path | `stage-0/<UTC-run-id>/packet-0.N/` |
| Governance contract | `governance/stage-0-contract.json` at provisioning commit `1913b180ac595634db81e285be40a46f621ddd3b` |
| Access | Shigeo/`abyssbugg` is owner/admin; Oz uses the delegated GitHub connection for automated review. There is no independent second principal. |
| Retention | Policy minimum 365 days after the Stage 0 decision; no automated expiry is configured. Owner/GitHub administrators retain ultimate deletion capability. |
| Branch controls | `main`; admin enforcement enabled; linear history required; force-push disabled; branch deletion disabled; conversation resolution required. |
| Upload | Copy only redacted packet files into the non-existing packet path in the external checkout, write `MANIFEST.sha256`, verify Git status contains only that packet, commit append-only, and push `main`. The path was proven by governance commit `1913b180ac595634db81e285be40a46f621ddd3b`. |
| Verification | Fetch into a new temporary checkout outside both repositories, reproduce every manifest hash, archive Oz’s review, and record the remote commit SHA. |
| Acceptance | In a later session, create a distinct acceptance commit by a method GitHub reports as `verified: true`; confirm via the GitHub commit API, then create/push the annotated accepted-packet tag. |

This repository is off-machine durable and tamper-evident; it is **not immutable** against `abyssbugg` or GitHub administrators. That downgrade is explicitly accepted for Stage 0 only. Raw packet/provisioning commits may be unsigned; an unsigned acceptance commit is invalid.

### 4.3 Evidence bundle layout

Create one manifested logical bundle in the external staging directory:

```text
/Users/datamatics/.rovodev/pathchanger-stage0/<run-id>/
  manifest.json
  approvals.json
  repository/
    git-identity.txt
    workspace-status.txt
    source-hashes.sha256
  environment/
    host.json
    flowdeck-config.json
    dependency-inventory.json
    hardware-inventory.json
  build/
    release-build.jsonl
    release-build.stderr.log
    result.json
  tests/
    discover-help.txt
    test-help.txt
    discovery.json
    full-suite.jsonl
    full-suite.stderr.log
    focused-suites.jsonl
    focused-suites.stderr.log
    skipped-tests.json
    flaky-tests.json
  installed-app-isolation/
    before.json
    after.json
    comparison.json
  gui/
    apps-before.json
    launch.json
    apps-after-launch.json
    session-start.json
    session-stop.json
    bounded-logs.jsonl
    bounded-logs.stderr.log
    active-surface-tree.json
    idle-state.png
    device-deduplication.png
    action-label.png
    observations.json
  trace-ledgers/
    lifecycle-writers.json
    discovery-ingestors.json
    start-stop-entry-points.json
    active-gui-controls.json
  conclusion/
    cleanup.json
    stage-0-result.json
    deviations.json
    upload-receipt.json
```

Every JSON record must include: run ID, UTC timestamp, repository commit, dirty-workspace flag, operator, command or observation method, exit status where applicable, artifact SHA-256, and redaction status. Do not store pairing records, full UDIDs, usernames, home paths, coordinates tied to a person, tokens, or unredacted privileged logs.

## 5. Entry gate

Execution must not begin until all checks are true:

- [x] The user explicitly authorized **Stage 0 execution only** under the single-maintainer waiver.
- [x] Section 3.1 records Shigeo as operator/product owner/accountable later-session approver and Oz as the automated reviewer; section 3.2 records the lack of independent human review and all compensating controls.
- [x] Section 4.2 records the provisioned private evidence repository, packet path, access limitation, 365-day policy, tested upload path, branch controls, and fresh-checkout verification method.
- [x] The staging root and unique DerivedData directory are under `/Users/datamatics/.rovodev/pathchanger-stage0/<run-id>/`, outside the audited repository.
- [x] The existing dirty workspace is acknowledged; no cleanup or reset is authorized.
- [x] Physical-device observation is approved only where the packet requires it; device mutation and location injection remain prohibited.
- [ ] FlowDeck availability, license, saved configuration, and external per-run configuration are verified at packet execution.
- [x] The operator agreed to stop on any privilege prompt or requested foreground-only UI action not separately approved.
- [ ] The eight original audit inputs, canonical document, ninth verification appendix, Stage 0 brief, and governance contract have baseline hashes recorded in packet 0.1.

Failure of either remaining runtime check produces a blocked Stage 0 result; it does not justify a workaround.

## 6. Work packet 0.1 — Freeze run and repository identity

**Purpose:** Establish the exact baseline being observed.

- [ ] Allocate the run ID, create `/Users/datamatics/.rovodev/pathchanger-stage0/<run-id>/`, and initialize the evidence manifest there.
- [ ] Resolve both repository root and staging root to absolute canonical paths; stop unless the staging root is outside and not nested under the repository.
- [ ] Record current branch, commit SHA, remotes, submodule state if present, and complete dirty/untracked status using read-only Git operations.
- [ ] Hash tracked source, project, script, resource, package-lock, and documentation files without modifying timestamps or content.
- [ ] Record the canonical source-of-truth and audit-appendix fingerprints.
- [ ] Mark every pre-existing modified/untracked path as baseline state, not Stage 0 output.

**Acceptance:** A reviewer can identify the exact repository state and distinguish pre-existing changes from evidence artifacts. If repository identity cannot be made unambiguous, stop.

## 7. Work packet 0.2 — Inventory environment and declared support

**Purpose:** Record the environment without installing, updating, or selecting dependencies.

- [ ] Record macOS version, CPU architecture, available storage, locale, time zone, and relevant accessibility/screen-recording permission status.
- [ ] Run `flowdeck config get --json` first and write its unmodified JSON to `environment/flowdeck-saved-config.json`. If no saved configuration exists, stop; Stage 0 may not create or overwrite the user’s saved configuration.
- [ ] Create `environment/flowdeck-stage0-config.json` in external staging by copying the saved workspace, scheme, configuration, and selected target and adding only `derivedDataPath: "/Users/datamatics/.rovodev/pathchanger-stage0/<run-id>/DerivedData"`. Record both config hashes and do not call `flowdeck config set` or `reset`.
- [ ] Record `flowdeck context --json` and `flowdeck license status --json`; if a required command lacks JSON support, wrap its exact stdout, stderr, exit status, and version in a JSON evidence record rather than leaving free-form output.
- [ ] Inventory installed Python candidates, ownership, architecture, version, hashes, import roots, and pymobiledevice3 versions without privilege.
- [ ] Inventory connected device models, redacted identifiers, iOS versions, connector types, observed USB/Wi-Fi paths, and available one-/two-device combinations without changing device state.
- [ ] Convert the “declared support matrix” policy into a concrete proposed matrix; mark unavailable combinations as coverage gaps rather than passes.

**Acceptance:** Environment, dependency, and hardware facts are reproducible, privacy-redacted, and explicitly separated from the future managed-runtime contract.

## 8. Work packet 0.3 — Preserve installed-app isolation

**Purpose:** Prove development verification does not replace or mutate the installed release app.

- [ ] Before build/run, record existence, bundle identity, version, signing identity, entitlements, Gatekeeper assessment, modification times, size, and recursive hash of `/Applications/PathChanger.app` if present.
- [ ] Use only the read-only inspection commands already documented in `DEPLOYMENT/02_CODE_SIGNING_PROCEDURES.md`: `/usr/bin/codesign --verify --verbose=4 /Applications/PathChanger.app`, `/usr/bin/codesign --display --verbose=4 --entitlements - /Applications/PathChanger.app`, and `/usr/sbin/spctl -a -v /Applications/PathChanger.app`. Wrap stdout, stderr, exit status, and command identity in JSON evidence because these tools do not provide the required JSON contract.
- [ ] Do not invoke `codesign` signing/force options, notarization, stapling, entitlement mutation, install, copy, delete, overwrite, or cleanup behavior against `/Applications`.
- [ ] After all allowed work packets, capture the same identity set.
- [ ] Compare before/after records byte-for-byte and explain any metadata-only difference.

**Acceptance:** Installed-app content and identity are unchanged. Any unexplained difference is an immediate Stage 0 failure and stop condition.

## 9. Work packet 0.4 — Build and automated-test baseline

**Purpose:** Reproduce the documented build/test claims without remediation.

Planned command order after authorization, where `STAGE0_ROOT` is the resolved external run directory and `STAGE0_FLOWDECK_CONFIG="$STAGE0_ROOT/environment/flowdeck-stage0-config.json"`:

```text
flowdeck config get --json
flowdeck test discover --config "$STAGE0_FLOWDECK_CONFIG" --json
flowdeck build -C Release --config "$STAGE0_FLOWDECK_CONFIG" --json
flowdeck test --config "$STAGE0_FLOWDECK_CONFIG" --json
flowdeck test --only "$DISCOVERED_TUNNEL_STATE_MACHINE_ID" --config "$STAGE0_FLOWDECK_CONFIG" --json
flowdeck test --only "$DISCOVERED_TUNNELD_MANAGER_ID" --config "$STAGE0_FLOWDECK_CONFIG" --json
```

Before execution, run `flowdeck test discover --help` and `flowdeck test --help` and record their output contract. Save discovery JSON before any test run; use `jq` to select exact identifiers returned by discovery for TunnelStateMachine and TunneldManager tests. Record the resolved identifiers in the manifest. If either selector matches zero or multiple candidate identifiers, stop rather than guessing. Every command must use the external per-run config and DerivedData path; do not overwrite saved FlowDeck configuration. Capture structured stdout, stderr, duration, exit status, test counts, failures, skips, retries, and environment in the evidence bundle.

- [ ] Reproduce or refute the claimed release build result.
- [ ] Reproduce or refute 857 tests, 0 failures, and 10 skips.
- [ ] Reproduce or refute the focused TunnelStateMachine and TunneldManager counts.
- [ ] List every skipped test with reason and owner.
- [ ] Run the MovementPhysics test repeatedly only if the approved execution scope includes flake characterization; record every iteration rather than hiding retries.
- [ ] Do not change code, tests, timeouts, dependencies, or project settings after a failure.

**Acceptance:** Results are complete and reproducible. A failing or count-mismatched baseline may still complete evidence collection, but Stage 0 cannot pass until the deviation is classified and approved; no fix is allowed in this stage.

## 10. Work packet 0.5 — GUI contract baseline

**Purpose:** Verify the active GUI’s idle/readiness presentation and canonical device display without starting a privileged tunnel.

Planned bounded FlowDeck sequence after authorization:

```text
flowdeck apps --json
flowdeck run --config "$STAGE0_FLOWDECK_CONFIG" --json
flowdeck apps --json
flowdeck ui mac session start --app "$STAGE0_APP_ID" --json
flowdeck logs "$STAGE0_APP_ID" --json
```

Capture launch JSON and use `jq` to resolve the single registered Stage 0 app ID; stop if no ID or multiple ambiguous IDs are returned. Start `flowdeck logs "$STAGE0_APP_ID" --json` as a separately managed background process, record its process ID and start time, stream complete output to external staging, and impose a 120-second packet deadline. At the deadline or after the final observation, send an interrupt to the log process, wait for termination, and record final exit status; do not pipe through `head` or abandon a live stream. Packet 0.7 must stop the macOS UI session and the Stage 0 app even when an earlier observation fails.

Use background macOS UI reads/actions only. Before any interaction command, consult its FlowDeck help, inspect the accessibility tree, prefer identifiers, and verify the screenshot/tree after every action. Do not accept an administrator prompt. Do not perform foreground drag, swipe, long-press, menu access, coordinate fallback, or app activation without separate permission.

- [ ] Capture the active map-first shell and accessibility tree.
- [ ] Confirm which compiled alternate surfaces are unmounted.
- [ ] Capture the selected device and all visible raw/canonical device counts available through non-privileged diagnostics.
- [ ] With one physical phone observed through available transports, record whether the GUI shows exactly one canonical entry.
- [ ] Record whether the tunnel action label is lifecycle-oriented (`Start Tunnel`) rather than readiness text (`USB Ready`/`Wi-Fi Ready`).
- [ ] Record USB/Wi-Fi/Both readiness indicators separately from the action label.
- [ ] Exercise only non-privileged device selection and idle UI navigation required to observe these facts.
- [ ] Stop before any action that triggers privilege, tunnel creation, pairing mutation, or location injection.

**Acceptance:** GUI evidence either reproduces the original symptoms or demonstrates their absence in the bounded idle scenario. Absence is not an architectural fix claim and does not certify tunnel behavior.

## 11. Work packet 0.6 — Source ownership trace ledgers

**Purpose:** Bind current behavior to exact symbols and remove ambiguity before remediation.

Read every relevant path end to end and record repository commit plus symbol/line ranges. At minimum cover:

- `PathChanger/PathChangerApp.swift`
- `PathChanger/UI/ContentView.swift`
- `PathChanger/UI/SimulationView.swift`
- `PathChanger/UI/SettingsView.swift`
- `PathChanger/UI/DeviceListView.swift`
- `PathChanger/Device/DeviceManager.swift`
- `PathChanger/Device/TunneldManager.swift`
- `PathChanger/Device/TunnelStateMachine.swift`
- `PathChanger/Device/TunnelHealthMonitor.swift`
- `PathChanger/Device/PersistentLocationBridge.swift`
- `PathChanger/Device/DevLocationBridge.swift`
- `PathChanger/Core/StateManagers/DeviceStateManager.swift`
- `PathChanger/Core/StateManagers/RouteStateManager.swift`
- `PathChanger/Core/StateManagers/SimulationStateManager.swift`
- `PathChanger/Core/PythonPathResolver.swift`
- `PathChanger/Core/DependencyValidator.swift`
- `scripts/location_bridge.py`
- `Package.swift`, `project.yml`, and the active build/deployment scripts

Produce four ledgers: lifecycle writers, discovery ingestors, start/stop entry points, and active GUI controls. Each entry must identify owner, source fact, copied/derived state, downstream consumer, asynchronous boundary, privilege boundary, current tests, and conflict with the target architecture.

**Acceptance:** Every active GUI control and tunnel/discovery transition has one traceable current call path; duplicated ownership is surfaced, not rationalized away.

## 12. Work packet 0.7 — Cleanup, evidence finalization, and gate decision

### 12.1 Always-run packet cleanup

Execute these steps after packet 0.5 and on every early exit after app launch:

- [ ] If the managed FlowDeck log process is still alive, send an interrupt, wait for termination, and record its final exit status and byte count.
- [ ] Run `flowdeck ui mac session stop --json` after confirming exact syntax with FlowDeck help; record the result even if no session remains.
- [ ] Run `flowdeck stop "$STAGE0_APP_ID" --json` after confirming exact syntax with FlowDeck help; then run `flowdeck apps --json` and verify the Stage 0 app is absent.
- [ ] Capture the installed-app after-state using the same hashes and read-only signing inspection as packet 0.3.
- [ ] Record cleanup results in `conclusion/cleanup.json`.

Cleanup may stop only Stage 0-owned FlowDeck sessions, the Stage 0-owned dev app, and Stage 0-owned log processes. It must never stop a pre-existing app/process, clean the repository, delete DerivedData outside this run, or touch `/Applications/PathChanger.app`.

### 12.2 Reconciliation and tamper-evident upload

- [ ] Compare fresh evidence against every Stage 0 claim in the canonical ledger.
- [ ] Classify each item as confirmed, refuted, blocked, not observed, or out of scope.
- [ ] Record deviations without changing implementation.
- [ ] Confirm no privileged tunnel operation occurred.
- [ ] Confirm installed-app isolation and evidence-bundle integrity.
- [ ] Redact prohibited data, finalize every artifact hash, close `manifest.json`, and generate a bundle-level SHA-256.
- [ ] Copy only the redacted packet into the non-existing `stage-0/<UTC-run-id>/packet-0.N/` path in `/Users/datamatics/.rovodev/evidence-checkouts/PathChanger-Evidence`; write `MANIFEST.sha256`; verify Git status contains only that packet; commit append-only; push protected `main`; and record the remote commit SHA and URL in `conclusion/upload-receipt.json`.
- [ ] Clone/fetch the remote into a new temporary checkout under `/Users/datamatics/.rovodev/evidence-checkouts/verification/<run-id>/`, reproduce every manifest hash, and archive Oz’s automated review report in the packet.
- [ ] In a separate later session, Shigeo completes the exit checklist verbatim, records product-owner observations and the Stage-0 engineering/security waiver decision, and creates a distinct acceptance commit whose GitHub API verification value is `true`.
- [ ] Create and push the annotated tag `stage0-packet-0.N-accepted-<UTC-run-id>` only after the verified acceptance commit exists.
- [ ] Remove only `/Users/datamatics/.rovodev/pathchanger-stage0/<run-id>/` and the temporary verification checkout after remote and fresh-checkout verification. Preserve staging on upload/verification failure and report its path; never broaden either deletion target.
- [ ] Update the canonical claimed-vs-verified ledger only in a separately authorized documentation step after evidence approval.

## 13. Stage 0 exit gate

Stage 0 passes only when:

- [ ] Repository, environment, dependency, and hardware baselines are revision-bound and reproducible.
- [ ] The release build and automated tests have complete retained evidence; every failure, skip, count mismatch, and flake is classified.
- [ ] Installed-app content is unchanged.
- [ ] The active GUI idle scenario is captured through FlowDeck and the original two visible symptoms have explicit bounded outcomes.
- [ ] Four source ownership trace ledgers are complete.
- [ ] No privileged operation, code change, dependency change, project-setting change, or device mutation occurred.
- [ ] All evidence hashes match `MANIFEST.sha256`, the recorded remote commit tree, and the fresh-checkout copy.
- [ ] Cleanup evidence proves the log stream, UI session, and Stage 0 app stopped and no pre-existing workspace/app artifact was touched.
- [ ] Oz’s automated review artifact is present, and Shigeo’s later-session verified acceptance commit records the checklist, product observations, and Stage-0 engineering/security waiver decision.

A Stage 0 pass means only that the baseline is trustworthy enough to plan Stage 1. It does not mean the tunnel works, the GUI defects are architecturally fixed, or release is permitted.

## 14. Immediate stop conditions

Stop and preserve evidence if any of the following occurs:

- an administrator or privilege prompt appears;
- a command would execute user-owned code as root;
- the installed app changes;
- the repository or project settings change;
- FlowDeck is unavailable, unlicensed, or lacks a valid saved configuration;
- physical-device access requires unapproved mutation or foreground interaction;
- any recorded role/waiver identity changes or a compensating control cannot be completed;
- the evidence repository is unavailable, no longer private, or its protected `main` allows force-push/deletion or stops enforcing administrators;
- the resolved staging or DerivedData path is inside the audited repository;
- evidence storage cannot provide append-only packet paths, fresh-checkout retrieval, manifest verification, or required redaction;
- observed output contains secrets, pairing material, full UDIDs, or unredacted personal paths;
- an operator proposes a workaround, timeout increase, cleanup, or code patch to make evidence pass.

The only permitted response is to mark the packet blocked or failed, retain evidence, and request a new decision.

## 15. Post-brief handoff

This brief and its Stage-0-only governance/storage waiver are approved. **Stage 0 execution is authorized exactly as written**, beginning with packet 0.1. The collection session must stop after cleanup, upload, fresh-checkout verification, and Oz’s archived review; final acceptance occurs only in the required separate later session through a GitHub-verified acceptance commit.

No implementation branch in the audited repository, source-code edit, privileged test, hardware mutation, location injection, Stage 1 work, or release action is authorized by this brief.
