# TA-ODIN Windows Parity Test Harness — Cmdlet-Shadow Stubs
#
# This file is dot-sourced ONLY when $env:ODIN_TEST_FIXTURE is set. In
# production (Splunk Universal Forwarder on Windows), that variable is
# never set and this file is never loaded.
#
# Purpose:
#   PowerShell resolves function names BEFORE cmdlet names (see
#   about_Command_Precedence). By defining functions with the same names
#   as Windows-only cmdlets, we replace the real cmdlets for the
#   remainder of the session. This lets the Windows orchestrator + six
#   modules run unchanged on macOS pwsh against deterministic fixture
#   data.
#
# Shape:
#   Each stub returns [PSCustomObject] instances whose properties match
#   the real cmdlet output surface documented in 01-RESEARCH.md §1.
#
# Throw sentinel:
#   If hostA-broken/services.json contains a record with Name = "__THROW__",
#   Get-Service throws "Induced failure for fail-soft test". This drives
#   Nyquist Dimension 6 (fail-soft verification).
#
# CLM discipline:
#   No forbidden patterns (see Dimension 1 grep in windows-parity-harness.sh
#   for the exact list). No cmdlet aliases. No dynamic code loading.
#   These stubs are audited by windows-parity-harness.sh Dimension 1.

function Get-OdinFixturePath {
    param([string]$Module)
    $fixtureDir = $env:ODIN_TEST_FIXTURE
    if (-not $fixtureDir) { return $null }
    if (-not (Test-Path $fixtureDir)) { return $null }
    $path = Join-Path $fixtureDir "$Module.json"
    if (Test-Path $path) { return $path } else { return $null }
}

function Read-OdinFixture {
    param([string]$Module)
    $path = Get-OdinFixturePath -Module $Module
    if ($null -eq $path) { return @() }
    $raw = Get-Content -Raw -Path $path
    $data = $raw | ConvertFrom-Json
    if ($null -eq $data) { return @() }
    # ConvertFrom-Json returns a single object for single-element arrays;
    # force array shape so callers can always iterate.
    return @($data)
}

function Get-Service {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments = $true)]$Args)
    $records = Read-OdinFixture -Module 'services'
    foreach ($rec in $records) {
        if ($rec.Name -eq '__THROW__') {
            throw "Induced failure for fail-soft test"
        }
    }
    return $records | ForEach-Object {
        [PSCustomObject]@{
            Name        = $_.Name
            DisplayName = $_.DisplayName
            Status      = $_.Status
            StartType   = $_.StartMode
        }
    }
}

function Get-CimInstance {
    [CmdletBinding()]
    param(
        [string]$ClassName,
        [string]$Query,
        [Parameter(ValueFromRemainingArguments = $true)]$Args
    )
    # Extract ClassName from -Query "SELECT ... FROM ClassName ..." if given
    if (-not $ClassName -and $Query) {
        if ($Query -match 'FROM\s+(\w+)') { $ClassName = $Matches[1] }
    }
    switch ($ClassName) {
        'Win32_Service' {
            $records = Read-OdinFixture -Module 'services'
            return $records | ForEach-Object {
                [PSCustomObject]@{
                    Name        = $_.Name
                    DisplayName = $_.DisplayName
                    State       = $_.Status
                    StartMode   = $_.StartMode
                    PathName    = $_.PathName
                    StartName   = $_.StartName
                }
            }
        }
        'Win32_Process' {
            $records = Read-OdinFixture -Module 'processes'
            return $records | ForEach-Object {
                [PSCustomObject]@{
                    ProcessId    = $_.Id
                    Name         = $_.Name
                    ExecutablePath = $_.Path
                    CommandLine  = $_.CommandLine
                }
            }
        }
        default {
            return @()
        }
    }
}

function Get-NetTCPConnection {
    [CmdletBinding()]
    param(
        [string]$State,
        [Parameter(ValueFromRemainingArguments = $true)]$Args
    )
    $records = Read-OdinFixture -Module 'ports'
    $tcp = $records | Where-Object { $_.transport -eq 'tcp' }
    return $tcp | ForEach-Object {
        [PSCustomObject]@{
            LocalAddress  = $_.LocalAddress
            LocalPort     = [uint16]$_.LocalPort
            State         = 'Listen'
            OwningProcess = [uint32]$_.OwningProcess
        }
    }
}

function Get-NetUDPEndpoint {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments = $true)]$Args)
    $records = Read-OdinFixture -Module 'ports'
    $udp = $records | Where-Object { $_.transport -eq 'udp' }
    return $udp | ForEach-Object {
        [PSCustomObject]@{
            LocalAddress  = $_.LocalAddress
            LocalPort     = [uint16]$_.LocalPort
            OwningProcess = [uint32]$_.OwningProcess
        }
    }
}

function Get-ScheduledTask {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments = $true)]$Args)
    $records = Read-OdinFixture -Module 'scheduled_tasks'
    return $records | ForEach-Object {
        [PSCustomObject]@{
            TaskName = $_.TaskName
            TaskPath = $_.TaskPath
            State    = $_.State
            Author   = $_.Author
        }
    }
}

