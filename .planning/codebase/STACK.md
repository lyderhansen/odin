# Technology Stack

**Analysis Date:** 2026-04-10

## Languages

**Primary:**
- Bash (GNU Bash 4+) — All endpoint enumeration logic for Linux. Used in `TA-ODIN/bin/odin.sh` (orchestrator) and the six module scripts in `TA-ODIN/bin/modules/` (`services.sh`, `ports.sh`, `packages.sh`, `cron.sh`, `processes.sh`, `mounts.sh`). Scripts rely on Bash-specific features (`[[ ]]`, `BASH_REMATCH`, arrays, associative arrays via `declare -A`, `<<<` here-strings) and explicitly check `$BASH_VERSION` at startup in `TA-ODIN/bin/odin.sh`.

**Secondary:**
- PowerShell — Windows enumeration placeholder only. Single stub file `TA-ODIN/bin/odin.ps1` that emits a "not yet implemented" event. Not functional.
- Splunk SPL (Search Processing Language) — Search-time logic in `ODIN_app_for_splunk/default/savedsearches.conf` (three saved searches: "ODIN - Host Inventory", "ODIN - Log Source Details", "ODIN - TA Deployment Matrix") and the dashboard datasource queries in `ODIN_app_for_splunk/default/data/ui/views/odin_overview.xml`.
- Splunk `.conf` (INI-style configuration DSL) — App metadata, inputs, props, transforms, indexes, savedsearches, metadata permissions. See `TA-ODIN/default/*.conf` and `ODIN_app_for_splunk/default/*.conf`.
- CSV — Classification and lookup tables under `ODIN_app_for_splunk/lookups/` (`odin_classify_services.csv`, `odin_classify_ports.csv`, `odin_classify_packages.csv`, `odin_log_sources.csv`, `odin_recommended_tas.csv`).
- XML — Splunk Dashboard Studio / SimpleXML view definitions: `ODIN_app_for_splunk/default/data/ui/views/odin_overview.xml`, `ODIN_app_for_splunk/default/data/ui/nav/default.xml`.
- Python 3 — Used only for developer tooling (not deployed). `tools/generate_odin_data.py` generates synthetic enumeration events; tests under `tools/tests/` (`test_classification_coverage.py`, `test_generate_odin_data.py`).

## Runtime

**Environment:**
- Splunk Universal Forwarder (running `TA-ODIN`) — Executes `bin/odin.sh` via scripted input on each endpoint. Target OS: Linux.
- Splunk Enterprise / Indexers (running `ODIN_app_for_splunk`) — Hosts the `odin_discovery` index defined in `ODIN_app_for_splunk/default/indexes.conf`.
- Splunk Enterprise / Search Heads (running `ODIN_app_for_splunk`) — Performs search-time field extraction, CIM aliasing, lookup enrichment, and runs scheduled saved searches.
- Linux (any distro with Bash) — Required on endpoints. Modules auto-detect distro family via `/etc/os-release` (in `TA-ODIN/bin/modules/packages.sh`).
- Python 3 — Required only for `tools/generate_odin_data.py` and the pytest suite. Not needed at runtime.

**Package Manager:**
- Splunk Deployment Server — Distributes `TA-ODIN` to Universal Forwarders via `deployment_apps/`.
- Splunk Cluster Manager or manual install — Distributes `ODIN_app_for_splunk` to indexers and search heads.
- Not applicable: no Node/npm, no pip lockfile committed for runtime dependencies.

## Frameworks

**Core:**
- Splunk Technology Add-on (TA) framework — Standard Splunk app layout with `default/`, `local/`, `bin/`, `lookups/`, `metadata/` directories. Two-app split per Splunk best practices (collection vs. knowledge).
- Splunk Common Information Model (CIM) — Compliance via field aliases in `ODIN_app_for_splunk/default/props.conf` (`FIELDALIAS-dest = hostname AS dest`, `FIELDALIAS-dvc = hostname AS dvc`).
- Splunk scripted inputs — Declared in `TA-ODIN/default/inputs.conf` (`[script://./bin/odin.sh]`, `[script://.\bin\odin.ps1]`).
- Splunk search-time lookups — WILDCARD and exact-match lookups declared in `ODIN_app_for_splunk/default/transforms.conf` and bound in `ODIN_app_for_splunk/default/props.conf` via `LOOKUP-*` stanzas.
- Splunk Dashboard Studio — Dashboard definitions use `<dashboard version="2">` with embedded JSON `<definition>` in `ODIN_app_for_splunk/default/data/ui/views/odin_overview.xml`.

