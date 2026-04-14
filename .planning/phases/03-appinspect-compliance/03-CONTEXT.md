---
phase: 3
slug: appinspect-compliance
status: context-locked
created: 2026-04-14
depends_on: [Phase 1 Windows Parity, Phase 2 Production Hardening]
requirements: [APPI-01, APPI-02, APPI-03, APPI-04, APPI-05, APPI-06]
---

# Phase 3 — AppInspect Compliance & Release Gate — CONTEXT

> Design-decisions locked before research and planning. Downstream agents (gsd-phase-researcher, gsd-planner) use this file to know what's decided and what to investigate.

## Goal

Both TA-ODIN and ODIN_app_for_splunk must pass `splunk-appinspect inspect --mode precert` with zero failures and zero manual-review warnings. Metadata must be Splunkbase-ready. AppInspect must be a mandatory release gate in the existing CI workflow (not advisory). The v1.0.0 tarballs must be pilot-deliverable with no ad-hoc pre-flight work.

Phase 1 landed Windows code, Phase 2 made it lint-clean and fleet-safe, Phase 3 is the final certification step before Splunkbase submission.

## Current state snapshot (from codebase scout, 2026-04-14)

- **TA-ODIN/default/app.conf:** Has `version = 1.0.0` (correct from Phase 2 HARD-01). Has `author = Your Organization` (PLACEHOLDER). Missing `license` field. Has `build = 3` in `[install]` stanza (arbitrary). Header comment still says `v2.2.0` (STRING DRIFT missed by Phase 2 check-version-sync.sh because that guard only greps the `version = ` line).
- **ODIN_app_for_splunk/default/app.conf:** Same pattern — `author = Your Organization`, missing `license`, `build = 1`, header comment says `v2.2.0`.
- **TA-ODIN/metadata/default.meta:** DOES NOT EXIST.
- **ODIN_app_for_splunk/metadata/default.meta:** Has blanket `export = system` for `[lookups]`, `[props]`, `[transforms]`, `[savedsearches]`, `[views]` — 5 stanzas, all system-wide.
- **splunk-appinspect:** NOT installed on the dev machine. No AppInspect findings captured yet.
- **CI workflow (.github/workflows/ci.yml from Phase 2):** 5 steps (shellcheck, PSA, two-app-split, version-sync, injection-fixture). Does NOT yet include AppInspect.

## Locked Design Decisions

### D1 — splunk-appinspect installation: pip-installed locally + CI step

**Decision:** Install via `pip install splunk-appinspect` on the dev machine for iteration. Wire it into the existing `.github/workflows/ci.yml` as a new job step that runs on every PR and push. No Docker, no Makefile.

**Rationale:** splunk-appinspect is a Python package that runs cross-platform. pip install on macOS works without additional system dependencies. The existing Phase 2 CI workflow is the natural home for the AppInspect gate — adds one step, reuses the same checkout + ubuntu-latest runner.

**Downstream:** Phase 3 planner must add a "Install splunk-appinspect" step to ci.yml followed by "Run AppInspect on TA-ODIN" and "Run AppInspect on ODIN_app_for_splunk" steps. Both must exit 0 for the CI job to pass.

**Deferral:** Docker-based AppInspect sandbox is deferred to v1.1+ if pip-based runs turn out to be non-reproducible across runner versions.

### D2 — App.conf metadata values (DEFAULTS — user may override during Plan 1)

**Decision (defaults chosen from repo context):**
- **author:** `Lyder Hansen` (from `git config user.name` and GitHub remote `lyderhansen/odin`)
- **license:** `Apache-2.0` (most common permissive license for Splunk TAs, Splunkbase-friendly)
- **description TA-ODIN:** `TA-ODIN forwarder app — enumerates services, ports, packages, scheduled tasks, processes, and mounts on Linux and Windows endpoints. Reports metadata only, never log content. Pairs with ODIN_app_for_splunk on indexers and search heads.` (~260 chars — AppInspect limit is ~400)
- **description ODIN_app_for_splunk:** `ODIN indexer and search head app — provides the odin_discovery index, classification lookups, and search-time enrichment for TA-ODIN enumeration data. Deploy TA-ODIN to forwarders separately.` (~200 chars)
- **build:** Leave existing values (`build = 3` for TA-ODIN, `build = 1` for ODIN_app_for_splunk). AppInspect does not validate the number — any integer passes.
- **version:** Already `1.0.0` from Phase 2 HARD-01. Do not touch.
- **id:** Already `TA-ODIN` and `ODIN_app_for_splunk`. Match directory names, Splunkbase-compatible. Do not touch.

**Rationale:** These defaults pass AppInspect's APPI-04 check and are accurate enough for Splunkbase submission. If the user wants a different author name, different license (e.g., MIT or proprietary), or different description wording, they can be edited in Plan 1 Task 1 before the first AppInspect run.

**Downstream:** Plan 1 Task 1 patches both app.conf files with these defaults. The planner must present the final values in the task action block so the user can review and override before execution commits.

