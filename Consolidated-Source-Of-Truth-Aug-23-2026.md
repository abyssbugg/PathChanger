# Consolidated Source of Truth — Aug 23, 2026

> **Purpose:** Reconcile the eight original Aug. 23 project documents into one documentation baseline and implementation plan before any code is changed, with the subsequent audit-closure artifact registered as a ninth verification appendix.
>
> **Evidence rule:** “Documented and evidenced” below means the source document supplies concrete code references, runtime observations, test counts, logs, or filesystem observations. It does **not** mean this reconciliation independently re-ran the code, GUI, tests, hardware, privilege path, or release pipeline. Every completion/fix/verification claim remains **unconfirmed by this task** until the verification named in section E is performed. The ninth appendix verifies this document’s structure and fingerprint; it does not independently certify product behavior.
>
> **Citation key:** Short names used after their first full filename mean: `Todo` = `Todo-aug-23-2026.md`; `Architecture-Note` = `Architecture-Note-Aug-23-2026.md`; `Lifecycle-Architecture` = `Tunnel-Lifecycle-Architecture-Aug-23-2026.md`; `Dependencies-Audit` = `Tunnel-Dependencies-Integrations-Audit-Aug-23-2026.md`; `Functional-Modules` = `Tunnel-Functional-Modules-Data-Flows-Aug-23-2026.md`; `Security-Reliability-Audit` = `Tunnel-Security-Reliability-Audit-Aug-23-2026.md`; `PathChanger…Final-Assessment` = `PathChanger-Tunnel-Lifecycle-Final-Assessment-Aug-23-2026.md`; `Final-Report-Completion` = `Final-Report-Completion-Aug-23-2026.md`; and `Final-Coverage-Ledger` = `Final-Coverage-Ledger-and-Audit-Conclusion-Aug-23-2026.md`. A citation names the source and its Markdown section; line numbers are intentionally omitted because they are unstable under later archival banners.

## A. Executive summary — where the project actually stands

PathChanger is not production-ready. The documentation consistently describes a viable macOS GUI application whose tunnel subsystem has substantial mapping and test coverage, but whose successful USB, Wi-Fi, daemon, persistent-bridge, failover, and five-mode hardware behavior is still unverified; the latest status document explicitly rates production release confidence “not acceptable” (`Final-Report-Completion-Aug-23-2026.md`, **Overall confidence**).

The core architectural problem is duplicated and overlapping “connection truth”: device identity, transport readiness, process existence, endpoint availability, lifecycle, route, and GUI state are owned or inferred by multiple layers. This began as a hypothesis in `Todo-aug-23-2026.md` (**Open questions**), was declared “confirmed at the structural level” by `Architecture-Note-Aug-23-2026.md` (**Root-cause hypothesis verdict**), was decomposed into lifecycle/readiness/session boundaries by `Tunnel-Lifecycle-Architecture-Aug-23-2026.md` (**Mapping result**), and was expanded into modules M1–M13 and flows A–I by `Tunnel-Functional-Modules-Data-Flows-Aug-23-2026.md` (**Functional domain model**; **Cross-module invariants**).

The most urgent blockers are not cosmetic GUI defects. They are: user-owned Homebrew Python/package code executed with root privileges; root log redirection and process-identity risks; a persistent bridge with exact-once and concurrency defects; unserialized lifecycle effects without generation identity; process-only health checks; incompatible daemon/one-shot success models; fragile human-log parsing; incomplete teardown proof; and insufficient tests for critical privileged and persistent-bridge paths (`Tunnel-Security-Reliability-Audit-Aug-23-2026.md`, **Security findings**, **Reliability findings**, **Prioritized remediation**).

The GUI remains the contract. The two original visible failures—readiness text occupying the tunnel action and one physical phone appearing multiple times—are claimed as live-corrected in the latest ledger: the button displayed “Start Tunnel,” and four raw records collapsed to one canonical GUI device (`Final-Report-Completion-Aug-23-2026.md`, **Live GUI and hardware ledger — Verified live**). Those observations are important but do not certify the architecture or all discovery paths; they must be independently reproduced and protected by end-to-end GUI tests.

Stage 0 execution is explicitly authorized under the entry gate and Stage-0-only single-maintainer/storage waiver in `Stage-0-Verification-and-Acceptance-Brief-Aug-23-2026.md`. The ten minimum product/policy decisions plus Decision 11 governance assignments are approved in section J.1; the four questions in section J.2 block later named stages, not Stage 0. If Stage 0 later passes its time-separated acceptance gate, the governing sequence remains Stages 1–8, with security containment and persistent-bridge correctness immediately after baseline isolation (`Final-Report-Completion-Aug-23-2026.md`, **Prioritized remediation summary**, **Completion status**; this document, **J.1**, **J.2**).

## B. Per-document summary table

| Document | Purpose and scope | Main contribution | Claimed status / confidence | Authority in this consolidation |
|---|---|---|---|---|
| `Todo-aug-23-2026.md` | Original phased roadmap for tunnel GUI state, device discovery, transports/failover, five modes, and wiring. | Defines the GUI contract, exit criteria, unresolved failover target, and initial shared-root-cause hypothesis. | Phase 0 GUI map checked; nearly all implementation/verification tasks unchecked (**Phase 0** through **Phase 5**). | Requirements origin; superseded for current status and ordering, retained for user intent and GUI acceptance. |
| `Architecture-Note-Aug-23-2026.md` | Phase 0 comprehension deliverable. | Maps active/unmounted GUI, runtime ownership, tunnel/device lifecycles, four enumeration paths, and D1–D11 divergence. | Claims Phase 0 mapping complete and structural root cause confirmed (**Phase 0 completion result**). | Canonical current-state architecture baseline; later documents supersede its “next action.” |
| `Tunnel-Lifecycle-Architecture-Aug-23-2026.md` | Phase 1 architecture/data-flow mapping; explicitly does not implement the target design. | Separates readiness from lifecycle; defines canonical attempt/session/readiness/route objects, GUI contract, and implementation dependencies. | No implementation completion claimed (**Purpose**; **Required Phase 1 state boundary**). | Canonical normative lifecycle design, extended—not replaced—by the Phase 3 functional model. |
| `Tunnel-Dependencies-Integrations-Audit-Aug-23-2026.md` | Read-only Phase 2 dependency/integration audit. | Inventories Python/pymobiledevice3, privilege, output, daemon, userspace, build/resource, and process-detection contracts; TUN-DEP-01…14. | Installed command shapes claimed sufficient, guarantees absent (**Audit conclusion**). | Canonical dependency/integration risk source; later ledger controls observed runtime version/status. |
| `Tunnel-Functional-Modules-Data-Flows-Aug-23-2026.md` | Phase 3 integration of earlier architecture, lifecycle, and dependency documents. | Defines six domain facts, M1–M13, flows A–I, lifecycle artifacts, invariants, and three implementation seams. | Claims documentation complete and no behavior changed (**Documentation result**). | Canonical integrated functional model and flow reference. |
| `Tunnel-Security-Reliability-Audit-Aug-23-2026.md` | Phase 4 static/runtime security and reliability audit. | Establishes trust boundaries, 12 security findings, 19 reliability findings, P0/P1/P2 remediation, and release gates. | Findings are documented with evidence/impact sections, but not independently revalidated here. | Canonical detailed security/reliability finding source. |
| `PathChanger-Tunnel-Lifecycle-Final-Assessment-Aug-23-2026.md` | Executive go/no-go assessment and high-level phased remediation narrative. | Summarizes principal architectural, security, and reliability causes; says viable but not shippable. | Claims build passing and several strengths verified; says tunnel is not production-safe (**Executive assessment**, **Current status**, **Verified strengths**). | Executive synthesis; parallel to, and less granular than, the completion report. |
| `Final-Report-Completion-Aug-23-2026.md` | Formal Stage 0–8 plan plus coverage ledger and confidence assessment. | Most complete status ledger among the eight original sources: tests, runtime, security, reliability, live GUI/hardware, explicit non-verifications, gates, and next step. | Claims 857 tests/0 failures/10 skipped and selected live observations; production confidence “not acceptable” (**Automated-test evidence**, **Overall confidence**). | Highest original-source authority for latest status, verification gaps, and action order. |
| `Final-Coverage-Ledger-and-Audit-Conclusion-Aug-23-2026.md` | Post-consolidation verification and audit-closure appendix; not an original synthesis input. | Independently checks the canonical document’s fingerprint/structure, records reviewed source paths and evidence coverage, states the final no-go posture, and reduces the prerequisite decision set to ten minimum items. | Records the canonical artifact’s exact SHA-256 and line count; explicitly rates live functional confidence low and prohibits unrestricted implementation (**Consolidated document verification**, **Live GUI/runtime evidence**, **Final go/no-go decision**). | Authoritative for audit closure and verification of this canonical artifact; it does not supersede the canonical plan or independently certify product behavior. |

