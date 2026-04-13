# TA-ODIN v1.0.0 - Windows filesystem volumes enumeration module
# Parity target: TA-ODIN/bin/modules/mounts.sh
# Emits: type=mount mount_device=<d> mount_point=<p> mount_type=<t>
#        mount_size_kb=<n> mount_used_kb=<n> mount_avail_kb=<n> mount_use_pct=<n>
#
# Strategy: Prefer Get-Volume (Windows 8+/Server 2012+). Fall back to
# Get-PSDrive -PSProvider FileSystem when the Storage module is absent.
#
# PS 5.1 COMPAT: No null-coalescing operator; uses explicit if/else.
#
# Cmdlets used (WIN-09 built-in only): Get-Volume, Get-PSDrive
# Standalone run (D6): pwsh TA-ODIN/bin/modules/mounts.ps1

. $PSScriptRoot/_common.ps1
Set-OdinContext
Initialize-OdinModuleState

function Convert-OdinBytesToKb {
    param([Parameter(Mandatory = $true)][AllowNull()]$Bytes)
    if ($null -eq $Bytes) { return 0 }
    try {
        return [int]([long]$Bytes / 1024)
    } catch {
        return 0
    }
}

$emittedPoints = @{}
$primaryWorked = $false

try {
    $vols = @()
    try {
        $vols = Get-Volume -ErrorAction Stop
        $primaryWorked = $true
    } catch {
        # Storage module unavailable - fall through to Get-PSDrive branch.
    }

    foreach ($v in $vols) {
        try {
            $point = ''
            if ($v.DriveLetter) {
                $point = "$($v.DriveLetter):\"
            } elseif ($v.Path) {
                $point = [string]$v.Path
            }
            if (-not $point) { continue }

            $device = if ($v.FileSystemLabel) { Format-OdinValue $v.FileSystemLabel } else { Format-OdinValue $point }
            $mountPt = Format-OdinValue $point
            $fsType = if ($v.FileSystem) { Format-OdinValue $v.FileSystem } else { 'unknown' }
            $sizeKb = Convert-OdinBytesToKb $v.Size
            $avail  = Convert-OdinBytesToKb $v.SizeRemaining
            $usedKb = $sizeKb - $avail
            if ($usedKb -lt 0) { $usedKb = 0 }
            $usePct = if ($sizeKb -gt 0) { [int](($usedKb * 100) / $sizeKb) } else { 0 }

            $emittedPoints[$point] = $true
            Invoke-OdinEmit "type=mount mount_device=$device mount_point=$mountPt mount_type=$fsType mount_size_kb=$sizeKb mount_used_kb=$usedKb mount_avail_kb=$avail mount_use_pct=$usePct"
        } catch {
            continue
        }
    }

    # Fallback: Get-PSDrive -PSProvider FileSystem when Get-Volume did not
    # work. This branch intentionally runs only when the primary branch
    # failed entirely (not as a supplement), to avoid double-emitting the
    # same mount point.
    if (-not $primaryWorked) {
        try {
            $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction Stop
            foreach ($d in $drives) {
                try {
                    $point = "$($d.Name):\"
                    if ($emittedPoints.ContainsKey($point)) { continue }

                    # PS 5.1 compat: explicit if/else (no null-coalescing operator)
                    $device = if ($d.DisplayRoot) { Format-OdinValue $d.DisplayRoot } else { Format-OdinValue $point }
                    $mountPt = Format-OdinValue $point
                    $fsType = 'unknown'
                    $sizeKb = Convert-OdinBytesToKb ($d.Used + $d.Free)
                    $usedKb = Convert-OdinBytesToKb $d.Used
                    $avail  = Convert-OdinBytesToKb $d.Free
                    $usePct = if ($sizeKb -gt 0) { [int](($usedKb * 100) / $sizeKb) } else { 0 }

                    Invoke-OdinEmit "type=mount mount_device=$device mount_point=$mountPt mount_type=$fsType mount_size_kb=$sizeKb mount_used_kb=$usedKb mount_avail_kb=$avail mount_use_pct=$usePct"
                } catch {
                    continue
                }
            }
        } catch {
            # Both providers failed - emit nothing, fail-soft.
        }
    }
} catch {
    throw
}