**USER OVERRIDE PROMPT:** Before Plan 1 Task 1 executes, the executor must surface these 3 fields (author, license, description) and allow a one-line override. If the user provides different values, those become the final values in the commit.

### D3 — metadata/default.meta scoping strategy

**Decision:**
- **ODIN_app_for_splunk:** Keep blanket `export = system` for all 5 stanzas (`[lookups]`, `[props]`, `[transforms]`, `[savedsearches]`, `[views]`). Document rationale inline as a header comment: "This IS the search-head app whose entire purpose is to make lookups and saved searches available to TA-ODIN-sourced events system-wide. Narrower scoping would break the TA-ODIN → ODIN_app_for_splunk data path."
- **TA-ODIN:** Create new `TA-ODIN/metadata/default.meta` with `[]` (default stanza) `export = none`. Document rationale: "TA-ODIN is a forwarder-only app. It has no lookups, no saved searches, no views to export. The explicit `export = none` tells AppInspect the empty export surface is intentional, not an omission."

**Rationale:** APPI-05 says exports should be "scoped as tightly as viable rather than blanket `export = system`". For ODIN_app_for_splunk, "as tightly as viable" means system — that's the app's purpose. The key word is "viable". Inline rationale comments make the decision auditable per ROADMAP success criterion #3.

**Downstream:** Plan 1 Task 2 creates `TA-ODIN/metadata/default.meta` and patches `ODIN_app_for_splunk/metadata/default.meta` with rationale comments. If AppInspect still flags the blanket export as a warning (not a failure), the warning is accepted with documented rationale in the SUMMARY.md.

### D4 — AppInspect mode: `--mode precert`

**Decision:** Use `splunk-appinspect inspect <app-dir> --mode precert --output-file .planning/artifacts/appinspect/<app-name>-<date>.json`. Capture JSON report to `.planning/artifacts/appinspect/` for reproducibility per ROADMAP success criterion #1.

**Rationale:** `precert` is the standard pre-certification mode that runs the full Splunk cloud-vetting rule set, including manual-review checks. It is what Splunkbase actually uses for cloud vetting. Other modes (`--mode experimental`, `--mode cloud`) are either broader or narrower — precert matches the ROADMAP's explicit target.

**Downstream:** Plan 1 Task 3 creates `.planning/artifacts/appinspect/` directory and runs both AppInspect invocations with the `--output-file` flag. Plan 3 Task (final) verifies the JSON reports show `failures: 0, manual_review: 0`.

### D5 — Finding-handling strategy: 3-plan split (audit → fix → CI integration + polish)

