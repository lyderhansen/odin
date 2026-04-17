---
gsd_state_version: 1.0
milestone: v1.0.1
milestone_name: production-readiness
current_plan: 0 of 0
status: scoping
last_updated: "2026-04-15T13:00:00.000Z"
last_activity: 2026-04-15
progress:
  total_phases: 3
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State — TA-ODIN

## Current Position

- **Milestone:** v1.0.1 — Production Readiness (scope PROD-01..PROD-06)
- **Phase:** Phase 4 — Windows Classification Data (not started; awaiting `/gsd-plan-phase 4`)
- **Plan:** None drafted yet
- **Status:** Milestone opened — requirements + roadmap committed, ready for planning
- **Current Plan:** 0 of 0
- **Total Plans in Phase:** TBD
- **Progress:** [──────────] 0%
- **Last activity:** 2026-04-15

## Milestone Scope (v1.0.1)

Take v1.0.0 from pilot-ready to fleet-deployable by closing the operational, observability, and documentation gaps that block safe rollout beyond ~50 hosts.

- **PROD-01.** Windows classification lookups — populate Windows-specific rows in `odin_classify_services.csv`, `odin_classify_ports.csv`, `odin_classify_packages.csv`, `odin_log_sources.csv` → **Phase 4**
- **PROD-02.** Pilot deployment — 5+ Linux + 5+ Windows real hosts via Deployment Server, 7-day observation window → **Phase 6**
- **PROD-03.** Operational runbook — on-call response procedures for all alert types → **Phase 5**
- **PROD-04.** Admin + troubleshooting docs — install, troubleshoot, data dictionary, upgrade guides → **Phase 5**
- **PROD-05.** Rollback procedure — documented + dry-run validated → **Phase 5**
- **PROD-06.** Ops observability dashboard — Dashboard Studio view with scan health + runtime + coverage panels → **Phase 5**
- **PROD-07.** Linux module standalone-fallback hygiene — bump v2.1.0→1.0.0, add MAX_EVENTS guard to standalone emit, extend version-sync check, optionally centralize into `_common.sh` → **Phase 5**

**Deferred to v1.1+:** Automated bash test harness (group D residual), reproducible `.tar.gz` packaging (group G), Splunk Cloud Victoria compatibility (Phase 3 D9), external security audit, supply chain attestation.

## Phase Map

| Phase | Name | Requirements | Status |
|-------|------|--------------|--------|
| 4 | Windows Classification Data | PROD-01 | Not started |
| 5 | Operational Readiness | PROD-03, PROD-04, PROD-05, PROD-06, PROD-07 | Not started |
| 6 | Pilot Validation | PROD-02 | Not started |

## Accumulated Context

### Codebase facts (as of 2026-04-15, post-v1.0.0)

- **v1.0.0 shipped**: tag `v1.0.0` on `origin/main` (commit `ad12450`). GitHub release page live. 78 commits, 3 phases, 30/30 UAT tests pass, 0 AppInspect failures under Enterprise scope.
- **Linux + Windows parity**: Both orchestrators on `ODIN_VERSION=1.0.0`. 6 Linux modules + 6 Windows modules emitting byte-identical `key=value` event format. Windows modules validated via mock fixtures + Nyquist harness (no real Windows host touched yet).
- **CI gates (all green)**: shellcheck, PSScriptAnalyzer, two-app-split guard, version-sync guard, HARD-08 injection fixtures (10/10), `.DS_Store` smoke test, AppInspect 4.1.3 hard-gate on both apps (SHA-pinned, `--excluded-tags cloud`). 8 mechanical gates + 4 setup/housekeeping steps in `.github/workflows/ci.yml`.
- **Classification data**: Linux lookups populated (services: 332 rows, ports: 206 rows, packages: 274 rows, log sources: 274 rows). **Windows rows empty** — this is PROD-01.
- **Two-app split**: TA-ODIN (forwarders) vs ODIN_app_for_splunk (indexers/SH). Enforced by CI guard + AppInspect.
- **Observability today**: 2 alert stanzas (`alert_odin_truncated`, `alert_odin_error_exit_124`) — definition-only in `ODIN_app_for_splunk/default/savedsearches.conf` (`disabled = 1`, empty `cron_schedule`). No ops dashboard yet.
- **Saved searches**: 3 nightly (Host Inventory, Log Source Details, TA Deployment Matrix) + 1 overview dashboard (`odin_overview.xml`).
- **Automated test coverage**: 0% on the runtime bash modules (the HARD-08 fixtures test `safe_val`/`emit` only). Windows modules are harness-validated against mock fixtures but not unit-tested.
- **Docs**: `CLAUDE.md` (developer-facing project guide), `DOCS/ARCHITECTURE.md`, `DOCS/COMMANDS.md`, `DOCS/CHANGEHISTORY.md`. **No admin-facing docs yet** — this is PROD-04.
- **No Windows live-host validation yet** — PROD-02 is the first time TA-ODIN will run on real Windows hardware.

### Hard constraints (unchanged from v1.0.0)

- Linux: Bash 4+ only. No Python, Perl, compiled binaries.
- Windows: PowerShell 5.1+ built-in cmdlets only. No PS Gallery, `Add-Type`, `Invoke-Expression`, base64.
- Read-only on the host: no writes outside Splunk var, no network, no process kills, no config changes.
- Runtime budget: ≤90s per module, ≤120s total scan, ≤50 000 events per module.
- Backwards-compatible event format: `odin:enumeration` sourcetype and field names are frozen.
- Splunk Enterprise scope only (Cloud Victoria deferred to future milestone).
- Both apps must continue to pass `splunk-appinspect` under Enterprise scope on every commit.

### Key decisions inherited from v1.0.0

- Full Windows parity (v1.0.0 Phase 1) — don't narrow Windows scope in v1.0.1.
- Registry-based Windows package enumeration — not `Win32_Product`.
- Linux modules frozen unless audit finds a concrete defect.
- AppInspect is a hard gate on every push, not a release-time check.
- Packaging as git tag + GitHub Release page for now; `.tar.gz` artifacts deferred.

### v1.0.1 roadmap decisions (2026-04-15)

- 3 phases, coarse granularity (matches v1.0.0 pattern per `config.json`).
- Strict build order: Classification data → Ops readiness → Pilot validation. Rationale: pilot needs classification to be meaningful; ops runbook needs the final deployed config; docs should describe the *final* v1.0.1 state, not a moving target.
- Phase 6 pilot is the only requirement that runs against real hosts — all other work is desk-executable.
- `PROD-02` pilot window is 7 continuous days; shorter windows miss drift and weekly-scheduled-task patterns.
- No new mandatory CI gates in this milestone (AppInspect + HARD-* gates from v1.0.0 continue to gate every commit).

## Todos

_None. Use `/gsd-add-todo` to capture ideas as they come up during planning._

## Session Continuity

_Last session: 2026-04-15 — shipped v1.0.0 (3/3 phases, 8/8 plans, 30/30 UAT tests, tag pushed to origin, GitHub Release created). Opened v1.0.1 Production Readiness milestone: REQUIREMENTS.md amended with PROD-01..PROD-06, ROADMAP.md rewritten for phases 4–6, STATE.md reset. Next: `/gsd-discuss-phase 4` or `/gsd-plan-phase 4` to start Windows classification data work._
