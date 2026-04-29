# Phase 8: Host Info — Windows - Pattern Map

**Mapped:** 2026-04-29
**Files analyzed:** 3 (2 modified, 1 new)
**Analogs found:** 3 / 3 — all in-repo, exact mirrors of Phase 7 counterparts

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `TA-ODIN/bin/modules/_common.ps1` (MODIFIED) | shared library / utility | one-shot probe → key=value emit | `TA-ODIN/bin/modules/_common.sh` (Phase 7 post-state, lines 88–344) + existing `_common.ps1` (lines 1–178) function style | exact — additive extension mirroring same-file Linux pattern |
| `TA-ODIN/bin/odin.ps1` (MODIFIED) | orchestrator | sequential lifecycle emit | `TA-ODIN/bin/odin.sh` lines 88–115 (source + emit_host_info call site) | exact — one-line insertion at mirror position |
| `tools/tests/check-host-info.ps1` (NEW) | test / regression guard | exec → grep → assert | `tools/tests/check-host-info.sh` (100 lines, 5 checks, 2 SKIP guards) | exact — PowerShell port of Linux sibling |

**Phase 9 mirror reference (NOT modified by Phase 8, but constrains design):**
| Mirror File | Role | Notes |
|-------------|------|-------|
| `tools/tests/windows-parity-harness.sh` | integration harness | Dimension 4 + 5 run the full orchestrator output. Phase 8 must NOT regress Dim 4 (start + complete + 6 module types) or Dim 5 (field-name parity). The `type=odin_host_info` event will appear in Dim 4 output; harness only counts the 6 module types so no assertion breaks. |

---

## Pattern Assignments

### `TA-ODIN/bin/modules/_common.ps1` (extend with 8 new helper functions)

**Analog:** `TA-ODIN/bin/modules/_common.ps1` itself (additive extension — DO NOT touch lines 1–178) plus `TA-ODIN/bin/modules/_common.sh` (Phase 7 post-state) as the function-by-function mirror source.

---

#### Pattern 1 — IMDS timeout env-var default (mirror of _common.sh line 49)

**Source analog:** `TA-ODIN/bin/modules/_common.sh` line 49:
```bash
ODIN_IMDS_TIMEOUT="${ODIN_IMDS_TIMEOUT:-1}"   # seconds per cloud probe (D-02: AWS→GCP→Azure)
```

**Apply to Phase 8:** Add the PowerShell mirror immediately after the existing `$script:ODIN_MODULE_TIMEOUT` block (after line 44 in `_common.ps1`), following the established `if (-not $env:X) { $env:X = 'default' }` idiom already used in `_common.ps1:40–44`:

```powershell
if (-not $env:ODIN_IMDS_TIMEOUT) { $env:ODIN_IMDS_TIMEOUT = '1' }
$script:ODIN_IMDS_TIMEOUT = [int]$env:ODIN_IMDS_TIMEOUT
```

**Critical:** This MUST be placed before the new helper functions because `Invoke-OdinCloudImds` reads `$script:ODIN_IMDS_TIMEOUT`. Matches `_common.sh` convention of env-var-aware default at file load, not redeclared inside the helper.

---

#### Pattern 2 — Function header comment block style (lines 54–61, 63–68, 93–99, 119–127 of `_common.ps1`)

**Source analog:** `TA-ODIN/bin/modules/_common.ps1` lines 54–61 (`Get-OdinTimestamp`) and lines 93–99 (`Invoke-OdinEmit`):

```powershell
# ---------------------------------------------------------------------------
# Get-OdinTimestamp - ISO 8601 UTC (yyyy-MM-ddTHH:mm:ssZ)
# ---------------------------------------------------------------------------
# Mirrors Linux get_timestamp() in TA-ODIN/bin/odin.sh. Uses the Get-Date
# cmdlet (NOT [DateTime]::UtcNow) so the emit path relies only on cmdlets
# that are allow-listed under WIN-09 Dimension 2.
function Get-OdinTimestamp {
    return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}
```

**Apply to Phase 8 — every new helper follows this exact template:**

