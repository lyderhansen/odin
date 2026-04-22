---
phase: 05-operational-readiness
status: complete
gathered: 2026-04-22
mode: inline (parallel bash + Read scout against codebase + savedsearches.conf + dashboard XML)
---

# Phase 5 Research — Operational Readiness

## Critical Finding (changes scope of D1)

**`odin_overview.xml` is ALREADY Dashboard Studio v2.** Empirical scan:

```xml
<dashboard version="2" theme="dark">
  <label>ODIN Host Classification</label>
  <description>Host role classification, log source identification, and TA deployment recommendations</description>
  <definition><![CDATA[
{
  "title": "ODIN Host Classification",
  "dataSources": { "ds_base": { "type": "ds.search", ... } },
  ...
}
]]></definition>
</dashboard>
```

**Implication for D1 (CONTEXT.md):** D1 was based on the assumption that the existing dashboard was Simple XML v1, requiring a "two-frameworks-in-same-app" trade-off discussion. In reality, the existing dashboard is already v2 (Dashboard Studio with JSON definition wrapped in v2 view stanza). The new `odin_ops.xml` simply follows the same v2 pattern — **no mixed-framework concern, no migration deferred**, just one consistent v2 dashboard pattern.

**Same lesson as Phase 4:** scout the codebase BEFORE recommending decisions in discuss-phase. CONTEXT.md D1 should be amended (planner can do this inline or just follow research) to remove the "two frameworks accepted" framing — there is only one framework, v2, used everywhere.

## 1. Dashboard Studio v2 viz components (existing + new needed)

Source: `ODIN_app_for_splunk/default/data/ui/views/odin_overview.xml` empirical scan.

**Already in use (proven to work + AppInspect-clean under Enterprise scope):**

| Viz component | Use case | Example panel |
|---|---|---|
| `splunk.singlevalue` | Single number with optional sparkline + threshold colors | "Total Classified Hosts", "Unclassified Hosts" |
| `splunk.column` | Vertical bar chart | Host count by role |
| `splunk.pie` | Pie chart | Host role distribution |
| `splunk.table` | Tabular results | TA deployment matrix |

**Needed for `odin_ops.xml` per CONTEXT D1 panel set + ROADMAP success criterion 5:**

| Viz component | Use case for ops dashboard |
|---|---|
| `splunk.singlevalue` | Scan success rate per OS (linux + windows), with sparkline trend |
| `splunk.timechart` | Module runtime p50/p95/p99 over time (one line per module) |
| `splunk.timechart` | Distinct hosts seen per day, last 30d |
| `splunk.timechart` | Event volume per host per day trendline |
| `splunk.heatmap` OR `splunk.table` with cell coloring | Module-failure heatmap (module × hostname × failure count) |
| `splunk.table` | Top-N truncating hosts |

`splunk.heatmap` is a valid Dashboard Studio component but verify panel-config-schema before relying on it — if uncertain, fall back to `splunk.table` with conditional formatting (the existing dashboard uses table coloring patterns).

## 2. Dashboard Studio v2 stanza wrapper convention

Confirmed pattern (use this exactly for `odin_ops.xml`):

```xml
<dashboard version="2" theme="dark">
  <label>ODIN Operational Health</label>
  <description>Fleet scan health, module runtime, coverage, and truncation telemetry from TA-ODIN enumeration data.</description>
  <definition><![CDATA[
{
  "title": "ODIN Operational Health",
  "description": "...",
  "visualizations": { ... },
  "dataSources": { ... },
  "inputs": { ... },
  "layout": {
    "type": "absolute",
    "options": { "width": 1440, "height": 960, "display": "auto" },
    "structure": [ ... ]
  }
}
]]></definition>
</dashboard>
```

**Notes:**
- `theme="dark"` matches existing overview dashboard — keep consistent
- `<label>` and `<description>` outside `<definition>` are required by Splunk view loader; the JSON `title`/`description` inside are duplicated for Studio runtime
- `<![CDATA[...]]>` is mandatory because the JSON contains `"` and `&` characters
- Layout `type: absolute` with explicit pixel coordinates is the existing convention; `type: grid` is also valid but avoid mixing styles

## 3. Standard saved-search stanza pattern (style template for SLO alert)

Source: `ODIN_app_for_splunk/default/savedsearches.conf` `[alert_odin_truncated_events]` stanza.

**Required keys for a definition-only alert stanza** (D2 SLO alert mirrors this):

