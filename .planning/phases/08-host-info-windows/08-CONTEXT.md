# Phase 8: Host Info — Windows - Context

**Gathered:** 2026-04-29
**Status:** Ready for planning
**Source:** /gsd-discuss-phase 8 (3 Windows-specific gray areas)

<domain>
## Phase Boundary

Mirror Phase 7's Linux host_info implementation onto Windows. The orchestrator `TA-ODIN/bin/odin.ps1` MUST emit exactly ONE `type=odin_host_info` event per scan, positioned as event #2 between `type=odin_start` and the first module event, populated with all 13 host metadata fields via Windows-native methods.

Field shape, event positioning, and sentinel discipline are LOCKED by Phase 7's parity contract — Phase 8 is a mechanical port. The 8 helper-function names are pre-committed in Phase 7's `_common.sh` comments (e.g., `detect_virt` → `Get-OdinVirtualization`).

**Scope:** TA-ODIN forwarder app only (no ODIN_app_for_splunk changes — those happen in Phase 9 dashboards). Cross-platform parity invariant (HARD-01) requires that the 13-field event shape and field semantics match Linux byte-for-byte (modulo platform-specific values like `os_arch=amd64` vs `x86_64`).
</domain>

<decisions>
## Implementation Decisions

### Inherited from Phase 7 (LOCKED — do not re-litigate)

These flow into Phase 8 unchanged via the cross-platform parity contract. Phase 8 implements them in PowerShell instead of bash; the field semantics are identical.

- **D-01 (mirror):** Helper placement — extend `TA-ODIN/bin/modules/_common.ps1` (currently 178 lines with 5 functions). NOT a new file, NOT a new directory. Mirrors PROD-07 (d) shared-lib pattern.
- **D-02 (mirror):** IMDS strategy — sequential AWS→GCP→Azure probe order. See **D-05** below for Windows-specific timeout decision.
- **D-03 (mirror):** Field error handling — all-strings sentinel. `"unknown"` for system failure (e.g., CIM query failed), `"none"` for semantic null (e.g., no cloud detected). Numeric fields ALSO emit as strings on failure (`cpu_cores=unknown`, never `cpu_cores=-1`).
- **D-04 (mirror):** Virtualization granularity — single field with 7-value enum: `baremetal|kvm|vmware|hyperv|xen|container|unknown`. Container-runtime detail deferred to v1.1.0.

### Pre-locked from seed (NOT discussed)

