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

> **— v1.1.0 milestone begins (Container Observability) —**

- [ ] **Phase 10: Container Environment Detection** — Linux + Windows orchestrators enrich `type=odin_host_info` event with 3 new container fields (`container_runtime`, `container_id`, `container_image_hint`) when running INSIDE a container; DATA-DICTIONARY.md extended.
- [ ] **Phase 11: Container Enumeration Module** — New `bin/modules/containers.{sh,ps1}` enumerates running containers (docker/podman/kubectl) and emits one `type=container` event per container with 8 fields. Edge case handling for missing/unreachable runtimes. New regression test + CI gate.
- [ ] **Phase 12: Image-based Classification + Dashboard** — New `odin_classify_container_images.csv` WILDCARD lookup (≥30 image patterns), new saved search producing `odin_container_inventory.csv`, new dashboard panel(s) for container density per host.

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

### Phase 10: Container Environment Detection
**Goal:** Both orchestrators (Linux + Windows) detect when running INSIDE a container and enrich the existing `type=odin_host_info` event with 3 new fields (`container_runtime`, `container_id`, `container_image_hint`) so SOC analysts can immediately distinguish container workloads from host workloads in fleet dashboards. DATA-DICTIONARY.md documents the new fields with the same per-field 4-item structure (Description + Source (Linux) + Source (Windows) + Example) established by HOST-04 D-10 convention.
**Depends on:** v1.0.2 milestone shipped (Phase 7+8+9 — orchestrators + DATA-DICTIONARY structure must exist as the base for additive enrichment).
**Requirements:** CONT-01, CONT-02, CONT-03
**Success Criteria** (what must be TRUE):
  1. Running `bash TA-ODIN/bin/odin.sh` INSIDE a Linux container (e.g. `docker run --rm rocky:9 bash`) produces a `type=odin_host_info` event with `virtualization=container container_runtime=docker container_id=<12-hex-prefix>`. On baremetal Linux: same event has `container_runtime=none container_id=none container_image_hint=none` (D-03 sentinel discipline).
  2. Running `powershell.exe -ExecutionPolicy Bypass -File TA-ODIN\bin\odin.ps1` INSIDE a Windows container produces parity output with the same 3 new fields populated. Baremetal Windows: same `none` sentinels.
  3. `DOCS/DATA-DICTIONARY.md` `## type=odin_host_info` section contains 3 new field headings (`#### \`container_runtime\``, `#### \`container_id\``, `#### \`container_image_hint\``), each with the 4-item per-field structure. Verified by `grep -cE '^#### \`container_' DOCS/DATA-DICTIONARY.md` returns 3.
  4. Worked example event line in DATA-DICTIONARY.md updated to include a container scenario (e.g. row showing rocky-on-docker with container_runtime=docker).
  5. AppInspect on both apps after the orchestrator changes still PASS with `failure=0, error=0, warning=0` (no new findings introduced by the additive field enrichment).
**Plans:** TBD (likely 1 plan covering Linux+Windows+docs since all 3 REQs share orchestrator+_common file paths and have natural sequential dependency Linux-then-Windows-then-docs)
**UI hint:** no (event-emission + docs only; no dashboard changes in this phase)

### Phase 11: Container Enumeration Module
**Goal:** TA-ODIN can run on a Docker or Kubernetes host and enumerate every running container/pod, emitting one `type=container` event per container with 8 fields covering identity, image, name, command, ports, runtime, state, and start time. Cross-platform parity (Linux + Windows containers via Docker Desktop / Mirantis). Edge cases (no runtime / daemon unreachable / RBAC denied) handled gracefully without aborting the orchestrator. New regression test added to CI.
**Depends on:** Phase 10 (container env detection establishes the runtime-detection helpers that the enumeration module reuses; sharing detection logic via `_common.{sh,ps1}` avoids duplication).
**Requirements:** CONT-04, CONT-05, CONT-06, CONT-07
**Success Criteria** (what must be TRUE):
  1. On a Linux host running 3 containers via Docker, `bash TA-ODIN/bin/odin.sh | grep -c '^.*type=container'` returns 3, and each `type=container` event contains all 8 named fields (`container_id`, `container_image`, `container_name`, `container_command`, `container_ports`, `container_runtime`, `container_state`, `container_started_at`).
  2. On a Windows host with Docker Desktop running 2 containers, `powershell.exe -ExecutionPolicy Bypass -File TA-ODIN\bin\odin.ps1 | Select-String 'type=container' | Measure-Object | Select-Object -Expand Count` returns 2. The `containers.ps1` module respects v1.0.2 PS5.1 lessons learned: ASCII-only output, `[System.IO.Path]::Combine` for paths, single-quote literals for static `Write-Output` strings, `-f` format for dynamic strings.
  3. On a Linux host WITHOUT docker/podman/kubectl installed, the module exits 0 emitting `type=none_found module=containers` (existing convention). On a host WITH docker installed but daemon stopped, exits 0 emitting `type=odin_warning module=containers reason="docker daemon unreachable"` and orchestrator continues to next module.
  4. `tools/tests/check-container-enumeration.sh` validates all 3 above scenarios with structured `[CONT-04 PASS]`/`[CONT-05 PASS]`/`[CONT-06 PASS]` token markers (mirroring HOST-01..05 test convention). Script exits 0 on dev box. New CI gate added to `.github/workflows/ci.yml`.
  5. AppInspect on TA-ODIN after the new module addition still PASS with `failure=0, error=0, warning=0`. The new module is auto-discovered by the orchestrator's standard `bin/modules/*.{sh,ps1}` glob pattern (no orchestrator-level changes needed beyond the auto-discovery exclusion list if any).
