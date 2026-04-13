---
phase: 2
slug: production-hardening
status: context-locked
created: 2026-04-13
depends_on: [Phase 1 Windows Parity]
requirements: [HARD-01, HARD-02, HARD-03, HARD-04, HARD-05, HARD-06, HARD-07, HARD-08]
---

# Phase 2 — Production Hardening — CONTEXT

> Design-decisions locked before research and planning. Downstream agents (gsd-phase-researcher, gsd-planner) use this file to know what's decided and what to investigate.

## Goal

Close every known production risk in the codebase so a Deployment Server push to 10k+ hosts is provably safe. Phase 1 landed Windows parity; Phase 2 makes the whole codebase lint-clean, version-consistent, tunable, observable, injection-safe, and mechanically split between the two apps.

## Locked Design Decisions

### D1 — CI platform: GitHub Actions only

**Decision:** One GitHub Actions workflow at `.github/workflows/ci.yml` runs on every PR to `main` and on pushes to `main`. Job steps: shellcheck, PSScriptAnalyzer, two-app-split guard, version-sync guard. No local pre-commit hooks in v1.0.0.

**Rationale:** Repo already has github.com/lyderhansen/odin as remote. AppInspect (Phase 3) needs CI as release gate anyway. Pre-commit hooks add friction without a meaningful safety net that CI doesn't already give.

**Downstream:** Phase 2 planner creates `.github/workflows/ci.yml` as a new file. Phase 3 reuses and extends this workflow (adds AppInspect job).

**Deferral:** Local pre-commit hooks may be added in v1.1+ if developer friction warrants.

### D2 — PSScriptAnalyzer strictness: Error + Warning fail CI

**Decision:** `Invoke-ScriptAnalyzer -Path TA-ODIN/bin -Recurse -Severity Error,Warning` must return zero findings. Information-severity findings are logged to CI artifacts but do not block the build.

**Rationale:** Phase 1 used `-Severity Error` as non-blocking sanity check. Phase 2 promotes it to release gate. Warning-level rules catch real bugs we already hit in Phase 1: `PSAvoidAssignmentToAutomaticVariable` (the `$pid` shadowing we corrected in ports.ps1 and processes.ps1), `PSAvoidUsingCmdletAliases` (gci/gcm/% that we explicitly banned), and `PSAvoidUsingPowerShellCoreOnlySyntax` (would have caught the `??` operator in mounts.ps1 if the rule were active).

**Downstream:** Planner must (a) run analyzer against current Phase 1 code and fix any existing Error+Warning findings as the first task in Phase 2, (b) wire the analyzer into CI.

### D3 — shellcheck strictness: default severity, zero findings

**Decision:** `shellcheck TA-ODIN/bin/odin.sh TA-ODIN/bin/modules/*.sh` exits 0 with default severity (info + warning + error all enforced). No `-S` override.

**Rationale:** HARD-05 says "zero findings at default severity" verbatim. Linux bash side is stable after two years — should tolerate the full rule set. If a few findings turn out to be false positives, we use inline `# shellcheck disable=SC####` directives rather than weakening the global severity.

**Downstream:** Planner runs `shellcheck` against all Linux modules first, fixes findings task-by-task, then wires it into CI.

### D4 — HARD-01 ODIN_VERSION: hardcode + drift guard

**Decision:** Hardcode the literal string `1.0.0` at all 4 sites (`TA-ODIN/default/app.conf`, `ODIN_app_for_splunk/default/app.conf`, `TA-ODIN/bin/odin.sh`, `TA-ODIN/bin/odin.ps1`). Ship `tools/tests/check-version-sync.sh` that parses all 4 and exits non-zero if any version string diverges. CI job runs this guard.

**Rationale:** Simpler and more auditable than build-time codegen or runtime imports. "Single source of truth" here means "synchronized across all sites, verified mechanically", not "imported from one file". Build-time approaches add a build step to a project that currently has zero build dependencies — out of scope for Phase 2.

