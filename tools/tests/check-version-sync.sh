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

if [[ $drift -eq 0 ]]; then
    echo "[HARD-01 PASS] Version sync: $canonical"
fi

exit $drift
