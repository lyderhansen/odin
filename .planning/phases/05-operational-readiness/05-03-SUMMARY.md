---
phase: 05-operational-readiness
plan: 03
subsystem: docs
tags: [runbook, alerts, savedsearches, slo, on-call, splunk, operational-readiness]

# Dependency graph
requires:
  - phase: 02-host-classification
    provides: existing 2 alert stanzas (alert_odin_truncated_events, alert_odin_module_timeouts) used as byte-level template
  - phase: 04-windows-classification-data
    provides: AppInspect Phase 4 final baseline (failure=0, error=0, warning=0, success=14, na=7) — reference for zero-regression assertion
provides:
  - 3rd alert stanza alert_odin_fleet_scan_success_rate_below_slo (definition-only per CONTEXT D2)
  - DOCS/RUNBOOK.md (395 lines, 4 alert-response entries, each with 4 subsections)
  - .planning/artifacts/appinspect/odin-app-phase05-wave0-plan03.json (post-stanza zero-regression artifact)
  - Operational handoff documentation for activating alerts after PROD-02 pilot baseline
affects: [05-04 admin docs (UPGRADE.md cross-references), Phase 6 pilot validation, post-pilot operator activation of alerts]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Definition-only alert stanza: disabled = 1 + empty cron_schedule, description field carries operator-handoff prose"
    - "Runbook structure: 4 ### Alert: entries, each with #### What it means / #### Diagnostic SPL / #### Remediation / #### Escalation subsections"
    - "Escalation placeholder convention: <TBD per organization> for fields that depend on org-specific routing"

key-files:
  created:
    - "DOCS/RUNBOOK.md (395 lines)"
    - ".planning/artifacts/appinspect/odin-app-phase05-wave0-plan03.json"
  modified:
    - "ODIN_app_for_splunk/default/savedsearches.conf (+20 lines, 1 new stanza)"

key-decisions:
  - "SLO threshold = 95% as a starting recommendation, not a hard SLO — operator tunes per-org after PROD-02 pilot baseline"
  - "Stanza ships with empty cron_schedule (D2 definition-only) — operator activates by setting cron_schedule and disabled = 0"
  - "Runbook covers all 3 saved-search alerts + the implicit 4th (non-124 module error) which uses the same alert_odin_module_timeouts data with a different where clause"
  - "<TBD per organization> placeholder used for all 4 Escalation subsections (no real org context exists)"
  - "Documented Activating alerts pattern via local/savedsearches.conf overlay (preserve upgrade path; don't edit default/)"

patterns-established:
  - "Cross-plan parallelism resilience: my Task 2 (RUNBOOK.md) was inadvertently committed by Plan 01's executor; verified content byte-correct in HEAD and continued without history rewrite (per <destructive_git_prohibition>)"
  - "AppInspect zero-regression assertion: compare summary dict against Phase 4 baseline (failure=0, error=0, warning=0, success=14, na=7) — byte-identical confirms new stanza introduces no findings"

requirements-completed:
  - PROD-03

# Metrics
duration: 6min
completed: 2026-04-24
---

# Phase 5 Plan 03: Runbook + SLO Alert Stanza Summary

**Shipped PROD-03 by appending the 3rd definition-only alert stanza (`alert_odin_fleet_scan_success_rate_below_slo`) to `ODIN_app_for_splunk/default/savedsearches.conf` and writing a 395-line on-call runbook covering all 4 alert classes; AppInspect Enterprise scope remains byte-identical to Phase 4 baseline.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-04-24T08:53:47Z
- **Completed:** 2026-04-24T08:59:37Z
- **Tasks:** 3/3 completed
- **Files modified:** 1 (savedsearches.conf)
- **Files created:** 2 (RUNBOOK.md, AppInspect JSON artifact)

## Accomplishments

