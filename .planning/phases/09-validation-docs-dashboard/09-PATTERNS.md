# Phase 9: Validation + Docs + Dashboard - Pattern Map

**Mapped:** 2026-04-29
**Files analyzed:** 3 (1 new test script, 2 modified documents)
**Analogs found:** 3 / 3 — all in-repo, no synthetic patterns needed

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `tools/tests/check-host-info-parity.sh` (NEW) | test / regression guard | exec → grep → diff → assert | `tools/tests/check-host-info.sh` (100 lines, 5 checks, set -u, REPO_ROOT, fail accumulator) | exact — same single-purpose test structure, different assertion content |
| `DOCS/DATA-DICTIONARY.md` (MODIFIED — add section) | documentation | read-only reference extension | `DOCS/DATA-DICTIONARY.md` `## type=odin_start` section (orchestrator-event peer) + `## type=service` (depth reference) | exact — append new `## type=odin_host_info` section following same template |
| `ODIN_app_for_splunk/default/data/ui/views/odin_overview.xml` (MODIFIED — add 2 panels) | dashboard | query → visualization | `odin_overview.xml` existing `ds_role_dist` / `viz_role_dist` pair (pie chart) and `ds_logsource_count` / `viz_logsource_count` pair (column chart) | exact — add 2 new dataSources + 2 new visualizations + 2 new layout blocks |

---

## Pattern Assignments

### `tools/tests/check-host-info-parity.sh` (NEW — test, exec-grep-diff-assert)

**Primary analog:** `tools/tests/check-host-info.sh` (lines 1–100) — exact same single-purpose test structure.
**Secondary analog:** `tools/tests/windows-parity-harness.sh` lines 122–137 — both-orchestrators invocation pattern.
**Tertiary analog:** `tools/tests/check-two-app-split.sh` lines 1–22 + 39 — minimal header + REPO_ROOT pattern.

---

#### Pattern 1 — File header + set -u + fail accumulator + REPO_ROOT discovery

**Source:** `tools/tests/check-host-info.sh` lines 1–23:

```bash
#!/usr/bin/env bash
# tools/tests/check-host-info.sh — HOST-01
#
# Verifies Phase 7 / HOST-01 success criteria:
#   1. Exactly ONE type=odin_host_info event per scan
#   ...
# Exit 0 when all checks pass, non-zero otherwise.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0

# --- Run the orchestrator and capture output ---
out=$(bash "$REPO_ROOT/TA-ODIN/bin/odin.sh" 2>&1)
```

**Apply to HOST-03 parity test:** Same shape. Change comment to HOST-03. Add pwsh availability check BEFORE running either orchestrator.

```bash
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
```

---

#### Pattern 2 — SKIP guard for unavailable dependency

**Source:** Implicit convention from `check-host-info.ps1` lines 21–24 (OS guard → exit 0) and `check-host-info.sh` lines 65–78 (empty event guard → SKIP token, not FAIL).

**Apply to HOST-03:** pwsh availability check as the first thing after variable setup:

```bash
# --- pwsh availability check ---
if ! command -v pwsh >/dev/null 2>&1; then
    echo "[HOST-03 SKIP] pwsh not found — parity test deferred to environment with PowerShell"
    exit 0
fi
```

**Token convention:** `[HOST-03 SKIP]` matches sibling test convention: `[HOST-01 SKIP]` (check-host-info.sh lines 77, 94), `[HOST-02 SKIP]` (check-host-info.ps1 lines 23, 56, 85, 100). Exit 0 on SKIP (not 1) — CI does not fail when prereq is absent.

---

#### Pattern 3 — Both-orchestrators live invocation

**Source:** `tools/tests/windows-parity-harness.sh` lines 122–127 (Dimension 4 — Windows invocation) combined with `tools/tests/check-host-info.sh` line 23 (Linux invocation):