### B.1 Overlap map

| Shared ground | Documents | Duplication / relationship |
|---|---|---|
| Original requirements and phase gates | `Todo`; `Architecture-Note`; `Final-Report-Completion` | `Todo` defines intent; `Architecture-Note` reports Phase 0; `Final-Report-Completion` reorders remaining work into safety-first Stages 0–8. |
| GUI composition and wiring | `Architecture-Note`; `Functional-Modules`; both final reports | Phase 0 provides exhaustive mapping; Phase 3 models GUI projection as M13; final documents summarize coverage and remaining wiring work. |
| Lifecycle ownership and state | `Architecture-Note`; `Lifecycle-Architecture`; `Functional-Modules`; `Security-Reliability`; both final reports | Increasing depth: divergence register → target state boundary → module/flow model → reliability findings → status/plan. |
| Device identity and duplicate records | `Todo`; `Architecture-Note`; `Functional-Modules`; both final reports | Requirement/hypothesis → enumeration/merge mapping → canonical target contract → claimed live GUI evidence and remaining Stage 5 work. |
| Python/pymobiledevice3 and privilege | `Dependencies-Audit`; `Functional-Modules`; `Security-Reliability`; both final reports | Dependency audit establishes contract risks; security audit establishes exploit surface; final reports prioritize containment. |
| Persistent bridge | `Dependencies-Audit`; `Functional-Modules`; `Security-Reliability`; both final reports | Resource/route gap → M12/Flow E → exact-once/concurrency findings → Stage 2 blocker and certification gap. |
| Daemon vs one-shot success | `Dependencies-Audit`; `Functional-Modules`; `Security-Reliability`; `Final-Report-Completion` | Repeated consistently as a contract mismatch requiring mode-specific validation and per-device daemon routes. |
| Health, adoption, teardown | `Lifecycle-Architecture`; `Functional-Modules`; `Security-Reliability`; `Final-Report-Completion` | Current flows and duplicated detection → missing contracts → risks → Stage 3/4/6 verification. |
| USB/Wi-Fi/failover and five modes | `Todo`; `Functional-Modules`; both original final reports; `Final-Coverage-Ledger` | Original GUI outcomes remain largely unverified; the governing plan postpones certification until architecture/security prerequisites are met, and the closure appendix confirms live functional confidence remains low. |
| Consolidation verification and audit closure | `Consolidated-Source-Of-Truth-Aug-23-2026.md`; `Final-Coverage-Ledger` | The canonical document performs reconciliation; the ninth appendix verifies its structure/fingerprint, summarizes coverage, and records the final go/no-go decision without replacing the canonical status or plan. |

## C. Contradiction register

The register distinguishes true disagreement from current-state/target-state differences. A target that does not yet exist is not treated as contradicting a current-state audit.

