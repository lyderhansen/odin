# Phase 5: Operational Readiness — Context

**Gathered:** 2026-04-20
**Status:** Ready for planning
**Source:** /gsd-discuss-phase 5 (5 gray areas, all decided)

<domain>
## Phase Boundary

Phase 5 owns 5 v1.0.1 requirements (PROD-03..PROD-07):

- **PROD-03** — `DOCS/RUNBOOK.md` with on-call alert response procedures
- **PROD-04** — Admin docs: `INSTALL.md`, `TROUBLESHOOTING.md`, `DATA-DICTIONARY.md`, `UPGRADE.md` + README updates in both apps
- **PROD-05** — `DOCS/ROLLBACK.md` + dry-run validation log
- **PROD-06** — Ops observability dashboard at `ODIN_app_for_splunk/default/data/ui/views/odin_ops.xml`
- **PROD-07** — Linux module standalone-fallback hygiene (3 sub-items, scope locked per D3 below)

Goal: an on-call SRE who has never seen TA-ODIN before can install it, diagnose alerts, and execute a rollback using the shipped docs alone. The new ops dashboard surfaces fleet health at a glance.

Out of scope: external security audit (separate governance track), Splunk Cloud Victoria compatibility (deferred per Phase 3 D9), automated bash test harness beyond the new check scripts (group D residual), `.tar.gz` packaging (group G residual).

</domain>

<decisions>
## Implementation Decisions

### D1 — Dashboard framework: Dashboard Studio (v2 JSON) for new ops dashboard

**Decision:** New `ODIN_app_for_splunk/default/data/ui/views/odin_ops.xml` is built as **Dashboard Studio v2** (JSON-based dashboard wrapped in the standard `<dashboard version="2">` view stanza). Existing `odin_overview.xml` (Simple XML v1, Phase 2) is left untouched and continues to work.

**Why:**
- ROADMAP PROD-06 explicitly specifies Dashboard Studio
- Better visualizations for ops data: heatmaps for module-failure-per-type, sparklines for runtime p95 trends, timelines for fleet host coverage drift
- v2 is Splunk's strategic direction; v1 Simple XML is in maintenance mode
- AppInspect tolerates mixed v1/v2 in the same app (verified in Phase 3 baseline)

**Implementation pattern:**
- Single XML view file containing `<dashboard version="2">` wrapper + JSON `<definition>` block
- Use `splunk.timechart`, `splunk.singlevalue`, `splunk.table`, `splunk.heatmap` viz components
- Existing `odin_overview.xml` (Simple XML) stays as-is — conversion deferred to v1.1+ as a separate refactor if needed

**Acceptance:** `splunk-appinspect inspect ODIN_app_for_splunk --mode precert --excluded-tags cloud` still returns `failure=0, error=0` after adding the v2 dashboard.

### D2 — Alert activation: definition-only + add 3rd SLO alert (also disabled)

**Decision:** Phase 5 keeps alerts in **definition-only state** (`disabled = 1`, empty `cron_schedule`) per Phase 2 precedent. PROD-03 runbook is preparatory documentation for when an operator activates them with baseline data from PROD-02 pilot. Phase 5 ALSO adds a third alert stanza:

```ini
[alert_odin_fleet_scan_success_rate_below_slo]
disabled = 1
cron_schedule =
search = ...computed fleet-wide success ratio...
```

**Why:**
- Phase 2 explicitly chose definition-only because activating fleet-wide alerts without baseline data risks false-positive storms
- PROD-03 ROADMAP criterion 1 requires runbook entries for 4 alert types — the 3 stanzas (truncated, module-timeout-124, fleet-SLO) + a 4th "non-124 module error" entry that runs against the SAME `alert_odin_module_timeouts`-style search (different `where` clause) cover the requirement
- Operator activates after PROD-02 pilot when they have a baseline scan-success rate to set the SLO threshold

**Operational handoff:** PROD-04 `UPGRADE.md` documents how to activate the alerts (set `disabled = 0`, set `cron_schedule = */15 * * * *` or per-org cadence).

