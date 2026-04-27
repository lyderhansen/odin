#!/bin/bash
#
# TA-ODIN Module: Service Enumeration
# Enumerates all services on the host using systemctl, service, or init.d fallback.
#
# Output fields:
#   type=service service_name= service_status= service_enabled= service_type=
#
# Guardrails:
#   - Single batch systemctl query (no per-unit subprocess spawning)
#   - timeout on all external commands
#   - timeout 5s per init.d script status check
#

# Force C locale for consistent command output parsing
export LC_ALL=C

# Use orchestrator functions if available, otherwise define standalone versions
if ! declare -f emit &>/dev/null; then
    # shellcheck source=/dev/null  # _common.sh resolved via dirname BASH_SOURCE
    source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
fi

# Helper: escape double quotes and wrap values containing spaces
safe_val() {
    local val="$1"
    val="${val//\"/\\\"}"
    if [[ "$val" == *" "* ]]; then
        echo "\"$val\""
    else
        echo "$val"
    fi
}

# Track whether we emitted anything
emitted=0

# --- Primary: systemctl (batch query) ---
if command -v systemctl &>/dev/null; then
    # Single batch call: get all service properties at once (zero per-unit subprocesses)
    batch_output=$(timeout 30 systemctl show --type=service --all \
        --property=Id,ActiveState,SubState,Type,UnitFileState --no-pager 2>/dev/null)
    batch_rc=$?

    if [[ $batch_rc -eq 124 ]]; then
        emit "type=odin_error module=services message=\"systemctl show timed out after 30s\""
    elif [[ -n "$batch_output" ]]; then
        # Parse blocks separated by blank lines
        # Each block has: Id=, ActiveState=, SubState=, Type=, UnitFileState=
        unit_id="" active_state="" sub_state="" service_type="" unit_file_state=""

        while IFS= read -r line; do
            if [[ -z "$line" ]]; then
                # End of a block — emit if we have data
                if [[ -n "$unit_id" ]]; then
                    service_name="${unit_id%.service}"

                    # Map active/sub to a status
                    case "$active_state" in
                        active)   service_status="$sub_state" ;;
                        inactive) service_status="stopped" ;;
                        failed)   service_status="failed" ;;
                        *)        service_status="$active_state" ;;
                    esac

                    # Map UnitFileState to enabled/disabled
                    case "$unit_file_state" in
                        enabled|enabled-runtime) enabled="enabled" ;;
                        disabled)                enabled="disabled" ;;
                        static)                  enabled="static" ;;
                        masked|masked-runtime)   enabled="masked" ;;
                        *)                       enabled="$unit_file_state" ;;
                    esac
                    [[ -z "$enabled" ]] && enabled="unknown"

                    out="type=service service_name=$(safe_val "$service_name") service_status=$service_status service_enabled=$enabled"
                    [[ -n "$service_type" ]] && out="$out service_type=$service_type"
                    emit "$out"
                    emitted=1
                fi
                # Reset for next block
                unit_id="" active_state="" sub_state="" service_type="" unit_file_state=""
                continue
            fi

            case "$line" in
                Id=*)            unit_id="${line#Id=}" ;;
                ActiveState=*)   active_state="${line#ActiveState=}" ;;
                SubState=*)      sub_state="${line#SubState=}" ;;
                Type=*)          service_type="${line#Type=}" ;;
                UnitFileState=*) unit_file_state="${line#UnitFileState=}" ;;
            esac
        done <<< "$batch_output"

        # Handle last block (no trailing blank line)
        if [[ -n "$unit_id" ]]; then
            service_name="${unit_id%.service}"
            case "$active_state" in
                active)   service_status="$sub_state" ;;
                inactive) service_status="stopped" ;;
                failed)   service_status="failed" ;;
                *)        service_status="$active_state" ;;
            esac
            case "$unit_file_state" in
                enabled|enabled-runtime) enabled="enabled" ;;
                disabled)                enabled="disabled" ;;
                static)                  enabled="static" ;;
                masked|masked-runtime)   enabled="masked" ;;
                *)                       enabled="$unit_file_state" ;;
            esac
            [[ -z "$enabled" ]] && enabled="unknown"
            out="type=service service_name=$(safe_val "$service_name") service_status=$service_status service_enabled=$enabled"
            [[ -n "$service_type" ]] && out="$out service_type=$service_type"
            emit "$out"
            emitted=1
        fi
    fi

    # If systemctl worked, we're done
    [[ $emitted -eq 1 ]] && exit 0
fi

# --- Fallback 1: service --status-all ---
if command -v service &>/dev/null; then
    while IFS= read -r line; do
        # Format: [ + ] service_name  or  [ - ] service_name  or  [ ? ] service_name
        status_char=$(echo "$line" | sed -n 's/.*\[ \(.\) \].*/\1/p')
        service_name=$(echo "$line" | sed -n 's/.*\] \(.*\)/\1/p' | xargs)

        [[ -z "$service_name" ]] && continue

        case "$status_char" in
            +) service_status="running" ;;
            -) service_status="stopped" ;;
            ?) service_status="unknown" ;;
            *) service_status="unknown" ;;
        esac

        emit "type=service service_name=$(safe_val "$service_name") service_status=$service_status service_enabled=unknown"
        emitted=1
    done < <(timeout 30 service --status-all 2>/dev/null)

    [[ $emitted -eq 1 ]] && exit 0
fi

# --- Fallback 2: /etc/init.d/ ---
if [[ -d /etc/init.d ]]; then
    for script in /etc/init.d/*; do
        [[ ! -x "$script" ]] && continue
        service_name=$(basename "$script")

        # Skip common non-service scripts
        case "$service_name" in
            README|skeleton|rc|rcS|functions|halt|killall|single|reboot) continue ;;
        esac

        # Try to get status (5s timeout per script to prevent hangs)
        if timeout 5 "$script" status &>/dev/null 2>&1; then
            service_status="running"
        else
            service_status="unknown"
        fi

        emit "type=service service_name=$(safe_val "$service_name") service_status=$service_status service_enabled=unknown"
        emitted=1
    done
fi

# Emit none_found if no services were discovered
if [[ $emitted -eq 0 ]]; then
    emit "type=none_found module=services message=\"No services discovered\""
fi

exit 0