```powershell
# ---------------------------------------------------------------------------
# Get-OdinOsDistro - returns pipe-separated "distro|version|pretty"
# ---------------------------------------------------------------------------
# Phase 8 mirror of detect_os_distro() in TA-ODIN/bin/modules/_common.sh.
# Detection: Get-CimInstance Win32_OperatingSystem (D-06: CIM only, never WMI).
# Returns "windows" as distro (hardcoded), Caption for os_pretty.
# Falls back to "unknown" sentinels per D-03 on any CIM failure.
function Get-OdinOsDistro {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        # ... detection logic ...
        return "$distro|$version|$pretty"
    } catch {
        return 'unknown|unknown|unknown'
    }
}
```

**Rule:** Separator line (`# ---...---`), 1-line purpose, blank line, mirror attribution (`# Phase 8 mirror of ...`), detection note citing D-06, sentinel note citing D-03, then `function Verb-OdinNoun {`.

---

#### Pattern 3 — Get-CimInstance usage with try/catch + ErrorAction Stop (D-06 + D-07)

**Source analog:** `TA-ODIN/bin/modules/processes.ps1` lines 16–33 (batch CIM query with inner catch):

```powershell
try {
    # Batch CIM query - single Win32_Process call; avoids N+1 subprocess
    # spawning. Mirrors processes.sh's single-ps-call pattern.
    $cimMap = @{}
    try {
        $cim = Get-CimInstance -ClassName Win32_Process -ErrorAction Stop
        foreach ($c in $cim) {
            # ... process $c ...
        }
    } catch {
        # CIM unavailable - fall back to Get-Process only (no ppid/command/user).
        $null = $_
    }
    # ... rest of function ...
} catch {
    throw
}
```

**Apply to Phase 8 — inner try/catch pattern for CIM queries:**

```powershell
function Get-OdinHardware {
    $cores = 'unknown'
    $memMb = 'unknown'
    try {
        $procs = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        $cores = ($procs | Measure-Object -Property NumberOfCores -Sum).Sum
        if ($null -eq $cores) { $cores = 'unknown' }
    } catch {
        $null = $_   # CIM unavailable → sentinel preserved
    }
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $memMb = [int]($os.TotalVisibleMemorySize / 1024)
    } catch {
        $null = $_
    }
    return "$cores|$memMb"
}
```

**Rules (D-06 + D-07):**
1. Always `Get-CimInstance`, never `Get-WmiObject` — NEVER touch `services.ps1`'s WMI code
2. Always `-ErrorAction Stop` inside `try` so the `catch` fires on failure
3. Swallow exception with `$null = $_` (CLM-safe, no string interpolation of `$_`)
4. Return sentinel `'unknown'` (or `'unknown|unknown'` for pipe-separated) — NEVER `-1` or `$null`

---

#### Pattern 4 — Format-OdinValue for fields containing whitespace

**Source analog:** `TA-ODIN/bin/modules/_common.ps1` lines 69–90 (`Format-OdinValue`) + `processes.ps1` lines 40, 53 (usage):

```powershell
# In processes.ps1 line 40 / 53:
$name    = Format-OdinValue $p.Name
$command = Format-OdinValue $cimProc.CommandLine
```

**Apply to Phase 8:** `os_pretty` ("Microsoft Windows 11 Pro") MUST be wrapped via `Format-OdinValue`. All other host_info fields are bare values (no spaces expected in region names, arch strings, etc.) — use them directly. In `Invoke-OdinEmitHostInfo`, the emit line should be:

```powershell
$prettyFmt  = Format-OdinValue $osPretty
$fqdnFmt    = Format-OdinValue $fqdn
$regionFmt  = Format-OdinValue $cloudRegion
Invoke-OdinEmit "type=odin_host_info os_distro=$osDistro os_version=$osVersion os_pretty=$prettyFmt os_kernel=$osKernel os_arch=$osArch cpu_cores=$cpuCores mem_total_mb=$memMb uptime_seconds=$uptimeSec fqdn=$fqdnFmt ip_primary=$ipPrimary virtualization=$virt cloud_provider=$cloudProvider cloud_region=$regionFmt"
```

