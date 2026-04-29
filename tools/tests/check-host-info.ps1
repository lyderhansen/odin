#!/usr/bin/env pwsh
# tools/tests/check-host-info.ps1 — HOST-02
#
# Verifies Phase 8 / HOST-02 success criteria:
#   1. Exactly ONE type=odin_host_info event per scan (Windows orchestrator)
#   2. All 13 named fields present in that event
#   3. Event positioned as #2 (between odin_start and module events)
#   4. Total IMDS budget on non-cloud hosts is ≤3s (D-05: 1s × 3 sequential)
#      NOTE: this script does NOT measure timing — that check lives in the
#      plan-level <verification> block. This file verifies field correctness
#      (event count, all 13 fields present, positioning, virt enum, cloud
#      sentinel). Adding a runtime measurement here is a future enhancement.
#
# Exit 0 when all checks pass, non-zero otherwise.

$ErrorActionPreference = 'Continue'  # Don't halt on individual check failures

# Platform guard — this test requires Windows (Windows-only CIM, odin.ps1 orchestrator)
# $IsLinux / $IsMacOS are PS7+ automatic variables. On PS5.1 (Windows-only) they are
# undefined ($null), so ($IsLinux -or $IsMacOS) evaluates to $false — correct behaviour.
if ($IsLinux -or $IsMacOS) {
    Write-Host "[HOST-02 SKIP] Windows-only test — skipping on $([System.Runtime.InteropServices.RuntimeInformation]::OSDescription)"
    exit 0
}

# Resolve repo root from script location
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$fail = 0

# --- Run the orchestrator and capture output ---
$orchestratorPath = Join-Path $RepoRoot 'TA-ODIN' 'bin' 'odin.ps1'
# Use pwsh if available (PS Core 7+), fall back to powershell.exe (PS5.1 on Windows).
# This avoids command-not-found on Linux/macOS CI that has pwsh but not powershell.exe.
$psExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell.exe' }
$out = & $psExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $orchestratorPath 2>&1 | Out-String

# --- Check 1: exactly ONE type=odin_host_info event ---
$hostInfoCount = ([regex]::Matches($out, 'type=odin_host_info')).Count
if ($hostInfoCount -eq 1) {
    Write-Host "[HOST-02 PASS] exactly 1 type=odin_host_info event emitted"
} else {
    Write-Host "[HOST-02 FAIL] expected 1 type=odin_host_info event, got $hostInfoCount"
    $fail = 1
}

# --- Check 2: all 13 named fields present ---
$expectedFields = @('os_distro', 'os_version', 'os_pretty', 'os_kernel', 'os_arch',
                    'cpu_cores', 'mem_total_mb', 'uptime_seconds',
                    'fqdn', 'ip_primary', 'virtualization',
                    'cloud_provider', 'cloud_region')
$hostInfoLine = ($out -split "`n" | Where-Object { $_ -match 'type=odin_host_info' } | Select-Object -First 1)
# SKIP guard (WR-03): when no event was emitted, Check 1 already reported FAIL.
# Iterating 13 fields against an empty string produces 13 misleading FAILs.
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

# --- Check 3: host_info is event #2 (right after odin_start) ---
$timestampLines = $out -split "`n" | Where-Object { $_ -match '^timestamp=' }
$event2 = if ($timestampLines.Count -ge 2) { $timestampLines[1] } else { '' }
if ($event2 -match 'type=odin_host_info') {
    Write-Host "[HOST-02 PASS] host_info is event #2 (between odin_start and module events)"
} else {
    Write-Host "[HOST-02 FAIL] event #2 is not type=odin_host_info — positioning broken"
    Write-Host "             event #2 was: $event2"
    $fail = 1
}

# --- Check 4: virtualization value is in D-04 enum (SKIP if event missing per WR-03) ---
if (-not $hostInfoLine) {
    Write-Host "[HOST-02 SKIP] virtualization enum check skipped — no event to inspect"
} else {
    $virtMatch = [regex]::Match($hostInfoLine, 'virtualization=(\S+)')
    $virtVal = if ($virtMatch.Success) { $virtMatch.Groups[1].Value } else { '' }
    $validVirt = @('baremetal', 'kvm', 'vmware', 'hyperv', 'xen', 'container', 'unknown')
    if ($virtVal -in $validVirt) {
        Write-Host "[HOST-02 PASS] virtualization=$virtVal is in D-04 enum"
    } else {
        Write-Host "[HOST-02 FAIL] virtualization=$virtVal is NOT in D-04 enum (baremetal|kvm|vmware|hyperv|xen|container|unknown)"
        $fail = 1
    }
}

# --- Check 5: cloud_provider sentinel discipline (SKIP if event missing per WR-03) ---
if (-not $hostInfoLine) {
    Write-Host "[HOST-02 SKIP] cloud_provider sentinel check skipped — no event to inspect"
} else {
    $cloudMatch = [regex]::Match($hostInfoLine, 'cloud_provider=(\S+)')
    $cloudVal = if ($cloudMatch.Success) { $cloudMatch.Groups[1].Value } else { '' }
    $validCloud = @('none', 'aws', 'gcp', 'azure', 'unknown')
    if ($cloudVal -in $validCloud) {
        Write-Host "[HOST-02 PASS] cloud_provider=$cloudVal honors D-03 sentinel discipline"
    } else {
        Write-Host "[HOST-02 FAIL] cloud_provider=$cloudVal is NOT a valid value (none|aws|gcp|azure|unknown)"
        $fail = 1
    }
}

if ($fail -eq 0) {
    Write-Host "[HOST-02 PASS] All checks passed"
}
exit $fail
