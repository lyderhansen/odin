# Roadmap — TA-ODIN v1.0.1

**Milestone:** v1.0.1 — Production Readiness
**Granularity:** coarse (3 phases)
**Created:** 2026-04-15
**Previous milestone:** v1.0.0 (First Production Delivery) — shipped 2026-04-15, tag `v1.0.0` on `origin/main`

## Goal

Take v1.0.0 from pilot-ready to fleet-deployable by closing the operational, observability, and documentation gaps that block safe rollout beyond ~50 hosts. Every requirement in this milestone either enables or validates that TA-ODIN can be pushed to 10k+ hosts without a "we don't know what will happen" conversation.

## Build-Order Rationale

Three phases, executed strictly in order:

1. **Phase 4 (Windows Classification Data)** lands first because it is pure data work — no code changes, no schema changes, no risk of breaking v1.0.0. It unblocks a pilot on real Windows hosts: without Windows rows in the classification CSVs, Windows hosts in the pilot would produce `host_role = null` and make PROD-02 impossible to interpret.
2. **Phase 5 (Operational Readiness)** lands second because docs, runbook, rollback procedure, and ops dashboard should be written against the *final* v1.0.1 config (including Phase 4's classification additions). Writing docs against v1.0.0 only would create a drift window where the docs don't match the pilot-deployed version.
3. **Phase 6 (Pilot Validation)** lands last because it is the release gate that validates everything Phases 4 and 5 produced. The pilot is the only requirement that runs against real hosts — all other requirements can be satisfied at a desk. Running the pilot before the runbook exists would leave on-call with no guidance when alerts fire.

## Phases

- [x] **Phase 4: Windows Classification Data** — Populate Windows-specific rows in the four classification lookups so Windows hosts classify to meaningful roles and produce a non-empty TA deployment matrix. **COMPLETE 2026-04-17 (Plans 04-01 + 04-02; PROD-01 closed; AppInspect Enterprise scope clean; PROD-01 regression guard added).**
- [x] **Phase 5: Operational Readiness** — Ship the docs, runbook, rollback procedure, and ops observability dashboard that an SRE needs to operate TA-ODIN in production without asking the original author. **COMPLETE 2026-04-24 (Plans 05-01 + 05-02 + 05-03 + 05-04; PROD-03..07 all closed; AppInspect Enterprise scope clean across all changes; full Phase 1+2+3+4 regression suite green).**
- [ ] **Phase 6: Pilot Validation** — Deploy to ≥5 Linux + ≥5 Windows real hosts via Deployment Server for a 7-day observation window and capture the telemetry that confirms fleet-deploy readiness.

> **— v1.0.2 milestone begins (Host Metadata Enrichment) —**

- [x] **Phase 7: Host Info — Linux** — Linux orchestrator emits `type=odin_host_info` event once per scan with all 13 host metadata fields (OS identity, hardware, network, virtualization, cloud detection). **COMPLETE 2026-04-29** (1/1 plans — HOST-01 closed)
- [x] **Phase 8: Host Info — Windows** — Windows orchestrator emits the same `type=odin_host_info` event with all 13 fields populated via Windows-native methods (Get-CimInstance, Win32_OperatingSystem, etc.). **COMPLETE 2026-04-29** (1/1 plans — HOST-02 closed)
- [x] **Phase 9: Validation + Docs + Dashboard** — Cross-platform parity validation, DATA-DICTIONARY.md update, and odin_overview.xml dashboard panels for OS distribution + virtualization breakdown. **COMPLETE 2026-04-29** (3/3 plans — HOST-03..05 all closed; AppInspect failure=0 error=0 warning=0)

## Phase Details

### Phase 4: Windows Classification Data
**Goal:** Every piloted Windows host — regardless of role (DC, IIS web server, SQL server, file server, print server, DHCP, DNS, generic member server, generic workstation) — classifies to at least one `host_role` in the `odin_host_inventory` saved search and surfaces at least one recommended TA in the deployment matrix.
**Depends on:** Nothing (data-only changes inside `ODIN_app_for_splunk/lookups/`, zero code churn)
**Requirements:** PROD-01
**Success Criteria** (what must be TRUE):
  1. `wc -l ODIN_app_for_splunk/lookups/odin_classify_services.csv` is strictly greater than its pre-Phase-4 count (332), and `grep -ic 'windows\|mssql\|iis\|w3svc\|adws\|ntds\|dhcp\|dnsserver\|exchange\|winrm\|spooler' ODIN_app_for_splunk/lookups/odin_classify_services.csv` returns at least 20 — proves meaningful Windows service coverage was added, not a token row.
  2. `grep -c '/tcp\|/udp' ODIN_app_for_splunk/lookups/odin_classify_ports.csv` grows by at least 15 rows and includes the canonical Windows port signals (`135/tcp`, `139/tcp`, `445/tcp`, `3389/tcp`, `5985/tcp`, `5986/tcp`, `88/tcp`, `389/tcp`, `636/tcp`, `53/tcp`, `53/udp`, `1433/tcp`, `1434/udp`) — proves port-based host-role classification works on Windows.
  3. `odin_classify_packages.csv` contains at least 30 Windows-specific registry display names (`Microsoft SQL Server *`, `Microsoft Internet Information Services`, `Active Directory *`, `Microsoft Exchange *`, `Windows Server *`, etc.) — verified by `grep -ic 'microsoft\|windows server\|active directory\|iis\|sql server' ODIN_app_for_splunk/lookups/odin_classify_packages.csv`.
  4. `odin_log_sources.csv` has at least 15 new rows whose `signal_type` is one of `service|port|package`, whose `host_role` is a Windows-mapped cross-platform role per CONTEXT.md D1 (e.g. `domain_controller`, `web_server`, `database_server`, `mail_server`, `file_server`, `dns_server`, `dhcp_server`, `print_server`, `virtualization_host`, `identity_server`, `certificate_server`, `rdp_server`, `management_server`, `ha_cluster`, `windows_management`, `windows_host`), and whose `log_source`/`sourcetype`/`recommended_ta` columns are filled — enabling the TA deployment matrix saved search to produce rows for piloted Windows hosts.
  5. A synthetic Windows event replay (`tools/tests/windows-fixtures/hostA` or equivalent — or the inline-simulated signal join used by `tools/tests/check-windows-classification.sh`) produces at least one `host_role` from the Windows-mapped cross-platform set per D1 and at least one recommended TA — confirmed via the regression script or by running the host-inventory saved search SPL against the fixture and piping through `stats`.
**Plans:** 2 of 2 complete (04-01 services+ports Wave 0 shipped 2026-04-17; 04-02 packages+log_sources+regression-guard Wave 1 shipped 2026-04-17)
**UI hint:** no

### Phase 5: Operational Readiness
**Goal:** Every ops-visible failure mode, runtime alert, and common admin task has a documented procedure that an on-call engineer — who has never seen TA-ODIN before — can follow end-to-end to reach a working outcome. The ops dashboard surfaces the telemetry an operator needs to answer "is the fleet healthy?" at a glance.
**Depends on:** Phase 4 (docs and dashboard panels reference the classified-host output, so Phase 4's classification data needs to be in place before docs are finalized and dashboard searches are written)
**Requirements:** PROD-03, PROD-04, PROD-05, PROD-06, PROD-07
**Success Criteria** (what must be TRUE):
  1. `DOCS/RUNBOOK.md` exists and contains at least 4 alert-response entries: one for `type=truncated`, one for `type=odin_error exit_code=124`, one for `type=odin_error` (non-124), and one for "fleet scan success rate below SLO". Each entry has sections: *What it means*, *Diagnostic SPL*, *Remediation*, *Escalation*. Verified by `grep -c '^### ' DOCS/RUNBOOK.md` ≥ 4 and `grep -c 'Diagnostic SPL' DOCS/RUNBOOK.md` ≥ 4.
  2. `DOCS/INSTALL.md`, `DOCS/TROUBLESHOOTING.md`, `DOCS/DATA-DICTIONARY.md`, and `DOCS/UPGRADE.md` all exist and are non-trivial (≥50 lines each), and both app-root READMEs (`TA-ODIN/README.md`, `ODIN_app_for_splunk/README.md`) reference these docs by relative path — verified by `test -s DOCS/INSTALL.md && test -s DOCS/TROUBLESHOOTING.md && test -s DOCS/DATA-DICTIONARY.md && test -s DOCS/UPGRADE.md` plus line-count spot checks.
  3. `DOCS/DATA-DICTIONARY.md` has one subsection per `type=*` event (`odin_start`, `odin_complete`, `odin_error`, `truncated`, `service`, `port`, `package`, `scheduled_task`, `process`, `mount`) and each subsection lists every field name the module can emit — verified by `grep -c '^## type=' DOCS/DATA-DICTIONARY.md` ≥ 10.
  4. `DOCS/ROLLBACK.md` documents the exact Deployment Server steps to disable TA-ODIN via `disabled = 1` in a local overlay without removing files, AND `.planning/artifacts/rollback-dryrun.md` contains a timestamped dry-run log showing (a) pre-toggle event count on a pilot host, (b) toggle applied, (c) event count drops to zero within one scan cycle, (d) toggle reverted, (e) events resume — proving the procedure is rehearsed, not theoretical.
  5. `ODIN_app_for_splunk/default/data/ui/views/odin_ops.xml` exists as a valid Dashboard Studio view, is exported via `metadata/default.meta`, contains panels for *scan success rate per OS*, *module runtime p95 per module*, *module-failure heatmap*, *event volume per host per day*, and *distinct hosts seen over time*, and the new view does not regress AppInspect: `splunk-appinspect inspect ODIN_app_for_splunk --mode precert --excluded-tags cloud` still exits with `summary.failure + summary.error = 0`.
  6. All 6 Linux modules (`TA-ODIN/bin/modules/*.sh`) use `ODIN_VERSION="${ODIN_VERSION:-1.0.0}"` in their standalone fallback (not `2.1.0`), and standalone `emit` checks `ODIN_MAX_EVENTS` and emits `type=truncated` at the cap. `check-version-sync.sh` now greps module fallbacks and fails on stale version strings. Optionally, standalone helpers are consolidated into `modules/_common.sh`. Verified by: `bash TA-ODIN/bin/modules/services.sh 2>&1 | head -1 | grep -c 'odin_version=1.0.0'` returns 1; `ODIN_MAX_EVENTS=2 bash TA-ODIN/bin/modules/services.sh 2>&1 | grep -c type=truncated` returns ≥1; `check-version-sync.sh` exits 0.
**Plans:** 4 of 4 complete. Wave 0 complete 2026-04-24: **05-01 complete** (PROD-07 closed: 6 module fallbacks bumped to 1.0.0 + MAX_EVENTS guard + check-version-sync.sh Section 3 drift gate); **05-02 complete** (PROD-05 + PROD-06 closed: 178-line `odin_ops.xml` Dashboard Studio v2 view with 7 panels + 180-line `tools/tests/rollback-dryrun.sh` shell-fixture validator + 157-line `DOCS/ROLLBACK.md` operator playbook + new CI hard-gate; AppInspect Enterprise scope failure=0/error=0/warning=0 byte-identical to Phase 4 baseline); **05-03 complete** (PROD-03 + SLO alert closed). Wave 1 complete 2026-04-24: **05-04 complete** (PROD-04 closed: 4 new admin docs — INSTALL 189 lines, TROUBLESHOOTING 293 lines, DATA-DICTIONARY 300 lines, UPGRADE 217 lines — plus Documentation sections appended to both app READMEs linking all 6 Phase 5 docs; pure documentation, zero code changes, zero AppInspect impact, full regression suite green).
**UI hint:** yes (Dashboard Studio view for PROD-06)

### Phase 6: Pilot Validation
**Goal:** TA-ODIN v1.0.1 runs unattended on ≥5 Linux + ≥5 Windows real hosts for a continuous 7-day window with a module-success rate ≥95%, no silent failures, no unexplained truncation, and every piloted host visible in the host inventory with a classified role. When this phase closes, the TA is ready for ring-1 rollout (50–100 host tier).
**Depends on:** Phase 4 (classification data must be live so Windows pilot hosts produce classified output) AND Phase 5 (runbook must exist so on-call knows what to do if alerts fire during the pilot)
**Requirements:** PROD-02
**Success Criteria** (what must be TRUE):
  1. `.planning/artifacts/pilot-v1.0.1/` contains a `deployment.md` file listing ≥5 Linux and ≥5 Windows pilot hostnames, their OS versions, their Deployment Server serverclass bindings, and the timestamp v1.0.1 landed on each — verifiable by `grep -c 'linux\|windows' .planning/artifacts/pilot-v1.0.1/deployment.md` ≥ 10.
  2. A Splunk search covering the pilot's 7-day observation window against `index=odin_discovery sourcetype=odin:enumeration type=odin_complete` shows `avg(modules_failed)` < 0.05 per host across the pilot fleet — captured as `.planning/artifacts/pilot-v1.0.1/success-rate.csv` (one row per host, columns `host, runs, successful, modules_failed_avg`).
  3. Every `type=truncated` or `type=odin_error` event emitted during the pilot window is either (a) linked to a documented expected cause in `.planning/artifacts/pilot-v1.0.1/alerts-log.md`, or (b) triaged as an in-pilot bug and fixed before pilot closure — verified by a spreadsheet of all alert events and their resolution status.
  4. `| inputlookup odin_host_inventory.csv | search host IN (<pilot hosts>)` returns one row per pilot host, each with a non-empty `host_roles` and `recommended_tas` field — proving Phase 4's classification data works on real-world Windows and Linux hosts, not just synthetic fixtures.
  5. A short go/no-go report (`.planning/artifacts/pilot-v1.0.1/release-gate.md`) summarizes the 7-day window, lists any deviations from the success criteria, and carries an explicit "ring-1 ready: yes/no" verdict signed off by the milestone owner.
**Plans:** TBD (1 plan expected — deploy + observe + capture artifacts)
**UI hint:** no

### Phase 7: Host Info — Linux
**Goal:** Linux orchestrator (`TA-ODIN/bin/odin.sh`) emits exactly one `type=odin_host_info` event per scan, positioned between `type=odin_start` and the first module event, populated with all 13 host metadata fields. The event uses the standard envelope (timestamp/hostname/os/run_id/odin_version) and follows the established `key=value` format.
**Depends on:** v1.0.1-rc1 release (HARD-01 version sync at 1.0.1 confirmed; orchestrator architecture stable).
**Requirements:** HOST-01
**Success Criteria** (what must be TRUE):
  1. `bash TA-ODIN/bin/odin.sh` produces output containing exactly ONE line matching `type=odin_host_info` and the line contains all 13 named fields (`os_distro`, `os_version`, `os_pretty`, `os_kernel`, `os_arch`, `cpu_cores`, `mem_total_mb`, `uptime_seconds`, `fqdn`, `ip_primary`, `virtualization`, `cloud_provider`, `cloud_region`).
  2. On a host without cloud metadata, IMDS probes complete cleanly within 2 seconds total (no module-timeout cascade); `cloud_provider=none` and `cloud_region=none` (or empty) are emitted.
  3. The event ordering is deterministic: `type=odin_start` is line 1, `type=odin_host_info` is line 2, modules run after that. Verified by `bash TA-ODIN/bin/odin.sh | head -2 | tail -1 | grep -c type=odin_host_info` returns 1.
  4. Existing v1.0.1 functionality unaffected: HARD-01, PROD-01, HARD-07, PROD-05, windows-parity-harness all still PASS; AppInspect TA-ODIN baseline preserved (failure=0, error=0, warning=1).
**Plans:** TBD (1-2 plans expected — helper functions in `_common.sh` + orchestrator integration + IMDS timeout safety + tests)
**UI hint:** no

### Phase 8: Host Info — Windows
**Goal:** Windows orchestrator (`TA-ODIN/bin/odin.ps1`) emits the same `type=odin_host_info` event with all 13 fields populated via Windows-native methods, achieving cross-platform parity with the Linux orchestrator.
**Depends on:** Phase 7 (Linux implementation establishes the event shape, field semantics, and IMDS timeout pattern that Windows mirrors).
**Requirements:** HOST-02
**Success Criteria** (what must be TRUE):
  1. `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File TA-ODIN\bin\odin.ps1` produces output containing exactly ONE line matching `type=odin_host_info` and the line contains all 13 named fields populated via Windows-native methods (Win32_OperatingSystem, Win32_Processor, Get-NetRoute, etc.).
  2. Cloud IMDS probes use `Invoke-RestMethod` with explicit 2s timeout; on hosts without cloud metadata the orchestrator does not hang or trigger Splunk's 120s scripted-input timeout.
  3. Field values follow Windows conventions where appropriate: `os_distro=windows`, `os_arch` reports `amd64` or `arm64` (per `$env:PROCESSOR_ARCHITECTURE`), `virtualization` reports detected hypervisor or `baremetal`/`container`/`none`.
  4. Existing v1.0.1 Windows functionality unaffected: AppInspect TA-ODIN baseline preserved (failure=0, error=0, warning=1).
**Plans:** 1 of 1 complete (08-01 HOST-02 closed: _common.ps1 extended 178→536 lines, 8 PS helpers, Invoke-OdinEmitHostInfo, odin.ps1 integration, check-host-info.ps1)
**UI hint:** no

### Phase 9: Validation + Docs + Dashboard
**Goal:** Cross-platform parity validated end-to-end, DATA-DICTIONARY documents the new event type, and the odin_overview.xml dashboard surfaces the new metadata so operators can see fleet OS distribution and virtualization breakdown.
**Depends on:** Phase 7 AND Phase 8 (both implementations must be in place before parity testing + documentation lock-in).
**Requirements:** HOST-03, HOST-04, HOST-05
**Success Criteria** (what must be TRUE):
  1. New regression script (`tools/tests/check-host-info-parity.sh` or extension to `windows-parity-harness.sh`) validates that Linux and Windows orchestrators produce a `type=odin_host_info` event with the same field set (modulo platform-specific values for `os_arch`/`os_kernel`). Script exits 0 on parity, exits 1 on field-set divergence.
  2. `DOCS/DATA-DICTIONARY.md` contains a `## type=odin_host_info` section with: descriptive overview, complete 13-field reference (description + source + example value per field), one worked example event line in the canonical envelope format, and a note on cloud-detection timeout semantics. Verified by `grep -c '^## type=odin_host_info' DOCS/DATA-DICTIONARY.md` returns 1.
  3. `ODIN_app_for_splunk/default/data/ui/views/odin_overview.xml` adds at least 2 new dashboard panels: (a) "OS Distribution" showing `count by os_distro,os_version` from the latest `type=odin_host_info` per host, (b) "Virtualization Breakdown" showing `count by virtualization`. Verified by `grep -c '<viz' ODIN_app_for_splunk/default/data/ui/views/odin_overview.xml` increases by ≥2 vs the v1.0.1-rc1 baseline.
  4. AppInspect on `ODIN_app_for_splunk` after dashboard changes still PASS with `failure=0, error=0, warning=0`. Saved as `.planning/artifacts/appinspect/odin-app-1.0.2-phase9.json`.
  5. UAT cycle (`/gsd-verify-work 9`) passes with all 5 v1.0.2 requirements (HOST-01..HOST-05) marked as DONE.
**Plans:** 3 of 3 complete (09-01 HOST-03: check-host-info-parity.sh; 09-02 HOST-04: DATA-DICTIONARY.md type=odin_host_info; 09-03 HOST-05: odin_overview.xml +2 panels viz count 10→12)
**UI hint:** yes (Dashboard Studio panels added to existing odin_overview.xml)

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 4. Windows Classification Data | 2/2 | Complete | 2026-04-17 |
| 5. Operational Readiness | 4/4 | Complete | 2026-04-24 |
| 6. Pilot Validation | 0/TBD | Not started — pending real infra | — |
| 7. Host Info — Linux | 1/1 | Complete | 2026-04-29 |
| 8. Host Info — Windows | 1/1 | Complete | 2026-04-29 |
| 9. Validation + Docs + Dashboard | 3/3 | Complete (HOST-03/04/05 closed; UAT signed off 2026-04-29) | 2026-04-29 |

## Coverage

### v1.0.1 — Production Readiness
- **Total requirements:** 7 (PROD-01..PROD-07)
- **Mapped:** 7/7 (PROD-01 → Phase 4; PROD-03..07 → Phase 5; PROD-02 → Phase 6)
- **Orphans:** 0
- **Duplicates:** 0

### v1.0.2 — Host Metadata Enrichment
- **Total requirements:** 5 (HOST-01..HOST-05)
- **Mapped:** 5/5 (HOST-01 → Phase 7; HOST-02 → Phase 8; HOST-03..05 → Phase 9)
- **Orphans:** 0
- **Duplicates:** 0

## Archived Milestones

- **v1.0.0** (First Production Delivery) — 26 requirements (WIN-01..12, HARD-01..08, APPI-01..06), 3 phases, shipped 2026-04-15, tag `v1.0.0` on `origin/main`. Detailed phase structure preserved in git history and in `.planning/phases/01-windows-parity/`, `02-production-hardening/`, `03-appinspect-compliance/`.
