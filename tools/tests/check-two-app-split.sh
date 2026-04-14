#!/usr/bin/env bash
# tools/tests/check-two-app-split.sh — HARD-07
#
# Verifies the TA-ODIN / ODIN_app_for_splunk two-app split is clean.
#
# TA-ODIN (forwarder app) must NOT contain:
#   - indexes.conf (belongs to indexer tier)
#   - transforms.conf (belongs to search head tier)
#   - savedsearches.conf (belongs to search head tier)
#   - lookups/ directory (belongs to search head tier)
#   - data/ui/views/ (dashboards, belong to search head tier)
#
# ODIN_app_for_splunk (indexer/SH app) must NOT contain:
#   - inputs.conf (scripted inputs are forwarder-only)
#   - bin/ directory (collection scripts are forwarder-only)
#
# Exit 0 when split is clean, non-zero otherwise.

set -u

fail=0

# TA-ODIN forbidden paths (relative to repo root)
ta_odin_forbidden=(
    'TA-ODIN/default/indexes.conf'
    'TA-ODIN/default/transforms.conf'
    'TA-ODIN/default/savedsearches.conf'
    'TA-ODIN/lookups'
    'TA-ODIN/default/data/ui/views'
)

# ODIN_app_for_splunk forbidden paths
sh_app_forbidden=(
    'ODIN_app_for_splunk/default/inputs.conf'
    'ODIN_app_for_splunk/bin'
)

# Resolve paths relative to repo root, not CWD
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

for f in "${ta_odin_forbidden[@]}"; do
    if [[ -e "$REPO_ROOT/$f" ]]; then
        echo "[HARD-07 FAIL] $f must NOT exist in TA-ODIN (indexer/SH artifact leaked into forwarder app)"
        fail=1
    fi
done

for f in "${sh_app_forbidden[@]}"; do
    if [[ -e "$REPO_ROOT/$f" ]]; then
        echo "[HARD-07 FAIL] $f must NOT exist in ODIN_app_for_splunk (forwarder artifact leaked into search-head app)"
        fail=1
    fi
done

if [[ $fail -eq 0 ]]; then
    echo "[HARD-07 PASS] Two-app split is clean"
fi

exit $fail
