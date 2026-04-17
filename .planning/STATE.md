---
gsd_state_version: 1.0
milestone: v1.0.1
milestone_name: milestone
current_plan: 2
status: executing
last_updated: "2026-04-17T13:20:12.201Z"
last_activity: 2026-04-17
progress:
  total_phases: 3
  completed_phases: 1
  total_plans: 2
  completed_plans: 2
  percent: 100
---

# Project State — TA-ODIN

## Current Position

- **Milestone:** v1.0.1 — Production Readiness (scope PROD-01..PROD-07)
- **Phase:** Phase 4 — Windows Classification Data (COMPLETE)
- **Plan:** 04-01 + 04-02 both shipped; PROD-01 fully closed
- **Status:** Phase 4 complete; ready to start Phase 5 (Operational Readiness)
- **Current Plan:** 2 of 2 (Phase 4)
- **Total Plans in Phase:** 2
- **Progress:** [██████████] 100%
- **Last activity:** 2026-04-17

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
| 4 | Windows Classification Data | PROD-01 | **Complete** (2/2 plans — 04-01 services+ports, 04-02 packages+log_sources+regression-guard) |
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

### Plan 04-01 outcomes (2026-04-17)

- `odin_classify_services.csv` grew 332 → 357 lines (+25 Windows service rows, D1 taxonomy, RESEARCH §3 canonical Get-Service Names).
- `odin_classify_ports.csv` grew 206 → 224 lines (+18 Windows port rows covering DC/Kerberos/WSUS/WDS/DFSR/KMS/SCCM/DPM/Hyper-V/SSAS/WCF/WinRM/RPC).
- AppInspect Enterprise scope still `failure=0, error=0, warning=0, success=14, na=7` — byte-for-byte identical to Phase 3 baseline. Wave 0 artifact committed at `.planning/artifacts/appinspect/odin-app-phase04-wave0.json`.
- Phase 1+2+3 regression suite green (HARD-01 version-sync, HARD-07 two-app-split, HARD-08 injection-fixtures 10/10, windows-parity-harness all dimensions).
- **Surprise:** Plan 04-01 was drafted assuming a clean Windows-free baseline; commit `da1f66e` (predates v1.0.1) had already added 23 of 34 required services + 18 of 24 required ports. Honored user's gating rule by preserving pre-existing rows byte-for-byte and appending only missing + additional canonical Windows rows to satisfy wc-l gates. Two pre-existing data-quality issues (duplicate (port,transport) keys; legacy role names like `web` instead of `web_server`) tracked for future cleanup in `.planning/phases/04-windows-classification-data/deferred-items.md` (D-04-01, D-04-02).
- Plan 04-02 should target the D1-correct `host_role` values in `odin_log_sources.csv` regardless of the legacy rows; a focused cleanup plan may re-align the legacy rows after Phase 4 lands.

### Plan 04-02 outcomes (2026-04-17)

- `odin_classify_packages.csv` grew 274 → 308 lines (+34 Windows package wildcard rows, D3 patterns + D1 taxonomy + RESEARCH §4 registry display names).
- `odin_log_sources.csv` grew 274 → 297 lines (+23 Windows log_source mapping rows: 8 canonical Splunkbase TAs + 8 baseline-only-marked + 7 baseline TAs without marker. Cross-CSV TA registry validation enforced against `odin_recommended_tas.csv` — zero invented TA names).
- `tools/tests/check-windows-classification.sh` created — 138-line shellcheck-clean executable regression guard. Implements ROADMAP §Phase 4 success criteria 1-5 as shell assertions: row counts on all 4 lookup CSVs, canonical Windows signal coverage, Sysmon XmlWinEventLog format guard, ≥7 baseline-only markers, cross-CSV TA validation, synthetic Windows host classification (W3SVC + MSSQLSERVER + LanmanServer ≥3 distinct roles), schema-header drift guards. Regression detection verified end-to-end (deleting W3SVC row triggers 3 failures; revert restores PASS).
- AppInspect Enterprise scope still `failure=0, error=0, warning=0, success=14, na=7` — byte-identical to Phase 3 baseline AND Wave 0 baseline. Final artifact at `.planning/artifacts/appinspect/odin-app-phase04-final.json`.
- Phase 1+2+3 regression suite + new PROD-01 guard all green.
- **PROD-01 fully closed.** Plans 04-01 + 04-02 together complete every PROD-01 acceptance criterion.
- Four Rule 1 fixes during execution: removed embedded commas from 2 package descriptions to satisfy NF==5 AC; switched script `grep -E` to `grep -F` for literal-paren wildcard patterns; made schema-header check `tr -d '\r'`-tolerant for pre-existing CRLF in `odin_log_sources.csv`; replaced `\xc2\xa78` byte-escape with literal "section 8" to satisfy shellcheck SC2028.
- Phase 4 left in fully-buildable, AppInspect-clean, regression-guard-protected state. Ready for Phase 5 (Operational Readiness).

## Todos

_None. Use `/gsd-add-todo` to capture ideas as they come up during planning._

## Session Continuity

_Last session: 2026-04-17 — Plan 04-02 (Wave 1 packages + log_sources + regression-guard + final AppInspect) executed end-to-end. 4/4 tasks committed (`7f5715a` packages +34, `d3b9c08` log_sources +23, `6e466fa` check-windows-classification.sh, `15ba0ac` AppInspect final baseline). Duration ~6 min. Four Rule 1 deviations documented (plan-supplied content vs plan AC mismatches: comma in description, regex grouping in fixed-string context, CRLF in pre-existing CSV, byte-escape vs shellcheck rule). AppInspect failure=0/error=0/warning=0; regression suite + new PROD-01 guard all green. PROD-01 fully closed. Next: `/gsd-plan-phase 5` to start Operational Readiness (PROD-03..PROD-07)._
