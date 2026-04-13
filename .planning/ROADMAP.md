# Roadmap — TA-ODIN v1.0.0

**Milestone:** v1.0.0 — First Production Delivery
**Granularity:** coarse (3 phases)
**Created:** 2026-04-10

## Goal

Ship a cross-platform (Linux + Windows) TA-ODIN that is AppInspect-clean, production-hardened, and safe to pilot on a Splunk Deployment Server fleet of 10k+ mixed hosts.

## Build-Order Rationale

Three phases, executed strictly in order:

1. **Phase 1 (Windows Parity)** lands first because the CI gates in Phase 2 (shellcheck, PSScriptAnalyzer, two-app-split guard) and the AppInspect vetting in Phase 3 must have real Windows code to inspect. Windows work touches new files only (`TA-ODIN/bin/odin.ps1`, `TA-ODIN/bin/modules/*.ps1`), so it does not disturb the frozen Linux modules.
2. **Phase 2 (Production Hardening)** lands second because it adds the guardrails, tunables, and CI gates that operate across both Linux and Windows code. Running PSScriptAnalyzer before Windows code exists would be a no-op; running shell-injection audits after AppInspect would mean re-running AppInspect.
3. **Phase 3 (AppInspect Compliance)** is last because AppInspect is the release gate that inspects everything delivered by Phases 1 and 2. Running it earlier would force multiple remediation cycles.

## Phases

- [x] **Phase 1: Windows Parity** — Implement the PowerShell orchestrator and six Windows modules with byte-compatible `key=value` output against the existing Linux event schema. (completed 2026-04-13)
- [ ] **Phase 2: Production Hardening** — Fix version drift, expose tunables, add alerting saved searches, gate CI on linters, mechanically enforce the two-app split, and audit shell-injection risk.
- [ ] **Phase 3: AppInspect Compliance & Release Gate** — Make both apps pass `splunk-appinspect` cleanly, complete Splunkbase-ready metadata, review least-privilege permissions, and wire AppInspect into the release build as a hard gate.

## Phase Details

### Phase 1: Windows Parity
**Goal:** Windows endpoints produce the same six discovery signal streams as Linux endpoints, in the exact same `key=value` format, using only built-in PowerShell 5.1+ cmdlets, so the existing search-time classification lookups and saved searches work unchanged on Windows data.
**Depends on:** Nothing (first phase — touches new files only, does not modify frozen Linux code)
**Requirements:** WIN-01, WIN-02, WIN-03, WIN-04, WIN-05, WIN-06, WIN-07, WIN-08, WIN-09, WIN-10, WIN-11, WIN-12
**Success Criteria** (what must be TRUE):
  1. `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File TA-ODIN/bin/odin.ps1` run against a mock-fixture harness emits a `type=odin_start` marker, one event per present fixture per module type (`service`, `port`, `package`, `scheduled_task`, `process`, `mount`), and a `type=odin_complete modules_total=6 modules_success=6 modules_failed=0` marker — verifiable by grepping captured stdout.
  2. Static diff of a sample `type=service` event between Linux and Windows shows the identical set of field names (`timestamp`, `hostname`, `os`, `run_id`, `odin_version`, `type`, `service_name`, plus module-specific fields) — so existing `LOOKUP-classify_services` and the nightly Host Inventory saved search key off the same fields on both platforms.
  3. `grep -RIEn 'Invoke-Expression|Add-Type|iex |FromBase64String|Net\.WebClient|DownloadString|IEX' TA-ODIN/bin/` against the Windows code returns zero matches, and `grep -RIEn '#Requires -Module|Import-Module [^M]' TA-ODIN/bin/` shows no references to non-built-in modules — proves the zero-dependency / EDR-safe constraint holds by static inspection.
  4. `TA-ODIN/bin/odin.ps1` auto-discovers every `.ps1` file in `TA-ODIN/bin/modules/`, runs each under a bounded per-module timeout (Windows equivalent of the Linux `timeout 90`), honors a pre-set `$env:ODIN_MAX_EVENTS`, and on a fixture where one module throws, emits a `type=odin_error exit_code=<n>` event and still reaches `type=odin_complete` — verifiable by inducing a failure in a stub module and asserting on the emitted lines.
  5. `TA-ODIN/bin/modules/packages.ps1` reads from `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` and `HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall` only — confirmed by `grep -n 'Win32_Product' TA-ODIN/bin/modules/packages.ps1` returning zero matches (prevents MSI self-repair blast).
**Plans:** 3/3 plans complete
**UI hint:** no