This mirrors `_common.sh`'s `_safe_val_host_info()` for space-quoting, but uses the already-existing `Format-OdinValue` instead of defining a private helper.

---

#### Pattern 5 — Invoke-OdinEmit as the SOLE output channel (D-05 guardrail)

**Source analog:** `TA-ODIN/bin/modules/_common.ps1` lines 100–117 (`Invoke-OdinEmit`) + `processes.ps1` line 122 (usage):

```powershell
# processes.ps1 line 122:
Invoke-OdinEmit $line

# _common.ps1 lines 114–116 — what Invoke-OdinEmit does:
$script:ODIN_EVENT_COUNT = $script:ODIN_EVENT_COUNT + 1
$ts = Get-OdinTimestamp
Write-Output "timestamp=$ts hostname=$($env:ODIN_HOSTNAME) os=$($env:ODIN_OS) run_id=$($env:ODIN_RUN_ID) odin_version=$($env:ODIN_VERSION) $Line"
```

**Apply to Phase 8:** `Invoke-OdinEmitHostInfo` MUST call `Invoke-OdinEmit` (never `Write-Output` directly). Reasons:
1. Inherits timestamp/hostname/os/run_id/odin_version envelope automatically
2. Counts toward `$script:ODIN_EVENT_COUNT` and `$script:ODIN_EVENTS_TRUNCATED` guardrail
3. CLM-safe (D5-revised: Write-Output only, no raw console writers)

```powershell
function Invoke-OdinEmitHostInfo {
    # ... call Get-Odin* helpers, split pipe-separated returns ...
    Invoke-OdinEmit "type=odin_host_info os_distro=... [all 13 fields] ..."
}
```

---

#### Pattern 6 — Pipe-separated return convention (mirror of _common.sh helper returns)

**Source analog:** `TA-ODIN/bin/modules/_common.sh` — all multi-field helpers return `"a|b"` strings:
```bash
# _common.sh lines 102, 114, 136:
echo "${distro}|${version}|${pretty}"
echo "${kernel}|${arch}"
echo "${cores}|${mem_mb}"
```

**Apply to Phase 8 PowerShell mirror:**

```powershell
# Get-OdinOsDistro returns 3-part pipe-separated:
$pair = Get-OdinOsDistro    # "windows|10.0.26100|Microsoft Windows 11 Pro"
$parts = $pair -split '\|', 3
$osDistro, $osVersion, $osPretty = $parts[0], $parts[1], $parts[2]

# Get-OdinOsKernelArch returns 2-part:
$pair = Get-OdinOsKernelArch  # "26100.4349|amd64"
$parts = $pair -split '\|', 2
$osKernel, $osArch = $parts[0], $parts[1]
```

Use `-split '\|', N` with limit argument to avoid splitting on pipe characters that might appear in pretty names. All other multi-field returns (hardware, network, cloud) use the same pattern with appropriate limits.

---

#### Pattern 7 — IMDS probe with Invoke-RestMethod -TimeoutSec (D-05 mirror)

**Source analog:** `TA-ODIN/bin/modules/_common.sh` lines 232–276 (AWS/GCP/Azure probe functions). The PowerShell equivalent uses `Invoke-RestMethod -TimeoutSec`:

```bash
# Linux analog (_common.sh lines 235–238):
token=$(timeout "$ODIN_IMDS_TIMEOUT" curl -s -X PUT \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
    --connect-timeout "$ODIN_IMDS_TIMEOUT" --max-time "$ODIN_IMDS_TIMEOUT" \
    http://169.254.169.254/latest/api/token 2>/dev/null) || return 1
```

**Apply to Phase 8 — PowerShell AWS IMDSv2 probe (D-05: 1s timeout):**

```powershell
function _Invoke-AwsImds {
    try {
        $headers = @{ 'X-aws-ec2-metadata-token-ttl-seconds' = '60' }
        $token = Invoke-RestMethod -Uri 'http://169.254.169.254/latest/api/token' `
                     -Method PUT -Headers $headers -TimeoutSec $script:ODIN_IMDS_TIMEOUT `
                     -ErrorAction Stop
        if (-not $token) { return $null }
        $region = Invoke-RestMethod -Uri 'http://169.254.169.254/latest/meta-data/placement/region' `
                      -Headers @{ 'X-aws-ec2-metadata-token' = $token } `
                      -TimeoutSec $script:ODIN_IMDS_TIMEOUT -ErrorAction Stop
        if ($region) { return "aws|$region" }
    } catch {
        $null = $_
    }
    return $null
}
```

