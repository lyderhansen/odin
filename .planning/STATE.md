# Project State — TA-ODIN

## Current Position

- **Milestone:** v1.0.0 — First Production Delivery (scope A–C)
- **Phase:** Not started (defining requirements → roadmap)
- **Plan:** —
- **Status:** Defining requirements
- **Last activity:** 2026-04-10 — Milestone v1.0.0 started via `/gsd-new-milestone`

## Milestone Scope (v1.0.0)

- **A.** Windows parity — `odin.ps1` orchestrator + six Windows modules matching Linux event format
- **B.** Production hardening — version drift fix, tunable guardrails, alerting, lint gates, two-app-split CI enforcement, shell-injection audit
- **C.** AppInspect compliance — both apps pass cloud vetting as a release gate

**Deferred to v1.1+:** D (testing harness), E (docs), F (Windows classification CSV content), G (packaging).

## Accumulated Context

### Codebase facts (as of 2026-04-10)
- Linux side complete: 6 modules (services, ports, packages, cron, processes, mounts), bash orchestrator with 90s/module timeout and MAX_EVENTS=50000 guardrails, space-separated `key=value` output.
- Two-app split in place: `TA-ODIN/` (forwarders) and `ODIN_app_for_splunk/` (indexers/SH). Currently enforced only by human discipline — no mechanical guard.
- Windows orchestrator `odin.ps1` is a stub that emits one "not yet implemented" event.
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

## Todos

_None. Use `/gsd-add-todo` to capture ideas as they come up._

## Session Continuity

_No pending handoff._
