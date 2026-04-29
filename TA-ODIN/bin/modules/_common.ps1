# TA-ODIN v1.0.2 - Shared PowerShell Library (Windows)
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

# D-05 (Phase 8 mirror of Phase 7 D-02): seconds per cloud probe (1s × 3 sequential).
# AWS IMDSv2 requires 2 sequential calls (token PUT + region GET).
# Worst-case total on a non-cloud host: 4s (AWS: 2×1s + GCP: 1s + Azure: 1s).
# Non-cloud hosts typically resolve in 3s — the token endpoint fails immediately,
# so the second AWS call is never made. (3-4s worst case)
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
    if (-not $env:ODIN_VERSION) { $env:ODIN_VERSION = '1.0.2' }
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

# ============================================================================
# Phase 8 / HOST-02: Host metadata detection helpers (v1.0.2)
# ============================================================================
# These helpers are called by Invoke-OdinEmitHostInfo to populate the 13-field
# type=odin_host_info event. Each helper:
#   - Returns ONE pipe-separated string OR a single value
#   - Returns "unknown" on detection failure (D-03 — system error sentinel)
#   - Returns "none" only for semantic null (e.g., no cloud detected)
#   - Wraps every CIM/Net call in try/catch (D-07 — PSCL graceful degradation)
#   - Mirrors a corresponding bash helper in TA-ODIN/bin/modules/_common.sh
# ============================================================================

# Mirror: TA-ODIN/bin/modules/_common.sh → detect_os_distro
# Returns: pipe-separated "distro|version|pretty" (3 of the 13 fields).
# os_distro is hardcoded "windows" (no parsing needed — Win32_OS.Caption always
# starts with "Microsoft Windows"). os_version uses [System.Environment] with
# fallback to Win32_OperatingSystem.Version (PSCL may block type accelerator).
function Get-OdinOsDistro {
    $distro = "windows"
    $version = "unknown"
    $pretty = "unknown"

    # Try [System.Environment] first (faster, no CIM call). PSCL may block this.
    try {
        $v = [System.Environment]::OSVersion.Version
        if ($v) { $version = "$($v.Major).$($v.Minor).$($v.Build)" }
    } catch {
        # PSCL or other failure — fallback to CIM
        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            if ($os.Version) { $version = $os.Version }
        } catch {
            $version = "unknown"
        }
    }

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        if ($os.Caption) { $pretty = $os.Caption.Trim() }
    } catch {
        $pretty = "unknown"
    }

    return "${distro}|${version}|${pretty}"
}

# Mirror: TA-ODIN/bin/modules/_common.sh → detect_os_kernel_arch
# Returns: pipe-separated "kernel|arch" (2 of the 13 fields).
# os_kernel uses Win32_OperatingSystem.BuildNumber (e.g., "26100"); concat with
# patch level if available. os_arch uses $env:PROCESSOR_ARCHITECTURE lowercased
# to match Linux x86_64/aarch64 convention (windows reports AMD64/ARM64).
function Get-OdinOsKernelArch {
    $kernel = "unknown"
    $arch = "unknown"

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        if ($os.BuildNumber) { $kernel = $os.BuildNumber }
    } catch {
        $kernel = "unknown"
    }

    try {
        if ($env:PROCESSOR_ARCHITECTURE) {
            $arch = $env:PROCESSOR_ARCHITECTURE.ToLower()
        }
    } catch {
        $arch = "unknown"
    }
    if (-not $arch) { $arch = "unknown" }

    return "${kernel}|${arch}"
}

# Mirror: TA-ODIN/bin/modules/_common.sh → detect_hardware
# Returns: pipe-separated "cpu_cores|mem_total_mb" (2 of the 13 fields).
# cpu_cores sums NumberOfCores across processors (multi-socket aware).
# mem_total_mb converts TotalVisibleMemorySize (KB) to MB via integer division.
function Get-OdinHardware {
    $cores = "unknown"
    $memMb = "unknown"

    try {
        $procs = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        $sum = ($procs | Measure-Object -Property NumberOfCores -Sum).Sum
        if ($sum -and $sum -gt 0) { $cores = "$sum" }
    } catch {
        $cores = "unknown"
    }

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        if ($os.TotalVisibleMemorySize -and $os.TotalVisibleMemorySize -gt 0) {
            $memMb = [string][int]($os.TotalVisibleMemorySize / 1024)
        }
    } catch {
        $memMb = "unknown"
    }

    return "${cores}|${memMb}"
}

# Mirror: TA-ODIN/bin/modules/_common.sh → detect_runtime_uptime
# Returns: a single integer string OR "unknown" (1 of the 13 fields).
# Detection: (Get-Date) - LastBootUpTime → TotalSeconds (cast to int).
function Get-OdinRuntimeUptime {
    $uptime = "unknown"

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        if ($os.LastBootUpTime) {
            $delta = ((Get-Date) - $os.LastBootUpTime).TotalSeconds
            if ($delta -and $delta -gt 0) {
                $uptime = "$([int]$delta)"
            }
        }
    } catch {
        $uptime = "unknown"
    }

    return $uptime
}

