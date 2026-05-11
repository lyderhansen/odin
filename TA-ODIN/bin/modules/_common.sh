#!/bin/bash
#
# TA-ODIN v1.0.2 - Shared Bash Library (Linux)
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
ODIN_VERSION="${ODIN_VERSION:-1.0.2}"
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
    local _id _version_id _pretty_name
    if [[ -r /etc/os-release ]]; then
        _id=$(grep '^ID=' /etc/os-release 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
        _version_id=$(grep '^VERSION_ID=' /etc/os-release 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
        _pretty_name=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
        [[ -n "$_id" ]] && distro="$_id"
        [[ -n "$_version_id" ]] && version="$_version_id"
        [[ -n "$_pretty_name" ]] && pretty="$_pretty_name"
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

# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Get-OdinVirtualization
# Returns one of: baremetal | kvm | vmware | hyperv | xen | container | unknown (D-04)
# Single field, 7-value enum (D-04 explicitly rejects per-runtime sub-fields).
# Detection cascade: systemd-detect-virt (preferred) → dmidecode → /proc/1/cgroup → unknown.
# Picked at sourcing time per Pattern 4 — no per-call branching cost.
if command -v systemd-detect-virt >/dev/null 2>&1; then
detect_virt() {
    local v
    v=$(timeout 2 systemd-detect-virt 2>/dev/null) || { echo "unknown"; return; }
    case "$v" in
        none)                                              echo "baremetal" ;;
        kvm|qemu)                                          echo "kvm" ;;
        vmware)                                            echo "vmware" ;;
        microsoft)                                         echo "hyperv" ;;
        xen)                                               echo "xen" ;;
        docker|podman|lxc|systemd-nspawn|wsl|rkt|openvz)   echo "container" ;;
        *)                                                 echo "unknown" ;;
    esac
}
else
detect_virt() {
    # Fallback chain when systemd-detect-virt is absent (RHEL 6, Alpine minimal, etc.)
    local vendor
    if command -v dmidecode >/dev/null 2>&1; then
        vendor=$(timeout 2 dmidecode -s system-manufacturer 2>/dev/null)
        case "$vendor" in
            *"QEMU"*|*"KVM"*)        echo "kvm";    return ;;
            *"VMware"*)              echo "vmware"; return ;;
            *"Microsoft"*)           echo "hyperv"; return ;;
            *"Xen"*)                 echo "xen";    return ;;
            *"Amazon EC2"*)          echo "kvm";    return ;;
            *"Google"*)              echo "kvm";    return ;;
        esac
    fi
    # cgroup probe (works without root, world-readable on most kernels)
    if [[ -r /proc/1/cgroup ]]; then
        if grep -qE '/(docker|containerd|kubepods|lxc|podman)/' /proc/1/cgroup 2>/dev/null; then
            echo "container"; return
        fi
    fi
    # No DMI signal + no container hint + no systemd-detect-virt → can't decide
    echo "unknown"
}
fi

# --- Cloud IMDS probes (D-02: sequential AWS→GCP→Azure, 1s curl timeout each) ---
# AWS requires 2 sequential curl calls (IMDSv2 token + region query).
# Worst-case total on a non-cloud host: 4s worst case (AWS IMDSv2 = 2 sequential calls:
# token PUT 1s + region GET 1s; GCP: 1s; Azure: 1s). Non-cloud hosts typically
# resolve in 3s as the IMDSv2 token endpoint fails immediately on first call.
# Internal helpers (single underscore prefix), called only by probe_cloud_imds.

