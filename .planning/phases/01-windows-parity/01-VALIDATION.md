---
phase: 1
slug: windows-parity
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-11
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution of Windows Parity work.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell-based harness (bash + pwsh + grep/diff) — no pytest/jest in this repo |
| **Config file** | `tools/tests/windows-parity-harness.sh` (created Wave 0) |
| **Quick run command** | `bash tools/tests/windows-parity-harness.sh --quick` |
| **Full suite command** | `bash tools/tests/windows-parity-harness.sh` |
| **Estimated runtime** | ~10 seconds (fixture-based, no real host access) |

Rationale: TA-ODIN has zero test framework dependencies by design (no Python/pytest on endpoints). The existing `tools/tests/` directory contains ad-hoc shell tests. We extend the same pattern rather than introducing a new framework.

---

## Sampling Rate

- **After every task commit:** Run `bash tools/tests/windows-parity-harness.sh --quick` (relevant dimension only)
- **After every plan wave:** Run `bash tools/tests/windows-parity-harness.sh` (all dimensions)
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Nyquist Dimensions (from 01-RESEARCH.md §12)

| Dim | Name | How Verified | Covers SC |
|-----|------|--------------|-----------|
| 1 | Static grep gate | `grep -RIEn 'Invoke-Expression\|Add-Type\|iex \|FromBase64String\|Net\.WebClient\|DownloadString\|IEX' TA-ODIN/bin/` → zero matches | SC #3 |
| 2 | Dependency gate | `grep -RIEn '#Requires -Module\|Import-Module [^M]' TA-ODIN/bin/` → zero matches | SC #3 |
| 3 | MSI hazard gate | `grep -n 'Win32_Product' TA-ODIN/bin/modules/packages.ps1` → zero matches | SC #5 |
| 4 | Behavioral fixture test | `ODIN_TEST_FIXTURE=tests/windows-fixtures/hostA pwsh TA-ODIN/bin/odin.ps1` emits `type=odin_start`, per-module events, `type=odin_complete modules_total=6` | SC #1 |
| 5 | Parity diff | `diff` of field-name sets between `type=service` event from `pwsh odin.ps1` and `bash odin.sh` → empty diff | SC #2 |
| 6 | Fail-soft test | Induced-throw stub module → output contains both `type=odin_error` AND `type=odin_complete` | SC #4 |

---

## Per-Task Verification Map

*Populated by gsd-planner. Each task produced by the planner must map to one or more dimensions above via an `<automated>` verify block.*

| Task ID | Plan | Wave | Requirement | Secure Behavior | Dim | Automated Command | Status |
|---------|------|------|-------------|-----------------|-----|-------------------|--------|
| TBD-by-planner | — | — | — | — | — | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Wave 0 bootstraps the test harness before any Windows code exists. These tasks create the infrastructure every later task depends on:

- [ ] `tools/tests/windows-parity-harness.sh` — top-level harness script that runs all 6 dimensions and exits non-zero on any failure
- [ ] `tools/tests/windows-fixtures/hostA/` — fixture directory containing mock data files for each module (services.txt, ports.txt, packages.reg, tasks.xml, processes.txt, volumes.txt)
- [ ] `tools/tests/windows-fixtures/stubs.ps1` — cmdlet-shadow stubs (`function Get-Service`, `function Get-NetTCPConnection`, etc.) returning fixture data when `$env:ODIN_TEST_FIXTURE` is set (per D3 in CONTEXT.md)
- [ ] `tools/tests/windows-fixtures/hostA-broken/` — second fixture that induces one module throw for Dimension 6 fail-soft test

**No pytest/jest install needed.** Existing repo has `bash`, `grep`, `diff`, and developers have `pwsh` on macOS.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| LocalSystem enumeration under Windows Server 2019/2022 | WIN-11 | No Windows test hosts available in v1.0.0 (per STATE.md hard constraint) | Deferred to post-v1.0.0 pilot window; documented in `.planning/phases/01-windows-parity/PILOT-PLAN.md` (v1.1 group D) |
| AppLocker/WDAC/CLM safe invocation | WIN-10 | Requires enterprise-lockdown test host | Static inspection only in Phase 1 (no `[Console]`/`Add-Type`/`Invoke-Expression`); runtime verification deferred to pilot |
| Splunk UF `.path` wrapper actually loads on a real UF | WIN-10 | Requires Windows UF install | Static verification: `.path` file exists, syntactically correct, references `$SPLUNK_HOME`; runtime verification deferred to pilot |

These three behaviors are **provably safe by static analysis** in Phase 1 but can only be fully validated with live Windows hosts in the pilot window. This is a declared hard constraint from STATE.md, not a gap.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (harness, fixtures, stubs)
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
