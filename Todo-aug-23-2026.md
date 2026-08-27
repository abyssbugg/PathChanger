# TODO — Aug 23, 2026

## Status
Not moving forward. Despite the cleanup and the new launch, we still have
**tunnel instability** and **incorrect device phasing/detection**. This file is
the ordered recovery plan.

## Ground Rules (apply to every task below)

1. **Use the Sequential Thinking MCP** for every problem in this file. Break
   each issue into explicit steps — root cause, affected files, dependency
   order, fix, verification — before touching code. No jumping straight to a
   patch.
2. **Understand before changing.** The first deliverable is comprehension of the
   existing system, not a fix. Read the code path end to end.
3. **The GUI is the contract.** Every fix must work through the app GUI. A fix
   that only works via CLI/script is not a fix. The GUI is the primary surface;
   underlying functions exist to serve and extend it.
4. **No bug-on-bug patching.** This project has accumulated layered workarounds
   with no real root-cause fixes. Every change must identify and address the
   actual cause. If a workaround is unavoidable, label it explicitly as
   temporary with a reason.
5. **One phase at a time.** Do not start a phase until the previous phase is
   verified working.

---

## Phase 0 — Understand the system first

- [x] Map the GUI: every screen, control, and state it can be in.
- [x] For each GUI control, trace the full call path down to the underlying
      function/process. Record file + function per hop.
- [x] Document the current tunnel lifecycle: start → connect → active →
      degrade → reconnect → stop.
- [x] Document the current device discovery lifecycle, including exactly where
      device identity is derived from.
- [x] Identify where GUI state and actual backend/tunnel state can diverge —
      this is the confirmed source of the "Ready vs. Start Tunnel" bug.
- [x] Output: a written architecture note. **No code changes in this phase.**

---

## Phase 1 — Fix the tunnel

### Confirmed bug
The tunnel service gets stuck displaying **"Wi-Fi Ready"** or **"USB Ready"**
instead of showing **"Start Tunnel"**. A transport-readiness state is being
rendered in place of the action control, so the user has no way to actually
start the tunnel.

### Root cause direction
Readiness (is a transport available?) and tunnel state (is the tunnel running?)
are being conflated into one value driving one UI element. These are two
separate concerns and need to be separated.

### Tasks
- [ ] Reproduce the stuck-state reliably. Document exact steps.
- [x] Root-cause it — separate **transport readiness** from **tunnel state**.
- [x] Define the two independent state machines:
      - **Transport readiness:** `none` / `usb-ready` / `wifi-ready` /
        `both-ready`
      - **Tunnel state:** `idle` / `starting` / `active` / `degraded` /
        `reconnecting` / `failed` / `stopping`
- [ ] The action button reflects **tunnel state only**
      (Start Tunnel / Starting… / Stop Tunnel).
- [ ] Readiness is displayed as a **separate status indicator**, never as the
      button label.
- [ ] Confirm tunnel state is a single source of truth, not duplicated between
      GUI and backend.
- [ ] Ensure tunnel start/stop is idempotent — repeated presses must not create
      orphaned processes or duplicate tunnels.
- [ ] Ensure teardown is clean: no leaked ports, sockets, or child processes.
- [ ] No optimistic states — never show `active` until the tunnel is genuinely up.

### New UI requirement — transport status indicator
Add a dedicated readiness/status area, separate from the action button, showing:

- [ ] **USB Ready** — USB transport available
- [ ] **Wi-Fi Ready** — Wi-Fi transport available
- [ ] **Both Ready** — both available, with which one is currently active
- [ ] **Active transport** — which transport the live tunnel is actually using
- [ ] **Same-network indicator** — whether PC and phone are on the same Wi-Fi
- [ ] Explicit distinction between these cases:
      - USB connected **and** on the same Wi-Fi network → Wi-Fi fallback
        available
      - USB connected but on a **different** network (or no shared Wi-Fi) →
        **no** Wi-Fi fallback available; warn the user
      - Wi-Fi only, same network → normal Wi-Fi mode
- [ ] Fallback availability must be visible **before** it's needed, not
      discovered at failure time.

### Verification
- [ ] **In a fresh dev session, verify the tunnel button behavior end to end**
      and confirm the fix holds — start, stop, restart, and rapid repeated
      presses.
- [ ] Button never displays a readiness string.
- [ ] Readiness indicator updates live as USB is plugged/unplugged and as
      Wi-Fi changes.
