---
phase: 04-windows-classification-data
plan: 02
subsystem: classification-data
tags: [windows, splunk-lookups, csv, packages, log-sources, recommended-tas, appinspect, regression-guard]

# Dependency graph
requires:
  - phase: 04-windows-classification-data/01
    provides: 25 Windows service rows (W3SVC, MSSQLSERVER, NTDS, MSExchangeTransport, LanmanServer, Spooler, vmms, adfssrv, TermService, CcmExec, WsusService, CertSvc, IAS, DFSR, ClusSvc, WinRM, ...) and 18 Windows port rows in odin_classify_services.csv / odin_classify_ports.csv that Plan 02 log_source rows reference via signal_type=service / signal_type=port keys
  - phase: 03-appinspect-baseline
    provides: AppInspect Enterprise scope clean baseline + --excluded-tags cloud convention + ~/Library/Python/3.9/bin/splunk-appinspect 4.1.3 binary
provides:
  - 34 Windows package wildcard rows in odin_classify_packages.csv (D3 wildcard patterns; transforms.conf already supports WILDCARD per RESEARCH §1)
  - 23 Windows log_source mapping rows in odin_log_sources.csv with cross-CSV TA registry validation (D5 hybrid recommended_ta strategy with [baseline only ...] markers)
  - tools/tests/check-windows-classification.sh — shellcheck-clean PROD-01 regression guard implementing ROADMAP §Phase 4 success criteria 1-5 as shell assertions
  - .planning/artifacts/appinspect/odin-app-phase04-final.json — AppInspect Enterprise-scope final baseline (failure=0, error=0)
  - PROD-01 fully closed (Plans 01 + 02 together)
affects: [05-operational-readiness, 06-pilot-validation]

# Tech tracking
tech-stack:
  added: []  # Data-only plan + one shell test; no new tools or libraries
  patterns:
    - "Cross-CSV TA registry validation: every recommended_ta value in odin_log_sources.csv must exist in odin_recommended_tas.csv OR be Splunk_TA_windows baseline (Python csv.DictReader join enforced in both Plan T2 verify and the regression guard)"
    - "Hybrid log_path representation: WinEventLog://channel for Event Log channels + Windows file paths (C:\\inetpub\\..., C:\\Program Files\\...) for file-based logs — directly copyable into Splunk_TA_windows or Splunk_TA_microsoft-iis inputs.conf stanzas without translation"
    - "Baseline-only TA marker convention: [baseline only - no dedicated Splunkbase TA] description prefix makes the 'canonical Splunkbase TA exists' vs 'baseline Windows umbrella covers it' distinction visible to operators reading the deployment matrix"
    - "Sysmon XML format: Sysmon row uses XmlWinEventLog: prefix per Splunk_TA_microsoft_sysmon canonical sourcetype (RESEARCH §8 pitfall #4) — distinct from generic WinEventLog: prefix used by everything else"

key-files:
  created:
    - tools/tests/check-windows-classification.sh
    - .planning/artifacts/appinspect/odin-app-phase04-final.json
    - .planning/phases/04-windows-classification-data/04-02-SUMMARY.md
  modified:
    - ODIN_app_for_splunk/lookups/odin_classify_packages.csv (274 → 308 lines, +34 Windows package wildcard rows appended)
    - ODIN_app_for_splunk/lookups/odin_log_sources.csv (274 → 297 lines, +23 Windows log_source mapping rows appended)

