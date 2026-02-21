#!/bin/bash
#
# TA-ODIN Module: Filesystem/Mount Enumeration
# Enumerates all mounted filesystems using df with a timeout for hung NFS mounts.
#
# Output fields:
#   event_type=mount mount_device= mount_point= mount_type= mount_size_kb=
#   mount_used_kb= mount_avail_kb= mount_use_pct=
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

# Use timeout to prevent hangs on unresponsive NFS mounts (if timeout is available)
# df -PT: P=POSIX output, T=print filesystem type
# Fallback chain: df -PT -> df -P -> df (for BusyBox/minimal systems)
has_timeout=0
command -v timeout >/dev/null 2>&1 && has_timeout=1

# Determine which df flags are supported
df_cmd=""
if df -PT / >/dev/null 2>&1; then
    df_cmd="df -PT"
    has_fstype=1
elif df -P / >/dev/null 2>&1; then
    df_cmd="df -P"
    has_fstype=0
else
    df_cmd="df"
    has_fstype=0
fi

if [[ $has_timeout -eq 1 ]]; then
    df_output=$(timeout 30 $df_cmd 2>/dev/null)
    df_rc=$?
else
    df_output=$($df_cmd 2>/dev/null)
    df_rc=$?
fi

if [[ $df_rc -eq 124 ]]; then
    emit "event_type=mount_error message=\"df command timed out after 30 seconds (possible hung NFS mount)\""
fi

emitted=0

if [[ -n "$df_output" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        if [[ $has_fstype -eq 1 ]]; then
            # df -PT output: Filesystem Type Size Used Avail Use% Mounted
            device=$(echo "$line" | awk '{print $1}')
            fstype=$(echo "$line" | awk '{print $2}')
            size_kb=$(echo "$line" | awk '{print $3}')
            used_kb=$(echo "$line" | awk '{print $4}')
            avail_kb=$(echo "$line" | awk '{print $5}')
            use_pct=$(echo "$line" | awk '{print $6}' | tr -d '%')
            mount_point=$(echo "$line" | awk '{print $7}')
        else
            # df -P output (no type): Filesystem Size Used Avail Use% Mounted
            device=$(echo "$line" | awk '{print $1}')
            fstype="unknown"
            size_kb=$(echo "$line" | awk '{print $2}')
            used_kb=$(echo "$line" | awk '{print $3}')
            avail_kb=$(echo "$line" | awk '{print $4}')
            use_pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
            mount_point=$(echo "$line" | awk '{print $6}')
        fi

        [[ -z "$device" || "$device" == "Filesystem" ]] && continue

        out="event_type=mount mount_device=$(safe_val "$device") mount_point=$(safe_val "$mount_point") mount_type=$fstype mount_size_kb=$size_kb mount_used_kb=$used_kb mount_avail_kb=$avail_kb mount_use_pct=$use_pct"
        emit "$out"
        emitted=1
    done < <(echo "$df_output" | tail -n +2)
fi

# Emit none_found if no mounts were discovered
if [[ $emitted -eq 0 ]]; then
    emit "event_type=none_found module=mounts message=\"No filesystem mounts discovered\""
fi

exit 0
