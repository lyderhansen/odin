#!/usr/bin/env bash
# tools/tests/check-version-sync.sh — HARD-01 drift guard
#
# Parses the canonical ODIN_VERSION string from all 4 sites and asserts
# they agree. Exits 0 on sync, 1 on drift. Safe to run locally or in CI.
#
# Sites checked:
#   TA-ODIN/default/app.conf                       version = X.Y.Z
#   ODIN_app_for_splunk/default/app.conf           version = X.Y.Z
#   TA-ODIN/bin/odin.sh                            export ODIN_VERSION="X.Y.Z"
#   TA-ODIN/bin/odin.ps1                           if (-not $env:ODIN_VERSION) { $env:ODIN_VERSION = 'X.Y.Z' }

set -u

# Portable version extractor — grep + sed, no awk/perl/python dependency.
extract_appconf() {
    local file="$1"
    grep -E '^version[[:space:]]*=' "$file" 2>/dev/null | head -1 | sed -E 's/^version[[:space:]]*=[[:space:]]*//' | tr -d ' '
}

extract_shell_export() {
    local file="$1"
    grep -E '^export ODIN_VERSION=' "$file" 2>/dev/null | head -1 | sed -E 's/^export ODIN_VERSION=//' | tr -d '"' | tr -d "'"
}

extract_ps1_env() {
    local file="$1"
    grep -E "env:ODIN_VERSION[[:space:]]*=[[:space:]]*'[^']+'" "$file" 2>/dev/null | head -1 | sed -E "s/.*env:ODIN_VERSION[[:space:]]*=[[:space:]]*'([^']+)'.*/\1/"
}

# Resolve paths relative to repo root, not CWD
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ta_odin_version=$(extract_appconf "$REPO_ROOT/TA-ODIN/default/app.conf")
sh_app_version=$(extract_appconf "$REPO_ROOT/ODIN_app_for_splunk/default/app.conf")
odin_sh_version=$(extract_shell_export "$REPO_ROOT/TA-ODIN/bin/odin.sh")
odin_ps1_version=$(extract_ps1_env "$REPO_ROOT/TA-ODIN/bin/odin.ps1")

# Assert all 4 extractions produced non-empty output
for pair in \
    "TA-ODIN/default/app.conf:$ta_odin_version" \
    "ODIN_app_for_splunk/default/app.conf:$sh_app_version" \
    "TA-ODIN/bin/odin.sh:$odin_sh_version" \
    "TA-ODIN/bin/odin.ps1:$odin_ps1_version"; do
    file="${pair%%:*}"
    ver="${pair##*:}"
    if [[ -z "$ver" ]]; then
        echo "[HARD-01 FAIL] Could not extract version from $file"
        exit 1
    fi
done

# Compare all 4 against the TA-ODIN/default/app.conf as canonical
canonical="$ta_odin_version"
drift=0

for pair in \
    "ODIN_app_for_splunk/default/app.conf:$sh_app_version" \
    "TA-ODIN/bin/odin.sh:$odin_sh_version" \
    "TA-ODIN/bin/odin.ps1:$odin_ps1_version"; do
    file="${pair%%:*}"
    ver="${pair##*:}"
    if [[ "$ver" != "$canonical" ]]; then
        echo "[HARD-01 DRIFT] $file has $ver but canonical is $canonical (from TA-ODIN/default/app.conf)"
        drift=1
    fi
done

# HARD-01 extension (Phase 3 Plan 1): also check app.conf header comments
# for v[0-9]+.[0-9]+.[0-9]+ drift. The main check above only greps the
# `version = X.Y.Z` line and misses string-drift in file header comments.
# Scoped to first 10 lines to avoid false positives on inline descriptions.
for f in \
    "$REPO_ROOT/TA-ODIN/default/app.conf" \
    "$REPO_ROOT/ODIN_app_for_splunk/default/app.conf"; do
    comment_version=$(head -n 10 "$f" 2>/dev/null | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ -n "$comment_version" ]] && [[ "${comment_version#v}" != "$canonical" ]]; then
        rel="${f#"$REPO_ROOT"/}"
        echo "[HARD-01 DRIFT] $rel header comment says $comment_version but canonical is v$canonical"
        drift=1
    fi
done

# ---------------------------------------------------------------------------
# Section 3 (PROD-07 c+d) — Linux module standalone-fallback version drift
# ---------------------------------------------------------------------------
# After PROD-07 (d) the standalone fallback block is consolidated into
# TA-ODIN/bin/modules/_common.sh and each module's standalone branch sources
# it (gated by `! declare -f emit` so orchestrator runs never source the
# library). We assert two invariants:
#   1. _common.sh declares the canonical ODIN_VERSION default
#   2. All 6 modules source _common.sh from their fallback gate
COMMON_SH="$REPO_ROOT/TA-ODIN/bin/modules/_common.sh"
if [[ ! -f "$COMMON_SH" ]]; then
    echo "[HARD-01 / PROD-07 FAIL] _common.sh missing at $COMMON_SH"
    exit 1
fi

common_version=$(grep -E 'ODIN_VERSION="\$\{ODIN_VERSION:-' "$COMMON_SH" \
    | head -1 \
    | sed -E 's/.*ODIN_VERSION:-([^"}]+).*/\1/')
if [[ -z "$common_version" ]]; then
    echo "[HARD-01 / PROD-07 FAIL] _common.sh has no fallback ODIN_VERSION line"
    exit 1
fi
if [[ "$common_version" != "$canonical" ]]; then
    echo "[HARD-01 / PROD-07 DRIFT] _common.sh fallback ODIN_VERSION='$common_version' (expected $canonical)"
    exit 1
fi

# Verify each module sources _common.sh from its standalone-fallback branch
declare -i missing_source=0
for module in "$REPO_ROOT"/TA-ODIN/bin/modules/*.sh; do
    [[ "$(basename "$module")" == "_common.sh" ]] && continue
    if ! grep -q 'source.*_common\.sh' "$module"; then
        rel="${module#"$REPO_ROOT"/}"
        echo "[HARD-01 / PROD-07 FAIL] $rel does not source _common.sh"
        missing_source=$((missing_source + 1))
    fi
done

if [[ $missing_source -gt 0 ]]; then
    echo "[HARD-01 / PROD-07 FAIL] $missing_source module(s) missing _common.sh source line"
    exit 1
fi

if [[ $drift -eq 0 ]]; then
    echo "[HARD-01 PASS] Version sync: $canonical (4 sites + _common.sh + 6 module sources)"
fi

exit $drift
