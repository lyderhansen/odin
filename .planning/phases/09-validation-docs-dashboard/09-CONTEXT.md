# Phase 9: Validation + Docs + Dashboard - Context

**Gathered:** 2026-04-29
**Status:** Ready for planning
**Source:** /gsd-discuss-phase 9 (3 Phase 9-specific gray areas)

<domain>
## Phase Boundary

Close out v1.0.2 milestone with three deliverables: (1) cross-platform parity validation that automatically catches Linux+Windows divergence in `type=odin_host_info` field-set, (2) DATA-DICTIONARY documentation for the new event type so Splunk admins can author searches/dashboards/alerts, (3) two new dashboard panels that surface the new metadata so operators can see fleet OS distribution and virtualization breakdown.

Multi-requirement phase (3 reqs: HOST-03/HOST-04/HOST-05) — distinct from Phase 7+8's single-requirement structure. Likely 1-3 plans depending on dependency analysis.

**Scope:** TA-ODIN forwarder (regression test only) + ODIN_app_for_splunk (DATA-DICTIONARY + dashboard) + tools/tests (new parity script). Two-app split honored — no orchestrator changes (Phase 7+8 already complete).
</domain>

<decisions>
## Implementation Decisions

### Inherited from Phase 7+8 (LOCKED — do not re-litigate)

These flow into Phase 9 unchanged via the established v1.0.2 contract.

- **D-01..D-07 (Phase 7+8 inheritance):** All 13 fields, sentinel discipline, virtualization enum, IMDS strategy, helper placement, CIM-only, PSCL graceful — Phase 9 documents and validates these but does NOT modify them.
- **HARD-01 invariant:** Cross-platform parity (Linux + Windows produce same field set, modulo platform-specific values).
- **Two-app split:** Phase 9 dashboard work belongs to ODIN_app_for_splunk (NOT TA-ODIN forwarder); regression test belongs to tools/tests/.
- **DATA-DICTIONARY format:** Existing `## type=X` sections per event type (established v1.0.0). New section follows same template.
- **Dashboard format:** Dashboard Studio v2 JSON (existing odin_overview.xml uses `<dashboard version="2">` with embedded JSON `<definition>` block). NOT Simple XML.

### Pre-locked from ROADMAP success criteria (NOT discussed)

- **Dashboard panel count:** Exactly 2 new panels per HOST-05 acceptance — (a) "OS Distribution" showing `count by os_distro,os_version` from latest type=odin_host_info per host, (b) "Virtualization Breakdown" showing `count by virtualization`.
- **AppInspect baseline preserved:** failure=0, error=0, warning=0 after dashboard changes. Saved as `.planning/artifacts/appinspect/odin-app-1.0.2-phase9.json`.
- **UAT cycle:** `/gsd-verify-work 9` passes with all 5 v1.0.2 requirements (HOST-01..HOST-05) marked DONE before milestone tag.

### Phase 9-specific decisions (this discussion)

#### D-08 — Parity test: new dedicated script (HOST-03)

**Decision:** Create new file `tools/tests/check-host-info-parity.sh`. Standalone single-purpose test that reads both Linux + Windows orchestrator output, extracts `type=odin_host_info` line from each, diffs the field-set (field names, NOT values — values are platform-specific), exits 0 on parity, exits 1 on divergence.

**Rationale:**
- Mirrors existing convention: `check-host-info.sh` (HOST-01), `check-version-sync.sh` (HARD-01), `check-two-app-split.sh` (HARD-07) — all standalone single-purpose scripts.
- Easier to run independently during development (`bash check-host-info-parity.sh`).
- Cleaner CI output — one focused test name vs nested dimension within harness.
- `windows-parity-harness.sh` is already 200+ lines covering 6 dimensions; adding HOST-03 there would mix concerns (per-module field parity vs orchestrator-event parity).

**File location:** `tools/tests/check-host-info-parity.sh`. Name uses `parity` suffix for grep convenience (`grep -l parity tools/tests/`). Token convention: `[HOST-03 PASS/FAIL/SKIP]` per existing pattern.

