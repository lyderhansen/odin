# TA-ODIN v1.0.1 - Shared PowerShell Library (Windows)
#
# D2 - DOT-SOURCED LIBRARY (NEVER a PowerShell module):
#   This file is dot-sourced directly by the orchestrator and (Wave 2) by every
#   module. It is NOT a PowerShell module; there is no .psm1/.psd1 and no
#   module-import call anywhere. Dot-sourcing is CLM-safe (Constrained Language
#   Mode) and requires no module manifest or module path configuration.
#
# D5-revised - CLM-SAFE EMISSION:
#   Events are emitted via Write-Output only. This file MUST NOT contain any of
#   the forbidden dynamic-code / raw-encoder patterns enforced by Nyquist
#   Dimension 1 (see tools/tests/windows-parity-harness.sh and plan 01
#   VALIDATION doc for the canonical grep list).
#   Windows line endings (CRLF) are normalized at Splunk parse time via
#   CHARSET = UTF-8 in TA-ODIN/default/props.conf. No in-script encoding shims.
#
# D6 - FIXTURE MODE:
#   When $env:ODIN_TEST_FIXTURE is set (e.g. by the windows-parity-harness),
#   the bottom of this file dot-sources tools/tests/windows-fixtures/stubs.ps1
#   which shadows Windows-only cmdlets (Get-Service, Get-CimInstance, etc.)
#   with fixture-driven functions. Production Splunk UF invocations NEVER set
#   ODIN_TEST_FIXTURE.
#
# CMDLET DISCIPLINE:
#   No aliases anywhere. Write out Get-ChildItem, Where-Object, ForEach-Object,
#   Sort-Object in full. No %, ?, gci, gjb, wjb, rjb. Harness Dim 1 does not
#   grep for aliases but manual review does.
#
# SCOPE DISCIPLINE:
#   All shared counters use $script: scope. No $global:. Start-Job spawns a
#   child pwsh process anyway, so no cross-job state is ever shared.

# ---------------------------------------------------------------------------
# Script-scope state variables (idempotent — safe against double dot-source)
# ---------------------------------------------------------------------------
# HARD-02: pre-set $env:ODIN_MAX_EVENTS / $env:ODIN_MODULE_TIMEOUT are
# honored. Defaults apply only when the env var is unset or empty. The
# env var is then cast to int for the $script: counter the orchestrator
# uses in its Wait-Job event-count comparison.
if (-not $env:ODIN_MAX_EVENTS)    { $env:ODIN_MAX_EVENTS = '50000' }
$script:ODIN_MAX_EVENTS = [int]$env:ODIN_MAX_EVENTS

if (-not $env:ODIN_MODULE_TIMEOUT) { $env:ODIN_MODULE_TIMEOUT = '90' }
$script:ODIN_MODULE_TIMEOUT = [int]$env:ODIN_MODULE_TIMEOUT

# D-05 (Phase 8 mirror of Phase 7 D-02): seconds per cloud probe (1s × 3 sequential = 3s worst case)
if (-not $env:ODIN_IMDS_TIMEOUT) { $env:ODIN_IMDS_TIMEOUT = '1' }
$script:ODIN_IMDS_TIMEOUT = [int]$env:ODIN_IMDS_TIMEOUT