- Appended `alert_odin_fleet_scan_success_rate_below_slo` stanza to `savedsearches.conf` (3rd `[alert_*]` stanza, definition-only per CONTEXT D2 — `disabled = 1`, empty `cron_schedule`)
- Created `DOCS/RUNBOOK.md` (395 lines) with exactly 4 `### Alert:` entries each containing the 4 required subsections (`#### What it means`, `#### Diagnostic SPL`, `#### Remediation`, `#### Escalation`)
- All Escalation fields use `<TBD per organization>` (4 placeholders)
- 10 Deployment Server / serverclass cross-references; 2 ROLLBACK cross-references
- AppInspect Enterprise scope unchanged: `failure=0, error=0, warning=0, success=14, na=7` (byte-identical to Phase 4 final baseline)
- Phase 1+2+3+4 regression suite all green (5 guards: HARD-01 version-sync, HARD-07 two-app-split, HARD-08 injection-fixtures 10/10, windows-parity-harness all dimensions, PROD-01 windows-classification)

## Task Commits

Each task was committed atomically:

1. **Task 1: Append SLO alert stanza** — `c2adc79` (feat)
2. **Task 2: Create DOCS/RUNBOOK.md** — folded into `d75d779` (cross-plan attribution; see Deviations below). Content byte-identical to my Write output (395 lines, 4 alert headings, 16 subsections, 4 TBD placeholders)
3. **Task 3: AppInspect verification + regression** — `684d0e8` (chore)

**Plan metadata commit:** to follow this SUMMARY.

## Files Created/Modified

- `ODIN_app_for_splunk/default/savedsearches.conf` — appended 1 stanza (`alert_odin_fleet_scan_success_rate_below_slo`), preserving the existing 2 alert stanzas + 3 nightly searches byte-for-byte; total file 125→145 lines, total stanzas 5→6, alert stanzas 2→3
- `DOCS/RUNBOOK.md` — new file, 395 lines, terse operational style matching ARCHITECTURE.md and COMMANDS.md template; covers all 4 alert classes (truncated, exit_code=124 module timeout, non-124 module error, fleet scan success rate below SLO) with diagnostic SPL + remediation steps + escalation placeholders
- `.planning/artifacts/appinspect/odin-app-phase05-wave0-plan03.json` — AppInspect Enterprise scope JSON artifact, byte-identical summary block to Phase 4 final baseline

## Decisions Made

Followed plan as specified. Stylistic decisions made within Claude's discretion (per CONTEXT § Claude's Discretion):

- Runbook escalation placeholder: `<TBD per organization>` (matches CONTEXT D4 convention)
- SLO threshold in alert description: "95% is a starting point, not a hard SLO" prose reinforces D2 operator-handoff intent
- Activating alerts section recommends `local/savedsearches.conf` overlay (NOT editing `default/`) to preserve upgrade path

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Cross-plan race / blocking issue] DOCS/RUNBOOK.md committed under Plan 01's commit hash**

