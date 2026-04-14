#!/bin/bash
#
# TA-ODIN v1.0.0 - Orchestrator Script for Linux
# Autodiscovers and runs all modules in bin/modules/
#
# Sets shared context via ODIN_* environment variables and runs each module.
# Emits start-event, runs modules, emits completion-event with summary.
# Never aborts on module failure.
#
# Guardrails:
#   - Per-module timeout of 90 seconds (leaves margin within Splunk's 120s input timeout)
#   - MAX_EVENTS cap of 50,000 per module to prevent output flooding
#

# Verify bash is available (scripts require bash features)
if [[ -z "$BASH_VERSION" ]]; then
    echo "timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ") hostname=$(hostname) os=linux run_id=error-$$ odin_version=1.0.0 type=odin_error message=\"TA-ODIN requires bash but it is not available on this system\""
    exit 1
fi

# Force C locale for consistent command output parsing across all locales
export LC_ALL=C

# Find script directory (works even with symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
MODULES_DIR="$SCRIPT_DIR/modules"

# --- Shared context (exported for modules) ---
export ODIN_VERSION="1.0.0"
export ODIN_HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
export ODIN_OS="linux"
export ODIN_RUN_ID="$(date +%s)-$$"

# Per-module timeout in seconds (90s leaves 30s margin within Splunk's 120s input timeout)
# HARD-02: pre-set ODIN_MODULE_TIMEOUT env var is honored, default applies only when unset
: "${ODIN_MODULE_TIMEOUT:=90}"
MODULE_TIMEOUT="$ODIN_MODULE_TIMEOUT"
HAS_TIMEOUT=0
command -v timeout >/dev/null 2>&1 && HAS_TIMEOUT=1

# Maximum events per module run (prevents output flooding from hosts with 100K+ items)
# HARD-02: pre-set ODIN_MAX_EVENTS env var is honored, default applies only when unset
: "${ODIN_MAX_EVENTS:=50000}"
export ODIN_MAX_EVENTS ODIN_MODULE_TIMEOUT
export ODIN_EVENT_COUNT=0
export ODIN_EVENTS_TRUNCATED=0

# Get timestamp in ISO 8601 UTC format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Emit a key=value event line with MAX_EVENTS guardrail
emit() {
    # If already truncated, silently drop
    if [[ $ODIN_EVENTS_TRUNCATED -eq 1 ]]; then
        return
    fi

    # Check event count limit
    if [[ $ODIN_EVENT_COUNT -ge $ODIN_MAX_EVENTS ]]; then
        ODIN_EVENTS_TRUNCATED=1
        echo "timestamp=$(get_timestamp) hostname=$ODIN_HOSTNAME os=$ODIN_OS run_id=$ODIN_RUN_ID odin_version=$ODIN_VERSION type=truncated message=\"Event limit reached (max=$ODIN_MAX_EVENTS). Remaining events suppressed.\""
        return
    fi

    ODIN_EVENT_COUNT=$((ODIN_EVENT_COUNT + 1))
    echo "timestamp=$(get_timestamp) hostname=$ODIN_HOSTNAME os=$ODIN_OS run_id=$ODIN_RUN_ID odin_version=$ODIN_VERSION $*"
}

# Export emit function for modules
export -f get_timestamp
export -f emit

# --- Privilege check ---
export ODIN_RUNNING_AS_ROOT=0
if [[ $EUID -eq 0 ]]; then
    ODIN_RUNNING_AS_ROOT=1
fi

# --- Start event ---
run_user=$(id -un 2>/dev/null || echo "unknown")
emit "type=odin_start run_as=$run_user euid=$EUID message=\"TA-ODIN enumeration started\""

# Warn if not running as root — some modules return limited data
if [[ $ODIN_RUNNING_AS_ROOT -eq 0 ]]; then
    emit "type=odin_warning module=ports message=\"Running as non-root (euid=$EUID). Port enumeration will not include process names/PIDs for ports owned by other users.\""
    emit "type=odin_warning module=cron message=\"Running as non-root (euid=$EUID). User crontabs in /var/spool/cron may be unreadable.\""
fi

# --- Discover and run modules ---
module_count=0
module_success=0
module_fail=0

if [[ ! -d "$MODULES_DIR" ]]; then
    emit "type=odin_error message=\"Modules directory not found: $MODULES_DIR\""
    emit "type=odin_complete modules_total=0 modules_success=0 modules_failed=0 message=\"TA-ODIN enumeration completed with errors\""
    exit 1
fi

for module in "$MODULES_DIR"/*.sh; do
    # Skip if no modules found (glob didn't expand)
    [[ ! -f "$module" ]] && continue

    module_name="$(basename "$module" .sh)"
    module_count=$((module_count + 1))

    # Reset per-module event counter
    export ODIN_EVENT_COUNT=0
    export ODIN_EVENTS_TRUNCATED=0

    # Run the module with timeout (if available) and capture its exit code
    if [[ $HAS_TIMEOUT -eq 1 ]]; then
        timeout "$MODULE_TIMEOUT" bash "$module"
    else
        bash "$module"
    fi
    rc=$?

    if [[ $rc -eq 124 && $HAS_TIMEOUT -eq 1 ]]; then
        # timeout returns 124 when the command is killed
        module_fail=$((module_fail + 1))
        emit "type=odin_error module=$module_name exit_code=$rc message=\"Module $module_name timed out after ${MODULE_TIMEOUT}s\""
    elif [[ $rc -ne 0 ]]; then
        module_fail=$((module_fail + 1))
        emit "type=odin_error module=$module_name exit_code=$rc message=\"Module $module_name failed with exit code $rc\""
    else
        module_success=$((module_success + 1))
    fi
done

# --- Completion event ---
emit "type=odin_complete modules_total=$module_count modules_success=$module_success modules_failed=$module_fail message=\"TA-ODIN enumeration completed\""

# Exit non-zero if any module failed
[[ $module_fail -gt 0 ]] && exit 1
exit 0
