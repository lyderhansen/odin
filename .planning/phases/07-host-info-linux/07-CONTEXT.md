# Phase 7: Host Info — Linux - Context

**Gathered:** 2026-04-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Linux orchestrator (`TA-ODIN/bin/odin.sh`) emits exactly ONE `type=odin_host_info` event per scan, positioned between `type=odin_start` and the first module event, populated with all 13 host metadata fields specified in REQUIREMENTS.md HOST-01 and `.planning/seeds/v1.0.2-host-metadata-enrichment.md`. The event uses the standard envelope (timestamp/hostname/os/run_id/odin_version) and follows the established `key=value` format.

This phase is Linux-only. Phase 8 mirrors all decisions for Windows. Phase 9 adds cross-platform parity validation, DATA-DICTIONARY documentation, and dashboard panels.

**In scope:** Implementation of detection helpers + orchestrator integration + IMDS timeout safety + per-field error handling + tests.

**Out of scope:** Windows orchestrator (Phase 8), parity validation script (Phase 9), DATA-DICTIONARY.md updates (Phase 9), dashboard panels (Phase 9), container enumeration (v1.1.0), cloud asset metadata beyond provider+region (v1.1.0 Phase 4 optional).

</domain>

<decisions>
## Implementation Decisions

### Helper Function Placement (Area A)

- **D-01:** **Extend `TA-ODIN/bin/modules/_common.sh`** with new helper functions for host metadata detection. The file grows from 59 → ~250 lines. Functions to add: `detect_os_distro()`, `detect_os_kernel_arch()`, `detect_hardware()`, `detect_runtime_uptime()`, `detect_network()`, `detect_virt()`, `probe_cloud_imds()`, `emit_host_info()`. Rationale: mirrors PROD-07d's "single shared lib" pattern; trivializes Phase 8 Windows parity (mirror in `_common.ps1`); no new directory structure (additive principle); per-module isolation harness from Plan 05-01 still works.

### IMDS Probe Strategy (Area B)

- **D-02:** **Sequential probe order: AWS → GCP → Azure with 1-second `curl` timeout per probe.** Worst case 3 seconds total for non-cloud hosts. AWS uses IMDSv2 (token-based, requires PUT first). GCP uses `Metadata-Flavor: Google` header. Azure uses `Metadata: true` header against `169.254.169.254/metadata/instance?api-version=2021-02-01`. Each probe returns either `cloud_provider|cloud_region` string on success or empty on failure. `probe_cloud_imds()` aggregates and returns `none|none` if all three fail. Rationale: 1s is rikelig for link-local IMDS endpoints (<100ms response when present); 3s worst case is trivial against 30-day scan interval and 120s Splunk timeout; deterministic ordering makes debugging predictable; pure sequential bash — no temp files, no race conditions, no background-process cleanup.

### Field Error Handling (Area C)

- **D-03:** **All-strings sentinel convention.** Every field emits as a string. Two distinct sentinel values:
    - `unknown` → detection command failed (e.g., `nproc` returned non-zero, `/proc/meminfo` missing, IMDS network error)
    - `none` → semantic null (e.g., `cloud_provider=none` means "not on a cloud", `ip_primary=none` means "no default route")

  Numeric fields (cpu_cores, mem_total_mb, uptime_seconds) ALSO emit as strings on failure (e.g., `cpu_cores=unknown`, NOT `cpu_cores=-1`). This means Splunk numeric queries on these fields require `| convert num(cpu_cores)` first, which naturally skips "unknown" rows. Rationale: simplest mental model (every field always populated, never empty, never omitted); clear semantic distinction between system-failure and semantic-null; matches existing `none_found` sentinel pattern from Phase 1 modules; forces dashboard authors to handle degraded case explicitly.

### Virtualization Field Granularity (Area D)

