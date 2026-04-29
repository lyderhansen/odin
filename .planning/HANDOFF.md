# Session Handoff — v1.0.2-rc1 SHIPPED (2026-04-29)

## TL;DR

**v1.0.2-rc1 is RELEASED** — GitHub prerelease live at https://github.com/lyderhansen/odin/releases/tag/v1.0.2-rc1 with both tarballs attached (TA-ODIN-1.0.2.tgz + ODIN_app_for_splunk-1.0.2.tgz). UAT signed off (5/5 HOST-* DONE), version bumped 1.0.1→1.0.2 across all 6 sites, tag annotated and pushed.

**3 strategic options for next session** (in order of "lowest commitment first"):
1. **Validate rc1 in production-like Splunk** — install the tarballs, confirm dashboards render with real data, then tag full `v1.0.2` (no -rc suffix)
2. **Open `/gsd-new-milestone` for v1.1.0 — Container Observability** — trigger condition (v1.0.2 shipped) satisfied; seed at `.planning/seeds/v1.1.0-container-observability.md` ready as input
3. **Address tooling debt** — stray `tools.zip` (67K, untracked from manual Windows copy), check if any other ignorable artifacts to add to `.gitignore`

**Recommended next step:** Option 1 first (closes v1.0.2 cleanly), then Option 2 (start v1.1.0 with proper foundation).

---

## What changed this session

### UAT cycle execution (5 tests, 0 issues)

| # | Requirement | Test | Result |
|---|---|---|---|
| 1 | HOST-01 | Linux orchestrator on Rocky 9.3 container | ✅ PASS — 13 fields populated, 5/5 PASS markers |
| 2 | HOST-02 | Windows 11 ARM64 / VMware / PS5.1 | ✅ PASS — after 3 PS5.1 compat fix commits |
| 3 | HOST-03 | Cross-platform parity test on macOS | ✅ PASS — 13 fields each, envelope-stripped |
| 4 | HOST-04 | DATA-DICTIONARY structural verify | ✅ PASS — section + 13 fields + cloud subsection |
| 5 | HOST-05 | odin_overview.xml dashboard panels | ✅ PASS — viz count 12, AppInspect clean |

### PS5.1 Windows compatibility — 3 in-UAT fix commits

UAT found that the regression test `tools/tests/check-host-info.ps1` ran fine on `pwsh` (PowerShell 7+) on macOS but crashed on Windows PowerShell 5.1 (default Windows install). Phase 8 verifier had this blindspot. Fixed via 3 layered commits:

1. **`1771688`** — minimal precursor (lines 41+100 only). Insufficient.
2. **`4cc234a`** — defensive parser fix: ALL `Write-Host "[HOST-02 ...]"` patterns converted to `'...'` (single-quote literals) or `('... {0}' -f $var)` (-f format). PS5.1 parser quirk where literal brackets at quote-start trigger MissingArrayIndexExpression in `if`-block context.
3. **`571e6e7`** — Join-Path arity (PS5.1 only takes 2 positional args; switched to `[System.IO.Path]::Combine`) + ASCII-only output (PS5.1 reads UTF-8 without BOM as Windows-1252).

Production code (`TA-ODIN/bin/odin.ps1`, `_common.ps1`) was correct from Phase 8 — only test tooling needed PS5.1 hardening.

### Release artifacts

- **Tag:** `v1.0.2-rc1` (annotated, pushed to origin)
- **GitHub release:** https://github.com/lyderhansen/odin/releases/tag/v1.0.2-rc1 (prerelease)
- **Tarballs:** `.planning/artifacts/builds/v1.0.2-rc1/{TA-ODIN-1.0.2.tgz, ODIN_app_for_splunk-1.0.2.tgz}` (gitignored, also attached to GitHub release)
- **Build flags:** `COPYFILE_DISABLE=1 tar --no-mac-metadata --exclude='._*' --exclude='*/local/*'` (Splunkbase APPI-01 compliant)

### Tracking docs (state alignment)