| # | Source A | Source B | Nature of conflict | Authority / resolution |
|---|---|---|---|---|
| C1 | “Not moving forward” (`Todo`, **Status**) | “The project is stabilized enough for structured remediation” (`PathChanger…Final-Assessment`, **Current status**) | Project-state disagreement. | The final assessment is later synthesis; treat the project as remediable but not shippable. “Not moving forward” remains historical context. |
| C2 | “The tunnel service gets stuck displaying ‘Wi-Fi Ready’ or ‘USB Ready’” (`Todo`, **Phase 1 — Confirmed bug**) | “Tunnel button displays ‘Start Tunnel’ rather than readiness text” (`Final-Report-Completion`, **Live GUI and hardware ledger — Verified live**) | Original bug vs claimed later observation. | Latest ledger controls current claimed status, but this task marks the fix unconfirmed pending fresh GUI reproduction and regression coverage. |
| C3 | “one phone → 4 duplicates” (`Todo`, **Phase 2**) | “Four raw device records collapsed to one canonical GUI device” (`Final-Report-Completion`, **Live GUI and hardware ledger — Verified live**) | Original symptom vs claimed later deduplication. | Latest ledger controls observed GUI status; Stage 5 remains required because ingestion normalization, names, ghost removal, and multi-device behavior are not certified. |
| C4 | The two bugs are “probably the same root cause” (`Todo`, **Open questions**) | “Verdict: confirmed at the structural level” (`Architecture-Note`, **Root-cause hypothesis verdict**) | Speculation vs structural conclusion. | Architecture note supersedes the hypothesis only at structural-analysis level; runtime causality still requires code-path and regression verification. |
| C5 | “The next gated action is Phase 1” (`Architecture-Note`, **Phase 0 completion result**) | “The next safe implementation step is Stage 0 … followed immediately by privileged security containment and persistent-bridge correctness” (`Final-Report-Completion`, **Completion status**) | Competing next-step instructions. | Completion report is authoritative: later audits exposed P0 risks and justify a new safety-first Stage 0–8 sequence. |
| C6 | App declares pymobiledevice3 `6.1.5` sufficient but behavior requires `>=6.2.0` (`Dependencies-Audit`, **TUN-DEP-02**) | Declared 6.1.5 “does not match modern 10.x APIs the code assumes” (`PathChanger…Final-Assessment`, **Phase results**) and runtime 10.7.4 (`Final-Report-Completion`, **Dependency and runtime integration**) | Different descriptions of the compatibility floor. | Not enough evidence to choose 6.2 vs 10.x as the true minimum. Treat 10.7.4 as observed runtime only; Stage 1 must pin/test an explicit supported version and transitive graph. |
| C7 | “Fixed Python executable policy” is a strength (`Dependencies-Audit`, **TUN-DEP-S2**) | Candidate fallback “changes TLS and protocol stack” (`Dependencies-Audit`, **TUN-DEP-11**) | Internal policy tension repeated across summaries. | The strength means ordered candidates, not a single immutable runtime. Risk finding controls: selection must be pinned and compatibility-validated. |
| C8 | One-shot userspace operations “can potentially use” no-root tunnels (`Dependencies-Audit`, **Upstream userspace-tunnel integration**) | “current privileged tunnel path executes … Homebrew Python … as root” (`PathChanger…Final-Assessment`, **Principal security cause**) | Capability vs current implementation. | Both can be true by operation. Do not generalize userspace support; Stage 1 must produce an operation/capability matrix and prefer no-root only where proven. |
| C9 | Device is visible through CoreDevice/Bonjour (`Final-Report-Completion`, **Live GUI and hardware ledger — Verified live**) | Tunnel reports “No tunnel services discovered” and “Device is not connected” (`Final-Report-Completion`, **Observed failure evidence**) | Discovery/readiness evidence conflicts with tunnel endpoint acquisition. | No silent reconciliation: discovery visibility is not usable tunnel capability. Code inspection must trace preparation, pairing, selected UDID, network suitability, protocol, and endpoint validation. |
| C10 | `TunnelStateMachine.swift` has “Strong coverage” (`Final-Report-Completion`, **Tunnel lifecycle core**) | Degraded lifecycle is “Not implemented” and reconnect is “Dead/incomplete” (`Final-Report-Completion`, **Reliability coverage**) | Coverage label risks implying feature completeness. | Reliability ledger controls. Existing-state tests may be strong while required-state coverage is absent; do not call the seven-state lifecycle complete. |
| C11 | Deduplication has “Strong discovery evidence” (`Final-Report-Completion`, **Tunnel lifecycle core**) | Four raw records still exist before GUI collapse (`Final-Report-Completion`, **Live GUI and hardware ledger — Verified live**) | Layer-specific success vs canonical-ingestion requirement. | GUI collapse is evidence of presentation behavior, not proof of canonical ingestion. Stage 5 remains authoritative. |
| C12 | “Build stability: passing” (`PathChanger…Final-Assessment`, **Current status**) | “Production release confidence: not acceptable” (`Final-Report-Completion`, **Overall confidence**) | Potentially misleading use of “passing.” | No technical contradiction: buildability is not release readiness. Canonical wording must always state both together. |
| C13 | Phase 1 target uses `active`/`failed` (`Lifecycle-Architecture`, **Tunnel lifecycle state machine**) | Current machine uses `running`/`error` (`Functional-Modules`, **M5 — Lifecycle State Kernel**) | Current vs target vocabulary. | Not a contradiction. Preserve current labels in as-is documentation and seven-state labels in target design; migration must map semantics explicitly. |
| C14 | “Active route is not published” (`Functional-Modules`, **M12 — Current gaps**) | Direct/persistent consumers implicitly choose routes from RSD presence (`Functional-Modules`, **Data flow D**, **Data flow E**) | Multiple implicit routes vs no canonical published route. | M12 target contract controls: one immutable `DeviceSessionRoute` must become the only route consumed by injection. |
| C15 | Two files claim finality: `PathChanger…Final-Assessment` and `Final-Report-Completion` | The first says “not … shippable”; the second says “Production release confidence: not acceptable” and supplies a new plan. | Filename/status ambiguity, not conclusion disagreement. | `Final-Report-Completion` is final for this documentation cycle and plan; neither means implementation is complete. The assessment remains an executive companion. |

## D. Authority hierarchy and rationale

### D.1 Topic-specific hierarchy

1. **Canonical cross-document decisions, current documentation status, and governing plan:** `Consolidated-Source-Of-Truth-Aug-23-2026.md`.
2. **Verification of the canonical artifact and closure of this audit cycle:** `Final-Coverage-Ledger-and-Audit-Conclusion-Aug-23-2026.md`. Its authority is limited to document verification, the recorded audit coverage, and the go/no-go conclusion; it cannot supersede canonical decisions or certify unrerun product behavior.
3. **Latest original-source status, evidence ledger, verification gaps, and action order:** `Final-Report-Completion-Aug-23-2026.md`.
4. **Detailed security/reliability findings:** `Tunnel-Security-Reliability-Audit-Aug-23-2026.md`.
5. **Integrated functional modules, flows, artifacts, and invariants:** `Tunnel-Functional-Modules-Data-Flows-Aug-23-2026.md`.
6. **Normative lifecycle/readiness architecture and GUI data contract:** `Tunnel-Lifecycle-Architecture-Aug-23-2026.md`.
7. **Dependency/runtime/integration contracts:** `Tunnel-Dependencies-Integrations-Audit-Aug-23-2026.md`, except where the later completion ledger records newer observed runtime state.
8. **Current GUI/composition/discovery baseline:** `Architecture-Note-Aug-23-2026.md`.
9. **Executive interpretation:** `PathChanger-Tunnel-Lifecycle-Final-Assessment-Aug-23-2026.md`.
10. **Original requirements and acceptance intent:** `Todo-aug-23-2026.md`.

### D.2 Required finality resolutions

- **`Tunnel-Lifecycle-Architecture` vs `PathChanger…Final-Assessment`:** the assessment is a successor in reporting stage but a parallel view in content. It summarizes architecture, security, reliability, and remediation; it does not replace the lifecycle document’s detailed target model.
- **`PathChanger…Final-Assessment` vs `Final-Report-Completion`:** the completion report is the authoritative final status/plan artifact among the eight original inputs because it adds the formal Stage 0–8 order, coverage ledger, explicit live/non-live split, and completion status. The assessment is the executive summary. They agree that the product is not shippable.
- **`Architecture-Note` vs the four `Tunnel-*` deep dives:** the note is the Phase 0 baseline. The Phase 1–4 documents progressively extend it by topic; they replace its phase-order recommendation where later risks require reprioritization, but do not replace its detailed current GUI/discovery map.
- **Canonical document vs `Final-Coverage-Ledger`:** the ledger is subsequent validation, not a successor source of truth. It verifies and closes the documentation audit, while this canonical document continues to own reconciled decisions, status qualifications, open questions, and the Stage 0–8 plan (`Final-Coverage-Ledger`, **Consolidated document verification**, **Documentation status**, **Authoritative next action**).

### D.3 Supersession and verification chain

`Todo` (requirements) → `Architecture-Note` (Phase 0 current-state map) → `Tunnel-Lifecycle-Architecture` (Phase 1 target boundary) → `Dependencies-Audit` (Phase 2 integration constraints) → `Functional-Modules` (Phase 3 integrated model) → `Security-Reliability-Audit` (Phase 4 risk gates) → `PathChanger…Final-Assessment` (executive assessment) → `Final-Report-Completion` (latest original-source status ledger and governing plan) → `Consolidated-Source-Of-Truth-Aug-23-2026.md` (canonical reconciliation).

`Final-Coverage-Ledger` then verifies the canonical artifact and closes the audit cycle; it is a verification edge, not another supersession edge. The chain establishes precedence for **decisions and status**, not permission to discard specialist detail.

## E. Claimed-vs-verified ledger

### E.1 Status vocabulary

- **Documented and evidenced:** source includes a concrete observation, code/path reference, test count, log, permission, or runtime value.
- **Documented but asserted:** source states a conclusion without independently reviewable evidence in the document.
- **Not documented / not verified:** source explicitly lacks evidence or does not cover the behavior.
- **Independent product status for this task:** **unconfirmed** for every product-behavior row; no code, test, GUI, hardware, privilege, or release verification was run. Documentation-artifact structure and fingerprint are separately verifiable and do not upgrade product claims.