```bash
# Dimension 4, windows-parity-harness.sh lines 122-127 — Windows invocation:
out=$(ODIN_TEST_FIXTURE="$FIXTURE_DIR" pwsh -NoProfile -NonInteractive -File TA-ODIN/bin/odin.ps1 2>&1)

# check-host-info.sh line 23 — Linux invocation:
out=$(bash "$REPO_ROOT/TA-ODIN/bin/odin.sh" 2>&1)
```

**Apply to HOST-03 parity test:** Run both live (D-09 — no fixture, no mocking):

```bash
# --- Run both orchestrators live and capture stdout ---
linux_out=$(bash "$REPO_ROOT/TA-ODIN/bin/odin.sh" 2>&1)
windows_out=$(pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass \
    -File "$REPO_ROOT/TA-ODIN/bin/odin.ps1" 2>&1)
```

**Note:** Do NOT pass `ODIN_TEST_FIXTURE` — the parity test is explicitly live mode (D-09). The windows-parity-harness uses fixtures for reproducibility; HOST-03 uses live execution to catch runtime regressions.

---

#### Pattern 4 — Extract type=odin_host_info line and diff field-name set

**Source:** `tools/tests/check-host-info.sh` lines 39, 66–67 (field extraction):

```bash
host_info_line=$(echo "$out" | grep 'type=odin_host_info' | head -1)
virt_val=$(echo "$host_info_line" | grep -oE 'virtualization=[^ ]+' | cut -d= -f2)
```

**Source:** `tools/tests/windows-parity-harness.sh` lines 163–177 (`extract_field_names` function):

```bash
extract_field_names() {
    local line="$1"
    local prelude='timestamp|hostname|os|run_id|odin_version'
    local stripped
    stripped=$(echo "$line" | sed -E 's/="[^"]*"/=/g')
    echo "$stripped" \
        | tr ' ' '\n' \
        | awk -F= 'NF>0 {print $1}' \
        | grep -vE "^($prelude)$" \
        | grep -vE '^$' \
        | sort -u
}
```

**Apply to HOST-03:** Extract field names from each platform's odin_host_info line and diff them:

```bash
# --- Extract type=odin_host_info event from each orchestrator ---
linux_event=$(echo "$linux_out" | grep 'type=odin_host_info' | head -1)
windows_event=$(echo "$windows_out" | grep 'type=odin_host_info' | head -1)

# --- Guard: check both events are present before diffing ---
if [[ -z "$linux_event" ]]; then
    echo "[HOST-03 FAIL] Linux orchestrator emitted no type=odin_host_info event"
    fail=1
fi
if [[ -z "$windows_event" ]]; then
    echo "[HOST-03 FAIL] Windows orchestrator emitted no type=odin_host_info event"
    fail=1
fi

# --- Extract field NAMES only (not values — values differ by platform per D-09) ---
linux_fields=$(echo "$linux_event"  | grep -oE '[a-z_]+=' | sed 's/=$//' | sort -u)
windows_fields=$(echo "$windows_event" | grep -oE '[a-z_]+=' | sed 's/=$//' | sort -u)

# --- Diff field-name sets ---
diff_out=$(diff <(echo "$linux_fields") <(echo "$windows_fields"))
if [[ -z "$diff_out" ]]; then
    echo "[HOST-03 PASS] Linux + Windows field-set parity confirmed (13 fields each)"
else
    echo "[HOST-03 FAIL] Linux/Windows field-set divergence detected:"
    echo "$diff_out"
    fail=1
fi

exit $fail
```

---

#### Pattern 5 — PASS/FAIL/SKIP token convention

**Source:** All 4 existing single-purpose tests use consistent token convention:

- `check-version-sync.sh`: `[HARD-01 PASS]`, `[HARD-01 FAIL]`, `[HARD-01 DRIFT]`
- `check-two-app-split.sh`: `[HARD-07 PASS]`, `[HARD-07 FAIL]`
- `check-host-info.sh`: `[HOST-01 PASS]`, `[HOST-01 FAIL]`, `[HOST-01 SKIP]`
- `check-host-info.ps1`: `[HOST-02 PASS]`, `[HOST-02 FAIL]`, `[HOST-02 SKIP]`

