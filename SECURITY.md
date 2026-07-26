# Security Policy

PathChanger is a macOS application that drives a paired iOS device through the
Python `pymobiledevice3` tooling. Parts of that work run with administrator
privileges. Please read the scope and known-accepted risk sections before
reporting — they will save you time on issues we already track.

## Reporting a vulnerability

Report privately. **Do not open a public issue for a security problem.**

- Preferred: GitHub **private vulnerability reporting** on this repository
  (Security → Report a vulnerability).
- Alternative: contact the maintainer [@abyssbugg](https://github.com/abyssbugg)
  directly and ask for a private channel before sending details.

Please include: affected version or commit SHA, macOS and iOS versions, the
tunnel mode in use (USB / Wi-Fi / daemon / auto), reproduction steps, and what an
attacker gains. A proof of concept is welcome but not required.

This is a small project with a single maintainer. Expect an acknowledgement within
about a week. We will tell you when a fix lands and credit you unless you prefer
otherwise.

## Supported versions

Only the current `main` branch is supported. There is no back-porting; fixes ship
in the next release. See `CHANGELOG.md`.

## Scope

In scope — these are the surfaces we consider security-relevant:

- **Privileged execution path.** The app invokes a Python interpreter and bundle
  scripts through `do shell script … with administrator privileges`. See
  `PathChanger/Core/PrivilegedPathSecurity.swift` and
  `PathChanger/Device/PrivilegedCommandValidator.swift`.
- **Subprocess construction and argument handling.** `PathChanger/Core/ArgumentSanitizer.swift`,
  `PathChanger/Core/SubprocessPolicy.swift`.
- **Interpreter resolution.** `PathChanger/Core/PythonPathResolver.swift`.
- **Tunnel and RSD handling**, including data parsed from `tunneld`.
  `PathChanger/Device/`.
- **GPX parsing** — untrusted file input. `PathChanger/GPX/GPXParser.swift`.
- **Supply chain** — `requirements-pathchanger.lock` and the pinned, checksum-verified
  tool downloads in `.github/workflows/ci.yml`.

Out of scope:

- The behaviour of `pymobiledevice3` itself — report upstream.
- Anything requiring an attacker who is already root on the host.
- Physical access to an unlocked, already-paired device.
- Use of the app to spoof location; that is the product's stated purpose.

## Known and accepted residual risk

Please do not re-report these. They are documented decisions, not oversights.

- **Same-UID replacement of user-owned interpreter code.** The app accepts
  current-user-owned code in its provenance policy, so malware running as the same
  user can replace the interpreter or entrypoint between check and use (TOCTOU).
  Interim mitigations reject targets reachable through a group- or other-writable
  ancestor and prefer a root-owned pinned interpreter. The durable fix is a signed,
  root-owned `SMAppService` helper reached over XPC, which verifies the caller's
  code signature. It is **deferred**: `SMAppService` daemons cannot be registered,
  run, or tested without Developer ID signing. See
  [ADR 004](docs/adr/004-security-remediation-and-privilege-boundary.md).
- **Ad-hoc signed releases, no notarization, no auto-update.** Release integrity
  rests on the published SHA-256 manifest; there is no Gatekeeper assurance and no
  cryptographic binding to a developer identity. See
  [ADR 005](docs/adr/005-interim-adhoc-distribution.md). Always verify downloads:

  ```bash
  shasum -a 256 -c PathChanger-<version>-macOS.sha256
  ```

- **No true cancellation of the synchronous privileged AppleScript path**, for the
  same reason as the first item.

A new finding that *deepens* one of these — for example, a concrete同-UID
exploitation chain that defeats the interim writable-ancestor check — is in scope
and worth reporting.

## What CI enforces

On every pull request to `main`:

- `gitleaks` secret scan (pinned, checksum-verified) over all files.
- Entitlement policy gate: the build fails if any high-risk code-signing
  entitlement is enabled (`disable-library-validation`, `allow-unsigned-executable-memory`,
  `allow-dyld-environment-variables`, `allow-jit`, `get-task-allow`).
- Hash-enforced Python dependency install (`pip install --require-hashes --no-deps`).
- SwiftLint (pinned, checksum-verified).
- Build, unit tests, and DocC build.
