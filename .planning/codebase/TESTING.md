# Testing

**Analysis Date:** 2026-04-10

## Summary — No Automated Tests for the Shipping Code

**The core TA-ODIN bash modules and the ODIN_app_for_splunk Splunk configuration have no automated tests.** There is no bash test framework (no `bats`, no `shunit2`), no Splunk `.conf` validation in CI, no CSV schema validation, and no GitHub Actions / CI pipeline of any kind. All verification of the collection pipeline, the classification lookups, the props/transforms stanzas, and the saved searches is done **manually** by running commands locally and eyeballing events in a Splunk instance.

This is a significant gap and is also surfaced in `CONCERNS.md`.

There **is** a small pytest suite in `tools/tests/` — but it only covers the Python **synthetic data generator** (`tools/generate_odin_data.py`) used to produce demo data for dashboards. It does not exercise the bash modules, the orchestrator, or Splunk parsing.

## Test Framework — Partial (Python Tooling Only)

**Runner:** `pytest` (no version pinned; no `requirements.txt` observed in repo root or `tools/`)
**Config:** None — no `pytest.ini`, `pyproject.toml`, `setup.cfg`, or `conftest.py` at repo root or in `tools/`.
**Scope:** `tools/tests/` only. Covers the synthetic-data generator, not production code.

### Test files

- `tools/tests/__init__.py`
- `tools/tests/test_generate_odin_data.py` — tests `tools/generate_odin_data.py`
- `tools/tests/test_classification_coverage.py` — cross-references generated host profiles against the CSV lookup files in `ODIN_app_for_splunk/lookups/`

### Run command

```bash
cd tools && python -m pytest tests/
```

Or from repo root:

```bash
python -m pytest tools/tests/
```

Neither command is documented in `CLAUDE.md` or any README. It is inferred from the file layout and the `sys.path.insert(0, str(Path(__file__).parent.parent))` shim at `tools/tests/test_classification_coverage.py:10`.

### What the Python tests actually cover

From `tools/tests/test_classification_coverage.py`:

- `test_service_signals_match_classify_services()` — asserts that at least 20 service names in the generator's `HOST_PROFILES` exist in `ODIN_app_for_splunk/lookups/odin_classify_services.csv`. A coverage sanity check for demo data, not a test of the lookup itself.
- Other tests in the file follow the same pattern for ports/packages.

These tests will fail if someone deletes rows from the classification CSVs that the demo generator depends on — which is useful as a lightweight schema-drift canary but does not validate production behavior.

## Manual Test Patterns (the actual "test suite")

All real verification of TA-ODIN happens via manual commands documented in `CLAUDE.md` under "Common Tasks". These are the only smoke-test procedures for the bash modules and the Splunk configuration.

### 1. Run the full orchestrator locally

```bash
cd TA-ODIN && bash bin/odin.sh
```

Verifies end-to-end: bash availability check, module autodiscovery, per-module timeout, MAX_EVENTS accounting, start/complete events, and exit code. Output goes to stdout as space-separated `key=value` events. Eyeball the output for:

- A `type=odin_start` line at the top.
- A `type=odin_complete modules_total=6 modules_success=6 modules_failed=0` line at the bottom (on a healthy Linux host with all six modules succeeding).
- No `type=odin_error` lines.
- No `type=truncated` lines unless testing on a 50k+ item host.

### 2. Run a single module in isolation

```bash
export ODIN_HOSTNAME=test ODIN_OS=linux ODIN_RUN_ID=test-001 ODIN_VERSION=2.1.0
bash TA-ODIN/bin/modules/services.sh
```

Exercises each module's standalone-fallback branch (`if ! declare -f emit &>/dev/null`). The `ODIN_*` exports are required because the module header expects them — running without the exports still works (the module provides defaults), but you lose the ability to correlate runs.

Repeat for `ports.sh`, `packages.sh`, `cron.sh`, `processes.sh`, `mounts.sh`.

**What to verify:**
- Every line starts with `timestamp=... hostname=test os=linux run_id=test-001 odin_version=2.1.0`.
- Every module-specific line begins `type=<module>` (e.g. `type=service`).
- Values with spaces are double-quoted.
- No multi-line output.
- Exit code is 0.

### 3. Verify events land in Splunk

After deploying to a real Splunk instance:

```spl
index=odin_discovery sourcetype=odin:enumeration
| stats count by type
| sort - count
```

Expected types: `service`, `port`, `package`, `cron`, `process`, `mount`, plus exactly one `odin_start` and one `odin_complete` per host per scan.

### 4. Verify classification lookup enrichment

```spl
index=odin_discovery sourcetype=odin:enumeration type=service
| lookup odin_classify_services service_name OUTPUT category, role
| stats count by hostname, role
```

Validates that `ODIN_app_for_splunk/default/props.conf` `LOOKUP-*` bindings, `transforms.conf` lookup definitions, and the CSV content are all wired together correctly.

### 5. Verify Phase 2 host role classification

