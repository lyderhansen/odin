# Phase 7: Host Info — Linux - Pattern Map

**Mapped:** 2026-04-28
**Files analyzed:** 3 (1 modified shared lib, 1 modified orchestrator, 1 new test)
**Analogs found:** 3 / 3 — all in-repo, no synthetic patterns needed

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `TA-ODIN/bin/modules/_common.sh` (MODIFIED) | shared library / utility | one-shot probe → key=value emit | `TA-ODIN/bin/modules/_common.sh` (self, lines 40–58) for `emit`/`get_timestamp` style + `TA-ODIN/bin/odin.sh` lines 60–64 for OS-feature detection at load time | exact (extension of same file) |
| `TA-ODIN/bin/odin.sh` (MODIFIED) | orchestrator / config | sequential lifecycle emit | `TA-ODIN/bin/odin.sh` (self, lines 94–105) — existing `odin_start` + warning emit cluster | exact (insertion into same emit sequence) |
| `tools/tests/check-host-info.sh` (NEW) | test / regression guard | exec → grep → assert | `tools/tests/check-two-app-split.sh` (filesystem assertions) + `tools/tests/check-version-sync.sh` (extraction + comparison) + `tools/tests/windows-parity-harness.sh` lines 119–146 (orchestrator stdout grep) | role-match (assertion script) |

**Phase 8 mirror reference (NOT modified by this phase, but constrains design):**
| Mirror File | Role | Notes |
|-------------|------|-------|
| `TA-ODIN/bin/modules/_common.ps1` (Phase 8) | shared library | Each new helper added in `_common.sh` MUST have a `PascalCase-Verb-Noun` PowerShell mirror name reserved (e.g., `detect_virt` → `Get-OdinVirtualization`). Phase 8 will add these in `_common.ps1`; document the parity contract in the helper's bash comment header. |
| `TA-ODIN/bin/odin.ps1` (Phase 8) | orchestrator | Phase 8 will insert one `Invoke-OdinEmit` of `type=odin_host_info` between line 95 (`type=odin_start` emit) and line 100 (counter init). Same positional contract as Linux. |

---

## Pattern Assignments

### `TA-ODIN/bin/modules/_common.sh` (extend with 8 new helper functions)

**Analog:** `TA-ODIN/bin/modules/_common.sh` itself (this is an additive extension — DO NOT touch lines 1–59) plus the OS-detection-at-load-time idiom from `TA-ODIN/bin/odin.sh:60–64`.

#### Pattern 1 — Header comment block must remain intact (lines 1–28)

The existing header documents the orchestrator-vs-standalone gating contract. Phase 7 must ADD a paragraph to this header that documents:
- New helpers are orchestrator-only (NOT for module use)
- Phase 8 mirror function name in `_common.ps1` per helper

Existing header to preserve verbatim (lines 1–28 of `_common.sh`):
```bash
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
```

**Rule:** No edits between lines 1–59 of `_common.sh`. All Phase 7 additions are appended after line 59. The `! declare -f emit` gate in modules continues to work because it tests for the orchestrator-exported `emit` symbol, not for any new symbols Phase 7 adds.

#### Pattern 2 — Standalone-context default block (lines 30–38) is the template for IMDS timeout default

Existing pattern (lines 30–38):
```bash
ODIN_HOSTNAME="${ODIN_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}"
ODIN_OS="${ODIN_OS:-linux}"
ODIN_RUN_ID="${ODIN_RUN_ID:-standalone-$$}"
ODIN_VERSION="${ODIN_VERSION:-1.0.1}"
ODIN_MAX_EVENTS="${ODIN_MAX_EVENTS:-50000}"
ODIN_EVENT_COUNT=0
```

**Apply to Phase 7:** Add the IMDS timeout knob in the same `${VAR:-default}` style at the same scope (after line 38, before the new helpers begin):
```bash
ODIN_IMDS_TIMEOUT="${ODIN_IMDS_TIMEOUT:-1}"   # seconds per cloud probe (D-02: AWS→GCP→Azure)
```

