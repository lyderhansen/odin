---
phase: 08-host-info-windows
verified: 2026-04-29T10:25:45Z
status: human_needed
score: 6/7 must-haves verified (truth 1 deferred to Windows VM; structural checks pass)
overrides_applied: 0
human_verification:
  - test: "Run odin.ps1 on a real Windows host with Windows-native CIM data"
    expected: "type=odin_host_info event with 13 fields populated from Win32_OperatingSystem (os_pretty != 'unknown', os_kernel != 'unknown'), cpu_cores and mem_total_mb as integers, uptime_seconds as integer, fqdn as qualified domain name, ip_primary as dotted-quad"
    why_human: "Dev environment is macOS. Get-CimInstance Win32_OperatingSystem returns nothing on macOS pwsh, so all 9 CIM-dependent fields degrade to 'unknown' via D-07. Structural correctness verified; value correctness requires a Windows host."
  - test: "Run tools/tests/check-host-info.ps1 on a Windows host using powershell.exe"
    expected: "[HOST-02 PASS] on all 5 checks (exit code 0)"
    why_human: "The test script calls powershell.exe (Windows 5.1 compatibility) which does not exist on macOS. On macOS, the test exits 1 because powershell.exe is not found and thus no output is captured. This is expected behavior — the test is designed for Windows. Structural review confirms the test logic is correct."
  - test: "Verify Win32_ComputerSystem virtualization cascade on bare metal, Hyper-V VM, VMware VM"
    expected: "Get-OdinVirtualization returns 'baremetal' on physical hardware, 'hyperv' in Hyper-V VM, 'vmware' in VMware VM"
    why_human: "Cannot verify hypervisor detection without VMs. The detection cascade logic is structurally correct (wildcard switch on Manufacturer+Model + OperatingSystemSKU container check), but production correctness needs real hardware."
deferred: []
---

# Phase 8: Host Info — Windows Verification Report

**Phase Goal:** Windows orchestrator (`TA-ODIN/bin/odin.ps1`) emits the same `type=odin_host_info` event with all 13 fields populated via Windows-native methods, achieving cross-platform parity with the Linux orchestrator.

**Verified:** 2026-04-29T10:25:45Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Cross-platform Validation Status

