# Requirements — TA-ODIN

## Milestone v1.0.0 — First Production Delivery

**Goal:** Ship a cross-platform (Linux + Windows) TA-ODIN that is AppInspect-clean, production-hardened, and safe to pilot on a Splunk Deployment Server fleet of 10k+ mixed hosts.

**In scope this milestone:** Windows parity (A), production hardening (B), AppInspect compliance (C).

**Not in scope this milestone:** Cross-platform testing harness (D), end-user documentation (E), Windows classification CSV content (F), reproducible packaging (G). Tracked under *Deferred to v1.1+*.

---

## v1.0.0 Requirements

### A. Windows Parity (WIN-*)

Full PowerShell 5.1+ implementation that mirrors the Linux orchestrator and six modules, emitting the same `key=value` event format so existing search-time lookups and saved searches keep working.

- [x] **WIN-01** — `TA-ODIN/bin/odin.ps1` orchestrator auto-discovers PowerShell modules under `bin/modules/*.ps1`, runs each under a bounded per-module timeout, enforces `ODIN_MAX_EVENTS`, emits `type=odin_start` and `type=odin_complete` markers, and exports shared context via `ODIN_*` environment variables
- [x] **WIN-02** — Windows `services.ps1` module enumerates services using `Get-Service` plus `Get-CimInstance Win32_Service` for start mode and image path; emits one `type=service` event per service
- [x] **WIN-03** — Windows `ports.ps1` module enumerates listening endpoints using `Get-NetTCPConnection -State Listen` and `Get-NetUDPEndpoint`; emits one `type=port` event per listener
- [x] **WIN-04** — Windows `packages.ps1` module enumerates installed software by scanning `HKLM:\...\Uninstall` and `HKLM:\...\Wow6432Node\...\Uninstall` registry keys — **never** `Win32_Product` (triggers MSI self-repair); emits one `type=package` event per entry
- [x] **WIN-05** — Windows `scheduled_tasks.ps1` module enumerates scheduled tasks using `Get-ScheduledTask` plus `Get-ScheduledTaskInfo`; emits one `type=scheduled_task` event per task
- [x] **WIN-06** — Windows `processes.ps1` module enumerates running processes using `Get-Process` (plus `Get-CimInstance Win32_Process` for command line where available); emits one `type=process` event per process
- [x] **WIN-07** — Windows `mounts.ps1` module enumerates filesystem volumes using `Get-Volume` / `Get-PSDrive -PSProvider FileSystem`; emits one `type=mount` event per volume
- [x] **WIN-08** — All Windows modules emit the **identical** space-separated `key=value` format used by Linux, including the same field names (`hostname`, `os`, `run_id`, `type`, etc.), so existing `odin_classify_*.csv` lookups and the three nightly saved searches work unchanged
- [x] **WIN-09** — Windows code uses only built-in PowerShell 5.1+ cmdlets: no PS Gallery modules, no `Add-Type`, no `Invoke-Expression`, no base64-encoded commands, no compiled binaries, no network calls
- [x] **WIN-10** — Windows orchestrator is invokable via `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File odin.ps1` and runs cleanly under AppLocker / WDAC / Constrained Language Mode
- [x] **WIN-11** — Windows modules run correctly under `LocalSystem` (the default Splunk UF service account) on Windows Server 2019/2022 and Windows 10/11
- [x] **WIN-12** — Windows orchestrator never aborts on module failure — failed modules emit a `type=odin_error` event with `exit_code` and the orchestrator continues, matching the Linux fail-soft behavior

### B. Production Hardening (HARD-*)

Close the gaps that prevent the current codebase from being safe to roll out to 10k+ hosts.

