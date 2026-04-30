# TA-ODIN (Project Odin)

## What This Is

TA-ODIN is a Splunk Technology Add-on that performs full metadata-only enumeration of endpoints (services, listening ports, installed packages, scheduled tasks, processes, mounts) and ships the results through a Universal Forwarder to Splunk, where a companion app (`ODIN_app_for_splunk`) classifies hosts by role and produces a deployment matrix of recommended Splunkbase TAs per host. It is built for Splunk administrators who need data-driven endpoint visibility without relying on incomplete CMDB data, and is intended to be pushed via Deployment Server to 10,000+ mixed Linux/Windows endpoints.

## Core Value

**Safe, dependency-free, cross-platform endpoint enumeration that ships to 10k+ hosts without breaking any of them** — if the agent ever breaks a production host or floods Splunk, the whole project is worthless.

## Current Milestone: v1.1.0 — Container Observability

**Status:** Defining requirements (started 2026-04-30).

**Goal:** Make TA-ODIN aware of containerized infrastructure — detect when running INSIDE a container, enumerate containers running ON a docker/k8s host, and classify container workloads by image so Splunk dashboards show container fleet composition + recommend appropriate Splunk TAs.

**Target features:**
- Container environment detection — refined `container_runtime`, `container_id`, `container_image_hint` fields enriching `type=odin_host_info`
- Container enumeration module — new `bin/modules/containers.{sh,ps1}` emitting one `type=container` event per running container with image, name, command, ports, state, started_at
- Image-based classification + dashboard panel — new `odin_classify_container_images.csv` lookup with WILDCARD pattern matching, saved search aggregating per-host container count + role distribution, dashboard panel showing container density per host

**Scope:** 3 phases (Phase 10/11/12 continuing numbering from v1.0.2). Estimated 2-4 days total.

**Architectural decisions to lock during plan-phase:**
- Container API access: direct binary (`docker ps`) vs unix-socket vs HTTP API → seed leaning: direct binary
- K8s API: `kubectl` vs k8s API client → seed leaning: kubectl on PATH + ~/.kube/config
- Permission model: root vs docker-group → document both

**Cross-cutting risks:** k8s RBAC complexity (mitigation: ship documented RBAC manifest), container churn within scan cycle (docs explain snapshot semantics), image name diversity (use Splunk WILDCARD match_type), Windows containers (defer to v1.1.1 if VM unavailable).

**Out of scope (DEFERRED to v1.1.1+):** Cloud auto-discovery (AWS/GCP/Azure metadata), service mesh observability, container security scanning, registry inventory, container resource utilization metrics, helm release inventory, k8s cluster topology beyond pods.

**Reference:** `.planning/seeds/v1.1.0-container-observability.md` — comprehensive scope, decision context, risk profile, NOT-in-scope list. Authoritative source for milestone definition.

## Past Milestones

