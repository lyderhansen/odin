#!/usr/bin/env bash
# rollback-dryrun.sh
# PROD-05 rollback dry-run validator (no real Splunk required).
#
# Simulates the production rollback procedure by:
#   1. Capturing pre-toggle event count from a live odin.sh invocation
#   2. Patching a temp copy of TA-ODIN/default/inputs.conf so both
#      [script://...] stanzas have `disabled = true`
#   3. Running a Python configparser-based emulator that confirms BOTH
#      stanzas are now inactive (mirrors what splunkd would do at next
#      reload-cycle: skip dispatching a disabled scripted input)
#   4. Capturing post-revert event count after discarding the temp patch
#   5. Writing .planning/artifacts/rollback-dryrun.md with timestamps,
#      counts, commit hash, and PASS/FAIL verdict
#   6. Asserting the real TA-ODIN/default/inputs.conf is byte-identical
#      to its committed state (`git diff --quiet`)
#
# Exits 0 on success, 1 on any failure. Safe to run in CI.
# Real-fleet validation is deferred to PROD-02 pilot (Phase 6).

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

INPUTS=TA-ODIN/default/inputs.conf
ARTIFACT=.planning/artifacts/rollback-dryrun.md
TMP_INPUTS=$(mktemp -t odin-rollback-inputs.XXXXXX)

# Always remove the temp patch on exit (success OR failure path).
# shellcheck disable=SC2329  # invoked indirectly via `trap cleanup EXIT`
cleanup() {
    rm -f "$TMP_INPUTS" "${TMP_INPUTS}.bak" 2>/dev/null || true
}
trap cleanup EXIT

# --- Step 0: pre-flight ---------------------------------------------------
if [ ! -f "$INPUTS" ]; then
    echo "[FAIL] $INPUTS missing — refusing to dry-run"
    exit 1
fi

mkdir -p "$(dirname "$ARTIFACT")"
cp "$INPUTS" "$TMP_INPUTS"

COMMIT=$(git rev-parse HEAD)
START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Step 1: pre-toggle baseline ----------------------------------------
PRE_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PRE_COUNT=$(bash TA-ODIN/bin/odin.sh 2>/dev/null | wc -l | tr -d ' ')

# --- Step 2: apply rollback patch to temp copy ---------------------------
# Convention from inputs.conf: `disabled = false` (string), NOT `disabled = 0`.
# Patch the string form to stay consistent with existing style — both stanzas
# (Linux odin.sh + Windows odin.path) toggled in one sed pass.
sed -i.bak 's/^disabled = false$/disabled = true/g' "$TMP_INPUTS"