- [ ] **HARD-01** — Single source of truth for `ODIN_VERSION` across `TA-ODIN/default/app.conf`, `ODIN_app_for_splunk/default/app.conf`, `TA-ODIN/bin/odin.sh`, and `TA-ODIN/bin/odin.ps1`; resolves the current `2.1.0` vs `2.2.0` drift and resets to `1.0.0`
- [ ] **HARD-02** — `ODIN_MAX_EVENTS` and `ODIN_MODULE_TIMEOUT` are tunable via environment variables in both orchestrators; pre-set values from the environment are honored and not overwritten by script defaults
- [x] **HARD-03** — Saved search in `ODIN_app_for_splunk/default/savedsearches.conf` alerts on `type=truncated` events across the fleet so silent MAX_EVENTS truncation becomes observable
- [x] **HARD-04** — Saved search in `ODIN_app_for_splunk/default/savedsearches.conf` alerts on `type=odin_error exit_code=124` (module timeouts) so fleet-wide timeout patterns become observable
- [x] **HARD-05** — `shellcheck` runs clean (zero findings at default severity) on every `TA-ODIN/bin/**/*.sh`, gated in CI as a release blocker
- [x] **HARD-06** — `PSScriptAnalyzer` runs clean (zero findings at default severity) on every `TA-ODIN/bin/**/*.ps1`, gated in CI as a release blocker
- [x] **HARD-07** — CI guard mechanically enforces the two-app split: forbids `indexes.conf`, `transforms.conf`, `savedsearches.conf`, and `lookups/` inside `TA-ODIN/`; forbids `inputs.conf` and any `bin/` scripts inside `ODIN_app_for_splunk/`
- [x] **HARD-08** — `safe_val()` and every `emit` call site in the Linux modules are audited for shell-injection against malicious service / unit / package / mount names; findings are fixed and a regression test fixture is added to `tools/tests/`

### C. AppInspect Compliance (APPI-*)

Make both apps pass Splunk's cloud vetting cleanly so the milestone can be pilot-delivered as a Splunkbase-ready bundle.

- [x] **APPI-01** — `TA-ODIN` passes `splunk-appinspect inspect` with zero failures and no critical warnings
- [x] **APPI-02** — `ODIN_app_for_splunk` passes `splunk-appinspect inspect` with zero failures and no critical warnings
- [x] **APPI-03** — AppInspect runs on every release build (local or CI), not ad-hoc — it is a hard release gate
- [x] **APPI-04** — `app.conf` metadata in both apps is Splunkbase-ready: `author`, `description`, `license`, `version`, `build`, `id` populated with correct values
- [x] **APPI-05** — `metadata/default.meta` permissions reviewed for least-privilege in both apps; exports are scoped as tightly as viable rather than blanket `export = system`
- [x] **APPI-06** — No AppInspect red flags exist in either app: no hardcoded host paths, no outbound network calls from scripts, no binary execution, no suspicious PowerShell / bash patterns that trip cloud vetting

---

## Deferred to v1.1+

_Scoped out of v1.0.0 to keep the first delivery finite. These will move back to "Active" at the start of v1.1._

### D. Cross-Platform Testing Strategy

Mock-fixture unit tests for Linux bash and Windows PowerShell modules, PowerShell parse gate via `pwsh` on CI (no Windows host required), per-distro Linux integration containers (Debian/RHEL/Alpine/Arch), and `type=odin_complete modules_failed=0` asserted as the success signal. Test harness runs without a real Splunk instance and without a Windows VM.

### E. Documentation

`DOCS/INSTALL.md` (Deployment Server rollout playbook), `DOCS/DATA-DICTIONARY.md` (field reference per event type), `DOCS/SAFETY.md` (why this is safe on 10k+ hosts), `DOCS/TROUBLESHOOTING.md` (common failure modes), `DOCS/RELEASE.md` (release procedure), plus README updates in both apps.

### F. Windows Classification Coverage

Windows-specific rows added to `odin_classify_services.csv` (IIS, W3SVC, MSSQLSERVER, ADWS, NTDS, DHCPServer, DNS, SMTPSVC, Exchange, WinRM, etc.), `odin_classify_ports.csv` (135, 445, 3389, 5985/6, 53, 389/636, 88, 1433, etc.), `odin_classify_packages.csv` (registry display names), and `odin_log_sources.csv` (host roles → Windows Event Log sources → recommended TAs).

### G. Packaging

Reproducible build script producing `TA-ODIN-<version>.tar.gz` and `ODIN_app_for_splunk-<version>.tar.gz` from a clean checkout, version stamped from a single source into both `app.conf` files and both orchestrators, excluding `.planning/`, `DOCS/`, `tools/`, tests, and dotfiles from the bundles.

---

## Out of Scope (v1.0.0 and beyond unless revisited)