- **v1.0.2 — Host Metadata Enrichment** — RELEASED 2026-04-29 ([GitHub release](https://github.com/lyderhansen/odin/releases/tag/v1.0.2)). All 5 HOST-* requirements closed. 13-field `type=odin_host_info` event covering OS, hardware, network, virtualization, cloud. Phase 7 (Linux), Phase 8 (Windows), Phase 9 (validation+docs+dashboard). UAT signed off across 3 platforms (Linux container + Windows 11 ARM64 VM + macOS).
- **v1.0.1 — Production Readiness** — v1.0.1-rc1 RELEASED 2026-04-28 as GitHub prerelease ([release page](https://github.com/lyderhansen/odin/releases/tag/v1.0.1-rc1)). 6/7 PROD-* requirements closed. Full v1.0.1 (no -rc suffix) still blocked on PROD-02 pilot acceptance pending real infrastructure — parallel/non-blocking path.

## Previous Milestone: v1.0.0 — First Production Delivery

**Status:** Shipped 2026-04-15. Tag `v1.0.0` on `origin/main`. GitHub release page live. 26 requirements closed (WIN-01..12, HARD-01..08, APPI-01..06), 3 phases, 8 plans, 30/30 UAT tests passed, 0 AppInspect failures under Splunk Enterprise scope.

**What v1.0.0 delivered:** Full Windows parity (`odin.ps1` + 6 Windows modules byte-compatible with Linux event format), production hardening (unified version, tunable guardrails, alerting stanzas, CI lint gates, two-app split enforcement, shell-injection audit), and AppInspect compliance as a mechanical CI gate. Scoped to Splunk Enterprise — Cloud Victoria compatibility deferred.

## Requirements

### Validated

<!-- Shipped and in use in the codebase. Locked unless a concrete defect is found. -->

- ✓ Six Linux discovery modules (services, ports, packages, cron, processes, mounts) — `TA-ODIN/bin/modules/*.sh`
- ✓ Auto-discovering bash orchestrator with per-module 90s timeout and MAX_EVENTS=50000 guardrails — `TA-ODIN/bin/odin.sh`
- ✓ Space-separated `key=value` event format, forwarder-side line-breaking only — `TA-ODIN/default/props.conf`
- ✓ Two-app split: TA-ODIN (forwarders) vs ODIN_app_for_splunk (indexers/SH) — per Splunk best practice
- ✓ Search-time classification lookups for services, ports, packages — `ODIN_app_for_splunk/lookups/odin_classify_*.csv`
- ✓ Signal-based host role classification via `odin_log_sources.csv` and the three nightly saved searches (Host Inventory, Log Source Details, TA Deployment Matrix)
- ✓ CIM field aliases (hostname → dest, hostname → dvc) for CIM compliance
- ✓ Fail-soft orchestration: module failures emit `odin_error` events and never abort the run
- ✓ One Dashboard Studio overview view — `odin_overview.xml`

### Active

<!-- This milestone's scope. Everything here is a hypothesis until shipped and validated. -->

**A. Windows parity (full feature match with Linux)**
- [ ] Windows orchestrator (`odin.ps1`) that mirrors `odin.sh`: auto-discovers modules, runs each under a bounded timeout, enforces MAX_EVENTS, emits `odin_start` / `odin_complete` markers, exports shared context via `ODIN_*` env vars
- [ ] Six Windows modules matching Linux parity:
  - [ ] services → `Get-Service` + `Get-CimInstance Win32_Service` for start mode / path
  - [ ] ports → `Get-NetTCPConnection -State Listen` + `Get-NetUDPEndpoint`
  - [ ] packages → **registry scan** of `HKLM:\...\Uninstall` and `HKLM:\...\Wow6432Node\...\Uninstall` (NOT `Win32_Product` — triggers MSI self-repair)
  - [ ] scheduled_tasks → `Get-ScheduledTask` + `Get-ScheduledTaskInfo`
  - [ ] processes → `Get-Process` (+ `Get-CimInstance Win32_Process` for command line if available)
  - [ ] mounts → `Get-Volume` / `Get-PSDrive -PSProvider FileSystem`
- [ ] Windows modules emit identical `key=value` format as Linux so the existing search-time lookups and saved searches work unchanged
- [ ] Uses only built-in PowerShell 5.1+ cmdlets — no external modules, no PS Gallery, no Python, no compiled binaries
- [ ] Safe invocation pattern: `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File odin.ps1`
- [ ] No `Invoke-Expression`, no base64-encoded commands, no `Add-Type`, no downloads — EDR-safe and Constrained Language Mode-friendly
- [ ] Runs correctly under LocalSystem (default Splunk UF service account) on Windows Server 2019/2022 and Windows 10/11

**B. Production hardening**
- [ ] Fix `ODIN_VERSION` drift: `TA-ODIN/bin/odin.sh:30` says `2.1.0`, `app.conf` says `2.2.0` — single source of truth
- [ ] Make `ODIN_MAX_EVENTS` and `ODIN_MODULE_TIMEOUT` tunable via environment variables (pre-set values in orchestrator must be honored, not overwritten)
- [ ] Alerting saved search for `type=truncated` events so silent truncation becomes visible
- [ ] Alerting saved search for `type=odin_error exit_code=124` (module timeouts) across the fleet
- [ ] Shellcheck clean on all bash (`TA-ODIN/bin/**/*.sh`) — gate in CI
- [ ] PSScriptAnalyzer clean on all PowerShell (`TA-ODIN/bin/**/*.ps1`) — gate in CI
- [ ] CI check: forbid `indexes.conf`, `transforms.conf`, `savedsearches.conf`, `lookups/` in `TA-ODIN/`; forbid `inputs.conf` and `bin/` scripts in `ODIN_app_for_splunk/` — mechanically enforce the two-app split
- [ ] Audit `safe_val()` and all `emit` call sites for shell-injection via malicious service/unit names (see CONCERNS.md security section)

**C. AppInspect compliance**
- [ ] Both apps (`TA-ODIN` + `ODIN_app_for_splunk`) pass `splunk-appinspect` with zero failures and no critical warnings
- [ ] Run AppInspect locally (or in CI) as part of the release build, not ad-hoc
- [ ] `app.conf` metadata complete for Splunkbase submission (author, description, license, version, build, id)
- [ ] `default.meta` permissions reviewed — least-privilege, not blanket exports if tighter scoping is viable
- [ ] No hardcoded paths, no network calls from scripts, no binary execution, no suspicious patterns that trip cloud vetting

### Deferred to v1.1+

<!-- Scoped out of v1.0.0 but still in the project's trajectory. These move back into Active at the start of v1.1. -->

**D. Cross-platform testing strategy (no Windows hosts available)**
- [ ] PowerShell syntax parse gate via `pwsh` on CI (runs on Linux/macOS — validates all `.ps1` files without executing them)
- [ ] Mock-fixture unit tests for both Linux bash modules and Windows PowerShell modules — stub `systemctl`, `dpkg-query`, `ss`, `Get-Service`, etc. with canned output; assert on emitted `key=value` lines
- [ ] Linux integration tests: one container per distro family (Debian, RHEL, Alpine, Arch) running each module end-to-end
- [ ] `type=odin_complete` + `modules_total=N modules_success=N modules_failed=0` asserted as the success signal
- [ ] Test harness is runnable without a real Splunk instance and without any Windows VM
- [ ] Live Windows validation explicitly deferred to user's pilot after release

**E. Documentation**
- [ ] `DOCS/INSTALL.md` — Deployment Server rollout playbook (Linux + Windows) with serverclass example, scale guidance, rollback procedure
- [ ] `DOCS/DATA-DICTIONARY.md` — complete field reference per event type (services, ports, packages, cron, processes, mounts, odin_start, odin_complete, odin_error, odin_warning, truncated, none_found)
- [ ] `DOCS/SAFETY.md` — why this is safe to run on 10k+ hosts: read-only operations, timeouts, MAX_EVENTS, no writes outside Splunk var, no network calls, degradation under low privilege, known risky patterns avoided (`Win32_Product`, `Invoke-Expression`, etc.)
- [ ] `DOCS/TROUBLESHOOTING.md` — common failure modes: non-root warnings, distro detection gaps, truncation, timeouts, Windows execution policy, PSReadline noise, Splunk input timeout
- [ ] Update `TA-ODIN/README.md` and `ODIN_app_for_splunk/README.md` to reflect cross-platform support and the documented tunables
- [ ] `DOCS/RELEASE.md` — release/build procedure, AppInspect gate, packaging steps

**F. Windows classification coverage**
- [ ] Add Windows-specific rows to `odin_classify_services.csv` (IIS, W3SVC, MSSQLSERVER, ADWS, NTDS, DHCPServer, DNS, SMTPSVC, Exchange, WinRM, etc.)
- [ ] Add Windows-specific rows to `odin_classify_ports.csv` (135 RPC, 445 SMB, 3389 RDP, 5985/5986 WinRM, 53 DNS, 389/636 LDAP, 88 Kerberos, 1433 MSSQL, etc.)
- [ ] Add Windows-specific rows to `odin_classify_packages.csv` — registry display names (Microsoft SQL Server, IIS, .NET Runtime, Exchange Server, etc.)
- [ ] Add Windows-specific rows to `odin_log_sources.csv` mapping each new signal to host roles, Windows Event Log sources, recommended TAs (Splunk_TA_windows, Splunk_TA_microsoft_iis, Splunk_TA_microsoft_sqlserver, etc.)

**G. Packaging**
- [ ] Reproducible build script that produces `TA-ODIN-<version>.tar.gz` and `ODIN_app_for_splunk-<version>.tar.gz` from a clean checkout
- [ ] Version string is stamped into `app.conf`, the bash orchestrator, and the PowerShell orchestrator from a single source
- [ ] Build excludes `.planning/`, `DOCS/`, `tools/`, tests, `.DS_Store`, dot-files, and any developer-only content

### Out of Scope

- **Windows live-host validation in this milestone** — user has no Windows host available; live pilot is deferred to after release
- **Linux module rewrites** — user explicitly wants Linux untouched unless a concrete defect or hardening gap is found during audit
- **Dashboards beyond `odin_overview.xml`** — tracked as future work in CLAUDE.md; not part of this milestone
- **Phase 3: Deployment Server serverclass auto-generation** — CLAUDE.md's stated "future" phase; would make this milestone sprawl beyond "production ready"
- **Manual change history automation** (`DOCS/CHANGEHISTORY.md` drift) — noted in CONCERNS.md but not load-bearing for production readiness
- **PowerShell 7 exclusive features** — baseline is 5.1 to avoid any install step on target hosts
- **Binary/compiled agents** — scripting-only, zero-dependency is a hard constraint
- **Additional distro support** (BSD, Gentoo OpenRC, NixOS, Void) — existing fallback chains stay, but no new backends in this milestone
- **CIS benchmark compliance for the TA itself** — nice-to-have, not requested

## Context

**Codebase state (as of 2026-04-10):**
- Phases 1 & 2 are complete per `CLAUDE.md` — enumeration and classification both work on Linux.
- Windows side is a stub (`odin.ps1` emits one "not yet implemented" event). This is the single largest gap per `.planning/codebase/CONCERNS.md`.
- Bash modules have **0% automated test coverage**. All verification is manual on live hosts today. At 10k+ host rollout this is untenable.
- Version drift exists: `odin.sh` declares `2.1.0`, both `app.conf` files declare `2.2.0`.
- Two-app split (`TA-ODIN` vs `ODIN_app_for_splunk`) is enforced only by human discipline — there is no mechanical guard.
- Classification CSVs are currently Linux-centric: `odin_classify_services.csv` (332 rows), `odin_classify_ports.csv` (206 rows), `odin_classify_packages.csv` (274 rows), `odin_log_sources.csv` (274 rows). Windows content must be added to reach parity.
- Dev tooling tests exist (`tools/tests/test_classification_coverage.py`, `test_generate_odin_data.py`, ~360 lines of pytest) but cover synthetic data generation, not the modules themselves.

**User context:**
- Single-developer project. User has worked on this for a long time and wants to finish so they can pilot it.
- No Windows test hosts available during development — testing strategy must work on macOS/Linux dev machine + deferred pilot validation.
- Target deployment: 10,000+ hosts mixing Linux (RHEL 8/9, Ubuntu 22/24, others) and Windows (Server 2019/2022, Win 10/11, both server and workstation, minimal installs).
- Delivery format: `.tar.gz` bundle per app, ready to hand to Deployment Server.

**Operating environment:**
- Splunk Universal Forwarder runs as `root` on Linux (recommended) and as `LocalSystem` on Windows by default.
- Scripted inputs are invoked every 2,592,000 seconds (30 days) with a 120-second hard timeout.
- Forwarders typically run in constrained enterprise environments: AppLocker, WDAC, EDR (CrowdStrike, Defender for Endpoint, etc.), strict execution policies.

## Constraints

- **Tech stack (Linux)**: Bash 4+ only — no Python, no Perl, no compiled binaries on endpoints. Reason: zero-install footprint on minimal installs; already the established pattern.
- **Tech stack (Windows)**: PowerShell 5.1+ built-in cmdlets only — no PS Gallery modules, no `Add-Type`, no `Invoke-Expression`, no base64 commands. Reason: Zero-dependency install on minimal Windows hosts; EDR-safe; AppLocker/WDAC compatible.
- **Safety**: Scripts must be read-only — no writes outside Splunk's var dir, no network calls, no process kills, no config changes on the host. Reason: 10k+ host blast radius via Deployment Server — a single destructive bug would be catastrophic.
- **Runtime budget**: Each module ≤ 90s wall-clock, total scan ≤ 120s (Splunk input timeout). Events per module ≤ 50,000 (tunable). Reason: Prevents runaway resource use on pathological hosts.
- **Output format**: Space-separated `key=value` — identical across Linux and Windows so one set of search-time lookups works for both. Reason: Decouples collection from knowledge; new modules require zero search-head changes.
- **Deployment**: Must deploy via Splunk Deployment Server without any manual per-host setup. Reason: This IS the Splunk fleet-management pattern; anything else doesn't scale.
- **AppInspect**: Both apps must pass `splunk-appinspect` cloud vetting. Reason: Enables Splunkbase publication and meets enterprise security gates.
- **No Windows hosts for testing**: Validation relies on static analysis, mock fixtures, and deferred-pilot live testing. Reason: User's current dev environment lacks Windows access; blocking on that would stall the project indefinitely.
- **Backwards compatibility**: Existing Linux event format, field names, and sourcetype (`odin:enumeration`) are frozen — existing search-time lookups and saved searches must keep working unchanged. Reason: User has a working classification pipeline; this milestone adds to it, doesn't replace it.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Full Windows parity (all 6 modules) rather than subset | User wants "same functionality as long as possible"; subset would leave visibility gaps on mixed estates | — Pending |
| PowerShell 5.1 baseline, no external modules | Ships with Server 2016+/Win 10 1607+; zero install; no PS Gallery dependency | — Pending |
| Registry-based package enumeration on Windows instead of `Win32_Product` | `Win32_Product` triggers MSI self-repair across all packages — directly violates "won't break the host" | — Pending |
| Linux modules frozen unless audit finds concrete defects | User explicitly asked not to touch working code | — Pending |
| Test strategy: static analysis + mock fixtures + deferred-pilot for Windows | No Windows hosts available; cannot block on live validation | — Pending |
| AppInspect gate is a hard requirement, not optional | Defines "production ready" concretely; enables Splunkbase path | — Pending |
| Packaging as `.tar.gz` per user preference | `.spl` is technically identical; user preference wins | — Pending |
| Dashboard expansion and Phase 3 (DS automation) explicitly excluded | Keeps milestone scope finite so user can actually finish and pilot | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-30 — milestone v1.1.0 kickoff (Container Observability, 3 phases)*

*Note: Active/Validated/Deferred requirement sections below still reflect v1.0.0 categorization. Per-milestone re-categorization deferred to next `/gsd-transition` cycle to avoid wholesale rewrite during milestone start.*