**Apply to HOST-03:** Use `[HOST-03 PASS]`, `[HOST-03 FAIL]`, `[HOST-03 SKIP]`. CI can `grep -c 'FAIL'` uniformly across all test scripts.

---

### `DOCS/DATA-DICTIONARY.md` (MODIFIED — append `## type=odin_host_info` section)

**Primary analog:** `DOCS/DATA-DICTIONARY.md` `## type=odin_start` section (lines 40–57) — closest peer: also an orchestrator-level event emitted once per invocation.
**Secondary analog:** `DOCS/DATA-DICTIONARY.md` `## type=service` section (lines 123–143) — most detailed module section: shows per-field format (name, description, note).

---

#### Pattern 1 — Section header and format from `## type=odin_start`

**Source:** `DOCS/DATA-DICTIONARY.md` lines 40–57 (`## type=odin_start`):

```markdown
## type=odin_start

Fires once per orchestrator invocation, immediately after privilege detection and
before the first module dispatch.

**Fields:**

- Common envelope (above)
- `run_as` — username running the orchestrator ...
- `euid` — effective UID (Linux only; omitted on Windows)
- `message` — fixed string `"TA-ODIN enumeration started"`

**Example:**

```
timestamp=2026-04-24T10:00:00Z ... type=odin_start run_as=splunk euid=998 message="TA-ODIN enumeration started"
```
```

**Apply to HOST-04:** Same structural template for `## type=odin_host_info`. Overview paragraph, then D-10's per-field table format (Description + Source Linux + Source Windows + Example), then worked example, then cloud timeout semantics note. Estimated ~120 lines.

---

#### Pattern 2 — Per-field entry depth from `## type=service` and `## type=process`

**Source:** `DOCS/DATA-DICTIONARY.md` lines 123–143 (`## type=service`) — shows field list with hyphen bullets plus contextual notes:

```markdown
**Fields:**

- Common envelope
- `service_name` — service identifier (`sshd`, `nginx`, `W3SVC`, `MSSQLSERVER`)
- `service_status` — current state (`running`, `stopped`, `unknown`)
- `service_enabled` — startup mode (`enabled`, `disabled`, `static`, `unknown`)
- `service_path` — service binary path (Windows present, Linux usually absent)
- `service_type` — systemd Type= property (Linux only; e.g., `forking`, `notify`)
```

**Apply to HOST-04 (D-10 format):** Each of the 13 fields needs 4-item entry per D-10. Recommended table format rather than bullet list, since 13 fields × 4 attributes each becomes unreadable as nested bullets. Use sub-section per field OR a Markdown table. The `## type=service` section uses bullet lists; HOST-04's D-10 spec is richer (adds Source Linux + Source Windows columns). Use a table for the 13 fields:

```markdown
### Fields

| Field | Description | Source (Linux) | Source (Windows) | Example |
|---|---|---|---|---|
| `os_distro` | OS family identifier | `/etc/os-release` `ID=` field | hardcoded `windows` | `os_distro=rocky` |
| `os_version` | ... | ... | ... | ... |
```

This mirrors the "Common envelope fields" table at DATA-DICTIONARY.md lines 29–37 which already uses `| Field | Example | Description |` format. Extend to 5 columns for per-platform sources.

---

#### Pattern 3 — Insertion point: after `## type=odin_start` (line 40), before `## type=odin_complete` (line 59)

**Finding:** The DATA-DICTIONARY.md has these section headers in order:
1. `## Cross-platform parity` (line 8)
2. `## Common envelope fields` (line 23)
3. `## type=odin_start` (line 40)
4. `## type=odin_complete` (line 59)
5. `## type=odin_error` (line 83)
6. `## type=truncated` (line 104)
7. `## type=service` (line 123)
...

