---
status: complete
phase: 04-windows-classification-data
source: [04-01-SUMMARY.md, 04-02-SUMMARY.md, 04-VERIFICATION.md]
started: 2026-04-17T13:30:00Z
updated: 2026-04-17T14:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Row count growth — all 4 CSVs meet ROADMAP success criteria 1–4
expected: `wc -l` returns: services ≥357, ports ≥224, packages ≥304, log_sources ≥289
result: pass

### 2. Linux rows preserved byte-for-byte — no Phase 4 modification of v1.0.0 baseline
expected: `git diff v1.0.0..HEAD -- ODIN_app_for_splunk/lookups/*.csv | grep -E '^-[^-]' | wc -l` returns 0
result: pass

### 3. PROD-01 regression script passes
expected: `bash tools/tests/check-windows-classification.sh` exits 0 and prints `[PROD-01 PASS]`
result: pass

### 4. Sysmon row uses XmlWinEventLog: prefix (RESEARCH §8 pitfall #4)
expected: exactly 1 row with `XmlWinEventLog:Microsoft-Windows-Sysmon/Operational`; 0 rows with wrong `WinEventLog:` prefix
result: pass

### 5. transforms.conf NOT modified by Phase 4
expected: `git diff v1.0.0..HEAD -- transforms.conf` is empty
result: pass

### 6. Cross-CSV TA validation
expected: every recommended_ta in odin_log_sources.csv exists in odin_recommended_tas.csv OR is Splunk_TA_windows. Result: 46 distinct TAs, 128 references, 0 unknown.
result: pass

### 7. D5 hybrid recommended_ta strategy — baseline marker present
expected: at least 7 rows with `[baseline only` description marker. Result: 8 rows (Print Server, Hyper-V, ADFS, WSUS, ADCS, NPS, DFS-R, Failover Cluster).
result: pass

### 8. ODIN_app_for_splunk passes AppInspect Enterprise scope (no Phase 4 regression)
expected: failure=0, error=0, warning=0. Result: byte-identical to Phase 3 baseline.
result: pass

### 9. Synthetic Windows host classifies to ≥3 D1 cross-platform host_roles
expected: W3SVC + MSSQLSERVER + LanmanServer signals resolve through odin_log_sources to ≥3 distinct D1 host_roles. Result: web_server + database_server + file_server with correct recommended_tas (Splunk_TA_microsoft-iis, Splunk_TA_microsoft_sqlserver, Splunk_TA_windows).
result: pass

### 10. Phase 1+2+3 regression suite preserved
expected: check-version-sync, check-two-app-split, injection-fixtures (10/10), windows-parity-harness (all dimensions) exit 0.
result: pass

## Summary

total: 10
passed: 10
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

<!-- None. D-04-01 (duplicate port keys from pre-Phase-4 commit da1f66e) and D-04-02 (legacy role names in services.csv from same commit) are documented in deferred-items.md and do NOT affect PROD-01 acceptance — Phase 4's new rows use D1-correct values throughout. -->