**Testing:**
- pytest — Python test runner for developer tooling only. Tests at `tools/tests/test_classification_coverage.py` and `tools/tests/test_generate_odin_data.py`. `.pytest_cache/` present in repo root.
- No bash test framework (no bats, shellspec). Manual module testing documented in `CLAUDE.md` via direct invocation with `ODIN_*` env vars.

**Build/Dev:**
- No build system — Splunk apps are shipped as directory trees; no compilation step.
- Git — Source control. Remote: `https://github.com/lyderhansen/odin.git`, branch `main`.

## Key Dependencies

**Critical (endpoint system binaries invoked by modules):**
- `bash` — Required (hard-checked in `TA-ODIN/bin/odin.sh` line 16).
- `timeout` (coreutils) — Wraps all external commands. Optional; modules degrade gracefully when absent (`HAS_TIMEOUT` check in `TA-ODIN/bin/odin.sh`).
- `systemctl` — Primary service and timer enumerator. Used in `TA-ODIN/bin/modules/services.sh` (batch `systemctl show --type=service --all`) and `TA-ODIN/bin/modules/cron.sh` (batch `systemctl list-timers` + `systemctl show`).
- `service` / `/etc/init.d` — Fallback service enumerators in `TA-ODIN/bin/modules/services.sh`.
- `ss` (iproute2) — Primary listening-port enumerator in `TA-ODIN/bin/modules/ports.sh` (`ss -tulpn`).
- `netstat` (net-tools) — Fallback port enumerator in `TA-ODIN/bin/modules/ports.sh`.
- `dpkg-query` — Debian/Ubuntu package enumerator in `TA-ODIN/bin/modules/packages.sh`.
- `rpm` — RHEL/CentOS/Fedora/SUSE package enumerator in `TA-ODIN/bin/modules/packages.sh`.
- `apk` — Alpine package enumerator in `TA-ODIN/bin/modules/packages.sh`.
- `pacman` — Arch/Manjaro package enumerator in `TA-ODIN/bin/modules/packages.sh`.
- `ps` (procps-ng) — Process enumerator in `TA-ODIN/bin/modules/processes.sh`. Falls back through `ps -eo ...` → `ps -o ...` → `ps -ef` / `ps aux` for BusyBox systems.
- `df` — Mount enumerator in `TA-ODIN/bin/modules/mounts.sh`. Falls back `df -PT` → `df -P` → `df`.
- `cron` filesystem layout — Reads `/etc/crontab`, `/etc/cron.d/`, `/var/spool/cron/crontabs/`, `/var/spool/cron/`, `/etc/cron.{hourly,daily,weekly,monthly}/`, `/etc/anacrontab` in `TA-ODIN/bin/modules/cron.sh`.
- `hostname` — Used by orchestrator and every module for `ODIN_HOSTNAME`.
- `date`, `id`, `basename`, `dirname`, `sed`, `grep`, `tr`, `xargs`, `tail`, `echo` — Standard POSIX utilities used throughout.

**Infrastructure (Splunk side):**
- Splunk Enterprise index `odin_discovery` — Defined in `ODIN_app_for_splunk/default/indexes.conf`. Default retention 1 year (`frozenTimePeriodInSecs = 31536000`), max size 1024 MB.
- Splunk sourcetype `odin:enumeration` — Parsing declared in both `TA-ODIN/default/props.conf` (minimal: line breaking, timestamp) and `ODIN_app_for_splunk/default/props.conf` (full: `KV_MODE=auto`, CIM aliases, lookups).
- Legacy sourcetype `odin:discovery` — Backward-compat stanza in `ODIN_app_for_splunk/default/props.conf` with custom `EXTRACT-odin_fields` regex.

## Configuration

**Environment:**
- Shared context passed to modules via exported `ODIN_*` variables set in `TA-ODIN/bin/odin.sh`:
  - `ODIN_VERSION` (currently `2.1.0` in orchestrator constant; app.conf is `2.2.0`)
  - `ODIN_HOSTNAME` (`hostname -f` fallback to `hostname`)
  - `ODIN_OS` (hardcoded `linux`)
  - `ODIN_RUN_ID` (`<epoch>-<PID>`)
  - `ODIN_MAX_EVENTS` (default `50000`)
  - `ODIN_EVENT_COUNT`, `ODIN_EVENTS_TRUNCATED` (per-module counters)
  - `ODIN_RUNNING_AS_ROOT` (set by orchestrator based on `$EUID`)