**Decision:** Insert `## type=odin_host_info` AFTER `## type=odin_start` and BEFORE `## type=odin_complete`. Rationale: `type=odin_host_info` is an orchestrator-level event (not a module event), fires between `odin_start` and module events, so the doc ordering should mirror execution ordering. This keeps the orchestrator-event cluster together (start → host_info → complete → error → truncated) before the module events (service, port, package, ...).

The planner's insertion instruction should be: "Add the new section beginning at line 59 (before `## type=odin_complete`), shifting subsequent sections down."

---

#### Pattern 4 — Cross-platform note pattern from `## type=service`

**Source:** `DOCS/DATA-DICTIONARY.md` lines 125–128 (emission sources for `type=service`):

```markdown
Emitted by `services.sh` (Linux: `systemctl show` batch query, with SysV init and
`/etc/init.d/` fallbacks) and `services.ps1` (Windows: `Get-Service` plus
`Get-CimInstance Win32_Service` for start mode and image path). Identical field names
per WIN-08 — same field set used regardless of source OS.
```

**Apply to HOST-04:** The `## type=odin_host_info` overview paragraph should follow the same pattern — name both orchestrators, state where the event is emitted, and call out the cross-platform parity contract (HARD-01):

```markdown
## type=odin_host_info

Fires exactly once per orchestrator invocation, immediately after `type=odin_start`
and before any module events (event #2 in output order). Emitted by `odin.sh` (Linux)
and `odin.ps1` (Windows). Provides rich host metadata for fleet classification: OS
distribution, hardware profile, network identity, virtualization type, and
cloud-provider detection.

Cross-platform parity: both orchestrators emit identical field names (13 fields,
HARD-01 contract). Field VALUES differ by platform (e.g., `os_distro=rocky` vs
`os_distro=windows`); field NAMES are identical. Validated by `check-host-info-parity.sh`.
```

---

### `ODIN_app_for_splunk/default/data/ui/views/odin_overview.xml` (MODIFIED — add 2 panels)

**Analog:** `odin_overview.xml` itself — the existing `ds_role_dist` / `viz_role_dist` pair (pie) and `ds_logsource_count` / `viz_logsource_count` pair (column chart) are the closest structural models.

---

#### Critical findings from reading odin_overview.xml

**Existing viz count:** The current dashboard has **10 visualizations** in `"visualizations"`:
1. `viz_sv_hosts` — singlevalue
2. `viz_sv_roles` — singlevalue
3. `viz_sv_logsources` — singlevalue
4. `viz_sv_tas` — singlevalue
5. `viz_roles_per_host` — column
6. `viz_role_dist` — pie
7. `viz_ta_matrix` — table
8. `viz_logsource_count` — column
9. `viz_host_inventory` — table
10. `viz_log_details` — table

**HOST-05 verify target:** "increases by ≥2 vs the v1.0.1-rc1 baseline." Current count = 10. After Phase 9: target ≥ 12. Adding exactly 2 new panels lands at 12. PASS.

**Grid layout — last item position:** The existing layout ends at:
```json
{"item": "viz_log_details", "type": "block", "position": {"x": 0, "y": 1480, "w": 1200, "h": 400}}
```
Last y + h = 1480 + 400 = 1880. The 2 new panels go at `y: 1880` and `y: 2180` (assuming ~300px height each). Full-width (w: 1200) matches the existing bottom-panel convention.

**Existing dataSource pattern:** `ds_base` is the root `ds.search`; all other data sources use `ds.chain` extending it. The two new panels will NOT use `ds_base` as their chain parent — they query `type=odin_host_info` events, which is a different event type entirely. They need their own `ds.search` data sources.