- [ ] Same-network vs. different-network states both display correctly.

---

## Phase 2 — Fix device discovery

### Confirmed bugs
1. **Wrong device name** — the app phases/reports an incorrect device name.
2. **Device duplication** — one physical device is exposed as **4 separate
   devices**.

### Root cause direction
Device identity is being derived from something non-unique or transport-scoped
(interface, socket, address, handle, per-transport enumeration) rather than a
single stable hardware identifier. Each enumeration path is creating its own
entry for the same phone.

### Tasks
- [ ] Find every code path that enumerates or registers a device. There are
      likely 4 — map each one and why it fires.
- [ ] Identify the current source of the device name and why it resolves wrong.
- [ ] Establish a **single stable device identity key** (persistent hardware
      identifier) used everywhere.
- [ ] Deduplicate: all enumeration paths must resolve to one canonical device
      entry keyed on that identity.
- [ ] Correct device name resolution — read from the authoritative source, with
      a defined fallback that is clearly marked as unknown rather than guessed.
- [ ] Same physical device over USB **and** Wi-Fi must remain **one** entry,
      annotated with which transports it is reachable on.
- [ ] Handle connect / disconnect / reconnect without stale or ghost entries.
- [ ] GUI device list reflects live truth with no manual refresh required.
- [ ] Never fabricate or guess a device name to fill a gap.

### Verification
- [ ] One phone connected → exactly **one** entry in the GUI. Not 4.
- [ ] Device name displayed matches the real device.
- [ ] Plug/unplug USB repeatedly → count stays at one, no ghosts.
- [ ] Join/leave Wi-Fi → count stays at one, no ghosts.
- [ ] Same device reachable over both transports → one entry, both transports
      shown.
- [ ] Two different devices connected → exactly two distinct entries, correctly
      named.

---

## Phase 3 — Tunnel over USB mode and Wi-Fi mode

Both transports must work **independently** and **simultaneously**.

- [ ] USB transport tunnel works standalone.
- [ ] Wi-Fi transport tunnel works standalone.
- [ ] Both can be active at the same time without interfering.

### Wi-Fi mode requirement (confirmed correct behavior)
Wi-Fi mode requires PC and phone on the **same Wi-Fi network**. This is correct
and expected for a location changer — keep it. Surface it clearly when the
requirement isn't met rather than failing silently.

### Transport priority (confirmed)
- [ ] **USB is the priority transport** when available.
- [ ] If USB is present but **unstable**, prefer Wi-Fi.
- [ ] Define "unstable" concretely and document it — e.g. N disconnects within
      a time window, sustained latency/error threshold, or repeated
      reconnect attempts. Do not leave this as a vibe check.
- [ ] Once demoted for instability, USB should not be re-promoted immediately —
      require a stability window to prevent flapping.

### Failover requirements

**USB → Wi-Fi fallback**
- [ ] If USB is unplugged mid-session while location spoofing is active, fall
      back to Wi-Fi **quickly and automatically**.
- [ ] Precondition: PC and phone are on the same Wi-Fi network.
- [ ] Primary trigger case: accidental/forgetful unplug during an active USB
      spoofing session.
- [ ] The active spoofing session must survive the transition — current mode,
      coordinates, route progress, and cooldown timers all preserved.
- [ ] If USB is unplugged and **no shared Wi-Fi exists**, fail honestly and
      visibly. Do not appear active.

**Wi-Fi → recovery**
- [ ] If Wi-Fi drops, fails, or degrades, handle gracefully — reconnect
      automatically, or fall back to USB if USB is available and stable.
- [ ] No silent failure. Session must never appear active when it isn't.

### Failover rules
- [ ] Document the full fallback decision logic (conditions, priority,
      thresholds, timeouts).
- [ ] Define retry/backoff — no infinite tight-loop reconnects.
- [ ] GUI must clearly show current transport and that a fallback occurred.
- [ ] Failover fast enough to avoid a visible break in spoofing.
- [ ] No flapping when both transports are marginal.

### Verification
- [ ] Unplug USB mid-spoof on shared Wi-Fi → falls back, session continues.
- [ ] Unplug USB with **no** shared Wi-Fi → clean, honest failure in GUI.
- [ ] Kill Wi-Fi mid-spoof → recovers or fails honestly.
- [ ] Flaky USB (repeated brief drops) → demotes to Wi-Fi, does not flap.
- [ ] Repeat cycles → no leaked processes, no duplicate tunnels.
- [ ] Run failover test **while each of the 5 modes is active** — failover must
      not corrupt mode state.