**SLO alert search shape (planner finalizes SPL):**
```spl
index=odin_discovery sourcetype=odin:enumeration type=odin_complete earliest=-1d
| stats count(eval(modules_failed=0)) AS successful, count AS total by hostname
| eval success_rate=successful/total
| where success_rate < 0.95
```

### D3 — PROD-07 scope: minimal (a + b + c), skip d

**Decision:** Implement only PROD-07 sub-items (a), (b), (c). Skip (d) `modules/_common.sh` consolidation — deferred to v1.1+ as a focused refactor.

**Locked sub-items:**
- **(a)** Bump 6 standalone fallback `ODIN_VERSION="${ODIN_VERSION:-2.1.0}"` lines to `:-1.0.0` across `cron.sh`, `mounts.sh`, `packages.sh`, `ports.sh`, `processes.sh`, `services.sh`
- **(b)** Add `ODIN_MAX_EVENTS` guard + `type=truncated` emission to the standalone fallback `emit()` function in each of the 6 modules — mirror the orchestrator's `emit()` guard at lines 63–70 of `TA-ODIN/bin/odin.sh`
- **(c)** Extend `tools/tests/check-version-sync.sh` to grep `TA-ODIN/bin/modules/*.sh` for stale version strings (any `2.1.0` reference fails the check)

**Why minimal:**
- Standalone fallback only activates when `! declare -f emit` (i.e., direct module invocation for debug/test); fleet production never hits it
- DRY violation is real but low-impact (6 nearly-identical `safe_val`/`emit`/`get_timestamp` blocks)
- Consolidation to `_common.sh` (mirror Windows `_common.ps1` pattern) is a clean refactor but rewrites all 6 modules and changes standalone-detection semantics — not in v1.0.1's "production readiness" mandate
- v1.1+ can do the `_common.sh` refactor as its own focused phase

### D4 — Documentation depth: terse + mono-file (4 docs)

**Decision:** Each PROD-04 doc file is a **single markdown file** in `DOCS/` matching the **terse, operational style** of existing `DOCS/ARCHITECTURE.md` and `DOCS/COMMANDS.md`. Target audience: a Splunk admin who knows Deployment Server and forwarder/indexer/search-head topology. Length: 50–150 lines per doc; ≥50 to meet ROADMAP criterion.

**Files to create (one each, mono-file):**
- `DOCS/INSTALL.md` — Deployment Server rollout playbook (TA-ODIN to UFs; ODIN_app_for_splunk to indexers/SHs); per-OS prerequisites; serverclass binding examples
- `DOCS/TROUBLESHOOTING.md` — common failure modes per OS (Linux: systemctl quirks, dpkg locks, hung NFS mounts; Windows: AppLocker/WDAC, registry permissions, Get-ScheduledTask noise on member servers, UAC edge cases on workstations)
- `DOCS/DATA-DICTIONARY.md` — one `## type=*` subsection per emitted event type (`odin_start`, `odin_complete`, `odin_error`, `truncated`, `service`, `port`, `package`, `cron`, `scheduled_task`, `process`, `mount`); each lists every field name the corresponding module can emit, plus 1-line description and example
- `DOCS/UPGRADE.md` — v1.0.0 → v1.0.1 upgrade path; `serverclass.conf` repush pattern; how to activate alerts (D2 handoff); rollback pointer to `DOCS/ROLLBACK.md`

**README updates:**
- `TA-ODIN/README.md` — add a "Documentation" section linking to relative paths in `../DOCS/INSTALL.md`, etc.
- `ODIN_app_for_splunk/README.md` — same
- Both READMEs link to `../DOCS/RUNBOOK.md` and `../DOCS/ROLLBACK.md`

**Anti-pattern reminder:** Don't write tutorial-style intros for SREs who haven't seen Splunk before — that's not the audience. Reader is presumed to know `splunk btool`, `inputs.conf`, `outputs.conf`, Deployment Server, and `splunk reload deploy-server`.

### D5 — Rollback dry-run: shell fixture simulation (no local Splunk install)