# Mirror: TA-ODIN/bin/modules/_common.sh → detect_network
# Returns: pipe-separated "fqdn|ip_primary" (2 of the 13 fields).
# Detection:
#   - fqdn: [System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName
#     PSCL fallback: just $env:COMPUTERNAME (unqualified) — better than "unknown"
#   - ip_primary: Get-NetRoute → Get-NetIPAddress for default route's source IP
#     Returns "none" semantic null when no default route exists, distinct from
#     "unknown" (system error, e.g., NetTCPIP module unavailable).
function Get-OdinNetwork {
    $fqdn = "unknown"
    $ip = "unknown"

    try {
        $hostName = [System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName
        if ($hostName) { $fqdn = $hostName }
    } catch {
        # PSCL or DNS failure — try unqualified COMPUTERNAME as fallback
        try {
            if ($env:COMPUTERNAME) { $fqdn = $env:COMPUTERNAME }
        } catch {
            $fqdn = "unknown"
        }
    }

    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
                 Sort-Object -Property RouteMetric |
                 Select-Object -First 1
        if ($route) {
            $netIp = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex `
                                      -AddressFamily IPv4 -ErrorAction Stop |
                     Select-Object -First 1
            if ($netIp -and $netIp.IPAddress) {
                $ip = $netIp.IPAddress
            } else {
                $ip = "none"
            }
        } else {
            # No default route → semantic null per D-03
            $ip = "none"
        }
    } catch {
        # NetTCPIP module unavailable or PSCL block → system failure sentinel
        $ip = "unknown"
    }

    return "${fqdn}|${ip}"
}

# Mirror: TA-ODIN/bin/modules/_common.sh → detect_virt
# Returns one of: baremetal | kvm | vmware | hyperv | xen | container | unknown (D-04)
# Single field, 7-value enum. Matches Phase 7's enum exactly for parity.
# Detection cascade:
#   1. Win32_ComputerSystem.Manufacturer + .Model wildcard match
#   2. Win32_OperatingSystem.OperatingSystemSKU container detection
#   3. Default to baremetal if no virt signal
#   "unknown" only when CIM call fails entirely (PSCL or RPC error per D-07)
function Get-OdinVirtualization {
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $signature = "$($cs.Manufacturer) $($cs.Model)"

        switch -Wildcard ($signature) {
            "*Microsoft*Virtual*"      { return "hyperv" }
            "*VMware*"                 { return "vmware" }
            "*QEMU*"                   { return "kvm" }
            "*Xen*"                    { return "xen" }
            "*Amazon EC2*"             { return "kvm" }    # EC2 nitro instances
            "*Google*Compute Engine*"  { return "kvm" }    # GCE
        }

        # No hypervisor signature — check for Windows Container OS edition
        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            # Container SKU values: 0x00000131 (Server Core Container), 0x00000132 (Nano Container)
            if ($os.OperatingSystemSKU -in @(0x00000131, 0x00000132)) {
                return "container"
            }
        } catch {
            # Container check failed — fall through to baremetal
        }

        # No virt signal + no container — assume baremetal
        return "baremetal"
    } catch {
        # Win32_ComputerSystem unavailable (PSCL or RPC failure) — D-07 sentinel
        return "unknown"
    }
}

# --- Cloud IMDS probes (D-05: sequential AWS→GCP→Azure, 1s timeout each, 3-4s worst case) ---
# Internal helpers, called only by Invoke-OdinCloudImds. Each returns
# "provider|region" on success or $null on failure (caller cascades).
# AWS IMDSv2 makes 2 sequential calls (token+region); GCP and Azure make 1 each.

# AWS IMDSv2 (token-based, more secure than v1).
# Two sequential calls: PUT token, GET region. PSCL note: Invoke-RestMethod
# is allowed in ConstrainedLanguage Mode (no .NET reflection).
function Get-OdinAwsImds {
    try {
        $tokenUrl = "http://169.254.169.254/latest/api/token"
        $token = Invoke-RestMethod -Method Put -Uri $tokenUrl `
            -Headers @{ "X-aws-ec2-metadata-token-ttl-seconds" = "60" } `
            -TimeoutSec $script:ODIN_IMDS_TIMEOUT `
            -UseBasicParsing -ErrorAction Stop
        if (-not $token) { return $null }

        $regionUrl = "http://169.254.169.254/latest/meta-data/placement/region"
        $region = Invoke-RestMethod -Method Get -Uri $regionUrl `
            -Headers @{ "X-aws-ec2-metadata-token" = $token } `
            -TimeoutSec $script:ODIN_IMDS_TIMEOUT `
            -UseBasicParsing -ErrorAction Stop
        if (-not $region) { return $null }
        return "aws|$region"
    } catch {
        return $null
    }
}

# GCP metadata server (header-gated, requires Metadata-Flavor: Google).
# Returns zone like "projects/PROJECT_NUM/zones/europe-west1-b" → strip to region.
function Get-OdinGcpImds {
    try {
        $url = "http://metadata.google.internal/computeMetadata/v1/instance/zone"
        $zone = Invoke-RestMethod -Method Get -Uri $url `
            -Headers @{ "Metadata-Flavor" = "Google" } `
            -TimeoutSec $script:ODIN_IMDS_TIMEOUT `
            -UseBasicParsing -ErrorAction Stop
        if (-not $zone) { return $null }
        # Strip whitespace including \r\n that Invoke-RestMethod may include
        # in text/plain HTTP responses on Windows (CR-01)
        $zone = $zone.ToString().Trim()
        if (-not $zone) { return $null }
        # Extract last path segment, strip trailing -letter zone suffix
        $lastSegment = ($zone -split '/')[-1]
        $region = $lastSegment -replace '-[a-z]$', ''
        if (-not $region) { return $null }
        return "gcp|$region"
    } catch {
        return $null
    }
}

# Azure IMDS (api-version param required).
function Get-OdinAzureImds {
    try {
        $url = "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text"
        $region = Invoke-RestMethod -Method Get -Uri $url `
            -Headers @{ "Metadata" = "true" } `
            -TimeoutSec $script:ODIN_IMDS_TIMEOUT `
            -UseBasicParsing -ErrorAction Stop
        if (-not $region) { return $null }
        return "azure|$region"
    } catch {
        return $null
    }
}

# Mirror: TA-ODIN/bin/modules/_common.sh → probe_cloud_imds
# Returns: pipe-separated "provider|region" (2 of the 13 fields).
# Sequential probe order: AWS → GCP → Azure (D-05 mirror of Phase 7 D-02).
# All three fail (non-cloud or PSCL block): returns "none|none" (semantic null per D-03).
function Invoke-OdinCloudImds {
    $result = Get-OdinAwsImds
    if ($result) { return $result }
    $result = Get-OdinGcpImds
    if ($result) { return $result }
    $result = Get-OdinAzureImds
    if ($result) { return $result }
    return "none|none"
}

# Mirror: TA-ODIN/bin/modules/_common.sh → emit_host_info
# THE ONLY function that emits type=odin_host_info. Calls each detection helper
# exactly once, splits pipe-separated returns, then issues a single Invoke-OdinEmit
# with all 13 fields concatenated.
#
# Field order in event (matches seed table v1.0.2-host-metadata-enrichment.md
# AND Phase 7's Linux emit_host_info — mandatory for cross-platform parity):
#   os_distro os_version os_pretty os_kernel os_arch
#   cpu_cores mem_total_mb uptime_seconds
#   fqdn ip_primary virtualization
#   cloud_provider cloud_region
#
# Counts toward $script:ODIN_MAX_EVENTS via Invoke-OdinEmit (1 event budget).
# Truncation marker safety preserved (Pattern 3 — same as Phase 7 D-01).
function Invoke-OdinEmitHostInfo {
    # Detection (each helper returns pipe-separated values for its field group).
    # Capture result first, then split — avoids PowerShell parsing -split as argument.
    $osPair = (Get-OdinOsDistro) -split '\|'
    $os_distro  = $osPair[0]
    $os_version = $osPair[1]
    $os_pretty  = $osPair[2]

    $kernPair = (Get-OdinOsKernelArch) -split '\|'
    $os_kernel = $kernPair[0]
    $os_arch   = $kernPair[1]

    $hwPair = (Get-OdinHardware) -split '\|'
    $cpu_cores    = $hwPair[0]
    $mem_total_mb = $hwPair[1]

    $uptime_seconds = Get-OdinRuntimeUptime

    $netPair = (Get-OdinNetwork) -split '\|'
    $fqdn       = $netPair[0]
    $ip_primary = $netPair[1]

    $virtualization = Get-OdinVirtualization

    $cloudPair = (Invoke-OdinCloudImds) -split '\|'
    $cloud_provider = $cloudPair[0]
    $cloud_region   = $cloudPair[1]

    # Build event line via Invoke-OdinEmit (NOT Write-Output — preserves
    # MAX_EVENTS guardrail + standard timestamp/hostname/os/run_id envelope).
    # Format-OdinValue handles space-quoting for fields that may contain spaces
    # (only os_pretty in practice — e.g., "Microsoft Windows 11 Pro").
    $line = "type=odin_host_info " +
            "os_distro=$(Format-OdinValue $os_distro) " +
            "os_version=$(Format-OdinValue $os_version) " +
            "os_pretty=$(Format-OdinValue $os_pretty) " +
            "os_kernel=$(Format-OdinValue $os_kernel) " +
            "os_arch=$os_arch " +
            "cpu_cores=$cpu_cores " +
            "mem_total_mb=$mem_total_mb " +
            "uptime_seconds=$uptime_seconds " +
            "fqdn=$(Format-OdinValue $fqdn) " +
            "ip_primary=$ip_primary " +
            "virtualization=$virtualization " +
            "cloud_provider=$cloud_provider " +
            "cloud_region=$(Format-OdinValue $cloud_region)"

    Invoke-OdinEmit $line
}
