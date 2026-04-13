---
status: complete
phase: 01-windows-parity
source: [01-01-SUMMARY.md, 01-02-SUMMARY.md, 01-03-SUMMARY.md]
started: 2026-04-13T15:30:00Z
updated: 2026-04-13T20:05:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Full harness green
expected: `bash tools/tests/windows-parity-harness.sh` exits 0 with all 6 Nyquist dimensions PASS
result: pass

### 2. hostA end-to-end — 6 modules, 0 failures
expected: Under `ODIN_TEST_FIXTURE=tools/tests/windows-fixtures/hostA`, orchestrator emits `type=odin_complete modules_total=6 modules_success=6 modules_failed=0` and one event per module type (service, port, package, scheduled_task, process, mount)
result: pass

### 3. WIN-04 — packages.ps1 contains zero Win32_Product references
expected: `grep -c 'Win32_Product' TA-ODIN/bin/modules/packages.ps1` returns exactly 0 (load-bearing MSI self-repair hazard gate)
result: pass

### 4. WIN-12 fail-soft — hostA-broken induces one module failure, orchestrator exits 0
expected: Under `ODIN_TEST_FIXTURE=tools/tests/windows-fixtures/hostA-broken`, orchestrator emits `type=odin_error module=services exit_code=1` AND `type=odin_complete modules_total=6 modules_success=5 modules_failed=1`, and exits 0
result: pass

### 5. D6 standalone — each module runs on its own under fixture
expected: `ODIN_TEST_FIXTURE=tools/tests/windows-fixtures/hostA pwsh -NoProfile -File TA-ODIN/bin/modules/services.ps1` runs without the orchestrator and emits at least one `type=service` line with Linux-parity prelude
result: pass

### 6. WIN-08 field-name parity vs Linux
expected: Dim 5 per-type diff (`bash tools/tests/windows-parity-harness.sh --dim 5`) shows `[DIM5-PASS]` for service, port, package, process, mount — and `[DIM5-SKIP]` for scheduled_task with documented rationale (the one intentional divergence per CONTEXT D6)
result: pass

## Summary

total: 6
passed: 6
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

<!-- None yet -->
