#!/bin/bash
#
# TA-ODIN Module: Cron/Scheduled Task Enumeration
# Enumerates crontabs, cron directories, systemd timers, and anacron jobs.
#
# Output fields:
#   event_type=cron cron_source= cron_user= cron_schedule= cron_command= cron_file=
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

# Helper: escape double quotes in a value and wrap if it contains spaces
safe_val() {
    local val="$1"
    # Replace double quotes with escaped quotes
    val="${val//\"/\\\"}"
    # If value contains spaces, wrap in quotes
    if [[ "$val" == *" "* ]]; then
        echo "\"$val\""
    else
        echo "$val"
    fi
}

# Parse a crontab-format line into schedule and command
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
        # Special schedule: @reboot, @daily, etc.
        schedule=$(echo "$line" | awk '{print $1}')
        command=$(echo "$line" | awk '{for(i=2;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
    else
        # Standard 5-field schedule
        schedule=$(echo "$line" | awk '{printf "%s %s %s %s %s", $1, $2, $3, $4, $5}')
        command=$(echo "$line" | awk '{for(i=6;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
    fi

    [[ -z "$command" ]] && return

    local out="event_type=cron cron_source=$source"
    [[ -n "$user" ]] && out="$out cron_user=$user"
    [[ -n "$schedule" ]] && out="$out cron_schedule=$(safe_val "$schedule")"
    [[ -n "$command" ]] && out="$out cron_command=$(safe_val "$command")"
    [[ -n "$file" ]] && out="$out cron_file=$file"
    emit "$out"
}

# --- /etc/crontab (system crontab, has user field) ---
if [[ -f /etc/crontab ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z_0-9]*= ]] && continue

        if [[ "$line" =~ ^[[:space:]]*@ ]]; then
            user=$(echo "$line" | awk '{print $2}')
            command=$(echo "$line" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
            schedule=$(echo "$line" | awk '{print $1}')
            [[ -z "$command" ]] && continue
            out="event_type=cron cron_source=system_crontab cron_user=$user cron_schedule=$(safe_val "$schedule") cron_command=$(safe_val "$command") cron_file=/etc/crontab"
            emit "$out"
        else
            # Standard 5-field + user + command
            schedule=$(echo "$line" | awk '{printf "%s %s %s %s %s", $1, $2, $3, $4, $5}')
            user=$(echo "$line" | awk '{print $6}')
            command=$(echo "$line" | awk '{for(i=7;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
            [[ -z "$command" ]] && continue
            out="event_type=cron cron_source=system_crontab cron_user=$user cron_schedule=$(safe_val "$schedule") cron_command=$(safe_val "$command") cron_file=/etc/crontab"
            emit "$out"
        fi
    done < /etc/crontab
fi

# --- /etc/cron.d/* (drop-in crontabs, have user field like /etc/crontab) ---
if [[ -d /etc/cron.d ]]; then
    for cronfile in /etc/cron.d/*; do
        [[ ! -f "$cronfile" ]] && continue
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z_0-9]*= ]] && continue

            if [[ "$line" =~ ^[[:space:]]*@ ]]; then
                user=$(echo "$line" | awk '{print $2}')
                command=$(echo "$line" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
                schedule=$(echo "$line" | awk '{print $1}')
            else
                schedule=$(echo "$line" | awk '{printf "%s %s %s %s %s", $1, $2, $3, $4, $5}')
                user=$(echo "$line" | awk '{print $6}')
                command=$(echo "$line" | awk '{for(i=7;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
            fi
            [[ -z "$command" ]] && continue
            out="event_type=cron cron_source=cron.d cron_user=$user cron_schedule=$(safe_val "$schedule") cron_command=$(safe_val "$command") cron_file=$cronfile"
            emit "$out"
        done < "$cronfile"
    done
fi

# --- User crontabs ---
# Try to read crontabs for all users via /var/spool/cron or crontab -l -u
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
        # Skip common non-script files
        [[ "$script_name" == .placeholder ]] && continue
        emit "event_type=cron cron_source=cron.$period cron_schedule=@$period cron_command=$script_name cron_file=$script"
    done
done

# --- Systemd timers ---
if command -v systemctl &>/dev/null; then
    while IFS= read -r line; do
        # list-timers output: NEXT LEFT LAST PASSED UNIT ACTIVATES
        timer_unit=$(echo "$line" | awk '{print $(NF-1)}')
        activated_unit=$(echo "$line" | awk '{print $NF}')

        [[ -z "$timer_unit" || "$timer_unit" == "UNIT" ]] && continue

        # Get the timer's schedule from the unit file
        schedule=$(systemctl show "$timer_unit" -p TimersCalendar 2>/dev/null | sed 's/TimersCalendar=//')
        if [[ -z "$schedule" || "$schedule" == "" ]]; then
            schedule=$(systemctl show "$timer_unit" -p TimersMonotonic 2>/dev/null | sed 's/TimersMonotonic=//')
        fi

        out="event_type=cron cron_source=systemd_timer cron_command=$activated_unit"
        [[ -n "$schedule" ]] && out="$out cron_schedule=$(safe_val "$schedule")"
        out="$out cron_file=$timer_unit"
        emit "$out"
    done < <(systemctl list-timers --all --no-pager --no-legend 2>/dev/null)
fi

# --- Anacron ---
if [[ -f /etc/anacrontab ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z_0-9]*= ]] && continue

        # Format: period delay job-identifier command
        period=$(echo "$line" | awk '{print $1}')
        delay=$(echo "$line" | awk '{print $2}')
        job_id=$(echo "$line" | awk '{print $3}')
        command=$(echo "$line" | awk '{for(i=4;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')

        [[ -z "$command" ]] && continue
        emit "event_type=cron cron_source=anacron cron_schedule=\"period=${period}d delay=${delay}m\" cron_command=$(safe_val "$command") cron_file=/etc/anacrontab"
    done < /etc/anacrontab
fi

exit 0
