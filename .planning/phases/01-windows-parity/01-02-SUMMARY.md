---
phase: 01-windows-parity
plan: 02
subsystem: ta-odin-windows
tags: [windows, powershell, orchestrator, splunk-uf, wave-1]
requires:
  - 01-01-PLAN (Wave 0 harness + fixtures + stubs)
provides:
  - Windows orchestrator (odin.ps1)
  - Shared PS library (_common.ps1)
  - Splunk UF .path wrapper (odin.path)
  - Forwarder inputs/props wiring
affects:
  - TA-ODIN/bin/
  - TA-ODIN/default/
tech-stack:
  added:
    - PowerShell 7+ (Start-Job / Wait-Job -Timeout canonical isolation pattern)
  patterns:
    - Dot-sourced shared library (no Import-Module)
    - CLM-safe emission via Write-Output (no raw encoders)
    - CRLF normalization at Splunk parse time (CHARSET = UTF-8)
    - Fixture-mode cmdlet shadowing via $env:ODIN_TEST_FIXTURE
key-files:
  created:
    - TA-ODIN/bin/modules/_common.ps1
    - TA-ODIN/bin/odin.ps1
    - TA-ODIN/bin/odin.path
  modified:
    - TA-ODIN/default/inputs.conf
    - TA-ODIN/default/props.conf
key-decisions:
  - D1 canonical Start-Job / Wait-Job -Timeout isolation implemented in odin.ps1
  - D2 dot-sourced _common.ps1 (no .psm1, no Import-Module)
  - D4 exit_code=124 timeout_reason=wait_job_timeout on Wait-Job expiry (POSIX parity)
  - D5-revised Write-Output only; CHARSET = UTF-8 in props.conf normalizes CRLF at parse time
  - D6 fixture-mode dot-source of stubs.ps1 gated by $env:ODIN_TEST_FIXTURE
requirements-completed:
  - WIN-01
  - WIN-08
  - WIN-09
  - WIN-10
  - WIN-12
duration: 15 min
completed: 2026-04-13
---

# Phase 1 Plan 02: Wave 1 Orchestrator + Shared Library Summary

Ships the Windows orchestrator, shared PowerShell helper library, Splunk UF
.path wrapper, and forwarder config wiring for TA-ODIN Phase 1. The
orchestrator emits canonical Linux-parity markers under fixture mode on
macOS pwsh, using the `Start-Job` / `Wait-Job -Timeout` canonical pattern
for per-module isolation, fail-soft error handling, and POSIX-convention
`exit_code=124` timeout synthesis — all CLM-safe with zero forbidden
dynamic-code patterns anywhere under `TA-ODIN/bin/`.

## Scope

- **Tasks completed:** 5 of 5
- **Files created:** 3 (`_common.ps1`, `odin.ps1`, `odin.path`)
- **Files modified:** 2 (`inputs.conf`, `props.conf`)
- **Total lines added:** 419 across 5 files
- **Start:** 2026-04-13T15:03Z
- **End:** 2026-04-13T15:10Z
- **Duration:** ~15 min

## Files Shipped

| File | Lines | Purpose | Locked Decisions |
|------|-------|---------|------------------|
| `TA-ODIN/bin/modules/_common.ps1` | 171 | Shared PS helpers: Get-OdinTimestamp, Format-OdinValue, Invoke-OdinEmit, Set-OdinContext, Initialize-OdinModuleState + D6 fixture dot-source | D2, D5-revised, D6 |
| `TA-ODIN/bin/odin.ps1` | 202 | Windows orchestrator — autodiscovers modules, Start-Job + Wait-Job -Timeout per module, canonical start/complete/error markers, fail-soft | D1, D2, D4, D5-revised, D6 |
| `TA-ODIN/bin/odin.path` | 1 | Splunk UF wrapper — `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File %SPLUNK_HOME%\...\odin.ps1` | WIN-10 |
| `TA-ODIN/default/inputs.conf` | 27 | Windows stanza header switched from `odin.ps1` to `odin.path`; Linux stanza preserved | RESEARCH §8 |
| `TA-ODIN/default/props.conf` | 18 | Added `CHARSET = UTF-8` under LINE_BREAKER | D5-revised |