if (-not (Get-Variable -Name 'ODIN_EVENT_COUNT' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ODIN_EVENT_COUNT = 0
}
if (-not (Get-Variable -Name 'ODIN_EVENTS_TRUNCATED' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ODIN_EVENTS_TRUNCATED = $false
}

# ---------------------------------------------------------------------------
# Get-OdinTimestamp - ISO 8601 UTC (yyyy-MM-ddTHH:mm:ssZ)
# ---------------------------------------------------------------------------
# Mirrors Linux get_timestamp() in TA-ODIN/bin/odin.sh. Uses the Get-Date
# cmdlet (NOT [DateTime]::UtcNow) so the emit path relies only on cmdlets
# that are allow-listed under WIN-09 Dimension 2.
function Get-OdinTimestamp {
    return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

# ---------------------------------------------------------------------------
# Format-OdinValue - equivalent to Linux safe_val() in modules/services.sh
# ---------------------------------------------------------------------------
# Strips CR/LF, escapes embedded double-quotes, wraps the result in double
# quotes if it contains whitespace or '='. Null values become empty string.
# This preserves one-record-per-line and keeps Splunk KV_MODE parsing clean.
function Format-OdinValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [AllowNull()]
        $Value
    )
    process {
        if ($null -eq $Value) { return '' }
        $s = [string]$Value
        # Strip CR, replace LF with single space (one record = one line)
        $s = $s -replace "`r", ''
        $s = $s -replace "`n", ' '
        # Escape embedded double quotes
        $s = $s -replace '"', '\"'
        # Wrap if it contains whitespace or '='
        if ($s -match '[\s=]') {
            return '"' + $s + '"'
        }
        return $s
    }
}

# ---------------------------------------------------------------------------
# Invoke-OdinEmit - single event emission with MAX_EVENTS guardrail
# ---------------------------------------------------------------------------
# Prepends the Linux-parity prelude:
#   timestamp=<iso> hostname=<fqdn> os=<os> run_id=<id> odin_version=<ver>
# followed by the caller-supplied $Line. Respects $script:ODIN_MAX_EVENTS
# and emits a single type=truncated marker when the cap is first breached.
# Uses Write-Output only (D5-revised).
function Invoke-OdinEmit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Line
    )
    if ($script:ODIN_EVENTS_TRUNCATED) { return }
    if ($script:ODIN_EVENT_COUNT -ge $script:ODIN_MAX_EVENTS) {
        $script:ODIN_EVENTS_TRUNCATED = $true
        $ts = Get-OdinTimestamp
        $truncLine = "timestamp=$ts hostname=$($env:ODIN_HOSTNAME) os=$($env:ODIN_OS) run_id=$($env:ODIN_RUN_ID) odin_version=$($env:ODIN_VERSION) type=truncated message=`"Event limit reached (max=$($script:ODIN_MAX_EVENTS)). Remaining events suppressed.`""
        Write-Output $truncLine
        return
    }
    $script:ODIN_EVENT_COUNT = $script:ODIN_EVENT_COUNT + 1
    $ts = Get-OdinTimestamp
    Write-Output "timestamp=$ts hostname=$($env:ODIN_HOSTNAME) os=$($env:ODIN_OS) run_id=$($env:ODIN_RUN_ID) odin_version=$($env:ODIN_VERSION) $Line"
}

# ---------------------------------------------------------------------------
# Initialize-OdinContext - populate $env:ODIN_* with standalone fallbacks
# ---------------------------------------------------------------------------
# Mirrors the Linux standalone-fallback block in modules/services.sh:19-26.
# When a module is run directly (not via the orchestrator) or when the
# orchestrator is invoked for the first time, this ensures the emit prelude
# has values for hostname, os, run_id, odin_version.
#
# [System.Net.Dns]::GetHostEntry is a reflection lookup on an allow-listed
# .NET type (see RESEARCH.md §7) and remains CLM-safe (no dynamic compilation).
# Wrapped in try/catch so macOS pwsh (fixture mode) falls back to the
# environment's COMPUTERNAME / hostname without throwing.
function Initialize-OdinContext {
    if (-not $env:ODIN_HOSTNAME) {
        try {
            $env:ODIN_HOSTNAME = [System.Net.Dns]::GetHostEntry('').HostName
        } catch {
            $env:ODIN_HOSTNAME = $env:COMPUTERNAME
        }
        if (-not $env:ODIN_HOSTNAME) {
            try {
                $env:ODIN_HOSTNAME = (& hostname 2>$null)
            } catch {
                $env:ODIN_HOSTNAME = 'unknown'
            }
        }
        if (-not $env:ODIN_HOSTNAME) { $env:ODIN_HOSTNAME = 'unknown' }
    }
    if (-not $env:ODIN_OS)      { $env:ODIN_OS = 'windows' }
    if (-not $env:ODIN_RUN_ID)  { $env:ODIN_RUN_ID = "standalone-$PID" }
    if (-not $env:ODIN_VERSION) { $env:ODIN_VERSION = '1.0.1' }
}

# ---------------------------------------------------------------------------
# Initialize-OdinModuleState - reset per-module counters
# ---------------------------------------------------------------------------
# Called by the orchestrator before each module runs, so the MAX_EVENTS cap
# applies per-module (matching Linux ODIN_EVENT_COUNT=0 reset per module).
function Initialize-OdinModuleState {
    $script:ODIN_EVENT_COUNT = 0
    $script:ODIN_EVENTS_TRUNCATED = $false
}

# ---------------------------------------------------------------------------
# D6 Fixture Mode - dot-source stubs.ps1 when ODIN_TEST_FIXTURE is set
# ---------------------------------------------------------------------------
# The harness sets ODIN_TEST_FIXTURE to a per-host fixture directory such as
# tools/tests/windows-fixtures/hostA. The stub library lives one level up at
# tools/tests/windows-fixtures/stubs.ps1 and shadows Windows-only cmdlets
# with fixture-backed functions (PowerShell function resolution precedes
# cmdlet resolution per about_Command_Precedence).
#
# Production Splunk UF invocations NEVER set ODIN_TEST_FIXTURE. This block
# is a no-op in that case.
if ($env:ODIN_TEST_FIXTURE) {
    $stubsPath = Join-Path (Split-Path -Parent $env:ODIN_TEST_FIXTURE) 'stubs.ps1'
    if (Test-Path $stubsPath) {
        . $stubsPath
    }
}