The pattern is: env-var-aware default at file load, never re-declared in the helper that uses it. This matches the established convention and makes the harness override path identical to `ODIN_MAX_EVENTS`.

#### Pattern 3 — `emit()` is the SOLE output channel (lines 49–59)

Existing emit (lines 49–59):
```bash
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
```

**Apply to Phase 7:** The new `emit_host_info()` MUST call `emit "type=odin_host_info ..."` exactly once with all 13 fields concatenated. Do NOT echo directly. Do NOT bypass `emit`. Reasons:
1. Inherits the timestamp/hostname/os/run_id/odin_version envelope automatically
2. Counts toward `ODIN_MAX_EVENTS` (1 event budget consumed for host_info — fine because it runs before the per-module reset on `odin.sh:132`)
3. Truncation marker safety preserved

Skeleton for `emit_host_info()`:
```bash
emit_host_info() {
    # Each field is detected once, then concatenated. Failure → 'unknown'; semantic null → 'none' (D-03).
    local os_distro os_version os_pretty os_kernel os_arch
    local cpu_cores mem_total_mb uptime_seconds
    local fqdn ip_primary virtualization
    local cloud_pair cloud_provider cloud_region

    # ... call detect_* helpers, parse pipe-separated returns ...

    emit "type=odin_host_info os_distro=$(safe_val "$os_distro") os_version=$(safe_val "$os_version") os_pretty=$(safe_val "$os_pretty") os_kernel=$(safe_val "$os_kernel") os_arch=$(safe_val "$os_arch") cpu_cores=$cpu_cores mem_total_mb=$mem_total_mb uptime_seconds=$uptime_seconds fqdn=$(safe_val "$fqdn") ip_primary=$ip_primary virtualization=$virtualization cloud_provider=$cloud_provider cloud_region=$(safe_val "$cloud_region")"
}
```

**`safe_val()` choice:** `safe_val` is currently defined inside individual modules (e.g., `services.sh:25–33`, `cron.sh:24–32`), NOT in `_common.sh`. Phase 7 has two options for `os_pretty` (the only host_info field guaranteed to contain spaces, e.g., `"Rocky Linux 9.3 (Blue Onyx)"`):

- **Option preferred (additive):** Define `safe_val()` once inside `emit_host_info()` (or as a private helper in the new section). Do NOT add it at module scope in `_common.sh` — that would change the resolution order for the 6 existing modules (which currently each define their own copy) and break the additive-only principle from CONTEXT.md `<specifics>`.
- **Option future:** Phase 9 may consolidate `safe_val()` into `_common.sh` once parity work is done. Not in scope here.

#### Pattern 4 — `get_epoch_ms()` style for OS-feature gated function definition

Source: `TA-ODIN/bin/odin.sh:60–64`:
```bash
if [[ "$(date +%3N 2>/dev/null)" =~ ^[0-9]+$ ]]; then
    get_epoch_ms() { date +%s%3N; }
else
    get_epoch_ms() { echo "$(date +%s)000"; }
fi
```

**Apply to Phase 7 `detect_virt()`:** Same idiom for picking the detection backend at load time vs. at every call. Recommended cascade structure (per CONTEXT.md D-04):
```bash
# Top-level dispatcher decided once at sourcing time. systemd-detect-virt is
# preferred (cleanest enum, vendored on every modern distro). Fallback chain
# only compiled if the preferred binary is absent.
if command -v systemd-detect-virt >/dev/null 2>&1; then
    detect_virt() {
        local v
        v=$(timeout 2 systemd-detect-virt 2>/dev/null) || { echo "unknown"; return; }
        case "$v" in
            none)                                echo "baremetal" ;;
            kvm|qemu)                            echo "kvm" ;;
            vmware)                              echo "vmware" ;;
            microsoft)                           echo "hyperv" ;;
            xen)                                 echo "xen" ;;
            docker|podman|lxc|systemd-nspawn|wsl) echo "container" ;;
            *)                                   echo "unknown" ;;
        esac
    }
else
    detect_virt() {
        # Fallback chain: dmidecode → /proc/1/cgroup → unknown
        # ... see plan for full body ...
        echo "unknown"
    }
fi
```

