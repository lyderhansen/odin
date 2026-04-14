---
status: complete
phase: 02-production-hardening
source: [02-01-SUMMARY.md, 02-02-SUMMARY.md, 02-03-SUMMARY.md]
started: 2026-04-14T12:00:00Z
updated: 2026-04-14T13:30:00Z
---

## Current Test

[testing complete]

## Tests

### 1. HARD-01 version sync — all 4 sites on 1.0.0 + drift guard green
expected: `bash tools/tests/check-version-sync.sh` exits 0 and all 4 version sites contain `1.0.0`
result: pass

### 2. HARD-02 tunable guardrails work on Linux orchestrator
expected: `ODIN_MAX_EVENTS=2 bash TA-ODIN/bin/odin.sh 2>&1 | grep -c type=truncated` returns at least 1 (pre-set env var overrides the 50000 default)
result: pass

### 3. HARD-02 tunable guardrails work on Windows orchestrator via _common.ps1
expected: `$env:ODIN_MAX_EVENTS='3'; ODIN_TEST_FIXTURE=tools/tests/windows-fixtures/hostA pwsh TA-ODIN/bin/odin.ps1 2>&1 | grep -c type=truncated` returns at least 1
result: pass

### 4. HARD-05 shellcheck clean at default severity
expected: `shellcheck TA-ODIN/bin/odin.sh TA-ODIN/bin/modules/*.sh` exits 0 with zero findings
result: pass

### 5. HARD-06 PSScriptAnalyzer clean at Error+Warning severity
expected: `pwsh -NoProfile -Command "(Invoke-ScriptAnalyzer -Path TA-ODIN/bin -Recurse -Severity Error,Warning | Measure-Object).Count"` returns 0
result: pass

### 6. HARD-07 two-app-split guard works
expected: `bash tools/tests/check-two-app-split.sh` exits 0 and prints `[HARD-07 PASS] Two-app split is clean`
result: pass

### 7. HARD-08 injection regression test passes
expected: `bash tools/tests/injection-fixtures/run.sh` exits 0 and prints `[HARD-08] 10 passed, 0 failed`
result: pass

### 8. HARD-03/04 saved search stanzas present and definition-only
expected: `grep -c '^\[alert_odin_' ODIN_app_for_splunk/default/savedsearches.conf` returns 2, and both stanzas contain `disabled = 1` with empty `cron_schedule =`
result: pass

### 9. CI workflow exists with SHA-pinned actions
expected: `.github/workflows/ci.yml` exists, contains 5 quality-gate steps (shellcheck, PSA, two-app split, version sync, injection regression), and `uses:` clauses pin by commit SHA (40-hex-char pattern) not by `@vN` tag
result: pass

### 10. Phase 1 parity preserved end-to-end
expected: `bash tools/tests/windows-parity-harness.sh` exits 0 with all 6 Nyquist dimensions PASS (Phase 2 introduced zero regressions to Phase 1 Windows code)
result: pass

## Summary

total: 10
passed: 10
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

<!-- None -->