**GCP and Azure probes follow the same pattern** — `Invoke-RestMethod` with `-TimeoutSec`, appropriate headers, catch swallows to `$null`. `Invoke-OdinCloudImds` calls all three and returns `'none|none'` when all fail (D-03 semantic null).

---

#### Pattern 8 — Virtualization detection cascade (D-04 + D-06)

**Source from 08-CONTEXT.md specifics section:**

```powershell
function Get-OdinVirtualization {
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $sig = "$($cs.Manufacturer) $($cs.Model)"
        switch -Wildcard ($sig) {
            '*Microsoft*Virtual*'     { return 'hyperv' }
            '*VMware*'                { return 'vmware' }
            '*QEMU*'                  { return 'kvm' }
            '*Xen*'                   { return 'xen' }
            '*Amazon EC2*'            { return 'kvm' }
            '*Google*Compute Engine*' { return 'kvm' }
            default {
                # Container detection (Windows containers): OperatingSystemSKU
                try {
                    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                    if ($os.OperatingSystemSKU -in @(0x00000131, 0x00000132)) {
                        return 'container'
                    }
                } catch { $null = $_ }
                return 'baremetal'
            }
        }
    } catch {
        return 'unknown'   # CIM unavailable — D-03 system failure sentinel
    }
}
```

**Enum constraint (D-04):** Return value MUST be one of: `baremetal|kvm|vmware|hyperv|xen|container|unknown`. No other values permitted. This is enforced by `check-host-info.ps1` Check 4.

---

### `TA-ODIN/bin/odin.ps1` (insert ONE call to `Invoke-OdinEmitHostInfo` between odin_start and module loop)

**Analog:** `TA-ODIN/bin/odin.ps1` itself, lines 92–100 — the `$scanStart` + `odin_start` emit cluster. Also `TA-ODIN/bin/odin.sh` lines 88–115 as the mirror reference.

---

#### Pattern — Exact insertion point confirmed (odin.ps1 line 95 → after line 95)

Current state of `odin.ps1` lines 90–103:

```powershell
$scanStart = Get-Date

# --------------------------------------------------------------------------
# Start marker (WIN-01)
# --------------------------------------------------------------------------
Invoke-OdinEmit "type=odin_start message=`"TA-ODIN Windows enumeration started`""

# --------------------------------------------------------------------------
# Module discovery + execution loop (WIN-01, WIN-12)
# --------------------------------------------------------------------------
$modules_total   = 0
$modules_success = 0
$modules_failed  = 0
```

**Apply to Phase 8:** Insert the host_info call as a new block between the `odin_start` emit (line 95) and the module counter init (line 100). The final structure should be:

```powershell
Invoke-OdinEmit "type=odin_start message=`"TA-ODIN Windows enumeration started`""

# --------------------------------------------------------------------------
# Host info event (Phase 8 / HOST-02)
# --------------------------------------------------------------------------
# Emit exactly one type=odin_host_info event with 13 host metadata fields
# (OS, hardware, network, virtualization, cloud detection). Positioned
# deterministically as event #2, between odin_start and any module events.
# Helper lives in TA-ODIN/bin/modules/_common.ps1 (dot-sourced above at line 65).
# Phase 8 mirror of odin.sh:110-115 (emit_host_info call site).
Invoke-OdinEmitHostInfo

# --------------------------------------------------------------------------
# Module discovery + execution loop (WIN-01, WIN-12)
# --------------------------------------------------------------------------
$modules_total   = 0
```

**Why this works without additional sourcing:** `_common.ps1` is already dot-sourced at `odin.ps1:65` (`. $CommonLib`). Because the new `Invoke-OdinEmitHostInfo` function will be defined IN `_common.ps1`, it is already in scope at line 95. No second source call needed. This is the direct PowerShell parallel to Linux Path A (source `_common.sh` once, call helpers directly).

