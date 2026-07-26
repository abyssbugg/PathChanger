# ADR 004: Security Remediation and Privilege Boundary

## Status
Accepted (2026-07)

## Context
A full security and code-integrity audit of PathChanger (macOS/Swift app that
drives a paired iOS device through Python `pymobiledevice3` tooling) produced 41
findings: 0 Critical, 4 High, 14 Medium, plus Low/Info. The dominant risk is
**local privilege escalation to root**: the app runs a Python interpreter /
bundle script via `do shell script … with administrator privileges`, and the
provenance policy accepts current-user-owned code, which same-UID malware can
replace (TOCTOU). Secondary risks were software-supply-chain integrity, release
integrity, and repository governance. The repo is private and no committed
secret was found in history.

## Decision
Remediate in sequenced waves, each landing as its own reviewed change with
evidence, rather than a single large rewrite:

- **Wave 0 — containment & governance.** Hash-enforced Python lock
  (`requirements-pathchanger.lock`, `pip install --require-hashes`) verified in
  CI; build/install workspace moved to a unique `mktemp` dir with post-copy
  signature re-verification (fixes a bundle-substitution TOCTOU); fail-closed
  coverage/validation scripts; `main` branch protection + Dependabot.
- **Wave 1 — privileged-path hardening (interim).** Reject privileged targets
  reachable through a group/other-writable ancestor and prefer a root-owned
  pinned interpreter. This reduces, but does not eliminate, same-UID replacement.
- **Wave 2 — hardening.** Remove the dormant, unauthenticated MultipeerConnectivity
  companion host and its entitlements; GPX input caps + coordinate-bounds
  validation + context-correct parsing; bounded concurrent subprocess capture
  with SIGTERM→SIGKILL escalation; CI secret scanning (gitleaks) + entitlement
  policy gate + pinned SwiftLint.
- **Wave 3 — cleanup.** Remove the build-excluded duplicate `Info.plist`,
  supersede stale ADRs, document the manual icon tool, add CODEOWNERS.

## Durable privilege boundary (planned)
The durable fix for the root-execution LPE is a **signed, root-owned privileged
helper** registered via `SMAppService` and reached over XPC, exposing only a
narrow typed API (`startTunnel(mode, udid)`, `pairWiFi(timeout, name)`,
`stopTunnel`). The helper resolves its own root-owned interpreter/entrypoint and
verifies the calling app's code signature (audit token) before acting, closing
the check-to-use TOCTOU window. This work is **deferred** because `SMAppService`
daemons cannot be registered, run, or tested without Developer ID signing, which
this ad-hoc-signed project does not yet have. It must not be enabled until
Developer ID signing + notarization are in place.

## Consequences
- Positive: cross-UID replacement paths closed; reproducible, tamper-evident
  dependency installs; smaller attack surface; enforced repo governance; CI now
  gates secrets and entitlements.
- Negative / residual: same-UID replacement of user-owned interpreter code
  remains possible until the signed helper ships; true cancellation of the
  synchronous AppleScript privileged path also awaits the helper; release
  artifacts remain ad-hoc signed pending Developer ID.

## Follow-ups
1. Obtain Developer ID; sign + notarize releases; implement the SMAppService/XPC
   helper and route privileged tunnel/pairing through it. The interim posture this
   forces on distribution — ad-hoc signing, no notarization, no auto-update — is
   recorded separately in [ADR 005](005-interim-adhoc-distribution.md), which shares
   this prerequisite and lists the reversal steps.
2. App Sandbox feasibility spike for the UI process, keeping device/Python work
   behind the privileged helper.
3. Add a second trusted reviewer, then enable "require Code Owner review".
