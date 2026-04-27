#!/bin/bash
#
# TA-ODIN Module: Cron/Scheduled Task Enumeration
# Enumerates crontabs, cron directories, systemd timers, and anacron jobs.
#
# Output fields:
#   type=cron cron_source= cron_user= cron_schedule= cron_command= cron_file=
#
# Guardrails:
#   - timeout 30s on systemctl list-timers
#   - Batch systemctl show for timer schedules (single call instead of per-timer)
#

# Force C locale for consistent command output parsing
export LC_ALL=C

# Use orchestrator functions if available, otherwise define standalone versions
if ! declare -f emit &>/dev/null; then
    # shellcheck source=/dev/null  # _common.sh resolved via dirname BASH_SOURCE
    source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
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
    [[ -n "$user" ]] && out="$out cron_user=$(safe_val "$user")"
    [[ -n "$schedule" ]] && out="$out cron_schedule=$(safe_val "$schedule")"
    [[ -n "$command" ]] && out="$out cron_command=$(safe_val "$command")"
    [[ -n "$file" ]] && out="$out cron_file=$(safe_val "$file")"
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

    local out
    out="type=cron cron_source=$source cron_user=$(safe_val "$user") cron_schedule=$(safe_val "$schedule") cron_command=$(safe_val "$command") cron_file=$(safe_val "$file")"
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
        mapfile -t cron_lines < "$cronfile"
        for line in "${cron_lines[@]}"; do
            parse_system_cron_line "$line" "cron.d" "$cronfile"
        done
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
    if [[ -r "$crontab_dir" ]]; then
        for userfile in "$crontab_dir"/*; do
            [[ ! -f "$userfile" ]] && continue
            user=$(basename "$userfile")
            mapfile -t user_cron_lines < "$userfile" 2>/dev/null || continue
            for line in "${user_cron_lines[@]}"; do
                parse_cron_line "$line" "$user" "user_crontab" "$userfile"
            done
        done
    else
        # Directory exists but is not readable (non-root)
        emit "type=privilege_warning module=cron message=\"Cannot read $crontab_dir (permission denied). User crontabs not enumerated. Run as root for full visibility.\""
    fi
fi

# --- cron.daily/hourly/weekly/monthly ---
for period in hourly daily weekly monthly; do
    dir="/etc/cron.$period"
    [[ ! -d "$dir" ]] && continue
    for script in "$dir"/*; do
        [[ ! -f "$script" ]] && continue
        script_name=$(basename "$script")
        [[ "$script_name" == .placeholder ]] && continue
        emit "type=cron cron_source=cron.$period cron_schedule=@$period cron_command=$(safe_val "$script_name") cron_file=$(safe_val "$script")"
        emitted=1
    done
done

# --- Systemd timers (batch query) ---
if command -v systemctl &>/dev/null; then
    # Collect timer unit names first
    timer_units=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        read -ra words <<< "$line"
        len=${#words[@]}
        [[ $len -lt 2 ]] && continue
        timer_unit="${words[$((len-2))]}"
        activated_unit="${words[$((len-1))]}"
        [[ -z "$timer_unit" || "$timer_unit" == "UNIT" ]] && continue
        timer_units+=("$timer_unit:$activated_unit")
    done < <(timeout 30 systemctl list-timers --all --no-pager --no-legend 2>/dev/null)

    if [[ ${#timer_units[@]} -gt 0 ]]; then
        # Batch query: get all timer properties in one call
        unit_names=()
        for entry in "${timer_units[@]}"; do
            unit_names+=("${entry%%:*}")
        done

        # Single systemctl show for all timers at once
        batch_output=$(timeout 30 systemctl show "${unit_names[@]}" \
            --property=Id,TimersCalendar,TimersMonotonic --no-pager 2>/dev/null)

        # Build associative-like lookup from batch output
        declare -A timer_schedules
        current_id=""
        current_cal=""
        current_mono=""

        while IFS= read -r line; do
            if [[ -z "$line" ]]; then
                if [[ -n "$current_id" ]]; then
                    if [[ -n "$current_cal" ]]; then
                        timer_schedules["$current_id"]="$current_cal"
                    elif [[ -n "$current_mono" ]]; then
                        timer_schedules["$current_id"]="$current_mono"
                    fi
                fi
                current_id="" current_cal="" current_mono=""
                continue
            fi
            case "$line" in
                Id=*)              current_id="${line#Id=}" ;;
                TimersCalendar=*)  current_cal="${line#TimersCalendar=}" ;;
                TimersMonotonic=*) current_mono="${line#TimersMonotonic=}" ;;
            esac
        done <<< "$batch_output"
        # Handle last block
        if [[ -n "$current_id" ]]; then
            if [[ -n "$current_cal" ]]; then
                timer_schedules["$current_id"]="$current_cal"
            elif [[ -n "$current_mono" ]]; then
                timer_schedules["$current_id"]="$current_mono"
            fi
        fi

        # Emit events using collected data
        for entry in "${timer_units[@]}"; do
            timer_unit="${entry%%:*}"
            activated_unit="${entry##*:}"
            schedule="${timer_schedules[$timer_unit]:-}"

            out="type=cron cron_source=systemd_timer cron_command=$(safe_val "$activated_unit")"
            [[ -n "$schedule" ]] && out="$out cron_schedule=$(safe_val "$schedule")"
            out="$out cron_file=$(safe_val "$timer_unit")"
            emit "$out"
            emitted=1
        done
    fi
fi

# --- Anacron ---
if [[ -f /etc/anacrontab ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z_0-9]*= ]] && continue

        # Format: period delay job-identifier command
        read -r period delay _ command <<< "$line"

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
