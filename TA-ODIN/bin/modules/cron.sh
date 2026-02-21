#!/bin/bash
#
# TA-ODIN Module: Cron/Scheduled Task Enumeration
# Enumerates crontabs, cron directories, systemd timers, and anacron jobs.
#
# Output fields:
#   type=cron cron_source= cron_user= cron_schedule= cron_command= cron_file=
#

# Force C locale for consistent command output parsing
export LC_ALL=C

# Use orchestrator functions if available, otherwise define standalone versions
if ! declare -f emit &>/dev/null; then
    ODIN_HOSTNAME="${ODIN_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}"
    ODIN_OS="${ODIN_OS:-linux}"
    ODIN_RUN_ID="${ODIN_RUN_ID:-standalone-$$}"
    ODIN_VERSION="${ODIN_VERSION:-2.0.0}"
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
    emit() { echo "timestamp=$(get_timestamp) hostname=$ODIN_HOSTNAME os=$ODIN_OS run_id=$ODIN_RUN_ID odin_version=$ODIN_VERSION $*"; }
fi

# Helper: escape double quotes in a value and wrap if it contains spaces
safe_val() {
    local val="$1"
    val="${val//\"/\\\"}"
    if [[ "$val" == *" "* ]]; then
        echo "\"$val\""
    else
        echo "$val"
    fi
}

# Parse a crontab-format line into schedule and command (user crontabs, no user field)
# Standard cron: min hour dom month dow command
# Supports @reboot, @daily etc.
parse_cron_line() {
    local line="$1"
    local user="$2"
    local source="$3"
    local file="$4"

    # Skip empty lines, comments, and variable assignments
    [[ -z "$line" ]] && return
    [[ "$line" =~ ^[[:space:]]*# ]] && return
    [[ "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z_0-9]*= ]] && return

    local schedule=""
    local command=""

    if [[ "$line" =~ ^[[:space:]]*@ ]]; then
        # Special schedule: @reboot command...
        read -r schedule command <<< "$line"
    else
        # Standard 5-field schedule: min hour dom month dow command...
        read -r f1 f2 f3 f4 f5 command <<< "$line"
        schedule="$f1 $f2 $f3 $f4 $f5"
    fi

    [[ -z "$command" ]] && return

    local out="type=cron cron_source=$source"
    [[ -n "$user" ]] && out="$out cron_user=$user"
    [[ -n "$schedule" ]] && out="$out cron_schedule=$(safe_val "$schedule")"
    [[ -n "$command" ]] && out="$out cron_command=$(safe_val "$command")"
    [[ -n "$file" ]] && out="$out cron_file=$file"
    emit "$out"
    emitted=1
}

# Parse a system crontab line (has user field between schedule and command)
# Format: min hour dom month dow user command
parse_system_cron_line() {
    local line="$1"
    local source="$2"
    local file="$3"

    # Skip empty lines, comments, and variable assignments
    [[ -z "$line" ]] && return
    [[ "$line" =~ ^[[:space:]]*# ]] && return
    [[ "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z_0-9]*= ]] && return

    local schedule=""
    local user=""
    local command=""

    if [[ "$line" =~ ^[[:space:]]*@ ]]; then
        # Special schedule: @reboot user command...
        read -r schedule user command <<< "$line"
    else
        # Standard: min hour dom month dow user command...
        read -r f1 f2 f3 f4 f5 user command <<< "$line"
        schedule="$f1 $f2 $f3 $f4 $f5"
    fi

    [[ -z "$command" ]] && return

    local out="type=cron cron_source=$source cron_user=$user cron_schedule=$(safe_val "$schedule") cron_command=$(safe_val "$command") cron_file=$file"
    emit "$out"
    emitted=1
}

emitted=0

# --- /etc/crontab (system crontab, has user field) ---
if [[ -f /etc/crontab ]]; then
    while IFS= read -r line; do
        parse_system_cron_line "$line" "system_crontab" "/etc/crontab"
    done < /etc/crontab
fi

# --- /etc/cron.d/* (drop-in crontabs, have user field like /etc/crontab) ---
if [[ -d /etc/cron.d ]]; then
    for cronfile in /etc/cron.d/*; do
        [[ ! -f "$cronfile" ]] && continue
        while IFS= read -r line; do
            parse_system_cron_line "$line" "cron.d" "$cronfile"
        done < "$cronfile"
    done
fi

# --- User crontabs ---
if [[ -d /var/spool/cron/crontabs ]]; then
    crontab_dir="/var/spool/cron/crontabs"
elif [[ -d /var/spool/cron ]]; then
    crontab_dir="/var/spool/cron"
else
    crontab_dir=""
fi

if [[ -n "$crontab_dir" ]]; then
    for userfile in "$crontab_dir"/*; do
        [[ ! -f "$userfile" ]] && continue
        user=$(basename "$userfile")
        while IFS= read -r line; do
            parse_cron_line "$line" "$user" "user_crontab" "$userfile"
        done < "$userfile" 2>/dev/null
    done
fi

# --- cron.daily/hourly/weekly/monthly ---
for period in hourly daily weekly monthly; do
    dir="/etc/cron.$period"
    [[ ! -d "$dir" ]] && continue
    for script in "$dir"/*; do
        [[ ! -f "$script" ]] && continue
        script_name=$(basename "$script")
        [[ "$script_name" == .placeholder ]] && continue
        emit "type=cron cron_source=cron.$period cron_schedule=@$period cron_command=$script_name cron_file=$script"
        emitted=1
    done
done

# --- Systemd timers ---
if command -v systemctl &>/dev/null; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Timer unit and activated unit are the last two fields
        # list-timers has variable-width date/time columns, so use array indexing
        words=($line)
        len=${#words[@]}
        [[ $len -lt 2 ]] && continue
        timer_unit="${words[$((len-2))]}"
        activated_unit="${words[$((len-1))]}"

        [[ -z "$timer_unit" || "$timer_unit" == "UNIT" ]] && continue

        # Get the timer's schedule from the unit file
        schedule=$(systemctl show "$timer_unit" -p TimersCalendar 2>/dev/null | sed 's/TimersCalendar=//')
        if [[ -z "$schedule" || "$schedule" == "" ]]; then
            schedule=$(systemctl show "$timer_unit" -p TimersMonotonic 2>/dev/null | sed 's/TimersMonotonic=//')
        fi

        out="type=cron cron_source=systemd_timer cron_command=$activated_unit"
        [[ -n "$schedule" ]] && out="$out cron_schedule=$(safe_val "$schedule")"
        out="$out cron_file=$timer_unit"
        emit "$out"
        emitted=1
    done < <(systemctl list-timers --all --no-pager --no-legend 2>/dev/null)
fi

# --- Anacron ---
if [[ -f /etc/anacrontab ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z_0-9]*= ]] && continue

        # Format: period delay job-identifier command
        read -r period delay job_id command <<< "$line"

        [[ -z "$command" ]] && continue
        emit "type=cron cron_source=anacron cron_schedule=\"period=${period}d delay=${delay}m\" cron_command=$(safe_val "$command") cron_file=/etc/anacrontab"
        emitted=1
    done < /etc/anacrontab
fi

# Emit none_found if no scheduled tasks were discovered
if [[ $emitted -eq 0 ]]; then
    emit "type=none_found module=cron message=\"No scheduled tasks found\""
fi

exit 0