**The existing `input_hostname` token `$hostname_filter$`:** The new panels should NOT reference `$hostname_filter$` because `type=odin_host_info` events aggregate across the whole fleet for a distribution chart. Including the filter would break the "fleet-wide OS distribution" semantics. Use `index=odin_discovery ... | dedup hostname` without the hostname filter — or optionally include it for per-host drill-through (planner's call).

**The `defaults.dataSources.ds.search.options.queryParameters` time-range binding:** All `ds.search` sources automatically inherit `"earliest": "$global_time.earliest$", "latest": "$global_time.latest$"`. New data sources will also inherit this — the time range input works for free.

---

#### Pattern 1 — dataSource pattern for new independent search (NOT ds.chain)

**Source:** `odin_overview.xml` lines 9–14 (`ds_base` — standalone ds.search):

```json
"ds_base": {
  "type": "ds.search",
  "name": "Classification Base Search",
  "options": {
    "query": "index=odin_discovery sourcetype=odin:enumeration (type=service OR type=port OR type=package) hostname=\"$hostname_filter$\"\n| eval signal_type=type\n..."
  }
}
```

**Apply to HOST-05 — OS Distribution dataSource:**

```json
"ds_os_dist": {
  "type": "ds.search",
  "name": "OS Distribution",
  "options": {
    "query": "index=odin_discovery sourcetype=odin:enumeration type=odin_host_info\n| dedup hostname\n| stats count by os_distro, os_version\n| sort - count"
  }
},
"ds_virt_dist": {
  "type": "ds.search",
  "name": "Virtualization Breakdown",
  "options": {
    "query": "index=odin_discovery sourcetype=odin:enumeration type=odin_host_info\n| dedup hostname\n| stats count by virtualization\n| sort - count"
  }
}
```

**Why `dedup hostname`:** Gets the latest `type=odin_host_info` event per host (most recent scan wins). This is the standard "latest-event-per-host" pattern — Splunk returns events newest-first within a time range; `dedup hostname` keeps the first (newest) match per hostname.

---

#### Pattern 2 — Column chart visualization (closest to HOST-05 panel needs)

**Source:** `odin_overview.xml` lines 193–204 (`viz_logsource_count` — column chart):

```json
"viz_logsource_count": {
  "type": "splunk.column",
  "title": "Log Sources per Host",
  "dataSources": {"primary": "ds_logsource_count"},
  "options": {
    "seriesColors": ["#00CDAF"],
    "xAxisLabelRotation": -45,
    "yAxisTitleText": "Log Sources",
    "yAxisTitleVisibility": "show",
    "xAxisTitleVisibility": "hide",
    "dataValuesDisplay": "all",
    "legendDisplay": "off"
  }
}
```

**Apply to HOST-05 — OS Distribution panel** (column chart, `os_distro` on x-axis, count on y-axis):

```json
"viz_os_dist": {
  "type": "splunk.column",
  "title": "OS Distribution",
  "dataSources": {"primary": "ds_os_dist"},
  "options": {
    "seriesColors": ["#009CEB"],
    "xAxisLabelRotation": -45,
    "yAxisTitleText": "Hosts",
    "yAxisTitleVisibility": "show",
    "xAxisTitleVisibility": "hide",
    "dataValuesDisplay": "all",
    "legendDisplay": "off"
  }
}
```

---

#### Pattern 3 — Pie chart visualization (for Virtualization Breakdown)

**Source:** `odin_overview.xml` lines 163–169 (`viz_role_dist` — pie chart):

```json
"viz_role_dist": {
  "type": "splunk.pie",
  "title": "Hosts per Role",
  "dataSources": {"primary": "ds_role_dist"},
  "options": {
    "labelDisplay": "valuesAndPercentage"
  }
}
```

**Apply to HOST-05 — Virtualization Breakdown panel** (pie chart works well for small enum: baremetal|kvm|vmware|hyperv|xen|container|unknown):

```json
"viz_virt_dist": {
  "type": "splunk.pie",
  "title": "Virtualization Breakdown",
  "dataSources": {"primary": "ds_virt_dist"},
  "options": {
    "labelDisplay": "valuesAndPercentage"
  }
}
```

---

#### Pattern 4 — Grid layout block — insertion at bottom

**Source:** `odin_overview.xml` lines 270–279 (layout.structure — last 4 entries):

```json
{"item": "viz_logsource_count", "type": "block", "position": {"x": 0, "y": 480, "w": 1200, "h": 300}},
{"item": "viz_ta_matrix",       "type": "block", "position": {"x": 0, "y": 780, "w": 1200, "h": 350}},
{"item": "viz_host_inventory",  "type": "block", "position": {"x": 0, "y": 1130, "w": 1200, "h": 350}},
{"item": "viz_log_details",     "type": "block", "position": {"x": 0, "y": 1480, "w": 1200, "h": 400}}
```

**Apply to HOST-05:** Two new rows appended after `viz_log_details`. Each panel is 600px wide, placed side-by-side in one row (OS distribution on left, Virtualization breakdown on right — they fit 600+600=1200):

```json
{"item": "viz_log_details", "type": "block", "position": {"x": 0,   "y": 1480, "w": 1200, "h": 400}},
{"item": "viz_os_dist",     "type": "block", "position": {"x": 0,   "y": 1880, "w": 600,  "h": 350}},
{"item": "viz_virt_dist",   "type": "block", "position": {"x": 600, "y": 1880, "w": 600,  "h": 350}}
```

**Alternative:** Stack them as two separate full-width rows (y: 1880 and y: 2230). Planner can choose; side-by-side is more visually compact and mirrors the `viz_roles_per_host` + `viz_role_dist` pairing at y: 130.

---

#### Pattern 5 — JSON structure: 4 insertion points in the file

The `<definition><![CDATA[...]]></definition>` block contains one JSON object with 4 top-level keys. Phase 9 adds to 2 of them:

| Top-level key | Action | Location |
|---|---|---|
| `"dataSources"` | Add `"ds_os_dist"` and `"ds_virt_dist"` entries | After line 102 (`"ds_log_details"` closing brace), before line 103 (`}` closing dataSources) |
| `"visualizations"` | Add `"viz_os_dist"` and `"viz_virt_dist"` entries | After line 223 (`"viz_log_details"` closing brace), before line 224 (`}` closing visualizations) |
| `"inputs"` | No change | — |
| `"layout".structure` | Add 2 new block objects | After line 279 (`"viz_log_details"` block), before line 280 (`]` closing structure) |

**Critical JSON hygiene:** Each new entry in `dataSources` and `visualizations` needs a comma after the preceding entry's closing `}`. The last entry in each map must NOT have a trailing comma. The planner's edit instruction should be precise about comma placement.

---

## Shared Patterns

### Single-purpose test structure (applies to `check-host-info-parity.sh`)

**Source:** `tools/tests/check-two-app-split.sh` lines 19–21, 38–39:

```bash
set -u    # NOT set -e — all assertions run even if one fails

fail=0    # Accumulate failures; exit $fail at end

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
```

**Apply to ALL test scripts:** `set -u` (not `set -e`), top-level `fail` accumulator, REPO_ROOT relative to BASH_SOURCE[0]. This is the universal test contract in this repo — every single-purpose test uses this shape.

### Token convention `[REQ-ID PASS/FAIL/SKIP]`

**Source:** `check-version-sync.sh` (`[HARD-01 ...]`), `check-two-app-split.sh` (`[HARD-07 ...]`), `check-host-info.sh` (`[HOST-01 ...]`), `check-host-info.ps1` (`[HOST-02 ...]`).

**Apply to HOST-03:** `[HOST-03 PASS]`, `[HOST-03 FAIL]`, `[HOST-03 SKIP]`. SKIP exits 0; FAIL sets fail=1 and exits 1.

### Dashboard Studio v2 JSON conventions (applies to `odin_overview.xml` edits)

**Source:** Entire `odin_overview.xml` `<definition>` block.

Key conventions observed:
1. `"type": "ds.search"` for root searches; `"type": "ds.chain"` for derived searches extending a root
2. New HOST-05 data sources MUST be `"type": "ds.search"` (not `ds.chain`) because they query a different event type than `ds_base`
3. Visualization types in use: `splunk.singlevalue`, `splunk.column`, `splunk.pie`, `splunk.table`. HOST-05 uses `splunk.column` and `splunk.pie` — both already present
4. Time range binding is automatic via `"defaults".dataSources.ds.search` — new data sources inherit it
5. Grid uses absolute pixel coordinates: x=0 is left edge, y increases downward, w+h in px
6. Current grid width = 1200px (all full-width panels use `"w": 1200`)

### DATA-DICTIONARY section format

**Source:** Every `## type=X` section in `DOCS/DATA-DICTIONARY.md`.

Pattern:
1. `## type=<event_type>` — H2 header as discriminator
2. One-paragraph overview: when it fires, which script emits it, platform note
3. `**Fields:**` subsection with bullet list or table
4. `**Example:**` with fenced code block showing a full realistic event line

HOST-04 adds a fifth element: `### Cloud detection timeout semantics` sub-section (D-10 requirement). This is new for this section only — no other section has a sub-section. Acceptable because the IMDS timeout behavior is uniquely complex to this event type.

---

## Critical Constraints Surfaced

### C1 — windows-parity-harness.sh overlap with HOST-03

**Finding:** `windows-parity-harness.sh` Dimension 4 and Dimension 5 DO run the Windows orchestrator live. However:
- Dim 4 counts `type=odin_start`, `type=odin_complete modules_total=6`, and the 6 module event types. The `type=odin_host_info` event will appear in output but Dim 4 does NOT check for it — no assertion conflict.
- Dim 5 diffs per-type field names for 5 types (service, port, package, process, mount) — `type=odin_host_info` is not in the Dim 5 type list. No assertion conflict.
- D-08 decision: HOST-03 is a SEPARATE dedicated script, not a Dimension 7. This was chosen for clean CI output and independence. No deduplication needed.

**Conclusion:** `check-host-info-parity.sh` and `windows-parity-harness.sh` are orthogonal. Harness tests Windows-vs-fixture module parity; HOST-03 tests Linux-vs-Windows orchestrator event parity. Both must stay green after Phase 9.

### C2 — Dashboard viz count baseline

**Finding:** Current `odin_overview.xml` has exactly 10 visualizations (counted from `"visualizations"` key). After Phase 9 adds 2 new panels: count = 12. HOST-05 acceptance requires "≥2 new panels" — adding exactly 2 satisfies this. The verify command `grep -c '"type": "splunk\.'` against the post-Phase-9 file should return 12.

### C3 — DATA-DICTIONARY insertion point

**Finding:** `## type=odin_host_info` MUST be inserted between `## type=odin_start` (line 40) and `## type=odin_complete` (line 59). This maintains execution-order grouping: start → host_info → complete → error → truncated. The planner's edit task is: insert ~120 lines of new Markdown at line 59 (before `## type=odin_complete`).

### C4 — odin_overview.xml dataSource independence

**Finding:** The new HOST-05 data sources (`ds_os_dist`, `ds_virt_dist`) MUST be `"type": "ds.search"` (not `"type": "ds.chain"`) because they query `type=odin_host_info` events, whereas `ds_base` queries `type=service OR type=port OR type=package`. Chaining off `ds_base` would produce empty results. This is a deviation from the existing pattern (most data sources extend `ds_base`) and must be called out explicitly in the plan.

### C5 — JSON comma discipline in odin_overview.xml

**Finding:** The dashboard XML wraps a raw JSON object in CDATA. JSON does not allow trailing commas. When inserting new entries into `"dataSources"`, `"visualizations"`, and `"layout".structure`, the planner must add a comma after each preceding entry's closing brace. The last entry in each map/array must NOT have a trailing comma.

---

## No Analog Found

All 3 Phase 9 files have strong in-repo analogs. No synthetic patterns needed.

The only mildly novel surface is the field-name extraction + diff logic in `check-host-info-parity.sh` (Pattern 4 above) — but `extract_field_names()` in `windows-parity-harness.sh` lines 163–177 provides the exact extraction idiom to copy. The diff itself uses standard POSIX `diff <(...)` process substitution — established Bash idiom with no repo precedent needed.

---

## Plan Structure Recommendation

### Recommendation: 3 separate plans in a single Wave 1

**Rationale:**

The 3 Phase 9 deliverables (HOST-03, HOST-04, HOST-05) have:
- Zero inter-dependencies: none reads or writes the other's output files
- Separate file targets: `tools/tests/` vs `DOCS/` vs `ODIN_app_for_splunk/default/data/ui/views/`
- Different agent skills needed: bash scripting (HOST-03) vs technical writing (HOST-04) vs JSON/SPL (HOST-05)
- Different verification commands: `bash check-host-info-parity.sh` vs markdown lint vs `grep -c '"type": "splunk\.'`

Phase 7+8 used 1 plan per phase because each phase had 1 requirement and tightly coupled files (_common.sh + odin.sh + regression test all in one coherent implementation story). Phase 9 has 3 requirements with NO coupling.

**Proposed structure:**

```
Phase 9 Wave 1 (parallel — no dependencies):
  Plan 09-01: HOST-03 — check-host-info-parity.sh (new test script)
  Plan 09-02: HOST-04 — DATA-DICTIONARY.md addition (docs)
  Plan 09-03: HOST-05 — odin_overview.xml extension (dashboard)

Phase 9 Wave 2 (sequential — depends on all 3 plans passing):
  SUMMARY.md + VERIFICATION pass covering all 5 v1.0.2 requirements (HOST-01..HOST-05)
```

**Counter-argument addressed:** The "1 monolithic plan" option's main appeal is less overhead. But Phase 9's VERIFICATION pass must cover HOST-01..HOST-05 (all 5 v1.0.2 requirements, per 09-CONTEXT.md pre-locked). That cross-cutting verification naturally belongs in a Wave 2 SUMMARY — not in any single plan's local verification block. So Wave 2 is needed regardless. Given Wave 2 exists, Wave 1 parallelism is free.

**Commit strategy per plan:**
- Plan 09-01 commit: `feat(test): HOST-03 cross-platform parity test`
- Plan 09-02 commit: `docs: HOST-04 add type=odin_host_info to DATA-DICTIONARY`
- Plan 09-03 commit: `feat(dashboard): HOST-05 OS distribution + virtualization panels`

---

## Metadata

**Analog search scope:** `tools/tests/`, `DOCS/`, `ODIN_app_for_splunk/default/data/ui/views/`
**Files scanned:** `check-host-info.sh` (100 lines), `check-host-info.ps1` (117 lines), `windows-parity-harness.sh` (325 lines), `check-version-sync.sh` (132 lines), `check-two-app-split.sh` (60 lines), `DATA-DICTIONARY.md` (306 lines), `odin_overview.xml` (284 lines), `07-PATTERNS.md`, `08-PATTERNS.md`
**Pattern extraction date:** 2026-04-29
**Decision compliance check:**
- D-08 (dedicated script, not harness dim): Pattern 1 — standalone check-host-info-parity.sh
- D-09 (live execution, not fixture): Pattern 3 — no ODIN_TEST_FIXTURE
- D-10 (per-field description + source + example): Patterns 1–4 under DATA-DICTIONARY section
- HARD-01 (cross-platform parity invariant): Surfaced in C1 and DATA-DICTIONARY Pattern 4
- Two-app split: dashboard changes in ODIN_app_for_splunk only (not TA-ODIN)
- Dashboard format: Dashboard Studio v2 JSON, NOT Simple XML (confirmed from reading odin_overview.xml)