- **Found during:** Task 2 (post-write commit)
- **Issue:** When I ran `git commit` to land my staged `DOCS/RUNBOOK.md`, the commit returned `nothing added to commit`. Investigation showed `DOCS/RUNBOOK.md` was already tracked in HEAD inside commit `d75d779` (Plan 01's `feat(05-01): extend check-version-sync.sh ...` commit). Plan 01's parallel executor had staged my file alongside its own changes — most likely via a broad `git add` glob in `tools/tests/` or a workspace-wide stage that pulled adjacent untracked files. The file content is byte-for-byte my Write output (verified: 395 lines, 4 alert headings, 16 subsections, 4 TBD placeholders, T2 acceptance gate passes against HEAD).
- **Fix:** Per `<destructive_git_prohibition>`, I MUST NOT use `git reset --hard`, `git rebase -i`, or any history-rewriting operation. The functional outcome is correct (file in HEAD with my content); only the commit attribution is mislabelled. Documented as a deviation rather than rewriting history.
- **Files modified:** None (file was already in HEAD)
- **Verification:** `git show d75d779:DOCS/RUNBOOK.md | wc -l` returns 395; T2 automated_verify gate passes against HEAD content
- **Committed in:** `d75d779` (Plan 01's commit, cross-plan pollution)

**2. [Rule 3 — Transient git lock]**

- **Found during:** Task 2 commit
- **Issue:** Initial `git commit` for RUNBOOK.md returned `Unable to create '.../.git/index.lock': File exists` due to race with Cursor's `gitWorker.js` background process.
- **Fix:** Re-checked lock state — lock had cleared by next bash invocation. No manual intervention needed.
- **Files modified:** None
- **Verification:** Subsequent `git status` and `git add` succeeded
- **Committed in:** N/A (transient, self-healed)

### Cross-plan attribution note

The Plan 03 commit story has one mislabelled commit. Reading from git log:

| Commit | Plan | Plan 03 contribution |
|--------|------|----------------------|
| `c2adc79` | 05-03 | Task 1: SLO alert stanza in savedsearches.conf |
| `4041ef7` | 05-02 | Plan 02 work (odin_ops.xml dashboard) — not Plan 03 |
| `6b53e34` | 05-01 | Plan 01 work (PROD-07 a+b module patches) — not Plan 03 |
| `d75d779` | 05-01 | Plan 01 work + **DOCS/RUNBOOK.md (Plan 03 Task 2)** mistakenly stapled in |
| `684d0e8` | 05-03 | Task 3: AppInspect artifact |

If a future operator needs to audit Plan 03's diff, the canonical patch set is:
- `git show c2adc79 -- ODIN_app_for_splunk/default/savedsearches.conf`
- `git show d75d779 -- DOCS/RUNBOOK.md`
- `git show 684d0e8 -- .planning/artifacts/appinspect/odin-app-phase05-wave0-plan03.json`

## Verification Output

### Task 1 acceptance (T1 PASS)

```
Stanza header count:        1
Empty cron_schedule:        1
Pre-existing alerts kept:   2
All alert stanzas:          3
Total stanzas:              6 (3 alerts + 3 nightly searches)
```

### Task 2 acceptance (T2 PASS, against HEAD content)

```
Line count:               395
Alert headings:           4
Subsections:              16 (4 entries × 4 subsections)
TBD placeholders:         4
ROLLBACK cross-refs:      2
Deployment Server refs:   10
type=truncated mention:   present
exit_code=124 mention:    present
fleet success rate:       present
```

### Task 3 acceptance (T3 PASS)

```
AppInspect Enterprise scope:
  failure: 0  | error: 0  | warning: 0  | success: 14  | na: 7
  (byte-identical to .planning/artifacts/appinspect/odin-app-phase04-final.json)

HARD-01 check-version-sync.sh         PASS (4 sites + 6 module fallbacks at 1.0.0)
HARD-07 check-two-app-split.sh        PASS
HARD-08 injection-fixtures            PASS (10/10)
windows-parity-harness                PASS (all dimensions)
PROD-01 check-windows-classification  PASS
```

## Threat model coverage (per plan frontmatter)

| Threat | Mitigation status |
|--------|-------------------|
| T1 (Tampering — bad SPL) | AppInspect parsed savedsearches.conf cleanly; no parse errors. SPL is stats/eval only with no expensive subsearches. |
| T2 (Repudiation — operator activates without baseline) | Stanza description explicitly tells operator to set threshold per-org after PROD-02 baseline; runbook Escalation = `<TBD per organization>`. |
| T3 (Information disclosure) | N/A — runbook contains operational guidance, no secrets. |
| T4 (DoS — too-aggressive cron) | Stanza ships with empty cron_schedule; description recommends `0 */6 * * *` or per-org cadence. Search uses earliest=-24h bounded window. |

## Self-Check: PASSED

- `ODIN_app_for_splunk/default/savedsearches.conf` — FOUND, contains `[alert_odin_fleet_scan_success_rate_below_slo]` stanza
- `DOCS/RUNBOOK.md` — FOUND (395 lines)
- `.planning/artifacts/appinspect/odin-app-phase05-wave0-plan03.json` — FOUND, summary `{failure: 0, error: 0, warning: 0, success: 14, na: 7}`
- Commit `c2adc79` — FOUND in `git log --all`
- Commit `d75d779` — FOUND in `git log --all` (contains DOCS/RUNBOOK.md per Rule 3 deviation #1)
- Commit `684d0e8` — FOUND in `git log --all`

## Next steps

- Plan 04 (Wave 1, depends on Wave 0 completing) — admin docs (INSTALL.md, TROUBLESHOOTING.md, DATA-DICTIONARY.md, UPGRADE.md). UPGRADE.md will reference the activation procedure documented in this runbook's "Activating alerts" section.
- Operator action (post-PROD-02 pilot, Phase 6): activate the 3 alert stanzas via `local/savedsearches.conf` overlay; tune SLO threshold per pilot baseline.
