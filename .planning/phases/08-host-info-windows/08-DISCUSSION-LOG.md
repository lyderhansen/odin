# Phase 8: Host Info — Windows - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-29
**Phase:** 08-host-info-windows
**Areas discussed:** IMDS timeout for Windows, CIM vs WMI standard, PSCL compatibility level

**Pre-discussion context:** Phase 8 inherits 4 locked decisions from Phase 7 (D-01..D-04) via the cross-platform parity contract. The seed file (`.planning/seeds/v1.0.2-host-metadata-enrichment.md`) already documents Windows detection methods for all 13 fields. Phase 7's `_common.sh` pre-commits the 8 PowerShell mirror function names. The 3 Windows-specific gray areas below are HOW questions that the inherited decisions did not resolve.

---

## Area W-A — IMDS Timeout for Windows (Phase 7 D-02 mirror)

**Question:** ROADMAP success criterion 2 says "Invoke-RestMethod with explicit 2s timeout", but Phase 7 D-02 locked 1s curl timeout. What's the right Windows budget?

| Option | Description | Selected |
|---|---|---|
| W-A1 — 1s for parity (mirror Phase 7 D-02) | `Invoke-RestMethod -TimeoutSec 1` per probe. Worst case 3s (or 4s for AWS IMDSv2 same as Phase 7). Cross-platform parity preserved. Requires ROADMAP SC2 relaxation note (2s → 1s). | ✓ |
| W-A2 — 2s per ROADMAP draft | More margin for Windows HTTP stack overhead. Worst case 6-8s. Breaks parity (same behavior, different latency). | |
| W-A3 — Auto-detect: 1s default + ODIN_IMDS_TIMEOUT env override | Mirror Phase 7's env-var knob. Most flexible but adds runtime variability. | |

**User's choice:** W-A1
**Notes:** Same precedence rule as Phase 7's 2s→3s relaxation: discuss-phase decisions override ROADMAP for HOW questions. ROADMAP SC2 will be relaxed in Task 10's CHANGEHISTORY entry (mirroring Phase 7's Decision change record pattern). PowerShell `Invoke-RestMethod -TimeoutSec` is "total request time" not "connect-only" — slightly stricter than curl semantics but functionally equivalent for non-cloud hosts (link-local routing fails immediately on connect).

---

## Area W-B — CIM vs WMI Standard for New Helpers

**Question:** Should new Phase 8 helpers use `Get-CimInstance` (modern), `Get-WmiObject` (legacy), or mixed?

| Option | Description | Selected |
|---|---|---|
| W-B1 — Get-CimInstance only (modern + PSCL-friendly) | All new helpers use Get-CimInstance. Existing services.ps1 (3× Get-WmiObject) NOT touched per HARD-01 invariant. | ✓ |
| W-B2 — Match local file convention | Existing _common.ps1 has neither — Phase 8 sets the new standard. | |
| W-B3 — Mixed (CIM with WMI fallback) | Try CIM, catch error, fallback to WMI. 2x code volume, more robust. | |

**User's choice:** W-B1
**Notes:** Get-WmiObject deprecated as of PowerShell 6, removed in PSCore 6+. Get-CimInstance uses WS-MAN protocol (faster, remote-friendly without DCOM), produces consistent objects across PS versions, more PSCL-compatible. Existing services.ps1 + processes.ps1 WMI usage is v1.0.0 code — out of scope for Phase 8 (deferred to v1.1.0 cleanup phase).

---

## Area W-C — PowerShell ConstrainedLanguage Mode (PSCL) Compatibility

**Question:** How should Phase 8 helpers behave when running under PSCL (DeviceGuard / WDAC code-integrity policies)?

| Option | Description | Selected |
|---|---|---|
| W-C1 — Best-effort with graceful degradation | Avoid Add-Type / Invoke-Expression / .NET reflection / type accelerators that PSCL blocks. When blocked: fall back to `unknown` per D-03. Don't crash. | ✓ |
| W-C2 — Hard requirement with warning event | Detect PSCL via $ExecutionContext.SessionState.LanguageMode and emit `type=odin_warning reason=PSCL_partial`. Clear monitoring signal. | |
| W-C3 — Skip PSCL support in v1.0.2 | Require FullLanguage Mode. Emit `type=odin_warning module=host_info reason=PSCL_unsupported` and skip event. Cleanest separation. | |

**User's choice:** W-C1
**Notes:** D-03's all-strings sentinel is exactly the right tool for graceful degradation. High-security Windows deployments enforce PSCL via DeviceGuard / WDAC — TA-ODIN must run there without crashing. The "PSCL_partial" warning event (W-C2) and "skip event entirely" (W-C3) are deferred to v1.0.3 if production monitoring shows widespread PSCL deployment. v1.0.2 prioritizes "works everywhere, partial data better than no data" over explicit signaling.

---

## Inherited Decisions (Phase 7 D-01..D-04 — NOT discussed)

These flow into Phase 8 unchanged via cross-platform parity. Listed here for audit clarity.

| ID | Decision | Phase 8 application |
|---|---|---|
| D-01 | Helper placement: extend `_common.sh` | Mirror: extend `_common.ps1` (currently 178 lines, +~250 expected) |
| D-02 | IMDS sequential AWS→GCP→Azure | Same probe order, timing per D-05 (1s mirror) |
| D-03 | Sentinel: `unknown` (failure) / `none` (semantic null) | Same string sentinels, same numeric-as-string convention |
| D-04 | Single virtualization field, 7-value enum | Same enum, Win32_ComputerSystem cascade for detection |

---

## Claude's Discretion

The following sub-decisions were NOT user-locked and are deferred to planning/execution:

- Internal helper function naming convention (already locked: `Get-Odin*` and `Invoke-Odin*` patterns from Phase 7's pre-commitment)
- Order within `Get-OdinVirtualization` cascade (Microsoft → VMware → QEMU → Xen → Amazon → Google → Container → baremetal — typical descending probability)
- IMDS endpoint URL constants (hardcoded inline vs script-scoped variables — likely script-scoped for testability)
- Test fixture format for IMDS mocking (PowerShell parameter injection vs HTTP response stub)
- Whether `Invoke-OdinEmitHostInfo` builds the event line via `-f` formatting OR string concatenation (style preference)
- Exact Win32 class field extraction (e.g., `.Caption` vs `.Caption.Trim()` for whitespace)

## Deferred Ideas

Surfaced during discussion but explicitly deferred to other phases/milestones:

- **Per-container Windows runtime detection** (Hyper-V Container vs Process Container vs WSL2) — defer to v1.1.0
- **PSCL hard-fail with explicit warning event** (`type=odin_warning reason=PSCL_unsupported`) — defer to v1.0.3 if monitoring shows widespread PSCL deployment
- **Win32_Processor.SocketDesignation for socket-aware cpu_cores** — defer (v1.0.2 sums NumberOfCores naively)
- **Cloud asset metadata** (AWS Instance Tags, GCP Labels, Azure Tags) — defer to v1.1.0 Phase 4 optional
- **Consolidating services.ps1 + processes.ps1 from Get-WmiObject to Get-CimInstance** — defer to v1.1.0 cleanup phase

## Discussion Pattern Observation

User selected the recommended option (`W-A1`, `W-B1`, `W-C1`) for ALL 3 Windows-specific areas. This is fully consistent with Phase 7's pattern (user selected A1/B1/C1/D1 — all 4 recommended defaults). Strong signal of trust in conservative defaults inherited from Phase 7's parity contract. Planner should default to conservative implementation choices for sub-decisions in Claude's discretion.
