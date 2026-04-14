# TA-ODIN v1.0.0 - Windows process enumeration module
# Parity target: TA-ODIN/bin/modules/processes.sh
# Emits: type=process process_pid=<n> process_ppid=<n> process_user=<u>
#        process_state=<s> [process_cpu=<n>] [process_mem=<n>]
#        [process_elapsed=<n>] process_name=<n> [process_command=<c>]
# Cmdlets used (WIN-09 built-in only): Get-Process, Get-CimInstance Win32_Process
# Standalone run (D6): pwsh TA-ODIN/bin/modules/processes.ps1
#
# Variable discipline: uses $procPid rather than the PS automatic process-id
# variable to avoid PSAvoidAssignmentToAutomaticVariable analyzer violation.

. $PSScriptRoot/_common.ps1
Initialize-OdinContext
Initialize-OdinModuleState

try {
    # Batch CIM query - single Win32_Process call; avoids N+1 subprocess
    # spawning. Mirrors processes.sh's single-ps-call pattern.
    $cimMap = @{}
    try {
        $cim = Get-CimInstance -ClassName Win32_Process -ErrorAction Stop
        foreach ($c in $cim) {
            # ProcessId is the canonical key on Win32_Process; fall back to
            # fixture-stub Id field if ProcessId is absent.
            $keyId = $null
            if ($null -ne $c.ProcessId) { $keyId = [int]$c.ProcessId }
            elseif ($null -ne $c.Id)    { $keyId = [int]$c.Id }
            if ($null -ne $keyId)       { $cimMap[$keyId] = $c }
        }
    } catch {
        # CIM unavailable - fall back to Get-Process only (no ppid/command/user).
    }

    $procs = Get-Process -ErrorAction Stop

    foreach ($p in $procs) {
        try {
            $procPid = [int]$p.Id
            $name    = Format-OdinValue $p.Name

            # Defaults for optional fields
            $ppid    = 0
            $user    = 'unknown'
            $command = ''

            $cimProc = $cimMap[$procPid]
            if ($cimProc) {
                if ($null -ne $cimProc.ParentProcessId) {
                    $ppid = [int]$cimProc.ParentProcessId
                }
                if ($cimProc.CommandLine) {
                    $command = Format-OdinValue $cimProc.CommandLine
                }
                # GetOwner() is an Invoke-CimMethod call; may fail for
                # protected/system processes (csrss, lsass, ELAM drivers),
                # and is not present on fixture PSCustomObject stubs either.
                # Wrap defensively so one ACL-denied process cannot break
                # enumeration; fallback is literal 'unknown' - never guessed.
                $ownerResolved = $false
                try {
                    $owner = Invoke-CimMethod -InputObject $cimProc -MethodName GetOwner -ErrorAction Stop
                    if ($owner -and $owner.ReturnValue -eq 0) {
                        $u = if ($owner.Domain) { "$($owner.Domain)\$($owner.User)" } else { $owner.User }
                        if ($u) {
                            $user = Format-OdinValue $u
                            $ownerResolved = $true
                        }
                    }
                } catch {
                    # Swallow - owner stays 'unknown'.
                }
                # Fixture-stub compatibility: when Invoke-CimMethod can't act
                # on a PSCustomObject, fall back to a UserName property if
                # the object surface-carries one (stubs.ps1 Win32_Process
                # fixture records include UserName for ergonomics).
                if (-not $ownerResolved -and $cimProc.PSObject.Properties['UserName'] -and $cimProc.UserName) {
                    $user = Format-OdinValue $cimProc.UserName
                }
            }

            # State: Get-Process does not expose a real state enum on Windows;
            # processes visible to Get-Process are running. Stopped/zombie
            # states are Linux-only semantics.
            $state = 'running'

            # Metrics - best effort from Get-Process. We ALWAYS emit these
            # fields (defaulting to 0) to maintain field-name parity with
            # Linux ps -o %cpu,rss,etime which also always populates them.
            # Nyquist Dim 5 diffs field names, not values.
            $cpu = '0'
            try {
                if ($null -ne $p.CPU) {
                    $cpu = [math]::Round([double]$p.CPU, 2).ToString()
                }
            } catch { }

            $mem = '0'
            try {
                if ($null -ne $p.WorkingSet64) {
                    $mem = [string][int]([long]$p.WorkingSet64 / 1024)
                }
            } catch { }

            $elapsed = '0'
            try {
                if ($p.StartTime) {
                    $elapsed = [string][int]((Get-Date) - $p.StartTime).TotalSeconds
                }
            } catch {
                # Access denied on protected processes - keep default 0.
            }

            # Always emit the full parity field set. process_command falls
            # back to the process name when CIM did not supply a command
            # line - parity with Linux ps which prints the short name in
            # the args column for kernel and thread-only processes.
            if (-not $command) { $command = $name }
            $line = "type=process process_pid=$procPid process_ppid=$ppid process_user=$user process_state=$state process_cpu=$cpu process_mem=$mem process_elapsed=$elapsed process_name=$name process_command=$command"
            Invoke-OdinEmit $line
        } catch {
            continue
        }
    }
} catch {
    throw
}
