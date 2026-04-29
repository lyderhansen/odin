#!/usr/bin/env bash
# tools/tests/check-host-info.sh — HOST-01
#
# Verifies Phase 7 / HOST-01 success criteria:
#   1. Exactly ONE type=odin_host_info event per scan
#   2. All 13 named fields present in that event
#   3. Event positioned as #2 (between odin_start and module events)
#   4. Total IMDS budget on non-cloud hosts is ≤3s overhead (D-02: 1s × 3
#      sequential probes — relaxed from ROADMAP's original 2s).
#      NOTE: this script does NOT measure timing — that check lives in the
#      plan-level <verification> block. This file verifies field correctness
#      (event count, all 13 fields present, positioning, virt enum, cloud
#      sentinel). Adding a runtime measurement here is a future enhancement.
#
# Exit 0 when all checks pass, non-zero otherwise.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0

# --- Run the orchestrator and capture output ---
out=$(bash "$REPO_ROOT/TA-ODIN/bin/odin.sh" 2>&1)

# --- Check 1: exactly ONE type=odin_host_info event ---
host_info_count=$(echo "$out" | grep -c 'type=odin_host_info')
if [[ "$host_info_count" -eq 1 ]]; then
    echo "[HOST-01 PASS] exactly 1 type=odin_host_info event emitted"
else
    echo "[HOST-01 FAIL] expected 1 type=odin_host_info event, got $host_info_count"
    fail=1
fi

# --- Check 2: all 13 named fields present ---
expected_fields=(os_distro os_version os_pretty os_kernel os_arch
                 cpu_cores mem_total_mb uptime_seconds
                 fqdn ip_primary virtualization
                 cloud_provider cloud_region)
host_info_line=$(echo "$out" | grep 'type=odin_host_info' | head -1)
missing_fields=()
for field in "${expected_fields[@]}"; do
    if ! echo "$host_info_line" | grep -q "${field}="; then
        missing_fields+=("$field")
    fi
done
if [[ ${#missing_fields[@]} -eq 0 ]]; then
    echo "[HOST-01 PASS] all 13 named fields present in event"
else
    echo "[HOST-01 FAIL] missing fields: ${missing_fields[*]}"
    fail=1
fi

# --- Check 3: host_info is event #2 (right after odin_start) ---
event2=$(echo "$out" | grep -E '^timestamp=' | sed -n '2p')
if echo "$event2" | grep -q 'type=odin_host_info'; then
    echo "[HOST-01 PASS] host_info is event #2 (between odin_start and module events)"
else
    echo "[HOST-01 FAIL] event #2 is not type=odin_host_info — positioning broken"
    echo "             event #2 was: $event2"
    fail=1
fi

# --- Check 4: virtualization value is in D-04 enum ---
virt_val=$(echo "$host_info_line" | grep -oE 'virtualization=[^ ]+' | cut -d= -f2)
case "$virt_val" in
    baremetal|kvm|vmware|hyperv|xen|container|unknown)
        echo "[HOST-01 PASS] virtualization=$virt_val is in D-04 enum"
        ;;
    *)
        echo "[HOST-01 FAIL] virtualization=$virt_val is NOT in D-04 enum (baremetal|kvm|vmware|hyperv|xen|container|unknown)"
        fail=1
        ;;
esac

# --- Check 5: cloud_provider sentinel discipline (none or aws|gcp|azure) ---
cloud_val=$(echo "$host_info_line" | grep -oE 'cloud_provider=[^ ]+' | cut -d= -f2)
case "$cloud_val" in
    none|aws|gcp|azure|unknown)
        echo "[HOST-01 PASS] cloud_provider=$cloud_val honors D-03 sentinel discipline"
        ;;
    *)
        echo "[HOST-01 FAIL] cloud_provider=$cloud_val is NOT a valid value (none|aws|gcp|azure|unknown)"
        fail=1
        ;;
esac

if [[ $fail -eq 0 ]]; then
    echo "[HOST-01 PASS] All checks passed"
fi
exit $fail
