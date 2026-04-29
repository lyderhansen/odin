# Phase 9: Validation + Docs + Dashboard - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-29
**Phase:** 09-validation-docs-dashboard
**Areas discussed:** Parity test approach (HOST-03), parity test execution mode, DATA-DICTIONARY field reference depth (HOST-04)

**Pre-discussion context:** Phase 9 is the final v1.0.2 phase, covering 3 distinct requirements (HOST-03 parity test, HOST-04 docs, HOST-05 dashboard). Most decisions are inherited from Phase 7+8 (D-01..D-07) or pre-locked by ROADMAP success criteria (panel count, AppInspect baseline, dashboard format). The 3 gray areas below are HOW questions specific to Phase 9 deliverables.

---

## Area A — Parity test approach (HOST-03)

**Question:** Should the cross-platform parity test be a new dedicated script or extend the existing windows-parity-harness.sh?

| Option | Description | Selected |
|---|---|---|
| A1 — New file `tools/tests/check-host-info-parity.sh` | Standalone single-purpose test mirroring check-host-info.sh / check-version-sync.sh / check-two-app-split.sh convention. Easier to run independently. Clean CI output. | ✓ |
| A2 — Extend windows-parity-harness.sh with new dimension | Keep all parity tests in one place. Adds Dimension 7. Harness already 200+ lines covering 6 dimensions; mixes per-module field parity with orchestrator-event parity concerns. | |
| A3 — Hybrid (new script called from harness) | Standalone file, but harness invokes it as part of suite. Best of both worlds; adds glue code. | |

**User's choice:** A1
**Notes:** Mirrors existing single-purpose convention. Token format `[HOST-03 PASS/FAIL/SKIP]`. Naming uses `parity` suffix for grep convenience. Harness extension was rejected because the existing harness focuses on per-module field parity (Dimensions 4-5), while HOST-03 is orchestrator-level event parity — different concern.

---

## Area B — Parity test execution mode

**Question:** Should the parity test run both orchestrators live, use pre-recorded fixtures, or both?

| Option | Description | Selected |
|---|---|---|
| B1 — Live mode (run both orchestrators) | `bash odin.sh` + `pwsh odin.ps1`, capture stdout, diff field-set. Most realistic — catches runtime regressions. macOS dev has pwsh 7.5.4; CI Linux runners need pwsh install (one-time). | ✓ |
| B2 — Fixture-based (pre-recorded golden output) | Pre-recorded `linux-host-info.txt` + `windows-host-info.txt` fixtures in tools/tests/parity-fixtures/. Test diff'er fixture vs schema. Faster, more deterministic, but doesn't catch live regressions. | |
| B3 — Hybrid (`--quick` for fixture, default for live) | Best of both. Adds 2x code complexity. | |

**User's choice:** B1
**Notes:** D-07's PSCL graceful degradation means pwsh on macOS returns "unknown" cleanly for CIM-dependent fields — field NAMES still match, which is what parity test validates. Field VALUES differ by design across platforms (Linux=real, macOS-pwsh=mostly "unknown") so test diffs only field-name set, not values. SKIP behavior when pwsh unavailable: exit 0 with `[HOST-03 SKIP] pwsh not found` — don't fail loudly, let CI / dev environments self-document.

---

## Area C — DATA-DICTIONARY field reference depth (HOST-04)

**Question:** How deep should the per-field reference be in DOCS/DATA-DICTIONARY.md?

| Option | Description | Selected |
|---|---|---|
| C1 — Per-field: description + source (Linux + Windows) + example | 3-4 lines per field × 13 fields. Mirrors existing DATA-DICTIONARY format for type=service / type=port / type=package sections. ~80 lines for field section. | ✓ |
| C2 — Extended: + Splunk SPL examples per field | Per field also include 1-2 SPL queries demonstrating use. ~150 lines. Better for adopters but more maintenance. | |
| C3 — Minimal: single field table only | One table with 13 rows (Field/Description/Example). 30 lines. Loses domain context. | |

