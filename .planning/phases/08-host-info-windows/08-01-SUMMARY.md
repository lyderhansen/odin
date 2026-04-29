---
phase: 08-host-info-windows
plan: 01
subsystem: windows-orchestrator
tags: [host-info, windows, powershell, host-metadata, parity]
dependency_graph:
  requires: [07-01]
  provides: [type=odin_host_info on Windows, Invoke-OdinEmitHostInfo, check-host-info.ps1]
  affects: [TA-ODIN/bin/modules/_common.ps1, TA-ODIN/bin/odin.ps1, tools/tests/check-host-info.ps1, DOCS/CHANGEHISTORY.md]
tech_stack:
  added: [Get-CimInstance (Win32_OperatingSystem, Win32_Processor, Win32_ComputerSystem), Get-NetRoute, Get-NetIPAddress, Invoke-RestMethod -UseBasicParsing]
  patterns: [pipe-separated helper returns, try/catch PSCL degradation, D-07 graceful fallback, D-03 sentinel discipline]
key_files:
  created: [tools/tests/check-host-info.ps1]
  modified: [TA-ODIN/bin/modules/_common.ps1, TA-ODIN/bin/odin.ps1, DOCS/CHANGEHISTORY.md]
decisions:
  - "D-05: ODIN_IMDS_TIMEOUT default 1s (mirrors Phase 7 D-02 for cross-platform parity)"
  - "D-06: Get-CimInstance exclusively in new helpers (never Get-WmiObject in Phase 8 code)"
  - "D-07: PSCL graceful degradation — try/catch + 'unknown' sentinel on every CIM/Net call"
  - "Rule 1 fix: wrap function calls in parens before -split operator (operator precedence)"
metrics:
  duration: "~15 min"
  completed: "2026-04-29"
  tasks_completed: 10
  tasks_total: 10
  files_changed: 4
---

# Phase 8 Plan 1: HOST-02 Windows Mirror — Host Metadata Enrichment Summary

8 PowerShell mirror helpers + Invoke-OdinEmitHostInfo aggregator wired into Windows orchestrator, emitting one `type=odin_host_info` event with all 13 fields per scan; parity with Phase 7 Linux implementation established.

## What Was Built

Phase 8 mirrors Phase 7's Linux `emit_host_info` implementation byte-for-byte (modulo platform-specific API differences) by extending `TA-ODIN/bin/modules/_common.ps1` with 8 PowerShell detection helpers:

| Helper | Bash Mirror | Fields | Windows API |
|--------|-------------|--------|-------------|
| `Get-OdinOsDistro` | `detect_os_distro` | os_distro, os_version, os_pretty | Win32_OperatingSystem.Caption/.Version |
| `Get-OdinOsKernelArch` | `detect_os_kernel_arch` | os_kernel, os_arch | Win32_OperatingSystem.BuildNumber + PROCESSOR_ARCHITECTURE |
| `Get-OdinHardware` | `detect_hardware` | cpu_cores, mem_total_mb | Win32_Processor.NumberOfCores sum + TotalVisibleMemorySize/1024 |
| `Get-OdinRuntimeUptime` | `detect_runtime_uptime` | uptime_seconds | (Get-Date) - LastBootUpTime |
| `Get-OdinNetwork` | `detect_network` | fqdn, ip_primary | DNS.GetHostByName + Get-NetRoute/Get-NetIPAddress |
| `Get-OdinVirtualization` | `detect_virt` | virtualization | Win32_ComputerSystem.Manufacturer+Model cascade |
| `Invoke-OdinCloudImds` | `probe_cloud_imds` | cloud_provider, cloud_region | Invoke-RestMethod sequential AWS/GCP/Azure |
| `Invoke-OdinEmitHostInfo` | `emit_host_info` | (aggregator) | Calls all above + Invoke-OdinEmit |

`_common.ps1` grew from 178 → 536 lines. One call site added to `odin.ps1` (line 103, between odin_start emit and modules loop). New regression test `tools/tests/check-host-info.ps1` mirrors `check-host-info.sh` with `[HOST-02]` token convention and WR-03 SKIP guards.

## Tasks Completed

| Task | Name | Commit | Key Changes |
|------|------|--------|-------------|
| T1 | ODIN_IMDS_TIMEOUT env-var | `1b74c08` | 4 lines added to _common.ps1 top section |
| T2 | OS detection (5 fields) | `9478668` | Get-OdinOsDistro + Get-OdinOsKernelArch appended |
| T3 | Hardware + runtime (3 fields) | `6b62678` | Get-OdinHardware + Get-OdinRuntimeUptime appended |
| T4 | Network (2 fields) | `5e55e72` | Get-OdinNetwork with 3-tier fqdn + none/unknown ip_primary |
| T5 | Virtualization (D-04 enum) | `a95558f` | Get-OdinVirtualization 7-value enum cascade |
| T6 | Cloud IMDS (D-05) | `d1a6dae` | Invoke-OdinCloudImds + 3 sub-probes |
| T7 | Aggregator | `cdf09b4` | Invoke-OdinEmitHostInfo + Rule 1 fix |
| T8 | odin.ps1 integration | `dbe24d7` | Single Invoke-OdinEmitHostInfo call site at line 103 |
| T9 | Regression test | `4f32b6d` | tools/tests/check-host-info.ps1 (99 lines, executable) |
| T10 | Changelog | `b4bc0a9` | CHANGEHISTORY.md v1.0.2-wip section extended |