- **13 fields exact:** `os_distro`, `os_version`, `os_pretty`, `os_kernel`, `os_arch`, `cpu_cores`, `mem_total_mb`, `uptime_seconds`, `fqdn`, `ip_primary`, `virtualization`, `cloud_provider`, `cloud_region`
- **Event name:** `type=odin_host_info`
- **Event positioning:** between `type=odin_start` (line 95 in odin.ps1) and the first module event (mirrors Linux odin.sh:99→102 contract)
- **Per-field detection methods:** see seed table at `.planning/seeds/v1.0.2-host-metadata-enrichment.md`
- **8 helper-function names** (pre-committed in Phase 7's `_common.sh` comments — must use exactly these names for parity grep convenience):
  - `Get-OdinOsDistro` — returns pipe-separated `distro|version|pretty`
  - `Get-OdinOsKernelArch` — returns pipe-separated `kernel|arch`
  - `Get-OdinHardware` — returns pipe-separated `cpu_cores|mem_total_mb`
  - `Get-OdinRuntimeUptime` — returns single integer string OR `unknown`
  - `Get-OdinNetwork` — returns pipe-separated `fqdn|ip_primary`
  - `Get-OdinVirtualization` — returns single string from D-04 7-value enum
  - `Invoke-OdinCloudImds` — returns pipe-separated `provider|region`
  - `Invoke-OdinEmitHostInfo` — calls all above + emits the unified event via existing `Invoke-OdinEmit`

### Windows-specific decisions (this discussion)

#### D-05 — IMDS timeout for Windows (Phase 7 D-02 mirror)

**Decision:** Use `Invoke-RestMethod -TimeoutSec 1` for all three cloud probes (AWS IMDSv2 + GCP + Azure). Total worst case = 3s (or 4s for AWS where IMDSv2 makes 2 sequential calls — same edge case as Phase 7 WR-01).

**Rationale:**
- Cross-platform parity with Phase 7 D-02 (1s curl timeout × 3 sequential probes).
- ROADMAP success criterion 2 originally said "2s timeout" — this is being relaxed to 1s for parity. Same precedence rule as Phase 7's 2s→3s relaxation: discuss-phase decisions override ROADMAP for HOW questions.
- Windows must mirror `ODIN_IMDS_TIMEOUT` env-var convention. PowerShell will read `$env:ODIN_IMDS_TIMEOUT` (default 1) at sourcing time, same as bash `${ODIN_IMDS_TIMEOUT:-1}`.

**Implementation note:** `Invoke-RestMethod` accepts `-TimeoutSec` (server response timeout). Combined with no separate connect-timeout knob in PowerShell's HTTP stack, the actual budget is "total request time" not "connect-only" — slightly stricter than curl's `--connect-timeout` semantics but functionally equivalent for non-cloud hosts (link-local routing fails immediately on connect).

#### D-06 — Use `Get-CimInstance` exclusively for new Phase 8 helpers

**Decision:** All new Phase 8 helpers use `Get-CimInstance` (modern, recommended by Microsoft, PSCL-friendlier). NEVER use `Get-WmiObject` in new code.

**Rationale:**
- `Get-WmiObject` is deprecated as of PowerShell 6 and removed from PowerShell Core 7+.
- `Get-CimInstance` is faster (uses WS-MAN protocol, can run remote without DCOM), more PSCL-compatible, and produces consistent objects across PowerShell versions.
- Existing `services.ps1` (3× Get-WmiObject) is v1.0.0 code — NOT touched in Phase 8 per HARD-01 invariant ("don't break what works"). Phase 9 or v1.1.0 may consolidate.

**Specific class mappings:**
- `Win32_OperatingSystem` → os_distro/os_version/os_pretty/os_kernel via `.Caption`/`.Version`/`.BuildNumber`/`.LastBootUpTime`
- `Win32_Processor` → cpu_cores via `.NumberOfCores` (sum across processors)
- `Win32_OperatingSystem.TotalVisibleMemorySize` (KB) / 1024 → mem_total_mb
- `Win32_ComputerSystem.Manufacturer` + `Win32_ComputerSystem.Model` → virtualization detection chain
- `Get-NetRoute -DestinationPrefix '0.0.0.0/0'` + `Get-NetIPAddress` → ip_primary (NOT a CIM call — uses NetTCPIP module, also PSCL-friendly)

#### D-07 — ConstrainedLanguage Mode (PSCL): best-effort with graceful degradation

**Decision:** Phase 8 helpers SHOULD be PSCL-compatible (avoid `Add-Type`, `Invoke-Expression`, .NET reflection, type accelerators that PSCL blocks). When PSCL blocks a specific operation, the affected field falls back to `"unknown"` (D-03 sentinel discipline) — the orchestrator does NOT crash, the event still emits with partial fields.

**Rationale:**
- High-security Windows deployments enforce PSCL via DeviceGuard / WDAC code-integrity policies. TA-ODIN must run in those environments without crashing.
- Hard-failing on PSCL would create a "TA-ODIN doesn't work on secure hosts" perception — worse for adoption.
- D-03's all-strings sentinel pattern is exactly the right tool for this: if `Get-CimInstance Win32_OperatingSystem` is blocked by PSCL, `os_distro=unknown` is honest and grep-stable.
- A separate `type=odin_warning module=host_info reason=PSCL_partial` MAY be emitted in v1.0.3 if monitoring shows widespread PSCL deployment. Not in v1.0.2 scope.

**Implementation note:** Detect PSCL via `$ExecutionContext.SessionState.LanguageMode` — check returns `"FullLanguage"`, `"ConstrainedLanguage"`, `"RestrictedLanguage"`, or `"NoLanguage"`. Phase 8 helpers can wrap risky operations in `try/catch` and emit `unknown` on failure regardless of cause (PSCL, missing CIM class, RPC failure, etc.) — the cause doesn't matter to Splunk dashboards, only the field value.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoritative source
- `.planning/phases/08-host-info-windows/08-CONTEXT.md` — this file (3 Windows-specific decisions D-05..D-07)
- `.planning/phases/07-host-info-linux/07-CONTEXT.md` — Phase 7 decisions D-01..D-04 (all mirror to Phase 8)
- `.planning/phases/07-host-info-linux/07-01-SUMMARY.md` — what Phase 7 actually built (the implementation Phase 8 mirrors)

### Detection methods + field shape
- `.planning/seeds/v1.0.2-host-metadata-enrichment.md` — 13-field detection methods table (Linux + Windows side-by-side)
- `.planning/REQUIREMENTS.md` § "v1.0.2 Requirements" — HOST-02 acceptance criteria
- `.planning/ROADMAP.md` § "Phase 8: Host Info — Windows" — 4 success criteria (note: SC2's "2s timeout" is relaxed to 1s per D-05)

### Phase 8 mirror commitments (pre-committed names)
- `TA-ODIN/bin/modules/_common.sh` lines containing `# Phase 8 mirror:` — 8 helper-function names locked
- `TA-ODIN/bin/modules/_common.ps1` — file to extend (current 178 lines, 5 existing functions: Get-OdinTimestamp, Format-OdinValue, Invoke-OdinEmit, Initialize-OdinContext, Initialize-OdinModuleState)
- `TA-ODIN/bin/odin.ps1` — orchestrator (find the equivalent of Linux odin.sh line 99 — likely line 95 per Phase 7 PATTERNS.md mirror reference)

### Cross-platform parity references
- `TA-ODIN/bin/modules/_common.sh` (post-Phase-7 state, 343 lines) — the implementation Phase 8 mirrors function-by-function
- `TA-ODIN/bin/odin.sh` (post-Phase-7 state, 178 lines) — orchestrator integration pattern Phase 8 mirrors (source `_common.ps1` once, call `Invoke-OdinEmitHostInfo` between odin_start emit and module loop)
- `tools/tests/check-host-info.sh` — Linux regression test; Phase 8 should produce a sibling `tools/tests/check-host-info.ps1` OR extend the existing test to cover both platforms
- `tools/tests/windows-parity-harness.sh` — existing parity test (HARD-01) — must continue to pass after Phase 8

</canonical_refs>

<specifics>
## Specific Ideas

### Detection method specifics (from seed table)

| Field | Windows command |
|---|---|
| `os_distro` | Hardcoded `"windows"` (no parsing needed — `Win32_OperatingSystem.Caption` always starts with "Microsoft Windows") |
| `os_version` | `[System.Environment]::OSVersion.Version` → "10.0.26100" format. PSCL note: type accelerator `[System.Environment]` may be blocked → fallback to `(Get-CimInstance Win32_OperatingSystem).Version` |
| `os_pretty` | `(Get-CimInstance Win32_OperatingSystem).Caption` → e.g., "Microsoft Windows 11 Pro" or "Microsoft Windows Server 2022 Datacenter" |
| `os_kernel` | `(Get-CimInstance Win32_OperatingSystem).BuildNumber` → e.g., "26100.4349" — concat with patch level if needed |
| `os_arch` | `$env:PROCESSOR_ARCHITECTURE` → "AMD64" / "ARM64" / "x86" — lowercase to match Linux `os_arch` convention |
| `cpu_cores` | `(Get-CimInstance Win32_Processor).NumberOfCores` — SUM if multiple processors, else single value |
| `mem_total_mb` | `[int]((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1024)` — TVMS is in KB, divide to MB |
| `uptime_seconds` | `[int](((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalSeconds)` |
| `fqdn` | `[System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName` (PSCL: fallback to `$env:COMPUTERNAME` only) |
| `ip_primary` | `(Get-NetRoute -DestinationPrefix '0.0.0.0/0' \| Get-NetIPAddress -AddressFamily IPv4).IPAddress` (mirror Linux `ip route get 1.1.1.1 \| awk '{print $7}'`) |
| `virtualization` | `(Get-CimInstance Win32_ComputerSystem).Manufacturer` + `.Model` cascade — see D-04 enum mapping below |
| `cloud_provider` | Sequential `Invoke-RestMethod` per D-05 (1s timeout) — AWS IMDSv2 token+region, GCP metadata.google.internal, Azure 169.254.169.254 |
| `cloud_region` | Same as cloud_provider — single probe returns both |

### Virtualization detection cascade (D-04 enum mapping)

```powershell
$cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
switch -Wildcard ("$($cs.Manufacturer) $($cs.Model)") {
    "*Microsoft*Virtual*"           { return "hyperv" }
    "*VMware*"                      { return "vmware" }
    "*QEMU*"                        { return "kvm" }
    "*Xen*"                         { return "xen" }
    "*Amazon EC2*"                  { return "kvm" }   # EC2 nitro instances
    "*Google*Compute Engine*"       { return "kvm" }   # GCE
    default {
        # Container detection (Windows containers): check for Container OS edition
        if ((Get-CimInstance Win32_OperatingSystem).OperatingSystemSKU -in @(0x00000131, 0x00000132)) {
            return "container"
        }
        return "baremetal"
    }
}
```

Wraps in `try/catch` per D-07 — returns `"unknown"` if Get-CimInstance fails.

### Insertion point in odin.ps1

Per Phase 7 PATTERNS.md mirror reference: between line 95 (`type=odin_start` emit) and line 100 (counter init), insert `Invoke-OdinEmitHostInfo`. Must be AFTER `_common.ps1` is sourced (which already happens since odin.ps1 sources it for Initialize-OdinContext).

### Test strategy

Two options for the regression test, planner should pick:
1. **Mirror Linux:** Create `tools/tests/check-host-info.ps1` with 5 PASS markers exactly mirroring `check-host-info.sh` (event count, 13 fields, positioning, virt enum, cloud sentinel). Cross-platform CI runs both.
2. **Extend parity-harness:** Add a "host_info event" check to existing `tools/tests/windows-parity-harness.sh:122-140` block. Less files, but couples host_info testing to parity-harness lifecycle.

Recommended: option 1 (mirror Linux) — symmetric, easier to maintain, CI runs both with same exit-code semantics.

</specifics>

<deferred>
## Deferred Ideas

These were surfaced during analysis but explicitly deferred:

- **Per-container Windows runtime detection** (Hyper-V Container vs Process Container vs WSL2) — defer to v1.1.0 container observability. Phase 8 collapses all to `virtualization=container`.
- **Windows ARM64 IMDS-via-IMDSv2 differences** — empirical: AWS IMDSv2 works identically on ARM64. No special handling needed in Phase 8.
- **PSCL hard-fail with explicit warning event** (`type=odin_warning reason=PSCL_unsupported`) — deferred to v1.0.3 if monitoring shows widespread PSCL deployment. v1.0.2 uses graceful degradation per D-07.
- **Win32_Processor.SocketDesignation for socket-aware cpu_cores** — defer; v1.0.2 sums NumberOfCores naively.
- **Cloud asset metadata** (AWS Instance Tags, GCP Labels, Azure Tags) — deferred to v1.1.0 Phase 4 optional, same as Linux.
- **Consolidating services.ps1 + processes.ps1 to Get-CimInstance** (cleanup of v1.0.0 WMI usage) — defer to v1.1.0 cleanup phase. Phase 8 adds NEW code in CIM only; doesn't refactor existing WMI.

---

*Phase: 08-host-info-windows*
*Context gathered: 2026-04-29 via /gsd-discuss-phase 8*
*3 Windows-specific decisions captured (D-05..D-07); 4 inherited from Phase 7 (D-01..D-04 mirror); 8 helper names pre-committed*
</deferred>