### E.2 Completion and working-behavior claims

| Claim | Documentation status | Source | Independent check required |
|---|---|---|---|
| Phase 0 GUI, tunnel, discovery, and divergence mapping complete | Documented but asserted | `Architecture-Note`, **Phase 0 completion result** | Trace every active GUI control and all four discovery paths against current source. |
| Structural shared root cause confirmed | Documented/evidenced by mapped ownership, but runtime causality unproven | `Architecture-Note`, **GUI/backend state-divergence register**, **Root-cause hypothesis verdict** | End-to-end event/source tracing for both original GUI defects. |
| Build stability passing / release build passed | Documented but asserted | Both final reports, **Current status** / **Automated-test evidence** | Re-run clean release build with preserved logs using approved Apple tooling. |
| 857 tests, 0 failures, 10 skipped | Documented but asserted | `Final-Report-Completion`, **Automated-test evidence** | Re-run suite; archive results; inspect all skips and flake history. |
| TunnelStateMachine 34 tests passed; TunneldManager 38 run/1 skipped/0 failed | Documented but asserted | `Final-Report-Completion`, **Automated-test evidence** | Re-run targeted suites and compare covered states to required seven-state model. |
| One phone shown once after four raw records | Documented and live-observation evidenced | `Final-Report-Completion`, **Live GUI and hardware ledger — Verified live** | Fresh/relaunch/unplug/replug/multi-device GUI matrix plus ingestion identity audit. |
| Tunnel button shows “Start Tunnel,” not readiness | Documented and live-observation evidenced | Same section | Fresh GUI regression through every start/stop/error/adoption state and every entry point. |
| Failed Wi-Fi start reaches stable “Tunnel Error” and does not reconnect-loop | Documented and live-observation evidenced (>85 seconds claimed) | `Final-Report-Completion`, **Reliability coverage**, **Live GUI and hardware ledger** | Reproduce with deterministic failure, stale callbacks, relaunch, and repeated attempts. |
| Selected Python 3.13.15 and pymobiledevice3 10.7.4 | Documented and runtime-observation evidenced | `Final-Report-Completion`, **Dependency and runtime integration** | Recheck selected interpreter, ownership, hashes, import path, and supported compatibility matrix. |
| `--script-mode` exists and daemon defaults to `127.0.0.1:49151` | Documented and CLI-help evidenced | Same section | Pin supported version and add contract tests; CLI help alone does not prove app integration. |
| Privileged argv, UDID, coordinate, and environment validation covered | Documented but test evidence not attached | `Final-Report-Completion`, **Security coverage** | Run targeted adversarial tests and inspect all privilege-boundary call sites. |
| Fresh dev app did not overwrite installed app | Documented and timestamp-observation evidenced | `Final-Report-Completion`, **Live GUI and hardware ledger** | Repeat clean builds and inspect all scripts/CI paths; enforce build/install separation. |
| Documentation phases 0–4 completed | Documented but asserted | `Final-Report-Completion`, **Documentation coverage** | This consolidated document confirms presence, not factual correctness of every claim. |
| Canonical document contains ordered sections A–J, Stages 0–8, all eight original source references, and no draft placeholders | Documented and independently artifact-verified | `Final-Coverage-Ledger`, **Consolidated document verification** | Re-run the structural validator and refresh the appendix fingerprint after every canonical edit; this verifies documentation structure only. |

### E.3 Explicitly unverified functionality

The latest ledger explicitly does **not** verify: successful Wi-Fi RSD, USB, or daemon tunnels; direct GUI userspace injection; physical-device persistent bridge; relaunch adoption; clean process/interface/port teardown; same-network or USB-instability detection; either failover direction; Teleport, Jump, Two-Spot, Multi-Spot, or Joystick device-side behavior; safe mode; cooldown; failover during a mode; or two simultaneous physical devices (`Final-Report-Completion`, **Live GUI and hardware ledger — Not verified live**). These are not working features for planning purposes until certified through the GUI.

## F. Consolidated master state

### F.1 Current architecture (documented model)

1. **Application and GUI composition.** `AppState` is the composition root but owns or aggregates more state than a thin composition root should. The active product surface is the map-first SwiftUI shell; older sidebar/list/inspector/floating-control surfaces remain compiled but unmounted (`Architecture-Note-Aug-23-2026.md`, **Runtime composition and ownership**, **GUI map and control call paths**, **Compiled but unmounted alternate UI**).
2. **Device observation.** Physical-device observations arrive through four source paths, including usbmux and Bonjour/mobdev2, and are merged toward a canonical identity. Current GUI evidence shows four raw records can collapse to one displayed device, but the target requires normalization during ingestion and one canonical device carrying a set of observed transports (`Architecture-Note-Aug-23-2026.md`, **Current device-discovery lifecycle**; `Final-Report-Completion-Aug-23-2026.md`, **Stage 5**, **Live GUI and hardware ledger**).
3. **Transport readiness.** USB/Wi-Fi readiness is observed and copied into GUI-facing properties, but same-network, both-ready, fallback, and instability are not complete first-class facts. The target is a per-device `TransportReadinessSnapshot` independent of tunnel lifecycle (`Tunnel-Functional-Modules-Data-Flows-Aug-23-2026.md`, **M2 — Transport Readiness Observation**; `Tunnel-Lifecycle-Architecture-Aug-23-2026.md`, **Transport readiness state machine**).
4. **Lifecycle.** `TunnelStateMachine` nominally models lifecycle, while `TunneldManager`, `DeviceManager`, `DeviceStateManager`, `TunnelHealthMonitor`, and GUI code also make or copy lifecycle decisions. Current states are documented as idle/starting/running/stopping/error; the required target is idle/starting/active/degraded/reconnecting/failed/stopping with serialized effects and generation-scoped events (`Tunnel-Lifecycle-Architecture-Aug-23-2026.md`, **Current truth sources and duplicated state**, **Required Phase 1 state boundary**, **Mapping result**; `Tunnel-Functional-Modules-Data-Flows-Aug-23-2026.md`, **M5 — Lifecycle State Kernel**).
5. **Process and privilege boundary.** Tunnel commands are allowlisted and environment-cleaned, but current elevated execution can run a user-owned Homebrew interpreter and package tree as root through an AppleScript/shell boundary. Process ownership is often inferred from PID or broad `pgrep` matching rather than helper-issued session identity (`Tunnel-Dependencies-Integrations-Audit-Aug-23-2026.md`, **Command and integration contracts**, **TUN-DEP-01**, **TUN-DEP-09**; `Tunnel-Security-Reliability-Audit-Aug-23-2026.md`, **SEC-TUN-01**, **SEC-TUN-04**, **SEC-TUN-05**, **SEC-TUN-12**).
6. **Endpoint acquisition.** One-shot modes parse output for RSD host/port; daemon mode queries a loopback HTTP API. Human-readable output parsing remains fragile, and daemon success is incorrectly coupled to a one-shot-style single endpoint while declared per-device daemon routes are not populated (`Tunnel-Functional-Modules-Data-Flows-Aug-23-2026.md`, **M7 — Endpoint Acquisition and Validation**, **Data flow A**, **Data flow C**).
7. **Session publication and routing.** Endpoint and active-mode truth are duplicated rather than published as one immutable validated `TunnelSession`/`DeviceSessionRoute`. Standard and persistent injection paths have divergent capabilities, and persistent routing depends on an external RSD endpoint for modern devices (`Tunnel-Functional-Modules-Data-Flows-Aug-23-2026.md`, **M8 — Tunnel Session Publication**, **M12 — Device Session Routing**, **Data flow D**, **Data flow E**).
8. **Health, adoption, teardown.** Health currently relies primarily on process existence, adoption duplicates broad process detection and shared-log parsing, and stop does not prove complete cleanup. Degraded/reconnecting do not yet flow through the lifecycle, and no generation identity prevents stale callbacks from mutating current state (`Tunnel-Lifecycle-Architecture-Aug-23-2026.md`, **Current adoption and app-relaunch flow**, **Current health and degradation flow**, **Current stop data flow**; `Tunnel-Security-Reliability-Audit-Aug-23-2026.md`, **REL-TUN-04**, **REL-TUN-06**, **REL-TUN-07**, **REL-TUN-10**, **REL-TUN-11**).
9. **Simulation and modes.** Teleport, Jump, Two-Spot, Multi-Spot, and Joystick are GUI requirements, but device-side behavior is not live-certified. Simulation state must be independent of transport and survive route changes; the GUI must render lifecycle/readiness facts rather than infer them (`Todo-aug-23-2026.md`, **Phase 4**; `Tunnel-Functional-Modules-Data-Flows-Aug-23-2026.md`, **Cross-module invariants**, **M13 — GUI Projection**; `Final-Report-Completion-Aug-23-2026.md`, **Stage 7**, **Not verified live**).