## Verification Status

### Passed on dev host (macOS + pwsh 7.5.4)

- `pwsh -NoProfile -Command "& { . ./TA-ODIN/bin/modules/_common.ps1 }"` → exit 0 (syntax valid)
- PowerShell parser reports 0 errors for both `_common.ps1` and `check-host-info.ps1`
- `pwsh odin.ps1` output line 1 = `type=odin_start`, line 2 = `type=odin_host_info` with all 13 fields
- `type=odin_host_info` positioned as event #2 (deterministic)
- `modules_total=6` in `odin_complete` (no `_common.ps1` leakage as module)
- `Invoke-OdinCloudImds` returns `none|none` in ~1.1s on non-cloud macOS dev host (D-05 budget)
- No `Get-WmiObject` in `_common.ps1` (D-06 enforcement)
- All 13 fields present in emitted event (verified by visual inspection + grep)
- WR-03 SKIP guards work: Checks 4+5 show SKIP when event is missing
- `bash tools/tests/check-version-sync.sh` → PASS (HARD-01, no regressions)
- `bash tools/tests/check-host-info.sh` → ALL 6 PASS (Linux implementation untouched)
- `bash tools/tests/windows-parity-harness.sh` → ALL DIMENSIONS PASSED (HARD-01 invariant)

### Deferred to Windows VM or CI

- `powershell.exe -File TA-ODIN\bin\odin.ps1` with real Windows CIM data (all fields populated, not "unknown")
- `powershell.exe -File tools\tests\check-host-info.ps1` → 5 PASS markers exit 0
- Win32_ComputerSystem virtualization cascade producing baremetal/hyperv/vmware/kvm on real hardware
- PSCL (ConstrainedLanguage Mode) enforcement test — try/catch fallback paths
- IMDS timing verification on AWS/Azure/GCP Windows instances
- Cross-platform parity diff: Linux odin.sh + Windows odin.ps1 produce identical 13-field set (modulo platform values like os_arch=x86_64 vs amd64) — deferred to Phase 9 parity test

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] PowerShell operator precedence: `-split` applied to function call instead of result**

- **Found during:** Task 7 (Invoke-OdinEmitHostInfo aggregator)
- **Issue:** `Get-OdinOsDistro -split '\|'` in PowerShell passes `-split` and `'\|'` as arguments to the function rather than splitting the return value. Result was individual characters of "windows" being split.
- **Fix:** Changed all 5 call sites to `(Get-OdinOsDistro) -split '\|'` (parens force function evaluation first, then the binary `-split` operator applies to the string result)
- **Files modified:** `TA-ODIN/bin/modules/_common.ps1` (Invoke-OdinEmitHostInfo body)
- **Commit:** `cdf09b4`
- **Note:** This is a PowerShell-specific gotcha not present in the bash analog. Phase 7's bash used `$(detect_os_distro)` which is explicitly command substitution — no ambiguity. Plan included `Get-OdinOsDistro -split '\|'` pattern which is incorrect; applied parens fix as Rule 1 (prevents incorrect field values in emitted events).

## Decisions Made

- IMDS timeout = 1s (D-05 mirror of Phase 7 D-02) instead of ROADMAP's original 2s — cross-platform parity takes precedence
- Get-CimInstance exclusively (D-06) — no Get-WmiObject in any new Phase 8 code
- PSCL graceful degradation (D-07) — try/catch on every CIM/Net call, "unknown" sentinel on failure
- No idempotency guards needed (PowerShell dot-sourcing simpler than bash export -f pattern)
- Format-OdinValue reused from existing _common.ps1 (no private helper needed unlike bash _safe_val)
- check-host-info.ps1 uses `powershell.exe` (not `pwsh`) to test Windows 5.1 compatibility

## Known Stubs

None. All 13 fields are wired to real detection logic. On non-Windows hosts (macOS dev, Linux CI), fields fall back to "unknown" via PSCL-safe try/catch — this is correct D-07 graceful degradation, not a stub.

## Threat Flags

No new threat surface beyond what was analyzed in the plan's threat model. All IMDS probes are outbound-only with 1s timeout + -UseBasicParsing. No new network ingress, no persistent storage, no credential logging.

## Self-Check

### Created files exist:
- `tools/tests/check-host-info.ps1` — FOUND
- `.planning/phases/08-host-info-windows/08-01-SUMMARY.md` — FOUND (this file)

### Commits exist:
- `1b74c08` T1 — FOUND
- `9478668` T2 — FOUND
- `6b62678` T3 — FOUND
- `5e55e72` T4 — FOUND
- `a95558f` T5 — FOUND
- `d1a6dae` T6 — FOUND
- `cdf09b4` T7 — FOUND
- `dbe24d7` T8 — FOUND
- `4f32b6d` T9 — FOUND
- `b4bc0a9` T10 — FOUND

## Self-Check: PASSED