- `REQUIREMENTS.md` traceability table: HOST-02..HOST-05 marked **CLOSED 2026-04-29**
- `ROADMAP.md` Phase 9 progress row: `1/3 Executing` → `3/3 Complete`
- `STATE.md` frontmatter: `status: executing` → `status: rc-shipped`
- `CHANGEHISTORY.md`: `## v1.0.2-wip` → `## v1.0.2 — Release Date 2026-04-29`

### HARD-01 version sync (1.0.2 across 6 sites)

| Site | Status |
|---|---|
| `TA-ODIN/default/app.conf` | `version = 1.0.2` ✓ |
| `ODIN_app_for_splunk/default/app.conf` | `version = 1.0.2` ✓ |
| `TA-ODIN/bin/odin.sh` | `export ODIN_VERSION="1.0.2"` ✓ |
| `TA-ODIN/bin/odin.ps1` | `env:ODIN_VERSION = '1.0.2'` ✓ |
| `TA-ODIN/bin/modules/_common.sh` | `ODIN_VERSION="${ODIN_VERSION:-1.0.2}"` ✓ |
| `TA-ODIN/bin/modules/_common.ps1` | `env:ODIN_VERSION = '1.0.2'` ✓ |

`bash tools/tests/check-version-sync.sh` → `[HARD-01 PASS] Version sync: 1.0.2`

---

## Active milestone tree

```
v1.0.0 ─── tagged 2026-04-15 (origin/main, GitHub release live)
   │
v1.0.1 ─── 67% (Phase 4+5 done); v1.0.1-rc1 SHIPPED 2026-04-28
   │       Phase 6 (PROD-02 pilot) blocked on real infra
   │
v1.0.2 ─── ✅ rc-shipped — v1.0.2-rc1 LIVE 2026-04-29
   │       Phase 7: Host Info — Linux ✓ COMPLETE (HOST-01)
   │       Phase 8: Host Info — Windows ✓ COMPLETE (HOST-02)
   │       Phase 9: Validation+Docs+Dashboard ✓ COMPLETE (HOST-03/04/05)
   │       UAT: 5/5 DONE (Rocky 9.3 container + Windows 11 ARM64 VM + macOS dev box)
   │
v1.1.0 ─── ⚡ TRIGGER SATISFIED — ready to open milestone
           Container Observability: 2 scenarios (INSIDE container + ON docker/k8s host)
           Seed: .planning/seeds/v1.1.0-container-observability.md (4 phases drafted)
           Estimated effort: 3-6 days
```

---

## Pending work — pre-tag v1.0.2 (no -rc suffix)

### 1. Production-like Splunk validation (recommended next)

Install both tarballs in a Splunk instance and confirm:
- Events with `odin_version=1.0.2` arrive in `index=odin_discovery`
- Exactly 1 `type=odin_host_info` event per scan per host (no duplicates from upgrade)
- 13 fields populated correctly (no field name typos, no value mangling)
- Dashboard `odin_overview.xml` renders both new panels (OS Distribution + Virtualization Breakdown) with real data
- AppInspect baseline preserved (failure=0, error=0, warning=0)

If validation passes → tag full `v1.0.2` (no -rc suffix), update GitHub release, mark `STATE.md` status `released`.

If validation surfaces bugs → fix-and-iterate, ship `v1.0.2-rc2`.

### 2. v1.1.0 milestone opening (parallel-safe)

`v1.1.0 — Container Observability` trigger condition is "v1.0.2 shipped" — satisfied with rc1. Can open in parallel with rc1 validation. Run:

```
/gsd-new-milestone "v1.1.0 — Container Observability"
```

The new-milestone workflow will:
1. Question goal/scope (seed at `.planning/seeds/v1.1.0-container-observability.md` is the authoritative input)
2. Optional research (k8s API integration, container enumeration patterns)
3. REQUIREMENTS scoping (3-4 phases per seed)
4. ROADMAP creation (continuing phase numbering 10+)

### 3. Tooling debt cleanup (low-priority)