# AWS IMDSv2 (token-based, more secure than v1).
_probe_aws_imds() {
    command -v curl >/dev/null 2>&1 || return 1
    local token region
    token=$(timeout "$ODIN_IMDS_TIMEOUT" curl -s -X PUT \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
        --connect-timeout "$ODIN_IMDS_TIMEOUT" --max-time "$ODIN_IMDS_TIMEOUT" \
        http://169.254.169.254/latest/api/token 2>/dev/null) || return 1
    [[ -z "$token" ]] && return 1
    region=$(timeout "$ODIN_IMDS_TIMEOUT" curl -s \
        -H "X-aws-ec2-metadata-token: $token" \
        --connect-timeout "$ODIN_IMDS_TIMEOUT" --max-time "$ODIN_IMDS_TIMEOUT" \
        http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null) || return 1
    [[ -z "$region" ]] && return 1
    echo "aws|$region"
    return 0
}

# GCP metadata server (header-gated, requires Metadata-Flavor: Google).
_probe_gcp_imds() {
    command -v curl >/dev/null 2>&1 || return 1
    local zone region
    zone=$(timeout "$ODIN_IMDS_TIMEOUT" curl -s \
        -H "Metadata-Flavor: Google" \
        --connect-timeout "$ODIN_IMDS_TIMEOUT" --max-time "$ODIN_IMDS_TIMEOUT" \
        http://metadata.google.internal/computeMetadata/v1/instance/zone 2>/dev/null) || return 1
    [[ -z "$zone" ]] && return 1
    # zone format: projects/PROJECT_NUM/zones/europe-west1-b → strip to region: europe-west1
    region=$(echo "$zone" | awk -F/ '{print $NF}' | sed 's/-[a-z]$//')
    [[ -z "$region" ]] && return 1
    echo "gcp|$region"
    return 0
}

# Azure IMDS (api-version param required).
_probe_azure_imds() {
    command -v curl >/dev/null 2>&1 || return 1
    local region
    region=$(timeout "$ODIN_IMDS_TIMEOUT" curl -s \
        -H "Metadata: true" \
        --connect-timeout "$ODIN_IMDS_TIMEOUT" --max-time "$ODIN_IMDS_TIMEOUT" \
        "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text" 2>/dev/null) || return 1
    [[ -z "$region" ]] && return 1
    echo "azure|$region"
    return 0
}

# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Invoke-OdinCloudImds
# Returns: pipe-separated "provider|region" (2 of the 13 fields).
# Sequential probe order: AWS → GCP → Azure (D-02). First success wins.
# All three fail (non-cloud or no curl): returns "none|none" (semantic null per D-03).
probe_cloud_imds() {
    local out
    out=$(_probe_aws_imds 2>/dev/null)   && [[ -n "$out" ]] && { echo "$out"; return; }
    out=$(_probe_gcp_imds 2>/dev/null)   && [[ -n "$out" ]] && { echo "$out"; return; }
    out=$(_probe_azure_imds 2>/dev/null) && [[ -n "$out" ]] && { echo "$out"; return; }
    echo "none|none"
}

# Phase 10 mirror: TA-ODIN/bin/modules/_common.ps1 → Invoke-OdinDetectContainer
# Returns: pipe-separated "runtime|id|image_hint" (3 of the 16 host_info fields).
# D-11 enum (5 values + 2 sentinels): docker|podman|containerd|unknown|none.
# D-12 source order: /proc/self/cgroup → /proc/1/cpuset → $DOCKER_CONTAINER_ID env-var.
# D-13 image_hint: /etc/os-release IMAGE_ID only; absent → "none".
# D-03 sentinel discipline:
#   not in container         → "none|none|none" (semantic null)
#   in container, classified → "<runtime>|<12-hex>|<value-or-none>"
#   in container, FAILED     → "unknown|unknown|none" (system failure)
detect_container() {
    local runtime="none" id="none" image_hint="none"
    local cgroup_content="" cpuset_content="" env_id=""

    # Read cgroup info — first-match source order per D-12
    [[ -r /proc/self/cgroup ]] && cgroup_content=$(cat /proc/self/cgroup 2>/dev/null)
    [[ -r /proc/1/cpuset ]] && cpuset_content=$(cat /proc/1/cpuset 2>/dev/null)
    env_id="${DOCKER_CONTAINER_ID:-}"

    # Detect runtime from cgroup content (D-11 enum)
    if [[ "$cgroup_content" == *"/docker/"* ]] || [[ "$cgroup_content" == *"docker-"* ]] || [[ "$cpuset_content" == *"/docker/"* ]]; then
        runtime="docker"
    elif [[ "$cgroup_content" == *"/libpod-"* ]] || [[ "$cgroup_content" == *"/podman-"* ]] || [[ "$cgroup_content" == *"libpod_parent"* ]]; then
        runtime="podman"
    elif [[ "$cgroup_content" == *"/containerd/"* ]] || [[ "$cgroup_content" == *"cri-containerd"* ]]; then
        runtime="containerd"
    elif [[ "$cgroup_content" != "" && "$cgroup_content" != *"/init.scope"* && "$cgroup_content" != *"/user.slice"* && "$cgroup_content" != *"/system.slice"* ]] || [[ -n "$env_id" ]]; then
        # Some container indicator present but doesn't match known runtimes
        runtime="unknown"
    else
        # No container indicators → baremetal
        echo "none|none|none"
        return 0
    fi

    # Extract container ID — first 12-char hex prefix (D-12 format)
    if [[ -n "$env_id" ]]; then
        id=$(echo "$env_id" | grep -oE '[a-f0-9]{12,64}' | head -1 | cut -c1-12)
    fi
    if [[ -z "$id" || "$id" == "none" ]]; then
        id=$(echo "$cgroup_content" | grep -oE '[a-f0-9]{12,64}' | head -1 | cut -c1-12)
    fi
    if [[ -z "$id" || "$id" == "none" ]]; then
        id=$(echo "$cpuset_content" | grep -oE '[a-f0-9]{12,64}' | head -1 | cut -c1-12)
    fi
    [[ -z "$id" ]] && id="unknown"

    # Extract image_hint from /etc/os-release IMAGE_ID (D-13)
    if [[ -r /etc/os-release ]]; then
        local hint
        hint=$(grep -E '^IMAGE_ID=' /etc/os-release 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' )
        [[ -n "$hint" ]] && image_hint="$hint"
    fi

    echo "${runtime}|${id}|${image_hint}"
}

# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Invoke-OdinEmitHostInfo
# THE ONLY function that emits type=odin_host_info. Calls each detect_* helper
# exactly once, splits pipe-separated returns, then issues a single emit() with
# all 16 fields concatenated (13 v1.0.2 + 3 Phase 10 container fields).
#
# Field order in event (13 v1.0.2 fields + 3 Phase 10 container fields = 16 total):
#   os_distro os_version os_pretty os_kernel os_arch
#   cpu_cores mem_total_mb uptime_seconds
#   fqdn ip_primary virtualization
#   cloud_provider cloud_region
#   container_runtime container_id container_image_hint
#
# Counts toward ODIN_MAX_EVENTS (1 event budget consumed before per-module
# reset on odin.sh:132). Truncation marker safety preserved (Pattern 3).
emit_host_info() {
    # Private quoter for fields that may contain spaces (only os_pretty in practice).
    # Defined inside the function to avoid module-scope name collisions with
    # services.sh:25 / cron.sh:24 etc. (additive principle from CONTEXT.md).
    _safe_val_host_info() {
        local v="$1"
        if [[ "$v" == *" "* || "$v" == *"\""* ]]; then
            echo "\"${v//\"/\\\"}\""
        else
            echo "$v"
        fi
    }

    local os_pair os_distro os_version os_pretty
    local kern_pair os_kernel os_arch
    local hw_pair cpu_cores mem_total_mb
    local uptime_seconds
    local net_pair fqdn ip_primary
    local virtualization
    local cloud_pair cloud_provider cloud_region
    local container_pair container_runtime container_id container_image_hint

    os_pair=$(detect_os_distro)
    IFS='|' read -r os_distro os_version os_pretty <<< "$os_pair"

    kern_pair=$(detect_os_kernel_arch)
    IFS='|' read -r os_kernel os_arch <<< "$kern_pair"

    hw_pair=$(detect_hardware)
    IFS='|' read -r cpu_cores mem_total_mb <<< "$hw_pair"

    uptime_seconds=$(detect_runtime_uptime)

    net_pair=$(detect_network)
    IFS='|' read -r fqdn ip_primary <<< "$net_pair"

    virtualization=$(detect_virt)

    cloud_pair=$(probe_cloud_imds)
    IFS='|' read -r cloud_provider cloud_region <<< "$cloud_pair"

    container_pair=$(detect_container)
    IFS='|' read -r container_runtime container_id container_image_hint <<< "$container_pair"

    emit "type=odin_host_info os_distro=$(_safe_val_host_info "$os_distro") os_version=$(_safe_val_host_info "$os_version") os_pretty=$(_safe_val_host_info "$os_pretty") os_kernel=$(_safe_val_host_info "$os_kernel") os_arch=$os_arch cpu_cores=$cpu_cores mem_total_mb=$mem_total_mb uptime_seconds=$uptime_seconds fqdn=$(_safe_val_host_info "$fqdn") ip_primary=$ip_primary virtualization=$virtualization cloud_provider=$cloud_provider cloud_region=$(_safe_val_host_info "$cloud_region") container_runtime=$container_runtime container_id=$container_id container_image_hint=$(_safe_val_host_info "$container_image_hint")"
}
