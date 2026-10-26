# Product Requirements Ledger — 2026-10-25

Status vocabulary per `CLAUDE.md` §2. Every row cites its evidence. This ledger covers
`PRODUCT_REQUIREMENTS.md` sections against the `feature/five-mode-reliability` branch
(including the merged `fix/wifi-connection-truth` lane) at the time of writing.

## §1 Objective and priority

| Requirement | Status | Evidence |
|---|---|---|
| Spoof persists until explicit Clear / unavoidable loss honestly reported | **PASS (device-free)** / **BLOCKED (hardware)** | Architecture: held-session + coordinator hold/loss semantics; unit suites `ModePersistenceTests`, `LocationSessionRecoveryTests`; physical persistence windows not yet observed on hardware (Task 17 owner-gated). |
| Priority order honored (reliability → … → GUI consistency) | PASS (device-free) | Connection-loss classification (`e5aaa80`), endpoint health (`ca57da6`), truth-first GUI chips; full suite 1069 tests green (behavior). |

## §2 Scope

| Requirement | Status | Evidence |
|---|---|---|
| Exactly five user modes | PASS | `LocationMode` five-case enum; `ModeTransportMatrixTests` 10-case table; GUI mode pill. |
| Canonical dependency name pymobiledevice3 | PASS | Source/tests audited; no "PyMobile3" identifiers. |

## §3 Five mode contracts

| Mode | Status | Evidence |
|---|---|---|
| Teleport | PASS (device-free) / **BLOCKED (hardware)** | `ModePersistenceTests` teleport lifecycle; receipt-driven apply; device-free green. Physical hold-window unobserved. |
| Jump Teleport | PASS (device-free) / BLOCKED (hardware) | Index advances on acknowledged receipt only; reconnect deliberately reapplies as teleport to protect the index (`0088255`). |
| Two-Spot | PASS (device-free) / BLOCKED (hardware) | Planner + lifecycle tests; completion holds destination. |
| Multi-Spot | PASS (device-free) / BLOCKED (hardware) | Route acknowledge/hold tests; matrix suite. |
| Joystick | PASS (device-free) / BLOCKED (hardware) | Engage/disengage hold tests; latest-wins queue. |

## §4 State model and GUI truth

| Requirement | Status | Evidence |
|---|---|---|
| Three separate state dimensions | PASS | Connection/Application/Movement chips; `LocationSessionState`. |
| Never report active without acknowledgement | PASS (device-free) | Coordinator accept/reject gates; connection-class rejections → uncertain (`e5aaa80`); 1055+ suite green. |
| Lost session reported honestly | PASS (device-free) | Endpoint probing + `healthCheckFailed`; immortal-monitor defect fixed (`ca57da6`). |

## §5 Persistence, hold, stop, clear

| Requirement | Status | Evidence |
|---|---|---|
| No implicit clear on stop/pause/completion/mode-change | PASS (device-free) | Stop-movement-holds tests; clear requires explicit action + confirmation dialog. |
| Explicit reset boundary | PASS (device-free) | Clear path separate; wired warnings. |

## §6 Safe Mode / cooldown

| Requirement | Status | Evidence |
|---|---|---|
| Removed from correctness | PASS | Branch commit a20b40c removed semantics; coordinator has no cooldown gate. |

## §7 USB and Wi-Fi transport

| Requirement | Status | Evidence |
|---|---|---|
| Truthful readiness per transport | PASS (device-free) | Direct-transport readiness without tunnel; cadence-bounded visibility (`cead924`). |
| Receipts carry identity/transport/generation | PASS | `LocationInjectionReceipt` + router validation suites. |
| Reconnect-and-reapply | PASS (device-free) | Recovery + one-tap reconnect (`0088255`); physical drop/restore unobserved (Task 17). |

## §8 pymobiledevice3 adapter contract

| Requirement | Status | Evidence |
|---|---|---|
| Single adapter boundary | PASS | `LocationInjecting` protocol; GUI never builds argv. |
| Protocol parity Swift/Python | PASS (device-free) | Request-ID/session-generation on both sides; parity tests. |
| Rate limiting never reports queued as applied | PASS | `.queued` outcome ≠ active; queue tests. |

## §10 Required test matrix

| Requirement | Status | Evidence |
|---|---|---|
| Deterministic unit + fake-adapter layers | PASS | 1069-test suite; matrix + interruption suites. |
| FlowDeck build/test execution | PASS | Both worktrees; ReleaseTesting + Debug. |
| FlowDeck GUI verification | **BLOCKED (environment)** | `flowdeck ui mac` recorder blocked by Accessibility/Screen-Recording permissions in agent sessions; launch + process-stable verified device-free. |
| Physical 5×2 matrix (§10 checkpoints, failure scenarios) | **NOT RUN — owner-gated (Task 17)** | Requires owner's physical actions; explicitly deferred to the owner's own test session per owner instruction 2026-10-25. |

## §11 Product acceptance criteria

Overall: **NOT complete** — pending the hardware matrix and final merge gates below.

## Deviations authorized by owner instruction (2026-10-25)

- Final merge to `main` authorized by owner order ("push everything to main") while Task 17
  remains open. Recorded here so the history is honest: hardware acceptance is outstanding,
  not waived silently.

## Known open defects (registered, not hidden)

- Test-host fd ceiling EMFILE under full-suite ordering — interim raised-limit invocation;
  deep-fix item in AGENTS.md (partly pre-existing; unbounded component fixed).
- `flowdeck ui mac` permission gap blocks scripted GUI verification in agent sessions.