```spl
index=odin_discovery sourcetype=odin:enumeration (type=service OR type=port OR type=package)
| eval signal_type=type
| eval signal_value=case(type="service", service_name, type="port", listen_port."/".transport, type="package", package_name)
| lookup odin_log_sources signal_type, signal_value
| where isnotnull(host_role)
| stats values(host_role) AS host_roles by hostname
```

This is the same SPL pattern used by the `[ODIN - Host Inventory]` saved search in `ODIN_app_for_splunk/default/savedsearches.conf`. Running it ad-hoc validates the signal synthesis, the `odin_log_sources.csv` lookup, and the dedup logic before trusting the scheduled search.

### 6. View generated output lookups

```spl
| inputlookup odin_host_inventory.csv
```

and

```spl
| inputlookup odin_host_inventory.csv
| makemv delim="," recommended_tas
| mvexpand recommended_tas
| stats values(hostname) AS hosts, dc(hostname) AS host_count by recommended_tas
| sort - host_count
```

Inspect the tables the saved searches produce. If `odin_host_inventory.csv` is empty, the scheduled search has either not run yet or the `odin_log_sources.csv` lookup has no matching rows for the signals actually present on the hosts.

## Manual Test Checklists

### Before merging a bash module change

1. `cd TA-ODIN && bash bin/odin.sh` exits 0 on a test host.
2. `bash bin/modules/<changed>.sh` run standalone produces expected events.
3. Event count stays within reason (well under `ODIN_MAX_EVENTS=50000`).
4. Each external command in the changed module is wrapped in `timeout N`.
5. Runtime for the changed module is well under 90s on a busy host.
6. `hostname` value contains no spaces or quotes that would break parsing.
7. Value quoting test: any field that could contain a space is routed through `safe_val`.

### Before merging a lookup CSV change

1. Header row matches the expected schema (see `CONVENTIONS.md`).
2. File ends with a newline, Unix line endings.
3. No rogue commas in description fields (or they are double-quoted).
4. `python -m pytest tools/tests/test_classification_coverage.py` passes if the rows correspond to signals the demo generator produces.
5. In Splunk, manually run the enrichment SPL (pattern #4 above) and confirm the new rows match as intended.
6. If the change is to `odin_log_sources.csv`, rerun the three saved searches (`ODIN - Host Inventory`, `ODIN - Log Source Details`, `ODIN - TA Deployment Matrix`) and inspect the generated output lookups.

### Before merging a `.conf` change

1. No `indexes.conf` in `TA-ODIN/`.
2. No `inputs.conf` in `ODIN_app_for_splunk/`.
3. Restart Splunk (or use `| rest /services/server/control/restart`) and check `splunkd.log` for parse errors.
4. Run pattern #3 to confirm events still index.
5. Run pattern #4 to confirm lookups still bind.

## Gaps and Risks

**No automated test coverage for production code:**

- Bash modules have no unit tests. A regression in `safe_val`, the systemctl batch parser in `services.sh:56-120`, the IPv6 port parser in `ports.sh:39-65`, or the cron line parser in `cron.sh:41-50` will only be caught manually.
- The orchestrator's `emit()` MAX_EVENTS truncation logic at `TA-ODIN/bin/odin.sh:51-66` is untested. A bug here could flood Splunk or silently drop events with no warning.
- The standalone-fallback branch in every module (`if ! declare -f emit &>/dev/null`) is untested and easy to drift from the orchestrator version, since it is copy-pasted.
- No snapshot tests for emitted event format. A change to the prelude would silently break downstream `KV_MODE=auto` extraction and no one would notice until a dashboard broke.
- No CSV schema validation in CI. A typo in a header (`service_patern` instead of `service_pattern`) breaks the lookup silently at search time.
- No `.conf` linting. A typo in a stanza key (e.g. `LOOKUP-classify_servces`) is a silent no-op.
- No SPL validation. The long multi-line searches in `savedsearches.conf` are not parsed by any tool before deployment.
- No CI pipeline at all — no GitHub Actions, no pre-commit hooks, no `make check` target.
- No multi-distro matrix test. The modules claim to support systemctl, `service`, and `init.d` fallbacks but these fallbacks are only exercised on hosts that happen to lack systemctl.
- No root-vs-non-root test matrix. The `cron` and `ports` modules have different output under different privilege levels and this is not verified.
- The `tools/tests/` suite is not run in CI and has no documented way to install dependencies (no `requirements.txt` seen).

**Recommended additions (for a future phase):**

1. Add `bats` tests for the orchestrator and each module, running against fixture command outputs piped through stubs.
2. Add a CSV schema validator (python script or `csvlint`) that enforces the header conventions from `CONVENTIONS.md`.
3. Add a `.conf` linter (Splunk's own `splunk btool` or `splunk-appinspect`) as a pre-commit or CI check.
4. Add an SPL syntax check by parsing saved searches with Splunk's SDK in CI.
5. Add a `Makefile` or `justfile` with `make test`, `make lint`, `make check` targets so new contributors know how to verify changes.
6. Document the `python -m pytest tools/tests/` command in the repo README so it actually gets run.
7. Add a distro matrix (Ubuntu, RHEL, Alpine, Amazon Linux) via container-based integration tests that run `bin/odin.sh` and diff the output against golden files.
