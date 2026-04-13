# TA-ODIN v1.0.0 - Windows services enumeration module
# Parity target: TA-ODIN/bin/modules/services.sh
# Emits: type=service service_name=<n> service_status=<s> service_enabled=<e>
# Cmdlets used (WIN-09 built-in only): Get-Service, Get-CimInstance Win32_Service
# Standalone run (D6): pwsh TA-ODIN/bin/modules/services.ps1
# Fail-soft: per-service try/catch; module-level try/catch around enumeration

. $PSScriptRoot/_common.ps1
Set-OdinContext
Initialize-OdinModuleState

try {
    $services = Get-Service -ErrorAction Stop

    # Fetch start-mode map in ONE Get-CimInstance call (batch - parity with
    # services.sh batch systemctl pattern).
    $startModeMap = @{}
    try {
        $cim = Get-CimInstance -ClassName Win32_Service -ErrorAction Stop
        foreach ($c in $cim) {
            $startModeMap[$c.Name] = $c.StartMode
        }
    } catch {
        # CIM not available - start mode will be "unknown" for every entry
        # (non-fatal, mirrors Linux fallback paths in services.sh).
    }

    foreach ($svc in $services) {
        try {
            $name = Format-OdinValue $svc.Name

            # Map PowerShell Status enum to lowercase parity string
            $statusRaw = [string]$svc.Status
            $status = switch ($statusRaw) {
                'Running'         { 'running' }
                'Stopped'         { 'stopped' }
                'Paused'          { 'paused' }
                'StartPending'    { 'starting' }
                'StopPending'     { 'stopping' }
                'ContinuePending' { 'resuming' }
                'PausePending'    { 'pausing' }
                default           {
                    if ($statusRaw) { $statusRaw.ToLower() } else { 'unknown' }
                }
            }

            # Map Win32_Service StartMode to parity string (enabled|disabled|unknown)
            $rawMode = $startModeMap[$svc.Name]
            $enabled = switch ($rawMode) {
                'Auto'     { 'enabled' }
                'Manual'   { 'enabled' }
                'Disabled' { 'disabled' }
                default    { 'unknown' }
            }

            Invoke-OdinEmit "type=service service_name=$name service_status=$status service_enabled=$enabled"
        } catch {
            # Per-entry fail-soft - one bad service cannot break enumeration.
            continue
        }
    }
} catch {
    # Module-level failure - rethrow so the orchestrator Start-Job wrapper
    # catches it and synthesizes type=odin_error module=services exit_code=1
    # (WIN-12 fail-soft at the orchestrator boundary).
    throw
}