| Check | Platform | Method | Status |
|-------|----------|--------|--------|
| Syntax and parse | macOS (pwsh 7.5.4) | `pwsh . _common.ps1` | VERIFIED |
| Orchestrator runs | macOS (pwsh 7.5.4) | `pwsh -File odin.ps1` | VERIFIED |
| Event emitted | macOS (pwsh 7.5.4) | grep output | VERIFIED |
| 13 fields present | macOS (pwsh 7.5.4) | field existence check | VERIFIED |
| Event ordering | macOS (pwsh 7.5.4) | head -2 pipe check | VERIFIED |
| modules_total=6 | macOS (pwsh 7.5.4) | odin_complete line | VERIFIED |
| IMDS timing | macOS (pwsh 7.5.4) | timed probe | VERIFIED (0.3s) |
| D-06: no Get-WmiObject | static grep | grep count | VERIFIED (0 matches) |
| D-07: try/catch coverage | static grep | structural inspection | VERIFIED |
| D-05: TimeoutSec present | static grep | grep count | VERIFIED (4 calls) |
| check-host-info.ps1 test | macOS (pwsh 7.5.4) | run test | FAILS (powershell.exe not found — expected on macOS) |
| CIM field values | Windows VM | NOT RUN — needs Windows | DEFERRED TO HUMAN |
| Virtualization cascade | Windows VM | NOT RUN — needs Windows | DEFERRED TO HUMAN |

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | `powershell.exe -File odin.ps1` produces exactly ONE `type=odin_host_info` line containing all 13 named fields via Windows-native methods (D-01..D-07 honored) | ? UNCERTAIN | Verified on macOS pwsh: exactly 1 event, 13 fields present. CIM fields fall back to "unknown" via D-07 (expected on macOS). Real-Windows value correctness deferred to human. |
| 2 | On a non-cloud host, IMDS probes complete within 3s total worst case (D-05: TimeoutSec 1 × 3 probes) | VERIFIED | timed run on macOS: `Invoke-OdinCloudImds` returns `none|none` in 0.3s. All 4 `Invoke-RestMethod` calls use `-TimeoutSec $script:ODIN_IMDS_TIMEOUT` (lines 409, 416, 432, 451). $script:ODIN_IMDS_TIMEOUT defaults to 1 (line 48). ROADMAP SC2 said "2s timeout" — relaxed to 1s per D-05 decision, documented in CHANGEHISTORY.md "Decision change record (Windows IMDS timeout)". |
| 3 | Event ordering deterministic: line 1=odin_start, line 2=odin_host_info, modules after | VERIFIED | `pwsh -File odin.ps1 \| head -2`: line 1 contains `type=odin_start`, line 2 contains `type=odin_host_info`. `Invoke-OdinEmitHostInfo` is at `odin.ps1:103`, between `Invoke-OdinEmit "type=odin_start"` (line 95) and `$modules_total = 0` (line 108). |
| 4 | All new Phase 8 helpers use Get-CimInstance exclusively (D-06): `grep -c Get-WmiObject _common.ps1` returns 0 | VERIFIED | `grep -c 'Get-WmiObject' _common.ps1` = 0. All CIM calls use `Get-CimInstance`. |
| 5 | PSCL graceful degradation honored (D-07): every detect_* call wrapped in try/catch with "unknown" fallback | VERIFIED | Static inspection confirms: Get-OdinOsDistro (2 try/catch blocks), Get-OdinOsKernelArch (2 try/catch), Get-OdinHardware (2 try/catch), Get-OdinRuntimeUptime (1 try/catch), Get-OdinNetwork (3 try/catch), Get-OdinVirtualization (outer + inner try/catch). All return "unknown" on exception. Empirical confirmation: macOS pwsh cannot call Win32_OperatingSystem — all CIM fields return "unknown" without crash. |
| 6 | Virtualization is single field with D-04 7-value enum: `baremetal\|kvm\|vmware\|hyperv\|xen\|container\|unknown` | VERIFIED | Get-OdinVirtualization returns exactly one of the 7 values. check-host-info.ps1 validates against `@('baremetal', 'kvm', 'vmware', 'hyperv', 'xen', 'container', 'unknown')`. On macOS: CIM unavailable → returns "unknown" (valid enum value). |
| 7 | Cross-platform parity preserved: windows-parity-harness.sh continues to PASS; AppInspect TA-ODIN baseline unchanged | VERIFIED | `bash tools/tests/windows-parity-harness.sh` → ALL DIMENSIONS PASSED. `grep -n 'Invoke-Expression\|Add-Type\|IEX' _common.ps1` → 0 matches (no AppInspect-triggering patterns added). |