```ini
[alert_odin_fleet_scan_success_rate_below_slo]
action.email = 0
action.script = 0
alert.digest_mode = 1
alert.severity = 3
alert.suppress = 0
alert.track = 0
counttype = number of events
cron_schedule =
description = Alerts when fleet-wide TA-ODIN scan-success rate (modules_failed=0) drops below 95% over the last 24 hours. Enable by setting cron_schedule (e.g., "0 */6 * * *") and disabled = 0. Operator should set the success-rate threshold per-org after PROD-02 pilot baseline (95% is a starting point, not a hard SLO).
disabled = 1
dispatch.earliest_time = -24h@h
dispatch.latest_time = now
search = index=odin_discovery sourcetype=odin:enumeration type=odin_complete earliest=-24h \
| stats count(eval(modules_failed=0)) AS successful, count AS total by hostname \
| eval success_rate=successful/total \
| where success_rate < 0.95 \
| stats count AS failing_hosts \
| where failing_hosts > 0
```

**Key stylistic conventions:**
- `description` field uses long-form prose explaining what the alert means + how to enable (operator handoff)
- `cron_schedule` is empty (definition-only per D2)
- `disabled = 1` (definition-only per D2)
- `dispatch.earliest_time = -24h@h` (rounded to hour for consistent dispatch caching)
- `search` uses backslash continuation for multi-line SPL (works in Splunk savedsearches.conf)

## 4. inputs.conf rollback dry-run target (D5 implementation)

Source: `TA-ODIN/default/inputs.conf` empirical scan.

**Two scripted-input stanzas exist** (D5 dry-run script must handle both):

```ini
[script://./bin/odin.sh]
disabled = false
index = odin_discovery
sourcetype = odin:enumeration
interval = 2592000
timeout = 120

[script://.\bin\odin.path]
disabled = false
index = odin_discovery
sourcetype = odin:enumeration
interval = 2592000
timeout = 120
```

**Critical detail for D5 fixture:**
- Existing stanzas use `disabled = false` (string), NOT `disabled = 0` (integer). Splunk accepts both, but the rollback patch must use `disabled = true` to stay consistent with existing style. Or use both forms in tests to prove parser tolerance.
- Two stanzas → rollback procedure (and dry-run fixture) must toggle BOTH `disabled = true` to fully halt enumeration on a host that has both Linux and Windows orchestrators (mixed environment edge case).
- The Windows stanza uses `.\bin\odin.path` (Windows path syntax with backslash) — Splunk on UNIX hosts will silently skip this stanza, so it's safe to leave unchanged in pure-Linux test environments.

**Recommended D5 rollback fixture approach:**

```bash
# tools/tests/rollback-dryrun.sh — outline
set -euo pipefail

ARTIFACT=.planning/artifacts/rollback-dryrun.md
TMP_INPUTS=$(mktemp)
cp TA-ODIN/default/inputs.conf "$TMP_INPUTS"

# Step 1: pre-toggle baseline — count events from a single odin.sh invocation
echo "## Rollback dry-run $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$ARTIFACT"
echo "Commit: $(git rev-parse HEAD)" >> "$ARTIFACT"
PRE_COUNT=$(bash TA-ODIN/bin/odin.sh 2>/dev/null | wc -l)
echo "Pre-toggle event count (live odin.sh run): $PRE_COUNT" >> "$ARTIFACT"

# Step 2: apply rollback patch — set disabled = true on both stanzas in temp copy
sed -i.bak 's/^disabled = false$/disabled = true/g' "$TMP_INPUTS"

# Step 3: parser-emulator — verify both stanzas now show disabled = true
python3 -c "
import configparser
c = configparser.ConfigParser(strict=False, allow_no_value=True)
c.read('$TMP_INPUTS')
all_disabled = True
for section in c.sections():
    if section.startswith('script://'):
        d = c.get(section, 'disabled', fallback='false').strip().lower()
        if d not in ('true', '1'):
            all_disabled = False
            print(f'STANZA STILL ACTIVE: {section}')
if all_disabled:
    print('ALL STANZAS INACTIVE — rollback patch verified')
    exit(0)
exit(1)
"

# Step 4: revert patch — restore original disabled = false
mv "$TMP_INPUTS.bak" "$TMP_INPUTS"

# Step 5: post-revert event count
POST_COUNT=$(bash TA-ODIN/bin/odin.sh 2>/dev/null | wc -l)
echo "Post-revert event count: $POST_COUNT" >> "$ARTIFACT"
echo "Result: $([ $POST_COUNT -gt 0 ] && echo PASS || echo FAIL)" >> "$ARTIFACT"
```

