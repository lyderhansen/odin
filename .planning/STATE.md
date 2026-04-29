---
gsd_state_version: 1.0
milestone: v1.0.2
milestone_name: host-metadata-enrichment
status: executing
last_updated: "2026-04-29T10:05:13.409Z"
last_activity: 2026-04-29
progress:
  total_phases: 7
  completed_phases: 7
  total_plans: 16
  completed_plans: 16
  percent: 100
---

# Project State — TA-ODIN

## Current Position

Phase: 09 (validation-docs-dashboard) — NOT STARTED
Plan: 0 of N (Phase 9 planning pending)

- **Active milestone:** **v1.0.2 — Host Metadata Enrichment** (5 requirements HOST-01..HOST-05; 3 phases 7/8/9; opened 2026-04-28)
- **Parallel/blocked milestone:** v1.0.1 — Production Readiness — **v1.0.1-rc1 released 2026-04-28** as GitHub prerelease; full v1.0.1 (no `-rc` suffix) blocked on Phase 6 (PROD-02) pilot acceptance criteria pending real infrastructure
- **Phase:** Phase 8 — Host Info — Windows **COMPLETE 2026-04-29** (1/1 plans: 08-01 HOST-02 Invoke-OdinEmitHostInfo with 13 fields + 8 PS helpers)
- **Plan:** 08-01 COMPLETE — _common.ps1 extended (178→536 lines), Invoke-OdinEmitHostInfo wired into odin.ps1, check-host-info.ps1 created
- **Status:** Phase 8 COMPLETE; awaiting Phase 9 planning (Validation + Docs + Dashboard)
- **Total Plans in Phase 8:** 1/1 COMPLETE

### v1.0.1 status (parallel — blocked on infra)

- Phase 4 — Windows Classification Data **COMPLETE 2026-04-17**
- Phase 5 — Operational Readiness **COMPLETE 2026-04-24** (Plans 05-01..05-04)
- Phase 6 — Pilot Validation (PROD-02) **deferred pending pilot infrastructure**
- Post-Phase-5 cleanup landed 2026-04-27..28: D-04-01, D-04-02, PROD-07 (d), orchestrator discovery fix, `duration_ms` parity, container Nivå 1 (14 signals), exploration outputs (note + 2 seeds for v1.0.2 + v1.1.0), version bump to 1.0.1, v1.0.1-rc1 released

### v1.0.2 status (active)

- Phase 7 — Host Info — Linux: **COMPLETE 2026-04-29** (1/1 plans — 07-01 HOST-01 emit_host_info 13 fields)
- Phase 8 — Host Info — Windows: **COMPLETE 2026-04-29** (1/1 plans — 08-01 HOST-02 Invoke-OdinEmitHostInfo 13 fields)
- Phase 9 — Validation + Docs + Dashboard: NOT STARTED (depends on Phase 7 + 8)

