# TA-ODIN v1.0.0 - Windows Orchestrator
#
# Autodiscovers and runs all modules in bin/modules/*.ps1 (excluding _common.ps1).
# Emits canonical type=odin_start / type=odin_complete / type=odin_error markers
# with the same prelude schema as the Linux orchestrator (TA-ODIN/bin/odin.sh):
#   timestamp=<ISO8601Z> hostname=<fqdn> os=windows run_id=<epoch-pid> odin_version=<ver>
#
# OPERATIONAL PREREQUISITE (D1):
#   In WDAC-enforced environments, every .ps1 file under
#       %SPLUNK_HOME%\etc\apps\TA-ODIN\bin\
#   (this orchestrator, _common.ps1, and every module) MUST be allow-listed
#   via code-signing or a path rule. Start-Job spawns a child PowerShell
#   process that re-evaluates WDAC policy on each script it loads, so the
#   modules are loaded in the child session, not the parent. This is an
#   operational note only — the orchestrator does NOT perform a runtime
#   WDAC check (there is no supported cmdlet for it and any runtime probe
#   would itself need to be allow-listed).
#
# CLM-SAFE DESIGN (D5-revised):
#   - Emission is exclusively via Write-Output (directly or through
#     Invoke-OdinEmit in _common.ps1). No raw console writer, no manual
#     UTF-8 encoder construction, no reflection on System.Text.Encoding.
#   - CRLF line endings on Windows are normalized at Splunk parse time by
#     CHARSET = UTF-8 in TA-ODIN/default/props.conf.
#
# FAIL-SOFT (WIN-12):
#   The orchestrator NEVER aborts on a module failure. Every module is
#   launched inside Start-Job and wrapped in try/catch. Exceptions, failed
#   job states, and timeouts are all synthesized into type=odin_error
#   events and enumeration continues with the next module. The process
#   ALWAYS exits 0. Phase 2 HARD-04 alerting keys off odin_error events
#   in SPL, not on exit code.
#
# TIMEOUT CONVENTION (D4):
#   On Wait-Job -Timeout expiry the orchestrator emits
#       type=odin_error module=<name> exit_code=124 timeout_reason=wait_job_timeout
#   matching POSIX timeout(1) so the Phase 2 HARD-04 alert is OS-agnostic.
#
# SCOPE DISCIPLINE:
#   All counters are plain local variables. No global-scope state anywhere.
#   _common.ps1 uses $script: state which is private to the parent session.

[CmdletBinding()]
param()

# Continue-on-error at orchestrator level: we catch per-module and never abort.
$ErrorActionPreference = 'Continue'

# --------------------------------------------------------------------------
# Resolve script directory (parity with TA-ODIN/bin/odin.sh:25)
# --------------------------------------------------------------------------
$ScriptDir  = Split-Path -Parent $PSCommandPath
$ModulesDir = Join-Path $ScriptDir 'modules'
$CommonLib  = Join-Path $ModulesDir '_common.ps1'