function Get-ScheduledTaskInfo {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]$InputObject,
        [string]$TaskName,
        [string]$TaskPath,
        [Parameter(ValueFromRemainingArguments = $true)]$Args
    )
    process {
        $records = Read-OdinFixture -Module 'scheduled_tasks'
        $target = $null
        if ($InputObject -and $InputObject.TaskName) {
            $target = $records | Where-Object { $_.TaskName -eq $InputObject.TaskName } | Select-Object -First 1
        } elseif ($TaskName) {
            $target = $records | Where-Object { $_.TaskName -eq $TaskName } | Select-Object -First 1
        } else {
            $target = $records | Select-Object -First 1
        }
        if ($null -eq $target) { return }
        return [PSCustomObject]@{
            TaskName       = $target.TaskName
            LastRunTime    = $target.LastRunTime
            LastTaskResult = [int]$target.LastTaskResult
            NextRunTime    = $target.NextRunTime
        }
    }
}

function Get-Process {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments = $true)]$Args)
    $records = Read-OdinFixture -Module 'processes'
    return $records | ForEach-Object {
        [PSCustomObject]@{
            Id   = [int]$_.Id
            Name = $_.Name
            Path = $_.Path
        }
    }
}

function Get-Volume {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments = $true)]$Args)
    $records = Read-OdinFixture -Module 'mounts'
    return $records | ForEach-Object {
        [PSCustomObject]@{
            DriveLetter     = [char]($_.DriveLetter)
            FileSystemLabel = $_.FileSystemLabel
            FileSystem      = $_.FileSystem
            Size            = [int64]$_.Size
            SizeRemaining   = [int64]$_.SizeRemaining
        }
    }
}

function Get-PSDrive {
    [CmdletBinding()]
    param(
        [string]$PSProvider,
        [Parameter(ValueFromRemainingArguments = $true)]$Args
    )
    $records = Read-OdinFixture -Module 'mounts'
    return $records | ForEach-Object {
        $used = [int64]$_.Size - [int64]$_.SizeRemaining
        [PSCustomObject]@{
            Name = "$($_.DriveLetter)"
            Used = $used
            Free = [int64]$_.SizeRemaining
            Root = "$($_.DriveLetter):\"
        }
    }
}

function Get-ChildItem {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Path,
        [string]$LiteralPath,
        [string]$Filter,
        [switch]$Recurse,
        [switch]$File,
        [switch]$Directory,
        [Parameter(ValueFromRemainingArguments = $true)]$Args
    )
    # Resolve an effective path from -Path, -LiteralPath, or the first
    # positional arg forwarded into $Args. This keeps both forms working:
    #   Get-ChildItem -Path 'HKLM:\...'
    #   Get-ChildItem 'HKLM:\...'
    $effectivePath = $null
    if ($Path) { $effectivePath = $Path }
    elseif ($LiteralPath) { $effectivePath = $LiteralPath }
    elseif ($Args -and $Args.Count -gt 0 -and $Args[0] -is [string]) { $effectivePath = $Args[0] }

    if ($effectivePath -is [string] -and $effectivePath -like 'HKLM:\SOFTWARE*Uninstall*') {
        $packages = Read-OdinFixture -Module 'packages'
        return $packages | ForEach-Object {
            [PSCustomObject]@{
                PSPath               = "HKLM:\Uninstall\$($_.DisplayName)"
                __OdinFixtureRecord  = $_
            }
        }
    }
    # Forward to the real cmdlet. Reconstruct named parameters the caller
    # supplied so they reach the underlying provider.
    $forwarded = @{}
    if ($Path)        { $forwarded['Path']        = $Path }
    if ($LiteralPath) { $forwarded['LiteralPath'] = $LiteralPath }
    if ($Filter)      { $forwarded['Filter']      = $Filter }
    if ($Recurse)     { $forwarded['Recurse']     = $true }
    if ($File)        { $forwarded['File']        = $true }
    if ($Directory)   { $forwarded['Directory']   = $true }
    if ($Args -and $Args.Count -gt 0) {
        return Microsoft.PowerShell.Management\Get-ChildItem @forwarded @Args
    }
    return Microsoft.PowerShell.Management\Get-ChildItem @forwarded
}

function Get-ItemProperty {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]$InputObject,
        [Parameter(ValueFromRemainingArguments = $true)]$Args
    )
    process {
        if ($InputObject -and $InputObject.PSObject.Properties['__OdinFixtureRecord']) {
            return $InputObject.__OdinFixtureRecord
        }
        if ($InputObject) {
            return Microsoft.PowerShell.Management\Get-ItemProperty -InputObject $InputObject @Args
        }
        return Microsoft.PowerShell.Management\Get-ItemProperty @Args
    }
}

function Test-Path {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Path,
        [string]$LiteralPath,
        [Parameter(ValueFromRemainingArguments = $true)]$Args
    )
    $effectivePath = $null
    if ($Path) { $effectivePath = $Path }
    elseif ($LiteralPath) { $effectivePath = $LiteralPath }
    elseif ($Args -and $Args.Count -gt 0 -and $Args[0] -is [string]) { $effectivePath = $Args[0] }

    if ($effectivePath -is [string] -and $effectivePath -like 'HKLM:\SOFTWARE*Uninstall*') {
        if ($env:ODIN_TEST_FIXTURE) { return $true }
    }
    $forwarded = @{}
    if ($Path)        { $forwarded['Path']        = $Path }
    if ($LiteralPath) { $forwarded['LiteralPath'] = $LiteralPath }
    if ($Args -and $Args.Count -gt 0) {
        return Microsoft.PowerShell.Management\Test-Path @forwarded @Args
    }
    return Microsoft.PowerShell.Management\Test-Path @forwarded
}