## Commits

| # | Hash | Task | Message |
|---|------|------|---------|
| 1 | `3b10698` | 1 | `feat(01-02): add _common.ps1 shared PowerShell library` |
| 2 | `41ccc1e` | 2 | `feat(01-02): add Windows orchestrator odin.ps1 with Start-Job timeout` |
| 3 | `f9fb015` | 3 | `feat(01-02): add odin.path Splunk UF wrapper for WIN-10` |
| 4 | `8c186de` | 4 | `feat(01-02): point Windows input at odin.path and add CHARSET = UTF-8` |

Task 5 (smoke test) created no commits — pure verification task per plan contract.

## Design Decision Implementation Matrix

| Decision | Implemented In | Evidence |
|----------|----------------|----------|
| **D1** — Start-Job child-process isolation, per-module Wait-Job -Timeout | `odin.ps1` lines ~110-180 | `grep -c 'Start-Job\|Wait-Job -Timeout\|Stop-Job\|Receive-Job\|Remove-Job' odin.ps1` = 14 |
| **D1 operational** — WDAC allow-listing prerequisite | `odin.ps1` header comment (~lines 9-18) | `grep -cE 'WDAC\|allow-list' odin.ps1` = 5 |
| **D2** — Dot-sourced `_common.ps1`, no Import-Module | Orchestrator line ~63 `. $CommonLib` | `grep -c 'Import-Module' TA-ODIN/bin/` = 0 |
| **D4** — `exit_code=124 timeout_reason=wait_job_timeout` on Wait-Job expiry | `odin.ps1` Wait-Job null-check branch | `grep -c 'exit_code=124' odin.ps1` = 3 |
| **D5-revised** — Write-Output emission + CHARSET = UTF-8 parse-time normalization | `_common.ps1 Invoke-OdinEmit`, `props.conf` line 14 | Zero `[Console]::`, `New-Object System.Text.UTF8Encoding`, `[System.Text.Encoding]::` anywhere under `TA-ODIN/bin/` |
| **D6** — Fixture-mode dot-source of stubs.ps1 gated by `$env:ODIN_TEST_FIXTURE` | `_common.ps1` tail block | `grep -c '\$env:ODIN_TEST_FIXTURE' _common.ps1` = 3 |

## Smoke-Test Output (Task 5)

Run command:
```bash
ODIN_TEST_FIXTURE=tools/tests/windows-fixtures/hostA \
  pwsh -NoProfile -NonInteractive -File TA-ODIN/bin/odin.ps1
```

Actual output (2 lines, clean stdout, no stderr noise):
```
timestamp=2026-04-13T15:09:05Z hostname=JOEHANSE-M-QJH9 os=windows run_id=1776092946-33876 odin_version=1.0.0 type=odin_start message="TA-ODIN Windows enumeration started"
timestamp=2026-04-13T15:09:05Z hostname=JOEHANSE-M-QJH9 os=windows run_id=1776092946-33876 odin_version=1.0.0 type=odin_complete modules_total=0 modules_success=0 modules_failed=0 duration_ms=13 message="TA-ODIN Windows enumeration completed"
```

Assertions (from Task 5):
- `type=odin_start` count = 1
- `type=odin_complete modules_total=[0-9]+ modules_success=[0-9]+ modules_failed=[0-9]+ duration_ms=[0-9]+` count = 1
- `ParserError|CommandNotFoundException|RuntimeException` count = 0
- Process exit code = 0
- `modules_total=0` (expected Wave 1 intermediate state; plan 03 will raise this to 6)
- Wall-clock duration < 1 second (well under 10s budget)

## Nyquist Dimension State After Plan 02

