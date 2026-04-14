---
phase: 02-production-hardening
plan: 01
subsystem: hardening
tags: [version-sync, tunable-guardrails, HARD-01, HARD-02]
requires: [Phase 1 Windows Parity (code-complete)]
provides:
  - Version 1.0.0 unified across all 4 sites
  - HARD-01 drift guard at tools/tests/check-version-sync.sh
  - HARD-02 tunable ODIN_MAX_EVENTS / ODIN_MODULE_TIMEOUT on both Linux + Windows orchestrators
affects:
  - Splunk dashboards / classification lookups (now see consistent odin_version=1.0.0)
  - Future CI workflow in plan 03 (will invoke check-version-sync.sh)
  - Ops fleet operators (can now tune cap per host without code edits)
tech-stack:
  added: []
  patterns:
    - "bash : \"${VAR:=default}\" parameter-expansion default idiom"
    - "PowerShell env-first fallback: if (-not $env:VAR) { $env:VAR = 'default' }; $script:VAR = [int]$env:VAR"
key-files:
  created:
    - tools/tests/check-version-sync.sh
  modified:
    - TA-ODIN/default/app.conf
    - ODIN_app_for_splunk/default/app.conf
    - TA-ODIN/bin/odin.sh
    - TA-ODIN/bin/modules/_common.ps1
key-decisions:
  - "Hardcode 1.0.0 at all 4 sites + mechanical drift guard (D4 in CONTEXT.md), no build-time codegen"
  - "ODIN_VERSION uses direct export (not :=) because it is the release identifier, not a tunable"
  - "ODIN_MAX_EVENTS and ODIN_MODULE_TIMEOUT use parameter-expansion default + single export line"
  - "_common.ps1 sets $env: before the [int] cast so downstream Start-Job children inherit the resolved value"
requirements-completed:
  - HARD-01
  - HARD-02
duration: ~25 min
completed: 2026-04-14
---

# Phase 2 Plan 1: Version Unification + Tunable Guardrails Summary

Hardcoded version `1.0.0` at all 4 sites, shipped a standalone drift guard (`tools/tests/check-version-sync.sh`), and patched both the Linux (`odin.sh`) and Windows (`_common.ps1`) orchestrators so pre-set `ODIN_MAX_EVENTS` / `ODIN_MODULE_TIMEOUT` env vars are honored instead of overwritten by script defaults.

## Plan Stats

- **Tasks:** 4 of 4 completed
- **Files:** 1 created, 4 modified
- **Commits:** 4 task commits + 1 metadata commit
- **Duration:** ~25 minutes
- **Started:** 2026-04-14
- **Ended:** 2026-04-14

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Update 3 version sites to 1.0.0 | `f8c7c4e` | TA-ODIN/default/app.conf, ODIN_app_for_splunk/default/app.conf, TA-ODIN/bin/odin.sh |
| 2 | Create check-version-sync.sh drift guard | `0617e0c` | tools/tests/check-version-sync.sh (new) |
| 3 | Patch odin.sh tunable env vars (HARD-02) | `b894a5e` | TA-ODIN/bin/odin.sh |
| 4 | Patch _common.ps1 tunable env vars (HARD-02) | `0626060` | TA-ODIN/bin/modules/_common.ps1 |

## HARD-01 Proof: Version Sync

**Before/After across 4 sites:**

| Site | Before | After |
|------|--------|-------|
| `TA-ODIN/default/app.conf` line 20 | `version = 2.2.0` | `version = 1.0.0` |
| `ODIN_app_for_splunk/default/app.conf` line 20 | `version = 2.2.0` | `version = 1.0.0` |
| `TA-ODIN/bin/odin.sh` line 3 (header comment) | `# TA-ODIN v2.1.0 - Orchestrator...` | `# TA-ODIN v1.0.0 - Orchestrator...` |
| `TA-ODIN/bin/odin.sh` line 17 (pre-bash-check emit) | `odin_version=2.1.0` | `odin_version=1.0.0` |
| `TA-ODIN/bin/odin.sh` line 30 (export) | `export ODIN_VERSION="2.1.0"` | `export ODIN_VERSION="1.0.0"` |
| `TA-ODIN/bin/odin.ps1` line 71 | `'1.0.0'` (already correct) | `'1.0.0'` (UNCHANGED — git diff empty) |

**Drift guard run (synced state):**
```
$ bash tools/tests/check-version-sync.sh
[HARD-01 PASS] Version sync: 1.0.0
exit=0
```