This mirrors the get_epoch_ms idiom **exactly** (capability check at load time, two function bodies, no per-call branching cost).

#### Pattern 5 — `timeout` wrapping for any external command (universal)

Source: `TA-ODIN/bin/modules/services.sh:41,141,158` and `cron.sh` (every external command is timeout-wrapped):
```bash
batch_output=$(timeout 30 systemctl show --type=service --all ...)
done < <(timeout 30 service --status-all 2>/dev/null)
if timeout 5 "$script" status &>/dev/null 2>&1; then
```

**Apply to Phase 7 IMDS probes (D-02):** Every `curl` to a cloud IMDS endpoint MUST be `timeout $ODIN_IMDS_TIMEOUT curl -s ...`. Example template for the AWS probe (IMDSv2):
```bash
probe_aws() {
    local token region
    token=$(timeout "$ODIN_IMDS_TIMEOUT" curl -s -X PUT \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
        http://169.254.169.254/latest/api/token 2>/dev/null) || return 1
    [[ -z "$token" ]] && return 1
    region=$(timeout "$ODIN_IMDS_TIMEOUT" curl -s \
        -H "X-aws-ec2-metadata-token: $token" \
        http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null) || return 1
    [[ -z "$region" ]] && return 1
    echo "aws|$region"
}
```

Worst-case 3s total when no cloud IMDS responds (1s × 3 probes), per D-02. This stays well within the orchestrator's 90s per-module budget AND the Splunk 120s scripted-input timeout.

---

### `TA-ODIN/bin/odin.sh` (insert ONE call to `emit_host_info` between odin_start and root warnings)

**Analog:** `TA-ODIN/bin/odin.sh` itself, lines 94–105 — the existing `--- Start event ---` / `--- Warn if not running as root ---` cluster.

#### Pattern — Insertion point (between line 99 and line 102)

Existing structure (lines 94–105):
```bash
# --- Start event ---
# Capture scan start time for duration_ms in odin_complete (parity with Windows
# orchestrator's $scanStart at odin.ps1:90 — captured immediately before start emit).
ODIN_START_MS=$(get_epoch_ms)
run_user=$(id -un 2>/dev/null || echo "unknown")
emit "type=odin_start run_as=$run_user euid=$EUID message=\"TA-ODIN enumeration started\""

# Warn if not running as root — some modules return limited data
if [[ $ODIN_RUNNING_AS_ROOT -eq 0 ]]; then
    emit "type=odin_warning module=ports message=\"Running as non-root (euid=$EUID). Port enumeration will not include process names/PIDs for ports owned by other users.\""
    emit "type=odin_warning module=cron message=\"Running as non-root (euid=$EUID). User crontabs in /var/spool/cron may be unreadable.\""
fi
```

**Apply to Phase 7:** Insert `emit_host_info` call as a new section between line 99 (`emit "type=odin_start ..."`) and line 102 (root-check `if`):
```bash
emit "type=odin_start run_as=$run_user euid=$EUID message=\"TA-ODIN enumeration started\""

# --- Host info event ---
# Phase 7 / HOST-01: emit exactly one type=odin_host_info event with 13 host
# metadata fields (OS, hardware, network, virtualization, cloud detection).
# Positioned deterministically as event #2, between odin_start and any
# warnings/module events. Helper lives in TA-ODIN/bin/modules/_common.sh.
emit_host_info

# Warn if not running as root — some modules return limited data
if [[ $ODIN_RUNNING_AS_ROOT -eq 0 ]]; then
    ...
```