**User's choice:** C1
**Notes:** Matches HOST-04 acceptance verbatim ("descriptive overview, complete 13-field reference (description + source + example value per field), one worked example event line in the canonical envelope format, and a note on cloud-detection timeout semantics"). SPL examples deferred to v1.0.3 docs polish phase. Estimated section size ~120 lines (overview ~20 + field reference ~80 + worked example ~10 + cloud timeout note ~10).

---

## Inherited Decisions (Phase 7+8 D-01..D-07 — NOT discussed)

| ID | Decision | Phase 9 application |
|---|---|---|
| D-01 | Linux helpers in `_common.sh` | Phase 9 documents the field shape; doesn't modify helpers |
| D-02 | Linux IMDS 1s sequential | Documented in DATA-DICTIONARY cloud timeout note |
| D-03 | Sentinel: `unknown`/`none` | Documented per-field; `cloud_provider=none\|aws\|gcp\|azure\|unknown` semantics explained |
| D-04 | Single virt field, 7-value enum | Documented; dashboard "Virtualization Breakdown" panel uses this |
| D-05 | Windows IMDS 1s sequential | Documented (mirror of D-02) |
| D-06 | Windows CIM only (no Get-WmiObject) | Documented in source column for Windows fields |
| D-07 | PSCL graceful degradation | Documented as part of Windows source description |

## Pre-locked from ROADMAP (NOT discussed)

| Item | Value |
|---|---|
| Dashboard panel count | Exactly 2 (OS Distribution + Virtualization Breakdown) |
| Dashboard format | Dashboard Studio v2 JSON (existing odin_overview.xml uses this) |
| AppInspect baseline | failure=0, error=0, warning=0 after dashboard changes |
| UAT cycle | `/gsd-verify-work 9` passes with all 5 v1.0.2 reqs DONE |

---

## Claude's Discretion

The following sub-decisions were NOT user-locked and are deferred to planning/execution:

- Whether to use `splunk.pie` or `splunk.column` for OS Distribution panel (recommend pie for distribution-style data)
- Whether to use `splunk.column` or `splunk.bar` for Virtualization Breakdown (recommend column)
- Exact SPL queries for the 2 panels (drafted in CONTEXT.md `<specifics>`, planner can refine)
- Where in DATA-DICTIONARY.md to place the new section (recommend after `## type=odin_start` to maintain orchestrator-event grouping)
- Diff algorithm in parity test (recommend `diff <(echo $linux_fields) <(echo $windows_fields)` per CONTEXT.md sketch)
- UAT structure when /gsd-verify-work 9 is invoked (managed by that skill, not Phase 9 plan)

## Deferred Ideas

Surfaced during discussion but explicitly deferred:

- **Splunk SPL examples per field in DATA-DICTIONARY** — defer to v1.0.3 docs polish phase
- **Additional dashboard panels** (Cloud Provider, Memory Distribution, etc) — defer to v1.0.3
- **Replace odin_overview.xml with new design** — defer; we add to existing
- **Add panels to odin_ops.xml as well** — defer; HOST-05 specifies odin_overview.xml only
- **Performance regression test** (IMDS budget timing assertion) — defer to v1.0.3 observability
- **Hybrid live+fixture parity test** — B3 deferred; B1 (live only) sufficient for v1.0.2

## Discussion Pattern Observation

User selected the recommended option (`A1`, `B1`, `C1`) for ALL 3 areas. Fully consistent with Phase 7's A1/B1/C1/D1 pattern AND Phase 8's W-A1/W-B1/W-C1 pattern. Strong signal of trust in conservative defaults. Across all 10 discuss-phase questions in this milestone (4 in Phase 7 + 3 in Phase 8 + 3 in Phase 9), user picked recommended option 10/10 times. Planner should default to conservative implementation choices for sub-decisions in Claude's discretion.