### F.2 Bugs and defects treated as confirmed by the documentation

These are **documentation-confirmed, independently unconfirmed**:

- Overlapping connection truth and multiple lifecycle/status writers (`Architecture-Note`, **D1–D8**, **Root-cause hypothesis verdict**).
- User-owned Python/package code executed as root; root-log symlink/TOCTOU exposure; permissive pairing-record permissions; PID/process-identity weakness; unpinned privileged dependencies; log privacy exposure; unauthenticated loopback API; incomplete persistent-bridge connection-field validation; broad entitlements; untyped AppleScript boundary (`Tunnel-Security-Reliability-Audit`, **SEC-TUN-01…12**).
- Persistent ready wait can double-resume; only one pending request is supported; lifecycle effects are not serialized; no attempt/session generation; subprocess output can deadlock; health does not measure endpoint/service health; degraded/reconnecting are absent; daemon/one-shot success models conflict; log parsing is fragile; adoption is duplicated; teardown is unproven; privileged commands block the main actor; termination teardown is duplicated; recovery can enter starting without launch; specific errors are overwritten; connection capabilities diverge; retained output is not drained; foreign process can be marked active; critical failure paths lack tests (`Tunnel-Security-Reliability-Audit`, **REL-TUN-01…19**).
- Per-device daemon route storage is declared but not populated, while startup waits for a single one-shot-style endpoint (`Tunnel-Functional-Modules`, **M7 — Confirmed daemon integration gap**).
- Persistent bridge resource packaging varies by build path and can depend on repository working directory (`Tunnel-Dependencies-Audit`, **TUN-DEP-06**; `Tunnel-Functional-Modules`, **Data flow E**).
- Installed dependency validation, selection, and compatibility are not guaranteed (`Tunnel-Dependencies-Audit`, **Audit conclusion**).

### F.3 Behavior documented as working, but not independently confirmed here

- The project builds and the cited test suites pass (`PathChanger…Final-Assessment`, **Current status**; `Final-Report-Completion`, **Automated-test evidence**).
- A fresh development launch left `/Applications/PathChanger.app` unchanged (`Final-Report-Completion`, **Live GUI and hardware ledger — Verified live**).
- One GUI device appeared from four raw observations, and the tunnel action showed “Start Tunnel” (`Final-Report-Completion`, same section).
- Wi-Fi start presented an administrator prompt, launched a process, then reached stable “Tunnel Error” without returning to Connecting (`Final-Report-Completion`, same section; **Observed failure evidence**).
- A usable endpoint is required before active state, and the automatic connecting loop is claimed eliminated (`Final-Report-Completion`, **Reliability coverage**).
- Privileged command allowlisting, argument validation, and environment cleanup exist (`Tunnel-Dependencies-Audit`, **Strengths**; `Tunnel-Security-Reliability-Audit`, **Security strengths**).

**Independently confirmed working behavior in this reconciliation:** none. This task deliberately did not execute the app, tests, hardware, privileged commands, or code paths.

### F.4 Prior questions and current resolution status

- **Resolved:** failover interruption acceptance is 1–3 seconds, measured from active-route loss to validated replacement-route publication (`Todo`, **Open questions**; this document, **J.1 decision 6**).
- **Open:** define current and intended Jump Teleport behavior (`Todo`, **Phase 4.2 — Jump Teleport**; this document, **J.2**).
- **Policy resolved; capability matrix pending:** supported discovery, preparation, and one-shot GUI operations must be no-root; a signed helper is limited to demonstrated unavoidable privilege (`Dependencies-Audit`, **Upstream userspace-tunnel integration**; this document, **J.1 decisions 2–3**).
- **Policy resolved; versions pending:** use a managed, exactly locked runtime; Stage 1 must select and validate exact Python/pymobiledevice3 versions and protocols (`Dependencies-Audit`, **Installed compatibility verification**, **TUN-DEP-02**, **TUN-DEP-07**; this document, **J.1 decision 4**).
- **Partially resolved:** healthy USB is preferred and failover behavior is approved; the exact same-network measurement remains open (`Functional-Modules`, **M2**, **M4**, **M9**, **M12**; this document, **J.1 decision 5**, **J.2**).
- **Open implementation detail:** define the authoritative packaged location and target-resource treatment of `scripts/location_bridge.py` (`Dependencies-Audit`, **Persistent bridge resource integration**; `Functional-Modules`, **Data flow E**).
- **Policy resolved; numeric limits pending:** safe mode and cooldown use enforced per-mode limits, with exact thresholds specified in Stage 7 (`Todo`, **Phase 4.0**; `Final-Report-Completion`, **Stage 7**; this document, **J.1 decision 7**).

### F.5 Known risk posture

- **Release blocker / P0:** privileged execution of user-owned code, root log race, process identity/termination, pairing privacy, unpinned dependency integrity, persistent-bridge exact-once/concurrency, and subprocess deadlock (`Tunnel-Security-Reliability-Audit`, **P0 — Block privileged-release risk**, **P0 — Fix deterministic crash/hang risks**).
- **High / P1:** lifecycle generation and serialization, endpoint health, degraded/reconnect, daemon contract, adoption, teardown, error preservation, and capability modeling (`Tunnel-Security-Reliability-Audit`, **P1 — Make lifecycle truth reliable**, **P1 — Make capabilities explicit**).
- **Functional certification risk:** no successful live tunnel transport, failover, physical persistent bridge, or five-mode hardware matrix has been documented (`Final-Report-Completion`, **Not verified live**, **Overall confidence**).
- **Deployment risk:** development/manual build paths can affect installed app and resources; release artifact itself is not certified (`Dependencies-Audit`, **Build and deployment integration**, **TUN-DEP-12**; `Final-Report-Completion`, **Stage 8**).