**Critical:** `emit_host_info` is not yet in scope at this line. The orchestrator currently does NOT source `_common.sh` (only modules do, conditionally). Phase 7 has TWO valid implementation paths — the planner picks one:

- **Path A (preferred — minimal):** Source `_common.sh` from `odin.sh` near line 50 (just after `MODULES_DIR` is set), guarded so it only happens once. Existing `emit()` and `get_timestamp()` defined in `odin.sh:67–86` STAY (they are the exported orchestrator versions); the source pulls in only the new `detect_*` and `emit_host_info` helpers. Risk: name collision on `emit()` and `get_timestamp()`. Mitigation: in `_common.sh`, guard the existing `emit`/`get_timestamp` definitions with `if ! declare -f emit &>/dev/null; then ... fi` — turning `_common.sh` into a true idempotent library that defines the helper only when missing. The new Phase 7 helpers (`detect_*`, `emit_host_info`) are defined unconditionally because they are NEW.

- **Path B (alternative):** Inline `emit_host_info` and all `detect_*` helpers into `odin.sh`. CONTEXT.md D-01 explicitly rejects this (option A4) — DO NOT use Path B.

Path A constraint: when guarding `emit`/`get_timestamp` in `_common.sh`, do not change their bodies. The orchestrator's `emit` (with `ODIN_EVENTS_TRUNCATED` flag, lines 67–82) is semantically richer than the standalone `emit` in `_common.sh:49–59` (no flag, just counter check). When `_common.sh` is sourced FROM the orchestrator, the orchestrator's `emit` is already defined and will not be overwritten — guarding behavior preserved.

#### Pattern — Module discovery loop excludes `_common`

Source: `TA-ODIN/bin/odin.sh:124–127`:
```bash
# Skip the shared library (sourced by modules' standalone-fallback branch,
# not a discoverable module itself). Mirrors Windows orchestrator at
# odin.ps1:114 which excludes _common.ps1 by name.
[[ "$module_name" == "_common" ]] && continue
```

**Apply to Phase 7:** No change required. The exclusion already protects `_common.sh` from being run as a module. Confirmed valid even after Phase 7 adds 8 new helpers — they are functions, not module entry points. The Windows mirror at `odin.ps1:114` (`-and $_.Name -ne '_common.ps1'`) provides parity protection on the Phase 8 side.

---

### `tools/tests/check-host-info.sh` (NEW regression test)

**Analog:** Hybrid of three existing tests:
1. `tools/tests/check-two-app-split.sh` — minimal exit-code structure, REPO_ROOT discovery
2. `tools/tests/check-version-sync.sh` — extraction-and-comparison pattern
3. `tools/tests/windows-parity-harness.sh:119–146` — running orchestrator and grep'ing stdout

#### Pattern 1 — File header + exit code discipline

Source: `tools/tests/check-two-app-split.sh:1–22`:
```bash
#!/usr/bin/env bash
# tools/tests/check-two-app-split.sh — HARD-07
#
# Verifies the TA-ODIN / ODIN_app_for_splunk two-app split is clean.
# ...
# Exit 0 when split is clean, non-zero otherwise.

set -u

fail=0
```

**Apply:** Same shape — set -u (NOT set -e — we want all assertions to run), top-level `fail=0` accumulator, REPO_ROOT discovered relative to script location.

#### Pattern 2 — REPO_ROOT discovery for portable invocation

Source: `tools/tests/check-two-app-split.sh:39`:
```bash
# Resolve paths relative to repo root, not CWD
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
```

**Apply:** Identical — Phase 7 test runs from anywhere (CI, local, harness loop).

#### Pattern 3 — Run orchestrator and grep stdout (assertion structure)