**Decision:** PROD-05 dry-run is executed via a new shell script `tools/tests/rollback-dryrun.sh` that simulates the Deployment Server toggle semantics WITHOUT requiring a real Splunk instance. The script produces the artifact `.planning/artifacts/rollback-dryrun.md` with timestamped pre-toggle / post-toggle event-count deltas. Real fleet validation happens in PROD-02 pilot (Phase 6).

**Simulation approach:**
1. Start with a temp working copy of `TA-ODIN/default/inputs.conf` (the actual stanza file shipping to forwarders)
2. Run `bash TA-ODIN/bin/odin.sh > /tmp/pre-toggle.events 2>&1`; capture event count and timestamp
3. Apply the rollback patch to the temp `inputs.conf`: `disabled = 1` added to the `[script://...odin.sh]` stanza
4. Verify that a parser/spawn-emulator (a small bash function in the script) **would not** invoke `odin.sh` based on the new stanza state
5. Revert the temp `inputs.conf`; capture timestamp
6. Re-run `bash TA-ODIN/bin/odin.sh > /tmp/post-revert.events 2>&1`; capture event count
7. Write all timestamps + event counts + commit hash to `.planning/artifacts/rollback-dryrun.md`

**What this proves:**
- The `disabled = 1` toggle semantics are correctly understood and documented
- The procedure terminates the enumeration scripts within one scan cycle (the parser-emulator confirms)
- Reverting restores enumeration

**What this does NOT prove (deferred to PROD-02):**
- Real Deployment Server reload-cycle delivers the patched `inputs.conf` to UFs within expected time
- Real Splunk forwarders honor the `disabled = 1` flag immediately on next reload
- No partial-state failure (e.g., `inputs.conf` syntax error after edit causes UF to reject the entire stanza)

These three are explicitly called out in the dry-run log as "verified by procedure inspection only; live fleet validation pending PROD-02".

**Acceptance modification:** ROADMAP §Phase 5 success criterion 4 should accept either a Splunk-instance-backed dry-run OR the shell-fixture simulation; planner notes this in PLAN.md.

### Plan structure (recommended waves — planner finalizes)

**Wave 0 (parallel-safe — no cross-deps):**
- Plan 01 — PROD-07 Linux module hygiene (3 sub-items abc; touches 6 `.sh` files + extends `check-version-sync.sh`)
- Plan 02 — PROD-06 ops dashboard + PROD-05 rollback fixture (touches `ODIN_app_for_splunk/default/data/ui/views/odin_ops.xml` + `tools/tests/rollback-dryrun.sh` + `DOCS/ROLLBACK.md` + `.planning/artifacts/rollback-dryrun.md`)
- Plan 03 — PROD-03 runbook + new SLO alert stanza (touches `DOCS/RUNBOOK.md` + `ODIN_app_for_splunk/default/savedsearches.conf`)

**Wave 1 (depends on Wave 0 completing):**
- Plan 04 — PROD-04 admin docs (4 docs + 2 README updates) — depends on all Wave 0 because UPGRADE.md references the activated alerts (Plan 03), the dashboard (Plan 02), and the new module hygiene (Plan 01)

Planner can collapse Plan 02 + Plan 03 into a single plan if cleaner; the wave dependency is what matters.

### Claude's Discretion

- Exact SPL of saved searches (D2 SLO alert is a sketch, planner may refine the success_rate threshold or window)
- Dashboard panel ordering and visualization choice within Dashboard Studio (D1)
- Runbook escalation contact placeholders (use `<TBD per organization>` since no real org context exists)
- Specific troubleshooting entries beyond the OS-quirks list in D4 — planner picks based on what's most likely to be hit in PROD-02 pilot
- Whether `DOCS/UPGRADE.md` includes a copy of the rollback procedure or just links to `ROLLBACK.md` — pick one to avoid drift; recommend link
- Whether `tools/tests/rollback-dryrun.sh` is added to CI as a regression guard — recommend yes (gate-safe; runs in <5s)

## Locked downstream contract