- **Progress (v1.0.2):** [######    ] 67% (2 of 3 phases complete)
- **Last activity:** 2026-04-29

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
| 5 | Operational Readiness | PROD-03, PROD-04, PROD-05, PROD-06, PROD-07 | **Complete 2026-04-24** (4/4 plans: 05-01 PROD-07 closed, 05-02 PROD-05+06 closed, 05-03 PROD-03 closed, 05-04 PROD-04 closed) |
| 6 | Pilot Validation | PROD-02 | Not started (release gate; the only requirement requiring real-host validation) |

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

### Plan 05-01 outcomes (2026-04-24)

- All 6 Linux module standalone fallbacks (`TA-ODIN/bin/modules/{cron,mounts,packages,ports,processes,services}.sh`) bumped from `ODIN_VERSION:-2.1.0` to `ODIN_VERSION:-1.0.0` and gained an `ODIN_MAX_EVENTS` guard inside their fallback `emit()` function (mirrors orchestrator behavior at `TA-ODIN/bin/odin.sh:55-71` for parity; closes Threat T2 standalone-version drift + Threat T3 unbounded-emission risk per plan threat model).
- `tools/tests/check-version-sync.sh` extended with Section 3: greps each module fallback for the canonical `1.0.0` value and exits 1 on drift. Induced-drift test confirmed exit 1 with `[HARD-01 / PROD-07 DRIFT]` message; revert restores PASS. shellcheck clean.
- Standalone-fallback gating (`if ! declare -f emit &>/dev/null`) preserved — orchestrator runs continue to use the orchestrator's `emit()` and never enter the fallback branch. Only direct module invocation (debug workflow) exercises the new code path.
- AppInspect TA-ODIN Enterprise scope: failure=0, error=0, warning=1 (pre-existing `check_for_indexer_synced_configs`, accepted per Phase 3 D9), success=13, na=7. Artifact at `.planning/artifacts/appinspect/ta-odin-phase05-wave0-plan01.json`.
- Full Phase 1+2+3+4 regression suite green: check-version-sync, check-two-app-split, injection-fixtures (10/10), windows-parity-harness (all dimensions), check-windows-classification.
- 3 commits: `6b53e34` (module patches), `d75d779` (check-version-sync.sh extension), `34270fa` (AppInspect baseline artifact).
- **PROD-07 fully closed** — sub-items (a)/(b)/(c) all delivered per plan D3 minimal scope. (d) `_common.sh` consolidation deferred to v1.1+ as planned.
- **One cross-plan-contamination deviation** documented in 05-01-SUMMARY.md Deviation 1: Plan 03's `DOCS/RUNBOOK.md` was created untracked in the shared working tree by the parallel Plan 03 executor and was inadvertently absorbed into Plan 01's commit `d75d779` due to a `git add` race in the shared index. History rewriting was rejected because Plan 02's commit `0030812` was already on top by the time the contamination was discovered. RUNBOOK.md content is byte-identical to Plan 03's intended artifact; Plan 03 executor will reconcile attribution in their own SUMMARY. **Recommendation: future parallel-wave executors should run in separate worktrees to prevent index races.**
- Duration ~7 min for the focused Plan 01 work.

### Plan 05-02 outcomes (2026-04-24)

- `ODIN_app_for_splunk/default/data/ui/views/odin_ops.xml` created — 178-line Dashboard Studio v2 view (`<dashboard version="2" theme="dark">` + JSON `<definition>`) with **7 visualization panels** covering ROADMAP §Phase 5 success criterion 5 (≥6 required): per-OS singlevalue success rate (Linux + Windows, 24h), p95 module runtime timechart (7d, by OS), distinct-hosts column timechart (30d, by OS stacked), event-volume column timechart (7d, top-20 hosts), module-failure heatmap (`splunk.table` with `rangeValue` cell-color thresholds — green/yellow/orange/red by failure count, per RESEARCH §1 fallback recommendation since `splunk.heatmap` is unproven in this codebase), top-10 truncating hosts table.
- `tools/tests/rollback-dryrun.sh` created — 180-line shellcheck-clean executable. Patches a `mktemp` copy of `inputs.conf` with `disabled = false` → `disabled = true` over both `[script://]` stanzas (Linux + Windows); runs an inline `python3 -c` configparser emulator confirming both stanzas would be skipped by splunkd at next reload; asserts `git diff --quiet -- TA-ODIN/default/inputs.conf` (real file MUST be byte-identical to HEAD); writes `.planning/artifacts/rollback-dryrun.md` with timestamps + counts + commit hash + PASS/FAIL verdict. Induced-failure detection verified end-to-end (replacing odin.sh with empty stub → POST_COUNT=0 → VERDICT=FAIL → exit 1; restored → exit 0). Two SC info-level findings suppressed with documented disable directives (SC2329 cleanup-via-trap; SC2016 markdown-backticks-in-single-quotes).
- `DOCS/ROLLBACK.md` created — 157-line operator-facing playbook matching `DOCS/ARCHITECTURE.md` + `DOCS/COMMANDS.md` terse style. Sections: when to roll back (tied to existing 3 alerts), Strategy A vs B comparison, Strategy A `local/inputs.conf` overlay step-by-step (both stanzas), Strategy B full uninstall step-by-step, verification SPL, reverting the rollback, dry-run artifact reference, explicit "what this does NOT cover" deferred-items section calling out PROD-02 live-fleet validation + Splunk Cloud Victoria + in-flight scan termination.
- `.github/workflows/ci.yml` extended with new "Rollback dry-run guard" CI step inserted between version-sync and injection-fixtures (mirrors check-version-sync wiring; <2s runtime).
- AppInspect ODIN_app_for_splunk Enterprise scope: failure=0, error=0, warning=0, success=14, not_applicable=7 — **byte-identical to Phase 4 final baseline** AND Wave 0 baseline. Artifact at `.planning/artifacts/appinspect/odin-app-phase05-wave0-plan02.json`. The new `splunk.timechart` and `splunk.table`-with-`rangeValue` viz components (not previously used in this codebase) introduced **zero** AppInspect findings.
- Full Phase 1+2+3+4 regression suite + new PROD-05 guard all green.
- 4 commits: `4041ef7` (odin_ops.xml dashboard), `0030812` (rollback-dryrun.sh + CI integration + initial artifact), `08863f2` (DOCS/ROLLBACK.md), `30404f5` (AppInspect baseline + Rule 1 windows-parity-harness fix + regenerated rollback artifact).
- **PROD-05 + PROD-06 both fully closed.**
- **One Rule 1 deviation** in `tools/tests/windows-parity-harness.sh`: pre-existing shellcheck findings (SC2164 missing `cd ... || exit` guard at line 19; SC2126 `grep | wc -l` at line 102 with existing rationale comment block) blocked the plan's `shellcheck tools/tests/*.sh` AC. Verified pre-existing via `git checkout HEAD~3 -- ... && shellcheck` — same exit 1 + same two findings. Applied minimal surgical fixes (added `|| { echo ...; exit 1; }` guard; added `# shellcheck disable=SC2126` directive citing the existing comment block above explaining WHY `grep | wc -l` was preferred over the buggy `grep -c` original). Verified harness still passes 6/6 Nyquist dimensions after fix.
- Duration ~7 min effective execution from T1 commit (`4041ef7` 10:54:58Z) to T4 commit (`30404f5` 11:02:23Z); 129 min wall-clock (includes parallel waiting on Plan 01/03).

### Plan 05-03 outcomes (2026-04-24)

- `DOCS/RUNBOOK.md` created (395 lines) with 4 alert-response entries (truncated, exit_code=124, non-124, fleet scan success rate below SLO) — each with the 4 mandated subsections (What it means / Diagnostic SPL / Remediation / Escalation). `<TBD per organization>` placeholder used for all 4 Escalation subsections (no real org context exists).
- `ODIN_app_for_splunk/default/savedsearches.conf` extended with 3rd alert stanza `alert_odin_fleet_scan_success_rate_below_slo` (definition-only per CONTEXT D2: `disabled = 1`, empty `cron_schedule`). SLO threshold = 95% as starting recommendation; operator tunes per-org after PROD-02 pilot baseline.
- AppInspect ODIN_app_for_splunk Enterprise scope: failure=0, error=0, warning=0, success=14, na=7 — byte-identical to baseline. Artifact at `.planning/artifacts/appinspect/odin-app-phase05-wave0-plan03.json`.
- 2 commits per Plan 03 wiring: `f87f328` (RUNBOOK.md + savedsearches.conf stanza). Note: RUNBOOK.md was inadvertently absorbed into Plan 01's commit `d75d779` due to a `git add` race in the shared worktree (documented in Plan 01 Deviation 1 as cross-plan-contamination); content is byte-identical to Plan 03's intended artifact.
- **PROD-03 fully closed.**

### Plan 05-04 outcomes (2026-04-24)

- `DOCS/INSTALL.md` created (189 lines) — Deployment Server rollout playbook covering both apps (TA-ODIN to UFs, ODIN_app_for_splunk to indexers/SHs) with serverclass binding examples for Linux-only / Windows-only / mixed fleets; per-OS prerequisites; post-install verification SPL.
- `DOCS/TROUBLESHOOTING.md` created (293 lines) with 12 `### Issue:` triples — 5 Linux (orchestrator-not-running, services-zero, packages-hang, mounts-NFS-hung, processes-truncated), 4 Windows (AppLocker/WDAC, packages-zero registry-perms, scheduled-task noise, UAC edge cases), 3 cross-platform (host_role-null with cross-ref to Phase 4 D-04-02 legacy role values, odin_host_inventory.csv stale, AppInspect failure).
- `DOCS/DATA-DICTIONARY.md` created (300 lines) with 11 `## type=` subsections (one per emitted event type from Linux + Windows modules: odin_start, odin_complete, odin_error, truncated, service, port, package, cron, scheduled_task, process, mount). Cross-platform parity note (WIN-08) front-loaded; `cron` vs `scheduled_task` divergence explicitly documented as the one Nyquist parity exception. Auxiliary event types (none_found, odin_warning, privilege_warning, mount_error) appended as appendix.
- `DOCS/UPGRADE.md` created (217 lines) — v1.0.0 -> v1.0.1 upgrade path covering all 7 PROD-* requirements (PROD-01 Windows classification, PROD-02 pilot TBD, PROD-03 runbook, PROD-04 admin docs, PROD-05 rollback, PROD-06 ops dashboard, PROD-07 module hygiene); pre-upgrade checks; in-place upgrade steps; post-upgrade verification; **alert activation procedure** for the new SLO alert (cross-ref to DOCS/RUNBOOK.md "Activating alerts" section); rollback pointer to DOCS/ROLLBACK.md.
- Both app READMEs gained `## Documentation` sections — TA-ODIN/README.md appended after `## Support`; ODIN_app_for_splunk/README.md appended after `## Version History`. 7 `../DOCS/` links each (INSTALL, TROUBLESHOOTING, DATA-DICTIONARY, UPGRADE, RUNBOOK, ROLLBACK, ARCHITECTURE) = 14 total, exceeds AC threshold of 12. Pure additions: zero pre-existing README content removed (`git diff -- ... | grep -E '^-[^-]' | wc -l` returns 0).
- Task 6 regression sweep: all 6 scripts green (HARD-01 PASS / HARD-07 PASS / HARD-08 10/10 / windows-parity-harness ALL DIMENSIONS PASSED / PROD-01 PASS / PROD-05 PASS) plus `shellcheck tools/tests/*.sh` exit 0. All 6 DOCS/ files >= 50 lines (smallest 157 ROLLBACK.md, largest 395 RUNBOOK.md). The rollback-dryrun.sh artifact at `.planning/artifacts/rollback-dryrun.md` was regenerated with current commit hash + timestamp (PASS verdict preserved) — expected per Plan 02 design.
- 5 commits (1 per task except T6 — regression-only no source changes): `de4c986` (T1 INSTALL.md), `6c3033a` (T2 TROUBLESHOOTING.md), `f7b2985` (T3 DATA-DICTIONARY.md), `92a4cb1` (T4 UPGRADE.md), `db2791b` (T5 README updates).
- **PROD-04 fully closed.** Phase 5 now FULLY COMPLETE (4/4 plans; PROD-03..07 all marked complete in REQUIREMENTS.md).
- Zero deviations — plan executed exactly as written; no Rule 1/2/3 auto-fixes, no Rule 4 architectural escalations.
- Pure documentation work: zero AppInspect impact (DOCS/ outside scan scope; README markdown additions tolerated), zero code changes.
- Duration ~9 min from Task 1 commit (`de4c986` ~10:30Z) to Task 6 SUMMARY (~10:39Z).

## Todos

_None. Use `/gsd-add-todo` to capture ideas as they come up during planning._

## Session Continuity

_Last session: 2026-04-29 — Plan 08-01 (HOST-02: Invoke-OdinEmitHostInfo Windows) executed end-to-end. 10/10 tasks committed: `1b74c08` (T1 ODIN_IMDS_TIMEOUT), `9478668` (T2 OS detection), `6b62678` (T3 hardware+runtime), `5e55e72` (T4 network), `a95558f` (T5 virtualization), `d1a6dae` (T6 IMDS cloud probe), `cdf09b4` (T7 Invoke-OdinEmitHostInfo aggregator + Rule 1 fix), `dbe24d7` (T8 odin.ps1 integration), `4f32b6d` (T9 regression test), `b4bc0a9` (T10 changelog). _common.ps1 extended from 178 to 536 lines with 8 PowerShell mirror helpers. type=odin_host_info event emitted as event #2 with all 13 fields. Windows parity harness ALL DIMENSIONS PASSED, Linux regression tests all green. Phase 8 COMPLETE; next: Phase 9 (Validation + Docs + Dashboard). Previously: Plan 07-01 (HOST-01: emit_host_info Linux) executed end-to-end. 10/10 tasks committed: `0177469` (T1 idempotent _common.sh), `4fb4553` (T2 OS detection), `01b09e0` (T3 hardware+runtime), `43f1279` (T4 network), `7e0ac96` (T5 virtualization), `7b57a5a` (T6 IMDS cloud probe), `8801f62` (T7 emit_host_info aggregator), `295e15b` (T8 odin.sh integration), `b47c01d` (T9 regression test), `13d73e9` (T10 changelog). _common.sh extended from 60 to 338 lines with 8 detection helpers. type=odin_host_info event emitted as event #2 with all 13 fields. check-host-info.sh exits 0 with 6 PASS markers. Zero deviations. Phase 7 COMPLETE; next: Phase 8 (Host Info — Windows). Previously: Plan 05-04 (Wave 1 PROD-04 admin docs cluster) executed end-to-end. 6/6 tasks committed: `de4c986` DOCS/INSTALL.md (189 lines, Deployment Server rollout playbook), `6c3033a` DOCS/TROUBLESHOOTING.md (293 lines, 12 ### Issue triples — 5 Linux + 4 Windows + 3 cross-platform; cross-refs Phase 4 D-04-02 deferred-items legacy role values), `f7b2985` DOCS/DATA-DICTIONARY.md (300 lines, 11 ## type= subsections covering all canonical event types from Linux + Windows modules; cross-platform parity note WIN-08 front-loaded), `92a4cb1` DOCS/UPGRADE.md (217 lines, v1.0.0 -> v1.0.1 path covering all 7 PROD-* requirements + alert activation procedure cross-ref to RUNBOOK.md + rollback pointer to ROLLBACK.md), `db2791b` README updates (both apps gain ## Documentation section with 7 ../DOCS/ links each = 14 total, pure additions zero pre-existing content removed). Task 6 regression sweep: all 6 scripts exit 0 (check-version-sync HARD-01, check-two-app-split HARD-07, injection-fixtures HARD-08 10/10, windows-parity-harness all dimensions, check-windows-classification PROD-01, rollback-dryrun PROD-05) plus shellcheck clean. All 6 DOCS/ files >= 50 lines (smallest 157, largest 395). Zero deviations — plan executed exactly as written. PROD-04 fully closed; Phase 5 now FULLY COMPLETE (4/4 plans, PROD-03..07 all closed in REQUIREMENTS.md). Milestone progress: 2/3 phases = 67%. Next: spawn Phase 6 planning (PROD-02 pilot validation — release gate, requires real-host deployment to ≥5 Linux + ≥5 Windows hosts for 7-day observation window)._
