# TA-ODIN v1.0.0 - Windows installed packages enumeration module
# Parity target: TA-ODIN/bin/modules/packages.sh
# Emits: type=package package_name=<n> package_version=<v> [package_arch=<a>] package_manager=registry
#
# ABSOLUTE PROHIBITION (WIN-04, RESEARCH.md §4): This module MUST NOT reference
# the deprecated MSI product-repair class under any circumstance. Touching that
# class triggers a fleet-wide MSI self-repair consistency check that rewrites
# every installed MSI's ProductState, can take 5-30 minutes per host, and has
# historically taken down production fleets. Nyquist Dimension 3 of the
# windows-parity-harness greps for that class name in THIS file specifically
# and fails the build if it finds any match.
#
# Enumeration strategy: Read HKLM Uninstall keys (both native and WOW64) via
# Get-ChildItem + Get-ItemProperty. This is the same mechanism Add/Remove
# Programs uses; it is non-invasive and cannot trigger MSI repair.
#
# Cmdlets used (WIN-09 built-in only): Get-ChildItem, Get-ItemProperty, Test-Path
# Standalone run (D6): pwsh TA-ODIN/bin/modules/packages.ps1

. $PSScriptRoot/_common.ps1
Initialize-OdinContext
Initialize-OdinModuleState

$uninstallPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

foreach ($path in $uninstallPaths) {
    try {
        if (-not (Test-Path -Path $path)) { continue }
        $keys = Get-ChildItem -Path $path -ErrorAction Stop
    } catch {
        # Hive path unreadable - defensively continue (WIN-11 fail-soft).
        continue
    }

    foreach ($key in $keys) {
        try {
            # Pipe the key into Get-ItemProperty rather than passing -Path;
            # this is the idiomatic form the Uninstall hive responds to and
            # is the one the fixture stubs also honor through their pipeline
            # InputObject parameter.
            $props = $key | Get-ItemProperty -ErrorAction Stop

            # Filter: skip hidden system components and patches/updates so the
            # emitted set matches what Add/Remove Programs shows to an admin.
            if ($props.SystemComponent -eq 1) { continue }
            if ($props.PSObject.Properties.Name -contains 'ParentKeyName' -and $props.ParentKeyName) { continue }

            $displayName = $props.DisplayName
            if (-not $displayName) { continue }  # Unnamed entries are installer leftovers

            $name = Format-OdinValue $displayName
            $version = if ($props.DisplayVersion) { Format-OdinValue $props.DisplayVersion } else { 'unknown' }

            # Infer architecture from the hive branch: Wow6432Node = x86 on
            # 64-bit host; native branch = x64/native. Parity with packages.sh
            # which emits package_arch for dpkg/rpm paths.
            $arch = if ($path -like '*Wow6432Node*') { 'x86' } else { 'x64' }

            $line = "type=package package_name=$name package_version=$version package_arch=$arch package_manager=registry"
            Invoke-OdinEmit $line
        } catch {
            # Per-entry fail-soft - one corrupt registry value cannot break
            # enumeration of the remaining keys.
            continue
        }
    }
}