**Score:** 6/7 truths verified (truth 1 is UNCERTAIN pending Windows-only human validation, not a structural failure)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `TA-ODIN/bin/modules/_common.ps1` | 8 PS mirror helpers + Invoke-OdinEmitHostInfo + ODIN_IMDS_TIMEOUT, min 350 lines | VERIFIED | 536 lines. `grep -c '^function Get-Odin\|^function Invoke-Odin' _common.ps1` = 8. Contains "Invoke-OdinEmitHostInfo" (line 488). ODIN_IMDS_TIMEOUT default set at line 47-48. |
| `TA-ODIN/bin/odin.ps1` | Contains "Invoke-OdinEmitHostInfo" call site | VERIFIED | `Invoke-OdinEmitHostInfo` at line 103, between odin_start (line 95) and modules loop (line 108). |
| `tools/tests/check-host-info.ps1` | HOST-02 regression test, min 70 lines, contains "type=odin_host_info" | VERIFIED | 99 lines. Contains "type=odin_host_info" (multiple occurrences). Uses `[HOST-02 PASS/FAIL/SKIP]` token convention. WR-03 SKIP guards present (2 `if (-not $hostInfoLine)` guards at lines 67 and 82). |
| `DOCS/CHANGEHISTORY.md` | v1.0.2-wip section extended with HOST-02, D-05..D-07, ROADMAP SC2 relaxation note | VERIFIED | "### Windows implementation (Phase 8 / HOST-02)" section exists. All 8 helper names documented (lines 61-68). D-05, D-06, D-07 present (lines 74-76). "Decision change record (Windows IMDS timeout)" present (line 79). |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `TA-ODIN/bin/odin.ps1` | `_common.ps1:Invoke-OdinEmitHostInfo` | function call at line 103 | VERIFIED | `grep -n 'Invoke-OdinEmitHostInfo' odin.ps1` = line 103. _common.ps1 already dot-sourced at line 65. |
| `_common.ps1:Invoke-OdinEmitHostInfo` | `_common.ps1:Invoke-OdinEmit` | `Invoke-OdinEmit $line` (line 535) where $line starts "type=odin_host_info..." | VERIFIED | `$line = "type=odin_host_info " + ...` at line 520. `Invoke-OdinEmit $line` at line 535. |
| `tools/tests/check-host-info.ps1` | `powershell.exe odin.ps1` stdout | `$out -split "n" \| Where-Object { $_ -match 'type=odin_host_info' }` | PARTIAL | Test logic is structurally correct. Fails on macOS because `powershell.exe` is Windows-only (line 24). Intentional design decision (SUMMARY: "check-host-info.ps1 uses powershell.exe (not pwsh) to test Windows 5.1 compatibility"). Must be run on Windows. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `_common.ps1:Invoke-OdinEmitHostInfo` | `$os_distro`, `$os_version`, `$os_pretty` | `Get-OdinOsDistro` → `Get-CimInstance Win32_OperatingSystem` | On Windows: yes. On macOS: "unknown" via D-07 graceful fallback | VERIFIED (on Windows by design) |
| `_common.ps1:Invoke-OdinEmitHostInfo` | `$cpu_cores`, `$mem_total_mb` | `Get-OdinHardware` → `Get-CimInstance Win32_Processor` + `Win32_OperatingSystem.TotalVisibleMemorySize` | On Windows: yes. On macOS: "unknown" via D-07 | VERIFIED (on Windows by design) |
| `_common.ps1:Invoke-OdinEmitHostInfo` | `$cloud_provider`, `$cloud_region` | `Invoke-OdinCloudImds` → sequential AWS/GCP/Azure IMDS via `Invoke-RestMethod` | On non-cloud host: returns "none|none" in 0.3s (confirmed on macOS) | VERIFIED |

All 13 fields are wired to detection logic. The "unknown" values on macOS are correct D-07 graceful degradation, not stubs — they are populated from real CIM/Net calls on Windows hosts.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| _common.ps1 syntax loads cleanly | `pwsh -NoProfile -Command ". _common.ps1"` | Exit 0, no errors | PASS |
| Orchestrator emits exactly 1 odin_host_info event | `pwsh -File odin.ps1 \| grep -c 'type=odin_host_info'` | 1 | PASS |
| Event is positioned as #2 | `pwsh -File odin.ps1 \| grep '^timestamp=' \| head -2` | line 1: odin_start, line 2: odin_host_info | PASS |
| modules_total=6 (no _common.ps1 leakage) | `pwsh -File odin.ps1 \| grep type=odin_complete \| grep -o 'modules_total=[0-9]*'` | modules_total=6 | PASS |
| IMDS probes complete fast on non-cloud host | `time pwsh -Command "Invoke-OdinCloudImds"` | 0.3s, returns none\|none | PASS |
| check-host-info.ps1 on Windows | `powershell.exe -File check-host-info.ps1` | Not runnable on macOS (powershell.exe not present) | SKIP — Windows required |
| Linux regression: HOST-01 not regressed | `bash check-host-info.sh` | All 6 checks PASS | PASS |
| Windows parity harness | `bash windows-parity-harness.sh` | ALL DIMENSIONS PASSED | PASS |
| Version sync HARD-01 | `bash check-version-sync.sh` | PASS | PASS |
| Two-app split HARD-07 | `bash check-two-app-split.sh` | PASS | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| HOST-02 | 08-01 | Windows orchestrator emits one `type=odin_host_info` event with 13 fields | UNCERTAIN (human needed) | Structural checks pass; CIM value correctness on real Windows deferred to human |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `tools/tests/check-host-info.ps1` | 24 | `powershell.exe` not available on macOS, causing test to exit 1 on dev host | Info | Expected — intentional Windows 5.1 compatibility design. Not a code bug. WR-03 guards prevent false FAIL on missing event. |

