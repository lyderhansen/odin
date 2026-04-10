# Requirements — TA-ODIN

## Milestone v1.0.0 — First Production Delivery

**Goal:** Ship a cross-platform (Linux + Windows) TA-ODIN that is AppInspect-clean, production-hardened, and safe to pilot on a Splunk Deployment Server fleet of 10k+ mixed hosts.

**In scope this milestone:** Windows parity (A), production hardening (B), AppInspect compliance (C).

**Not in scope this milestone:** Cross-platform testing harness (D), end-user documentation (E), Windows classification CSV content (F), reproducible packaging (G). Tracked under *Deferred to v1.1+*.

---

## v1.0.0 Requirements

### A. Windows Parity (WIN-*)

Full PowerShell 5.1+ implementation that mirrors the Linux orchestrator and six modules, emitting the same `key=value` event format so existing search-time lookups and saved searches keep working.

- [ ] **WIN-01** — `TA-ODIN/bin/odin.ps1` orchestrator auto-discovers PowerShell modules under `bin/modules/*.ps1`, runs each under a bounded per-module timeout, enforces `ODIN_MAX_EVENTS`, emits `type=odin_start` and `type=odin_complete` markers, and exports shared context via `ODIN_*` environment variables
- [ ] **WIN-02** — Windows `services.ps1` module enumerates services using `Get-Service` plus `Get-CimInstance Win32_Service` for start mode and image path; emits one `type=service` event per service
- [ ] **WIN-03** — Windows `ports.ps1` module enumerates listening endpoints using `Get-NetTCPConnection -State Listen` and `Get-NetUDPEndpoint`; emits one `type=port` event per listener
- [ ] **WIN-04** — Windows `packages.ps1` module enumerates installed software by scanning `HKLM:\...\Uninstall` and `HKLM:\...\Wow6432Node\...\Uninstall` registry keys — **never** `Win32_Product` (triggers MSI self-repair); emits one `type=package` event per entry
- [ ] **WIN-05** — Windows `scheduled_tasks.ps1` module enumerates scheduled tasks using `Get-ScheduledTask` plus `Get-ScheduledTaskInfo`; emits one `type=scheduled_task` event per task
- [ ] **WIN-06** — Windows `processes.ps1` module enumerates running processes using `Get-Process` (plus `Get-CimInstance Win32_Process` for command line where available); emits one `type=process` event per process
- [ ] **WIN-07** — Windows `mounts.ps1` module enumerates filesystem volumes using `Get-Volume` / `Get-PSDrive -PSProvider FileSystem`; emits one `type=mount` event per volume
- [ ] **WIN-08** — All Windows modules emit the **identical** space-separated `key=value` format used by Linux, including the same field names (`hostname`, `os`, `run_id`, `type`, etc.), so existing `odin_classify_*.csv` lookups and the three nightly saved searches work unchanged
- [ ] **WIN-09** — Windows code uses only built-in PowerShell 5.1+ cmdlets: no PS Gallery modules, no `Add-Type`, no `Invoke-Expression`, no base64-encoded commands, no compiled binaries, no network calls
- [ ] **WIN-10** — Windows orchestrator is invokable via `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File odin.ps1` and runs cleanly under AppLocker / WDAC / Constrained Language Mode
- [ ] **WIN-11** — Windows modules run correctly under `LocalSystem` (the default Splunk UF service account) on Windows Server 2019/2022 and Windows 10/11
- [ ] **WIN-12** — Windows orchestrator never aborts on module failure — failed modules emit a `type=odin_error` event with `exit_code` and the orchestrator continues, matching the Linux fail-soft behavior

### B. Production Hardening (HARD-*)

Close the gaps that prevent the current codebase from being safe to roll out to 10k+ hosts.

- [ ] **HARD-01** — Single source of truth for `ODIN_VERSION` across `TA-ODIN/default/app.conf`, `ODIN_app_for_splunk/default/app.conf`, `TA-ODIN/bin/odin.sh`, and `TA-ODIN/bin/odin.ps1`; resolves the current `2.1.0` vs `2.2.0` drift and resets to `1.0.0`
- [ ] **HARD-02** — `ODIN_MAX_EVENTS` and `ODIN_MODULE_TIMEOUT` are tunable via environment variables in both orchestrators; pre-set values from the environment are honored and not overwritten by script defaults
- [ ] **HARD-03** — Saved search in `ODIN_app_for_splunk/default/savedsearches.conf` alerts on `type=truncated` events across the fleet so silent MAX_EVENTS truncation becomes observable
- [ ] **HARD-04** — Saved search in `ODIN_app_for_splunk/default/savedsearches.conf` alerts on `type=odin_error exit_code=124` (module timeouts) so fleet-wide timeout patterns become observable
- [ ] **HARD-05** — `shellcheck` runs clean (zero findings at default severity) on every `TA-ODIN/bin/**/*.sh`, gated in CI as a release blocker
- [ ] **HARD-06** — `PSScriptAnalyzer` runs clean (zero findings at default severity) on every `TA-ODIN/bin/**/*.ps1`, gated in CI as a release blocker
- [ ] **HARD-07** — CI guard mechanically enforces the two-app split: forbids `indexes.conf`, `transforms.conf`, `savedsearches.conf`, and `lookups/` inside `TA-ODIN/`; forbids `inputs.conf` and any `bin/` scripts inside `ODIN_app_for_splunk/`
- [ ] **HARD-08** — `safe_val()` and every `emit` call site in the Linux modules are audited for shell-injection against malicious service / unit / package / mount names; findings are fixed and a regression test fixture is added to `tools/tests/`

### C. AppInspect Compliance (APPI-*)

Make both apps pass Splunk's cloud vetting cleanly so the milestone can be pilot-delivered as a Splunkbase-ready bundle.

- [ ] **APPI-01** — `TA-ODIN` passes `splunk-appinspect inspect` with zero failures and no critical warnings
- [ ] **APPI-02** — `ODIN_app_for_splunk` passes `splunk-appinspect inspect` with zero failures and no critical warnings
- [ ] **APPI-03** — AppInspect runs on every release build (local or CI), not ad-hoc — it is a hard release gate
- [ ] **APPI-04** — `app.conf` metadata in both apps is Splunkbase-ready: `author`, `description`, `license`, `version`, `build`, `id` populated with correct values
- [ ] **APPI-05** — `metadata/default.meta` permissions reviewed for least-privilege in both apps; exports are scoped as tightly as viable rather than blanket `export = system`
- [ ] **APPI-06** — No AppInspect red flags exist in either app: no hardcoded host paths, no outbound network calls from scripts, no binary execution, no suspicious PowerShell / bash patterns that trip cloud vetting

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

_Populated by `gsd-roadmapper` when the roadmap is created. Each REQ-ID will be mapped to exactly one phase._

| REQ-ID | Phase | Notes |
|--------|-------|-------|
| _pending roadmap_ | | |