## G. Unified ordered action plan

This order follows technical and safety dependencies, not the original document order. No stage begins until the prior gate is evidenced through the GUI where applicable.

### Stage 0 — Preserve, reproduce, and instrument the baseline

**Actions**
1. Keep development builds isolated from `/Applications/PathChanger.app`; separate build from install and prevent scripts from overwriting/deleting installed bundles.
2. Re-run the existing build/test baseline and retain machine-readable evidence; enumerate skips and the MovementPhysics flake.
3. Document the required test seams and deterministic fakes for process, endpoint, health, time, and persistent-bridge I/O before concurrency/lifecycle changes; do not implement them during Stage 0.
4. Reproduce the original GUI readiness-label and duplicate-device scenarios in a fresh session; record exact event sources and current outcomes.
5. Establish source-level trace ledgers for every lifecycle writer, discovery ingestor, start/stop entry point, and active GUI control.

**Gate:** reproducible clean GUI launch; installed app untouched; baseline build/tests evidenced; original defects either reproduced or explicitly demonstrated absent with regression coverage.

**Sources:** `Final-Report-Completion`, **Stage 0**; `Todo`, **Phase 0**, **Phase 1 verification**, **Phase 2 verification**; `Architecture-Note`, **GUI map and control call paths**. **Execution/acceptance artifact:** `Stage-0-Verification-and-Acceptance-Brief-Aug-23-2026.md`; its existence does not authorize execution.

### Stage 1 — Contain privileged execution and dependency risk

**Actions**
1. Produce an operation/capability matrix that requires no-root discovery, preparation, and supported one-shot GUI location actions; identify any persistent/high-frequency capability that demonstrably requires privilege.
2. Stop executing user-owned Homebrew Python/packages as root; implement privilege, where proven unavoidable, only through a signed typed helper instead of AppleScript shell embedding.
3. Eliminate root redirection to user-controlled paths; bind launched processes to helper-issued session identity; enforce private pairing-record permissions.
4. Select a managed runtime; pin and hash Python, pymobiledevice3, and transitive dependencies; define supported protocol/version combinations, compatibility tests, and controlled upgrade policy.
5. Add adversarial privilege-boundary tests: symlink/TOCTOU, PID reuse/foreign process, environment/import path, malformed target/connection fields, log privacy, and daemon API exposure.

**Gate:** no user-owned root code; no root log race; no unrelated process termination/adoption; private pairing records; reproducible dependency graph; GUI start paths use only approved capability routes.

**Sources:** `Security-Reliability-Audit`, **SEC-TUN-01…12**, **P0 — Block privileged-release risk**, **Security gates**; `Dependencies-Audit`, **TUN-DEP-01…03**, **TUN-DEP-05**, **TUN-DEP-07**, **TUN-DEP-11**, **TUN-DEP-14**; `Final-Report-Completion`, **Stage 1**.

### Stage 2 — Make persistent bridge and subprocess I/O deterministic

**Actions**
1. Replace ready continuation handling with exact-once completion across success, timeout, cancellation, EOF, and process failure.
2. Enforce one in-flight request with a deterministic queue and exact-once completion; do not introduce multiplexing unless measured throughput evidence justifies a separately approved protocol change.
3. Validate the complete JSON protocol, including connection fields, not coordinates alone.
4. Package `scripts/location_bridge.py` as a proper target resource independent of working directory/build path.
5. Drain stdout/stderr continuously with streaming limits and retain readers for owned long-running processes.
6. Add stress tests for continuation races, concurrent requests, cancellation, backpressure, oversized output, timeout cleanup, and retained-process teardown.

**Gate:** no double resume, request overwrite, timeout leak, pipe deadlock, or working-directory dependency; persistent bridge failures render actionable GUI state.

**Sources:** `Security-Reliability-Audit`, **REL-TUN-01**, **REL-TUN-02**, **REL-TUN-05**, **REL-TUN-17**, **SEC-TUN-10**, **P0 — Fix deterministic crash/hang risks**; `Functional-Modules`, **Data flow E**; `Final-Report-Completion`, **Stage 2**.

### Stage 3 — Centralize lifecycle and transport readiness

**Actions**
1. Introduce immutable `TransportReadinessSnapshot`, `TunnelAttempt`, `TunnelSession`, typed failure, teardown report, and `DeviceSessionRoute` models.
2. Implement one per-device readiness store and one seven-state lifecycle kernel: idle, starting, active, degraded, reconnecting, failed, stopping.
3. Attach generation ID, canonical UDID, timestamp, and route/mode context to every asynchronous event; reject stale events.
4. Serialize events and effects; remove copied tunnel-running booleans, competing status writers, and recovery timers from decision paths.
5. Make GUI action and transport indicator separate projections; GUI renders state and never infers lifecycle from readiness/process existence.
6. Unify process detection/health ownership and wire adoption/relaunch through the same generation-scoped state kernel.

**Gate:** one lifecycle source, one readiness source, active always owns a validated immutable session, stale events cannot mutate current state, and all start/stop/error/adoption transitions are visible and correct in the GUI.

**Sources:** `Lifecycle-Architecture`, **Required Phase 1 state boundary**, **Required canonical session objects**, **GUI data contract**, **Phase 1 implementation dependencies**; `Functional-Modules`, **M2**, **M5**, **M8**, **Cross-module invariants**; `Security-Reliability-Audit`, **REL-TUN-03**, **REL-TUN-04**, **REL-TUN-07**, **REL-TUN-14**; `Final-Report-Completion`, **Stage 3**.

### Stage 4 — Repair endpoint, daemon, adoption, health, and teardown contracts

**Actions**
1. Use pymobiledevice3 `--script-mode`; separate stdout and stderr; preserve specific failure diagnostics.
2. Apply mode-specific success validators: one-shot requires parsed/validated RSD; daemon requires API readiness plus a target route.
3. Query daemon API only in daemon mode and populate per-device daemon routes.
4. Replace broad `pgrep`/shared-log adoption with owned session metadata and generation-scoped reconciliation.
5. Probe endpoint/DVT service health, not process existence alone; publish degraded/reconnect/failure through lifecycle.
6. Route every injection through one immutable `DeviceSessionRoute`.
7. Make stop idempotent and return proof of process, task, interface, socket, and port cleanup.

**Gate:** deterministic parsing, valid daemon and one-shot behavior, owned adoption, real service health, preserved error specificity, observable route, and evidenced clean teardown.

**Sources:** `Dependencies-Audit`, **TUN-DEP-04**, **TUN-DEP-08…10**, **Prioritized remediation sequence**; `Functional-Modules`, **M7…M12**, **Flows A, C, F, G, H, I**; `Security-Reliability-Audit`, **REL-TUN-06**, **REL-TUN-08…11**, **REL-TUN-15**, **REL-TUN-18**; `Final-Report-Completion`, **Stage 4**.

### Stage 5 — Complete canonical device identity and truthful readiness UI

**Actions**
1. Define one canonical `DeviceIdentity` keyed by canonical UDID with a set of transport observations.
2. Normalize usbmux, Bonjour/mobdev2, pairing, and other discovery records at ingestion; never pass raw endpoint/source-local identifiers as tunnel targets.
3. Resolve names from explicitly selected authoritative live metadata and define stale/ghost expiration.
4. Publish USB/Wi-Fi/Both/Same-network/Fallback readiness separately from lifecycle action.
5. Route every Start Tunnel surface through one selected-device API; retire divergent settings behavior.
6. Test one device, multiple transports, reconnect/relaunch, stale records, and two physical devices through the active GUI.

