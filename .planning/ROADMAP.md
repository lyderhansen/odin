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

- [ ] **Phase 4: Windows Classification Data** — Populate Windows-specific rows in the four classification lookups so Windows hosts classify to meaningful roles and produce a non-empty TA deployment matrix.
- [ ] **Phase 5: Operational Readiness** — Ship the docs, runbook, rollback procedure, and ops observability dashboard that an SRE needs to operate TA-ODIN in production without asking the original author.
- [ ] **Phase 6: Pilot Validation** — Deploy to ≥5 Linux + ≥5 Windows real hosts via Deployment Server for a 7-day observation window and capture the telemetry that confirms fleet-deploy readiness.

## Phase Details

### Phase 4: Windows Classification Data
**Goal:** Every piloted Windows host — regardless of role (DC, IIS web server, SQL server, file server, print server, DHCP, DNS, generic member server, generic workstation) — classifies to at least one `host_role` in the `odin_host_inventory` saved search and surfaces at least one recommended TA in the deployment matrix.
**Depends on:** Nothing (data-only changes inside `ODIN_app_for_splunk/lookups/`, zero code churn)
**Requirements:** PROD-01
**Success Criteria** (what must be TRUE):
  1. `wc -l ODIN_app_for_splunk/lookups/odin_classify_services.csv` is strictly greater than its pre-Phase-4 count (332), and `grep -ic 'windows\|mssql\|iis\|w3svc\|adws\|ntds\|dhcp\|dnsserver\|exchange\|winrm\|spooler' ODIN_app_for_splunk/lookups/odin_classify_services.csv` returns at least 20 — proves meaningful Windows service coverage was added, not a token row.
  2. `grep -c '/tcp\|/udp' ODIN_app_for_splunk/lookups/odin_classify_ports.csv` grows by at least 15 rows and includes the canonical Windows port signals (`135/tcp`, `139/tcp`, `445/tcp`, `3389/tcp`, `5985/tcp`, `5986/tcp`, `88/tcp`, `389/tcp`, `636/tcp`, `53/tcp`, `53/udp`, `1433/tcp`, `1434/udp`) — proves port-based host-role classification works on Windows.
  3. `odin_classify_packages.csv` contains at least 30 Windows-specific registry display names (`Microsoft SQL Server *`, `Microsoft Internet Information Services`, `Active Directory *`, `Microsoft Exchange *`, `Windows Server *`, etc.) — verified by `grep -ic 'microsoft\|windows server\|active directory\|iis\|sql server' ODIN_app_for_splunk/lookups/odin_classify_packages.csv`.
  4. `odin_log_sources.csv` has at least 15 new rows whose `signal_type` is one of `service|port|package`, whose `host_role` is a Windows role (e.g. `windows_dc`, `windows_iis`, `windows_sql`, `windows_file`, `windows_generic`), and whose `log_source`/`sourcetype`/`recommended_ta` columns are filled — enabling the TA deployment matrix saved search to produce rows for piloted Windows hosts.
  5. A synthetic Windows event replay (`tools/tests/windows-fixtures/hostA` or equivalent) fed through the classification SPL produces at least one `host_role` that starts with `windows_*` and at least one recommended TA — confirmed by running the host-inventory saved search SPL against the fixture and piping through `stats`.
**Plans:** TBD (1–2 plans expected — single large data PR, or split by lookup file)
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
**Plans:** TBD (2–3 plans expected — docs cluster, rollback cluster, dashboard + module hygiene cluster)
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

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 4. Windows Classification Data | 0/TBD | Not started | — |
| 5. Operational Readiness | 0/TBD | Not started | — |
| 6. Pilot Validation | 0/TBD | Not started | — |

## Coverage

- **Total v1.0.1 requirements:** 7 (PROD-01..PROD-07)
- **Mapped:** 7/7
- **Orphans:** 0
- **Duplicates:** 0

## Archived Milestones

- **v1.0.0** (First Production Delivery) — 26 requirements (WIN-01..12, HARD-01..08, APPI-01..06), 3 phases, shipped 2026-04-15, tag `v1.0.0` on `origin/main`. Detailed phase structure preserved in git history and in `.planning/phases/01-windows-parity/`, `02-production-hardening/`, `03-appinspect-compliance/`.
