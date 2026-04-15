---
phase: 03-appinspect-compliance
plan: 01
subsystem: appinspect-compliance
tags: [appinspect, metadata, splunkbase, apache-2.0, enterprise-scope]
requires: [Phase 1 Windows Parity, Phase 2 Production Hardening]
provides:
  - Splunkbase-ready app.conf metadata for both apps (APPI-04)
  - Clean AppInspect Enterprise-scope baseline (APPI-01, APPI-02)
  - Explicit metadata/default.meta for both apps with APPI-05 rationale
  - Header-comment drift guard in check-version-sync.sh (CONTEXT D6)
affects: [TA-ODIN/default/app.conf, ODIN_app_for_splunk/default/app.conf, tools/tests/check-version-sync.sh]
tech-stack:
  added: [splunk-appinspect 4.1.3 (dev-machine only)]
  patterns: [Enterprise-only AppInspect scope via --excluded-tags cloud]
key-files:
  created:
    - TA-ODIN/metadata/default.meta
    - .planning/artifacts/appinspect/ta-odin-fixed.json
    - .planning/artifacts/appinspect/odin-app-fixed.json
  modified:
    - TA-ODIN/default/app.conf
    - ODIN_app_for_splunk/default/app.conf
    - ODIN_app_for_splunk/metadata/default.meta
    - tools/tests/check-version-sync.sh
    - .gitignore
decisions:
  - Enterprise-only scope locked via --excluded-tags cloud per CONTEXT D9
  - Author = Lyder Hansen, License = Apache-2.0 per CONTEXT D2 defaults
  - TA-ODIN uses export=none (no lookups/savedsearches to export)
  - ODIN_app_for_splunk preserves blanket export=system with expanded rationale
  - check_for_updates = False added to both [package] stanzas (only fixable warning)
metrics:
  duration: ~4 minutes
  tasks: 7
  files: 8
  completed: 2026-04-15
---

# Phase 03 Plan 01: Metadata Polish + Clean AppInspect Baseline Summary

Splunkbase-ready metadata across both apps + explicit `metadata/default.meta` scoping + header-drift guard extension + clean `splunk-appinspect --mode precert --excluded-tags cloud` baseline (both apps: failure=0, error=0).

## Scope (Enterprise-only per CONTEXT D9)

All AppInspect invocations in this plan use `--excluded-tags cloud` to scope the rule catalog to Splunk Enterprise. Cloud Victoria compatibility is deferred to v1.1+ because the 7 Cloud-specific failures surfaced during Phase 3 research would require undoing significant Phase 1 and Phase 2 architectural choices (`.path` wrapper, Windows scripted inputs, saved-search alerts, index config, metadata permissions). Pilots target Enterprise deployments, so Enterprise-only certification is sufficient for v1.0.0.

## Tasks Executed

| # | Name | Commit | Key Files |
|---|------|--------|-----------|
| 1 | Update both app.conf with Splunkbase-ready metadata | `f512d9d` | TA-ODIN/default/app.conf, ODIN_app_for_splunk/default/app.conf |
| 2 | Delete .DS_Store files + canonical gitignore pattern | `821ede7` | .gitignore (disk-only .DS_Store files removed) |
| 3 | Create TA-ODIN/metadata/default.meta with export=none | `342f5b4` | TA-ODIN/metadata/default.meta |
| 4 | Expand ODIN_app_for_splunk/metadata/default.meta rationale | `07d6aa3` | ODIN_app_for_splunk/metadata/default.meta |
| 5 | Extend check-version-sync.sh to catch header-comment drift | `eb6fbf1` | tools/tests/check-version-sync.sh |
| 6 | Add check_for_updates = False to both [package] stanzas | `92323d1` | TA-ODIN/default/app.conf, ODIN_app_for_splunk/default/app.conf |
| 7 | Re-run AppInspect Enterprise scope + commit clean baselines | `dc27c69` | .planning/artifacts/appinspect/{ta-odin,odin-app}-fixed.json |

## Final AppInspect Results (Enterprise scope)

**TA-ODIN:**
```
error:          0
failure:        0
skipped:        0
not_applicable: 7
warning:        1   (check_for_indexer_synced_configs - Victoria Cloud-runtime concern, info only)
success:       13
Total:         21
```

**ODIN_app_for_splunk:**
```
error:          0
failure:        0
skipped:        0
not_applicable: 7
warning:        0   (clean across all severities)
success:       14
Total:         21
```

The single remaining TA-ODIN warning (`check_for_indexer_synced_configs`) is a Cloud Victoria config-replication concern about `default/inputs.conf` not syncing to Victoria-hosted indexers. It is accepted as info-only under Enterprise scope per CONTEXT D9 — TA-ODIN's `inputs.conf` is a forwarder scripted-input stanza that belongs on UFs and never gets pushed to indexers in any deployment topology (two-app split design).

## Deviations from Plan

### Rule 3 — Blocking fix: .DS_Store files were untracked, not tracked