Researcher and planner produce content that satisfies:

1. **5 requirements covered** — every plan's `requirements:` field includes its PROD-* IDs; together the plans cover PROD-03..PROD-07
2. **No transforms.conf, no app.conf, no orchestrator code changes** — Phase 5 is docs + dashboard + savedsearches + Linux fallback hygiene only. AppInspect baseline must remain `failure=0, error=0` after every plan.
3. **No new mandatory CI gates** — D2 alerts stay disabled; D5 dry-run script can be added to CI as informational (non-blocking) or as a hard gate (planner decides; recommend hard gate since it runs in <5s)
4. **No `windows_*` host_role values introduced** — Phase 4 D1 still binding (no roles added in Phase 5 anyway, but if any saved search or doc example references roles, use D1-correct names)
5. **Linux module standalone-fallback semantics preserved** — D3 minimal scope means modules still detect `! declare -f emit` and define their own fallback; new logic just bumps version and adds MAX_EVENTS check inside that fallback
6. **TA-ODIN forwarder app remains forwarder-shaped** — no docs, dashboards, or savedsearches inside `TA-ODIN/`; all Phase 5 ODIN_app_for_splunk-targeted artifacts go in that app per CLAUDE.md two-app-split rule
7. **AppInspect Enterprise scope (`--excluded-tags cloud`) remains the only AppInspect mode** — no Cloud Victoria work in v1.0.1

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 4 outcomes (informs Phase 5)
- `.planning/phases/04-windows-classification-data/04-VERIFICATION.md` — Phase 4 final state, post-Phase-4 baseline counts
- `.planning/phases/04-windows-classification-data/deferred-items.md` — D-04-01 + D-04-02 (informs PROD-04 troubleshooting "if classification looks wrong, check legacy role values")

### Existing dashboards + saved searches (extend, don't replace)
- `ODIN_app_for_splunk/default/data/ui/views/odin_overview.xml` — existing Simple XML overview (Phase 2); leave untouched (D1)
- `ODIN_app_for_splunk/default/savedsearches.conf` — existing 2 alert stanzas (`alert_odin_truncated_events`, `alert_odin_module_timeouts`) + 3 nightly searches (Host Inventory, Log Source Details, TA Deployment Matrix); D2 adds 1 new alert stanza

### Existing docs (style template)
- `DOCS/ARCHITECTURE.md` — terse style template for D4
- `DOCS/COMMANDS.md` — terse style template for D4
- `DOCS/CHANGEHISTORY.md` — needs new v1.0.1 section (planner decides whether to update as part of Plan 04)

### Existing test harness (style template for new shell scripts)
- `tools/tests/check-version-sync.sh` — style template for D3 (c) extension and D5 rollback dry-run script
- `tools/tests/check-two-app-split.sh` — same
- `tools/tests/check-windows-classification.sh` — Phase 4 PROD-01 guard (newest example, shellcheck-clean)

### Linux module fallback context (D3 implementation)
- `TA-ODIN/bin/odin.sh` lines 29 (canonical `ODIN_VERSION="1.0.0"` export), 38–46 (canonical guardrails), 55–70 (canonical `emit()` with MAX_EVENTS guard) — D3 (b) mirrors lines 63–70 into each module's standalone fallback
- `TA-ODIN/bin/modules/services.sh` lines 17–25 — example of current standalone fallback to be patched (1 of 6)

### AppInspect baseline (must not regress)
- `.planning/artifacts/appinspect/odin-app-phase04-final.json` — current `failure=0, error=0, warning=0, success=14, na=7`
- `.planning/artifacts/appinspect/ta-odin-final.json` — current TA-ODIN baseline; Phase 5 changes the bash modules but check_for_indexer_synced_configs is the only existing warning, accepted per Phase 3 D9

### Project conventions
- `CLAUDE.md` — two-app-split is sacred (docs/dashboards/savedsearches in `ODIN_app_for_splunk` only)
- `.planning/REQUIREMENTS.md` PROD-03..PROD-07 sections — acceptance criteria
- `.planning/ROADMAP.md` §Phase 5 success criteria 1–6

