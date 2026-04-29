---
phase: 07-host-info-linux
reviewed: 2026-04-29T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - TA-ODIN/bin/modules/_common.sh
  - TA-ODIN/bin/odin.sh
  - tools/tests/check-host-info.sh
findings:
  critical: 1
  warning: 3
  info: 2
  total: 6
status: issues_found
---

# Phase 7: Code Review Report

**Reviewed:** 2026-04-29T00:00:00Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Three files reviewed: the extended `_common.sh` shared library (338 lines, +278 from Phase 7), the `odin.sh` orchestrator (178 lines, +~20 from Phase 7), and the new regression test `check-host-info.sh` (90 lines). All files pass `bash -n` syntax checking and shellcheck reports no errors.

The implementation is largely correct and well-structured. The D-01 through D-04 decisions are honored, idempotency guards are in place, and the event ordering is deterministic. However, one critical security issue was found (eval on file content), one correctness defect (IMDS worst-case timing documentation/claim is wrong), one real env-pollution bug (eval leaks shell variables and the protective comment is false), and one test weakness (empty virt_val causes false negative label). Two additional maintainability items are also noted.

---

## Critical Issues

### CR-01: `eval` on `/etc/os-release` content enables command injection; misleading comment claims non-existent subshell isolation

**File:** `TA-ODIN/bin/modules/_common.sh:95`

**Issue:** `detect_os_distro()` uses `eval "$(grep -E '^(ID|VERSION_ID|PRETTY_NAME)=' /etc/os-release)"` to parse the OS release file. The comment on line 94 says *"Source in subshell to avoid polluting our env with NAME=, ID=, etc."* — this is factually wrong on both counts:

1. **No subshell exists.** The `eval` runs in the current function's scope (not in a `( )` subshell). Variables set by `eval` — `ID`, `VERSION_ID`, `PRETTY_NAME` — are NOT declared `local` and therefore leak into the calling scope (`odin.sh`'s global scope) after `emit_host_info` returns. Verified by test: `detect_os_distro; echo "${ID:-unset}"` prints the OS ID string, not `unset`.

2. **Command injection is possible.** The `grep -E '^(ID|VERSION_ID|PRETTY_NAME)='` filter only requires the line to *start* with one of those key names, but it does not prevent value-side injection. A crafted `/etc/os-release` line like `ID=$(cat /etc/shadow)` passes the grep filter, and `eval` executes the command substitution. On an uncompromised system this is moot (the file is root-owned 644), but it violates defence-in-depth. The threat model notes the file is trusted, but the comment actively misrepresents the isolation, and any future refactor that copies this pattern to a less-trusted input source would be immediately exploitable.

**Fix:** Replace `eval` with direct parsing — no injection surface, no leak, no misleading comment:

```bash
detect_os_distro() {
    local distro="unknown" version="unknown" pretty="unknown"
    local _id _version_id _pretty_name
    if [[ -r /etc/os-release ]]; then
        _id=$(grep '^ID=' /etc/os-release | head -1 | cut -d= -f2- | tr -d '"')
        _version_id=$(grep '^VERSION_ID=' /etc/os-release | head -1 | cut -d= -f2- | tr -d '"')
        _pretty_name=$(grep '^PRETTY_NAME=' /etc/os-release | head -1 | cut -d= -f2- | tr -d '"')
        [[ -n "$_id" ]] && distro="$_id"
        [[ -n "$_version_id" ]] && version="$_version_id"
        [[ -n "$_pretty_name" ]] && pretty="$_pretty_name"
    fi
    echo "${distro}|${version}|${pretty}"
}
```

This is safe, readable, and correctly handles the common quoting formats in `/etc/os-release` (`ID=ubuntu` and `ID="ubuntu"` both work).

---

## Warnings

### WR-01: IMDS worst-case latency is 4 seconds, not 3 — documentation and comments are wrong

**File:** `TA-ODIN/bin/modules/_common.sh:222` (comment block), `TA-ODIN/bin/odin.sh:89` (comment)

**Issue:** Every comment and planning artifact asserts "1s curl timeout × 3 sequential probes = 3s worst case." This count is wrong. `_probe_aws_imds()` makes **two** sequential curl calls: one to fetch the IMDSv2 token (lines 229-232) and one to fetch the region (lines 234-237). With `ODIN_IMDS_TIMEOUT=1`, AWS alone can take up to 2 seconds. The full sequential chain on a non-cloud host is:

- AWS token fetch: 1s max
- AWS region fetch: 1s max (only attempted if token succeeds, but on a host that partially responds to 169.254.169.254 both calls can timeout)
- GCP: 1s max
- Azure: 1s max

**Actual worst case: 4 seconds**, not 3. The implementation behaviour is correct (all calls are individually bounded); only the stated budget is wrong. At 4s this remains trivially within the 90s module budget, but the discrepancy between claim and reality is a documentation defect that will mislead anyone setting `ODIN_IMDS_TIMEOUT` based on the documented formula.

**Fix:** Update the comment block at line 222 and the `probe_cloud_imds` docstring to reflect the true budget:

```bash
# --- Cloud IMDS probes (D-02: sequential AWS→GCP→Azure, 1s curl timeout each) ---
# AWS requires 2 sequential curl calls (IMDSv2 token + region query).
# Worst-case total on a non-cloud host: 4s (AWS: 2×1s + GCP: 1s + Azure: 1s).
# All three fail without curl: returns "none|none" immediately.
```

Also update `CHANGEHISTORY.md` (the "Decision change record" section says "3s worst case") and the plan-level verification checklist. D-02 itself should note 4s not 3s.

---

### WR-02: `eval` in `detect_os_distro()` leaks `ID`, `VERSION_ID`, `PRETTY_NAME` into `odin.sh` global scope

**File:** `TA-ODIN/bin/modules/_common.sh:95-98`

**Issue:** This is the scope-pollution side of CR-01, treated separately because it is an independent bug even if the eval injection risk were accepted. Variables set by `eval` inside a bash function are NOT confined to the function unless declared `local`. The three variables `ID`, `VERSION_ID`, and `PRETTY_NAME` are all set by `eval` without prior `local` declarations, so they persist in `odin.sh`'s global scope after `emit_host_info` returns.

Verified: running `bash -c 'detect_os_distro > /dev/null; echo "${ID:-unset}"'` prints the actual OS ID (e.g., `ubuntu`), not `unset`.

While `odin.sh` itself does not currently use a variable named `$ID`, any future module or orchestrator code that does (e.g., checking a loop variable named `$ID`) would silently receive the stale OS ID value instead of the expected empty/unset state. The protective comment is the real hazard: it asserts isolation that does not exist, making this invisible to future maintainers.

**Fix:** Use the direct-parsing approach from CR-01's fix (no eval needed), OR explicitly declare `local ID VERSION_ID PRETTY_NAME` at the top of `detect_os_distro()` to confine them to function scope.

---

### WR-03: Test Check 4 false-reports FAIL with misleading message when `host_info_line` is empty

**File:** `tools/tests/check-host-info.sh:64-73`

**Issue:** Check 4 extracts `virt_val` with:
```bash
virt_val=$(echo "$host_info_line" | grep -oE 'virtualization=[^ ]+' | cut -d= -f2)
```
If `host_info_line` is empty (because Check 1 already failed — no `odin_host_info` event was found), `virt_val` will be an empty string. The subsequent `case` statement has no arm matching the empty string, so it falls to `*)`:

```bash
echo "[HOST-01 FAIL] virtualization=$virt_val is NOT in D-04 enum ..."
```

This emits `virtualization= is NOT in D-04 enum` — a misleading secondary failure that appears to say the field value is wrong, when the real problem (already reported by Check 1) is that the event is entirely absent. The same applies to Check 5 (`cloud_val`). In CI output, this produces confusing duplicate failure messages for a single root cause.

**Fix:** Guard checks 2-5 on the prerequisite that Check 1 passed, or at minimum emit a clearer message:

```bash
# After Check 1:
if [[ "$host_info_count" -ne 1 ]]; then
    echo "[HOST-01 FAIL] skipping checks 2-5 — prerequisite event not found"
    fail=1
    exit 1   # or use a 'found_event' flag
fi
```

Alternatively, at minimum add a guard at the top of Check 4:
```bash
if [[ -z "$virt_val" ]]; then
    echo "[HOST-01 FAIL] virtualization field absent from event (or no event found)"
    fail=1
else
    case "$virt_val" in ...
fi
```

---

## Info

### IN-01: `_safe_val_host_info` does not quote field values containing `=` signs

**File:** `TA-ODIN/bin/modules/_common.sh:301-307`

**Issue:** `_safe_val_host_info` only wraps a value in double-quotes if it contains a space or double-quote character. A value containing a literal `=` sign (e.g., a hypothetical `PRETTY_NAME="my=distro"`) would be emitted unquoted as `os_pretty=my=distro`. Splunk's `KV_MODE=auto` tokenizes this as two key-value pairs: `os_pretty=my` and a dangling `distro`. In practice, no real Linux distro's `PRETTY_NAME`, kernel version, FQDN, or cloud region contains `=`, so this is not a current bug. It is worth documenting as a known limitation.

**Fix (optional, defensive):** Add `=` to the quoting trigger:
```bash
if [[ "$v" == *" "* || "$v" == *"\""* || "$v" == *"="* ]]; then
```

---

### IN-02: Header version banner in `_common.sh` and `odin.sh` does not reflect Phase 7 additions

**File:** `TA-ODIN/bin/modules/_common.sh:3`, `TA-ODIN/bin/odin.sh:3`

**Issue:** Both file headers read `TA-ODIN v1.0.1` while the Phase 7 block inside `_common.sh` clearly labels itself `v1.0.2 (Phase 7 / HOST-01)`. `ODIN_VERSION` is also hardcoded to `1.0.1` in `odin.sh:29` and `_common.sh:46`. The released version in `app.conf` is `1.0.1`, so the WIP state is intentional, but the file-level banner creates reader confusion ("this file says v1.0.1 but has v1.0.2 content"). A comment like `# Phase 7 (v1.0.2-wip) additions below` at the section boundary (already present at line 77) is sufficient — the file header should match the released version until the version bump commit.

This is a `status: wip` issue only, not a production defect. No fix needed before merging; the CHANGEHISTORY.md entry documents the version split.

---

_Reviewed: 2026-04-29T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
