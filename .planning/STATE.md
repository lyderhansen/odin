---
gsd_state_version: 1.0
milestone: v1.0.0
milestone_name: milestone
status: Plan 01-02 executed; harness --quick green (Dim 1-3); Dim 4-6 awaiting plan 03 modules
last_updated: "2026-04-13T15:12:00Z"
last_activity: "2026-04-13 — Plan 01-02 (Wave 1 orchestrator + shared library) executed: 5 tasks, 5 files, 4 commits (3b10698, 41ccc1e, f9fb015, 8c186de)"
progress:
  total_phases: 3
  completed_phases: 0
  total_plans: 3
  completed_plans: 2
  percent: 67
---

# Project State — TA-ODIN

## Current Position

- **Milestone:** v1.0.0 — First Production Delivery (scope A–C)
- **Phase:** Phase 1 — Windows Parity (Wave 0, 1 complete, Wave 2 next)
- **Plan:** 01-02 complete (orchestrator + shared library); 01-03 next (6 Windows modules)
- **Status:** Plan 01-02 executed; harness --quick PASS (Dim 1-3); Dim 4-6 awaiting plan 03 modules
- **Progress:** [███████░░░] 67%
- **Last activity:** 2026-04-13 — Plan 01-02 (Wave 1 orchestrator + shared library) executed: 5 tasks, 5 files, 4 commits (3b10698, 41ccc1e, f9fb015, 8c186de)

## Milestone Scope (v1.0.0)

- **A.** Windows parity — `odin.ps1` orchestrator + six Windows modules matching Linux event format → **Phase 1**
- **B.** Production hardening — version drift fix, tunable guardrails, alerting, lint gates, two-app-split CI enforcement, shell-injection audit → **Phase 2**
- **C.** AppInspect compliance — both apps pass cloud vetting as a release gate → **Phase 3**

**Deferred to v1.1+:** D (testing harness), E (docs), F (Windows classification CSV content), G (packaging).

## Phase Map

| Phase | Name | Requirements | Status |
|-------|------|--------------|--------|
| 1 | Windows Parity | WIN-01..WIN-12 | Not started |
| 2 | Production Hardening | HARD-01..HARD-08 | Not started |
| 3 | AppInspect Compliance & Release Gate | APPI-01..APPI-06 | Not started |

## Accumulated Context

### Codebase facts (as of 2026-04-10)

- Linux side complete: 6 modules (services, ports, packages, cron, processes, mounts), bash orchestrator with 90s/module timeout and MAX_EVENTS=50000 guardrails, space-separated `key=value` output.
- Two-app split in place: `TA-ODIN/` (forwarders) and `ODIN_app_for_splunk/` (indexers/SH). Currently enforced only by human discipline — no mechanical guard.
- Windows orchestrator `odin.ps1` (v1.0.0) now ships the Wave 1 implementation: autodiscovers modules, Start-Job + Wait-Job -Timeout canonical pattern, fail-soft try/catch, D4 `exit_code=124` synthesis on Wait-Job timeout, canonical Linux-parity markers via dot-sourced `_common.ps1`. Splunk UF integration via `odin.path` wrapper + inputs.conf stanza pointing at `odin.path`. `props.conf` has `CHARSET = UTF-8` for CRLF normalization.
- Bash modules have **0% automated test coverage**. All verification is manual.
- Version drift: `TA-ODIN/bin/odin.sh` says `2.1.0`; both `app.conf` files say `2.2.0`. Will be reset to `1.0.0` at v1.0.0 release.
- Search-time classification lookups exist for Linux (services: 332 rows, ports: 206 rows, packages: 274 rows, log sources: 274 rows). Windows rows are deferred to v1.1 (group F).
- Three nightly saved searches produce host inventory, log source details, TA deployment matrix.
- One Dashboard Studio overview (`odin_overview.xml`).
- Dev tooling tests (`tools/tests/test_classification_coverage.py`, `test_generate_odin_data.py`) exist but cover synthetic data generation, not the modules themselves.

### Hard constraints

- Linux tech stack: Bash 4+ only. No Python, Perl, or compiled binaries on endpoints.
- Windows tech stack: PowerShell 5.1+ built-in cmdlets only. No PS Gallery, no `Add-Type`, no `Invoke-Expression`, no base64.
- Read-only on the host: no writes outside Splunk var, no network, no process kills, no config changes.
- Runtime budget: ≤90s per module, ≤120s total scan (Splunk input timeout), ≤50,000 events per module.
- Backwards-compatible event format: existing `odin:enumeration` sourcetype and field names are frozen.
- No Windows test hosts available — validation relies on static analysis, mock fixtures, deferred-pilot.
- Both apps must pass `splunk-appinspect` cloud vetting.

### Key decisions (from PROJECT.md)

- Full Windows parity (all 6 modules), not a subset.
- Registry-based Windows package enumeration, **not** `Win32_Product` (MSI self-repair side effect).
- Linux modules frozen unless audit finds a concrete defect.
- AppInspect is a hard gate, not optional.
- Packaging as `.tar.gz`, not `.spl`.

### Roadmap decisions (2026-04-10)

- 3 phases (coarse granularity per config.json).
- Strict build order: Windows Parity → Hardening → AppInspect. Rationale: CI lint gates and the two-app-split guard need real Windows code to inspect; AppInspect must run after all code it vets is frozen, otherwise the vet cycle repeats.
- Each phase is a "bucket of work" with 2–3 plans expected downstream.

## Todos

_None. Use `/gsd-add-todo` to capture ideas as they come up._

## Session Continuity

_Last session: 2026-04-13 — completed 01-02-PLAN.md (Wave 1 orchestrator + shared library). Next: `/gsd-execute-phase 1` for plan 01-03 (Wave 2 — 6 Windows modules: services, ports, packages, scheduled_tasks, processes, mounts)._