key-decisions:
  - "Removed embedded commas from package description fields (e.g., 'Microsoft SQL Server engine (64-bit, any version)' → '... (64-bit any version)') to satisfy plan T1 acceptance criterion #9 which mandates exactly 5 comma-separated fields. Semantic content unchanged; reads identically to a human."
  - "Made schema-header check in regression script CRLF-tolerant via 'tr -d \\r' pipe. odin_log_sources.csv has pre-existing CRLF line endings (predates Phase 4 — present in commit da1f66e and earlier); fixing the line endings is out of scope per the user gating rule. Tolerance is the correct approach so the script works against current state without modifying pre-existing content."
  - "Used grep -F (fixed-string) instead of grep -E (extended regex) in the package-pattern loop of the regression script. Wildcard patterns contain literal '*' and '(' / ')' characters which grep -E interprets as regex metacharacters; -F treats them as literal text, matching the actual CSV content correctly."
  - "All 23 new log_source rows use unique (signal_type, signal_value, log_source) keys distinct from pre-existing Windows rows added in commit da1f66e. Where the plan named a log_source overlapping a pre-existing row, the row was appended anyway because the (signal_type, signal_value, log_source) triple is unique — Splunk lookup behavior is fine with this; both rows enrich the same signal but contribute different log_source/log_path/recommended_ta context."
  - "Cross-CSV TA registry validation enforced both at plan execution time (T2 automated_verify) and as an ongoing regression guard (T3 script). Every appended recommended_ta value validates: 8 distinct TA references — Splunk_TA_microsoft-iis (2x), Splunk_TA_microsoft_sqlserver (2x), Splunk_TA_microsoft_exchange (2x), Splunk_TA_microsoft_sysmon (1x), Splunk_TA_windows (16x baseline). Zero invented TA names."

patterns-established:
  - "Wave 1 of a data-population phase: append remaining lookup rows + add a regression-guard script + run final AppInspect baseline. Symmetric to Wave 0 (services + ports + AppInspect baseline) but adds a shell-assertion test script that institutionalizes the row counts as future-regression detectable."
  - "Cross-CSV referential integrity check via Python csv.DictReader join — same pattern usable for any future lookup that references another lookup (e.g., a saved-search lookup referencing a host_role registry)."

requirements-completed: [PROD-01]  # Plans 01 + 02 together fully satisfy PROD-01

# Metrics
duration: 6min
completed: 2026-04-17
---

# Phase 4 Plan 02: Windows Package Patterns + Log-Source Mapping (Wave 1) Summary

**+34 Windows package wildcard rows + +23 Windows log_source mapping rows appended to ODIN_app_for_splunk lookup CSVs with cross-CSV TA registry validation; shellcheck-clean check-windows-classification.sh regression guard implementing ROADMAP §Phase 4 success criteria 1-5; AppInspect Enterprise scope failure=0/error=0 (byte-identical to Phase 3 + Wave 0 baselines).**

## Performance

- **Duration:** 6 min 4 sec
- **Started:** 2026-04-17T13:11:12Z
- **Completed:** 2026-04-17T13:17:16Z
- **Tasks:** 4 of 4 complete (T1 packages, T2 log_sources, T3 regression script, T4 AppInspect + regression suite)
- **Files modified:** 2 CSVs + 1 new shell test + 1 AppInspect artifact + 1 summary

## Accomplishments

