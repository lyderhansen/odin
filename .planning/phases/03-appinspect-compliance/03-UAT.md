---
status: complete
phase: 03-appinspect-compliance
source: [03-01-SUMMARY.md, 03-02-SUMMARY.md, 03-VERIFICATION.md]
started: 2026-04-15T00:00:00Z
updated: 2026-04-15T00:30:00Z
---

## Current Test

[testing complete]

## Tests

### 1. APPI-01 prohibited files removed + canonical gitignore
expected: `find TA-ODIN ODIN_app_for_splunk -name .DS_Store` returns empty AND `.gitignore` contains `**/.DS_Store`
result: pass

### 2. APPI-02 metadata/default.meta present in both apps
expected: `test -f TA-ODIN/metadata/default.meta && test -f ODIN_app_for_splunk/metadata/default.meta && echo ok` prints `ok`
result: pass

### 3. APPI-04 Splunkbase-ready metadata in both app.conf files
expected: both app.conf files contain `author =`, `description =`, `label =`, `version = 1.0.0`
result: pass

### 4. APPI-05 check_for_updates = False in both [package] stanzas
expected: `grep -c 'check_for_updates = False' TA-ODIN/default/app.conf ODIN_app_for_splunk/default/app.conf` shows 1 in each file
result: pass

### 5. APPI-03 CI workflow has AppInspect hard-gate wired up
expected: `.github/workflows/ci.yml` contains `splunk-appinspect==4.1.3` pinned and two `sys.exit(1` JSON-parse hard-gate wrappers (one per app), total 12 named steps (5 Phase 2 gates + 3 Phase 3 AppInspect steps + 4 setup/housekeeping)
result: pass

### 6. APPI-06 no http:// red flags in executable scripts
expected: `grep -rE 'http://' TA-ODIN/bin --include='*.sh' --include='*.ps1'` returns 0 hits
result: pass

### 7. TA-ODIN passes AppInspect under Enterprise scope
expected: `splunk-appinspect inspect TA-ODIN --mode precert --excluded-tags cloud` returns failure=0 error=0 (warning=1 accepted per D9)
result: pass

### 8. ODIN_app_for_splunk passes AppInspect under Enterprise scope
expected: `splunk-appinspect inspect ODIN_app_for_splunk --mode precert --excluded-tags cloud` returns failure=0 error=0 warning=0
result: pass

### 9. .DS_Store smoke test: AppInspect reliably detects prohibited files
expected: injecting `TA-ODIN/.DS_Store` produces failure=1 AND fires `check_that_extracted_splunk_app_does_not_contain_prohibited_directories_or_files`; post-revert working tree is clean
result: pass

### 10. Phase 1+2 regression preserved — all prior guards still green
expected: `check-version-sync.sh`, `check-two-app-split.sh`, `injection-fixtures/run.sh`, `windows-parity-harness.sh` all exit 0
result: pass

## Summary

total: 10
passed: 10
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

<!-- None -->