if (-not (Test-Path $CommonLib)) {
    $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    Write-Output "timestamp=$ts hostname=unknown os=windows run_id=error-$PID odin_version=1.0.0 type=odin_error message=`"_common.ps1 not found at $CommonLib`""
    exit 1
}

# Dot-source shared helpers (D2) — also triggers D6 fixture-mode stub load
# inside _common.ps1 if $env:ODIN_TEST_FIXTURE is set.
. $CommonLib

# Run-id prelude (mirrors Linux odin.sh's $(date +%s)-$$ pattern)
if (-not $env:ODIN_RUN_ID) {
    $epoch = [int][double]((Get-Date).ToUniversalTime() - (Get-Date '1970-01-01Z').ToUniversalTime()).TotalSeconds
    $env:ODIN_RUN_ID = "$epoch-$PID"
}
if (-not $env:ODIN_VERSION) { $env:ODIN_VERSION = '1.0.0' }

# Populate remaining $env:ODIN_* with fallbacks (hostname, os)
Initialize-OdinContext

# --------------------------------------------------------------------------
# Per-module timeout (seconds) — 90s leaves 30s margin within the Splunk
# scripted-input timeout of 120s. Tunable via ODIN_MODULE_TIMEOUT for
# Phase 2 HARD-02 global-budget experiments.
# --------------------------------------------------------------------------
$ModuleTimeout = 90
if ($env:ODIN_MODULE_TIMEOUT) {
    $parsed = 0
    if ([int]::TryParse($env:ODIN_MODULE_TIMEOUT, [ref]$parsed) -and $parsed -gt 0) {
        $ModuleTimeout = $parsed
    }
}

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

if (-not (Test-Path $ModulesDir)) {
    Invoke-OdinEmit "type=odin_error message=`"Modules directory not found: $ModulesDir`""
} else {
    # NOTE: The fixture harness (tools/tests/windows-fixtures/stubs.ps1)
    # shadows Get-ChildItem with a function that uses
    # ValueFromRemainingArguments and forwards via a positional splat; this
    # mishandles any named parameter like -Path or -Filter. To stay portable
    # between production pwsh (real cmdlet) and fixture mode, we pass the
    # path positionally and filter with Where-Object.
    $moduleFiles = Get-ChildItem $ModulesDir |
                   Where-Object { -not $_.PSIsContainer -and $_.Extension -eq '.ps1' -and $_.Name -ne '_common.ps1' } |
                   Sort-Object Name

    foreach ($moduleFile in $moduleFiles) {
        $modules_total++
        $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($moduleFile.Name)
        Initialize-OdinModuleState

        # D1 CANONICAL PATTERN: Start-Job / Wait-Job -Timeout / Stop-Job / Receive-Job / Remove-Job
        $job = $null
        try {
            $job = Start-Job -ScriptBlock {
                param(
                    $modulePath,
                    $commonLibPath,
                    $fixtureDir,
                    $hostname,
                    $os,
                    $runId,
                    $version,
                    $maxEvents
                )
                # Re-establish context in the child pwsh session. Start-Job
                # spawns a fresh process, so no $env or $script state is
                # inherited from the parent.
                if ($fixtureDir) { $env:ODIN_TEST_FIXTURE = $fixtureDir }
                $env:ODIN_HOSTNAME = $hostname
                $env:ODIN_OS       = $os
                $env:ODIN_RUN_ID   = $runId
                $env:ODIN_VERSION  = $version
                . $commonLibPath
                $script:ODIN_MAX_EVENTS = $maxEvents
                . $modulePath
            } -ArgumentList $moduleFile.FullName, $CommonLib, $env:ODIN_TEST_FIXTURE, $env:ODIN_HOSTNAME, $env:ODIN_OS, $env:ODIN_RUN_ID, $env:ODIN_VERSION, $script:ODIN_MAX_EVENTS

            $finished = Wait-Job -Job $job -Timeout $ModuleTimeout

            if ($null -eq $finished) {
                # D4: timeout — synthesize exit_code=124 (POSIX timeout(1) convention)
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                $partialOutput = Receive-Job -Job $job -ErrorAction SilentlyContinue
                foreach ($line in $partialOutput) { Write-Output $line }
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                $modules_failed++
                Invoke-OdinEmit "type=odin_error module=$moduleName exit_code=124 timeout_reason=wait_job_timeout message=`"Module $moduleName exceeded ${ModuleTimeout}s timeout`""
            } else {
                # Module finished within budget — pipe its output through
                $jobOutput = Receive-Job -Job $job -ErrorAction Continue
                foreach ($line in $jobOutput) { Write-Output $line }
                $jobState = $job.State
                $childReason = $null
                if ($job.ChildJobs -and $job.ChildJobs[0] -and $job.ChildJobs[0].JobStateInfo -and $job.ChildJobs[0].JobStateInfo.Reason) {
                    $childReason = $job.ChildJobs[0].JobStateInfo.Reason.Message
                }
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

                if ($jobState -eq 'Failed') {
                    $modules_failed++
                    $errMsg = 'module threw an exception'
                    if ($childReason) {
                        $errMsg = $childReason -replace '"', "'" -replace "`r", '' -replace "`n", ' '
                    }
                    Invoke-OdinEmit "type=odin_error module=$moduleName exit_code=1 error_message=`"$errMsg`""
                } else {
                    $modules_success++
                }
            }
        } catch {
            # Parent-side exception (Start-Job itself failed, etc.)
            if ($job) {
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
            $modules_failed++
            $exMsg = ($_.Exception.Message) -replace '"', "'" -replace "`r", '' -replace "`n", ' '
            Invoke-OdinEmit "type=odin_error module=$moduleName exit_code=2 error_message=`"$exMsg`""
        }
    }
}

# --------------------------------------------------------------------------
# Completion marker
# --------------------------------------------------------------------------
$scanEnd = Get-Date
$durationMs = [int]($scanEnd - $scanStart).TotalMilliseconds
Invoke-OdinEmit "type=odin_complete modules_total=$modules_total modules_success=$modules_success modules_failed=$modules_failed duration_ms=$durationMs message=`"TA-ODIN Windows enumeration completed`""

# Fail-soft (WIN-12): always exit 0. Phase 2 HARD-04 alerts on type=odin_error
# in SPL, not on process exit code.
exit 0
