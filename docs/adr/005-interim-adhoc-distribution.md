# ADR 005: Interim Ad-Hoc Distribution

## Status
Accepted (2026-07)

## Context
ADR 004 established that the durable fix for the root-execution LPE is a signed,
root-owned `SMAppService` helper, and deferred it because `SMAppService` daemons
cannot be registered, run, or tested without Developer ID signing. It recorded the
same constraint for release artifacts: "release artifacts remain ad-hoc signed
pending Developer ID."

That constraint has a second consequence ADR 004 did not record. The UI redesign
and security-remediation branch removed the entire signed-distribution path that
existed on `main`. The removal is *enforced* — `scripts/validate-release-config.sh`
fails the build if Sparkle wiring or the legacy deployment documents reappear — but
it was never *explained*; no ADR or changelog entry recorded why. What was removed:

- the Sparkle dependency in `Package.swift` and `PathChanger/Core/UpdaterController.swift`
- the Developer ID → notarize → staple → Gatekeeper-assess → Sparkle-sign steps in
  `.github/workflows/release-validation.yml`
- `DEPLOYMENT/02_CODE_SIGNING_PROCEDURES.md` through `05_UAT_SIGN_OFF.md`

The two branches then each carried a different `release-validation.yml`. The
resulting add/add conflict left PR #2 in a `CONFLICTING` state, which prevented
GitHub from constructing a merge ref, which in turn meant **none of the four
required status checks ever ran on the security-remediation work** — 40 commits
merged against no build, test, lint, or secret-scan evidence.

## Decision
Adopt ad-hoc-signed, GitHub-direct distribution as the explicit interim posture,
and record it rather than leaving it implicit in a deleted file.

- **Release artifacts** are a zip plus a SHA-256 manifest, published as GitHub
  release assets. `DEPLOYMENT/README.md` is the authoritative process.
- **`release-validation.yml`** validates that artifact: build, ad-hoc bundle,
  bundle hygiene, xattr policy, zip, checksum generation and verification. The
  Developer-ID steps are removed rather than kept and skipped, because the
  required secrets (`MACOS_CERTIFICATE_*`, `APPLE_*`, `SPARKLE_PRIVATE_KEY`) do
  not exist and their absence would fail the workflow closed on every run.
- **`com.apple.provenance` is deliberately absent** from the workflow's
  forbidden-xattr check. This mirrors `build-app-bundle.sh`, which probes whether
  the host attaches the attribute unremovably and tolerates it with a warning when
  it does — the behaviour of the GitHub `macos-14` runners. Re-adding it to the
  hard-fail list would redden the gate on every run.
- **No auto-update channel.** Sparkle and `UpdaterController` stay removed until
  updates can be signed; an unsigned update channel is a worse risk than no
  update channel.
- **`DEPLOYMENT/02` through `05` stay deleted.** Their absence is not incidental:
  `scripts/validate-release-config.sh` asserts it by name and fails the *Build &
  Test* required check if any reappears ("Contradictory legacy deployment document
  must be removed"), with a companion check that `DEPLOYMENT/README.md` does not
  link them. `DEPLOYMENT/README.md` states that where documentation and workflow
  behaviour diverge, the workflow and validation script are authoritative.

  That enforcement is correct: a repository that simultaneously ships a
  notarization playbook and a validation script forbidding notarization is worse
  than one that ships neither. What was missing was the *reason*, which existed
  only as a shell assertion. This ADR is that reason.

  The content is not lost. Retrieve it when signing lands:

  ```bash
  git show 75321f5:DEPLOYMENT/02_CODE_SIGNING_PROCEDURES.md
  git show 75321f5:DEPLOYMENT/03_SECURITY_VERIFICATION_CHECKLIST.md
  git show 75321f5:DEPLOYMENT/04_PERFORMANCE_BASELINE.md
  git show 75321f5:DEPLOYMENT/05_UAT_SIGN_OFF.md
  ```

  Two cautions for whoever restores them. `04` and `05` are December 2025 records
  whose "macOS 11.0+" and "Universal Binary" claims already contradict the current
  `.macOS(.v14)` target, and `05` is a completed v1.0.0 RC1 sign-off rather than a
  blank template. `03` is the one whose file and test-suite references remain
  accurate and is the strongest candidate to reinstate — but reinstating any of
  them requires updating `validate-release-config.sh` in the same change set.

## Consequences
- Positive: the release pipeline is honest — every step it runs can actually pass,
  and the posture is written down instead of being inferable only from a deleted
  file. PR #2 becomes mergeable, so the required checks can run at all.
- Negative / residual:
  - End users get no Gatekeeper assurance and must right-click-open the app.
  - Release integrity rests entirely on the SHA-256 manifest and the trust of the
    GitHub release page. There is no cryptographic binding to this project's identity.
  - There is no update channel; users must return to the release page.
  - The ADR 004 privileged helper stays deferred, so the same-UID interpreter
    replacement risk documented there remains open.

## Reversal criteria
A single prerequisite — obtaining a Developer ID — unblocks this ADR and ADR 004's
deferred helper together. On obtaining it:

1. Restore Sparkle + `UpdaterController`, and the notarize/staple/Gatekeeper and
   Sparkle-signature steps in `release-validation.yml`, following
   `DEPLOYMENT/02_CODE_SIGNING_PROCEDURES.md`.
2. Implement the `SMAppService`/XPC privileged helper per ADR 004 follow-up #1 and
   route privileged tunnel/pairing through it.
3. Flip `02_CODE_SIGNING_PROCEDURES.md` from DEFERRED to ACTIVE and supersede this ADR.

Until then, do not add code paths that require Developer ID, notarization, or
`SMAppService` — they cannot be built or tested in this project's CI.

## Related
- [ADR 004](004-security-remediation-and-privilege-boundary.md) — security remediation
  and privilege boundary; shares the Developer ID prerequisite.
- `DEPLOYMENT/README.md` — the authoritative release process.