</canonical_refs>

<specifics>
## Specific Ideas

### D1 Dashboard Studio panel set (planner finalizes layout)
Per ROADMAP success criterion 5 + D1 visualization recommendations:
- **Scan success rate per OS** — `splunk.singlevalue` × 2 (linux / windows) over last 24h, with sparkline
- **Module runtime p95 per module** — `splunk.timechart` (line) bucketed by module name, last 7d
- **Module-failure heatmap** — `splunk.heatmap` (or `splunk.table` with cell-color) module × hostname over last 7d
- **Event volume per host per day trendline** — `splunk.timechart` aggregated daily, top 20 hosts
- **Distinct hosts seen over time** — `splunk.timechart` of `dc(hostname)` per day, last 30d
- **Top-N truncating hosts** — `splunk.table` of hosts with `type=truncated` events in last 7d, sorted desc

### D2 SLO alert SPL (planner refines)
```spl
index=odin_discovery sourcetype=odin:enumeration type=odin_complete earliest=-1d
| stats count(eval(modules_failed=0)) AS successful, count AS total by hostname
| eval success_rate=successful/total
| where success_rate < 0.95
| stats count AS failing_hosts
| where failing_hosts > 0
```

### D5 Rollback dry-run script outline
```bash
#!/bin/bash
# tools/tests/rollback-dryrun.sh
set -euo pipefail
ARTIFACT=.planning/artifacts/rollback-dryrun.md
TMP_INPUTS=$(mktemp)
cp TA-ODIN/default/inputs.conf "$TMP_INPUTS"

# Step 1: pre-toggle baseline
echo "## Rollback dry-run $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$ARTIFACT"
echo "Commit: $(git rev-parse HEAD)" >> "$ARTIFACT"
echo "" >> "$ARTIFACT"
echo "### Pre-toggle baseline" >> "$ARTIFACT"
PRE_COUNT=$(bash TA-ODIN/bin/odin.sh 2>/dev/null | wc -l)
echo "- Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$ARTIFACT"
echo "- Event count: $PRE_COUNT" >> "$ARTIFACT"

# Step 2: apply rollback (add disabled = 1)
sed -i.bak 's/^\[script:.*odin\.sh\]$/&\ndisabled = 1/' "$TMP_INPUTS"

# Step 3: parser-emulator: scan stanza, return false if disabled = 1
python3 -c "
import configparser
c = configparser.ConfigParser(strict=False, allow_no_value=True)
c.read('$TMP_INPUTS')
for section in c.sections():
    if 'odin.sh' in section:
        if c.get(section, 'disabled', fallback='0') == '1':
            print('STANZA INACTIVE - orchestrator NOT invoked')
            exit(0)
print('STANZA ACTIVE - WOULD INVOKE')
exit(1)
"

# Step 4 + 5: log + revert
# ...timestamps + post-revert event count + write final report
```

</specifics>

<deferred>
## Deferred Ideas

- **PROD-07 (d) `modules/_common.sh` consolidation** — clean refactor mirroring Windows `_common.ps1`; deferred to v1.1+ per D3
- **`odin_overview.xml` Simple-XML → Dashboard Studio conversion** — deferred to v1.1+ per D1
- **Real Splunk Enterprise dry-run for PROD-05** — overkill for v1.0.1; PROD-02 pilot covers live validation
- **Activating the 3 alerts** — Phase 5 keeps them disabled; activation is operator decision after PROD-02 baseline data
- **`DOCS/GETTING-STARTED.md` for non-Splunk audiences** — deferred to v1.1+ doc-group E completion
- **Per-issue troubleshooting fragments** (vs single mono-file) — deferred to v1.1+ if mono-file proves unwieldy
- **CI integration of `rollback-dryrun.sh`** — recommend planner add it as a hard gate (5s runtime), but acceptable to skip if it complicates CI-step ordering

</deferred>

---

*Phase: 05-operational-readiness*
*Context gathered: 2026-04-20 via /gsd-discuss-phase 5*
