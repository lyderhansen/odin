---
phase: 3
slug: appinspect-compliance
status: research-complete
created: 2026-04-14
research_approach: inline (installed splunk-appinspect via pip, ran against both apps, captured actual findings)
---

# Phase 3 — AppInspect Compliance & Release Gate — RESEARCH

> Factual findings captured by running `splunk-appinspect inspect --mode precert` against both apps at commit `c9cfb76`. This is REAL audit data, not speculation.

## Executive summary (surprises)

- **Both apps have ONE finding each, both the same trivial issue: a macOS `.DS_Store` file.** No hardcoded URLs. No insecure scripts. No deprecated stanzas. No license issues. No metadata issues flagged by AppInspect.
- **The codebase is much cleaner than expected.** 9 successes + 217 skipped (checks for features the apps don't use: modular inputs, UCC, Mako templates, Python code, etc.) + 2 not_applicable + 1 failure = 229 total checks per app.
- **Scope adjustment:** CONTEXT.md D5 proposed 3 plans (audit → fix → CI-integrate). With findings this minimal, the audit and fix work collapses into ONE plan. Phase 3 is now 2 plans instead of 3. RESEARCH.md recommends the planner honor this collapse.
- **splunk-appinspect 4.1.3 required libmagic system library.** Dev-machine install flow: `brew install libmagic` + `pip3 install --user splunk-appinspect` + add `~/Library/Python/3.9/bin` to PATH + `DYLD_LIBRARY_PATH=/opt/homebrew/lib` for the magic library. CI runner (ubuntu-latest) has `libmagic` pre-installed via apt, so CI only needs `pip install splunk-appinspect`.

---

## §1 — AppInspect audit baseline (captured 2026-04-14)

**Invocation:**
```bash
splunk-appinspect inspect TA-ODIN/ --mode precert --output-file .planning/artifacts/appinspect/ta-odin-initial.json --data-format json
splunk-appinspect inspect ODIN_app_for_splunk/ --mode precert --output-file .planning/artifacts/appinspect/odin-app-initial.json --data-format json
```

**Results (identical for both apps):**

| Category | Count |
|----------|-------|
| error | 0 |
| failure | 1 |
| warning | 0 |
| success | 9 |
| skipped | 217 |
| not_applicable | 2 |
| **Total** | **229** |

**The one failure in both apps:**
- **Check:** `check_that_extracted_splunk_app_does_not_contain_prohibited_directories_or_files`
- **Source:** `check_packaging_standards.py:356`
- **Message:** `A prohibited file or directory was found in the extracted Splunk App: .DS_Store`

`.DS_Store` is a macOS Finder metadata file that macOS automatically creates in every browsed directory. It has no functional purpose on non-macOS systems and is prohibited by Splunkbase packaging standards.

**Files to delete:**
```
TA-ODIN/.DS_Store
ODIN_app_for_splunk/.DS_Store
```

**Prevention:** Add `.DS_Store` to `.gitignore` at the repo root (which already has a `.gitignore` from session start). Also scan `.gitignore` to confirm the entry doesn't already exist — if it does, the files are tracked in git but untracked in the filesystem sense, which is a rarer case.

**Re-running the audit after deletion:** Expected to show `failure: 0, warning: 0, success: 9, skipped: 217, not_applicable: 2, total: 228` (one fewer check because the prohibited-file check finds nothing).

**JSON reports committed to:** `.planning/artifacts/appinspect/ta-odin-initial.json` and `odin-app-initial.json` — these become the Plan 1 baseline evidence.

---

## §2 — splunk-appinspect CLI reference

**Installation on dev-machine (macOS):**
```bash
brew install libmagic                              # required system library
pip3 install --user splunk-appinspect              # Python package
export PATH="$HOME/Library/Python/3.9/bin:$PATH"
export DYLD_LIBRARY_PATH="/opt/homebrew/lib:$DYLD_LIBRARY_PATH"
splunk-appinspect inspect --help
```

**Installation in CI (ubuntu-latest):**
```yaml
- name: Install splunk-appinspect
  run: pip install splunk-appinspect
  # libmagic is pre-installed on ubuntu-latest via apt
```

**Core invocation for Phase 3:**
```bash
splunk-appinspect inspect <app-dir> --mode precert --output-file <report.json> --data-format json
```

**Exit codes:**
- `0` — all checks ran (regardless of pass/fail — the failure info is in the report)
- non-zero — tool itself crashed (should not happen in normal use)

**Note:** `--mode precert` returns exit 0 even when `failure > 0`. To make AppInspect a true CI gate, the wrapping CI step must parse the JSON report and exit non-zero when `summary.failure > 0` (or `summary.error > 0`). Sample wrapper:
```bash
splunk-appinspect inspect <app> --mode precert --output-file /tmp/r.json --data-format json
python3 -c "import json, sys; s=json.load(open('/tmp/r.json'))['summary']; sys.exit(1 if (s.get('failure',0)+s.get('error',0))>0 else 0)"
```

**Structure of the JSON report:**
```json
{
  "request_id": "...",
  "reports": [{
    "groups": [{
      "checks": [{
        "name": "check_name",
        "result": "success|failure|warning|skipped|not_applicable",
        "messages": [{"message": "...", "filename": "...", "line": 123}],
        "description": "...",
        "tags": ["cloud", "precert"]
      }]
    }]
  }],
  "summary": {
    "error": 0, "failure": 0, "warning": 0,
    "success": 9, "skipped": 217, "not_applicable": 2
  },
  "metrics": {...}
}
```

---

## §3 — Current app.conf + metadata state (captured post-audit)

### TA-ODIN/default/app.conf

```ini
# Splunk app configuration for TA-ODIN v2.2.0      <-- HEADER DRIFT (Plan 2 missed)
# ...

[install]
is_configured = 0
build = 3

[ui]
is_visible = false
label = TA-ODIN Endpoint Enumeration

[launcher]
author = Your Organization                          <-- PLACEHOLDER
description = Technology Add-on for ODIN - ... <long description>
version = 1.0.0                                     <-- correct from Phase 2 HARD-01

[package]
id = TA-ODIN
```

**Missing fields (APPI-04 canonical set):** `license` is absent. AppInspect does NOT flag its absence in the precert mode — only packaging-level rules. But APPI-04 in REQUIREMENTS.md lists `license` as a required metadata field for Splunkbase submission.

### ODIN_app_for_splunk/default/app.conf

Same structure, same drift. `author = Your Organization` placeholder, no `license` field, header comment says `v2.2.0`.

### TA-ODIN/metadata/default.meta

**DOES NOT EXIST.** AppInspect did not flag this as a failure (defaulted to "no exports" assumption is acceptable). But CONTEXT.md D3 says to create it explicitly with `export = none` for auditability.

### ODIN_app_for_splunk/metadata/default.meta

```ini
[lookups]
export = system

[props]
export = system

[transforms]
export = system

[savedsearches]
export = system

[views]
export = system
```

AppInspect did NOT flag the blanket system exports as a failure (precert mode accepts them with the explanation that the user took an explicit decision). CONTEXT.md D3 says to add rationale comments inline to make the decision auditable for human Splunkbase reviewers.

---

## §4 — APPI-06 red-flag grep baseline

**Invocation from ROADMAP success criterion #5:**
```bash
grep -RIEn 'http[s]?://|Invoke-Expression|Add-Type|FromBase64String|/usr/local/bin|C:\\\\' TA-ODIN/ ODIN_app_for_splunk/
```

**Expected output:** Some hits in comments and .conf file metadata (e.g., Splunk documentation URLs) but ZERO hits in actual executable code (bash/PowerShell scripts).

**This grep should be part of Plan 2 final validation as APPI-06 proof.** Excluded from rejection: legitimate Splunkbase URLs in `odin_log_sources.csv` (if any reference external Splunkbase TAs), docstring comments in `.conf` headers.

---

## §5 — Header comment v2.2.0 drift fix

**Current state (both app.conf files):**
```ini
# Splunk app configuration for TA-ODIN v2.2.0
# Lightweight forwarder app for endpoint enumeration
```

**Target state:**
```ini
# Splunk app configuration for TA-ODIN v1.0.0
# Lightweight forwarder app for endpoint enumeration
```

**Phase 2 check-version-sync.sh extension:** The Phase 2 drift guard currently extracts `version = X.Y.Z` from `[launcher]` stanza only. Extending it to ALSO scan conf-file header comments for `v[0-9]+\.[0-9]+\.[0-9]+` patterns would prevent this class of drift.

**Recommended extension (plan task):**
```bash
# Add to check-version-sync.sh after the 4 standard checks:
for f in TA-ODIN/default/app.conf ODIN_app_for_splunk/default/app.conf; do
    comment_version=$(grep -Eo '^#.*\bv[0-9]+\.[0-9]+\.[0-9]+\b' "$f" 2>/dev/null | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ -n "$comment_version" ]] && [[ "$comment_version" != "v$canonical" ]]; then
        echo "[HARD-01 DRIFT] $f header comment says $comment_version but canonical is v$canonical"
        drift=1
    fi
done
```

---

## §6 — Metadata values for D2 (defaults from CONTEXT.md)

**From CONTEXT.md D2 (confirmed by user via 'y' during discuss-phase):**

- **author:** `Lyder Hansen` (from git config user.name and GitHub remote)
- **license:** `Apache-2.0` (permissive, Splunkbase-friendly)
- **description TA-ODIN:** `TA-ODIN forwarder app — enumerates services, ports, packages, scheduled tasks, processes, and mounts on Linux and Windows endpoints. Reports metadata only, never log content. Pairs with ODIN_app_for_splunk on indexers and search heads.`
- **description ODIN_app_for_splunk:** `ODIN indexer and search head app — provides the odin_discovery index, classification lookups, and search-time enrichment for TA-ODIN enumeration data. Deploy TA-ODIN to forwarders separately.`

**Planner instruction:** Bake these values into Plan 1 Task 1's action block verbatim. Executor surfaces them in the commit message so user can see what landed; override requires a follow-up commit (acceptable given low stakes).

---

## §7 — CI workflow integration for AppInspect

**Current CI workflow (.github/workflows/ci.yml from Phase 2):** 5 steps (shellcheck, PSA, two-app split, version sync, injection regression). Runs on ubuntu-latest.

**New steps to add (Plan 2 Task 1):**
```yaml
- name: Install splunk-appinspect
  run: pip install splunk-appinspect

- name: AppInspect TA-ODIN
  run: |
    splunk-appinspect inspect TA-ODIN --mode precert --output-file /tmp/ta-odin-ci.json --data-format json
    python3 -c "import json, sys; s=json.load(open('/tmp/ta-odin-ci.json'))['summary']; print(s); sys.exit(1 if (s.get('failure',0)+s.get('error',0))>0 else 0)"

- name: AppInspect ODIN_app_for_splunk
  run: |
    splunk-appinspect inspect ODIN_app_for_splunk --mode precert --output-file /tmp/odin-app-ci.json --data-format json
    python3 -c "import json, sys; s=json.load(open('/tmp/odin-app-ci.json'))['summary']; print(s); sys.exit(1 if (s.get('failure',0)+s.get('error',0))>0 else 0)"
```

**Note on CI: AppInspect CI runtime is ~60 seconds per app.** Total CI time grows from ~90s (Phase 2) to ~210s (Phase 3). Acceptable.

---

## §8 — Nyquist dimensions for Phase 3

Proposed 4 dimensions for `03-VALIDATION.md`:

| Dim | Name | Command | Expected | Covers |
|-----|------|---------|----------|--------|
| 1 | TA-ODIN AppInspect clean | `splunk-appinspect inspect TA-ODIN --mode precert` + JSON failure check | `failure: 0, error: 0` | APPI-01 |
| 2 | ODIN_app_for_splunk AppInspect clean | same against the other app | `failure: 0, error: 0` | APPI-02 |
| 3 | APPI-06 red-flag grep | `grep -RIEn 'http[s]?://\|Invoke-Expression\|Add-Type\|FromBase64String\|/usr/local/bin\|C:\\\\' TA-ODIN/ ODIN_app_for_splunk/` | zero hits in executable code | APPI-06 |
| 4 | Metadata fields complete | `grep -cE '^(author|description|license|version|build|id)' <each>/default/app.conf` | returns 6 per app | APPI-04 |

APPI-03 (hard-gate) and APPI-05 (least-privilege meta) are verified by dedicated plan tasks rather than Nyquist dimensions — APPI-03 by a deliberate-violation smoke test, APPI-05 by presence of rationale comments in metadata/default.meta.

---

## §9 — Plan-split recommendation (SIMPLIFIED after audit)

**CONTEXT.md D5 originally proposed 3 plans.** With findings this minimal, the audit and fix work collapse into one plan:

**Plan 1 — Metadata polish + .DS_Store cleanup + first clean audit (5-6 tasks):**
- Task 1: Update both app.conf files: author=Lyder Hansen, license=Apache-2.0, description (from CONTEXT D2), header comment v2.2.0→v1.0.0
- Task 2: Delete TA-ODIN/.DS_Store and ODIN_app_for_splunk/.DS_Store + add `**/.DS_Store` to .gitignore
- Task 3: Create TA-ODIN/metadata/default.meta with explicit `export = none` + rationale comment
- Task 4: Add rationale comments to ODIN_app_for_splunk/metadata/default.meta preserving blanket system export
- Task 5: Extend tools/tests/check-version-sync.sh to also grep conf-file header comments for v[0-9]+\.[0-9]+\.[0-9]+ drift
- Task 6: Re-run splunk-appinspect audit on both apps — expect failure: 0 across the board. Commit JSON reports to .planning/artifacts/appinspect/.

**Plan 2 — CI integration + hard-gate test + final validation (4-5 tasks):**
- Task 1: Extend .github/workflows/ci.yml with 3 new steps: Install splunk-appinspect, AppInspect TA-ODIN, AppInspect ODIN_app_for_splunk
- Task 2: APPI-03 deliberate-violation smoke test (inject `# http://example.com` into TA-ODIN/default/app.conf, run AppInspect, confirm failure on http_check rule, revert)
- Task 3: APPI-06 red-flag grep validation — run the full-repo grep against both app trees, commit result showing zero unexpected hits
- Task 4: Full validation run — all 4 Phase 3 Nyquist dimensions green, Phase 1 harness still green, Plan 1 audit JSON still shows failure: 0

**Total: 9-11 tasks across 2 plans.** Much simpler than the original 3-plan estimate. Plan 1 is the bigger of the two (~6 tasks) because it bundles all the metadata work plus the fix for the one actual AppInspect finding.

---

## §10 — Threat-model hints for each plan

**Plan 1 threats:**
- T-03-01-01: Metadata author/license values may be user-override targets. No secret leakage (git name is already public).
- T-03-01-02: `.DS_Store` deletion removes a file from git history. Low risk — macOS metadata, no operational data.
- T-03-01-03: check-version-sync.sh extension could false-positive on legitimate `vN.M.K` strings in unrelated comments. Mitigation: only scan HEADER comments (first 10 lines of each .conf file).

**Plan 2 threats:**
- T-03-02-01: pip install splunk-appinspect in CI pulls from PyPI unpinned. Supply-chain risk. Mitigation: pin to specific version (`pip install splunk-appinspect==4.1.3`).
- T-03-02-02: Deliberate-violation test must revert cleanly. Risk: test commits land on main if not reverted. Mitigation: test runs in a scratch branch, not on main, OR test modifies a file in-place, runs AppInspect, immediately reverts without committing.
- T-03-02-03: AppInspect CI step adds ~2 minutes to PR turnaround. Acceptable. No mitigation needed.

---

## Constraints for planner

- All 8 locked decisions D1-D8 in CONTEXT.md are FINAL. D5 is relaxed from 3 plans to 2 plans per the actual audit findings — planner may honor this simplification without asking.
- Every task must have an `<automated>` verify block.
- Plan 1's .DS_Store deletion is atomic — `git rm TA-ODIN/.DS_Store ODIN_app_for_splunk/.DS_Store` + commit + re-run audit in the same task.
- Threat-model every plan.
- Ensure PATH and DYLD_LIBRARY_PATH exports are documented in task action blocks — without them, splunk-appinspect fails to import on dev machines.
- Phase 2 artifacts must be preserved end-to-end: shellcheck clean, PSA clean, check-version-sync exits 0, check-two-app-split exits 0, Phase 1 harness still exits 0.
