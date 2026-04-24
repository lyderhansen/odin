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
    ODIN_HOSTNAME="${ODIN_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}"
    ODIN_OS="${ODIN_OS:-linux}"
    ODIN_RUN_ID="${ODIN_RUN_ID:-standalone-$$}"
    ODIN_VERSION="${ODIN_VERSION:-1.0.0}"
    ODIN_MAX_EVENTS="${ODIN_MAX_EVENTS:-50000}"
    ODIN_EVENT_COUNT=0
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
    emit() {
        if [[ $ODIN_EVENT_COUNT -ge $ODIN_MAX_EVENTS ]]; then
            if [[ $ODIN_EVENT_COUNT -eq $ODIN_MAX_EVENTS ]]; then
                echo "timestamp=$(get_timestamp) hostname=$ODIN_HOSTNAME os=$ODIN_OS run_id=$ODIN_RUN_ID odin_version=$ODIN_VERSION type=truncated message=\"Event limit reached (max=$ODIN_MAX_EVENTS). Remaining events suppressed.\""
                ODIN_EVENT_COUNT=$((ODIN_EVENT_COUNT + 1))
            fi
            return 0
        fi
        ODIN_EVENT_COUNT=$((ODIN_EVENT_COUNT + 1))
        echo "timestamp=$(get_timestamp) hostname=$ODIN_HOSTNAME os=$ODIN_OS run_id=$ODIN_RUN_ID odin_version=$ODIN_VERSION $*"
    }
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
