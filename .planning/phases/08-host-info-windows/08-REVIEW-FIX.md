---
phase: 08-host-info-windows
fixed_at: 2026-04-29T14:30:00+02:00
review_path: .planning/phases/08-host-info-windows/08-REVIEW.md
fix_scope: critical_warning
findings_in_scope: 4
fixed: 4
skipped: 0
iteration: 1
status: all_fixed
---

# Phase 8: Code Review Fix Report

**Fixed at:** 2026-04-29T14:30:00+02:00
**Source review:** .planning/phases/08-host-info-windows/08-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 4 (CR-01, WR-01, WR-02, WR-03)
- Fixed: 4
- Skipped: 0

## Fixed Issues

### CR-01: GCP zone-to-region regex fails when HTTP response contains trailing `\r`

**Files modified:** `TA-ODIN/bin/modules/_common.ps1`
**Commit:** `fda47ac`
**Applied fix:** In `Get-OdinGcpImds`, added `$zone = $zone.ToString().Trim()` after the null guard and before the `/`-split. This strips `\r\n` that `Invoke-RestMethod` may include in `text/plain` HTTP responses on Windows, allowing the `-replace '-[a-z]$', ''` zone-suffix regex to match correctly. Added a second null guard after Trim() for defensive completeness.

Manual verification confirmed: input `'projects/123456/zones/us-central1-f' + [char]13 + [char]10` now produces `us-central1` (not `us-central1-f`).

---

### WR-01: IMDS worst-case timing comment repeats Phase 7 WR-01 error (3s vs 4s)

**Files modified:** `TA-ODIN/bin/modules/_common.ps1`
**Commit:** `1375160`
**Applied fix:** Updated two comments in `_common.ps1`:
1. Line 46 (`ODIN_IMDS_TIMEOUT` declaration): expanded the single-line claim into a 5-line block explaining that AWS IMDSv2 makes 2 sequential calls (token PUT + region GET), making the true worst case 4s (AWS: 2×1s + GCP: 1s + Azure: 1s). Added `(3-4s worst case)` tag.
2. Cloud IMDS section header (former line 397): appended `3-4s worst case` to the section banner and added a clarifying line about AWS making 2 calls vs GCP/Azure making 1 each.

Verification: `grep -n '3-4s worst case' _common.ps1` returns 2 matches.

---

### WR-02: Test executor hardcoded to `powershell.exe` — fails on Linux/macOS CI

**Files modified:** `tools/tests/check-host-info.ps1`
**Commit:** `437e0f2`
**Applied fix:** Two changes to `check-host-info.ps1`:
1. Added a platform guard block immediately after `$ErrorActionPreference`: checks `$IsLinux -or $IsMacOS` (PS7+ automatic variables; undefined/null on PS5.1 Windows = evaluates false, correct). On non-Windows, emits `[HOST-02 SKIP]` with OS description and exits 0.
2. Replaced hardcoded `powershell.exe` with portable binary detection: `$psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell.exe' }`. This prefers pwsh (PS Core 7+, works on Linux/macOS/Windows) and falls back to powershell.exe (PS5.1 Windows-only).

Verification on macOS: `pwsh tools/tests/check-host-info.ps1` now outputs `[HOST-02 SKIP] Windows-only test — skipping on Darwin...` and exits 0 (previously produced command-not-found cascade with 5 FAILs).

---

### WR-03: Check 2 missing SKIP guard — cascade-prevention not applied (partial repeat of Phase 7 WR-03)

**Files modified:** `tools/tests/check-host-info.ps1`
**Commit:** `4d0c3ce`
**Applied fix:** Wrapped Check 2's field-presence `foreach` loop in the same `if (-not $hostInfoLine) { ... } else { ... }` guard that was already correctly applied to Checks 4 and 5. When `$hostInfoLine` is empty (no `type=odin_host_info` event in output), Check 2 now emits `[HOST-02 SKIP] field presence check skipped — no event to inspect (see Check 1)` rather than cascading 13 misleading `missing fields` FAILs.

Verification: `grep -c 'if (-not \$hostInfoLine)' tools/tests/check-host-info.ps1` returns 3 (Check 2, Check 4, Check 5).

---

## Regression Results

All regressions run after applying all 4 fixes:

| Test | Command | Result |
|------|---------|--------|
| `_common.ps1` dot-source (syntax) | `pwsh -NoProfile -Command "& { . ./TA-ODIN/bin/modules/_common.ps1 }"` | PASS — no errors |
| `odin.ps1` host_info event count | `pwsh -File ./TA-ODIN/bin/odin.ps1 \| grep -c 'type=odin_host_info'` | PASS — 1 event |
| `check-host-info.ps1` (macOS) | `pwsh tools/tests/check-host-info.ps1` | PASS — clean SKIP (exit 0) |
| `check-host-info.sh` (Linux Phase 7) | `bash tools/tests/check-host-info.sh` | PASS — 5 PASS, exit 0 |
| `check-version-sync.sh` (HARD-01) | `bash tools/tests/check-version-sync.sh` | PASS — v1.0.1 (4 sites + sources) |
| `check-two-app-split.sh` (HARD-07) | `bash tools/tests/check-two-app-split.sh` | PASS — two-app split clean |
| `windows-parity-harness.sh` | `bash tools/tests/windows-parity-harness.sh` | PASS — all 6 dimensions passed |

---

_Fixed: 2026-04-29T14:30:00+02:00_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