---

#### Pattern — Module exclusion (_common.ps1 already excluded at odin.ps1:114)

**Source:** `TA-ODIN/bin/odin.ps1` lines 113–115:

```powershell
$moduleFiles = Get-ChildItem $ModulesDir |
               Where-Object { -not $_.PSIsContainer -and $_.Extension -eq '.ps1' -and $_.Name -ne '_common.ps1' } |
               Sort-Object Name
```

**Apply to Phase 8:** No change required. The existing `-and $_.Name -ne '_common.ps1'` filter already excludes `_common.ps1` from the module loop. Adding new functions to `_common.ps1` does not affect this guard — confirmed valid.

---

### `tools/tests/check-host-info.ps1` (NEW regression test)

**Analog:** `tools/tests/check-host-info.sh` (100 lines, 5 checks, 2 SKIP guards) — direct PowerShell port.

---

#### Pattern 1 — File header + REPO_ROOT discovery + fail accumulator

**Source analog:** `tools/tests/check-host-info.sh` lines 1–21:

```bash
#!/usr/bin/env bash
# tools/tests/check-host-info.sh — HOST-01
#
# Verifies Phase 7 / HOST-01 success criteria:
#   1. Exactly ONE type=odin_host_info event per scan
#   ...
# Exit 0 when all checks pass, non-zero otherwise.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0
```

**Apply to Phase 8 PowerShell equivalent:**

```powershell
# tools/tests/check-host-info.ps1 — HOST-02
#
# Verifies Phase 8 / HOST-02 success criteria:
#   1. Exactly ONE type=odin_host_info event per scan
#   2. All 13 named fields present in that event
#   3. Event positioned as #2 (between odin_start and module events)
#   4. virtualization value is in D-04 enum (baremetal|kvm|vmware|hyperv|xen|container|unknown)
#   5. cloud_provider sentinel discipline (none|aws|gcp|azure|unknown)
# Exit 0 when all checks pass, non-zero otherwise.

$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fail = 0
```

---

#### Pattern 2 — Run orchestrator and capture output

**Source analog:** `tools/tests/check-host-info.sh` line 23:
```bash
out=$(bash "$REPO_ROOT/TA-ODIN/bin/odin.sh" 2>&1)
```

**Apply to Phase 8:**

```powershell
$orchestratorPath = Join-Path $RepoRoot 'TA-ODIN' 'bin' 'odin.ps1'
$out = pwsh -NoProfile -NonInteractive -File $orchestratorPath 2>&1
$outLines = $out -join "`n"
```

Note: `pwsh` (PowerShell 7+) is the target. Uses same `-NoProfile -NonInteractive` flags as `windows-parity-harness.sh:124`.

---

#### Pattern 3 — Five check structure with PASS/FAIL/SKIP tokens

**Source analog:** `tools/tests/check-host-info.sh` lines 25–95. All 5 checks follow this structure — match it exactly in PowerShell:

```powershell
# --- Check 1: exactly ONE type=odin_host_info event ---
$hostInfoCount = ($outLines | Select-String -Pattern 'type=odin_host_info' -AllMatches).Matches.Count
if ($hostInfoCount -eq 1) {
    Write-Output '[HOST-02 PASS] exactly 1 type=odin_host_info event emitted'
} else {
    Write-Output "[HOST-02 FAIL] expected 1 type=odin_host_info event, got $hostInfoCount"
    $fail = 1
}

# --- Check 2: all 13 named fields present ---
$expectedFields = @('os_distro','os_version','os_pretty','os_kernel','os_arch',
                    'cpu_cores','mem_total_mb','uptime_seconds',
                    'fqdn','ip_primary','virtualization',
                    'cloud_provider','cloud_region')
$hostInfoLine = ($outLines -split "`n" | Where-Object { $_ -match 'type=odin_host_info' } | Select-Object -First 1)
$missingFields = @()
foreach ($field in $expectedFields) {
    if ($hostInfoLine -notmatch "${field}=") { $missingFields += $field }
}
if ($missingFields.Count -eq 0) {
    Write-Output '[HOST-02 PASS] all 13 named fields present in event'
} else {
    Write-Output "[HOST-02 FAIL] missing fields: $($missingFields -join ', ')"
    $fail = 1
}

