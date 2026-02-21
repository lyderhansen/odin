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

# ps output: PID PPID USER STAT %CPU %MEM ELAPSED COMM ARGS
# ARGS can contain spaces, so we handle it carefully
ps -eo pid,ppid,user,stat,%cpu,%mem,etime,comm,args --no-headers 2>/dev/null | while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # Parse fixed-width fields, then everything remaining is args
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
done

exit 0
