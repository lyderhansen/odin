#!/bin/bash
#
# TA-ODIN v2.0 - Orchestrator Script for Linux
# Autodiscovers and runs all modules in bin/modules/
#
# Sets shared context via ODIN_* environment variables and runs each module.
# Emits start-event, runs modules, emits completion-event with summary.
# Never aborts on module failure.
#

# Find script directory (works even with symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
MODULES_DIR="$SCRIPT_DIR/modules"

# --- Shared context (exported for modules) ---
export ODIN_VERSION="2.0.0"
export ODIN_HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
export ODIN_OS="linux"
export ODIN_RUN_ID="$(date +%s)-$$"

# Get timestamp in ISO 8601 UTC format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Emit a key=value event line
emit() {
    echo "timestamp=$(get_timestamp) hostname=$ODIN_HOSTNAME os=$ODIN_OS run_id=$ODIN_RUN_ID odin_version=$ODIN_VERSION $*"
}

# Export emit function for modules
export -f get_timestamp
export -f emit

# --- Start event ---
emit "event_type=odin_start message=\"TA-ODIN enumeration started\""

# --- Discover and run modules ---
module_count=0
module_success=0
module_fail=0

if [[ ! -d "$MODULES_DIR" ]]; then
    emit "event_type=odin_error message=\"Modules directory not found: $MODULES_DIR\""
    emit "event_type=odin_complete modules_total=0 modules_success=0 modules_failed=0 message=\"TA-ODIN enumeration completed with errors\""
    exit 1
fi

for module in "$MODULES_DIR"/*.sh; do
    # Skip if no modules found (glob didn't expand)
    [[ ! -f "$module" ]] && continue

    module_name="$(basename "$module" .sh)"
    module_count=$((module_count + 1))

    # Run the module and capture its exit code
    bash "$module"
    rc=$?

    if [[ $rc -eq 0 ]]; then
        module_success=$((module_success + 1))
    else
        module_fail=$((module_fail + 1))
        emit "event_type=odin_error module=$module_name exit_code=$rc message=\"Module $module_name failed with exit code $rc\""
    fi
done

# --- Completion event ---
emit "event_type=odin_complete modules_total=$module_count modules_success=$module_success modules_failed=$module_fail message=\"TA-ODIN enumeration completed\""