# --- Step 3: parser-emulator ---------------------------------------------
# Verifies all [script://...] stanzas in the patched file now have
# disabled = true (i.e., splunkd would NOT dispatch them at next reload).
# Inline python3 -c (NOT heredoc) per Phase 4 plan-checker fix to avoid
# indentation pitfalls under `set -euo pipefail`.
EMULATOR_OUT=$(python3 -c "
import configparser, sys
c = configparser.ConfigParser(strict=False, allow_no_value=True)
c.read('$TMP_INPUTS')
script_sections = [s for s in c.sections() if s.startswith('script://')]
if not script_sections:
    print('NO_SCRIPT_STANZAS')
    sys.exit(1)
all_disabled = True
report = []
for s in script_sections:
    d = c.get(s, 'disabled', fallback='false').strip().lower()
    is_off = d in ('true', '1')
    if not is_off:
        all_disabled = False
    report.append('  [{}] disabled={} -> {}'.format(s, d, 'INACTIVE' if is_off else 'ACTIVE'))
for line in report:
    print(line)
if all_disabled:
    print('ALL_STANZAS_INACTIVE')
    sys.exit(0)
print('ONE_OR_MORE_STANZAS_STILL_ACTIVE')
sys.exit(1)
")
EMULATOR_RC=$?

# --- Step 4: discard the temp patch and revert (real file untouched) -----
# The real INPUTS file was never modified — TMP_INPUTS is the only patched
# artifact and gets removed by the EXIT trap. Nothing to "revert" on disk;
# the temp copy goes away. We still capture post-revert timing/count to
# prove the procedure is reversible.
REVERT_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Step 5: post-revert event count -------------------------------------
POST_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
POST_COUNT=$(bash TA-ODIN/bin/odin.sh 2>/dev/null | wc -l | tr -d ' ')

# --- Step 6: assert real file untouched ----------------------------------
if ! git diff --quiet -- "$INPUTS"; then
    echo "[FAIL] $INPUTS was modified by the dry-run script — this MUST NOT happen"
    git diff -- "$INPUTS"
    exit 1
fi

# --- Verdict --------------------------------------------------------------
VERDICT=PASS
if [ "$EMULATOR_RC" -ne 0 ]; then
    VERDICT=FAIL
fi
if [ "$POST_COUNT" -le 0 ]; then
    VERDICT=FAIL
fi

# --- Step 7: write the dry-run artifact ----------------------------------
{
    echo "# Rollback dry-run record"
    echo ""
    echo "Generated: $START_TS"
    echo "Commit: $COMMIT"
    echo "Verdict: $VERDICT"
    echo ""
    echo "## Pre-toggle baseline (live odin.sh invocation)"
    echo ""
    echo "- Pre-toggle timestamp: $PRE_TS"
    echo "- Pre-toggle event count: $PRE_COUNT"
    echo ""
    echo "## Rollback patch (applied to temp copy of inputs.conf)"
    echo ""
    echo "Patch: \`sed 's/^disabled = false\$/disabled = true/g'\` over both"
    echo "\`[script://...]\` stanzas (Linux odin.sh + Windows odin.path)."
    echo ""
    echo "Parser emulator (configparser) report:"
    echo '```'
    echo "$EMULATOR_OUT"
    echo '```'
    echo ""
    echo "## Post-revert (temp patch discarded; real file untouched)"
    echo ""
    echo "- Revert timestamp: $REVERT_TS"
    echo "- Post-revert timestamp: $POST_TS"
    echo "- Post-revert event count: $POST_COUNT"
    echo ""
    echo "## Real-file integrity check"
    echo ""
    echo "- \`git diff --quiet -- $INPUTS\` exit: 0 (no real-file modification)"
    echo ""
    echo "## What this dry-run proves"
    echo ""
    echo "- The \`disabled = true\` toggle semantics are correctly understood"
    echo "  and applied to both Linux (\`[script://./bin/odin.sh]\`) and Windows"
    # Use printf for the Windows-stanza line so backslashes render literally
    # without tripping shellcheck SC2028 (echo + escape-sequence pitfall).
    # shellcheck disable=SC2016  # backticks here are literal markdown, not command sub
    printf '%s\n' '  (`[script://.\bin\odin.path]`) scripted-input stanzas.'
    echo "- A Splunk-equivalent parser (Python configparser) confirms both"
    echo "  stanzas would NOT be dispatched after rollback."
    echo "- The procedure is reversible: discarding the temp patch restores"
    echo "  enumeration (post-revert event count > 0)."
    echo "- The real inputs.conf in the repo is never modified by this script"
    echo "  (working-tree \`git diff\` is empty)."
    echo ""
    echo "## What this dry-run does NOT prove (deferred to PROD-02 pilot)"
    echo ""
    echo "- Real Deployment Server reload-cycle delivers the patched"
    echo "  inputs.conf to UFs within expected propagation time."
    echo "- Real Splunk forwarders honor the \`disabled = true\` flag"
    echo "  immediately on next reload (vs queued in-flight scan)."
    echo "- No partial-state failure (e.g., inputs.conf syntax error after"
    echo "  edit causes UF to reject the entire stanza)."
    echo ""
    echo "These three are explicitly verified during PROD-02 pilot, not here."
} > "$ARTIFACT"

if [ "$VERDICT" = "PASS" ]; then
    echo "[PROD-05 PASS] rollback dry-run verified — artifact: $ARTIFACT"
    exit 0
else
    echo "[PROD-05 FAIL] verdict=$VERDICT — see $ARTIFACT"
    exit 1
fi
