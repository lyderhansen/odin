#!/bin/bash
#
# TA-ODIN Module: Service Enumeration
# Enumerates all services on the host using systemctl, service, or init.d fallback.
#
# Output fields:
#   event_type=service service_name= service_status= service_enabled= service_type=
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

# Track whether we emitted anything
emitted=0

# --- Primary: systemctl ---
if command -v systemctl &>/dev/null; then
    while IFS= read -r line; do
        # Parse systemctl list-units output: UNIT LOAD ACTIVE SUB DESCRIPTION...
        unit=$(echo "$line" | awk '{print $1}')
        active=$(echo "$line" | awk '{print $3}')
        sub=$(echo "$line" | awk '{print $4}')

        # Skip empty or invalid lines
        [[ -z "$unit" ]] && continue

        # Strip .service suffix for clean name
        service_name="${unit%.service}"

        # Determine enabled status
        enabled=$(systemctl is-enabled "$unit" 2>/dev/null || echo "unknown")

        # Determine service type from unit file
        service_type=""
        type_line=$(systemctl show "$unit" -p Type 2>/dev/null)
        if [[ "$type_line" == Type=* ]]; then
            service_type="${type_line#Type=}"
        fi

        # Map active/sub to a status
        case "$active" in
            active)   service_status="$sub" ;;   # running, exited, waiting, etc.
            inactive) service_status="stopped" ;;
            failed)   service_status="failed" ;;
            *)        service_status="$active" ;;
        esac

        out="event_type=service service_name=$service_name service_status=$service_status service_enabled=$enabled"
        [[ -n "$service_type" ]] && out="$out service_type=$service_type"
        emit "$out"
        emitted=1
    done < <(systemctl list-units --type=service --all --no-pager --no-legend 2>/dev/null)

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

        emit "event_type=service service_name=$service_name service_status=$service_status service_enabled=unknown"
        emitted=1
    done < <(service --status-all 2>/dev/null)

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

        # Try to get status
        if "$script" status &>/dev/null 2>&1; then
            service_status="running"
        else
            service_status="unknown"
        fi

        emit "event_type=service service_name=$service_name service_status=$service_status service_enabled=unknown"
        emitted=1
    done
fi

# Emit none_found if no services were discovered
if [[ $emitted -eq 0 ]]; then
    emit "event_type=none_found module=services message=\"No services discovered\""
fi

exit 0