- **D-04:** **Single field `virtualization` with 6-value enum.** Allowed values: `baremetal`, `kvm`, `vmware`, `hyperv`, `xen`, `container`, `unknown`. Container-runtime detail (docker vs podman vs k8s) is NOT included in v1.0.2 host_info — that detail belongs in v1.1.0 sine `type=container` per-container events. Detection chain: primary `systemd-detect-virt` (returns "none" → map to `baremetal`; otherwise pass through), fallback to `dmidecode` Manufacturer field, final fallback to `/proc/1/cgroup` inspection (presence of `/docker/`, `/containerd/`, `/kubepods/` → `container`). On all-fallback-failure, emit `virtualization=unknown`. Rationale: keeps strict 13-field count from seed; container-runtime detail flows naturally in v1.1.0's per-container events; aligns with `systemd-detect-virt` enum semantics; v1.0.2 ships fast without forward-compat regrets.

### Locked from Seed (not re-discussed)

These were already established in `.planning/seeds/v1.0.2-host-metadata-enrichment.md` and `.planning/REQUIREMENTS.md` HOST-01. NOT discussed in this phase, but listed here for downstream agent reference:

- **Event type name:** `type=odin_host_info` (not `type=host_info` or `type=odin_environment`)
- **Field count:** Exactly 13 fields (`os_distro`, `os_version`, `os_pretty`, `os_kernel`, `os_arch`, `cpu_cores`, `mem_total_mb`, `uptime_seconds`, `fqdn`, `ip_primary`, `virtualization`, `cloud_provider`, `cloud_region`)
- **Event positioning:** Between `type=odin_start` and the first module event (line 2 of orchestrator output, deterministic)
- **Event count per scan:** Exactly 1
- **Detection methods per field:** Per the seed's table (e.g., `os_distro` from `/etc/os-release` ID=, `cpu_cores` from `nproc`, `fqdn` from `hostname -f`)

### Claude's Discretion

The following sub-decisions are NOT user-locked and may be refined during planning/execution:

- Internal helper function naming conventions (camelCase vs snake_case — follow existing `_common.sh` style)
- Order of detection within `detect_virt()` fallback chain (after systemd-detect-virt, dmidecode then cgroup OR cgroup then dmidecode)
- Whether `probe_cloud_imds()` returns parsed values or raw IMDS response strings (planner can decide)
- Test fixture format for IMDS mocking (stub `curl` via PATH wrapper, OR env-var-based response injection)
- Exact error message format if all detections fail (string content within the `unknown` sentinel value)

### Folded Todos

None — no pending todos in `.planning/todos/` matched this phase's scope.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 7 Authoritative Sources
- `.planning/seeds/v1.0.2-host-metadata-enrichment.md` — Complete 13-field reference table with detection methods per platform (Linux + Windows). Acceptance criteria. Risk profile.
- `.planning/notes/2026-04-27-host-metadata-and-container-strategy.md` — Decision context for why this milestone exists, why fields are split this way, why this phase is Linux-only.
- `.planning/REQUIREMENTS.md` — HOST-01 acceptance criteria (locked text).
- `.planning/ROADMAP.md` §"Phase 7: Host Info — Linux" — 4 success criteria + dependency on v1.0.1-rc1.

### Code to Modify
- `TA-ODIN/bin/modules/_common.sh` — Current 59 lines. ALL new helper functions go here. Will grow to ~250 lines.
- `TA-ODIN/bin/odin.sh` — Orchestrator. Insert `emit_host_info` call between line 99 (`emit "type=odin_start ..."`) and line 102 (`# Warn if not running as root`) — see existing structure.

### Pattern References (read for style consistency)
- Commit `4b7ef88` — PROD-07 (d) `_common.sh` consolidation pattern. Establishes how helpers in `_common.sh` are sourced by modules and called from orchestrator.
- Commit `718f76b` — `duration_ms` parity work. Establishes `get_epoch_ms()` helper convention (cross-platform date detection with fallback).
- `TA-ODIN/bin/modules/_common.ps1` — Windows shared lib. Phase 8 mirror reference.

### Documentation to Update Later (Phase 9 — NOT this phase)
- `DOCS/DATA-DICTIONARY.md` — Phase 9 will add `## type=odin_host_info` section.
- `ODIN_app_for_splunk/default/data/ui/views/odin_overview.xml` — Phase 9 will add OS Distribution + Virtualization Breakdown panels.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`emit()` function** (in `_common.sh` and `odin.sh`) — already exports correctly via `export -f emit`. New `emit_host_info()` calls `emit "type=odin_host_info ..."` with the 13 fields concatenated as `key=value` pairs.
- **`get_timestamp()` function** (in `_common.sh`) — provides ISO 8601 UTC timestamp for the host_info event envelope.
- **`get_epoch_ms()` function** (in `odin.sh` lines 60-64) — pattern for "GNU vs BSD detection at startup, define different function bodies". Can mirror this approach for `systemd-detect-virt` vs fallback chain.
- **`safe_val()` pattern** (in modules) — already-established pattern for quoting values containing spaces. host_info `os_pretty` field will need this (e.g., "Rocky Linux 9.3 (Blue Onyx)" has spaces).