No stub patterns found. No `return null`/`return {}` stubs. No `TODO`/`FIXME`/`PLACEHOLDER` comments in implementation files. No hardcoded empty data. All 13 fields wired to detection code paths.

No `Get-WmiObject` in new Phase 8 code (D-06 verified). No `Invoke-Expression`, `Add-Type`, or other AppInspect-triggering patterns.

### Human Verification Required

#### 1. Windows CIM field population

**Test:** On a Windows Server 2019/2022 or Windows 10/11 host, run:
```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File TA-ODIN\bin\odin.ps1 | Select-String 'type=odin_host_info'
```
**Expected:** One line containing all 13 fields with non-"unknown" values for: `os_pretty` (e.g., "Microsoft Windows Server 2022 Datacenter"), `os_kernel` (e.g., "20348"), `cpu_cores` (integer), `mem_total_mb` (integer), `uptime_seconds` (integer), `fqdn` (qualified hostname), `ip_primary` (dotted-quad). `os_distro` must equal "windows". `os_arch` must be "amd64" or "arm64". Cloud fields: `cloud_provider=none cloud_region=none` on on-prem host.
**Why human:** Dev environment is macOS. All CIM-dependent fields fall back to "unknown" via D-07 graceful degradation on macOS pwsh. Requires a Windows host to verify real field population.

#### 2. check-host-info.ps1 regression test on Windows

**Test:** On a Windows host with powershell.exe 5.1+, run:
```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tools\tests\check-host-info.ps1
```
**Expected:** Exit code 0, all 5 check lines show `[HOST-02 PASS]`, no `[HOST-02 FAIL]` lines.
**Why human:** The test calls `powershell.exe` (Windows 5.1 compatibility check) which does not exist on macOS. Structural review confirms test logic is correct (5 checks with WR-03 SKIP guards for checks 4-5 when event is missing).

#### 3. Virtualization detection cascade on real Windows hardware/VMs

**Test:** Run `powershell.exe -Command ". .\TA-ODIN\bin\modules\_common.ps1; Initialize-OdinContext; Get-OdinVirtualization"` on:
- Physical Windows machine → expected: "baremetal"
- Hyper-V guest → expected: "hyperv"
- VMware guest → expected: "vmware"
**Why human:** Cannot verify `Win32_ComputerSystem.Manufacturer/Model` cascade without real hardware. The detection logic is structurally correct (switch -Wildcard on signature string) but requires real hardware to validate the wildcard patterns match real Windows CIM values.

## Gaps Summary

No blocking gaps found. Phase 8 is structurally complete:
- All 4 required artifacts exist and pass line-count and content checks
- All 8 PS mirror helpers are present in _common.ps1
- Orchestrator integration is wired and confirmed working via behavioral spot-checks on macOS pwsh
- All Linux regression tests pass (no regressions introduced)
- Windows parity harness passes (HARD-01 invariant preserved)
- D-05 (IMDS timeout), D-06 (no Get-WmiObject), D-07 (PSCL graceful degradation) all verified

The only outstanding items are Windows-specific runtime validation that requires a Windows host:
- CIM field value correctness (Win32_OperatingSystem, Win32_Processor)
- check-host-info.ps1 test execution (requires powershell.exe)
- Virtualization cascade on real hardware/VMs

The ROADMAP SC2 deviation (1s timeout instead of 2s) is properly documented in CHANGEHISTORY.md under "Decision change record (Windows IMDS timeout)" and does not constitute a gap — it is a deliberate cross-platform parity decision that makes Windows behavior mirror Phase 7's Linux implementation.

The commit count (10 commits for 10 tasks) matches SUMMARY.md. The verification approach expected 11 commits but SUMMARY documented 10 tasks — this is a minor discrepancy in the verification approach, not a gap.

---

_Verified: 2026-04-29T10:25:45Z_
_Verifier: Claude (gsd-verifier)_