**What the fixture proves:** parser-level rollback semantics + script idempotency on revert. Real-fleet validation (UF reload-cycle timing, Splunk-side stanza re-dispatch) is PROD-02 territory.

## 5. metadata/default.meta — no changes needed

`ODIN_app_for_splunk/metadata/default.meta` already exports `[views] = system` (line 36). Adding `odin_ops.xml` automatically inherits this export. No new export stanza needed.

## 6. PROD-07 Linux module fallback patch — exact target lines

For each of the 6 modules, the standalone fallback block is gated by `if ! declare -f emit &>/dev/null` and currently looks like (example: `cron.sh:18-25`):

```bash
if ! declare -f emit &>/dev/null; then
    ODIN_HOSTNAME="${ODIN_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}"
    ODIN_OS="${ODIN_OS:-linux}"
    ODIN_RUN_ID="${ODIN_RUN_ID:-standalone-$$}"
    ODIN_VERSION="${ODIN_VERSION:-2.1.0}"           # <-- D3 (a) bump to 1.0.0
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
    emit() { echo "timestamp=$(get_timestamp) hostname=$ODIN_HOSTNAME os=$ODIN_OS run_id=$ODIN_RUN_ID odin_version=$ODIN_VERSION $*"; }
    # ^ D3 (b) — wrap with MAX_EVENTS guard mirroring odin.sh:63-70
fi
```

**D3 (a) patch (one line per module, 6 modules):**

```diff
-    ODIN_VERSION="${ODIN_VERSION:-2.1.0}"
+    ODIN_VERSION="${ODIN_VERSION:-1.0.0}"
```

**D3 (b) patch (replace single-line `emit()` with guarded multi-line version):**