**Found during:** Task 2
**Issue:** Plan Task 2 Step 2 assumed both `.DS_Store` files were tracked by git and called for `git rm`. In reality both files existed on disk only (creation time: Apr 14 23:03, pre-ignore) and were not in the git index. A prior uncommitted `.gitignore` change (staged in the workspace at plan start) had already added per-file paths.
**Fix:** Used `rm -f` instead of `git rm` (since files weren't tracked). Consolidated `.gitignore` from the 8 per-file entries to the canonical `**/.DS_Store` + `.DS_Store` glob with an APPI-01 rationale comment. Smaller and more maintainable than the per-file list.
**Files modified:** `.gitignore` (8 lines → 3 lines with comment)
**Commit:** `821ede7`

### No other deviations

Tasks 1, 3, 4, 5, 6, 7 executed exactly as written in the plan. Task 5 included the induced drift test from the plan's verify block which confirmed the guard exits 1 on header drift and returns to PASS after revert.

## Phase 1/2 Guards Preserved

End-to-end verification that existing invariants still hold:

| Guard | Result |
|-------|--------|
| `bash tools/tests/check-version-sync.sh` | `[HARD-01 PASS] Version sync: 1.0.0` |
| `bash tools/tests/check-two-app-split.sh` | `[HARD-07 PASS] Two-app split is clean` |
| `bash tools/tests/windows-parity-harness.sh` | `Windows parity harness: ALL DIMENSIONS PASSED` |

## Requirements Closed

- **APPI-01** — AppInspect both apps pass precert baseline (under Enterprise scope; Cloud deferred to v1.1+)
- **APPI-02** — Zero failures and zero errors on clean audit (under Enterprise scope)
- **APPI-04** — Both app.conf files have canonical metadata: author, description, license, version, build, id
- **APPI-05** — metadata/default.meta files exist with explicit scoping + auditable rationale comments in both apps

**Deferred to Plan 2 (Wave 1):**
- **APPI-03** — CI workflow hard-gate integration (AppInspect runs on every PR/push, `.DS_Store` re-creation smoke test)
- **APPI-06** — Full-repo red-flag grep validation

## Key Decisions

1. **Enterprise-only scope (D9)**: All AppInspect runs use `--excluded-tags cloud`. Cloud Victoria compatibility deferred to v1.1+ because the 7 Cloud-specific findings would each require undoing significant Phase 1/Phase 2 architecture. Documented in both SUMMARY.md and CONTEXT.md D9.
2. **Metadata defaults (D2)**: Author = Lyder Hansen (public GitHub repo owner), License = Apache-2.0 (Splunkbase-friendly permissive), descriptions ~260 chars each (within AppInspect ~400 char limit).
3. **Asymmetric default.meta scoping (D3)**: TA-ODIN gets `export = none` (nothing to export), ODIN_app_for_splunk preserves blanket `export = system` with expanded rationale (narrower scoping would break the TA-ODIN → ODIN_app_for_splunk data path for operators running ad-hoc queries outside the app context).
4. **Header-drift guard (D6)**: Extended check-version-sync.sh to `head -n 10 | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+'`. Scoped to first 10 lines to avoid false positives on inline descriptions. Shellcheck-clean.
5. **check_for_updates = False (D9)**: Added to both `[package]` stanzas to close the single fixable Enterprise-scope warning (`check_for_updates_disabled`). Canonical value for apps distributed via Deployment Server or Splunkbase without an upstream auto-update URL.

## Artifacts

- `.planning/artifacts/appinspect/ta-odin-fixed.json` — clean TA-ODIN baseline (Enterprise scope)
- `.planning/artifacts/appinspect/odin-app-fixed.json` — clean ODIN_app_for_splunk baseline (Enterprise scope)
- Previous baselines from aeb3cdc (`ta-odin-initial.json`, `odin-app-initial.json`) still in place as pre-fix comparison

## Next Plan (Plan 2)

Plan 2 (Wave 1) wires AppInspect into `.github/workflows/ci.yml` as a mandatory CI gate, runs a `.DS_Store` re-creation smoke test (empirically caught by `check_that_extracted_splunk_app_does_not_contain_prohibited_directories_or_files`), does the full-repo red-flag grep (APPI-06), and produces the final clean-audit + phase-level SUMMARY.

## Self-Check: PASSED

- FOUND: TA-ODIN/default/app.conf (author = Lyder Hansen, license = Apache-2.0, version = 1.0.0, check_for_updates = False)
- FOUND: ODIN_app_for_splunk/default/app.conf (author = Lyder Hansen, license = Apache-2.0, version = 1.0.0, check_for_updates = False)
- FOUND: TA-ODIN/metadata/default.meta (export = none)
- FOUND: ODIN_app_for_splunk/metadata/default.meta (5× export = system, APPI-05 rationale)
- FOUND: tools/tests/check-version-sync.sh (header comment scan block)
- FOUND: .gitignore (**/.DS_Store pattern)
- FOUND: .planning/artifacts/appinspect/ta-odin-fixed.json (failure=0, error=0)
- FOUND: .planning/artifacts/appinspect/odin-app-fixed.json (failure=0, error=0)
- FOUND commit f512d9d (Task 1)
- FOUND commit 821ede7 (Task 2)
- FOUND commit 342f5b4 (Task 3)
- FOUND commit 07d6aa3 (Task 4)
- FOUND commit eb6fbf1 (Task 5)
- FOUND commit 92323d1 (Task 6)
- FOUND commit dc27c69 (Task 7)
