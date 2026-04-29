---
phase: 08-host-info-windows
reviewed: 2026-04-29T12:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - TA-ODIN/bin/modules/_common.ps1
  - TA-ODIN/bin/odin.ps1
  - tools/tests/check-host-info.ps1
findings:
  critical: 1
  warning: 3
  info: 2
  total: 6
status: issues_found
---

# Phase 8: Code Review Report

**Reviewed:** 2026-04-29T12:00:00Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Three files reviewed: the extended `_common.ps1` shared library (536 lines, +358 from Phase 8, adding 8 helper functions for host metadata detection), the `odin.ps1` orchestrator (211 lines, +~10 from Phase 8 inserting `Invoke-OdinEmitHostInfo`), and the new regression test `check-host-info.ps1` (99 lines).

The implementation is well-structured and honors D-03, D-04, D-06, and D-07 decisions. No `Get-WmiObject` usage in new code. All `Invoke-RestMethod` calls carry `-UseBasicParsing` and `-TimeoutSec $script:ODIN_IMDS_TIMEOUT`. The sentinel discipline (`"unknown"` / `"none"`) is consistent across helpers. `Get-OdinVirtualization` correctly returns the full D-04 seven-value enum. The orchestrator insertion point is correct (event #2, after `odin_start`, before module loop). No eval/Invoke-Expression usage found.

One critical bug was found: the GCP zone-to-region regex fails when `Invoke-RestMethod` returns a trailing `\r` in the zone string (text/plain HTTP response), causing the zone letter to remain in `cloud_region` (e.g., `us-central1-f` instead of `us-central1`). Three warnings were found: the IMDS timing claim in the comment repeats the Phase 7 WR-01 error (`3s` when AWS two-call budget makes worst case `4s`), the test executor is hardcoded to `powershell.exe` which does not exist on Linux/macOS CI runners, and the test Check 2 lacks the same cascade-prevention guard that was correctly applied to Checks 4 and 5 (a partial repeat of Phase 7 WR-03).

---

## Critical Issues

### CR-01: GCP zone-to-region regex fails when HTTP response contains trailing `\r`

**File:** `TA-ODIN/bin/modules/_common.ps1:436-437`

**Issue:** `Get-OdinGcpImds` extracts the region from the GCP metadata zone string by splitting on `/` and applying `-replace '-[a-z]$', ''`. However, `Invoke-RestMethod` against a `text/plain` GCP metadata endpoint on Windows can return the zone string with a trailing `\r` (carriage return from HTTP CRLF line endings). When `$zone` is `"projects/123/zones/us-central1-f\r"`:

1. The split produces `$lastSegment = "us-central1-f\r"`.
2. The regex `-replace '-[a-z]$', ''` attempts to match the single-letter zone suffix immediately before end-of-string. In PowerShell's default (non-multiline) mode, `$` anchors before the end of the string, which is after `\r`. The character before `\r` is `f` (a letter), but the character before that is `-`, so the pattern `-[a-z]$` would need to match `-f` at the end. However, because `\r` is after `f`, `$` does not match right after `f` — the match fails.
3. The `$region` is left as `"us-central1-f\r"` (zone suffix not stripped).
4. `Format-OdinValue` correctly strips the `\r`, but the zone letter `f` remains.
5. The emitted field is `cloud_region=us-central1-f` instead of the correct `cloud_region=us-central1`.

This is a data correctness defect on any real GCP instance where the metadata server returns CRLF-terminated text. AWS (`$region` is a plain region string, no suffix stripping needed) and Azure (plain text, no suffix stripping needed) are unaffected because their region values do not go through a suffix-stripping regex step.

**Fix:** `.Trim()` the zone string (and other IMDS text responses defensively) before processing, or apply the regex to the trimmed value:

```powershell
# In Get-OdinGcpImds, replace the current extraction block:
$zone = ($zone -replace "`r", '' -replace "`n", ' ').Trim()
if (-not $zone) { return $null }
$lastSegment = ($zone -split '/')[-1]
$region = $lastSegment -replace '-[a-z]$', ''
if (-not $region) { return $null }
return "gcp|$region"
```

Alternatively, apply `.Trim()` only to `$lastSegment` before the regex:

```powershell
$lastSegment = (($zone -split '/')[-1]).Trim()
$region = $lastSegment -replace '-[a-z]$', ''
```

For defensive consistency, also trim AWS and Azure responses (they currently pass through Format-OdinValue which strips `\r`, but trimming before the pipe-concatenation is cleaner):

```powershell
# Get-OdinAwsImds
$region = ($region -replace "`r", '').Trim()

# Get-OdinAzureImds
$region = ($region -replace "`r", '').Trim()
```

---

## Warnings

### WR-01: IMDS worst-case timing comment repeats Phase 7 WR-01 error — claims 3s when AWS two-call budget makes worst case 4s

**File:** `TA-ODIN/bin/modules/_common.ps1:46`

**Issue:** Line 46 reads:
```
# D-05 (Phase 8 mirror of Phase 7 D-02): seconds per cloud probe (1s × 3 sequential = 3s worst case)
```

This is the same incorrect claim that Phase 7's WR-01 found and fixed in `_common.sh`. `Get-OdinAwsImds` makes **two** sequential `Invoke-RestMethod` calls: one PUT to fetch the IMDSv2 token (line 407-410) and one GET to fetch the region (lines 414-417). Each call uses `$script:ODIN_IMDS_TIMEOUT` (default 1s). On a host with partial link-local routing where the token endpoint responds slowly, AWS alone can consume 2s. The actual worst-case IMDS budget is:

- AWS token fetch: 1s max
- AWS region fetch: 1s max (if token call times out, this call is never made; but if the endpoint partially responds, both calls can time out)
- GCP: 1s max
- Azure: 1s max

**Actual worst case: 4s**, not 3s. Phase 7's CONTEXT.md (D-05 section, line 49) correctly acknowledges "3s (or 4s for AWS where IMDSv2 makes 2 sequential calls — same edge case as Phase 7 WR-01)" but the implementation comment ignores this.

**Fix:** Update line 46 to match the accurate timing statement that was applied to `_common.sh` by Phase 7's fix:

```powershell
# D-05 (Phase 8 mirror of Phase 7 D-02): seconds per cloud probe (1s × 3 sequential).
# AWS IMDSv2 requires 2 sequential calls (token PUT + region GET).
# Worst-case total on a non-cloud host: 4s (AWS: 2×1s + GCP: 1s + Azure: 1s).
# Non-cloud hosts typically resolve in 3s — the token endpoint fails immediately,
# so the second AWS call is never made.
```

---

### WR-02: Test executor hardcoded to `powershell.exe` — fails on Linux/macOS CI with command-not-found

**File:** `tools/tests/check-host-info.ps1:24`

**Issue:** The script's shebang is `#!/usr/bin/env pwsh` (cross-platform PowerShell 7+), but the orchestrator invocation is:

```powershell
$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $orchestratorPath 2>&1 | Out-String
```

`powershell.exe` is the Windows PowerShell 5.1 binary that does not exist on Linux or macOS. On a Linux or macOS CI runner that has `pwsh` (PowerShell Core 7+) installed, this line throws a command-not-found error, `$out` is empty, and all 5 checks fail — producing misleading FAIL output instead of a platform SKIP.

The review scope notes that the script "exits 1 on macOS as designed" — but a hard command-not-found error is not a clean design. The correct design for a Windows-only test is to emit a clear platform skip, not cascade 5 FAILs from a missing binary.

**Fix:** Add a platform guard at the top of the test script, and use `pwsh` (or detect which binary is available) for the executor call:

```powershell
# Platform guard — this test requires Windows (powershell.exe or pwsh on Windows)
if ($IsLinux -or $IsMacOS) {
    Write-Host "[HOST-02 SKIP] Windows-only test — skipping on $([System.Runtime.InteropServices.RuntimeInformation]::OSDescription)"
    exit 0
}

# Use pwsh if available (PS7+), fall back to powershell.exe (PS5.1 on Windows)
$psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell.exe' }
$out = & $psExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $orchestratorPath 2>&1 | Out-String
```

---

### WR-03: Test Check 2 lacks cascade-prevention guard — emits misleading 13-field FAIL when event is absent (partial repeat of Phase 7 WR-03)

**File:** `tools/tests/check-host-info.ps1:42-53`

**Issue:** Phase 7 WR-03 was fixed by wrapping Checks 4 and 5 in `if (-not $hostInfoLine)` guards. Check 2 (all 13 fields present) was not given the same treatment. When `$hostInfoLine` is empty (because Check 1 already determined no `type=odin_host_info` event exists), the `foreach` loop at lines 43-47 evaluates `$hostInfoLine -notmatch "$field="` — where `$hostInfoLine` is empty — which is true for all 13 fields. The result is:

```
[HOST-02 FAIL] missing fields: os_distro, os_version, os_pretty, os_kernel, os_arch, cpu_cores, mem_total_mb, uptime_seconds, fqdn, ip_primary, virtualization, cloud_provider, cloud_region
```

This is a misleading cascade failure. The real problem is that the event doesn't exist (Check 1), not that 13 individual fields are missing. CI output for a single root cause (broken `Invoke-OdinEmitHostInfo` call) shows 1 FAIL (Check 1) + 1 misleading FAIL (Check 2) instead of 1 FAIL + 1 SKIP.

Note: Checks 4 and 5 already have the correct guard (`if (-not $hostInfoLine)`). Check 2 was missed.

**Fix:** Add the same guard to Check 2:

```powershell
# --- Check 2: all 13 named fields present ---
$hostInfoLine = ($out -split "`n" | Where-Object { $_ -match 'type=odin_host_info' } | Select-Object -First 1)
if (-not $hostInfoLine) {
    Write-Host "[HOST-02 SKIP] field presence check skipped — no event to inspect (see Check 1)"
} else {
    $missingFields = @()
    foreach ($field in $expectedFields) {
        if ($hostInfoLine -notmatch "$field=") {
            $missingFields += $field
        }
    }
    if ($missingFields.Count -eq 0) {
        Write-Host "[HOST-02 PASS] all 13 named fields present in event"
    } else {
        Write-Host "[HOST-02 FAIL] missing fields: $($missingFields -join ', ')"
        $fail = 1
    }
}
```

---

## Info

### IN-01: `[System.Net.Dns]::GetHostByName` is obsolete — `GetHostEntry` already used in `Initialize-OdinContext`

**File:** `TA-ODIN/bin/modules/_common.ps1:320`

**Issue:** `Get-OdinNetwork` uses `[System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName` to resolve the FQDN. `GetHostByName` has been marked `[Obsolete]` in .NET since .NET 2.0. The recommended replacement is `GetHostEntry`. Interestingly, `Initialize-OdinContext` (line 138, Phase 1 code) already uses `GetHostEntry('')` correctly. The two functions are inconsistent.

On all currently supported .NET versions used by PowerShell 5.1 through 7.x, `GetHostByName` still works and produces the same result as `GetHostEntry`. This is a quality inconsistency, not a functional defect.

**Fix:** Replace with `GetHostEntry` for consistency with the existing pattern:

```powershell
$hostName = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName
```

---

### IN-02: `Invoke-OdinEmitHostInfo` comment says "Counts toward `$script:ODIN_MAX_EVENTS` (1 event budget)" — misleading since `Initialize-OdinModuleState` resets the counter before the first module

**File:** `TA-ODIN/bin/modules/_common.ps1:486`

**Issue:** The docstring comment reads:
```
# Counts toward $script:ODIN_MAX_EVENTS via Invoke-OdinEmit (1 event budget).
```

This is technically true (the counter is incremented to 1), but the comment implies the host_info event consumes one slot from the module event budget. It does not. `Invoke-OdinEmitHostInfo` is called at `odin.ps1:103`, before the module loop. `Initialize-OdinModuleState` is called at `odin.ps1:128` for every module, which resets `$script:ODIN_EVENT_COUNT` to 0. The host_info event increment is therefore wiped out before any module's MAX_EVENTS guard ever evaluates it. The host_info event does not cost any module its events.

The comment is misleading to future maintainers who might believe the MAX_EVENTS cap applies cross-module or that the host_info event competes with module events.

**Fix:** Update the comment to accurately describe the behavior:

```powershell
# Emits exactly 1 event via Invoke-OdinEmit. Does NOT consume from any module's
# MAX_EVENTS budget — Initialize-OdinModuleState resets $script:ODIN_EVENT_COUNT
# to 0 before the first module runs (odin.ps1:128).
```

---

_Reviewed: 2026-04-29T12:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