**Plans:** TBD (likely 2 parallel plans in Wave 1: 11-01 Linux module + edge cases, 11-02 Windows module + edge cases; then Wave 2: 11-03 regression test + CI gate. files_modified are disjoint between Linux and Windows modules, so Wave 1 parallelism is natural per Phase 8 lessons.)
**UI hint:** no (new event-emitting module; no dashboard changes in this phase)

### Phase 12: Image-based Classification + Dashboard
**Goal:** Container events from Phase 11 are classified by image name into business roles (web_server, database, message_broker, etc.) and surfaced in a dedicated dashboard panel showing container density per host. Aggregated `odin_container_inventory.csv` parallel to existing `odin_host_inventory.csv` enables SOC analysts to query "which hosts are running which container roles" without writing custom SPL. AppInspect baseline preserved.
**Depends on:** Phase 11 (`type=container` events must exist for classification to operate against; lookup binding in `transforms.conf` requires the event type as input).
**Requirements:** CONT-08, CONT-09, CONT-10
**Success Criteria** (what must be TRUE):
  1. `ODIN_app_for_splunk/lookups/odin_classify_container_images.csv` exists with at least 30 rows covering web servers (nginx, apache, caddy), databases (mysql, postgres, mongodb, redis), message brokers (rabbitmq, kafka), reverse proxies (haproxy, traefik), monitoring (prometheus, grafana), and application runtimes (node, python, java, ruby). WILDCARD `match_type` declared in `transforms.conf` (mirrors existing `odin_classify_packages.csv` pattern). Verified by `wc -l` ≥ 30 and `grep -c WILDCARD ODIN_app_for_splunk/default/transforms.conf` increases by ≥1.
  2. New saved search `[ODIN - Container Inventory]` in `savedsearches.conf` aggregates `type=container` events into per-host inventory. Schedule: nightly. Output: `odin_container_inventory.csv` with columns `hostname, container_count, top_roles, last_seen`. Verified by `splunk search '| inputlookup odin_container_inventory.csv | head 5'` returns rows after one nightly cycle.
  3. `ODIN_app_for_splunk/default/data/ui/views/odin_overview.xml` adds at least 1 new dashboard panel "Container Density per Host" (column chart, top 20 hosts by container count). Optional second panel "Container Role Distribution" (pie chart aggregating `container_role` fleet-wide). Both panels appended below v1.0.2's OS Distribution + Virtualization Breakdown. Visualization count increases from 12 (v1.0.2) to 13 or 14. Verified by JSON parse + `grep -c 'Container Density'` returns 1.
  4. AppInspect on `ODIN_app_for_splunk` after the dashboard + lookup + savedsearches.conf changes still PASS with `failure=0, error=0, warning=0`. Saved as `.planning/artifacts/appinspect/odin-app-1.1.0-phase12.json`.
  5. UAT cycle (`/gsd-verify-work 12`) passes with all 10 v1.1.0 requirements (CONT-01..CONT-10) marked as DONE. Final HOST + CONT cross-check: a host running 5 containers produces 1 `type=odin_host_info` (with `container_runtime=none` if not INSIDE a container itself) + 5 `type=container` events, joinable via `run_id` for full host/container topology.
**Plans:** TBD (likely 3 plans: 12-01 lookup + transforms.conf binding, 12-02 saved search + nightly schedule, 12-03 dashboard panels + AppInspect baseline; sequential — lookup must exist before saved search can reference it, saved search output must exist before dashboard can render it)
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
| 10. Container Environment Detection | 0/TBD | Not started — defining plans | — |
| 11. Container Enumeration Module | 0/TBD | Not started — defining plans | — |
| 12. Image-based Classification + Dashboard | 0/TBD | Not started — defining plans | — |

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

### v1.1.0 — Container Observability
- **Total requirements:** 10 (CONT-01..CONT-10)
- **Mapped:** 10/10 (CONT-01..03 → Phase 10; CONT-04..07 → Phase 11; CONT-08..10 → Phase 12)
- **Orphans:** 0
- **Duplicates:** 0

## Archived Milestones

- **v1.0.0** (First Production Delivery) — 26 requirements (WIN-01..12, HARD-01..08, APPI-01..06), 3 phases, shipped 2026-04-15, tag `v1.0.0` on `origin/main`. Detailed phase structure preserved in git history and in `.planning/phases/01-windows-parity/`, `02-production-hardening/`, `03-appinspect-compliance/`.