### Phase 2: Production Hardening
**Goal:** Close every known production risk in the codebase — version drift, unsettable guardrails, invisible truncation, silent timeouts, un-linted scripts, un-enforced two-app split, and shell-injection exposure — so a Deployment Server push to 10k+ hosts is provably safe.
**Depends on:** Phase 1 (CI gates HARD-05/06 and the split guard HARD-07 must lint real Linux and Windows code; HARD-01 unifies versioning across both orchestrators)
**Requirements:** HARD-01, HARD-02, HARD-03, HARD-04, HARD-05, HARD-06, HARD-07, HARD-08
**Success Criteria** (what must be TRUE):
  1. `grep -RIEn 'ODIN_VERSION|^version' TA-ODIN/default/app.conf ODIN_app_for_splunk/default/app.conf TA-ODIN/bin/odin.sh TA-ODIN/bin/odin.ps1` shows the identical string `1.0.0` at every site — and a sample `type=odin_start` event captured from each orchestrator carries `odin_version=1.0.0` (proves HARD-01 resolves the 2.1.0 vs 2.2.0 drift at runtime, not just in config).
  2. Running `ODIN_MAX_EVENTS=10 ODIN_MODULE_TIMEOUT=5 bash TA-ODIN/bin/odin.sh` on a host with more than 10 services produces a `type=truncated` event and the final `odin_complete` reflects the lowered cap — and the equivalent `$env:ODIN_MAX_EVENTS=10` invocation of `odin.ps1` does the same (proves HARD-02 works on both orchestrators and pre-set env vars are honored, not overwritten).
  3. `splunk btool savedsearches list --app=ODIN_app_for_splunk` (or direct inspection of `ODIN_app_for_splunk/default/savedsearches.conf`) shows two new stanzas: one alerting on `type=truncated`, one on `type=odin_error exit_code=124` — and both compile as valid SPL when loaded via `splunk cmd btool --debug` (proves HARD-03 and HARD-04 are wired and parseable).
  4. `shellcheck TA-ODIN/bin/odin.sh TA-ODIN/bin/modules/*.sh` exits 0 with zero findings at default severity, `Invoke-ScriptAnalyzer -Path TA-ODIN/bin -Recurse` exits clean, and both checks are registered as required steps in `.github/workflows/` (or the project's CI equivalent) such that a deliberately-introduced `shellcheck` violation on a PR fails the pipeline — proves HARD-05 and HARD-06 are actual release gates, not advisory.
  5. The CI two-app-split guard fails fast when a test PR drops `indexes.conf` into `TA-ODIN/default/` or drops `bin/foo.sh` into `ODIN_app_for_splunk/` — verifiable by running the guard script locally against a dirty working copy and asserting non-zero exit (proves HARD-07 mechanically enforces what was previously discipline-only).
  6. `tools/tests/` contains a regression fixture that feeds a service/unit/package name containing shell metacharacters (`;`, `$(...)`, backticks, embedded newlines, unbalanced quotes) through `safe_val()` and the `emit` path, and asserts the resulting output is a single well-formed `key=value` line with no shell expansion — proves HARD-08 closed the injection surface and left a test behind to prevent regression.
**Plans:** TBD
**UI hint:** no

### Phase 3: AppInspect Compliance & Release Gate
**Goal:** Both apps pass `splunk-appinspect` cloud vetting with zero failures and no critical warnings, carry Splunkbase-ready metadata, use least-privilege permissions, and run AppInspect automatically on every release build so the v1.0.0 tarballs are pilot-deliverable with no ad-hoc pre-flight work.
**Depends on:** Phase 1 (AppInspect must vet the Windows code) and Phase 2 (AppInspect must vet the hardened orchestrators, new saved searches, and updated metadata — re-running it after any of those changes would waste a cycle)
**Requirements:** APPI-01, APPI-02, APPI-03, APPI-04, APPI-05, APPI-06
**Success Criteria** (what must be TRUE):
  1. `splunk-appinspect inspect TA-ODIN/ --mode precert` and `splunk-appinspect inspect ODIN_app_for_splunk/ --mode precert` both exit 0 with zero failures and zero manual-review warnings — the captured JSON reports are saved under `.planning/artifacts/appinspect/` so the result is reproducible, not transient.
  2. `grep -E '^(author|description|license|version|build|id)' TA-ODIN/default/app.conf` shows all six fields populated with non-placeholder values, and the same check passes for `ODIN_app_for_splunk/default/app.conf` — with `version = 1.0.0` matching the HARD-01 single source of truth.
  3. `metadata/default.meta` in both apps has been re-reviewed and, where tighter scoping is viable, the blanket `export = system` has been replaced with per-object `[lookups/...]` or `[savedsearches/...]` stanzas — documented in a short rationale comment in each file or in the commit message, so the least-privilege decision is auditable (APPI-05).
  4. The release build path (Makefile target, shell script, or CI job) invokes AppInspect as a mandatory step and fails the build on any AppInspect failure — verifiable by deliberately introducing a known AppInspect violation (e.g., a `http://` URL in a `.conf` comment) and confirming the release build halts (proves APPI-03 is a hard gate, not a reminder).
  5. A full-repo scan for AppInspect red-flag patterns — `grep -RIEn 'http[s]?://|Invoke-Expression|Add-Type|FromBase64String|/usr/local/bin|C:\\\\' TA-ODIN/ ODIN_app_for_splunk/` (excluding comments and legitimate Splunkbase URLs in `odin_recommended_tas.csv`) — returns no unexpected hits, confirming APPI-06 on both apps by static inspection.
**Plans:** TBD
**UI hint:** no

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Windows Parity | 3/3 | Complete   | 2026-04-13 |
| 2. Production Hardening | 0/TBD | Not started | - |
| 3. AppInspect Compliance & Release Gate | 0/TBD | Not started | - |

## Coverage

- **Total v1.0.0 requirements:** 26 (WIN-01..12, HARD-01..08, APPI-01..06)
- **Mapped:** 26/26
- **Orphans:** 0
- **Duplicates:** 0

_Note: The milestone brief stated "23 requirements to map" but REQUIREMENTS.md lists 12 + 8 + 6 = 26 REQ-IDs under the in-scope groups. The roadmap maps all 26 REQ-IDs present in REQUIREMENTS.md. The "23" figure in the brief appears to be a miscount; the authoritative source is REQUIREMENTS.md._