# --- Check 3: host_info is event #2 (right after odin_start) ---
$timestampLines = $outLines -split "`n" | Where-Object { $_ -match '^timestamp=' }
$event2 = if ($timestampLines.Count -ge 2) { $timestampLines[1] } else { '' }
if ($event2 -match 'type=odin_host_info') {
    Write-Output '[HOST-02 PASS] host_info is event #2 (between odin_start and module events)'
} else {
    Write-Output "[HOST-02 FAIL] event #2 is not type=odin_host_info — positioning broken"
    Write-Output "             event #2 was: $event2"
    $fail = 1
}

# --- Check 4: virtualization value is in D-04 enum (SKIP guard if no event) ---
if ($hostInfoLine) {
    $virtVal = if ($hostInfoLine -match 'virtualization=([^ ]+)') { $Matches[1] } else { '' }
    $validVirt = @('baremetal','kvm','vmware','hyperv','xen','container','unknown')
    if ($virtVal -in $validVirt) {
        Write-Output "[HOST-02 PASS] virtualization=$virtVal is in D-04 enum"
    } else {
        Write-Output "[HOST-02 FAIL] virtualization=$virtVal is NOT in D-04 enum (baremetal|kvm|vmware|hyperv|xen|container|unknown)"
        $fail = 1
    }
} else {
    Write-Output '[HOST-02 SKIP] virtualization enum check skipped — no event to inspect (see Check 1)'
}

# --- Check 5: cloud_provider sentinel discipline (SKIP guard if no event) ---
if ($hostInfoLine) {
    $cloudVal = if ($hostInfoLine -match 'cloud_provider=([^ ]+)') { $Matches[1] } else { '' }
    $validCloud = @('none','aws','gcp','azure','unknown')
    if ($cloudVal -in $validCloud) {
        Write-Output "[HOST-02 PASS] cloud_provider=$cloudVal honors D-03 sentinel discipline"
    } else {
        Write-Output "[HOST-02 FAIL] cloud_provider=$cloudVal is NOT a valid value (none|aws|gcp|azure|unknown)"
        $fail = 1
    }
} else {
    Write-Output '[HOST-02 SKIP] cloud_provider sentinel check skipped — no event to inspect (see Check 1)'
}

if ($fail -eq 0) { Write-Output '[HOST-02 PASS] All checks passed' }
exit $fail
```

**Token convention:** Use `[HOST-02 PASS]` / `[HOST-02 FAIL]` / `[HOST-02 SKIP]` (mirrors Linux's `[HOST-01 ...]` with phase-specific number). CI can `grep -c 'FAIL'` uniformly across both test scripts.

---

## Shared Patterns

### Sentinel value convention (D-03 — applies to ALL 8 new helpers)

**Source:** `TA-ODIN/bin/modules/_common.sh` lines 88–288 (every helper) + `_common.ps1:131–149` (`Initialize-OdinContext` try/catch with `'unknown'` fallback):

```powershell
# From Initialize-OdinContext lines 133–136:
try {
    $env:ODIN_HOSTNAME = [System.Net.Dns]::GetHostEntry('').HostName
} catch {
    $env:ODIN_HOSTNAME = $env:COMPUTERNAME
}
if (-not $env:ODIN_HOSTNAME) { $env:ODIN_HOSTNAME = 'unknown' }
```

**Apply to ALL Phase 8 helpers:**
- System failure (CIM unavailable, Invoke-RestMethod exception, DNS failure) → `'unknown'`
- Semantic null (not on a cloud host, no default route detected) → `'none'`
- Numeric fields (`cpu_cores`, `mem_total_mb`, `uptime_seconds`) → emit as strings even on failure: `'unknown'`, NEVER `0` or `-1`
- Exception swallow: always `$null = $_` (not `Write-Error $_.Exception`, not `throw`)

### CLM-safe coding rules (D-07 — apply to all new code)

**Source:** `TA-ODIN/bin/modules/_common.ps1` header (lines 1–32):

```
D5-revised - CLM-SAFE EMISSION:
  Events are emitted via Write-Output only. This file MUST NOT contain any of
  the forbidden dynamic-code / raw-encoder patterns enforced by Nyquist
  Dimension 1 (see tools/tests/windows-parity-harness.sh).
