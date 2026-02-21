#!/bin/bash
#
# TA-ODIN Module: Port Enumeration
# Enumerates all listening ports using ss or netstat fallback.
#
# Output fields:
#   type=port transport= listen_address= listen_port= process_name= process_pid=
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

# Parse address:port, handling IPv6 bracket notation
# Input: "[::1]:8080" or "0.0.0.0:80" or "127.0.0.1:443" or "*:22" or ":::22"
parse_address_port() {
    local addr_port="$1"

    if [[ "$addr_port" == \[*\]:* ]]; then
        # IPv6 with brackets: [::1]:8080
        listen_address="${addr_port%%]:*}]"
        listen_address="${listen_address#[}"
        listen_address="${listen_address%]}"
        listen_port="${addr_port##*]:}"
    elif [[ "$addr_port" == *:::* ]]; then
        # IPv6 short form: :::22 means [::]:22
        listen_address="::"
        listen_port="${addr_port##*:::}"
    elif [[ "$addr_port" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
        # IPv4: 0.0.0.0:80
        listen_address="${addr_port%:*}"
        listen_port="${addr_port##*:}"
    elif [[ "$addr_port" == \*:* ]]; then
        # Wildcard: *:22
        listen_address="*"
        listen_port="${addr_port##*:}"
    else
        # Fallback: try last colon as separator
        listen_address="${addr_port%:*}"
        listen_port="${addr_port##*:}"
    fi
}

emitted=0

# --- Primary: ss ---
if command -v ss &>/dev/null; then
    while IFS= read -r line; do
        # ss -tulpn output: Netid State Recv-Q Send-Q Local:Port Peer:Port Process
        read -r netid _ _ _ local_addr _ process_info <<< "$line"

        [[ -z "$local_addr" ]] && continue

        # Determine transport
        case "$netid" in
            tcp) transport="tcp" ;;
            udp) transport="udp" ;;
            *)   transport="$netid" ;;
        esac

        # Parse address and port
        parse_address_port "$local_addr"

        # Skip if no valid port
        [[ -z "$listen_port" || "$listen_port" == "Port" ]] && continue

        # Extract process name and PID from users:(("name",pid=1234,...))
        process_name=""
        process_pid=""
        if [[ "$process_info" =~ users:\(\(\"([^\"]+)\",pid=([0-9]+) ]]; then
            process_name="${BASH_REMATCH[1]}"
            process_pid="${BASH_REMATCH[2]}"
        fi

        out="type=port transport=$transport listen_address=$listen_address listen_port=$listen_port"
        [[ -n "$process_name" ]] && out="$out process_name=$(safe_val "$process_name")"
        [[ -n "$process_pid" ]] && out="$out process_pid=$process_pid"
        emit "$out"
        emitted=1
    done < <(ss -tulpn 2>/dev/null | tail -n +2)

    [[ $emitted -eq 1 ]] && exit 0
fi

# --- Fallback: netstat ---
if command -v netstat &>/dev/null; then
    while IFS= read -r line; do
        # netstat -tulpn output: Proto Recv-Q Send-Q Local Foreign State PID/Program
        read -r proto _ _ local_addr _ _ pid_prog <<< "$line"

        [[ -z "$local_addr" ]] && continue

        case "$proto" in
            tcp|tcp6) transport="tcp" ;;
            udp|udp6) transport="udp" ;;
            *)        transport="$proto" ;;
        esac

        parse_address_port "$local_addr"

        [[ -z "$listen_port" || "$listen_port" == "Port" ]] && continue

        process_name=""
        process_pid=""
        if [[ "$pid_prog" != "-" && -n "$pid_prog" ]]; then
            process_pid="${pid_prog%%/*}"
            # basename of program: handles both "1234/sshd" and "1234/usr/sbin/sshd"
            process_name="${pid_prog##*/}"
        fi

        out="type=port transport=$transport listen_address=$listen_address listen_port=$listen_port"
        [[ -n "$process_name" ]] && out="$out process_name=$(safe_val "$process_name")"
        [[ -n "$process_pid" ]] && out="$out process_pid=$process_pid"
        emit "$out"
        emitted=1
    done < <(netstat -tulpn 2>/dev/null | grep -E '^(tcp|udp)')
fi

# Emit none_found if no listening ports were discovered
if [[ $emitted -eq 0 ]]; then
    emit "type=none_found module=ports message=\"No listening ports discovered\""
fi

exit 0
