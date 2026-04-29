#!/bin/bash
#
# TA-ODIN v1.0.1 - Shared Bash Library (Linux)
#
# This file is sourced by every module's standalone-fallback branch when the
# orchestrator's emit() function is not in scope (i.e., when a module is
# invoked directly for debugging instead of via odin.sh).
#
# Sourcing pattern (inside each module):
#
#     if ! declare -f emit &>/dev/null; then
#         # shellcheck source=_common.sh
#         source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
#     fi
#
# When the orchestrator runs a module, emit() is exported via `export -f emit`
# (see TA-ODIN/bin/odin.sh:75) so `declare -f emit` returns true and this file
# is NEVER sourced. The gating mechanism is critical: dual-defining emit()
# would shadow the orchestrator's truncation tracking.
#
# Mirrors the Windows shared library at TA-ODIN/bin/modules/_common.ps1
# (which is dot-sourced rather than imported as a PowerShell module for
# Constrained Language Mode safety — see _common.ps1 D2/D5 notes).
#
# Closes PROD-07 (d) — consolidation of standalone-fallback hygiene from
# 6 modules into a single shared file. The pre-refactor pattern duplicated
# this 20-line block across cron.sh, mounts.sh, packages.sh, ports.sh,
# processes.sh, services.sh.
#
# v1.0.2 (Phase 7 / HOST-01) extends this file with 8 host_info detection
# helpers (detect_*, probe_cloud_imds, emit_host_info) appended after the
# v1.0.1 standalone-fallback section. Those helpers are ORCHESTRATOR-ONLY:
# they are sourced by odin.sh and called once from emit_host_info()
# between odin_start and the modules loop. Modules MUST NOT call detect_*
# or emit_host_info directly — they would emit duplicate type=odin_host_info
# events outside the orchestrator's deterministic event sequence.
# Each new helper documents its Phase 8 PowerShell mirror name in its own
# comment header (e.g., detect_virt → Get-OdinVirtualization).

# Standalone-context defaults — orchestrator pre-sets these via export, so the
# parameter expansion is a no-op when invoked via odin.sh. Direct module
# invocation (debugging) gets sensible defaults here.
ODIN_HOSTNAME="${ODIN_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}"
ODIN_OS="${ODIN_OS:-linux}"
ODIN_RUN_ID="${ODIN_RUN_ID:-standalone-$$}"
ODIN_VERSION="${ODIN_VERSION:-1.0.1}"
ODIN_MAX_EVENTS="${ODIN_MAX_EVENTS:-50000}"
ODIN_EVENT_COUNT=0
ODIN_IMDS_TIMEOUT="${ODIN_IMDS_TIMEOUT:-1}"   # seconds per cloud probe (D-02: AWS→GCP→Azure)

if ! declare -f get_timestamp &>/dev/null; then
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}
fi

# Emit a key=value event line with MAX_EVENTS guardrail.
# Mirrors orchestrator emit() behavior: emits exactly one type=truncated marker
# on first cap-breach, drops subsequent events. Counter is incremented past the
# cap on the truncated emit so subsequent events match the -ge guard but not
# the -eq re-emit guard, preventing duplicate truncation markers.
if ! declare -f emit &>/dev/null; then
emit() {
    if [[ $ODIN_EVENT_COUNT -ge $ODIN_MAX_EVENTS ]]; then
        if [[ $ODIN_EVENT_COUNT -eq $ODIN_MAX_EVENTS ]]; then
            echo "timestamp=$(get_timestamp) hostname=$ODIN_HOSTNAME os=$ODIN_OS run_id=$ODIN_RUN_ID odin_version=$ODIN_VERSION type=truncated message=\"Event limit reached (max=$ODIN_MAX_EVENTS). Remaining events suppressed.\""
            ODIN_EVENT_COUNT=$((ODIN_EVENT_COUNT + 1))
        fi
        return 0
    fi
    ODIN_EVENT_COUNT=$((ODIN_EVENT_COUNT + 1))
    echo "timestamp=$(get_timestamp) hostname=$ODIN_HOSTNAME os=$ODIN_OS run_id=$ODIN_RUN_ID odin_version=$ODIN_VERSION $*"
}
fi

