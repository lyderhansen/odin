# TA-ODIN v1.0.1 - Windows listening ports enumeration module
# Parity target: TA-ODIN/bin/modules/ports.sh
# Emits: type=port transport=<tcp|udp> listen_address=<ip> listen_port=<n>
#        [process_name=<n>] [process_pid=<n>]
# Cmdlets used (WIN-09 built-in only): Get-NetTCPConnection, Get-NetUDPEndpoint,
#                                       Get-Process
# Standalone run (D6): pwsh TA-ODIN/bin/modules/ports.ps1
#
# Variable discipline: uses $procPid rather than the PS automatic process-id
# variable to avoid PSAvoidAssignmentToAutomaticVariable analyzer violation.

. $PSScriptRoot/_common.ps1
Initialize-OdinContext
Initialize-OdinModuleState

try {
    # ----------------------------------------------------------------------
    # TCP listeners
    # ----------------------------------------------------------------------
    $tcp = @()
    try {
        $tcp = Get-NetTCPConnection -State Listen -ErrorAction Stop
    } catch {
        # NetTCPIP module not available - Windows 7 / locked-down images.
        # Parity with Linux ss/netstat fallback: emit nothing and continue.
        $null = $_
    }

    foreach ($c in $tcp) {
        try {
            $addr = Format-OdinValue $c.LocalAddress
            $port = $c.LocalPort
            $line = "type=port transport=tcp listen_address=$addr listen_port=$port"
            $procPid = $c.OwningProcess
            if ($procPid -and $procPid -gt 0) {
                try {
                    $proc = @(Get-Process -Id $procPid -ErrorAction Stop) | Select-Object -First 1
                    $pname = Format-OdinValue $proc.Name
                    $line = "$line process_name=$pname process_pid=$procPid"
                } catch {
                    # Process exited between enumerations - emit the port event
                    # with pid only (parity with Linux ss racy-PID behavior).
                    $line = "$line process_pid=$procPid"
                }
            }
            Invoke-OdinEmit $line
        } catch {
            continue
        }
    }

    # ----------------------------------------------------------------------
    # UDP endpoints
    # ----------------------------------------------------------------------
    $udp = @()
    try {
        $udp = Get-NetUDPEndpoint -ErrorAction Stop
    } catch {
        # Same defensive fallback as TCP branch
        $null = $_
    }

    foreach ($u in $udp) {
        try {
            $addr = Format-OdinValue $u.LocalAddress
            $port = $u.LocalPort
            $line = "type=port transport=udp listen_address=$addr listen_port=$port"
            $procPid = $u.OwningProcess
            if ($procPid -and $procPid -gt 0) {
                try {
                    $proc = @(Get-Process -Id $procPid -ErrorAction Stop) | Select-Object -First 1
                    $pname = Format-OdinValue $proc.Name
                    $line = "$line process_name=$pname process_pid=$procPid"
                } catch {
                    $line = "$line process_pid=$procPid"
                }
            }
            Invoke-OdinEmit $line
        } catch {
            continue
        }
    }
} catch {
    throw
}
