#!/bin/bash
#
# TA-ODIN Module: Process Enumeration
# Enumerates all running processes via ps.
#
# Output fields:
#   type=process process_pid= process_ppid= process_user= process_state=
#   process_cpu= process_mem= process_elapsed= process_name= process_command=
#
# Guardrails:
#   - timeout 30s on ps commands
#   - Single ps invocation (capture once, parse from output)
#

# Force C locale for consistent command output parsing
export LC_ALL=C

# Use orchestrator functions if available, otherwise define standalone versions
if ! declare -f emit &>/dev/null; then
    # shellcheck source=/dev/null  # _common.sh resolved via dirname BASH_SOURCE
    source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
fi

# Helper: escape and quote values with spaces
safe_val() {
    local val="$1"
    val="${val//\"/\\\"}"
    if [[ "$val" == *" "* ]]; then
        echo "\"$val\""
    else
        echo "$val"
    fi
}

emitted=0

# Try GNU ps first — capture output once, then parse
ps_output=$(timeout 30 ps -eo pid,ppid,user,stat,%cpu,%mem,etime,comm,args --no-headers 2>/dev/null)

if [[ $? -eq 0 && -n "$ps_output" ]]; then
    # GNU ps: PID PPID USER STAT %CPU %MEM ELAPSED COMM ARGS
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        read -r pid ppid user stat cpu mem elapsed comm args <<< "$line"

        [[ -z "$pid" ]] && continue

        out="type=process process_pid=$pid process_ppid=$ppid process_user=$user process_state=$stat process_cpu=$cpu process_mem=$mem process_elapsed=$elapsed process_name=$comm"
        [[ -n "$args" ]] && out="$out process_command=$(safe_val "$args")"
        emit "$out"
        emitted=1
    done <<< "$ps_output"
else
    # BusyBox/minimal ps fallback: limited fields available
    ps_output=$(timeout 30 ps -o pid,ppid,user,stat,comm,args 2>/dev/null)

    if [[ $? -eq 0 && -n "$ps_output" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            read -r pid ppid user stat comm args <<< "$line"

            [[ -z "$pid" || "$pid" == "PID" ]] && continue

            out="type=process process_pid=$pid process_ppid=$ppid process_user=$user process_state=$stat process_name=$comm"
            [[ -n "$args" ]] && out="$out process_command=$(safe_val "$args")"
            emit "$out"
            emitted=1
        done <<< "$ps_output"
    else
        # Absolute fallback: basic ps with default output
        ps_output=$(timeout 30 ps -ef 2>/dev/null)
        [[ -z "$ps_output" ]] && ps_output=$(timeout 30 ps aux 2>/dev/null)

        if [[ -n "$ps_output" ]]; then
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue

                read -r pid user args <<< "$line"

                [[ -z "$pid" || "$pid" == "PID" ]] && continue

                # Extract process name as basename of first word in args
                comm="${args%% *}"
                comm="${comm##*/}"

                out="type=process process_pid=$pid process_user=$user process_name=$comm"
                [[ -n "$args" ]] && out="$out process_command=$(safe_val "$args")"
                emit "$out"
                emitted=1
            done <<< "$ps_output"
        fi
    fi
fi

# Emit none_found if no processes were discovered
if [[ $emitted -eq 0 ]]; then
    emit "type=none_found module=processes message=\"No running processes found\""
fi

exit 0
