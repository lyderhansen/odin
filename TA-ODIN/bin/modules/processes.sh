#!/bin/bash
#
# TA-ODIN Module: Process Enumeration
# Enumerates all running processes via ps.
#
# Output fields:
#   event_type=process process_pid= process_ppid= process_user= process_state=
#   process_cpu= process_mem= process_elapsed= process_name= process_command=
#

# Use orchestrator functions if available, otherwise define standalone versions
if ! declare -f emit &>/dev/null; then
    ODIN_HOSTNAME="${ODIN_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}"
    ODIN_OS="${ODIN_OS:-linux}"
    ODIN_RUN_ID="${ODIN_RUN_ID:-standalone-$$}"
    ODIN_VERSION="${ODIN_VERSION:-2.0.0}"
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
    emit() { echo "timestamp=$(get_timestamp) hostname=$ODIN_HOSTNAME os=$ODIN_OS run_id=$ODIN_RUN_ID odin_version=$ODIN_VERSION $*"; }
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

# Try GNU ps first (full output), fall back to basic ps for BusyBox/minimal systems
emitted=0

# Test if GNU ps -eo is supported
if ps -eo pid,ppid,user,stat,%cpu,%mem,etime,comm,args --no-headers >/dev/null 2>&1; then
    # GNU ps: PID PPID USER STAT %CPU %MEM ELAPSED COMM ARGS
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        pid=$(echo "$line" | awk '{print $1}')
        ppid=$(echo "$line" | awk '{print $2}')
        user=$(echo "$line" | awk '{print $3}')
        stat=$(echo "$line" | awk '{print $4}')
        cpu=$(echo "$line" | awk '{print $5}')
        mem=$(echo "$line" | awk '{print $6}')
        elapsed=$(echo "$line" | awk '{print $7}')
        comm=$(echo "$line" | awk '{print $8}')
        args=$(echo "$line" | awk '{for(i=9;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')

        [[ -z "$pid" ]] && continue

        out="event_type=process process_pid=$pid process_ppid=$ppid process_user=$user process_state=$stat process_cpu=$cpu process_mem=$mem process_elapsed=$elapsed process_name=$comm"
        [[ -n "$args" ]] && out="$out process_command=$(safe_val "$args")"
        emit "$out"
        emitted=1
    done < <(ps -eo pid,ppid,user,stat,%cpu,%mem,etime,comm,args --no-headers 2>/dev/null)
else
    # BusyBox/minimal ps fallback: limited fields available
    # BusyBox ps -o may support: pid,ppid,user,stat,comm,args (but not %cpu,%mem,etime)
    if ps -o pid,ppid,user,stat,comm,args 2>/dev/null | head -1 >/dev/null 2>&1; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            pid=$(echo "$line" | awk '{print $1}')
            ppid=$(echo "$line" | awk '{print $2}')
            user=$(echo "$line" | awk '{print $3}')
            stat=$(echo "$line" | awk '{print $4}')
            comm=$(echo "$line" | awk '{print $5}')
            args=$(echo "$line" | awk '{for(i=6;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')

            [[ -z "$pid" || "$pid" == "PID" ]] && continue

            out="event_type=process process_pid=$pid process_ppid=$ppid process_user=$user process_state=$stat process_name=$comm"
            [[ -n "$args" ]] && out="$out process_command=$(safe_val "$args")"
            emit "$out"
            emitted=1
        done < <(ps -o pid,ppid,user,stat,comm,args 2>/dev/null)
    else
        # Absolute fallback: basic ps with default output
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            pid=$(echo "$line" | awk '{print $1}')
            user=$(echo "$line" | awk '{print $2}')
            args=$(echo "$line" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')

            [[ -z "$pid" || "$pid" == "PID" ]] && continue

            # Extract process name from command
            comm=$(echo "$args" | awk '{print $1}')
            comm="${comm##*/}"

            out="event_type=process process_pid=$pid process_user=$user process_name=$comm"
            [[ -n "$args" ]] && out="$out process_command=$(safe_val "$args")"
            emit "$out"
            emitted=1
        done < <(ps -ef 2>/dev/null || ps aux 2>/dev/null)
    fi
fi

# Emit none_found if no processes were discovered
if [[ $emitted -eq 0 ]]; then
    emit "event_type=none_found module=processes message=\"No running processes found\""
fi

exit 0