**Gate:** one phone is always one GUI entry; names are correct; no ghosts; readiness does not change the action label; all start entry points select the same canonical device.

**Sources:** `Todo`, **Phase 2**, **Phase 3**, **New UI requirement**; `Architecture-Note`, **Current device-discovery lifecycle**, **D2–D5**; `Functional-Modules`, **M1**, **M2**, **M13**; `Final-Report-Completion`, **Stage 5**.

### Stage 6 — Certify USB, Wi-Fi, daemon, userspace, and failover

**Actions**
1. Through the GUI, certify direct/one-shot USB, Wi-Fi, daemon, and supported no-root userspace routes independently.
2. Define same-network and “unstable USB” measurements, sampling windows, thresholds, and user-visible states.
3. Implement bounded reconnect and stability windows without infinite loops or false active states.
4. Implement healthy-USB preference: fail USB→Wi-Fi when endpoint/service health crosses the approved instability threshold, and return Wi-Fi→USB only after a defined USB stability window.
5. Preserve simulation state across route changes and prove no process/port/task/session leaks.
6. Measure route interruption from active-route loss to validated replacement-route publication; require no more than three seconds and target one second where the certified environment supports it.

**Gate:** each transport works independently through the GUI; failure and recovery are honest; failover meets the approved latency/stability policy without losing simulation state.

**Sources:** `Todo`, **Phase 3**, **Open questions**; `Functional-Modules`, **M4**, **M9**, **M12**; `Final-Report-Completion`, **Stage 6**, **Not verified live**.

### Stage 7 — Define and certify all five GUI modes

**Actions**
1. Specify enforced per-mode distance, speed, and frequency limits; exceptional-jump confirmations; bounded retries; visible cooldown timers; and safe reset behavior before implementation/testing.
2. Reverse-engineer and obtain approval for current/target Jump behavior.
3. Certify Teleport, Jump, Two-Spot, Multi-Spot, and Joystick independently through the GUI on USB and Wi-Fi.
4. Exercise all secondary controls, edits, reset/clear paths, route staging, mode switching, errors, stop/restart, and failover.
5. Remove or retire dormant/duplicate simulation implementations only after active-path parity is proven.

**Gate:** full five-mode GUI/hardware matrix passes with no residual state, no dead controls, correct device-side movement, and correct behavior during route changes.

**Sources:** `Todo`, **Phase 4**; `Architecture-Note`, **Mode context card**, **D9–D11**; `Final-Report-Completion`, **Stage 7**, **Not verified live**.

### Stage 8 — Complete wiring, deployment, and release certification

**Actions**
1. Complete GUI control → handler → implementation → test/live-status ledger; remove dead controls and duplicate settings/UI paths.
2. Enforce build/install separation and correct resource packaging.
3. Validate signing, helper authorization, hardened runtime, notarization, stapling, entitlements, dependency scanning, and privacy-sensitive logging.
4. Run security/reliability gates, current tunnel-specific line/branch coverage, full GUI/hardware acceptance, and release-artifact—not development-build—validation.
5. Archive superseded documents according to section I and make this document the maintained index/source of truth.

**Gate:** no unresolved critical/high privilege or reliability issue; all required GUI/hardware evidence attached; actual release artifact passes deployment and security checks.

**Sources:** `Todo`, **Phase 5**, **Exit criteria**; `Security-Reliability-Audit`, **Required verification gates**, **Release assessment**; `Final-Report-Completion`, **Stage 8**, **Overall confidence**.

## H. Gap analysis

The combined documentation set—including the ninth verification appendix—does not fully provide:

1. **Revision-bound source-code verification ledger.** The ninth appendix lists inspected paths, and the original documents cite many files/functions, but none attaches a current repository commit SHA, complete call graph, or per-claim source excerpt. Required: tie every claim to repository revision and exact symbol/line range.
2. **Reproducible evidence artifacts.** Test counts, live observations, filesystem checks, and runtime versions are mostly prose. Required: retained test reports, logs with privacy controls, screenshots/video, environment manifest, and hardware identifiers redacted as appropriate.
3. **A complete GUI acceptance specification.** The GUI is declared the contract, but state-by-state expected labels, controls, disabled states, progress, errors, recovery, accessibility, and relaunch behavior are not exhaustively tabulated.
4. **Formal transition tables.** The seven-state model lacks a complete event/guard/effect/timeout/idempotency table, including cancellation and stale-generation behavior.
5. **A concrete privilege-helper design.** “Signed typed helper” is proposed without protocol, authorization rule, install/update lifecycle, code-signing ownership, threat model, or rollback design.
6. **Concrete managed-runtime matrix.** The managed, exactly locked runtime policy is approved, but exact Python/pymobiledevice3 versions, protocol combinations, hashes, transitive lock, compatibility CI rows, and upgrade procedure remain to be selected and evidenced.
7. **Remaining transport and mode definitions.** Healthy-USB preference, 1–3 second failover, serialized bridge requests, and enforced per-mode safety are approved; same-network evidence, USB-instability thresholds/stability windows, numeric safety limits, and Jump semantics remain unspecified.
8. **Concrete hardware/environment matrix.** Certification of the declared support range—including one- and two-device cases—is approved, but Stage 0 must inventory exact macOS/iOS versions, CPU architectures, device models, connector types, network topologies, and available clean/upgrade environments.
9. **Data/privacy lifecycle.** Pairing-record retention, log redaction/rotation/deletion, diagnostics export, and user consent are not fully specified.
10. **Observability contract.** No stable event schema, correlation/generation IDs, privacy classification, metrics, or support diagnostics format is defined.
11. **Performance and resource budgets.** No startup, endpoint acquisition, health polling, movement update, CPU, memory, battery, or subprocess-output budgets are established beyond the approved 1–3 second failover interruption gate.
12. **Recovery/rollback details.** The completion report says rollback boundaries exist, but the visible plan does not provide operational rollback procedures for each stage.
13. **Named ownership and delivery metadata.** Engineering, independent release/security, and product approval roles are approved, but named owners, reviewers, estimates, dependency owners, and decision deadlines are not assigned.
14. **Concrete evidence endpoint and retention.** Immutable CI/release storage and canonical links are approved, but the exact service, path, access policy, retention period, and approval identities must be recorded before Stage 0 execution.
15. **Explicit distinction between current and target diagrams.** Several documents mix current facts and required contracts; future revisions need visually and semantically separate “as-is” and “to-be” sections.

## I. Documentation consolidation recommendation

### I.1 Canonical document

Make **this file, `Consolidated-Source-Of-Truth-Aug-23-2026.md`, the canonical index and decision/status document**. It should carry a revision history, repository commit SHA, evidence links, decision log, and current stage/gate status. `Stage-0-Verification-and-Acceptance-Brief-Aug-23-2026.md` is its governed Stage 0 child artifact and does not supersede it or authorize execution. Specialist documents should remain immutable evidence appendices for this audit date rather than competing sources of current truth.

### I.2 Retain as the ninth verification appendix