# ============================================================================
# Phase 7 / HOST-01: Host metadata detection helpers (v1.0.2)
# ============================================================================
# These helpers are called by emit_host_info() to populate the 13-field
# type=odin_host_info event. Each helper:
#   - Returns ONE pipe-separated string OR a single value
#   - Returns "unknown" on detection failure (D-03 — system error sentinel)
#   - Returns "none" only for semantic null (e.g., no cloud detected)
#   - Wraps every external command with `timeout` (D-02 + project convention)
#   - Documents its Phase 8 PowerShell mirror name in the comment header
# ============================================================================

# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Get-OdinOsDistro
# Returns: pipe-separated "distro|version|pretty" (3 of the 13 fields).
# Detection: parse /etc/os-release per systemd spec.
detect_os_distro() {
    local distro="unknown" version="unknown" pretty="unknown"
    if [[ -r /etc/os-release ]]; then
        # Source in subshell to avoid polluting our env with NAME=, ID=, etc.
        eval "$(grep -E '^(ID|VERSION_ID|PRETTY_NAME)=' /etc/os-release 2>/dev/null)"
        [[ -n "${ID:-}" ]] && distro="$ID"
        [[ -n "${VERSION_ID:-}" ]] && version="$VERSION_ID"
        [[ -n "${PRETTY_NAME:-}" ]] && pretty="$PRETTY_NAME"
    fi
    echo "${distro}|${version}|${pretty}"
}

# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Get-OdinOsKernelArch
# Returns: pipe-separated "kernel|arch" (2 of the 13 fields).
# Detection: uname -r and uname -m.
detect_os_kernel_arch() {
    local kernel arch
    kernel=$(timeout 2 uname -r 2>/dev/null) || kernel="unknown"
    arch=$(timeout 2 uname -m 2>/dev/null) || arch="unknown"
    [[ -z "$kernel" ]] && kernel="unknown"
    [[ -z "$arch" ]] && arch="unknown"
    echo "${kernel}|${arch}"
}

# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Get-OdinHardware
# Returns: pipe-separated "cpu_cores|mem_total_mb" (2 of the 13 fields).
# Detection: nproc + /proc/meminfo. Numbers stay as strings even on failure
# (D-03: "unknown" not -1).
detect_hardware() {
    local cores mem_mb
    if command -v nproc >/dev/null 2>&1; then
        cores=$(timeout 2 nproc 2>/dev/null) || cores="unknown"
    else
        cores="unknown"
    fi
    [[ -z "$cores" || ! "$cores" =~ ^[0-9]+$ ]] && cores="unknown"

    if [[ -r /proc/meminfo ]]; then
        mem_mb=$(awk '/^MemTotal:/{print int($2/1024); exit}' /proc/meminfo 2>/dev/null) || mem_mb="unknown"
        [[ -z "$mem_mb" || ! "$mem_mb" =~ ^[0-9]+$ ]] && mem_mb="unknown"
    else
        mem_mb="unknown"
    fi
    echo "${cores}|${mem_mb}"
}

# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Get-OdinRuntimeUptime
# Returns: a single integer string OR "unknown" (1 of the 13 fields).
# Detection: /proc/uptime first column (seconds since boot, floating point → int).
detect_runtime_uptime() {
    local uptime
    if [[ -r /proc/uptime ]]; then
        uptime=$(awk '{print int($1); exit}' /proc/uptime 2>/dev/null) || uptime="unknown"
        [[ -z "$uptime" || ! "$uptime" =~ ^[0-9]+$ ]] && uptime="unknown"
    else
        uptime="unknown"
    fi
    echo "$uptime"
}

# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Get-OdinNetwork
# Returns: pipe-separated "fqdn|ip_primary" (2 of the 13 fields).
# Detection:
#   - fqdn: hostname -f, fall back to `unknown` if not resolvable
#   - ip_primary: `ip route get 1.1.1.1` extracted via awk src-keyword indexing
#     (more robust than $7 — handles single-line and multi-word output formats)
# Returns "none" for ip_primary when there is no default route (semantic null
# per D-03), distinct from "unknown" (detection failure).
detect_network() {
    local fqdn ip
    fqdn=$(timeout 2 hostname -f 2>/dev/null) || fqdn="unknown"
    [[ -z "$fqdn" ]] && fqdn="unknown"

    if command -v ip >/dev/null 2>&1; then
        # Try default route to public IP. Empty/error → no route → semantic null.
        ip=$(timeout 2 ip route get 1.1.1.1 2>/dev/null \
            | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')
        if [[ -z "$ip" ]]; then
            ip="none"
        fi
    else
        ip="unknown"
    fi
    echo "${fqdn}|${ip}"
}