### Established Patterns
- **`! declare -f emit` gating** — orchestrator-vs-standalone gate. host_info detection helpers don't need this gate since they're only called from orchestrator (not from modules), but the helper file IS sourced by modules so we shouldn't break the existing gate.
- **`${VAR:-default}` parameter expansion** — used throughout `_common.sh` for env-var-aware defaults. Use same pattern for any per-field detection that supports env-var overrides (e.g., `ODIN_IMDS_TIMEOUT="${ODIN_IMDS_TIMEOUT:-1}"`).
- **`timeout` command wrapping** — used by orchestrator for module timeouts. Use the same idiom for IMDS probes: `timeout 1 curl -s ...`.

### Integration Points
- **Orchestrator emit-host-info call site:** between line 99 (`emit "type=odin_start ..."`) and line 102 (root warning emits). Specifically: insert `emit_host_info` call as new line 100, before the root warning emits, so host_info appears as line 2 of orchestrator output (per Phase 7 success criterion #3 in ROADMAP).
- **`_common.sh` sourced by modules:** when modules call into helpers from `_common.sh` standalone, the new host_info helpers are visible too — but they should NEVER be called from modules (host_info is orchestrator-only). Document this in `_common.sh` header.

### Creative Options
- **`probe_cloud_imds()` could return a single pipe-separated string** like `aws|eu-north-1` — orchestrator splits on `|` to populate two fields. Alternative: function sets two global vars (`ODIN_CLOUD_PROVIDER`, `ODIN_CLOUD_REGION`). Pipe-separated is more functional, no global-state side-effects.
- **`detect_virt()` could be one function with internal cascading**, OR three separate functions (`detect_virt_systemd`, `detect_virt_dmi`, `detect_virt_cgroup`) called in a wrapper. Latter is more testable in isolation.

</code_context>

<specifics>
## Specific Ideas

User explicitly emphasized "ikke ødelegg det vi har laget" — additive-only principle. This means:
- No refactoring of existing `emit()`, `get_timestamp()`, or modules
- New functions extend `_common.sh` without modifying existing functions
- Orchestrator gets ONE new emit call, no other restructuring
- Existing regression suite (HARD-01, PROD-01, HARD-07, PROD-05, windows-parity-harness) MUST stay green

User selected my recommended option for all 4 gray areas (A1, B1, C1, D1) without override — strong signal of trust in conservative defaults. Planner should default to conservative implementation choices for any sub-decisions Claude has discretion on.

</specifics>

<deferred>
## Deferred Ideas

### Reviewed Todos (not folded)
None — no todos cross-referenced this phase's scope.

### Discussion-Surfaced Defers
- **Container runtime detection at host_info level** (mentioned during Area D discussion) — deferred to v1.1.0 per `.planning/seeds/v1.1.0-container-observability.md`. v1.1.0 adds `container_runtime`, `container_id`, `container_image_hint` fields to host_info; this v1.0.2 phase keeps `virtualization=container` as the only container indicator.
- **Caching of IMDS detection across runs** (mentioned during Area B discussion) — deferred. Would require cache file location decision, invalidation logic, and breaks "every scan emits authoritative data" principle. Revisit if scan interval drops below 1 hour.
- **Fleet broken-down-by-container_runtime dashboard panel** (mentioned during Area D discussion) — deferred to v1.1.0. v1.0.2 Phase 9 dashboards will show `virtualization` breakdown only.
- **Per-cloud asset metadata** (AWS Tags, GCP Labels, Azure tags, IAM roles) — explicitly deferred to v1.1.0 Phase 4 (optional).

</deferred>

---

*Phase: 07-host-info-linux*
*Context gathered: 2026-04-28*
