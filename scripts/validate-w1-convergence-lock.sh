#!/bin/bash
# Validate W1 freeze-lock authority convergence using lightweight static checks.
#
# Gates:
#   A. No UI calls to TunneldManager.startTunnel().
#   B. No new UI simulation execution callers outside the canonical authority.
#   C. No new UI teleport execution callers outside documented W4 exceptions.
#   D. No non-canonical "Set Location" T0 labels.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

failures=0

fail() {
    echo "✗ $1" >&2
    failures=$((failures + 1))
}

pass() {
    echo "✓ $1"
}

matches_without_allowed() {
    local pattern="$1"
    shift
    local paths=("$@")

    grep -RInE --include="*.swift" "$pattern" "${paths[@]}" || true
}

check_gate() {
    local pass_message="$1"
    local fail_message="$2"
    local matches="$3"

    if [ -n "$matches" ]; then
        fail "$fail_message"
        printf '%s\n' "$matches" >&2
    else
        pass "$pass_message"
    fi
}

echo "Validating W1 convergence lock..."

# Gate A — forbidden tunnel-start callers.
# Allowed: TunneldManager internals only. UI must route through autoStart().
gate_a_matches="$(matches_without_allowed 'tunneldManager[[:space:]]*\.[[:space:]]*startTunnel[[:space:]]*\(' PathChanger/UI)"
check_gate \
    "Gate A passed: no UI tunneldManager.startTunnel callers" \
    "Gate A failed: UI source must not call tunneldManager.startTunnel(" \
    "$gate_a_matches"

# Gate B — forbidden simulation-execution callers.
# Allowed canonical T0 authority: PrimaryActionPill.swift.
# Documented W4-deferred compatibility exception: SimulationView.swift legacy
# .full chrome main control panel until W4 removes the compatibility surface.
gate_b_matches="$(matches_without_allowed 'appState[[:space:]]*\.[[:space:]]*(startSimulation|stopSimulation)[[:space:]]*\(' PathChanger/UI \
    | grep -v '^PathChanger/UI/Components/PrimaryActionPill.swift:' \
    | grep -v '^PathChanger/UI/SimulationView.swift:' || true)"
check_gate \
    "Gate B passed: no new UI simulation execution callers" \
    "Gate B failed: UI simulation execution must remain in PrimaryActionPill or documented W4 legacy full-chrome exception" \
    "$gate_b_matches"

# Gate C — forbidden teleport execution callers.
# Allowed canonical execution path: AppState/startSimulation internals, not UI.
# Documented W4-deferred compatibility exception: SidebarView.swift history Apply
# remains until W4 compatibility-surface deletion.
gate_c_matches="$(matches_without_allowed 'appState[[:space:]]*\.[[:space:]]*setLocation[[:space:]]*\(' PathChanger/UI \
    | grep -v '^PathChanger/UI/SidebarView.swift:' || true)"
check_gate \
    "Gate C passed: no UI setLocation callers outside documented W4 exception" \
    "Gate C failed: UI setLocation callers must not appear outside the documented W4 SidebarView exception" \
    "$gate_c_matches"

# Gate D — forbidden visual-authority regressions.
# Allowed canonical rendered T0 label authority: PrimaryActionPill.swift.
gate_d_matches="$(matches_without_allowed '"Set Location"' PathChanger/UI \
    | grep -v '^PathChanger/UI/Components/PrimaryActionPill.swift:' || true)"
check_gate \
    "Gate D passed: no non-canonical UI \"Set Location\" labels" \
    "Gate D failed: non-canonical UI \"Set Location\" label detected outside PrimaryActionPill" \
    "$gate_d_matches"

if [ "$failures" -ne 0 ]; then
    echo "W1 convergence-lock validation failed with $failures violation(s)." >&2
    exit 1
fi

echo "W1 convergence-lock validation passed."