```

**Apply to Phase 8 — ALL new code must avoid:**
- `Add-Type` (JIT compilation blocked by CLM)
- `Invoke-Expression` / `iex` (forbidden by Dim 1 static grep)
- `.NET` reflection (`[System.Reflection.*]`)
- Type accelerators that go beyond `[int]`, `[string]`, `[double]` (e.g., `[System.Environment]` for `os_version` — D-07 says fall back to CIM if that fails)
- `Import-Module` or `#Requires -Module` (Dim 2 static grep)

**PSCL fallback for fqdn:** `[System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName` may fail in strict CLM. `Initialize-OdinContext` (lines 131–149) already handles this pattern with try/catch → `$env:COMPUTERNAME`. Mirror that exact pattern in `Get-OdinNetwork`.

### Invoke-OdinEmit as sole output channel (applies to `Invoke-OdinEmitHostInfo`)

**Source:** `TA-ODIN/bin/modules/_common.ps1` lines 93–117. Every module (`processes.ps1:122`, `services.ps1`, etc.) calls `Invoke-OdinEmit` — never `Write-Output` directly for event emission.

**Apply to Phase 8:** `Invoke-OdinEmitHostInfo` calls `Invoke-OdinEmit` once with all 13 fields concatenated. This is non-negotiable: it ensures the `$script:ODIN_EVENT_COUNT` guardrail and `$script:ODIN_EVENTS_TRUNCATED` flag apply to the host_info event.

### Cross-platform parity contract (Phase 8 ↔ Phase 7 mirror names)

**Source:** `TA-ODIN/bin/modules/_common.sh` — each helper has a `# Phase 8 mirror:` comment:

```bash
# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Get-OdinOsDistro
# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Get-OdinOsKernelArch
# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Get-OdinHardware
# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Get-OdinRuntimeUptime
# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Get-OdinNetwork
# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Get-OdinVirtualization
# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Invoke-OdinCloudImds
# Phase 8 mirror: TA-ODIN/bin/modules/_common.ps1 → Invoke-OdinEmitHostInfo
```

**Apply to Phase 8:** These 8 names are NON-NEGOTIABLE. They are pre-committed in Phase 7's code. Each PowerShell function's header MUST include a back-reference:

```powershell
# Phase 8 mirror of detect_os_distro() in TA-ODIN/bin/modules/_common.sh
```

### windows-parity-harness.sh non-regression constraints

**Source:** `tools/tests/windows-parity-harness.sh` Dimensions 1–6.

| Dimension | What it checks | Phase 8 impact |
|-----------|---------------|----------------|
| Dim 1 (line 64) | `grep -RIEn 'Invoke-Expression\|Add-Type\|iex \|...' TA-ODIN/bin/` | New code in `_common.ps1` MUST NOT contain any of these patterns |
| Dim 2 (line 82) | `grep -RIEn '#Requires -Module\|Import-Module [^M]'` | No new module imports in Phase 8 code |
| Dim 3 (line 103) | `grep 'Win32_Product' packages.ps1` | Phase 8 does not touch packages.ps1 — no impact |
| Dim 4 (line 126–136) | `grep -c 'type=odin_start'`, `type=odin_complete modules_total=6`, 6 module types | The new `type=odin_host_info` event will appear in output but harness only counts module types. No breakage. |
| Dim 5 (line 204–244) | Per-type field-name parity (service/port/package/process/mount) vs Linux golden | Phase 8 adds no new module event types — no breakage. `odin_host_info` is orchestrator-level, not in Dim 5 type list. |
| Dim 6 (line 258–260) | `type=odin_error module=services` + `type=odin_complete modules_total=6 modules_success=5 modules_failed=1` | Phase 8 does not change fail-soft logic — no impact |