---

## Phase 4 — All 5 modes

The five modes:

1. **Teleport**
2. **Jump Teleport**
3. **Two-Spot Mode**
4. **Multi-Spot Mode**
5. **Joystick**

**Design intent (confirmed):** these are **five independent features**, not
variants of one another. Each must work differently and stand on its own. Do
not refactor them into a shared behavior with flags, and do not assume one
mode's logic is correct for another.

Each must work fully **through the GUI**.

### Master matrix

| # | Mode | Core function | Safe mode | Cooldown reminder | Extra functions | GUI verified | Survives failover |
|---|------|---------------|-----------|-------------------|-----------------|--------------|-------------------|
| 1 | Teleport | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| 2 | Jump Teleport | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| 3 | Two-Spot Mode | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| 4 | Multi-Spot Mode | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| 5 | Joystick | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |

### Shared requirements (all 5 modes)
- [ ] Mode works fully on its own, independent of the other four.
- [ ] Switching modes is clean — no leaked state, residual timers, or stale
      coordinates from the previous mode.
- [ ] Each mode has its **own** safe mode and cooldown implementation
      (see 4.0 below).
- [ ] Every **extra/secondary function** in the mode is verified working — not
      just the primary action.
- [ ] Mode state is single-source-of-truth, shared with the GUI.
- [ ] Mode survives a transport failover (Phase 3) without corruption.
- [ ] Confirm no mode is silently reusing another mode's code path.

---

### 4.0 Research task — Safe Mode & Cooldown Reminder

**This is a prerequisite for the rest of Phase 4. Do not implement before
completing it.**

Safe mode and cooldown reminders are standard in location-changer apps
generally, not unique to this project — but their actual purpose and correct
logic are currently unknown to us.

- [ ] Research what **safe mode** does in location-changer apps: what it
      prevents, what it limits, and why users rely on it.
- [ ] Research what a **cooldown reminder** is for: what it tracks (distance,
      time, or both), how the interval is typically derived, and what problem
      it protects the user from.
- [ ] Document the standard/expected behavior of each.
- [ ] Audit what our app currently implements versus that standard.
- [ ] Determine whether ours are enabled **automatically by the system** or
      were **manually enabled at some point** — establish the actual current
      behavior, then decide the intended default.
- [ ] Verify whether either is a **label-only toggle** that enforces nothing.

**Confirmed requirement:** safe mode and cooldown logic **must differ per
mode** — all five need their own logic. Do not share one implementation across
all five.

- [ ] Define correct safe-mode logic per mode (5 definitions).
- [ ] Define correct cooldown logic per mode (5 definitions).
- [ ] Explicitly identify where a **single shared implementation is currently
      being incorrectly applied across modes** — especially discrete-jump modes
      (1–4) versus continuous movement (5), which cannot share the same math.

---

### 4.1 Teleport
- [ ] Single-target teleport lands on the exact selected coordinate.
- [ ] Repeated teleports in sequence work without drift or stale position.
- [ ] Safe mode: enforce the Teleport-specific guardrail defined in 4.0.
- [ ] Cooldown reminder based on the real distance of the jump.
- [ ] GUI position readout matches actual spoofed position.

### 4.2 Jump Teleport
- [ ] Document what this mode actually does today, from the code — there is no
      predefined intended difference from Teleport, so define it from real
      behavior and confirm it is correct and distinct.
- [ ] Verify the full jump sequence completes, including any multi-leg or
      return behavior.
- [ ] Interrupting mid-sequence leaves a clean, known state — never a
      half-applied position.
- [ ] Safe mode enforced on **each leg**, not just the first.
- [ ] Cooldown accounts for total distance across all legs.

### 4.3 Two-Spot Mode
- [ ] Both spots can be set, cleared, and re-set through the GUI.
- [ ] Alternation between the two spots is correct and repeatable.
- [ ] Timing/interval control works as configured.
- [ ] Start / pause / resume / stop all behave correctly.
- [ ] Safe mode enforced on every alternation, not only the first.
- [ ] Cooldown tracks cumulative distance across alternations.
- [ ] Spots persist across a transport failover.

