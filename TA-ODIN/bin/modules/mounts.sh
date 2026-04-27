#!/bin/bash
#
# TA-ODIN Module: Filesystem/Mount Enumeration
# Enumerates all mounted filesystems using df with a timeout for hung NFS mounts.
#
# Output fields:
#   type=mount mount_device= mount_point= mount_type= mount_size_kb=
#   mount_used_kb= mount_avail_kb= mount_use_pct=
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

# Use timeout to prevent hangs on unresponsive NFS mounts (if timeout is available)
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

read -ra df_args <<< "$df_cmd"
if [[ $has_timeout -eq 1 ]]; then
    df_output=$(timeout 30 "${df_args[@]}" 2>/dev/null)
    df_rc=$?
else
    df_output=$("${df_args[@]}" 2>/dev/null)
    df_rc=$?
fi

if [[ $df_rc -eq 124 ]]; then
    emit "type=mount_error message=\"df command timed out after 30 seconds (possible hung NFS mount)\""
fi

emitted=0

if [[ -n "$df_output" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        if [[ $has_fstype -eq 1 ]]; then
            # df -PT output: Filesystem Type Size Used Avail Use% Mounted-on
            # read -r assigns everything from field 7 onwards to mount_point (handles spaces)
            read -r device fstype size_kb used_kb avail_kb use_pct mount_point <<< "$line"
        else
            # df -P output (no type): Filesystem Size Used Avail Use% Mounted-on
            read -r device size_kb used_kb avail_kb use_pct mount_point <<< "$line"
            fstype="unknown"
        fi

        # Strip % from use_pct
        use_pct="${use_pct%\%}"

        [[ -z "$device" || "$device" == "Filesystem" ]] && continue

        out="type=mount mount_device=$(safe_val "$device") mount_point=$(safe_val "$mount_point") mount_type=$fstype mount_size_kb=$size_kb mount_used_kb=$used_kb mount_avail_kb=$avail_kb mount_use_pct=$use_pct"
        emit "$out"
        emitted=1
    done < <(echo "$df_output" | tail -n +2)
fi

# Emit none_found if no mounts were discovered
if [[ $emitted -eq 0 ]]; then
    emit "type=none_found module=mounts message=\"No filesystem mounts discovered\""
fi

exit 0