- `tools.zip` (67K, untracked) — manual zip created during this UAT to copy `tools/` to Windows VM. Safe to delete or add to `.gitignore`.
- `.planning/artifacts/manual-tests/linux_sample.txt` — manual test fixture from earlier session. Consider adding `.planning/artifacts/manual-tests/` to `.gitignore` if not already.
- `.planning/research/` — research scratch dir from project setup. Safe to leave.

---

## Key lessons from this session (DO NOT lose)

1. **PS5.1 is a first-class CI target, not an afterthought.** Default Windows installs ship with PS5.1 only. PS7+ requires separate install. Test scripts validated only on `pwsh` will silently break on real Windows. Mitigation: `tools/tests/check-host-info.ps1` now has explicit "PS5.1 compatibility notes" header documenting the 3 quirks (string convention, Join-Path arity, ASCII-only). Future PowerShell tooling MUST follow these conventions.

2. **Cascading parser errors mask the root cause.** When PS5.1 reports parse errors on lines N1, N2, N3 — fix N1 first, retest. Often N2 and N3 are recovery-boundary artifacts that disappear once N1 is fixed. Don't try to fix all reported errors at once.

3. **`-f` format is a parser-shield idiom for PowerShell.** `('static {0}' -f $var)` parses identically to `"static $var"` semantically but uses EXPLICIT operator/operand structure that no PS parser misinterprets. For PowerShell strings with embedded interpolation AND literal brackets, `-f` is the bulletproof pattern.

4. **`COPYFILE_DISABLE=1 tar --no-mac-metadata` is mandatory for macOS builds.** AppleDouble (`._*` files) are auto-rejected by Splunkbase AppInspect (APPI-01). v1.0.1-rc1 build pattern carried forward unchanged.

5. **UAT cycle catches what code-review and verifier miss.** Phase 8 verifier and code-reviewer both passed cleanly on the PS5.1 compat issues because they ran in pwsh (PS7+) on macOS. Real-runtime UAT on actual Windows surfaced 3 distinct bugs that no automated check would have caught. UAT is not theater — it's the final defense layer.

6. **`status: rc-shipped` as transitional state.** STATE.md now distinguishes `executing` (in progress) → `rc-shipped` (rc out, awaiting validation) → `released` (full version tagged). Cleaner mental model than just `complete` for milestones with -rc cycles.

---

## Pre-handoff git state

- **Branch:** `main` (no other branches)
- **HEAD:** `280fa53` (synced with origin/main)
- **Tags:** `v1.0.0`, `v1.0.1-rc1`, `v1.0.2-rc1` (newest)
- **Commits since pre-compact handoff (`ffaeefe`):** 6 commits + 1 tag
- **Working tree:** clean except `.claude/` (cache), `tools.zip` (manual zip — see cleanup), `.planning/artifacts/manual-tests/linux_sample.txt`, `.planning/research/`
- **GitHub releases:** v1.0.0, v1.0.1-rc1, **v1.0.2-rc1** (newest, prerelease, 2 tarballs attached)

---

## Quick-resume commands

```bash
# See current state
/gsd-progress

# Recommended path: production validation
# (manual — install tarballs in Splunk, then come back)

# Then tag full v1.0.2 (after validation):
git tag -a v1.0.2 -m "v1.0.2 - Host Metadata Enrichment (full release after rc1 validation)"
git push origin v1.0.2
gh release edit v1.0.2-rc1 --prerelease=false  # promote rc1 release
# OR create new release: gh release create v1.0.2 ... --notes "..."

# Alternative: start v1.1.0 in parallel
/gsd-new-milestone "v1.1.0 — Container Observability"
```

---

## Risk profile

**v1.0.2 closure risk: VERY LOW.** rc1 is shipped, all auto-gates passed, UAT clean across 3 platforms (Linux container + Windows 11 ARM64 VM + macOS dev box). Worst case scenario: production Splunk validation surfaces a field-extraction edge case requiring rc2 (estimated 1-2h fix-and-retest cycle).

**v1.1.0 readiness: HIGH.** Trigger condition met. Seed comprehensive (4 phases drafted, decision context preserved from /gsd-explore session 2026-04-27). New-milestone workflow can run cleanly with seed as input.

**No outstanding blockers for any path forward.**