### 4.4 Multi-Spot Mode
- [ ] Adding, reordering, editing, deleting spots all work in the GUI.
- [ ] Route executes in the correct order.
- [ ] Loop / repeat / one-shot behavior works as configured.
- [ ] Pause and resume returns to the correct point — not a restart.
- [ ] Route progress preserved across a transport failover.
- [ ] Safe mode enforced at every hop.
- [ ] Cooldown tracks cumulative route distance.
- [ ] Empty or single-spot route behavior is defined, not a crash.

### 4.5 Joystick
- [ ] Continuous movement is smooth — no stutter or position snap-back.
- [ ] Direction input maps correctly to actual movement.
- [ ] Speed control works across its full range.
- [ ] Release/stop halts movement immediately with no drift.
- [ ] Sustained-use stability — no memory/handle growth or degradation.
- [ ] Safe mode enforces speed limiting per the 4.0 definition.
- [ ] Cooldown logic must be **distinct** from the teleport-class modes —
      continuous movement cannot reuse discrete-jump distance math.
- [ ] Joystick latency over Wi-Fi is acceptable; document the threshold.
- [ ] Failover mid-movement causes no position jump and does not leave movement
      stuck on.

### Verification
- [ ] Run each of the 5 modes in isolation, start to finish.
- [ ] Run each mode's safe mode and confirm the enforced behavior.
- [ ] Trigger each cooldown reminder and confirm timing and message.
- [ ] Exercise every extra function in every mode.
- [ ] Switch across all 5 modes in sequence — no residual state.
- [ ] Repeat the full pass over USB, then Wi-Fi, then with mid-session failover.

---

## Phase 5 — Full wiring audit

The project has accumulated bugs layered on bugs without real fixes. This phase
confirms everything is genuinely connected.

- [ ] Every GUI control traces to a real, working implementation. No dead
      buttons, no-op handlers, or label-only toggles.
- [ ] Every setting/toggle actually reaches and affects underlying behavior.
- [ ] No orphaned, duplicated, or superseded code paths still being invoked.
- [ ] No swallowed errors — failures must surface, not silently return empty or
      default values.
- [ ] State is single-source-of-truth; no divergent copies between GUI and
      backend.
- [ ] Confirm no mode is silently sharing another mode's implementation.
- [ ] Confirm the 4 duplicate-device enumeration paths from Phase 2 are fully
      consolidated, not just masked at the UI layer.
- [ ] Remove or explicitly document every temporary workaround found.

### Output
- [ ] Wiring report: GUI control → handler → implementation → verified status,
      with file + line for each.
- [ ] List of every previously-patched-over bug and its actual root cause.

---

## Exit criteria

Do not consider this done until **all** of the following hold:

- Tunnel button shows the correct action, never a readiness label.
- Transport readiness UI accurately shows USB/Wi-Fi availability, active
  transport, same-network status, and whether fallback is available.
- One physical device appears as exactly **one** correctly-named entry.
- Device discovery is accurate and live, with no ghost or duplicate entries.
- USB and Wi-Fi tunnels work independently and concurrently.
- USB is prioritized; Wi-Fi takes over when USB is unstable, without flapping.
- USB → Wi-Fi fallback works on accidental unplug, session preserved.
- Wi-Fi drop/failure handled gracefully.
- Safe mode and cooldown reminder are researched, understood, documented, and
  implemented with **per-mode** logic.
- Teleport, Jump Teleport, Two-Spot, Multi-Spot, and Joystick each work
  independently, including safe mode, cooldown, and all extra functions.
- Every mode survives a mid-session transport failover intact.
- Everything above verified **through the GUI**.
- Wiring audit clean — no dead paths, no undocumented workarounds.
- Verified in a **fresh dev session**, not a warm one carrying prior state.

---

## Open questions

1. **Failover speed target (unresolved).** You weren't sure how to answer this,
   which is fine — it's answerable empirically instead. Task: measure how long
   USB → Wi-Fi failover currently takes, then determine the maximum gap the
   spoofing session can tolerate before the position visibly breaks. Set the
   target from that measurement rather than guessing up front.
2. **"Unstable USB" definition** — needs a concrete, measurable threshold
   (see Phase 3). Propose one based on observed behavior.
3. **Jump Teleport definition** — to be derived from current code behavior in
   4.2, since there is no predefined intent.

   ======================

   The one thing I'd flag as the real unlock: the 4-duplicate-device bug and the "Ready vs. Start Tunnel" bug are probably the same root cause — multiple enumeration paths each publishing their own state, with the UI reading whichever wrote last. Worth checking that hypothesis first in Phase 0, since fixing it once may clear both.