```bash
ODIN_MAX_EVENTS="${ODIN_MAX_EVENTS:-50000}"
ODIN_EVENT_COUNT=0
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

This mirrors `TA-ODIN/bin/odin.sh:55-71` (the orchestrator's canonical guarded `emit()`) verbatim except adapted for the standalone scope.

**D3 (c) extension to `tools/tests/check-version-sync.sh`:** Add a section that greps `TA-ODIN/bin/modules/*.sh` for any `2.1.0` or non-`1.0.0` version string and exits non-zero if found. Use existing `extract_canonical_version()` shell function pattern for consistency.

## 7. AppInspect compatibility notes

**Adding artifacts (Phase 5 changes):**
- `odin_ops.xml` (new Dashboard Studio v2 view) — same shape as existing `odin_overview.xml`; AppInspect already accepts that shape (`failure=0` baseline). Verify after writing.
- New alert stanza in `savedsearches.conf` — same shape as existing 2 alert stanzas; AppInspect already accepts that shape.
- `DOCS/*.md` files — outside the apps directory; AppInspect doesn't scan them.
- `tools/tests/rollback-dryrun.sh` + extended `check-version-sync.sh` — outside the apps directory; AppInspect doesn't scan them.
- 6 module patches (`TA-ODIN/bin/modules/*.sh`) — bash code changes inside TA-ODIN. shellcheck must remain clean (HARD-05 gate). AppInspect TA-ODIN baseline currently has 1 warning (`check_for_indexer_synced_configs`, accepted per Phase 3 D9); these patches don't introduce new code paths so no new findings expected.

**Verification step required in EVERY plan that touches apps:**

```bash
~/Library/Python/3.9/bin/splunk-appinspect inspect ODIN_app_for_splunk --mode precert --excluded-tags cloud --output-file /tmp/check.json --data-format json
python3 -c "import json; r=json.load(open('/tmp/check.json'))['summary']; exit(0 if r['failure']+r['error']==0 else 1)"
```

Same for `TA-ODIN` (no Phase 5 changes to verify against, but include for parity).

## 8. Validation Architecture (Nyquist)

| Dimension | Phase 5 application |
|---|---|
| **D1 — Field parity** | N/A (no new emit code; PROD-07 uses identical fields as orchestrator) |
| **D2 — Output format** | PROD-07 standalone fallback emits identical `key=value` format as orchestrator (verified by mirroring `odin.sh:55-71`) |
| **D3 — Idempotency** | Dashboard renders identically across runs; alert stanza `disabled=1` produces no scheduler activity; PROD-07 standalone-run idempotent (no state writes) |
| **D4 — Bounds enforcement** | PROD-07 (b) adds MAX_EVENTS guard to standalone fallback — VERIFY by running `ODIN_MAX_EVENTS=2 bash TA-ODIN/bin/modules/services.sh 2>&1 \| grep -c type=truncated` returns >=1 |
| **D5 — Per-type behavior** | PROD-06 dashboard panels segregate metrics by `type=` event (truncated, odin_error, odin_complete) |
| **D6 — Failure surfacing** | PROD-03 runbook entries explicitly cover each alert/error type; PROD-04 TROUBLESHOOTING.md mirrors |
| **D7 — End-to-end pipeline** | PROD-05 dry-run script demonstrates full toggle→halt→revert→resume cycle in shell-fixture form |
| **D8 — Validation suite** | New scripts (`rollback-dryrun.sh`, extended `check-version-sync.sh`) added to existing tools/tests/ harness; CI hard-gate or informational (planner decides per CONTEXT specifics) |

## 9. Pitfalls and surprises discovered

1. **Existing `odin_overview.xml` is already Dashboard Studio v2** (CONTEXT D1 stale assumption corrected; new dashboard follows same v2 pattern, no mixed-framework concern).
2. **Two `script://` stanzas in `inputs.conf`** (Linux `odin.sh` + Windows `odin.path`) — D5 rollback fixture must handle both stanzas, even if test environment is Linux-only (Windows stanza is no-op on Linux but rollback procedure should toggle both for fleet correctness).
3. **`disabled = false` (string) used in inputs.conf**, not `disabled = 0` (integer) — D5 rollback patch should use `disabled = true` to stay consistent. Both forms work in Splunk parser; consistency matters for human readability.
4. **`metadata/default.meta` already exports `[views] = system`** — adding `odin_ops.xml` requires no new export stanza, same as how `odin_overview.xml` worked.
5. **Existing alert stanza pattern is `description = ...long prose explaining how to enable...`** — operator handoff is in the description field, not in a separate doc. PROD-04 UPGRADE.md should reference this pattern when documenting alert activation.
6. **Existing dashboard uses `splunk.column`, `splunk.pie`, `splunk.singlevalue`, `splunk.table`** — `splunk.timechart` and `splunk.heatmap` (needed for ops dashboard) are not yet proven against AppInspect in this codebase. If `splunk.heatmap` causes AppInspect issues, fall back to `splunk.table` with cell-color formatting (which the existing dashboard already uses).
7. **PROD-07 (b) MAX_EVENTS guard** — must mirror `odin.sh:63-70` byte-for-byte (with the shared-state `ODIN_EVENT_COUNT` counter), NOT reinvent the guard logic. Otherwise standalone behavior drifts from orchestrator behavior over time.
8. **`tools/tests/check-version-sync.sh` already has a comment-version-drift secondary check** at line 70+ that greps file headers — D3 (c) extension should add a third section that greps modules, following the same shell-style conventions already established.

---

## Summary for the planner

- **Scope simpler than CONTEXT.md indicates**: existing dashboard is already v2; adding `odin_ops.xml` is a one-pattern continuation, not a framework migration.
- **Files to create/modify:**
  - `ODIN_app_for_splunk/default/data/ui/views/odin_ops.xml` (new, ~200-400 lines of v2 JSON wrapped in v2 view stanza)
  - `ODIN_app_for_splunk/default/savedsearches.conf` (append 1 new alert stanza)
  - `TA-ODIN/bin/modules/*.sh` (6 files, 2 patches each: D3 (a) version bump + D3 (b) emit guard)
  - `tools/tests/check-version-sync.sh` (extend with module-grep section per D3 (c))
  - `tools/tests/rollback-dryrun.sh` (new, ~50-80 lines of bash)
  - `DOCS/RUNBOOK.md` (new, ~100-150 lines for 4 alert entries)
  - `DOCS/INSTALL.md`, `DOCS/TROUBLESHOOTING.md`, `DOCS/DATA-DICTIONARY.md`, `DOCS/UPGRADE.md` (new, 50-150 lines each)
  - `DOCS/ROLLBACK.md` (new, 50-100 lines)
  - `TA-ODIN/README.md` + `ODIN_app_for_splunk/README.md` (update with Documentation links)
  - `.planning/artifacts/rollback-dryrun.md` (artifact produced by running rollback-dryrun.sh)
- **Plan structure recommendation:** 4 plans aligned to CONTEXT.md "Plan structure" section.
- **Verification gates after each plan:** AppInspect Enterprise scope clean + Phase 1+2+3+4 regression suite (5 guards) green.
- **CONTEXT D1 amendment recommended**: planner can reframe in PLAN.md prose ("existing dashboard already v2; new dashboard follows same pattern") without rewriting CONTEXT.md, OR planner can update CONTEXT.md inline to remove the stale "two-frameworks accepted" framing.
