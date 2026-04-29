---
status: complete
phase: 09-validation-docs-dashboard
source: [09-01-SUMMARY.md, 09-02-SUMMARY.md, 09-03-SUMMARY.md]
started: 2026-04-29T15:00:00Z
updated: 2026-04-29T16:15:00Z
---

## Current Test

[testing complete]

## Tests

### 1. HOST-01 — Linux orchestrator emits odin_host_info
expected: |
  `bash TA-ODIN/bin/odin.sh 2>&1 | grep 'type=odin_host_info'` returns exactly 1
  line containing all 13 fields. `bash tools/tests/check-host-info.sh` prints
  `[HOST-01 PASS] All checks passed` and exits 0. Field values look real
  (os_pretty is a recognizable distro name, cpu_cores is a positive integer,
  fqdn is the actual hostname).
result: pass
notes: |
  Verified on Rocky Linux 9.3 container. All 13 fields present:
  os_distro=rocky, os_version=9.3, os_pretty="Rocky Linux 9.3 (Blue Onyx)",
  os_kernel=6.12.76-linuxkit, os_arch=x86_64, cpu_cores=12, mem_total_mb=11947,
  uptime_seconds=451178, fqdn=e0c0ddd5630b, ip_primary=unknown,
  virtualization=container, cloud_provider=none, cloud_region=none.
  Container-environmental: ip_primary=unknown (no outbound network in this
  container), fqdn=short-id-only (Docker default, no DNS domain). Both are
  correct sentinel/value behavior per D-03 + spec.

### 2. HOST-02 — Windows orchestrator emits odin_host_info (parity)
expected: |
  On a real Windows host: `powershell.exe -ExecutionPolicy Bypass -File TA-ODIN\bin\odin.ps1 | Select-String 'type=odin_host_info'`
  returns exactly 1 line with all 13 fields populated by Windows-native methods
  (CIM/Get-NetRoute/IMDS). `powershell.exe -File tools\tests\check-host-info.ps1`
  exits 0 with 5 [HOST-02 PASS] markers. CIM-derived fields look real (os_pretty
  like "Microsoft Windows 11 Pro", virtualization matches ground truth).
  If no Windows VM is available: respond "blocked - need Windows host" or "skip".
result: pass
notes: |
  Verified on Windows 11 ARM64 in VMware/Parallels VM with Windows PowerShell 5.1.
  Orchestrator output: 13 fields populated — os_distro=windows, os_version=10.0.26100,
  os_pretty="Microsoft Windows 11 Pro", os_kernel=26100, os_arch=arm64, cpu_cores=2,
  mem_total_mb=4091, uptime_seconds=204165, fqdn=test, ip_primary=172.16.156.128,
  virtualization=vmware, cloud_provider=none, cloud_region=none.
  check-host-info.ps1 exits 0 with 5 [HOST-02 PASS] + final summary marker.
  Required 3 in-UAT fix commits to make the regression test PS5.1-compatible:
    - 4cc234a: parser quirk fix (Write-Host "[HOST-02 ...]" → single-quote/-f format)
    - 1771688: minimal precursor (lines 41+100 only — superseded by 4cc234a)
    - 571e6e7: Join-Path arity (PS5.1 only takes 2 positional args) + ASCII-only output
  Production code (TA-ODIN\bin\odin.ps1, _common.ps1) was correct from Phase 8 — only
  the regression test needed PS5.1 hardening. Phase 8 verifier had a blindspot:
  validated via pwsh on macOS, missed PS5.1-specific behaviors.

### 3. HOST-03 — Cross-platform parity test
expected: |
  `bash tools/tests/check-host-info-parity.sh` prints
  `[HOST-03 PASS] Linux + Windows field-set parity confirmed (13 fields each)`
  and exits 0. On a host without pwsh, the same script prints `[HOST-03 SKIP]`
  and exits 0 (no false failure).
result: pass
notes: |
  Verified on macOS dev-box (Apple Silicon, pwsh 7.5.4 installed):
  `[HOST-03 PASS] Linux + Windows field-set parity confirmed (13 fields each)`
  exit 0. Confirms field-NAME parity (envelope-stripped count = 13 not 19).
  Skip-path optional bonus test deferred — already verified by Phase 9 verifier.

### 4. HOST-04 — DATA-DICTIONARY documents odin_host_info
expected: |
  Open `DOCS/DATA-DICTIONARY.md`. Section `## type=odin_host_info` exists between
  `## type=odin_start` and `## type=odin_complete`. Has overview paragraph, worked
  example event line (Rocky Linux on AWS KVM), all 13 fields documented with
  per-field structure (Description + Source (Linux) + Source (Windows) + Example),
  and a `### Cloud detection timeout semantics` subsection with the 3-4s worst-case
  AWS IMDSv2 explanation + `ODIN_IMDS_TIMEOUT` override.
result: pass
notes: |
  Verified via grep -nE structural extraction. Section placement correct
  (line 59, between line 40 odin_start and line 220 odin_complete). All 13
  field headings present (lines 82-173). Overview paragraph (lines 61-70)
  references v1.0.2 dashboards + v1.1.0 container observability prerequisite.
  Worked example line (line 75) shows Rocky Linux on AWS KVM with all 13
  fields populated. Per-field 4-item structure verified via os_distro example.
  Cloud detection timeout subsection (lines 180-218) includes AWS IMDSv2
  two-call explanation, sequential vs parallel trade-off, sentinel value
  table (aws/gcp/azure vs none vs unknown), Splunk SPL filter examples,
  and ODIN_IMDS_TIMEOUT override.

### 5. HOST-05 — Dashboard panels added
expected: |
  Open `ODIN_app_for_splunk/default/data/ui/views/odin_overview.xml`. JSON parses
  cleanly. Two new panels exist: `viz_os_distribution` (splunk.pie, queries
  `count by os_distro,os_version`) and `viz_virtualization_breakdown`
  (splunk.column, queries `count by virtualization`). Both placed side-by-side at
  y:1880 (x:0 and x:600, width 600 each). Visualization count = 12 (was 10 at
  v1.0.1-rc1). AppInspect baseline `.planning/artifacts/appinspect/odin-app-1.0.2-phase9.json`
  shows failure=0, error=0, warning=0. (Live Splunk render is optional — if no
  Splunk instance handy, respond "skip - no Splunk instance" for that part.)
result: pass
notes: |
  Verified via Phase 9 verifier (status: VERIFIED 2026-04-29T14:30:00Z):
  JSON parse OK, viz count = 12 (was 10), both viz_os_distribution and
  viz_virtualization_breakdown present in visualizations + layout, side-by-side
  at y:1880 (x:0 and x:600). AppInspect baseline failure=0, error=0, warning=0
  (CI-equivalent flags). Live Splunk render deferred — no Splunk instance
  available, but JSON structure + AppInspect verify the contract.

## Summary

total: 5
passed: 5
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none yet]
