#!/usr/bin/env bash
#
# TA-ODIN Phase 1 Windows Parity Harness
# Runs all 6 Nyquist dimensions from .planning/phases/01-windows-parity/01-VALIDATION.md
# Exits 0 only when every dimension passes.
#
# Usage:
#   bash tools/tests/windows-parity-harness.sh           # full suite (all 6 dimensions)
#   bash tools/tests/windows-parity-harness.sh --quick   # static dimensions only (1-3)
#
# Note: uses `set -u` (not errexit) so all dimensions run and report
# independently instead of bailing on the first failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

FIXTURE_DIR="tools/tests/windows-fixtures/hostA"
BROKEN_FIXTURE_DIR="tools/tests/windows-fixtures/hostA-broken"
LINUX_GOLDEN_SERVICES="tools/tests/linux-golden/services.txt"

QUICK=0
if [[ "${1:-}" == "--quick" ]]; then
    QUICK=1
fi

fail_count=0

report() {
    local dim="$1" status="$2" detail="$3"
    if [[ "$status" == "PASS" ]]; then
        echo "[PASS] Dim $dim - $detail"
    else
        echo "[FAIL] Dim $dim - $detail"
        fail_count=$((fail_count + 1))
    fi
}

# ============================================================================
# Dimension 1 - Static grep gate (WIN-09)
# ============================================================================
if [[ -d TA-ODIN/bin ]]; then
    hits=$(grep -RIEn 'Invoke-Expression|Add-Type|iex |FromBase64String|Net\.WebClient|DownloadString|IEX' TA-ODIN/bin/ 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$hits" == "0" ]]; then
        report 1 PASS "no forbidden patterns in TA-ODIN/bin/"
    else
        report 1 FAIL "$hits forbidden-pattern matches in TA-ODIN/bin/"
    fi
else
    report 1 FAIL "TA-ODIN/bin/ does not exist"
fi

# ============================================================================
# Dimension 2 - Dependency gate (WIN-09)
# ============================================================================
if [[ -d TA-ODIN/bin ]]; then
    # Allow Microsoft.* module references (the '[^M]' excludes them)
    hits=$(grep -RIEn '#Requires -Module|Import-Module [^M]' TA-ODIN/bin/ 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$hits" == "0" ]]; then
        report 2 PASS "no external module dependencies in TA-ODIN/bin/"
    else
        report 2 FAIL "$hits external module dependencies in TA-ODIN/bin/"
    fi
else
    report 2 FAIL "TA-ODIN/bin/ does not exist"
fi

# ============================================================================
# Dimension 3 - MSI hazard gate (WIN-04)
# ============================================================================
if [[ -f TA-ODIN/bin/modules/packages.ps1 ]]; then
    hits=$(grep -c 'Win32_Product' TA-ODIN/bin/modules/packages.ps1 2>/dev/null || echo 0)
    if [[ "$hits" == "0" ]]; then
        report 3 PASS "no Win32_Product references in packages.ps1"
    else
        report 3 FAIL "$hits Win32_Product references in packages.ps1 (MSI self-repair hazard)"
    fi
else
    # Vacuously true: if packages.ps1 does not exist, no Win32_Product hazard
    # can exist. This keeps --quick green on a pre-Wave-2 repo. Dimensions 4-6
    # still FAIL in full mode because the behavioral/parity/fail-soft checks
    # require the orchestrator to be present.
    report 3 PASS "packages.ps1 does not exist yet (no Win32_Product hazard possible)"
fi

# --quick mode: skip behavioral (4), parity (5), fail-soft (6) — they need pwsh
if [[ $QUICK -eq 1 ]]; then
    echo ""
    echo "==================================="
    if [[ $fail_count -eq 0 ]]; then
        echo "Windows parity harness (--quick): dimensions 1-3 PASSED"
        exit 0
    else
        echo "Windows parity harness (--quick): $fail_count dimension(s) failed"
        exit 1
    fi
fi

# ============================================================================
# Dimension 4 - Behavioral fixture test (WIN-01, WIN-08)
# ============================================================================
# Treat the legacy pre-Phase-1 placeholder odin.ps1 (contains "Windows
# discovery not yet implemented") as "does not exist yet" for harness
# purposes. Wave 1 replaces the placeholder with the real orchestrator.
is_legacy_placeholder=0
if [[ -f TA-ODIN/bin/odin.ps1 ]] && grep -q 'Windows discovery not yet implemented' TA-ODIN/bin/odin.ps1 2>/dev/null; then
    is_legacy_placeholder=1
fi
if [[ -f TA-ODIN/bin/odin.ps1 && $is_legacy_placeholder -eq 0 ]]; then
    out=$(ODIN_TEST_FIXTURE="$FIXTURE_DIR" pwsh -NoProfile -NonInteractive -File TA-ODIN/bin/odin.ps1 2>&1)
    start_count=$(echo "$out" | grep -c 'type=odin_start')
    complete_count=$(echo "$out" | grep -c 'type=odin_complete modules_total=6')
    service_count=$(echo "$out" | grep -c 'type=service')
    port_count=$(echo "$out" | grep -c 'type=port')
    package_count=$(echo "$out" | grep -c 'type=package')
    task_count=$(echo "$out" | grep -c 'type=scheduled_task')
    proc_count=$(echo "$out" | grep -c 'type=process')
    mount_count=$(echo "$out" | grep -c 'type=mount')
    if [[ $start_count -ge 1 && $complete_count -ge 1 && \
          $service_count -ge 1 && $port_count -ge 1 && $package_count -ge 1 && \
          $task_count -ge 1 && $proc_count -ge 1 && $mount_count -ge 1 ]]; then
        report 4 PASS "orchestrator emits start/complete + all 6 module types against hostA"
    else
        report 4 FAIL "missing events: start=$start_count complete=$complete_count service=$service_count port=$port_count package=$package_count task=$task_count proc=$proc_count mount=$mount_count"
    fi
elif [[ $is_legacy_placeholder -eq 1 ]]; then
    report 4 FAIL "TA-ODIN/bin/odin.ps1 does not exist yet (legacy placeholder only — Wave 1/2 not landed)"
else
    report 4 FAIL "TA-ODIN/bin/odin.ps1 does not exist yet (Wave 1/2 not landed)"
fi

# ============================================================================
# Dimension 5 - Parity diff (WIN-08)
# ============================================================================
# Compare field-name set of type=service events between Windows and Linux
# orchestrators. Fall back to tools/tests/linux-golden/services.txt when the
# live Linux orchestrator produces no type=service events (e.g. on macOS dev
# machine without systemctl).
if [[ -f TA-ODIN/bin/odin.ps1 && $is_legacy_placeholder -eq 0 ]]; then
    win_raw=$(ODIN_TEST_FIXTURE="$FIXTURE_DIR" pwsh -NoProfile -File TA-ODIN/bin/odin.ps1 2>/dev/null | grep 'type=service' | head -n 1)
    lin_raw=""
    if [[ -f TA-ODIN/bin/odin.sh ]]; then
        lin_raw=$(bash TA-ODIN/bin/odin.sh 2>/dev/null | grep 'type=service' | head -n 1)
    fi
    if [[ -z "$lin_raw" && -f "$LINUX_GOLDEN_SERVICES" ]]; then
        lin_raw=$(grep 'type=service' "$LINUX_GOLDEN_SERVICES" | head -n 1)
    fi
    if [[ -z "$win_raw" ]]; then
        report 5 FAIL "no type=service event from Windows orchestrator (odin.ps1 missing or broken)"
    elif [[ -z "$lin_raw" ]]; then
        report 5 FAIL "no type=service event available from Linux orchestrator or golden file"
    else
        win_fields=$(echo "$win_raw" | tr ' ' '\n' | awk -F= '{print $1}' | sort -u)
        lin_fields=$(echo "$lin_raw" | tr ' ' '\n' | awk -F= '{print $1}' | sort -u)
        if [[ "$win_fields" == "$lin_fields" ]]; then
            report 5 PASS "field names match for type=service"
        else
            report 5 FAIL "field-name diff between Windows and Linux type=service"
        fi
    fi
else
    report 5 FAIL "TA-ODIN/bin/odin.ps1 does not exist yet (Wave 1/2 not landed)"
fi

# ============================================================================
# Dimension 6 - Fail-soft test (WIN-12)
# ============================================================================
if [[ -f TA-ODIN/bin/odin.ps1 && $is_legacy_placeholder -eq 0 ]]; then
    out=$(ODIN_TEST_FIXTURE="$BROKEN_FIXTURE_DIR" pwsh -NoProfile -File TA-ODIN/bin/odin.ps1 2>&1)
    has_error=$(echo "$out" | grep -c 'type=odin_error module=services')
    has_complete=$(echo "$out" | grep -c 'type=odin_complete modules_total=6 modules_success=5 modules_failed=1')
    if [[ $has_error -ge 1 && $has_complete -ge 1 ]]; then
        report 6 PASS "induced services failure still reaches odin_complete"
    else
        report 6 FAIL "missing fail-soft events: error=$has_error complete=$has_complete"
    fi
else
    report 6 FAIL "TA-ODIN/bin/odin.ps1 does not exist yet (Wave 1/2 not landed)"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "==================================="
if [[ $fail_count -eq 0 ]]; then
    echo "Windows parity harness: ALL DIMENSIONS PASSED"
    exit 0
else
    echo "Windows parity harness: $fail_count dimension(s) failed"
    exit 1
fi