- **odin_classify_packages.csv: 274 → 308 lines** (+34 Windows package wildcard rows). Coverage: SQL Server engine 64/32-bit, SSMS, Common Files, Express; Exchange Server; AD DS / FS / CS / LDS; IIS server + Express dev tooling; Hyper-V; SCCM client + site server; MECM; WSUS; WDS; .NET Framework + .NET 5+; Visual C++ Redistributable; Edge + Edge Update; Office; Teams; OneDrive; Windows Server / 10 / 11; Windows Admin Center; PowerShell standalone; Microsoft Monitoring Agent; SCOM; Sysmon. All wildcard patterns use literal `*` glob per D3 + RESEARCH §4. All rows D1-compliant (`web_server`, `database_server`, `mail_server`, `domain_controller`, `identity_server`, `certificate_server`, `virtualization_host`, `management_server`, `monitoring_server`, `monitoring_agent`, `security_endpoint`, `windows_host`, `windows_management`).
- **odin_log_sources.csv: 274 → 297 lines** (+23 Windows log_source mapping rows). Each row maps a `(signal_type, signal_value)` to host_role + log_source + sourcetype + recommended_ta + log_path + description + daily volume range. Coverage: IIS access + httperr, MSSQL errorlog + Application audit, Exchange transport + protocol, NTDS Directory Service + Security audit, DNS audit + analytical, DHCP operational, SMB Security audit, Print Service operational, Hyper-V VMMS, AD FS Admin, WSUS Application, CertSvc Application, NPS Security, DFS Replication, Failover Cluster, Sysmon (XmlWinEventLog format), RDP session, WinRM PowerShell. 8 rows use canonical Splunkbase TAs (`Splunk_TA_microsoft-iis`, `Splunk_TA_microsoft_sqlserver`, `Splunk_TA_microsoft_exchange`, `Splunk_TA_microsoft_sysmon`); 8 rows use `Splunk_TA_windows` baseline with `[baseline only ...]` description marker; 7 rows use `Splunk_TA_windows` directly without marker (Active Directory + DNS + DHCP + SMB on DC channels which the baseline TA covers natively).
- **tools/tests/check-windows-classification.sh** — new shellcheck-clean executable test script (138 lines). Implements ROADMAP §Phase 4 success criteria 1-5 as shell assertions: row-count growth on all 4 lookup CSVs; canonical Windows service/port/package coverage; Sysmon XmlWinEventLog format guard; ≥7 baseline-only markers; cross-CSV TA registry validation via Python csv.DictReader; synthetic Windows host (W3SVC + MSSQLSERVER + LanmanServer) classifies to ≥3 distinct roles; schema-header drift guards on all 4 CSVs.
- **AppInspect Enterprise scope: failure=0, error=0, warning=0, success=14, na=7** — byte-identical to Phase 3 baseline (`odin-app-final.json`) and to Wave 0 baseline (`odin-app-phase04-wave0.json`). Adding 34 + 23 lookup rows has zero AppInspect impact, as predicted by RESEARCH §6.
- **TA-ODIN AppInspect** (no Phase 4 changes; verification only): failure=0, error=0, warning=1 — pre-existing baseline warning, unchanged. Not committed (no scope change).
- **Phase 1+2+3 regression suite all green:** HARD-01 version-sync (1.0.0), HARD-07 two-app-split, HARD-08 injection-fixtures (10/10), windows-parity-harness (all 6 dimensions, scheduled_task skip per CONTEXT D6), and the new PROD-01 check-windows-classification regression guard.
- **PROD-01 fully closed.** Plans 04-01 (services + ports) + 04-02 (packages + log_sources + regression script + AppInspect) together complete every PROD-01 acceptance criterion in ROADMAP §Phase 4. The regression script institutionalizes the row counts so future commits cannot silently regress them.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add 34 Windows package wildcard rows** — `7f5715a` (feat)
2. **Task 2: Add 23 Windows log_source mapping rows + cross-CSV TA validation** — `d3b9c08` (feat)
3. **Task 3: Create check-windows-classification.sh PROD-01 regression guard** — `6e466fa` (feat)
4. **Task 4: Final AppInspect Enterprise scope + Phase 1+2+3 regression suite** — `15ba0ac` (chore)

**Plan metadata commit:** _final docs commit covering this SUMMARY + STATE + ROADMAP + REQUIREMENTS update added after self-check below._

## Files Created/Modified

- `ODIN_app_for_splunk/lookups/odin_classify_packages.csv` — appended 34 Windows package wildcard rows (rows 275–308). Existing 274 Linux rows untouched.
- `ODIN_app_for_splunk/lookups/odin_log_sources.csv` — appended 23 Windows log_source mapping rows (rows 275–297). Existing 274 rows (Linux + pre-existing Windows from commit `da1f66e`) untouched.
- `tools/tests/check-windows-classification.sh` — new executable shell script (138 lines, shellcheck-clean).
- `.planning/artifacts/appinspect/odin-app-phase04-final.json` — AppInspect Enterprise-scope JSON snapshot after all Phase 4 changes (failure=0, error=0).
- `.planning/phases/04-windows-classification-data/04-02-SUMMARY.md` — this file.

## Decisions Made