- `LC_ALL=C` forced in every script for deterministic parsing across locales.
- No `.env` file; no external secrets required. No credentials of any kind stored in the repo.

**Build:**
- No build config files. Splunk app structure is the packaging format.

**Key Splunk config files:**

*TA-ODIN (forwarder app):*
- `TA-ODIN/default/app.conf` — App metadata, version `2.2.0`, `is_visible = false`.
- `TA-ODIN/default/inputs.conf` — Scripted inputs: `[script://./bin/odin.sh]` and `[script://.\bin\odin.ps1]`, both at `interval = 2592000` (30 days), `timeout = 120`, `index = odin_discovery`, `sourcetype = odin:enumeration`.
- `TA-ODIN/default/props.conf` — Minimal parse-time only: `SHOULD_LINEMERGE = false`, `LINE_BREAKER = ([\r\n]+)`, `TIME_PREFIX = timestamp=`, `TIME_FORMAT = %Y-%m-%dT%H:%M:%SZ`, `TRUNCATE = 10000`.

*ODIN_app_for_splunk (indexer/SH app):*
- `ODIN_app_for_splunk/default/app.conf` — App metadata, version `2.2.0`, `is_visible = true`, label "ODIN Endpoint Visibility".
- `ODIN_app_for_splunk/default/indexes.conf` — Defines `[odin_discovery]` index with `$SPLUNK_DB` paths, 1-year retention, 1 GB cap.
- `ODIN_app_for_splunk/default/props.conf` — Full search-time config: `KV_MODE = auto`, CIM aliases, three `LOOKUP-*` bindings (services, ports, packages), legacy `odin:discovery` stanza.
- `ODIN_app_for_splunk/default/transforms.conf` — Five lookup definitions: `odin_classify_services` (WILDCARD), `odin_classify_ports`, `odin_classify_packages` (WILDCARD), `odin_log_sources`, `odin_recommended_tas`. All `case_sensitive_match = false`.
- `ODIN_app_for_splunk/default/savedsearches.conf` — Three scheduled searches (cron `5 1 * * *`, `10 1 * * *`, `15 1 * * *`) that produce `odin_host_inventory.csv`, `odin_log_source_details.csv`, and a TA deployment matrix.
- `ODIN_app_for_splunk/metadata/default.meta` — Exports `lookups`, `props`, `transforms`, `savedsearches`, `views` to `system` scope so they apply globally.
- `ODIN_app_for_splunk/default/data/ui/nav/default.xml` — App navigation.
- `ODIN_app_for_splunk/default/data/ui/views/odin_overview.xml` — Dashboard Studio view "ODIN Host Classification".

**Lookup CSVs (data, not config):**
- `ODIN_app_for_splunk/lookups/odin_classify_services.csv` — `service_pattern,category,subcategory,vendor,role,description`
- `ODIN_app_for_splunk/lookups/odin_classify_ports.csv` — `port,transport,expected_service,category,description`
- `ODIN_app_for_splunk/lookups/odin_classify_packages.csv` — `package_pattern,category,vendor,role,description`
- `ODIN_app_for_splunk/lookups/odin_log_sources.csv` — `signal_type,signal_value,host_role,log_source,sourcetype,recommended_ta,log_path,description,daily_volume_low_mb,daily_volume_high_mb`
- `ODIN_app_for_splunk/lookups/odin_recommended_tas.csv` — `recommended_ta,splunkbase_id,splunkbase_url,official_name,status,github_url,notes`

## Platform Requirements

**Development:**
- macOS / Linux with Bash 4+ for local module testing.
- Python 3 with pytest for running the tooling test suite under `tools/tests/`.
- Git.
- A Splunk instance (Enterprise or UF) for end-to-end validation — not required for script-level testing (modules run standalone via `ODIN_*` env vars).

**Production:**
- *Forwarders:* Splunk Universal Forwarder on Linux endpoints. Bash required. Root is recommended for full visibility (ports `process_name`/`pid`, user crontabs in `/var/spool/cron/`).
- *Indexers:* Splunk Enterprise with sufficient storage for `odin_discovery` index (1 GB default cap, 1-year retention).
- *Search Heads:* Splunk Enterprise with `ODIN_app_for_splunk` installed for lookup enrichment and scheduled saved searches.
- Deployment Server for distributing `TA-ODIN` to UF fleet (Phase 3 target also uses Deployment Server for auto-generated serverclasses).

---

*Stack analysis: 2026-04-10*