Source: `tools/tests/windows-parity-harness.sh:122–140`:
```bash
out=$(ODIN_TEST_FIXTURE="$FIXTURE_DIR" pwsh -NoProfile -NonInteractive -File TA-ODIN/bin/odin.ps1 2>&1)
local start_count complete_count service_count ...
start_count=$(echo "$out" | grep -c 'type=odin_start')
complete_count=$(echo "$out" | grep -c 'type=odin_complete modules_total=6')
...
if [[ $start_count -ge 1 && $complete_count -ge 1 && \
      $service_count -ge 1 && ... ]]; then
    report 4 PASS "orchestrator emits ..."
```

**Apply to Phase 7:** Same pattern — capture orchestrator output, count occurrences of `type=odin_host_info`, then validate field presence:
```bash
out=$(bash "$REPO_ROOT/TA-ODIN/bin/odin.sh" 2>&1)

# Success criterion 1: exactly ONE type=odin_host_info event
host_info_count=$(echo "$out" | grep -c 'type=odin_host_info')
if [[ "$host_info_count" -eq 1 ]]; then
    echo "[HOST-01 PASS] exactly 1 type=odin_host_info event emitted"
else
    echo "[HOST-01 FAIL] expected 1 type=odin_host_info event, got $host_info_count"
    fail=1
fi

# Success criterion 2: all 13 named fields present in the host_info line
host_info_line=$(echo "$out" | grep 'type=odin_host_info' | head -1)
for field in os_distro os_version os_pretty os_kernel os_arch cpu_cores \
             mem_total_mb uptime_seconds fqdn ip_primary virtualization \
             cloud_provider cloud_region; do
    if ! echo "$host_info_line" | grep -q "${field}="; then
        echo "[HOST-01 FAIL] missing field: $field"
        fail=1
    fi
done

# Success criterion 3: host_info appears as event #2 (right after odin_start)
event2=$(echo "$out" | grep -E '^timestamp=' | sed -n '2p')
if echo "$event2" | grep -q 'type=odin_host_info'; then
    echo "[HOST-01 PASS] host_info is event #2 (between odin_start and module events)"
else
    echo "[HOST-01 FAIL] event #2 is not type=odin_host_info — positioning broken"
    fail=1
fi

exit $fail
```

#### Pattern 4 — Structured PASS/FAIL output (for CI parsing)

Source: `tools/tests/check-two-app-split.sh:42–53`:
```bash
for f in "${ta_odin_forbidden[@]}"; do
    if [[ -e "$REPO_ROOT/$f" ]]; then
        echo "[HARD-07 FAIL] $f must NOT exist in TA-ODIN ..."
        fail=1
    fi
done
...
if [[ $fail -eq 0 ]]; then
    echo "[HARD-07 PASS] Two-app split is clean"
fi
exit $fail
```

**Apply:** Use `[HOST-01 PASS]` / `[HOST-01 FAIL]` token convention so the existing harness output parser (and human review) can grep for tier-FAIL lines uniformly.

---

## Shared Patterns

### Sentinel value convention (D-03 — applies to ALL detection helpers)

**Source:** Phase 7 CONTEXT.md decision D-03 (no codebase precedent for the `unknown`/`none` distinction yet — `services.sh:171` uses `none_found` only in the per-module case).

**Apply to:** Every `detect_*` helper in `_common.sh`.

```bash
# Failure path (command returned non-zero, file missing, network error)
# → emit field=unknown
detect_cpu_cores() {
    local n
    n=$(nproc 2>/dev/null) || { echo "unknown"; return; }
    [[ -z "$n" || ! "$n" =~ ^[0-9]+$ ]] && { echo "unknown"; return; }
    echo "$n"
}

# Semantic null path (no cloud → cloud_provider=none, no default route → ip_primary=none)
probe_cloud_imds() {
    probe_aws  && return  # returns "aws|<region>"
    probe_gcp  && return  # returns "gcp|<region>"
    probe_azure && return # returns "azure|<region>"
    echo "none|none"      # all three failed → semantic null
}
```