- `Final-Coverage-Ledger-and-Audit-Conclusion-Aug-23-2026.md` — retain as the post-consolidation verification and audit-closure appendix. It verifies canonical structure/fingerprint, records the coverage summary and final go/no-go decision, and must not be treated as an independent certification of product behavior.

After any canonical edit, re-run the canonical structural validator and refresh only the appendix’s canonical SHA-256, line count, and corresponding verification statement. The appendix does not own decisions or the Stage 0–8 plan.

### I.3 Retain as specialist appendices

- `Architecture-Note-Aug-23-2026.md` — retain as the detailed Phase 0 as-is GUI/composition/discovery map.
- `Tunnel-Lifecycle-Architecture-Aug-23-2026.md` — retain as the detailed normative lifecycle/readiness architecture.
- `Tunnel-Dependencies-Integrations-Audit-Aug-23-2026.md` — retain as the dependency/integration audit.
- `Tunnel-Functional-Modules-Data-Flows-Aug-23-2026.md` — retain as the integrated M1–M13 / Flow A–I model.
- `Tunnel-Security-Reliability-Audit-Aug-23-2026.md` — retain as the detailed findings and gate appendix.

These are not superseded for specialist detail, but they must link back to the canonical document and display an “audit snapshot—not current status” banner in any future documentation migration.

### I.4 Archive as superseded status/planning artifacts

- `Todo-aug-23-2026.md` — archive as original requirements/history. It is actively misleading as a current plan because checkboxes and phase order predate later P0 findings.
- `PathChanger-Tunnel-Lifecycle-Final-Assessment-Aug-23-2026.md` — archive as executive assessment. Its “Final” label is ambiguous and it lacks the later coverage ledger/order.
- `Final-Report-Completion-Aug-23-2026.md` — archive as the final report for the prior documentation cycle, not as implementation completion. It remains the primary original source for this consolidation’s latest evidence ledger and Stage 0–8 plan.

### I.5 Naming and maintenance policy

1. Ban unqualified `Final`, `Completion`, `Done`, and `Verified` from filenames/status unless scope and evidence are explicit.
2. Use document types: `requirements`, `as-is-architecture`, `target-architecture`, `audit`, `evidence-ledger`, `decision-record`, and `implementation-plan`.
3. Add metadata: status, owner, date/time, repository commit SHA, supersedes/superseded-by, scope, and evidence links.
4. Update only the canonical status/plan after each gate; keep dated specialist audits immutable.
5. Do not delete or edit the eight original inputs as part of this task. Maintain the ninth appendix only to keep canonical verification metadata accurate.

## J. Approved prerequisite decisions and remaining questions

### J.1 Approved minimum decisions — Aug. 23, 2026

1. **Execution authorization — Stage 0 planning only.** Produce an implementation-ready documentation brief, then stop. This decision does not authorize executing baseline checks, launching the app, using hardware, running privileged commands, or changing code.
2. **Privilege policy — no-root plus signed helper.** Use no-root routes wherever upstream capability and GUI verification prove them safe. Isolate only unavoidable privileged operations in a signed, typed, narrowly authorized helper; never execute user-owned Python/package code as root.
3. **Required no-root operations — supported one-shot operations.** Discovery, preparation, and supported one-shot GUI location actions must use no-root routes where proven. Persistent or high-frequency operations may use the signed helper only when capability analysis demonstrates privilege is unavoidable.
4. **Dependency policy — managed locked runtime.** Release behavior must use a controlled Python/pymobiledevice3 runtime with exact versions, hashes, a transitive lock, compatibility tests, and an explicit upgrade process. The observed Python 3.13.15/pymobiledevice3 10.7.4 pair is evidence, not automatically the selected release contract.
5. **Transport/failover policy — healthy USB preferred.** Prefer USB only while endpoint/service health probes pass; fail to Wi-Fi on measured instability; return to USB only after a defined stability window; preserve simulation state across every route change.
6. **Failover latency — 1–3 seconds.** Acceptance must measure interruption from loss of the active route to validated publication of the replacement route and require no more than three seconds, with a one-second target where the environment supports it.
7. **Safe-mode/cooldown policy — enforced per-mode limits.** Define and enforce mode-specific distance, speed, and frequency limits; confirmations for exceptional jumps; bounded retries; visible cooldown timers; and an explicit safe reset path. Exact numeric limits remain a Stage 7 product specification task.
8. **Persistent bridge concurrency — strict serialization initially.** Permit one in-flight request, queue later requests deterministically, and guarantee exact-once completion. Multiplexing requires measured throughput evidence and a separately approved protocol change.
9. **Release hardware matrix — declared support matrix.** Certification must cover every advertised macOS/iOS range and CPU architecture using representative devices, applicable USB-C/Lightning paths, USB and Wi-Fi, relaunch/reconnect, and one- and two-device scenarios. Stage 0 must turn this policy into a concrete inventory and coverage table.
10. **Evidence governance — Stage-0 tamper-evident private repository waiver.** For Stage 0 only, store redacted packet artifacts in private repository `abyssbugg/PathChanger-Evidence` under `stage-0/<UTC-run-id>/packet-0.N/`, with SHA-256 manifests, protected linear history, force-push/deletion disabled, minimum 365-day retention policy, fresh-checkout verification, automated review artifacts, and identity-bound acceptance records. This is off-machine durable and tamper-evident, not immutable against the repository owner/GitHub administrators; it does not satisfy later release/security gates. Local staging is `/Users/datamatics/.rovodev/pathchanger-stage0/<run-id>/`, with checkout at `/Users/datamatics/.rovodev/evidence-checkouts/PathChanger-Evidence`.
11. **Role assignments — documented single-maintainer Stage-0 waiver.** Shigeo (`datamatics`; GitHub `abyssbugg`) is Stage 0 operator, accountable engineering owner, product owner, and time-separated Stage 0 security-waiver approver. Oz is the delegated automated technical reviewer whose archived report verifies completeness and hashes but does not constitute independent human accountability. Final Stage 0 self-approval is valid only in a later review session using the brief checklist verbatim, after a fresh-checkout hash verification, and through an acceptance commit GitHub reports as `verified: true`. This waiver expires after Stage 0 and cannot approve Stage 1 or release/security gates.

### J.2 Remaining non-minimum questions

These do not block writing the Stage 0 brief, but each blocks the named later-stage acceptance criterion:

1. **Same-network definition (blocks Stage 6):** determine whether network suitability is interface/subnet evidence, verified service reachability, endpoint capability, or a documented combination.
2. **Jump specification (blocks Stage 7):** define the intended user-visible and device-side Jump behavior before implementation or certification.
3. **Dormant UI disposition (blocks Stage 8 cleanup):** remove, feature-flag, or restore parity for Sidebar/DeviceList/Inspector/Floating controls.
4. **Documentation migration permission (blocks archival banners):** decide whether the eight immutable original inputs may receive archival banners/links in a later documentation-only migration.

---

## Reconciliation conclusion

The minimum policy decisions required to write Stage 0 planning are now approved, but the project remains insufficiently verified to claim a working or releasable tunnel product. The authoritative next artifact is `Stage-0-Verification-and-Acceptance-Brief-Aug-23-2026.md`; after that brief is written, work must stop for explicit authorization before any verification execution or code change (`Final-Coverage-Ledger`, **Authoritative next action**; `Final-Report-Completion-Aug-23-2026.md`, **Completion status**, **Overall confidence**).

