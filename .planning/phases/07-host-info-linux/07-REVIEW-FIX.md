---
phase: 07-host-info-linux
fixed_at: 2026-04-29T10:30:00+02:00
review_path: .planning/phases/07-host-info-linux/07-REVIEW.md
fix_scope: critical_warning
findings_in_scope: 4
fixed: 4
skipped: 0
iteration: 1
status: all_fixed
---

# Phase 7: Code Review Fix Report

**Fixed at:** 2026-04-29T10:30:00+02:00
**Source review:** .planning/phases/07-host-info-linux/07-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 4 (CR-01, WR-01, WR-02, WR-03)
- Fixed: 4
- Skipped: 0

WR-02 was resolved as a direct consequence of the CR-01 fix (same root cause, same fix). It is documented separately below per the review scope instructions.

---

## Fixed Issues

### CR-01: eval on /etc/os-release — command injection + scope leak

**Files modified:** `TA-ODIN/bin/modules/_common.sh`
**Commit:** `9504090`
**Applied fix:** Replaced `eval "$(grep -E '^(ID|VERSION_ID|PRETTY_NAME)=' /etc/os-release)"` with three explicit `grep '^KEY=' | head -1 | cut -d= -f2- | tr -d '"'` pipelines. Added `local _id _version_id _pretty_name` declarations. Removed the misleading "Source in subshell" comment (no subshell ever existed). Variables ID, VERSION_ID, PRETTY_NAME are now strictly local and never reach global scope.

**Verification:** `declare -p ID VERSION_ID PRETTY_NAME 2>&1 | grep -c "not found"` returns `3` after calling `detect_os_distro`. Regression test `check-host-info.sh` passes all 5 checks.

---

### WR-01: IMDS worst-case timing documentation — 3s should be 4s

**Files modified:** `TA-ODIN/bin/modules/_common.sh`, `DOCS/CHANGEHISTORY.md`
**Commit:** `e983239`
**Applied fix:**
- `_common.sh` Cloud IMDS section header: added a 4-line comment explaining AWS IMDSv2 requires 2 sequential calls (token PUT + region GET), making the actual worst case 4s on a non-cloud host (not 3s as previously stated). Note preserved that non-cloud hosts typically resolve in 3s because the token endpoint fails immediately.
- `CHANGEHISTORY.md` D-02 locked decision line: updated from "worst case 3s on non-cloud" to "4s worst case on non-cloud; AWS IMDSv2 = 2 sequential calls; non-cloud host typically resolves in 3s as token endpoint fails immediately".
- `CHANGEHISTORY.md` Decision change record: updated from "≤3s IMDS budget" to "≤4s IMDS budget" with full explanation of per-provider breakdown.

**Verification:** `grep -c '4s worst case' TA-ODIN/bin/modules/_common.sh DOCS/CHANGEHISTORY.md` returns 3 total (1 + 2).

---

### WR-02: eval leaks ID/VERSION_ID/PRETTY_NAME into global scope

**Files modified:** `TA-ODIN/bin/modules/_common.sh` (same change as CR-01)
**Commit:** `9504090` (same commit as CR-01 — fixed_by: CR-01, same root cause, same fix)
**Applied fix:** The CR-01 fix (replacing eval with grep/cut/tr + local declarations) is the complete fix for WR-02. No separate file change was needed. The three variables are now truly local to `detect_os_distro()` and are never assigned in the global shell environment.

---

### WR-03: check-host-info.sh Checks 4+5 emit misleading FAIL when event is absent

**Files modified:** `tools/tests/check-host-info.sh`
**Commit:** `c756541`
**Applied fix:** Wrapped Checks 4 and 5 in `if [[ -n "$host_info_line" ]]; then ... else echo "[HOST-01 SKIP] ... skipped — no event to inspect (see Check 1)"; fi` guards. When `host_info_line` is empty (event absent), the checks now emit a clear SKIP message instead of falling through to the case catch-all which produced a misleading "virtualization= is NOT in D-04 enum" failure. Also corrected the script header comment from "≤3s overhead" to "≤4s overhead" for consistency with WR-01 fix.

**Verification (positive path):** `bash tools/tests/check-host-info.sh` exits 0 with 5 PASS + 1 "All checks passed" markers.

**Verification (negative path):** With `emit_host_info` removed from odin.sh output, the test produces exactly 1 FAIL (Check 1: event count=0) + 2 SKIP messages (Checks 4 and 5). The 3 confusing FAIL messages from the pre-fix behavior are gone.

---

## Regression Suite Results

All tests run after all fixes applied on `main`:

| Test | Command | Result |
|------|---------|--------|
| HOST-01 event emitted | `bash TA-ODIN/bin/odin.sh \| grep -c 'type=odin_host_info'` | `1` — PASS |
| HOST-01 regression test | `bash tools/tests/check-host-info.sh` | exit 0, 5 PASS — PASS |
| HARD-01 version sync | `bash tools/tests/check-version-sync.sh` | exit 0 — PASS |
| HARD-07 two-app split | `bash tools/tests/check-two-app-split.sh` | exit 0 — PASS |

---

_Fixed: 2026-04-29T10:30:00+02:00_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