#### D-09 — Parity test execution: LIVE mode (both orchestrators)

**Decision:** Parity test runs both orchestrators live: `bash TA-ODIN/bin/odin.sh` and `pwsh TA-ODIN/bin/odin.ps1`, captures stdout, extracts `type=odin_host_info` event from each, diffs the field-set.

**Rationale:**
- Most realistic — catches regressions in actual runtime behavior (e.g., if Phase 8 helper accidentally drops a field, fixture test wouldn't catch it).
- macOS dev env already has pwsh 7.5.4 (verified during Phase 8 execution).
- CI Linux runners need pwsh installed (`apt install -y powershell` or use `mcr.microsoft.com/powershell:latest` Docker image). One-time CI investment.
- D-07's PSCL graceful degradation means the Windows side returns "unknown" cleanly on macOS where CIM is unavailable — field NAMES still match Linux side, which is what parity test validates. Field VALUES differ by design (Linux=real values, macOS-pwsh=mostly "unknown"), so test diffs only field-name set, not values.

**SKIP behavior:** If `pwsh` not available on the runner, exit 0 with `[HOST-03 SKIP] pwsh not found — parity test deferred to environment with PowerShell`. Don't fail loudly — let CI / dev environments self-document.

#### D-10 — DATA-DICTIONARY HOST-04: per-field reference (description + source + example)

**Decision:** New `## type=odin_host_info` section in `DOCS/DATA-DICTIONARY.md` with per-field reference. Each of the 13 fields gets:
- **Description:** What the field represents (1-2 sentences)
- **Source (Linux):** The detection command/file/CIM class used
- **Source (Windows):** The PowerShell mirror command/CIM class used
- **Example:** A realistic value (e.g., `os_distro=rocky` or `virtualization=baremetal`)

Plus an overview paragraph at the top explaining: when the event fires (once per scan, between odin_start and module events), why it exists (fleet classification, dashboard support, v1.1.0 container observability prerequisite), and a worked example event line in the canonical envelope format.

Plus a "Cloud detection timeout semantics" note explaining: D-02/D-05 IMDS budget (1s × 3 = 3-4s worst case), `cloud_provider=none|aws|gcp|azure|unknown` sentinel meanings, why probes are sequential.

**Rationale:**
- Mirrors existing DATA-DICTIONARY format — same depth as `## type=service`, `## type=port`, `## type=package` sections.
- Matches HOST-04 acceptance verbatim ("descriptive overview, complete 13-field reference (description + source + example value per field), one worked example event line in the canonical envelope format, and a note on cloud-detection timeout semantics").
- Splunk SPL examples per field (option B) deferred — more maintenance overhead, not in v1.0.2 scope.

**Estimated section size:** ~120 lines (overview ~20 + field reference ~80 + worked example ~10 + cloud timeout note ~10).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative source
- `.planning/phases/09-validation-docs-dashboard/09-CONTEXT.md` — this file (D-08..D-10 + inherited)
- `.planning/phases/07-host-info-linux/07-CONTEXT.md` — Phase 7 D-01..D-04 (Linux implementation contract)
- `.planning/phases/08-host-info-windows/08-CONTEXT.md` — Phase 8 D-05..D-07 (Windows implementation contract)
- `.planning/phases/07-host-info-linux/07-01-SUMMARY.md` — Phase 7 implementation summary
- `.planning/phases/08-host-info-windows/08-01-SUMMARY.md` — Phase 8 implementation summary

### Acceptance criteria + field shape
- `.planning/REQUIREMENTS.md` § "v1.0.2 Requirements" — HOST-03, HOST-04, HOST-05 acceptance text
- `.planning/ROADMAP.md` § "Phase 9: Validation + Docs + Dashboard" — 5 success criteria
- `.planning/seeds/v1.0.2-host-metadata-enrichment.md` — 13-field detection methods table (referenced by D-10 docs)

### Existing artifacts to mirror/extend
- `DOCS/DATA-DICTIONARY.md` — existing format reference; new `## type=odin_host_info` section appends here (probably after the existing `## type=odin_start` section to maintain orchestrator-event grouping)
- `tools/tests/check-host-info.sh` — Linux regression test pattern; new parity test mirrors structure
- `tools/tests/windows-parity-harness.sh` — existing 6-dimension harness; D-08 chose NOT to extend, but the file is reference for token convention `[HARD-XX PASS/FAIL/SKIP]`
- `tools/tests/check-version-sync.sh` — single-purpose test pattern reference
- `tools/tests/check-two-app-split.sh` — single-purpose test pattern reference
- `ODIN_app_for_splunk/default/data/ui/views/odin_overview.xml` — Dashboard Studio v2 JSON format; new panels added to existing `<definition>` block
- `ODIN_app_for_splunk/default/data/ui/views/odin_ops.xml` — sibling dashboard for reference

### Source files Phase 9 DOES NOT modify
- `TA-ODIN/bin/modules/_common.sh` — Phase 7 work, frozen
- `TA-ODIN/bin/modules/_common.ps1` — Phase 8 work, frozen
- `TA-ODIN/bin/odin.sh` / `odin.ps1` — orchestrators, frozen
- `tools/tests/check-host-info.sh` / `.ps1` — Phase 7+8 tests, frozen

### Splunk skill resources
- `splunk-dashboard-studio` skill — reference for Dashboard Studio v2 JSON syntax (planner can invoke for HOST-05 panel construction)
- `splunk-spl-syntax` skill — reference for SPL gotchas in panel queries

</canonical_refs>

<specifics>
## Specific Ideas

### HOST-03 parity test structure (`check-host-info-parity.sh`)

```bash
#!/usr/bin/env bash
# tools/tests/check-host-info-parity.sh — HOST-03
# Verifies Linux + Windows orchestrators emit type=odin_host_info with same field-set.
# Exit 0 on parity, exit 1 on divergence. Exit 0 with SKIP if pwsh unavailable.

set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0

# --- pwsh availability check ---
if ! command -v pwsh >/dev/null 2>&1; then
    echo "[HOST-03 SKIP] pwsh not found — parity test deferred to environment with PowerShell"
    exit 0
fi

# --- Run both orchestrators and extract type=odin_host_info ---
linux_out=$(bash "$REPO_ROOT/TA-ODIN/bin/odin.sh" 2>&1)
windows_out=$(pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass \
    -File "$REPO_ROOT/TA-ODIN/bin/odin.ps1" 2>&1)

linux_event=$(echo "$linux_out" | grep 'type=odin_host_info' | head -1)
windows_event=$(echo "$windows_out" | grep 'type=odin_host_info' | head -1)

# --- Extract field NAMES (not values) ---
linux_fields=$(echo "$linux_event" | grep -oE '[a-z_]+=' | sort -u)
windows_fields=$(echo "$windows_event" | grep -oE '[a-z_]+=' | sort -u)

# --- Diff field sets ---
diff_out=$(diff <(echo "$linux_fields") <(echo "$windows_fields"))
if [[ -z "$diff_out" ]]; then
    echo "[HOST-03 PASS] Linux + Windows field-set parity confirmed (13 fields each)"
else
    echo "[HOST-03 FAIL] Linux/Windows field-set divergence:"
    echo "$diff_out"
    fail=1
fi

exit $fail
```

### HOST-04 DATA-DICTIONARY section structure

```markdown
## type=odin_host_info

Fires once per orchestrator invocation, immediately after `type=odin_start` and
before any module events. Provides rich host metadata for fleet classification:
OS distribution, hardware profile, network identity, virtualization, and
cloud-provider detection.

[Why this exists: Splunk dashboards need to filter/group hosts by attributes
beyond `os=linux|windows`. Foundational prerequisite for v1.1.0 container
observability — `virtualization=container` field hints whether host runs
INSIDE a container.]

### Worked example

```
timestamp=2026-04-29T10:00:00Z hostname=web01.prod.example.com os=linux run_id=1740100800-1234 odin_version=1.0.2 type=odin_host_info os_distro=rocky os_version=9.3 os_pretty="Rocky Linux 9.3 (Blue Onyx)" os_kernel=5.14.0-362.el9.x86_64 os_arch=x86_64 cpu_cores=8 mem_total_mb=16384 uptime_seconds=432000 fqdn=web01.prod.example.com ip_primary=10.0.5.123 virtualization=kvm cloud_provider=aws cloud_region=eu-north-1
```

### Fields

#### `os_distro`
- **Description:** OS family identifier — `rocky`, `ubuntu`, `debian`, `windows`, `alpine`, etc.
- **Source (Linux):** parse `/etc/os-release` `ID=` field
- **Source (Windows):** hardcoded `windows` (Win32_OperatingSystem.Caption always starts "Microsoft Windows")
- **Example:** `os_distro=rocky` or `os_distro=windows`

[... 12 more fields with same structure ...]

### Cloud detection timeout semantics

The `cloud_provider` and `cloud_region` fields use sequential AWS→GCP→Azure
IMDS probing with a 1-second timeout per probe (decisions D-02 + D-05).
Worst-case latency on a non-cloud host is 3-4 seconds (AWS IMDSv2 makes 2
sequential calls — token PUT + region GET — so AWS alone can take up to 2s
when the token endpoint accepts but region times out).

Sentinel values:
- `cloud_provider=none`: All three IMDS probes failed (host is not in AWS/GCP/Azure or has no link-local routing). `cloud_region=none` accompanies.
- `cloud_provider=aws|gcp|azure`: Probe succeeded. `cloud_region` is the detected region (e.g., `eu-north-1`, `europe-west1`, `eastus`).
- `cloud_provider=unknown`: Detection raised an exception (CIM unavailable in PSCL, or `curl` not installed). `cloud_region=unknown` accompanies.
```

### HOST-05 dashboard panels (Dashboard Studio v2 JSON)

Two panels added to `odin_overview.xml`'s existing `<definition>` JSON block:

**Panel 1: OS Distribution**
- Type: `splunk.pie` or `splunk.column`
- Data source: latest type=odin_host_info per host, group by os_distro,os_version
- SPL: `index=odin_discovery sourcetype=odin:enumeration type=odin_host_info | dedup hostname | stats count by os_distro, os_version | sort - count`

**Panel 2: Virtualization Breakdown**
- Type: `splunk.column` or `splunk.bar`
- Data source: latest type=odin_host_info per host, group by virtualization
- SPL: `index=odin_discovery sourcetype=odin:enumeration type=odin_host_info | dedup hostname | stats count by virtualization | sort - count`

Both panels use existing `ds_base` data source pattern from current dashboard. Layout: add to grid in a free row.

</specifics>

<deferred>
## Deferred Ideas

These were surfaced but explicitly deferred:

- **Splunk SPL examples per field in DATA-DICTIONARY** — defer to v1.0.3 docs polish phase. Adds maintenance burden, not in HOST-04 acceptance.
- **Additional dashboard panels beyond required 2** (Cloud Provider, Memory Distribution, etc) — defer to v1.0.3 dashboard expansion. HOST-05 specifies "at least 2", v1.0.2 ships exactly 2 to keep scope tight.
- **Replace odin_overview.xml entirely with new design** — defer; we add panels to existing dashboard, not redesign.
- **Add type=odin_host_info to odin_ops.xml as well** — defer; HOST-05 specifies odin_overview.xml only.
- **Live parity test integration into windows-parity-harness.sh as Dimension 7** — D-08 chose dedicated script, but a future cleanup phase could optionally invoke check-host-info-parity.sh from within harness for unified CI run.
- **Performance regression test (IMDS budget timing assertion)** — informally verified during Phase 7+8 ad-hoc; formal automated assertion deferred to v1.0.3 monitoring/observability phase.

---

*Phase: 09-validation-docs-dashboard*
*Context gathered: 2026-04-29 via /gsd-discuss-phase 9*
*3 Phase 9-specific decisions captured (D-08..D-10); 7 inherited from Phase 7+8 (D-01..D-07)*
</deferred>