| Dim | Gate | Status | Notes |
|-----|------|--------|-------|
| 1 | Static grep for forbidden patterns in `TA-ODIN/bin/` | **PASS** | Zero `Invoke-Expression \| Add-Type \| iex \| FromBase64String \| Net.WebClient \| DownloadString \| IEX`; zero `[Console]:: \| New-Object System.Text.UTF8Encoding \| [System.Text.Encoding]::` |
| 2 | No external module dependencies (no `Import-Module` of non-Microsoft.*) | **PASS** | Harness grep returns 0 |
| 3 | No `Win32_Product` in packages.ps1 | **PASS** (vacuous) | packages.ps1 doesn't exist yet |
| 4 | Behavioral fixture test — `type=odin_start` + `type=odin_complete modules_total=6` + 6 module types | **PARTIAL** | start/complete emitted, but the literal `modules_total=6` assertion and per-type counts (`service/port/package/scheduled_task/process/mount`) wait on plan 03 modules |
| 5 | Linux↔Windows golden parity (same service names produced) | **FAIL (expected)** | Plan 03 |
| 6 | Fail-soft under hostA-broken fixture | **FAIL (expected)** | Machinery is in place (try/catch + Wait-Job -Timeout + exit_code=124 synthesis), but requires module 3 of plan 03 to execute end-to-end |

- `bash tools/tests/windows-parity-harness.sh --quick` → exit 0
- `bash tools/tests/windows-parity-harness.sh` (full) → exit 1 (Dim 4/5/6 awaiting plan 03)

Correct intermediate state per plan 02 verification contract.

## Deviations from Plan

### [Rule 3 — Blocking] Fixture stub `Get-ChildItem` breaks named parameters `-Filter` / `-File` / `-Path`

- **Found during:** Task 2 initial smoke test (orchestrator ran but printed a noisy `Get-ChildItem` error to stderr: `"A positional parameter cannot be found that accepts argument '-Filter'"` and subsequently `"Cannot find path '.../-Path' because it does not exist"`).
- **Root cause:** `tools/tests/windows-fixtures/stubs.ps1` shadows `Get-ChildItem` with a function using `[Parameter(ValueFromRemainingArguments=$true)]$Args` and forwards via `Microsoft.PowerShell.Management\Get-ChildItem @Args`. Splatting an array positionally mangles named parameters.
- **Fix (in-scope, orchestrator side):** Changed the module-discovery call from `Get-ChildItem -Path $ModulesDir -Filter '*.ps1' -File | Where-Object { $_.Name -ne '_common.ps1' }` to `Get-ChildItem $ModulesDir | Where-Object { -not $_.PSIsContainer -and $_.Extension -eq '.ps1' -and $_.Name -ne '_common.ps1' }`. Positional path + post-filter works identically against both the real cmdlet and the fixture shadow.
- **Files modified:** `TA-ODIN/bin/odin.ps1`
- **Verification:** Fixture smoke now prints exactly 2 clean marker lines with no stderr noise.
- **Commit:** `41ccc1e`
- **NOT touched:** `tools/tests/windows-fixtures/stubs.ps1` — that is a Wave 0 artifact and out of scope for this plan. Plan 03 may revisit stub parameter shapes if modules need named parameters that the current stub form breaks.

### [Rule 3 — Blocking] Comment wording tripped Dimension 1 / Dimension 2 static grep gates

- **Found during:** Task 1 verification (`grep -cE 'Invoke-Expression|Add-Type|...'` returned non-zero on `_common.ps1`); again in Task 2 harness run (`Import-Module ` grep hit).
- **Root cause:** Header comments listed forbidden patterns by name for documentation. The harness grep does not exempt comments — any literal match is a failure.
- **Fix:** Rewrote comments to describe the forbidden-pattern class without quoting the literal strings. Same for `$global:` in a scope-discipline comment (rephrased to "global-scope state").
- **Files modified:** `TA-ODIN/bin/modules/_common.ps1`, `TA-ODIN/bin/odin.ps1`
- **Verification:** `bash tools/tests/windows-parity-harness.sh --quick` → Dim 1, 2, 3 all PASS.
- **Commits:** `3b10698`, `41ccc1e`