Numeric fields (`cpu_cores`, `mem_total_mb`, `uptime_seconds`) emit as STRINGS even on failure (`cpu_cores=unknown`, never `cpu_cores=-1`). Splunk dashboards handle this with `| convert num(cpu_cores)` which naturally drops `unknown` rows.

### Cross-platform parity contract (Phase 8 readiness)

**Apply to:** Every helper added in `_common.sh`. Each helper's leading comment block must include:
```bash
# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Get-OdinVirtualization
# Returns one of: baremetal | kvm | vmware | hyperv | xen | container | unknown (D-04)
```

This makes Phase 8 a mechanical port (read header, mirror name, mirror enum). Phase 9 parity test asserts both produce the same field values for matching fixtures.

| Linux helper | Windows mirror name (Phase 8 contract) |
|---|---|
| `detect_os_distro()` | `Get-OdinOsDistro` |
| `detect_os_kernel_arch()` | `Get-OdinOsKernelArch` |
| `detect_hardware()` | `Get-OdinHardware` |
| `detect_runtime_uptime()` | `Get-OdinRuntimeUptime` |
| `detect_network()` | `Get-OdinNetwork` |
| `detect_virt()` | `Get-OdinVirtualization` |
| `probe_cloud_imds()` | `Invoke-OdinCloudImds` |
| `emit_host_info()` | `Invoke-OdinEmitHostInfo` |

### `LC_ALL=C` locale enforcement

**Source:** Every Linux module sets `export LC_ALL=C` near the top (e.g., `services.sh:16`, `cron.sh:15`). Orchestrator does the same on `odin.sh:22`.

**Apply to Phase 7:** No new locale export needed — `_common.sh` is sourced from a context that already has `LC_ALL=C` set. But if any new helper parses `awk`/`sed` output (e.g., `awk '/MemTotal/{print int($2/1024)}' /proc/meminfo`), the existing locale is what guarantees stable parsing.

### `command -v` capability gate before any external binary

**Source:** Used everywhere — `services.sh:39` (`command -v systemctl`), `services.sh:124` (`command -v service`), `odin.sh:41` (`command -v timeout`).

**Apply to Phase 7:** Every detection helper that calls a non-coreutils binary MUST gate it. Examples:
- `detect_virt()` → `command -v systemd-detect-virt >/dev/null 2>&1`
- `detect_virt()` fallback → `command -v dmidecode >/dev/null 2>&1`
- `detect_network()` → `command -v ip >/dev/null 2>&1` (modern) vs `command -v ifconfig` (RHEL 6 fallback)
- `probe_cloud_imds()` → `command -v curl >/dev/null 2>&1` (return `none|none` immediately if absent)

This guarantees Phase 7 stays compatible with minimal-install distros (Alpine, RHEL UBI minimal) where `dmidecode`, `systemd-detect-virt`, `ip`, even `curl` may be absent.

---

## No Analog Found

None. All three Phase 7 files have strong in-repo analogs. The only "novel" surface is the IMDS probe pattern (cloud-specific HTTP calls with provider-specific auth headers), but that mechanically follows from the existing `timeout <n> <cmd>` wrapping convention — no new architectural pattern is introduced.

---

## Metadata

**Analog search scope:** `TA-ODIN/bin/`, `tools/tests/`
**Files scanned:** `_common.sh`, `_common.ps1`, `odin.sh`, `odin.ps1`, `services.sh`, `cron.sh`, `check-two-app-split.sh`, `check-version-sync.sh`, `windows-parity-harness.sh`
**Pattern extraction date:** 2026-04-28
**Decision compliance check:** All 4 locked decisions (D-01 single-file extension, D-02 sequential 1s×3 IMDS, D-03 unknown/none sentinels, D-04 6-value virtualization enum) have a concrete code pattern assigned above.