**Dim 4 subtlety:** `complete_count=$(echo "$out" | grep -c 'type=odin_complete modules_total=6')` checks for `modules_total=6` specifically. Phase 8 only adds a pre-loop emit call — module count stays 6. No change needed.

---

## Critical Implementation Questions Resolved

### Q1: Does odin.ps1 already dot-source _common.ps1?

**Yes.** `odin.ps1:65`: `. $CommonLib`

This means adding functions to `_common.ps1` makes them immediately available in `odin.ps1`'s scope. Phase 8 requires NO additional sourcing — just add `Invoke-OdinEmitHostInfo` to `_common.ps1` and call it from `odin.ps1:96` (after the existing `odin_start` emit at line 95).

### Q2: Where is the exact insertion line in odin.ps1?

**After line 95** — after `Invoke-OdinEmit "type=odin_start ..."` and before line 100 (`$modules_total = 0`). This is the direct mirror of Linux `odin.sh:115` (`emit_host_info`), which sits between `odin_start` (line 108) and the counter init (line 124).

### Q3: Are there any idempotency guards needed for _common.ps1?

**No.** The existing idempotency mechanism in `_common.ps1` (lines 46–51: `Get-Variable -Name ... -ErrorAction SilentlyContinue`) only guards `$script:ODIN_EVENT_COUNT` and `$script:ODIN_EVENTS_TRUNCATED`. The new functions (`Get-OdinOsDistro`, etc.) can be defined unconditionally — PowerShell function definitions in a script scope are idempotent by overwrite when dot-sourced. This mirrors Phase 7's Linux behavior (new `detect_*` functions defined unconditionally in `_common.sh`, only `emit`/`get_timestamp` guarded by `! declare -f`).

### Q4: Where does Invoke-OdinEmit get called in the existing module loop?

Modules run inside `Start-Job` child processes (`odin.ps1:125–146`), which dot-source `_common.ps1` independently in the child session. `Invoke-OdinEmit` is called from inside each module (e.g., `processes.ps1:122`). The orchestrator's `Invoke-OdinEmit` calls for `odin_start`, `odin_error`, and `odin_complete` are in the PARENT process. `Invoke-OdinEmitHostInfo` will also run in the PARENT process (not inside Start-Job) — same as Linux where `emit_host_info` is called by the orchestrator, not a module subprocess.

---

## No Analog Found

None. All three Phase 8 files have exact in-repo analogs:
- `_common.ps1` extension: mirrors Phase 7's `_common.sh` extension pattern + follows existing `_common.ps1:59–160` function style
- `odin.ps1` insertion: direct mirror of `odin.sh:110–115`
- `check-host-info.ps1`: direct port of `check-host-info.sh:1–100`

The only novel element is `Invoke-RestMethod` for IMDS probes — but this follows mechanically from the D-05 decision (mirror curl with `Invoke-RestMethod -TimeoutSec 1`) and the existing `Invoke-CimMethod` usage in `processes.ps1:62` establishes the Invoke-verb/try-catch idiom.

---

## Metadata

**Analog search scope:** `TA-ODIN/bin/`, `TA-ODIN/bin/modules/`, `tools/tests/`
**Files scanned:** `_common.ps1` (178 lines), `_common.sh` (344 lines), `odin.ps1` (203 lines), `odin.sh` (178 lines), `processes.ps1` (129 lines), `check-host-info.sh` (100 lines), `windows-parity-harness.sh` (324 lines)
**Pattern extraction date:** 2026-04-29
**Decision compliance check:**
- D-05 (Invoke-RestMethod -TimeoutSec 1): Pattern 7 above
- D-06 (Get-CimInstance only): Pattern 3 + explicit rules, never WMI
- D-07 (PSCL graceful degradation): Pattern 3 + Shared Pattern CLM-safe rules
- D-01 (extend _common.ps1): confirmed — additive-only, no new file
- D-02 (sequential AWS→GCP→Azure): Pattern 7 (Invoke-OdinCloudImds)
- D-03 (unknown/none sentinels): Shared Pattern + per-function fallbacks
- D-04 (7-value virt enum): Pattern 8 — exact switch statement