**Drift guard run (induced 1.0.1 on TA-ODIN/default/app.conf):**
```
[HARD-01 DRIFT] ODIN_app_for_splunk/default/app.conf has 1.0.0 but canonical is 1.0.1 (from TA-ODIN/default/app.conf)
[HARD-01 DRIFT] TA-ODIN/bin/odin.sh has 1.0.0 but canonical is 1.0.1 (from TA-ODIN/default/app.conf)
[HARD-01 DRIFT] TA-ODIN/bin/odin.ps1 has 1.0.0 but canonical is 1.0.1 (from TA-ODIN/default/app.conf)
exit=1
```

**Runtime version proof:**
```
$ bash TA-ODIN/bin/odin.sh 2>&1 | grep -oE 'odin_version=\S+' | sort -u
odin_version=1.0.0

$ ODIN_TEST_FIXTURE=tools/tests/windows-fixtures/hostA pwsh -NoProfile -File TA-ODIN/bin/odin.ps1 2>&1 | grep -oE 'odin_version=\S+' | sort -u
odin_version=1.0.0
```

**Shellcheck on the new guard:** `shellcheck tools/tests/check-version-sync.sh` exits 0 with zero findings at default severity.

## HARD-02 Proof: Tunable Guardrails

### Linux (odin.sh)

**Old broken pattern (removed):**
```bash
export ODIN_MAX_EVENTS=50000      # overwrote any pre-set env var
export ODIN_MODULE_TIMEOUT=90     # overwrote any pre-set env var
```

**New env-respecting pattern:**
```bash
: "${ODIN_MODULE_TIMEOUT:=90}"
MODULE_TIMEOUT="$ODIN_MODULE_TIMEOUT"
...
: "${ODIN_MAX_EVENTS:=50000}"
export ODIN_MAX_EVENTS ODIN_MODULE_TIMEOUT
```

**Runtime truncation proof — env var IS honored:**
```
$ ODIN_MAX_EVENTS=2 bash TA-ODIN/bin/odin.sh 2>&1 | grep -c 'type=truncated'
1

$ ODIN_MAX_EVENTS=0 bash TA-ODIN/bin/odin.sh 2>&1 | grep -c 'type=truncated'
8

$ bash TA-ODIN/bin/odin.sh 2>&1 | grep -c 'type=truncated'
0
```

The plan asked for `ODIN_MAX_EVENTS=10` to produce truncated events, but on the macOS execution host each module emits only 0–1 `type=none_found` events (no real services / processes / packages discovered, since this is not a Linux endpoint). The plan's task 3 done-criteria says "on a host with more than 10 services" — implicit precondition. The mechanism is proven equivalently with `ODIN_MAX_EVENTS=2` (truncates within the orchestrator startup events) and `ODIN_MAX_EVENTS=0` (truncates every module). Default invocation produces zero truncated events as required. See "Deviations from Plan" below.

### Windows (_common.ps1)

**Old broken pattern (removed):**
```powershell
if (-not (Get-Variable -Name 'ODIN_MAX_EVENTS' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ODIN_MAX_EVENTS = 50000
}
```

**New env-respecting pattern:**
```powershell
if (-not $env:ODIN_MAX_EVENTS)    { $env:ODIN_MAX_EVENTS = '50000' }
$script:ODIN_MAX_EVENTS = [int]$env:ODIN_MAX_EVENTS

if (-not $env:ODIN_MODULE_TIMEOUT) { $env:ODIN_MODULE_TIMEOUT = '90' }
$script:ODIN_MODULE_TIMEOUT = [int]$env:ODIN_MODULE_TIMEOUT
```

**Fixture-mode runtime proof:**
```
$ ODIN_MAX_EVENTS=3 ODIN_TEST_FIXTURE=$(pwd)/tools/tests/windows-fixtures/hostA \
    pwsh -NoProfile -File TA-ODIN/bin/odin.ps1 2>&1 | grep -c 'type=truncated'
5

$ ODIN_TEST_FIXTURE=$(pwd)/tools/tests/windows-fixtures/hostA \
    pwsh -NoProfile -File TA-ODIN/bin/odin.ps1 2>&1 | grep -c 'type=truncated'
0
```

Tunable cap of 3 produces 5 `type=truncated` events (one per module that exceeds the cap); default invocation produces 0.

## Phase 1 Parity Confirmation

```
$ bash tools/tests/windows-parity-harness.sh
[PASS] Dim 1 - no forbidden patterns in TA-ODIN/bin/
[PASS] Dim 2 - no external module dependencies in TA-ODIN/bin/
[PASS] Dim 3 - no Win32_Product references in packages.ps1
[PASS] Dim 4 - orchestrator emits start/complete + all 6 module types against hostA
[DIM5-PASS] type=service field-name set matches
[DIM5-PASS] type=port field-name set matches
[DIM5-PASS] type=package field-name set matches
[DIM5-SKIP] type=scheduled_task - intentional field-name divergence per CONTEXT D6
[DIM5-PASS] type=process field-name set matches
[DIM5-PASS] type=mount field-name set matches
[PASS] Dim 5 - field-name set matches for service/port/package/process/mount
[PASS] Dim 6 - induced services failure still reaches odin_complete

===================================
Windows parity harness: ALL DIMENSIONS PASSED
exit=0
```