- **Windows live-host validation in this milestone** — no Windows hosts available during development; live pilot is deferred to after release
- **Linux module rewrites** — user explicitly wants Linux untouched unless a concrete defect or hardening gap is found
- **Dashboards beyond `odin_overview.xml`** — tracked as future work in CLAUDE.md, not this milestone
- **Phase 3: Deployment Server serverclass auto-generation** — future work, would make this milestone sprawl beyond "production ready"
- **Manual change history automation** (`DOCS/CHANGEHISTORY.md` drift) — noted in CONCERNS.md, not load-bearing
- **PowerShell 7 exclusive features** — baseline is 5.1 to avoid any install step
- **Binary / compiled agents** — scripting-only, zero-dependency is a hard constraint
- **Additional distro support** (BSD, Gentoo OpenRC, NixOS, Void) — existing fallback chains stay, no new backends
- **CIS benchmark compliance for the TA itself** — nice-to-have, not requested

---

## Traceability

_Populated by `gsd-roadmapper` on 2026-04-10. Each REQ-ID maps to exactly one phase._

| REQ-ID | Phase | Notes |
|--------|-------|-------|
| WIN-01 | Phase 1 | Windows orchestrator auto-discovery + markers |
| WIN-02 | Phase 1 | services.ps1 module |
| WIN-03 | Phase 1 | ports.ps1 module |
| WIN-04 | Phase 1 | packages.ps1 via registry (NOT Win32_Product) |
| WIN-05 | Phase 1 | scheduled_tasks.ps1 module |
| WIN-06 | Phase 1 | processes.ps1 module |
| WIN-07 | Phase 1 | mounts.ps1 module |
| WIN-08 | Phase 1 | Identical key=value format parity with Linux |
| WIN-09 | Phase 1 | Built-in cmdlets only; no PS Gallery / Add-Type / IEX |
| WIN-10 | Phase 1 | Safe invocation under AppLocker/WDAC/CLM |
| WIN-11 | Phase 1 | LocalSystem on Server 2019/2022 + Win 10/11 |
| WIN-12 | Phase 1 | Fail-soft orchestration parity with Linux |
| HARD-01 | Phase 2 | Single source of truth for ODIN_VERSION → 1.0.0 |
| HARD-02 | Phase 2 | Tunable MAX_EVENTS + MODULE_TIMEOUT both orchestrators |
| HARD-03 | Phase 2 | Alerting saved search for type=truncated |
| HARD-04 | Phase 2 | Alerting saved search for odin_error exit_code=124 |
| HARD-05 | Phase 2 | shellcheck CI gate |
| HARD-06 | Phase 2 | PSScriptAnalyzer CI gate |
| HARD-07 | Phase 2 | Two-app-split CI guard |
| HARD-08 | Phase 2 | safe_val / emit shell-injection audit + regression fixture |
| APPI-01 | Phase 3 | TA-ODIN passes splunk-appinspect |
| APPI-02 | Phase 3 | ODIN_app_for_splunk passes splunk-appinspect |
| APPI-03 | Phase 3 | AppInspect wired into release build as hard gate |
| APPI-04 | Phase 3 | Splunkbase-ready app.conf metadata both apps |
| APPI-05 | Phase 3 | default.meta least-privilege review |
| APPI-06 | Phase 3 | No AppInspect red flags (paths, network, binaries) |

---

## Milestone v1.0.1 — Production Readiness

**Status:** Active (opened 2026-04-15)
**Goal:** Take v1.0.0 from pilot-ready to fleet-deployable by closing the operational, observability, and documentation gaps that block safe rollout beyond ~50 hosts.

**In scope this milestone:** Windows classification data (PROD-01), operational readiness (PROD-03..PROD-07), and pilot validation (PROD-02).

**Not in scope this milestone:** Automated bash test harness (group D), Splunk Cloud Victoria compatibility (Phase 3 D9 — still Enterprise-only), external security audit (separate governance track), supply chain attestation / SLSA L2+, reproducible `.tar.gz` packaging (group G — can ship via GitHub tag for now). Tracked under *Deferred to v1.1+*.

### v1.0.1 Requirements