- **Removed embedded commas from 2 package description fields** to satisfy plan T1 AC #9 (`awk -F, NF==5`). The plan's required-row literal text included `"... engine (64-bit, any version)"` which would parse as 6 comma-separated fields. Rephrased to `"... engine (64-bit any version)"` and similar for the 32-bit row. Semantically identical; satisfies the field-count gate.
- **Made schema-header check in regression script CRLF-tolerant** via `tr -d '\r'` pipe before grep. `odin_log_sources.csv` has pre-existing CRLF line endings (commit `da1f66e` and earlier) which are out of scope for Phase 4 per the user gating rule. The tolerance approach lets the regression guard work against current state without requiring a CSV rewrite. The other 3 CSVs use LF and the same tr filter is a no-op for them — defensive coding.
- **Used `grep -F` (fixed-string) for package-pattern loop** in the regression script. Wildcard patterns contain `*`, `(`, `)` which `grep -E` interprets as regex metacharacters, causing false negatives. Fixed-string match treats them as literal characters, matching CSV content directly.
- **Cross-CSV TA registry validation as both gate and guard.** Plan T2 `automated_verify` runs the Python join check against `odin_recommended_tas.csv` once at execution time. The regression guard repeats the check on every CI run, so future additions to `odin_log_sources.csv` cannot silently introduce a typo'd TA name without failing the guard.
- **Plan 02's new log_source rows coexist with pre-existing Windows rows from commit `da1f66e`.** Rather than re-name plan-required log_sources to avoid all overlap, verified that the `(signal_type, signal_value, log_source)` triple is unique vs pre-existing rows for all 23 additions. Splunk lookup behavior is fine with multiple rows enriching the same signal — they just contribute different log_source/log_path/recommended_ta context. Operationally this is more thorough coverage, not a defect.
- **Used canonical Splunkbase TA names from RESEARCH §1**: `Splunk_TA_microsoft_exchange` (not `Splunk_TA_exchange`), `Splunk_TA_microsoft_sysmon` (not `TA-microsoft-sysmon`), `Splunk_TA_microsoft-iis` (with hyphen, intentional per the registry's actual entry).
- **Sysmon row uses `XmlWinEventLog:Microsoft-Windows-Sysmon/Operational` sourcetype** per RESEARCH §8 pitfall #4. The `Splunk_TA_microsoft_sysmon` TA expects XML-format event ingestion, not the generic `WinEventLog:` text format.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Plan T1 description fields contained embedded commas, breaking the AC #9 5-field check**
- **Found during:** Task 1 immediately after appending rows
- **Issue:** The plan's literal CSV block included descriptions like `"Microsoft SQL Server engine (64-bit, any version)"` which under `awk -F,` parses as 6 fields, failing AC #9 (`NR>1 && NF != 5 {exit 1}`). The plan author made a syntactic mistake — the AC and the required-row block conflict.
- **Fix:** Removed the offending commas from the 2 affected descriptions: `(64-bit, any version)` → `(64-bit any version)` and `(32-bit, legacy)` → `(32-bit legacy)`. Reads identically to a human; satisfies the field-count gate.
- **Files modified:** `ODIN_app_for_splunk/lookups/odin_classify_packages.csv` only.
- **Verification:** Plan T1 `automated_verify` passes (`T1 PASS`).
- **Committed in:** `7f5715a`

**2. [Rule 1 — Bug] Plan T3 script grep -E pattern with literal parens fails to match**
- **Found during:** Task 3 first run of the new script (`bash tools/tests/check-windows-classification.sh`)
- **Issue:** The plan-supplied script used `grep -qE "^${pkg_pattern},"` with patterns like `'Microsoft SQL Server \*(64-bit)\*'`. Under `grep -E`, the `(` and `)` are regex grouping metacharacters, not literal parens. The pattern matched zero rows even though the row literally exists in the file.
- **Fix:** Switched to `grep -qF` (fixed-string match) and dropped the `\*` escapes (which `grep -F` doesn't need either). All 6 wildcard patterns in the loop now match correctly.
- **Files modified:** `tools/tests/check-windows-classification.sh` only.
- **Verification:** Script reaches `[PROD-01 PASS]`; AC regression-detection test confirms script catches deletions.
- **Committed in:** `6e466fa`

**3. [Rule 1 — Bug] Plan T3 script schema-header check fails on CRLF line endings in log_sources.csv**
- **Found during:** Task 3 first run
- **Issue:** `odin_log_sources.csv` has CRLF line endings (commit `da1f66e` and earlier). `head -1 file | grep -qx 'header'` includes the trailing `\r` in the comparison, so the exact match fails. The other 3 CSVs are LF.
- **Fix:** Inserted `| tr -d '\r'` between `head -1` and `grep -qx` for all 4 schema checks. Defensive: works against either line-ending style. Out of scope per SCOPE BOUNDARY to fix the CRLF in `odin_log_sources.csv` itself (predates Phase 4 by many commits; no operational impact in Splunk; deferred to a future cleanup plan).
- **Files modified:** `tools/tests/check-windows-classification.sh` only.
- **Verification:** Script reaches `[PROD-01 PASS]`.
- **Committed in:** `6e466fa`

**4. [Rule 1 — Bug] Plan T3 script triggers shellcheck SC2028 on `\xc2\xa78` byte-escape in echo**
- **Found during:** Task 3 first shellcheck run
- **Issue:** The plan-supplied script included a Sysmon failure message with `\xc2\xa78` (UTF-8 bytes for the `§` section sign) embedded literally in an `echo` string. shellcheck SC2028 flags this because `echo` does not expand escape sequences portably; the script would print the literal backslash-x sequence rather than the section sign. AC #3 requires `shellcheck` exits 0 (default severity includes `info` rules like SC2028).
- **Fix:** Replaced `\xc2\xa78` with the literal text `section 8`. Functionally equivalent; shellcheck-clean.
- **Files modified:** `tools/tests/check-windows-classification.sh` only.
- **Verification:** `shellcheck tools/tests/check-windows-classification.sh` exits 0.
- **Committed in:** `6e466fa`

---

**Total deviations:** 4 auto-fixed (4 Rule 1 bugs in plan-supplied content)
**Impact on plan:** All 4 deviations are minor textual corrections to plan-supplied text that contradicted the plan's own acceptance criteria. The substantive intent of every plan task is satisfied — 34 wildcard package rows, 23 log_source rows with cross-CSV TA validation, shellcheck-clean regression script, AppInspect clean. No scope creep, no architectural changes.

**Note on D-04-02 legacy roles surfacing in synthetic test output**: When the regression script's synthetic Windows host (W3SVC + MSSQLSERVER + LanmanServer) gets joined through the services lookup, it returns `web` + `database` + `file_server` (3 distinct values, passes the ≥3 check) — but `web` and `database` are the legacy D-04-02 role names from pre-existing commit `da1f66e` rather than the D1-correct `web_server` and `database_server`. The check passes because it counts distinct roles, but it incidentally documents the D-04-02 legacy-role issue. This is expected and consistent with the deferred-items registry — the legacy-role cleanup is tracked there for a future plan.

## Issues Encountered

- **Plan-supplied text vs plan acceptance criteria mismatch (×2).** T1's required-row block had description-field commas that violated T1's own AC #9; T3's script had a `grep -E` pattern with literal parens that wouldn't match. Both are simple corrections but show the value of running the AC checks immediately after applying the plan-supplied content rather than trusting it to be self-consistent.
- **CRLF in `odin_log_sources.csv` is a long-standing pre-existing issue.** Out of scope per the user gating rule. The regression guard now tolerates CRLF; the underlying line-ending normalization can land in a future cleanup plan if desired (no operational impact — Splunk parses CRLF and LF lookups identically).
- **shellcheck `info` severity is included in default exit behavior.** SC2028 is an info-level rule and triggered the failure. The fix (literal text instead of byte-escape) is the right semantic resolution; alternatively a `# shellcheck disable=SC2028` directive would have suppressed the warning. Chose the literal-text fix because it's also more readable.

## User Setup Required

None — Phase 4 is data-only. The new lookup rows take effect at the next search-time lookup invocation after the app is deployed. No runtime, no schema, no permission, no index changes.

## Next Phase Readiness

**Ready for Phase 5 (Operational Readiness — PROD-03..PROD-07).** PROD-01 is fully closed by Plans 04-01 + 04-02 together:
- All 4 lookup CSVs have Windows-specific rows (services 357, ports 224, packages 308, log_sources 297).
- Cross-platform host_role taxonomy (D1) honored — no `windows_iis` / `windows_dc` / etc roles introduced anywhere in Phase 4.
- Cross-CSV TA registry validation enforced as both execution-time gate and ongoing CI guard.
- AppInspect Enterprise scope clean and traceable through 3 baselines (Phase 3 final, Phase 4 wave 0, Phase 4 final).
- Regression-guard shell script institutionalizes the row counts and signal coverage so future PRs cannot silently regress PROD-01 deliverables.

**Considerations for Phase 5:**
- The `check-windows-classification.sh` regression guard should be wired into `.github/workflows/ci.yml` (Phase 5 PROD-04 docs work or a dedicated CI gate). Currently it runs locally but isn't part of automated CI.
- The two D-04 deferred items (D-04-01 duplicate port keys, D-04-02 legacy Windows service role names) remain open. Neither blocks v1.0.1 release — they're cosmetic and don't affect the deployment matrix or host inventory output. If Phase 5 has scope for a "lookup data hygiene" sub-task, both can land there alongside the CRLF normalization for `odin_log_sources.csv`.
- PROD-02 pilot (Phase 6) will exercise these lookup rows against real Windows hardware for the first time. Expect the pilot to surface: (a) wildcard patterns that over-match (T1 from threat model) — log to deferred-items.md; (b) registry display names that don't match any wildcard — add new rows in a follow-up plan.

**Blockers/concerns for downstream phases:** None. Phase 4 leaves the project in a fully-buildable, fully-AppInspect-clean, regression-guard-protected state.

## Threat Model Update

The threat model's T2 (wrong recommended_ta name) was the elevated threat for this plan. Mitigation as planned: cross-CSV join check executed at T2 execution time + permanently enforced by `check-windows-classification.sh`. **Both gates green.** No false-positive TA names introduced.

T3 (operator confusion between canonical TA and baseline fallback) mitigated by the `[baseline only - no dedicated Splunkbase TA]` description marker present on 8 rows. T1 (wildcard over-match) and T4 (information disclosure) unchanged from frontmatter — T1 awaits PROD-02 pilot empirical data; T4 N/A.

No new threat surface introduced by Plan 02. The new shell test reads CSVs only — no network, no privileged operations, no writes outside the test process.

## Self-Check: PASSED

Verified before final commit:

- `ODIN_app_for_splunk/lookups/odin_classify_packages.csv` exists, 308 lines (FOUND)
- `ODIN_app_for_splunk/lookups/odin_log_sources.csv` exists, 297 lines (FOUND)
- `tools/tests/check-windows-classification.sh` exists, executable, shellcheck-clean (FOUND)
- `.planning/artifacts/appinspect/odin-app-phase04-final.json` exists, tracked by git (FOUND)
- Commit `7f5715a` exists in git log (FOUND — `feat(04-02): add 34 Windows package wildcard rows ...`)
- Commit `d3b9c08` exists in git log (FOUND — `feat(04-02): add 23 Windows log_source mapping rows ...`)
- Commit `6e466fa` exists in git log (FOUND — `feat(04-02): add check-windows-classification.sh PROD-01 regression guard`)
- Commit `15ba0ac` exists in git log (FOUND — `chore(04-02): commit AppInspect Phase 4 final baseline ...`)
- Phase 1+2+3 regression suite green (HARD-01, HARD-07, HARD-08, windows-parity-harness, plus new PROD-01 guard)
- AppInspect summary `failure=0, error=0, warning=0, success=14, na=7` byte-identical to Phase 3 + Wave 0 baselines

---
*Phase: 04-windows-classification-data*
*Completed: 2026-04-17*
