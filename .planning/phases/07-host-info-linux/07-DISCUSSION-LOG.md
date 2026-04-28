# Phase 7: Host Info — Linux - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-28
**Phase:** 07-host-info-linux
**Areas discussed:** Helper function placement, IMDS probe strategy, Field error handling, Virtualization granularity

**Pre-discussion context:** This phase had unusually rich pre-context from `.planning/seeds/v1.0.2-host-metadata-enrichment.md` (planted 2026-04-27 during /gsd-explore session). The seed locked: 13-field event shape, `type=odin_host_info` event name, event positioning (between odin_start and first module), 2s IMDS timeout intent, per-field detection methods. The 4 gray areas below are HOW questions that the seed did not pre-answer.

---

## Area A — Helper Function Placement

**Question:** Where does the OS/HW/network/cloud detection helper code live?

| Option | Description | Selected |
|---|---|---|
| A1 — Extend `_common.sh` | Add helpers to existing 59-line shared lib (grows to ~250 lines). Mirrors PROD-07d single-shared-lib pattern. | ✓ |
| A2 — New `bin/modules/_host_info.sh` | Separate `_`-prefixed file sourced by orchestrator. Keeps `_common.sh` focused on emit/get_timestamp. | |
| A3 — New `bin/lib/host_info.sh` | New `bin/lib/` directory. Cleanest separation but introduces new structural pattern. | |
| A4 — Inline in `odin.sh` | All helpers directly in orchestrator. Bloats from 162 → ~400 lines. | |

**User's choice:** A1
**Notes:** Aligns with established PROD-07d shared-lib pattern. Phase 8 (Windows) gets trivial parity by mirroring `_common.ps1`. No new directory structure. Per-module isolation harness from Plan 05-01 still works.

---

## Area B — IMDS Probe Strategy

**Question:** How do we balance latency vs cloud-detection coverage?

| Option | Description | Selected |
|---|---|---|
| B1 — Sequential 1s × 3 (AWS→GCP→Azure) | Worst case 3s for non-cloud hosts. Deterministic order. Pure sequential bash. | ✓ |
| B2 — Sequential 2s × 3 | Strict reading of seed's "2s timeout". Worst case 6s for non-cloud. More margin for slow hosts. | |
| B3 — Parallel (all three at once) | Worst case ~1-2s. Requires `&` + `wait` + temp files + race-handling. Faster but more complex. | |
| B4 — Heuristic-skip (DMI vendor first) | Check `/sys/class/dmi/id/sys_vendor` for "Amazon"/"Google"/"Microsoft" → probe matching cloud only. Fastest but edge-case-sensitive. | |

**User's choice:** B1
**Notes:** 1s timeout is plenty for link-local IMDS endpoints (response in <100ms when present). 3s worst case is trivial for 30-day scan interval. No temp files, no race conditions, no cleanup logic. Easier to unit-test (mock one endpoint at a time).

---

## Area C — Field Error Handling Convention

**Question:** What value does a field emit when detection fails?

| Option | Description | Selected |
|---|---|---|
| C1 — All-strings sentinel (`unknown`/`none`) | Every field is a string. `unknown`=detection failed, `none`=semantic null (not on cloud, no route). Numeric fields ALSO emit as string on failure. | ✓ |
| C2 — Mixed type-aware sentinel | Strings get `unknown`, numbers get `-1`. Splunk numeric queries work directly but need `\| where cpu_cores > 0` filter. | |
| C3 — Omit failed fields | Skip the field entirely from event line. `isnotnull()` filter in Splunk. Loses "detection was attempted" signal. | |
| C4 — Always-populated with degraded fallbacks | Use unqualified hostname for fqdn, 0.0.0.0 for ip_primary, etc. No "unknown" anywhere. Masks detection failures. | |

**User's choice:** C1
**Notes:** Simplest mental model — every field always populated. Clear semantic distinction between system-failure (`unknown`) and semantic-null (`none`). Matches Phase 1 modules' `none_found` sentinel pattern. Forces dashboard authors to handle degraded case explicitly. Trade-off: Splunk numeric queries need `| convert num(cpu_cores)` first (which naturally skips "unknown" rows).

---

## Area D — Virtualization Field Granularity

**Question:** Single field vs composite for virtualization detection?

| Option | Description | Selected |
|---|---|---|
| D1 — Single field, 6-value enum | `virtualization=baremetal\|kvm\|vmware\|hyperv\|xen\|container\|unknown`. Container-runtime detail belongs in v1.1.0 per-container events. | ✓ |
| D2 — Two fields (virt + container_runtime) | Adds 14th field. `virtualization=container container_runtime=docker`. Mer detaljert men utvider seed-scopen. | |
| D3 — Single field with namespace separator | `virtualization=container:docker`. Needs Splunk eval/rex to extract sub-info. Awkward downstream. | |
| D4 — Triple field (+ container_id) | Most info but `container_id` is high-cardinality identifier — bad for `\| stats by`. Belongs in per-container events. | |

**User's choice:** D1
**Notes:** Keeps strict 13-field count from seed (no scope creep). Container-runtime detail comes naturally in v1.1.0's per-container events. `| stats count by virtualization` gives immediate fleet breakdown. systemd-detect-virt is primary detection; dmidecode + cgroup inspection are fallbacks.

---

## Claude's Discretion

The following sub-decisions were NOT user-locked and are deferred to planning/execution:

- Internal helper function naming convention (camelCase vs snake_case — follow existing `_common.sh` style)
- Order within `detect_virt()` fallback chain (after systemd-detect-virt, dmidecode then cgroup OR cgroup then dmidecode)
- `probe_cloud_imds()` return format (pipe-separated string vs setting two global vars)
- Test fixture format for IMDS mocking (PATH-stub for curl OR env-var response injection)
- Exact error message format inside `unknown` sentinel value

## Deferred Ideas

Surfaced during discussion but explicitly deferred to other phases/milestones:

- **Container runtime detection at host_info level** (Area D adjacent) — deferred to v1.1.0 per existing seed
- **Caching IMDS detection across runs** (Area B adjacent) — deferred, would break "authoritative data per scan" principle
- **Fleet-by-container_runtime dashboard panel** (Area D adjacent) — deferred to v1.1.0
- **Per-cloud asset metadata** (Tags, Labels, IAM roles) — explicitly deferred to v1.1.0 Phase 4 optional

## Discussion Pattern Observation

User selected the recommended option (`A1`, `B1`, `C1`, `D1`) for ALL 4 areas without override. Strong signal of trust in conservative defaults. Planner should default to conservative implementation choices for sub-decisions in Claude's discretion.
