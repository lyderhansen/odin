#!/usr/bin/env bash
# tools/tests/check-host-info-parity.sh — HOST-03
#
# Verifies cross-platform parity: Linux + Windows orchestrators emit
# type=odin_host_info with IDENTICAL field-name set (13 fields each).
# Diffs field NAMES only — field VALUES are allowed to differ per D-09.
# Exit 0 on parity or pwsh-unavailable (SKIP). Exit 1 on divergence.
#
# Decision refs: D-08 (dedicated script), D-09 (live execution mode)

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0

# --- Tier 1: pwsh availability check (D-09 SKIP behavior) ---
if ! command -v pwsh >/dev/null 2>&1; then
    echo "[HOST-03 SKIP] pwsh not found — parity test deferred to environment with PowerShell"
    exit 0
fi

# --- Tier 2: capture both orchestrators (live mode per D-09) ---
linux_out=$(bash "$REPO_ROOT/TA-ODIN/bin/odin.sh" 2>&1)
windows_out=$(pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass \
    -File "$REPO_ROOT/TA-ODIN/bin/odin.ps1" 2>&1)

# --- Extract type=odin_host_info line from each platform ---
linux_event=$(echo "$linux_out" | grep 'type=odin_host_info' | head -1)
windows_event=$(echo "$windows_out" | grep 'type=odin_host_info' | head -1)

if [[ -z "$linux_event" ]]; then
    echo "[HOST-03 FAIL] Linux orchestrator emitted no type=odin_host_info event"
    fail=1
fi
if [[ -z "$windows_event" ]]; then
    echo "[HOST-03 FAIL] Windows orchestrator emitted no type=odin_host_info event"
    fail=1
fi
[[ $fail -ne 0 ]] && exit $fail

# --- Extract field NAMES (regex: lowercase_word= — names only, not values) ---
# grep -oE '[a-z_]+=' matches each field_name= occurrence.
# sed 's/=$//' strips the trailing '=' so we compare bare names.
# grep -vE removes the common envelope fields (timestamp, hostname, os, run_id,
# odin_version, type) so field_count reflects the 13 type-specific fields only.
# sort -u deduplicates and orders alphabetically for diff stability.
_envelope='^(timestamp|hostname|os|run_id|odin_version|type)$'
linux_fields=$(echo "$linux_event"  | grep -oE '[a-z_]+=' | sed 's/=$//' | grep -vE "$_envelope" | sort -u)
windows_fields=$(echo "$windows_event" | grep -oE '[a-z_]+=' | sed 's/=$//' | grep -vE "$_envelope" | sort -u)

# --- Diff field sets ---
diff_out=$(diff <(echo "$linux_fields") <(echo "$windows_fields"))
if [[ -z "$diff_out" ]]; then
    field_count=$(echo "$linux_fields" | wc -l | tr -d ' ')
    echo "[HOST-03 PASS] Linux + Windows field-set parity confirmed ($field_count fields each)"
else
    echo "[HOST-03 FAIL] Linux/Windows field-set divergence:"
    # shellcheck disable=SC2001  # multiline indent; parameter expansion can't do this cleanly
    echo "$diff_out" | sed 's/^/    /'
    fail=1
fi

exit $fail
