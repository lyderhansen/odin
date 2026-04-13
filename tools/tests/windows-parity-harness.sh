#!/usr/bin/env bash
#
# TA-ODIN Phase 1 Windows Parity Harness
# Runs all 6 Nyquist dimensions from .planning/phases/01-windows-parity/01-VALIDATION.md
# Exits 0 only when every selected dimension passes.
#
# Usage:
#   bash tools/tests/windows-parity-harness.sh             # full suite (all 6 dimensions)
#   bash tools/tests/windows-parity-harness.sh --quick     # static dimensions only (1-3)
#   bash tools/tests/windows-parity-harness.sh --dim N     # run a single dimension (1..6)
#
# Note: uses `set -u` (not errexit) so all dimensions run and report
# independently instead of bailing on the first failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

FIXTURE_DIR="tools/tests/windows-fixtures/hostA"
BROKEN_FIXTURE_DIR="tools/tests/windows-fixtures/hostA-broken"
LINUX_GOLDEN_DIR="tools/tests/linux-golden"

QUICK=0
DIM_FILTER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick)   QUICK=1; shift ;;
        --dim)     DIM_FILTER="${2:-}"; shift 2 ;;
        --dim=*)   DIM_FILTER="${1#--dim=}"; shift ;;
        *)         echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

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

# Detect legacy placeholder odin.ps1 (Wave 0 pre-orchestrator state)
is_legacy_placeholder() {
    if [[ -f TA-ODIN/bin/odin.ps1 ]] && grep -q 'Windows discovery not yet implemented' TA-ODIN/bin/odin.ps1 2>/dev/null; then
        echo 1
    else
        echo 0
    fi
}

