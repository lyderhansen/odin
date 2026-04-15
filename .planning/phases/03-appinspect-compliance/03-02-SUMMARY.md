---
phase: 03-appinspect-compliance
plan: 02
subsystem: appinspect-compliance
tags: [appinspect, ci, github-actions, hard-gate, enterprise-scope, release-gate]
requires: [03-01 metadata polish + clean baseline]
provides:
  - AppInspect as mandatory CI gate (APPI-03)
  - APPI-06 red-flag grep verification (zero hits in executable scripts)
  - Final clean AppInspect baselines for v1.0.0 release (APPI-01, APPI-02)
  - End-to-end proof that CI gate fails on bad input (.DS_Store smoke test)
affects:
  - .github/workflows/ci.yml
  - .planning/artifacts/appinspect/ta-odin-final.json
  - .planning/artifacts/appinspect/odin-app-final.json
tech-stack:
  added: [splunk-appinspect==4.1.3 pinned in CI]
  patterns:
    - JSON-parse hard-gate wrapper around splunk-appinspect (CLI exit is always 0)
    - Enterprise-only scope via --excluded-tags cloud in CI
    - .DS_Store re-creation smoke test (empirically proven detection per RESEARCH §11.5)
key-files:
  created:
    - .planning/artifacts/appinspect/ta-odin-final.json
    - .planning/artifacts/appinspect/odin-app-final.json
  modified:
    - .github/workflows/ci.yml
decisions:
  - Pin splunk-appinspect to 4.1.3 to freeze rule catalog for v1.0.0
  - JSON-parse Python wrapper is the hard gate, not AppInspect's own exit code
  - Smoke test uses .DS_Store re-creation (proven) instead of http:// injection (disproven per RESEARCH §11.5)
  - Final JSON artifacts named *-final.json (not dated) to act as stable shipping baselines
metrics:
  duration: ~3 minutes
  tasks: 4
  files: 3
  completed: 2026-04-15
---

# Phase 03 Plan 02: CI Workflow + Red-Flag Grep + Final Clean Baseline Summary

Wires AppInspect into `.github/workflows/ci.yml` as a mandatory release gate on top of Phase 2's 5 quality-gate steps (now 8 steps total). Runs the APPI-03 deliberate-violation smoke test locally (detection -> revert -> clean re-audit). Runs the APPI-06 full-repo red-flag grep. Captures the final clean AppInspect JSON baselines for both apps. Phase 3 is now code-complete and ready for `/gsd-verify-work 3`.

## Scope (Enterprise-only per CONTEXT D9)

All AppInspect invocations — in CI and locally — use `--mode precert --excluded-tags cloud` to scope the rule catalog to Splunk Enterprise. Cloud Victoria compatibility remains deferred to v1.1+ per the rationale in Plan 01's SUMMARY.md and CONTEXT.md D9. v1.0.0 targets Enterprise pilots; Enterprise-only certification is the correct scope for this milestone.

## Tasks Executed

| # | Name | Commit | Key Files |
|---|------|--------|-----------|
| 1 | Extend ci.yml with 3 AppInspect steps (install + TA-ODIN + ODIN_app_for_splunk) | `6f21ad3` | .github/workflows/ci.yml |
| 2 | APPI-03 hard-gate smoke test (.DS_Store injection, detection, revert, clean re-audit) | pure verification — no commit | (no file changes) |
| 3 | APPI-06 red-flag grep — zero hits in executable scripts | pure verification — no commit | (no file changes) |
| 4 | Final clean AppInspect audit + commit final JSON baselines | `e82ab24` | .planning/artifacts/appinspect/ta-odin-final.json, .planning/artifacts/appinspect/odin-app-final.json |

## Task 1 — CI Workflow Diff

Before (Phase 2, 5 quality-gate steps): Checkout, Shellcheck, PSScriptAnalyzer, Two-app split, Version sync, Injection fixture.

After (Phase 3, 8 quality-gate steps): the above **plus**:

```yaml
      - name: Install splunk-appinspect
        run: pip install 'splunk-appinspect==4.1.3'

      - name: AppInspect TA-ODIN
        run: |
          splunk-appinspect inspect TA-ODIN --mode precert --excluded-tags cloud --output-file /tmp/ta-odin-ci.json --data-format json
          python3 -c "import json, sys; s=json.load(open('/tmp/ta-odin-ci.json'))['summary']; print('TA-ODIN AppInspect summary:', s); sys.exit(1 if (s.get('failure',0)+s.get('error',0))>0 else 0)"

      - name: AppInspect ODIN_app_for_splunk
        run: |
          splunk-appinspect inspect ODIN_app_for_splunk --mode precert --excluded-tags cloud --output-file /tmp/odin-app-ci.json --data-format json
          python3 -c "import json, sys; s=json.load(open('/tmp/odin-app-ci.json'))['summary']; print('ODIN_app_for_splunk AppInspect summary:', s); sys.exit(1 if (s.get('failure',0)+s.get('error',0))>0 else 0)"
```