**Downstream:** Planner creates `tools/tests/check-version-sync.sh` (new file) and a task to update all 4 sites from `2.1.0` / `2.2.0` drift to `1.0.0`.

**Note:** The project currently sits at v2.2.0 in some files and v2.1.0 in others — Phase 1's RESEARCH.md captured this drift as the first HARD-01 target. Phase 2 resets to `1.0.0` per PROJECT.md milestone semantics.

### D5 — HARD-02 tunable env vars: both orchestrators respect pre-set values

**Decision:** Both `odin.sh` and `odin.ps1` read `ODIN_MAX_EVENTS` and `ODIN_MODULE_TIMEOUT` from the environment. If pre-set, use as-is. If unset, apply internal defaults (50000 and 90 respectively). The current `odin.sh` already honors this pattern for some variables but the export logic overwrites pre-set values — needs a surgical fix.

**Rationale:** HARD-02 explicitly requires "pre-set values from the environment are honored and not overwritten by script defaults". The success criteria run the orchestrator with `ODIN_MAX_EVENTS=10` set at invocation and expects truncation at 10, not 50000.

**Downstream:** Planner writes a small patch to `odin.sh` + `odin.ps1` that wraps default assignment in `: "${ODIN_MAX_EVENTS:=50000}"` bash idiom (and the PowerShell `if (-not $env:ODIN_MAX_EVENTS) { ... }` equivalent already in `_common.ps1`). Also updates `_common.ps1` to prefer env var over script-scope initialization.

### D6 — HARD-03/04 saved searches: definition-only, no cadence

**Decision:** Ship two new stanzas in `ODIN_app_for_splunk/default/savedsearches.conf`:
- `[alert_odin_truncated_events]` — searches for `type=truncated` across the fleet
- `[alert_odin_timeout_failures]` — searches for `type=odin_error exit_code=124`

Both stanzas include the SPL query, description, and `disabled = 1` by default. No `cron_schedule`, no alert actions, no email recipients. Ops team enables and configures cadence per their retention/fleet/alert-channel setup.

**Rationale:** We don't know customer retention (7 days? 30 days? 1 year?), fleet size (1k? 50k?), or alert channels (email? PagerDuty? webhook?). Shipping an always-on scheduled alert guesses wrong and creates either false-positive spam or silent misses. "Definition-only" lets ops enable with one flag flip after they've set their own cadence.

**Downstream:** Planner writes the two stanzas with battle-tested SPL and clear comments explaining the ops-enable step. Adds a brief section in DOCS (when E phase lands in v1.1) explaining how to activate.

### D7 — HARD-07 two-app split guard: standalone bash script, CI-wrapped

**Decision:** Create `tools/tests/check-two-app-split.sh` as a standalone bash script that:
- Fails if `indexes.conf`, `transforms.conf`, `savedsearches.conf`, or any `lookups/` directory appears under `TA-ODIN/`
- Fails if `inputs.conf` or any `bin/` scripts appear under `ODIN_app_for_splunk/`

CI job invokes the script. Developers can run it locally during development with `bash tools/tests/check-two-app-split.sh`.

**Rationale:** Same pattern as `windows-parity-harness.sh` from Phase 1 — reusable, testable, invokable outside CI. Implementing the guard inline in `ci.yml` would duplicate the logic and hide it from developers.

**Downstream:** Planner creates the script and a CI step that invokes it. Test by temporarily adding a forbidden file, confirming the guard fails, then removing the test file.

### D8 — HARD-08 injection audit scope: Linux only, regression fixtures required

**Decision:** HARD-08 audit covers ONLY the Linux bash side: `TA-ODIN/bin/odin.sh` + `TA-ODIN/bin/modules/*.sh` (services, ports, packages, cron, processes, mounts). Windows side is out of scope because Phase 1 `Format-OdinValue` + Dimension 5 already mitigate injection (T-03-02 in plan 03 threat model).

