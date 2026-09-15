# PathChanger Deployment and Acceptance

## Current status

**Not release-ready.** Automated tests are necessary but do not replace physical USB/Wi-Fi acceptance, visual review, signing, notarization, or owner sign-off. Historical performance numbers and unchecked templates are not release evidence.

## Safety rules

- Build and test the feature branch before integration.
- Keep the protected `main` checkout available as rollback until acceptance completes.
- Never run the entire hardware-gated test class against an attached phone.
- Never start an elevated tunnel without explicit owner approval.
- Never report Apply or Clear success without provider acknowledgement.
- Never include raw device identifiers, private endpoints, or credentials in evidence.
- Do not publish a GitHub release during local acceptance.

## Artifact construction

`build-app-bundle.sh` constructs and retains an app bundle under `APP_BUNDLE_BUILD_ROOT`, defaulting to `build`. It does not install, launch, or delete global applications.

```bash
APP_BUNDLE_BUILD_ROOT="$PWD/build" ./build-app-bundle.sh
```

Installation is separate and explicit:

```bash
./install.sh
```

Agent-driven Apple builds, tests, launches, logs, and UI automation must use FlowDeck.
## Required gates

1. Confirm feature and remote commit identities match.
2. Resolve the managed Python dependency snapshot and verify required capabilities.
3. Run focused tests for changed components.
4. Run the complete `ReleaseTesting` suite with zero failures.
5. Build one fresh Release bundle from that exact commit.
6. Complete visual review in light/dark appearance and accessibility inspection.
7. Complete ten core physical cases: five user modes over USB and Wi-Fi.
8. Verify interruption, disconnect, helper death, preserve-and-quit, relaunch adoption, and explicit Clear.
9. Confirm no app, helper, location, or tunnel process remains after teardown.
10. Perform code signing, notarization, and owner sign-off before distribution.

## Physical case evidence

For every case record the selected device alias, observed physical transport, actual DVT channel, requested coordinate, acknowledged coordinate, generation, request suffix, hold interval, independent phone observation, and final teardown state. Redact device IDs and endpoint addresses.

Stop preserves the last acknowledged coordinate. Explicit Clear is the only normal destructive reset. A timeout is uncertain until reconciliation proves the durable provider result.

## Supporting documents

- `TUNNEL_MODES.md` — transport/channel selection and safety
- `02_CODE_SIGNING_PROCEDURES.md` — signing and notarization
- `03_SECURITY_VERIFICATION_CHECKLIST.md` — security review
- `04_PERFORMANCE_BASELINE.md` — template for fresh measurements
- `05_UAT_SIGN_OFF.md` — owner acceptance record

A checked box, old benchmark, or UI-only exercise is not proof of hardware correctness. Release readiness exists only after all current gates have dated evidence tied to the exact release commit.