# ============================================================================
# Dimension 1 - Static grep gate (WIN-09)
# ============================================================================
dimension_1_static_grep() {
    if [[ -d TA-ODIN/bin ]]; then
        local hits
        hits=$(grep -RIEn 'Invoke-Expression|Add-Type|iex |FromBase64String|Net\.WebClient|DownloadString|IEX' TA-ODIN/bin/ 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$hits" == "0" ]]; then
            report 1 PASS "no forbidden patterns in TA-ODIN/bin/"
        else
            report 1 FAIL "$hits forbidden-pattern matches in TA-ODIN/bin/"
        fi
    else
        report 1 FAIL "TA-ODIN/bin/ does not exist"
    fi
}

# ============================================================================
# Dimension 2 - Dependency gate (WIN-09)
# ============================================================================
dimension_2_dependency() {
    if [[ -d TA-ODIN/bin ]]; then
        # Allow Microsoft.* module references (the '[^M]' excludes them)
        local hits
        hits=$(grep -RIEn '#Requires -Module|Import-Module [^M]' TA-ODIN/bin/ 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$hits" == "0" ]]; then
            report 2 PASS "no external module dependencies in TA-ODIN/bin/"
        else
            report 2 FAIL "$hits external module dependencies in TA-ODIN/bin/"
        fi
    else
        report 2 FAIL "TA-ODIN/bin/ does not exist"
    fi
}

# ============================================================================
# Dimension 3 - MSI hazard gate (WIN-04)
# ============================================================================
dimension_3_msi_hazard() {
    if [[ -f TA-ODIN/bin/modules/packages.ps1 ]]; then
        local hits
        hits=$(grep -c 'Win32_Product' TA-ODIN/bin/modules/packages.ps1 2>/dev/null || echo 0)
        if [[ "$hits" == "0" ]]; then
            report 3 PASS "no Win32_Product references in packages.ps1"
        else
            report 3 FAIL "$hits Win32_Product references in packages.ps1 (MSI self-repair hazard)"
        fi
    else
        # Vacuously true: if packages.ps1 does not exist, no Win32_Product hazard
        # can exist. This keeps --quick green on a pre-Wave-2 repo.
        report 3 PASS "packages.ps1 does not exist yet (no Win32_Product hazard possible)"
    fi
}

# ============================================================================
# Dimension 4 - Behavioral fixture test (WIN-01, WIN-08)
# ============================================================================
dimension_4_behavioral() {
    local legacy
    legacy=$(is_legacy_placeholder)
    if [[ -f TA-ODIN/bin/odin.ps1 && "$legacy" == "0" ]]; then
        local out
        out=$(ODIN_TEST_FIXTURE="$FIXTURE_DIR" pwsh -NoProfile -NonInteractive -File TA-ODIN/bin/odin.ps1 2>&1)
        local start_count complete_count service_count port_count package_count task_count proc_count mount_count
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
    elif [[ "$legacy" == "1" ]]; then
        report 4 FAIL "TA-ODIN/bin/odin.ps1 is a legacy placeholder only (Wave 1/2 not landed)"
    else
        report 4 FAIL "TA-ODIN/bin/odin.ps1 does not exist yet (Wave 1/2 not landed)"
    fi
}

# ============================================================================
# Dimension 5 - Per-type field-name parity diff (WIN-08)
# ============================================================================
# Strips the orchestrator prelude (timestamp/hostname/os/run_id/odin_version)
# from both Windows emit lines and Linux golden lines, then diffs the
# remaining per-type field-name set.
#
# scheduled_task is explicitly SKIPPED with a logged rationale: the Linux
# cron event model (cron_source/schedule/command/file/user) does NOT map 1:1
# to the Windows Task Scheduler object model (task_name/path/state/author/
# last_run/next_run/last_result). This divergence is the ONE documented
# allowed field-name exception per CONTEXT.md D6 and WIN-05. Forcing an
# alias would produce false positives; the skip is the honest answer and is
# audited by code review rather than mechanical grep.

extract_field_names() {
    local line="$1"
    local prelude='timestamp|hostname|os|run_id|odin_version'
    echo "$line" \
        | tr ' ' '\n' \
        | awk -F= 'NF>0 {print $1}' \
        | grep -vE "^($prelude)$" \
        | grep -vE '^$' \
        | sort -u
}

dimension_5_parity() {
    local legacy status=0
    legacy=$(is_legacy_placeholder)
    if [[ ! -f TA-ODIN/bin/odin.ps1 || "$legacy" == "1" ]]; then
        report 5 FAIL "TA-ODIN/bin/odin.ps1 does not exist yet (Wave 1/2 not landed)"
        return 1
    fi

    # Run the Windows orchestrator once under hostA fixture and reuse its
    # output for every per-type check.
    local win_output
    win_output=$(ODIN_TEST_FIXTURE="$FIXTURE_DIR" pwsh -NoProfile -NonInteractive -File TA-ODIN/bin/odin.ps1 2>/dev/null)

    # The six event types to diff (Windows label -> Linux golden file basename)
    local types=(service port package scheduled_task process mount)
    local -A golden_map=(
        [service]=services.txt
        [port]=ports.txt
        [package]=packages.txt
        [scheduled_task]=cron.txt
        [process]=processes.txt
        [mount]=mounts.txt
    )

    for t in "${types[@]}"; do
        local golden_file="$LINUX_GOLDEN_DIR/${golden_map[$t]}"
        if [[ ! -f "$golden_file" ]]; then
            echo "[DIM5-FAIL] golden file missing: $golden_file"
            status=1
            continue
        fi

        local win_line
        win_line=$(echo "$win_output" | grep -m1 "type=$t ") || true
        if [[ -z "$win_line" ]]; then
            echo "[DIM5-FAIL] Windows output has no type=$t line"
            status=1
            continue
        fi

        # scheduled_task <-> cron: intentional divergence. Skip with rationale.
        if [[ "$t" == "scheduled_task" ]]; then
            echo "[DIM5-SKIP] type=scheduled_task - intentional field-name divergence per CONTEXT D6 (Linux uses cron_source/schedule/command/file, Windows uses task_name/path/state/author/last_run/next_run/last_result - different semantic model, same signal)"
            continue
        fi

        local win_fields lin_fields
        win_fields=$(extract_field_names "$win_line" | grep -v '^type$')
        lin_fields=$(extract_field_names "$(cat "$golden_file")" | grep -v '^type$')

        if [[ "$win_fields" != "$lin_fields" ]]; then
            echo "[DIM5-FAIL] type=$t field-name drift"
            echo "  Windows: $(echo "$win_fields" | tr '\n' ' ')"
            echo "  Linux:   $(echo "$lin_fields" | tr '\n' ' ')"
            status=1
        else
            echo "[DIM5-PASS] type=$t field-name set matches"
        fi
    done

    if [[ $status -eq 0 ]]; then
        report 5 PASS "field-name set matches for service/port/package/process/mount (scheduled_task skipped per CONTEXT D6)"
    else
        report 5 FAIL "per-type field-name drift detected (see [DIM5-*] lines above)"
    fi
    return $status
}

# ============================================================================
# Dimension 6 - Fail-soft test (WIN-12)
# ============================================================================
dimension_6_failsoft() {
    local legacy
    legacy=$(is_legacy_placeholder)
    if [[ -f TA-ODIN/bin/odin.ps1 && "$legacy" == "0" ]]; then
        local out
        out=$(ODIN_TEST_FIXTURE="$BROKEN_FIXTURE_DIR" pwsh -NoProfile -File TA-ODIN/bin/odin.ps1 2>&1)
        local has_error has_complete
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
}

# ============================================================================
# Dispatch
# ============================================================================
if [[ -n "$DIM_FILTER" ]]; then
    case "$DIM_FILTER" in
        1) dimension_1_static_grep ;;
        2) dimension_2_dependency ;;
        3) dimension_3_msi_hazard ;;
        4) dimension_4_behavioral ;;
        5) dimension_5_parity ;;
        6) dimension_6_failsoft ;;
        *) echo "Unknown dimension: $DIM_FILTER" >&2; exit 2 ;;
    esac
    echo ""
    echo "==================================="
    if [[ $fail_count -eq 0 ]]; then
        echo "Windows parity harness (dim $DIM_FILTER): PASSED"
        exit 0
    else
        echo "Windows parity harness (dim $DIM_FILTER): $fail_count dimension(s) failed"
        exit 1
    fi
fi

# Static dimensions always run
dimension_1_static_grep
dimension_2_dependency
dimension_3_msi_hazard

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

# Full run: behavioral + parity + fail-soft
dimension_4_behavioral
dimension_5_parity
dimension_6_failsoft

echo ""
echo "==================================="
if [[ $fail_count -eq 0 ]]; then
    echo "Windows parity harness: ALL DIMENSIONS PASSED"
    exit 0
else
    echo "Windows parity harness: $fail_count dimension(s) failed"
    exit 1
fi