**Work products:**
1. **Audit:** Read every `safe_val()` call site and every `emit` call site. Identify any path where external data flows into output without quote-wrapping and CRLF stripping.
2. **Fixes:** Apply surgical patches to any unsafe call site. Preserve existing key=value output format.
3. **Regression test:** `tools/tests/injection-fixtures/` with malicious service/unit/package/mount names containing `;`, `$(...)`, backticks, embedded newlines, unbalanced quotes. Test asserts `safe_val()` output is a single well-formed line with no shell expansion.

**Rationale:** HARD-08 verbatim says "the Linux modules". Windows modules went through the same audit during Phase 1 plan 03 threat modeling (T-03-02) and `Format-OdinValue` was explicitly designed for it. Re-auditing Windows would just duplicate work already done and verified by Dim 5 parity enforcement.

**Downstream:** Planner produces one task per module with audit notes, one task for the fix pass, one task for the regression test fixture, one task for running the test fixture.

## Dependency chain

Phase 2 tasks have a natural order enforced by dependencies:

1. **HARD-01 first** — version unification is trivial and needs to land before CI guards are written (so the guards assert `1.0.0`, not whatever drift is currently committed).
2. **HARD-02 second** — tunable guardrails, independent, quick.
3. **HARD-05 and HARD-06 in parallel** — shellcheck and PSScriptAnalyzer audit passes. Both are linting the existing code, no overlap.
4. **HARD-08 parallel to HARD-05/06** — injection audit happens on the same Linux files but checks different properties.
5. **HARD-07 after 5/6** — two-app split guard needs the lint gates to already exist so it can be slotted into the same CI workflow.
6. **HARD-03 and HARD-04 last** — saved search stanzas are ODIN_app_for_splunk-side, independent of everything else, can land any time after CI is wired.

The planner will decide exact wave grouping, but the above dependency hints guide the split.

## Deferred work items

- **Local pre-commit hooks** — Deferred to v1.1+ per D1.
- **Alert cadence, email recipients, webhook integration** — Deferred to ops team per D6 (user enables stanzas after their own configuration).
- **Windows-side injection audit** — Out of scope per D8 (already handled by `Format-OdinValue` in Phase 1).
- **Reproducible packaging** — Deferred to v1.1+ per ROADMAP.md (this is requirement group G, out of milestone scope).
- **AppInspect compliance** — Phase 3, not Phase 2.
- **Dashboards** — Out of milestone scope per CLAUDE.md.
- **Build-time codegen for ODIN_VERSION** — Rejected in D4 (would add a build step to a zero-build project).
- **Unified PowerShell 5.1 / 7 compatibility shims** — Phase 1 already handles this case-by-case (no null-coalescing, explicit if/else); Phase 2 lint gate (PSScriptAnalyzer `PSAvoidUsingPowerShellCoreOnlySyntax`) will catch regressions mechanically.

## Context for downstream agents

**For gsd-phase-researcher:**
- Investigate: shellcheck default ruleset, PSScriptAnalyzer rule catalog, GitHub Actions runner images that pre-install shellcheck and pwsh, Splunk savedsearches.conf alerting syntax, safe_val() call graph in Linux modules, bash `${VAR:=default}` vs `${VAR:-default}` semantics for HARD-02.
- Do NOT investigate: AppInspect (Phase 3), Windows injection paths (out of scope per D8), alerting integrations beyond Splunk savedsearches.conf.

**For gsd-planner:**
- Split roughly into 3 plans: (Plan 1) version unification + tunable guardrails + version-sync guard [HARD-01, HARD-02]; (Plan 2) lint gates + CI infrastructure + two-app split guard [HARD-05, HARD-06, HARD-07]; (Plan 3) injection audit + regression fixtures + alert stanzas [HARD-08, HARD-03, HARD-04].
- Exact split is planner's call — these are hints, not mandates.
- Every task must have an `<automated>` verify block; pure audit tasks get a checklist verifier that greps for the audited call sites.
- Threat model every plan (even HARD-03/04 alerts — STRIDE-analyze the SPL query for information disclosure if someone runs it on wrong index context).