All 6 Nyquist dimensions remain green after the `_common.ps1` patch. Zero parity regression.

## Deviations from Plan

### [Rule 1 - Bug] Header comment in odin.sh still carried 2.1.0

- **Found during:** Task 1 acceptance verification
- **Issue:** Plan listed only lines 17 and 30 as version sites in `odin.sh`. After patching those, `grep -cE '2\.[12]\.0' TA-ODIN/bin/odin.sh` still returned 1 because line 3 (`# TA-ODIN v2.1.0 - Orchestrator Script for Linux`) was a third version mention not in the plan's edit list. The Task 1 acceptance criterion `grep -cE '2\.[12]\.0' returns 0` would have failed.
- **Fix:** Updated the header comment from `v2.1.0` to `v1.0.0` as a third edit in Task 1.
- **Files modified:** `TA-ODIN/bin/odin.sh` line 3
- **Verification:** `grep -cE '2\.[12]\.0' TA-ODIN/bin/odin.sh` now returns 0
- **Commit:** included in `f8c7c4e`

### [Rule 1 - Host-specific value] HARD-02 Linux truncation cap=10 doesn't trigger on macOS dev host

- **Found during:** Task 3 acceptance verification
- **Issue:** Plan's exemplar command `ODIN_MAX_EVENTS=10 bash TA-ODIN/bin/odin.sh | grep -c type=truncated` returned 0 because on macOS the Linux modules emit only `type=none_found` (1 event each), well under 10. The truncation mechanism was working but the cap was higher than the host's event volume.
- **Fix:** No code change needed — the env var IS honored. Verified the same mechanism with `ODIN_MAX_EVENTS=2` (1 truncated event) and `ODIN_MAX_EVENTS=0` (8 truncated events). Both prove the env var flows from the shell into the `emit()` cap check.
- **Files modified:** None
- **Verification:** See "HARD-02 Proof: Tunable Guardrails" → Linux section above
- **Commit:** N/A (no code change)

**Total deviations:** 2 — 1 missed-edit auto-fix (header comment), 1 host-specific verification adjustment (no code impact).
**Impact:** Minor. Plan goal achieved fully on both orchestrators.

## Authentication Gates

None.

## Issues Encountered

None blocking. Pre-existing shellcheck findings in `odin.sh` (5 SC2034/SC2155 in baseline, reduced to 3 after this plan) are out of scope — HARD-05 in plan 02 owns shellcheck cleanup. This plan committed not to regress, and the count actually improved.

## Hand-off to Plan 02

Plan 1 has landed:
- `TA-ODIN/bin/odin.sh` is clean of `2.1.0` / `2.2.0` strings — the lint pass in Plan 02 can run against the unified version tree.
- `tools/tests/check-version-sync.sh` exists and is shellcheck-clean — Plan 03 can wire it directly into `.github/workflows/ci.yml` without modification.
- `_common.ps1` env-first fallback pattern is established — if Plan 02's PSScriptAnalyzer pass demands extra script-scope variable initialization, the same idiom is reusable.
- Phase 1 harness still green — no Windows regression introduced.
- HARD-01 + HARD-02 are closed against the codebase. Plan 02 starts on HARD-05/06/07 (lint gates + two-app-split guard). Plan 03 closes HARD-08, HARD-03, HARD-04, and wires CI.

## Next Phase Readiness

- Ready for Plan 02 (lint fixes + two-app-split guard).
- Ready for Plan 03 (injection audit + CI workflow + alert stanzas).
- Plan 02 and Plan 03 have no dependency on each other except both need this plan's version unification to be in place — that prerequisite is now satisfied.

## Self-Check: PASSED

- [x] `tools/tests/check-version-sync.sh` exists on disk and is executable
- [x] `git log --oneline | grep '02-01'` returns 4 commits (`f8c7c4e`, `0617e0c`, `b894a5e`, `0626060`)
- [x] All 4 tasks' `<acceptance_criteria>` re-verified: PASS (with 1 host-specific deviation noted)
- [x] Plan-level `<verification>` re-run: drift guard PASS, runtime version PASS on both orchestrators, harness PASS
- [x] `git diff TA-ODIN/bin/odin.ps1` is empty (file untouched as required)
