# TA-ODIN v1.0.0 - Windows scheduled tasks enumeration module
# Parity target: TA-ODIN/bin/modules/cron.sh (semantic parallel, different label)
# Emits: type=scheduled_task task_name=<n> task_path=<p> task_state=<s>
#        [task_author=<a>] [task_last_run=<t>] [task_next_run=<t>] [task_last_result=<n>]
#
# NOTE on field names: Linux emits type=cron with cron_* prefix. Windows
# emits type=scheduled_task with task_* prefix. This is the ONE intentional
# field-name divergence in Phase 1, documented in CONTEXT.md D6. Dimension
# 5 of the Nyquist harness explicitly SKIPs type=scheduled_task parity with
# a logged rationale; all other type=* events must have identical field sets.
#
# Cmdlets used (WIN-09 built-in only): Get-ScheduledTask, Get-ScheduledTaskInfo
# Standalone run (D6): pwsh TA-ODIN/bin/modules/scheduled_tasks.ps1

. $PSScriptRoot/_common.ps1
Initialize-OdinContext
Initialize-OdinModuleState

try {
    $tasks = @()
    try {
        $tasks = Get-ScheduledTask -ErrorAction Stop
    } catch {
        # ScheduledTasks module not present (very old Windows). Fail-soft.
        return
    }

    foreach ($t in $tasks) {
        try {
            $name   = Format-OdinValue $t.TaskName
            $path   = Format-OdinValue $t.TaskPath
            $stateRaw = [string]$t.State
            $state  = Format-OdinValue ($stateRaw.ToLower())
            $author = if ($t.Author) { Format-OdinValue $t.Author } else { '' }

            # Get-ScheduledTaskInfo enriches with LastRunTime/NextRunTime/LastTaskResult
            $lastRun = ''
            $nextRun = ''
            $lastRes = ''
            try {
                $info = Get-ScheduledTaskInfo -InputObject $t -ErrorAction Stop
                if ($info.LastRunTime) {
                    $lrt = $info.LastRunTime
                    if ($lrt -isnot [datetime]) { $lrt = [datetime]$lrt }
                    $lastRun = $lrt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
                if ($info.NextRunTime) {
                    $nrt = $info.NextRunTime
                    if ($nrt -isnot [datetime]) { $nrt = [datetime]$nrt }
                    $nextRun = $nrt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
                if ($null -ne $info.LastTaskResult) {
                    $lastRes = [string]$info.LastTaskResult
                }
            } catch {
                # Enrichment is best-effort; emit core fields only.
            }

            $line = "type=scheduled_task task_name=$name task_path=$path task_state=$state"
            if ($author)           { $line = "$line task_author=$author" }
            if ($lastRun)          { $line = "$line task_last_run=$lastRun" }
            if ($nextRun)          { $line = "$line task_next_run=$nextRun" }
            if ($lastRes -ne '')   { $line = "$line task_last_result=$lastRes" }
            Invoke-OdinEmit $line
        } catch {
            continue
        }
    }
} catch {
    throw
}