- [x] **PROD-01** — Windows-specific rows added to `ODIN_app_for_splunk/lookups/odin_classify_services.csv` (IIS, W3SVC, MSSQLSERVER, ADWS, NTDS, DHCPServer, DNS, SMTP, Exchange, WinRM, etc.), `odin_classify_ports.csv` (135/tcp, 445/tcp, 3389/tcp, 5985/tcp, 5986/tcp, 53/udp, 389/tcp, 636/tcp, 88/tcp, 1433/tcp, etc.), `odin_classify_packages.csv` (common registry display names), and `odin_log_sources.csv` (host_role → Windows Event Log source → recommended TA). Acceptance: a simulated Windows host with realistic services classifies to a non-empty set of roles and produces a non-empty TA deployment matrix row. **DONE 2026-04-17 via Phase 4 (Plans 04-01 + 04-02): services 332→357, ports 206→224, packages 274→308, log_sources 274→297. Cross-CSV TA registry validation enforced via `tools/tests/check-windows-classification.sh` (PROD-01 PASS). AppInspect Enterprise scope failure=0/error=0/warning=0 across all changes.**
- [ ] **PROD-02** — TA-ODIN piloted on ≥5 Linux + ≥5 Windows real hosts via Deployment Server for a 7-day observation window. Acceptance: `modules_failed=0` on ≥95% of `type=odin_complete` events across the window, no unexplained `type=truncated` alerts, `odin_host_inventory.csv` lookup produces a row for every piloted host with a classified role, pilot log captured in `.planning/artifacts/pilot-v1.0.1/`.
- [x] **PROD-03** — `DOCS/RUNBOOK.md` with on-call response procedures for `type=truncated`, `type=odin_error exit_code=124`, `type=odin_error` (non-124), and "fleet scan success rate below SLO" alerts. Each entry includes: what the alert means, diagnostic SPL, remediation steps, escalation contact. Acceptance: a reader who has never seen the TA before can follow one entry end-to-end and understand what to do. **Closed 2026-04-24 by Plan 05-03** — 395-line `DOCS/RUNBOOK.md` with 4 alert-response entries (truncated, exit_code=124, non-124, fleet scan success rate below SLO), each with the 4 mandated subsections. New 3rd alert stanza `alert_odin_fleet_scan_success_rate_below_slo` added to `ODIN_app_for_splunk/default/savedsearches.conf` (definition-only per CONTEXT D2). Summary: `.planning/phases/05-operational-readiness/05-03-SUMMARY.md`.
- [x] **PROD-04** — `DOCS/INSTALL.md` (Deployment Server rollout playbook per OS), `DOCS/TROUBLESHOOTING.md` (common failure modes — permission issues, missing cmdlets, systemctl quirks, Windows UAC edge cases), `DOCS/DATA-DICTIONARY.md` (every field per `type=*` event), `DOCS/UPGRADE.md` (v1.0.0 → v1.0.1 upgrade path including rollback note), README updates in both app roots. Acceptance: a Splunk admin unfamiliar with TA-ODIN can install it, understand the fields, and diagnose a common failure using these docs alone. **Closed 2026-04-24 by Plan 05-04** — 4 new admin docs (INSTALL 189 lines, TROUBLESHOOTING 293 lines with 12 ### Issue triples covering Linux/Windows/cross-platform, DATA-DICTIONARY 300 lines with 11 ## type= subsections per emitted event type, UPGRADE 217 lines covering all 7 PROD-* requirements + alert activation procedure + rollback pointer). Both app READMEs gained ## Documentation sections linking all 6 Phase 5 docs (TA-ODIN: 7 ../DOCS/ links; ODIN_app_for_splunk: 7 ../DOCS/ links; pure additions, zero pre-existing content removed). Commits: `de4c986`, `6c3033a`, `f7b2985`, `92a4cb1`, `db2791b`. Summary: `.planning/phases/05-operational-readiness/05-04-SUMMARY.md`.
- [x] **PROD-05** — `DOCS/ROLLBACK.md` documenting exact Deployment Server steps to disable TA-ODIN on the fleet without removing files (toggle `disabled = 1` in a local overlay stanza), plus dry-run validation: toggle on a pilot host, verify the scripted input stops within one scan cycle, toggle back, verify events resume. Acceptance: dry-run logged in `.planning/artifacts/rollback-dryrun.md` with timestamps and event-count deltas. **Closed 2026-04-24 by Plan 05-02** — 157-line `DOCS/ROLLBACK.md` (Strategy A overlay + Strategy B uninstall, both stanzas covered, deferred-items section calls out PROD-02 live-fleet validation explicitly). Dry-run validated via `tools/tests/rollback-dryrun.sh` (180 lines, shellcheck-clean, configparser-emulator confirms both `[script://]` stanzas would be skipped after `disabled = true` patch; real `inputs.conf` byte-identical to HEAD; induced-failure detection verified end-to-end). New CI hard-gate `Rollback dry-run guard` in `.github/workflows/ci.yml` runs the script on every push. Commits: `0030812`, `08863f2`. Summary: `.planning/phases/05-operational-readiness/05-02-SUMMARY.md`.
- [x] **PROD-06** — Ops observability dashboard at `ODIN_app_for_splunk/default/data/ui/views/odin_ops.xml` (Dashboard Studio) showing: scan success rate per OS, module runtime p50/p95/p99 per module type, module-failure heatmap, event-volume-per-host-per-day trendline, fleet host coverage over time (distinct hosts seen per day), top-N truncating hosts. Acceptance: dashboard renders with test data in a local Splunk instance, panels are labeled, no broken searches. AppInspect still passes after adding the view. **Closed 2026-04-24 by Plan 05-02** — 178-line Dashboard Studio v2 view (`<dashboard version="2" theme="dark">` + JSON `<definition>`) with 7 panels (≥6 ROADMAP threshold): per-OS singlevalue success rate, p95 runtime timechart, distinct-hosts column timechart (30d), event-volume column timechart (7d top-20), module-failure heatmap (`splunk.table` + rangeValue cell-coloring per RESEARCH §1 fallback), top-10 truncating hosts table. AppInspect Enterprise scope `failure=0 error=0 warning=0 success=14 not_applicable=7` — byte-identical to Phase 4 final baseline. Commits: `4041ef7`, `30404f5`. Summary: `.planning/phases/05-operational-readiness/05-02-SUMMARY.md`.

- [x] **PROD-07** — Linux module standalone-fallback hygiene: (a) bump all 6 `TA-ODIN/bin/modules/*.sh` standalone version fallbacks from `2.1.0` to `1.0.0`, (b) add `ODIN_MAX_EVENTS` truncation check + `type=truncated` emission to the standalone fallback `emit` function so standalone execution matches orchestrator guardrail behavior, (c) extend `tools/tests/check-version-sync.sh` to grep `TA-ODIN/bin/modules/*.sh` for stale version strings and fail if any `2.1.0` (or non-`1.0.0`) reference is found, (d) optionally consolidate `safe_val` + `emit` + `get_timestamp` fallbacks into a shared `modules/_common.sh` dot-sourced by all modules (mirrors the Windows `_common.ps1` pattern). Acceptance: `bash TA-ODIN/bin/modules/services.sh 2>&1 | head -1 | grep -c 'odin_version=1.0.0'` returns 1 (standalone runs with correct version); `check-version-sync.sh` exits 0 including module-fallback sites; `ODIN_MAX_EVENTS=2 bash TA-ODIN/bin/modules/services.sh 2>&1 | grep -c type=truncated` returns at least 1 (standalone truncation works). **Closed 2026-04-24 by Plan 05-01** — sub-items (a)/(b)/(c) delivered per D3 minimal scope; (d) `_common.sh` consolidation deferred to v1.1+ as planned. Verified by per-module isolation harness (5 emits at cap=2 → 2 normal + 1 truncated + 0 leaks across all 6 modules) plus check-version-sync.sh induced-drift test (exit 1 on stale 2.1.0; PASS on revert). Commits: `6b53e34`, `d75d779`, `34270fa`. Summary: `.planning/phases/05-operational-readiness/05-01-SUMMARY.md`.

**Sub-item (d) closed 2026-04-27** (post-Phase-5 tech-debt cleanup): `TA-ODIN/bin/modules/_common.sh` created with `get_timestamp` + `emit` (with MAX_EVENTS guard) + standalone-context defaults. All 6 modules refactored to source `_common.sh` from inside their existing `! declare -f emit` gate (preserves orchestrator-vs-standalone gating; `emit` is exported by orchestrator so the source line never fires under normal runs). `check-version-sync.sh` Section 3 refactored to assert _common.sh has the canonical fallback ODIN_VERSION AND all 6 modules contain a source line. Per-module isolation harness re-verified after refactor: 6/6 modules pass with normal=2 + truncated=1 + leaks=0. AppInspect TA-ODIN Enterprise scope baseline preserved (failure=0, error=0, warning=1, success=13, na=7). Net diff: 96 lines removed across 6 modules, 1 new file (61 lines), check-version-sync.sh net +20 lines. Aligns Linux with the existing Windows `_common.ps1` pattern.

### Deferred to v1.1+

The v1.0.0 deferred groups (D, E, F, G, Cloud Victoria, external audit, SLSA) remain active backlog. PROD-04 covers part of group E (admin-facing docs), and PROD-01 covers group F for classification data. The *testing harness* portion of group D and the *reproducible packaging* portion of group G stay deferred to v1.1+.

### Traceability (v1.0.1)

| REQ-ID | Phase | Notes |
|--------|-------|-------|
| PROD-01 | Phase 4 | Windows classification CSV content — pure data work, no code changes |
| PROD-03 | Phase 5 | Operational runbook — alert response procedures |
| PROD-04 | Phase 5 | Admin + troubleshooting + data dictionary + upgrade docs |
| PROD-05 | Phase 5 | Rollback procedure + dry-run validation |
| PROD-06 | Phase 5 | Ops observability dashboard (Dashboard Studio) |
| PROD-07 | Phase 5 | Linux module standalone-fallback hygiene (version + MAX_EVENTS + _common.sh) |
| PROD-02 | Phase 6 | Pilot deployment + 7-day observation window (release gate) |

## Milestone v1.0.2 — Host Metadata Enrichment

**Goal:** Every TA-ODIN scan emits ONE `type=odin_host_info` event with rich host metadata (13 fields covering OS identity, hardware, network, virtualization, cloud detection) so Splunk dashboards and saved searches can classify, group, and filter hosts by OS distribution, hardware profile, network identity, and runtime environment — not just by `os=linux|windows`.

**Trigger:** v1.0.1-rc1 released 2026-04-28 (https://github.com/lyderhansen/odin/releases/tag/v1.0.1-rc1). Seed planted 2026-04-27 during `/gsd-explore` session — see `.planning/seeds/v1.0.2-host-metadata-enrichment.md` and `.planning/notes/2026-04-27-host-metadata-and-container-strategy.md` for decision context.

**In scope this milestone:** OS identity (distro, version, pretty name, kernel, architecture), hardware metadata (cpu_cores, mem_total_mb), runtime metadata (uptime_seconds), network identity (fqdn, ip_primary), virtualization detection (kvm/vmware/hyperv/container/baremetal), cloud detection (provider + region via IMDS endpoints with timeout safety). Cross-platform parity, DATA-DICTIONARY documentation update, and dashboard panels showing OS distribution + virtualization breakdown.

**Not in scope this milestone:** Container enumeration (Docker/podman/kubectl `ps` output) — deferred to v1.1.0. Cloud asset metadata (AWS Tags, GCP Labels, Azure tags) — deferred to v1.1.0 Phase 4 optional. Network topology, hardware inventory, BIOS/firmware versions — all deferred to v1.2+. v1.0.0 deferred items (test harness, reproducible packaging, Cloud Victoria, external audit, SLSA L2+) remain deferred — not in v1.0.2 scope.

**Risk:** LOW — fully additive (no schema changes, no existing field semantics affected, no behavioral changes to existing modules).

### v1.0.2 Requirements

- [x] **HOST-01** — Linux orchestrator emits exactly one `type=odin_host_info` event per scan, positioned between `type=odin_start` and the first module event, populated with all 13 fields: `os_distro`, `os_version`, `os_pretty`, `os_kernel`, `os_arch` (from `/etc/os-release` + `uname`), `cpu_cores` (from `nproc`), `mem_total_mb` (from `/proc/meminfo`), `uptime_seconds` (from `/proc/uptime`), `fqdn` (from `hostname -f`), `ip_primary` (from `ip route get 1.1.1.1`), `virtualization` (from `systemd-detect-virt` with dmidecode/cgroup fallback), `cloud_provider` + `cloud_region` (from IMDS endpoint probes with 1s timeout, default `none` on failure). Acceptance: `bash TA-ODIN/bin/odin.sh | grep -c '^.*type=odin_host_info'` returns 1; the event line contains all 13 named fields; AppInspect baseline preserved. **CLOSED 2026-04-29 by Plan 07-01.**

- [x] **HOST-02** — Windows orchestrator emits exactly one `type=odin_host_info` event per scan with the same 13 fields populated via Windows-native methods: `os_distro=windows`, `os_version` from `[System.Environment]::OSVersion.Version`, `os_pretty` from `(Get-CimInstance Win32_OperatingSystem).Caption`, `os_kernel` from `BuildNumber`, `os_arch` from `$env:PROCESSOR_ARCHITECTURE`, `cpu_cores` from `Win32_Processor.NumberOfCores`, `mem_total_mb` from `Win32_OperatingSystem.TotalVisibleMemorySize`, `uptime_seconds` from `LastBootUpTime` delta, `fqdn` from `[System.Net.Dns]::GetHostByName`, `ip_primary` from `Get-NetRoute 0.0.0.0/0`, `virtualization` from `Win32_ComputerSystem.Manufacturer`/`Model`, `cloud_provider` + `cloud_region` from cloud-specific IMDS via `Invoke-RestMethod` with 2s timeout. Acceptance: `powershell.exe -ExecutionPolicy Bypass -File odin.ps1 | Select-String 'type=odin_host_info'` returns exactly 1 line containing all 13 named fields; AppInspect baseline preserved.

- [ ] **HOST-03** — Cross-platform parity verified: Linux + Windows produce a `type=odin_host_info` event with the same field set (modulo platform-specific values like `os_arch=x86_64` vs `amd64`). Cloud IMDS probes time out cleanly within 2s on hosts WITHOUT cloud metadata (no false positives, no hangs, no module timeouts triggered). Acceptance: new regression script `tools/tests/check-host-info-parity.sh` (or extension to `windows-parity-harness.sh`) validates field-set equivalence between Linux + Windows test fixtures.

- [ ] **HOST-04** — `DOCS/DATA-DICTIONARY.md` updated with full `## type=odin_host_info` section: descriptive overview, complete field reference (all 13 fields with description, source, and example value per field), a worked example event line, and a note on cloud-detection timeout semantics. Acceptance: `grep -c '^## type=odin_host_info' DOCS/DATA-DICTIONARY.md` returns 1; field list matches what HOST-01/HOST-02 emit; example event line is byte-format-correct.

- [ ] **HOST-05** — `ODIN_app_for_splunk/default/data/ui/views/odin_overview.xml` adds at least 2 new dashboard panels: (a) "OS Distribution" pie/column chart showing `count by os_distro,os_version` from latest `type=odin_host_info` per host, (b) "Virtualization Breakdown" panel showing `count by virtualization` (kvm/vmware/hyperv/container/baremetal/none). Acceptance: dashboard renders with test data in a local Splunk instance; AppInspect on `ODIN_app_for_splunk` baseline preserved (failure=0, error=0, warning=0).

### Deferred to v1.0.3 / v1.1+

- Container enumeration (Docker/podman/kubectl `ps`) — see `.planning/seeds/v1.1.0-container-observability.md`
- Cloud asset metadata (tags, labels, IAM role) — v1.1.0 Phase 4 optional
- Network topology (route table, DNS, gateway) — v1.2+
- Hardware inventory (PCI/GPU/NVMe) — v1.2+
- BIOS/firmware versions — v1.2+ (security-audit territory)
- All v1.0.0 deferred items (group D test harness residual, group G reproducible packaging, Splunk Cloud Victoria, external security audit, SLSA L2+) remain deferred — not in v1.0.2 scope

### Traceability (v1.0.2)

| REQ-ID | Phase | Notes |
|--------|-------|-------|
| HOST-01 | Phase 7 | Linux orchestrator implementation — 13-field event emission | **CLOSED 2026-04-29** |
| HOST-02 | Phase 8 | Windows orchestrator implementation — parity with Linux |
| HOST-03 | Phase 9 | Cross-platform parity validation + IMDS timeout safety |
| HOST-04 | Phase 9 | DATA-DICTIONARY.md update — type=odin_host_info field reference |
| HOST-05 | Phase 9 | odin_overview.xml dashboard panels (OS Distribution + Virtualization) |

---