**Decision:** Phase 3 splits into three plans:
- **Plan 1 — Metadata polish + initial audit:** Install splunk-appinspect, update both app.conf files with real values, create/patch metadata/default.meta files, fix header comment drift (`v2.2.0` → `v1.0.0`), run FIRST AppInspect audit, commit JSON reports as baseline.
- **Plan 2 — Fix findings:** For each AppInspect finding from Plan 1's audit, one task per finding category. Examples: `http://` URL removal, hardcoded path replacement, comment cleanup, deprecated setting migration. Actual tasks depend on what Plan 1's audit surfaces.
- **Plan 3 — CI integration + final clean audit + red-flag sweep:** Wire AppInspect into `.github/workflows/ci.yml` as a mandatory gate. Run deliberate-violation smoke test (inject `http://` URL, confirm CI fails, revert). Run final clean AppInspect audit on both apps with zero findings. Run APPI-06 full-repo red-flag grep (success criterion #5). Commit final SUMMARY.

**Rationale:** Same staged pattern as Phase 1 and Phase 2. Each plan is atomic enough to execute in one gsd-executor spawn. Plan 2 is the only plan whose task count is TBD — it depends on Plan 1's audit results.

**Downstream:** Plan 2's task list is generated AFTER Plan 1's audit runs. The planner may write a placeholder Plan 2 skeleton during the initial plan-phase run, then the executor expands it during Wave 1 based on actual findings. Alternatively, Plan 1 captures findings and immediately spawns a re-plan for Plan 2 with concrete tasks.

### D6 — v2.2.0 header comment drift: fix in Plan 1 + extend check-version-sync.sh

**Decision:** Plan 1 Task 1 updates header comments in both `app.conf` files from `v2.2.0` to `v1.0.0`. Extend `tools/tests/check-version-sync.sh` from Phase 2 Plan 1 to ALSO grep for `v[0-9]\.[0-9]\.[0-9]` patterns in `.conf` file comments — not just the `version = ` line. The extended guard catches future string-drift regressions.

**Rationale:** Phase 2 HARD-01 resolved live version drift but missed dead-string drift in comments. A human reviewer glancing at `app.conf` now sees `v2.2.0` in the header and `version = 1.0.0` in the stanza — confusing and professionally embarrassing on a Splunkbase submission. The fix is mechanical; extending the guard prevents regression.

**Downstream:** Plan 1 Task 1 updates both header comments and patches `check-version-sync.sh` in one atomic commit. Plan 1 Task 1 also verifies that `bash tools/tests/check-version-sync.sh` still exits 0 after the extended grep (it must — both live and comment values are now `1.0.0`).

### D7 — APPI-03 hard-gate test: `http://` URL in conf comment

**Decision:** Plan 3 final validation task uses the following reversible test to prove APPI-03 is a hard gate:
1. Inject `# http://example.com test comment` into `TA-ODIN/default/app.conf` (reversible change in a comment line)
2. Run the CI workflow locally via `act` OR commit to a feature branch and observe CI fails
3. Verify CI fails on the AppInspect step with the expected red-flag rule
4. Revert the injection, re-run CI, verify pass

**Rationale:** ROADMAP success criterion #4 verbatim requires this test. Using a comment-only injection means zero behavioral impact on the actual TA. AppInspect's "no_hardcoded_urls" or equivalent rule will catch it.

**Downstream:** Plan 3 last task documents the 4-step sequence. If `act` (local GitHub Actions runner) is available, run it locally; otherwise commit to a throwaway branch for the test and delete the branch afterward.

### D8 — Reproducible AppInspect artifact storage

**Decision:** Create `.planning/artifacts/appinspect/` directory under `.planning/` (a documentation-only tree — not shipped with the Splunk tarballs). Filename convention: `<app-id>-<YYYY-MM-DD>.json` (e.g., `ta-odin-2026-04-14.json` and `odin-app-for-splunk-2026-04-14.json`). Each audit run overwrites its own dated file if the same date is used, otherwise creates a new file. The Plan 3 final commit keeps the LAST clean audit from each app plus any interesting intermediate audits that show progress.

**Rationale:** `.planning/artifacts/` is already gitignored in the planning tree by convention — wait, let me verify that. Actually, `.planning/` IS tracked in git (the whole CONTEXT.md/PLAN.md/SUMMARY.md system lives there). So `.planning/artifacts/appinspect/*.json` will be committed. That's fine for reproducibility — a reviewer can see the last AppInspect result without re-running the tool.

**Downstream:** Plan 1 Task 3 creates the directory with a `.gitkeep` file if empty. Plan 1 + Plan 3 both write `.json` files into it. Plan 2's fix passes may ALSO generate intermediate audits for before/after comparison; those are committed as part of each task's proof-of-fix.

## Deferred work items

- **Docker-based AppInspect sandbox** — Deferred to v1.1+ per D1 rationale.
- **Makefile-based release build** — Not used; CI workflow is the build gate per D1.
- **Per-object `metadata/local.meta`** — Not needed for v1.0.0; blanket system export for ODIN_app_for_splunk is intentional per D3.
- **Reproducible packaging** (tar.gz generation) — Deferred to v1.1+ per PROJECT.md / ROADMAP.md (requirement group G, not in milestone scope).
- **Dashboards and views** — Out of milestone scope per CLAUDE.md.
- **AppInspect manual-review-only findings** — If any finding is legitimately manual-review-only (not an automated rule), accept it with documented rationale in SUMMARY.md. Do not fabricate a fix just to silence the check.

## Context for downstream agents

**For gsd-phase-researcher:**
- Investigate: splunk-appinspect CLI interface (flags, output formats, rule list for precert mode), common AppInspect rule catalog (especially around hardcoded URLs, scripts, binaries, network calls), Splunkbase app.conf metadata requirements (author format, description length limits, license canonical names), CIM taxonomy compliance rules for saved searches, metadata/default.meta export scoping precedence, splunk-appinspect exit codes and JSON schema.
- Do NOT investigate: AppInspect manual-review-only checks that are out of scope for automated gate; Docker sandbox variants (deferred per D1); Makefile release builds (not used); TA-ODIN module output format (already verified by Phase 1 harness).

**For gsd-planner:**
- Split into 3 plans per D5: metadata polish + audit → fix findings → CI integration + final clean audit.
- Plan 1's task count is known (4-5 tasks: metadata, app.conf, meta files, audit, commit artifacts).
- Plan 2's task count is TBD and depends on Plan 1's audit findings. Write Plan 2 as a skeleton during initial plan-phase run; the executor will expand it after Plan 1 completes, OR the orchestrator re-invokes plan-phase to regenerate Plan 2 with concrete tasks.
- Plan 3's task count is ~4-5 (CI patch, AppInspect installation step, deliberate-violation smoke test, red-flag grep, final clean audit).
- Every task must have an `<automated>` verify block. AppInspect rules can be asserted via exit code or JSON field greps on the captured report.
- Threat model every plan. For Plan 3 specifically, the CI integration adds supply-chain risk: `pip install splunk-appinspect` pulls from PyPI — pin the version if possible, document the integrity check.
- The user override prompt for D2 (author/license/description) must be surfaced in Plan 1 Task 1's action block so the executor can ask before committing placeholder defaults.
