#!/bin/bash
# Validate W1 freeze-lock authority convergence using lightweight static checks.
#
# Gates:
#   A. No shell-surface calls to TunneldManager.startTunnel().
#   B. SimulationView is shell-only (no legacy `.full` chrome pathway).
#   C. SimulationView has no direct simulation execution callers.
#   D. CollapsibleSidebar has no execution-adjacent callers.
#   E. Shell surfaces expose no non-canonical "Set Location" labels.
#   F. Policy script contains no legacy governance markers.

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

matches_in_scope() {
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

require_paths() {
    local missing=0
    for path in "$@"; do
        if [ ! -f "$path" ]; then
            fail "Required validation target is missing: $path"
            missing=1
        fi
    done
    return "$missing"
}

echo "Validating W1 convergence lock..."

shell_paths=(
    PathChanger/UI/MainMapShell.swift
    PathChanger/UI/SimulationView.swift
    PathChanger/UI/Components/CollapsibleSidebar.swift
)

require_paths "${shell_paths[@]}" || true

# Gate A — forbidden direct tunnel-start callers in shell surfaces.
gate_a_matches="$(matches_in_scope 'tunneldManager[[:space:]]*\.[[:space:]]*startTunnel[[:space:]]*\(' "${shell_paths[@]}")"
check_gate \
    "Gate A passed: no shell-surface tunneldManager.startTunnel callers" \
    "Gate A failed: shell surfaces must not call tunneldManager.startTunnel(" \
    "$gate_a_matches"

# Gate B — no legacy SimulationView full-chrome pathway markers.
gate_b_matches="$(matches_in_scope '(case[[:space:]]+full|chrome[[:space:]]*:[[:space:]]*SimulationViewChrome[[:space:]]*=[[:space:]]*\.full|chrome[[:space:]]*==[[:space:]]*\.full|SimulationViewChrome[[:space:]]*\.[[:space:]]*full)' PathChanger/UI/SimulationView.swift)"
check_gate \
    "Gate B passed: SimulationView has no legacy full-chrome pathway markers" \
    "Gate B failed: SimulationView must not encode legacy full-chrome pathway markers" \
    "$gate_b_matches"

# Gate C — no direct simulation execution callers from SimulationView.
gate_c_matches="$(matches_in_scope 'appState[[:space:]]*\.[[:space:]]*(startSimulation|stopSimulation|pauseSimulation|resumeSimulation)[[:space:]]*\(' PathChanger/UI/SimulationView.swift)"
check_gate \
    "Gate C passed: SimulationView has no direct simulation execution callers" \
    "Gate C failed: SimulationView must not call AppState simulation execution APIs directly" \
    "$gate_c_matches"

# Gate D — CollapsibleSidebar must remain execution-adjacent-action free.
gate_d_matches="$(matches_in_scope '(appState[[:space:]]*\.[[:space:]]*setLocation[[:space:]]*\(|tunneldManager[[:space:]]*\.[[:space:]]*(autoStart|startTunnel)[[:space:]]*\()' PathChanger/UI/Components/CollapsibleSidebar.swift)"
check_gate \
    "Gate D passed: CollapsibleSidebar has no execution-adjacent callers" \
    "Gate D failed: CollapsibleSidebar must not call AppState.setLocation or tunnel start actions" \
    "$gate_d_matches"

# Gate E — no non-canonical "Set Location" label in shell surfaces.
gate_e_matches="$(matches_in_scope '"Set Location"' "${shell_paths[@]}")"
check_gate \
    "Gate E passed: no shell-surface \"Set Location\" labels" \
    "Gate E failed: shell surfaces must not render \"Set Location\" authority labels" \
    "$gate_e_matches"

# Gate F — no legacy governance markers in this policy script.
gate_f_matches="$(grep -InE 'allow[[:space:]]*list|white[[:space:]]*list' scripts/validate-w1-convergence-lock.sh || true)"
check_gate \
    "Gate F passed: policy script has no legacy governance markers" \
    "Gate F failed: legacy governance markers remain in convergence lock script" \
    "$gate_f_matches"

if [ "$failures" -ne 0 ]; then
    echo "W1 convergence-lock validation failed with $failures violation(s)." >&2
    exit 1
fi

echo "W1 convergence-lock validation passed."
