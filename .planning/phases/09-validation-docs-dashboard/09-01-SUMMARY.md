---
phase: 09-validation-docs-dashboard
plan: 01
subsystem: test-tooling
tags: [host-info, parity, regression-test, bash, HOST-03]
dependency_graph:
  requires: [07-01, 08-01]
  provides: [check-host-info-parity.sh]
  affects: [ci-pipeline]
tech_stack:
  added: []
  patterns: [set-u-fail-accumulator, repo-root-discovery, process-substitution-diff]
key_files:
  created: [tools/tests/check-host-info-parity.sh]
  modified: []
decisions:
  - "D-08: dedicated script not harness extension — single-purpose, clean CI output"
  - "D-09: live execution mode, not fixture-based — catches runtime regressions"
  - "Envelope exclusion: strip timestamp|hostname|os|run_id|odin_version|type before counting to report 13 type-specific fields"
metrics:
  duration: "~10 min"
  completed: "2026-04-29"
  tasks_completed: 4
  files_created: 1
  files_modified: 0
---

# Phase 9 Plan 1: HOST-03 Cross-Platform Parity Regression Test Summary

## One-liner

Cross-platform HOST-03 parity test: live bash + pwsh orchestrator execution, field-name diff (envelope excluded), 13-field PASS on dev box, SKIP gate for pwsh-free environments.

## What Was Built

`tools/tests/check-host-info-parity.sh` — a single-purpose regression test that verifies the Linux and Windows orchestrators both emit `type=odin_host_info` events with the same 13 field names (modulo platform-specific values).

Key behaviors:
- **SKIP gate (D-09):** If `pwsh` is not available, exits 0 with `[HOST-03 SKIP]` — does not fail loudly
- **Live execution (D-09):** Runs both `bash TA-ODIN/bin/odin.sh` and `pwsh TA-ODIN/bin/odin.ps1` directly
- **Field-name extraction:** `grep -oE '[a-z_]+='` captures all `fieldname=` tokens; envelope fields stripped before comparison
- **Diff logic:** `diff <(echo "$linux_fields") <(echo "$windows_fields")` — exits clean on parity
- **Structured tokens:** `[HOST-03 PASS/FAIL/SKIP]` per repo convention

## Completed Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| T1 | Skeleton + pwsh SKIP gate + full extraction + diff logic | d97919c | tools/tests/check-host-info-parity.sh (created, 60 lines) |
| T2-T3 | Field extraction + diff (integrated) | d97919c | (same commit — integrated approach) |
| T4 (fix) | Envelope exclusion so count = 13 not 19 | 0aaab45 | tools/tests/check-host-info-parity.sh (+7 lines) |

## Live Test Results (Task 4 Verification)

```
$ bash tools/tests/check-host-info-parity.sh
[HOST-03 PASS] Linux + Windows field-set parity confirmed (13 fields each)
Exit code: 0

$ env PATH=/bin bash tools/tests/check-host-info-parity.sh
[HOST-03 SKIP] pwsh not found — parity test deferred to environment with PowerShell
SKIP-mode exit: 0
```

Regression suite (all green):
- `bash tools/tests/check-host-info.sh` → [HOST-01 PASS] All checks passed
- `bash tools/tests/check-version-sync.sh` → [HARD-01 PASS] Version sync: 1.0.1
- `bash tools/tests/check-two-app-split.sh` → [HARD-07 PASS] Two-app split is clean
- `bash tools/tests/windows-parity-harness.sh` → ALL DIMENSIONS PASSED

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Envelope field exclusion: count was 19 instead of 13**
- **Found during:** Task 4 live verification
- **Issue:** The field extraction regex `grep -oE '[a-z_]+='` captured all fields in the event line including the 6 common envelope fields (timestamp, hostname, os, run_id, odin_version, type), producing a count of 19 instead of the specified 13
- **Fix:** Added `grep -vE "$_envelope"` filter (where `_envelope='^(timestamp|hostname|os|run_id|odin_version|type)$'`) to strip envelope fields before sort/comparison. Parity diff still works correctly (both platforms have identical envelope, so diff result is unchanged); only the displayed count now reflects the 13 type-specific fields
- **Files modified:** tools/tests/check-host-info-parity.sh
- **Commit:** 0aaab45

**2. [Integration approach] Tasks 1-3 committed together in T1**
- T1 created the skeleton; T2 (extraction) and T3 (diff logic) were integrated into the same file write rather than applied as sequential edits. All Task 2 and Task 3 acceptance criteria are met in the final script. This is not a functional deviation — the end state is identical to what sequential edits would produce.

## Known Stubs

None. The script produces live results — no hardcoded empty values, no placeholder text.

## Threat Flags

No new threat surface. The script reads orchestrator stdout (controlled by TA-ODIN itself) and writes only to its own stdout. No network calls, no file writes, no credential handling.

## Self-Check: PASSED

- `tools/tests/check-host-info-parity.sh` exists: FOUND
- Commit d97919c exists: FOUND  
- Commit 0aaab45 exists: FOUND
- `bash tools/tests/check-host-info-parity.sh` exits 0 with `[HOST-03 PASS]`: VERIFIED
- Field count is 13: VERIFIED
- SKIP mode exits 0 with `[HOST-03 SKIP]`: VERIFIED
