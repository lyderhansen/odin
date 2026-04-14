#!/usr/bin/env bash
#
# tools/tests/injection-fixtures/run.sh — HARD-08 regression test
#
# Feeds malicious inputs through safe_val() (sourced from
# TA-ODIN/bin/modules/services.sh) and asserts the output is
# single-line and contains no shell expansion. When the input
# contains whitespace, the output must be double-quoted (safe_val's
# current contract — see Phase 2 Plan 3 SUMMARY deviation note on
# assertion scope).

# Locate repo root (three levels up from this script)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIXTURE_FILE="$REPO_ROOT/tools/tests/injection-fixtures/malicious-names.txt"
SERVICES_MOD="$REPO_ROOT/TA-ODIN/bin/modules/services.sh"

if [[ ! -f "$FIXTURE_FILE" ]]; then
    echo "[HARD-08 FAIL] Fixture file missing: $FIXTURE_FILE"
    exit 2
fi

if [[ ! -f "$SERVICES_MOD" ]]; then
    echo "[HARD-08 FAIL] services.sh not found at: $SERVICES_MOD"
    exit 2
fi

# Extract the safe_val function body from services.sh and eval it in
# the current shell. We cannot `source` services.sh directly because
# the module ends with `exit 0`, which would terminate this test
# runner before the fixture loop executes. Using a scoped extraction
# keeps the trust boundary tight: we only evaluate the function block
# `safe_val() { ... }` from the checked-in module, never the module's
# top-level enumeration code.
safe_val_def=$(awk '
    /^safe_val\(\) \{/ { capturing = 1 }
    capturing            { print }
    capturing && /^\}/   { capturing = 0; exit }
' "$SERVICES_MOD")

if [[ -z "$safe_val_def" ]]; then
    echo "[HARD-08 FAIL] Could not extract safe_val from services.sh"
    exit 2
fi

eval "$safe_val_def"

# Sanity check: safe_val must be defined
if ! declare -F safe_val >/dev/null; then
    echo "[HARD-08 FAIL] safe_val function not defined after sourcing services.sh"
    exit 2
fi

# From here on, enforce strict variable usage for the test loop
set -u

pass=0
fail=0
entry_num=0

# Read fixture file line-by-line. Embedded-newline entry 4 is two
# physical lines — both halves are processed and must each produce
# safe single-line output.
while IFS= read -r input || [[ -n "$input" ]]; do
    # Skip blank lines and comments
    [[ -z "$input" ]] && continue
    [[ "$input" =~ ^# ]] && continue

    entry_num=$((entry_num + 1))

    # Run through safe_val
    output=$(safe_val "$input")

    # assertion 1: output is a single line
    line_count=$(printf '%s' "$output" | wc -l | tr -d ' ')
    if [[ "$line_count" -gt 0 ]]; then
        echo "[FAIL entry $entry_num] Multi-line output from: '$input' -> '$output'"
        fail=$((fail + 1))
        continue
    fi

    # assertion 2: if input contains whitespace, output must be
    # double-quoted. safe_val only wraps whitespace-bearing values —
    # not '=' sign. See Plan 3 SUMMARY for the deviation rationale.
    if [[ "$input" =~ [[:space:]] ]]; then
        if [[ ! "$output" =~ ^\".*\"$ ]]; then
            echo "[FAIL entry $entry_num] Unquoted output for whitespace input: '$input' -> '$output'"
            fail=$((fail + 1))
            continue
        fi
    fi

    # assertion 3: no shell expansion happened. None of the fixtures
    # contain the literal string 'uid=' or an unescaped 'root' token,
    # so if those appear in the output, safe_val (or bash) executed
    # the payload.
    if [[ "$output" == *"uid="* ]] || [[ "$output" == *$'\n'* ]]; then
        echo "[FAIL entry $entry_num] Shell expansion or newline in output: '$input' -> '$output'"
        fail=$((fail + 1))
        continue
    fi

    pass=$((pass + 1))
done < "$FIXTURE_FILE"

echo "[HARD-08] $pass passed, $fail failed (total entries processed: $entry_num)"

if [[ $fail -gt 0 ]]; then
    exit 1
fi
exit 0