**Pure additions** — `git diff` shows zero lines removed. All 5 existing Phase 2 steps preserved byte-for-byte, SHA-pinned `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683` kept.

**Version pin confirmed:** `grep 'splunk-appinspect==4.1.3' .github/workflows/ci.yml` = 1 hit. This freezes the rule catalog for v1.0.0. Any future rule-set tightening (v4.1.4+) cannot silently fail our CI.

**Hard-gate mechanic:** AppInspect's own CLI exit code is always 0 (it reports findings, not errors). The JSON-parse wrapper (`sys.exit(1 if failure+error > 0 else 0)`) is what makes the step enforceable. Both AppInspect steps have the wrapper — `grep -c 'sys.exit(1 if' .github/workflows/ci.yml` = 2.

## Task 2 — APPI-03 Hard-Gate Smoke Test

Executed end-to-end locally to prove the CI gate fires on bad input. Per RESEARCH §11.5, the original http:// injection strategy was empirically disproven (http:// in a comment is NOT caught by AppInspect 4.1.3 under either bare `precert` or `precert --excluded-tags cloud`). The replacement strategy uses `.DS_Store` re-creation, which is reliably caught by `check_that_extracted_splunk_app_does_not_contain_prohibited_directories_or_files` and is NOT cloud-tagged (fires under Enterprise scope too).

**Cycle executed:**

| Step | Action | Result |
|------|--------|--------|
| 1 — Pre-state | `find TA-ODIN -name .DS_Store` + baseline audit | Empty output; `{failure:0, error:0, warning:1, success:13, n/a:7}` |
| 2 — Inject | `touch TA-ODIN/.DS_Store` | File exists (0 bytes) |
| 3 — Detect | `splunk-appinspect inspect TA-ODIN --mode precert --excluded-tags cloud` | **`{failure:1, error:0, success:9, skipped:9, n/a:2}`** — rule `check_that_extracted_splunk_app_does_not_contain_prohibited_directories_or_files` fired by name |
| 4 — Revert | `rm -f TA-ODIN/.DS_Store` | `find` returns empty |
| 5 — Re-audit | `splunk-appinspect inspect TA-ODIN ...` | `{failure:0, error:0, warning:1, success:13, n/a:7}` — identical to pre-state |
| 6 — Working tree | `git diff --quiet TA-ODIN/` | Exits 0 — byte-identical to pre-state |

**APPI-03 proven end-to-end.** The CI gate will fail on injected prohibited files. The revert cycle confirms no residual working-tree state. `git diff` is clean.

## Task 3 — APPI-06 Red-Flag Grep

```bash
grep -RIEn 'http[s]?://|Invoke-Expression|Add-Type|FromBase64String|/usr/local/bin|C:\\\\' TA-ODIN/ ODIN_app_for_splunk/
```

**Total hits:** 48.

**Classified:**

| File type | Hit count | Disposition |
|-----------|-----------|-------------|
| `.sh` (bash scripts) | **0** | HARD CONSTRAINT MET |
| `.ps1` (PowerShell scripts) | **0** | HARD CONSTRAINT MET |
| `.conf` | 0 | — |
| `.csv` | 47 | ALL legitimate `https://splunkbase.splunk.com/app/<id>` URLs in `ODIN_app_for_splunk/lookups/odin_recommended_tas.csv` — reference data for TA deployment recommendations. Splunkbase is the canonical source; URLs are expected. |
| `.meta` | 0 | — |
| Other (README.md) | 1 | `TA-ODIN/README.md:108` contains `/usr/local/bin/backup.sh` inside a sample cron event output in documentation. Not executable code, not shipped with the TA runtime. |

**APPI-06 verified:** zero red-flag patterns in `.sh` or `.ps1` executable code. All non-script hits are legitimate reference data or documentation examples with clear rationale. No files modified during this task.

## Task 4 — Final Clean AppInspect Audit

Final baseline captured under Enterprise scope (`--mode precert --excluded-tags cloud`):

**TA-ODIN** (`.planning/artifacts/appinspect/ta-odin-final.json`):
```
error:          0
failure:        0
skipped:        0
not_applicable: 7
warning:        1   (check_for_indexer_synced_configs — Cloud-runtime concern, accepted per CONTEXT D9)
success:       13
Total:         21
```

**ODIN_app_for_splunk** (`.planning/artifacts/appinspect/odin-app-final.json`):
```
error:          0
failure:        0
skipped:        0
not_applicable: 7
warning:        0   (fully clean)
success:       14
Total:         21
```

Both reports committed in `e82ab24` as the shipping artifacts for v1.0.0. They replace the Plan 1 `*-fixed.json` baselines as the definitive final audit.

## Phase 3 Nyquist Dimensions

| # | Dimension | Evidence | Status |
|---|-----------|----------|--------|
| 1 | TA-ODIN AppInspect clean | `ta-odin-final.json` summary.failure = 0, error = 0 | PASS |
| 2 | ODIN_app_for_splunk AppInspect clean | `odin-app-final.json` summary.failure = 0, error = 0 | PASS |
| 3 | APPI-06 red-flag grep on executable scripts | 0 hits in `.sh` + `.ps1` files | PASS |
| 4 | APPI-04 metadata fields complete | Both app.conf files: `grep -cE '^(author|description|license|version)'` = 4 | PASS |

## Phase 2 Preservation

All 5 Phase 2 quality gates still pass (regression check executed as part of Task 4 Step 4):

| Guard | Result |
|-------|--------|
| `bash tools/tests/check-version-sync.sh` | `[HARD-01 PASS] Version sync: 1.0.0` |
| `bash tools/tests/check-two-app-split.sh` | `[HARD-07 PASS] Two-app split is clean` |
| `shellcheck TA-ODIN/bin/odin.sh TA-ODIN/bin/modules/*.sh` | clean |
| `pwsh Invoke-ScriptAnalyzer -Severity Error,Warning` | 0 findings |
| `bash tools/tests/injection-fixtures/run.sh` | `[HARD-08] 10 passed, 0 failed` |

## Phase 1 Preservation

`bash tools/tests/windows-parity-harness.sh` — `Windows parity harness: ALL DIMENSIONS PASSED` (Dim 1–6 all green, Dim 5 scheduled_task skip per CONTEXT D6 preserved).

## Deviations from Plan

None. Tasks 1–4 executed exactly as written. The plan itself already incorporated the RESEARCH §11.5 empirical correction from the original http:// smoke test to the .DS_Store strategy, so no Rule-3 blocking fix was needed during execution. Task 1's YAML edit was a pure append (no deletions). Task 2's smoke cycle produced the expected detection/revert/clean sequence on first attempt.

## Requirements Closed

- **APPI-01** — Both apps pass AppInspect precert (confirmed via final JSON reports under Enterprise scope)
- **APPI-02** — Zero failures and zero errors on final clean audit (both apps)
- **APPI-03** — AppInspect wired into `.github/workflows/ci.yml` as a hard gate (JSON-parse wrapper); smoke test proves the gate fails on bad input
- **APPI-04** — Already closed in Plan 01; re-verified in Task 4 Dim 4
- **APPI-05** — Already closed in Plan 01; not touched in this plan
- **APPI-06** — Red-flag grep returns zero hits in executable scripts; non-script hits documented and accepted

## Hand-off

Phase 3 is **code-complete**. All 6 APPI-* requirements are satisfied. CI workflow has 8 mandatory quality gates (5 Phase 2 + 3 Phase 3). The final JSON baselines are committed as `.planning/artifacts/appinspect/{ta-odin,odin-app}-final.json`.

**Next steps for the operator:**
1. Run `/gsd-verify-work 3` to attest the Phase 3 requirements via the verifier sub-agent.
2. After all three phases are verified, run `/gsd-ship` (or push to `main`) which will trigger the first PR-gated CI run exercising the new AppInspect steps end-to-end on ubuntu-latest.
3. Tag `v1.0.0` once verification passes. The tarballs (`TA-ODIN/` and `ODIN_app_for_splunk/`) are pilot-deliverable with no ad-hoc pre-flight work.

**Operational note on branch protection** (per threat model T-03-02-03): The CI workflow is only enforceable if GitHub branch protection on `main` requires the `quality-gates` job to pass before merge. Configure this in repo Settings → Branches outside this plan's scope.

## Self-Check: PASSED

- FOUND: .github/workflows/ci.yml (3 new AppInspect steps, splunk-appinspect==4.1.3 pinned, JSON hard-gate wrapper)
- FOUND: .planning/artifacts/appinspect/ta-odin-final.json (failure=0, error=0)
- FOUND: .planning/artifacts/appinspect/odin-app-final.json (failure=0, error=0)
- FOUND commit 6f21ad3 (Task 1 — CI workflow extension)
- FOUND commit e82ab24 (Task 4 — final JSON baselines)
- Task 2 + Task 3 are pure-verification tasks with no commits (documented in Tasks table)