### [Noted — not a deviation] Pre-existing comment in `props.conf` contains the string `KV_MODE`

- Line 5 of the pre-existing props.conf top-of-file comment reads: `# Full search-time props (KV_MODE, CIM aliases, lookups) live in ODIN_app_for_splunk.` This is a documentation comment, not a live directive, but a strict `grep -cE 'KV_MODE|LOOKUP-|FIELDALIAS-|EXTRACT-'` returns 1 instead of the acceptance criterion's expected 0.
- **Scope boundary:** The comment pre-dates plan 02 and is unrelated to my changes. The semantic intent of the acceptance criterion ("no search-time config leaked into forwarder props") is satisfied — no actual settings of those types exist. Not touching the pre-existing comment per the plan's scope rules.
- No commit.

**Total deviations:** 2 Rule-3 auto-fixes (both addressed during their respective tasks). **Impact:** zero scope expansion; all 5 tasks still completed; plan 02 success criteria met.

## Authentication Gates

None. No external services involved.

## Known Stubs

None. Plan 02 ships infrastructure only; no data sources to wire. Plan 03 will ship the 6 modules that populate real data.

## Handoff Notes to Plan 03

Plan 03's 6 modules (`services`, `ports`, `packages`, `cron`/`scheduled_tasks`, `processes`, `mounts`) can dot-source `_common.ps1` and rely on the following contract without additional wiring:

```powershell
# At the top of each module (bin/modules/<name>.ps1):
. $PSScriptRoot/_common.ps1
Set-OdinContext              # idempotent; no-op if orchestrator already set $env:ODIN_*
Initialize-OdinModuleState   # resets per-module event counter so MAX_EVENTS is per-module
# ...module logic, calling Invoke-OdinEmit for each event and Format-OdinValue for escaping...
```

When each module is invoked by the orchestrator via `Start-Job`, a child pwsh process is spawned that re-reads `_common.ps1`, picks up `$env:ODIN_TEST_FIXTURE` if set, and therefore automatically loads the fixture stubs under harness mode. Plan 03 modules do NOT need their own fixture detection logic.

**Important parameter-shape caveat from deviation 1:** The Wave 0 fixture stubs use `ValueFromRemainingArguments` which mangles named parameters when forwarded via `@Args`. Plan 03 modules should prefer **positional arguments** to Windows cmdlets under test, or use only cmdlet parameters that the fixture stubs explicitly declare. If any module needs a named parameter like `-Filter`, check `tools/tests/windows-fixtures/stubs.ps1` first, or update the stub's parameter shape in a small Wave 0 patch.

**Expected plan 03 delta:** After plan 03 lands with 6 modules + corresponding fixture JSON, the full harness should reach:
- Dim 4 PASS (`type=odin_complete modules_total=6`, plus at least 1 event of each of `type=service|port|package|scheduled_task|process|mount`)
- Dim 5 PASS (Linux↔Windows service-name parity against `tools/tests/linux-golden/services.txt`)
- Dim 6 PASS (hostA-broken fixture produces `type=odin_error` events and orchestrator still exits 0)

Ready for plan 03 (Wave 2: 6 Windows modules).

## Self-Check: PASSED

- `TA-ODIN/bin/modules/_common.ps1` — FOUND
- `TA-ODIN/bin/odin.ps1` — FOUND (new content, not legacy placeholder)
- `TA-ODIN/bin/odin.path` — FOUND
- `TA-ODIN/default/inputs.conf` — MODIFIED (Windows stanza points at odin.path)
- `TA-ODIN/default/props.conf` — MODIFIED (CHARSET = UTF-8 added)
- Commit `3b10698` — FOUND in `git log --oneline`
- Commit `41ccc1e` — FOUND in `git log --oneline`
- Commit `f9fb015` — FOUND in `git log --oneline`
- Commit `8c186de` — FOUND in `git log --oneline`
- Fixture smoke exit code = 0 — verified
- Harness --quick exit code = 0 — verified
- Harness full exit code = 1 (Dim 4/5/6 pending plan 03) — expected intermediate state
