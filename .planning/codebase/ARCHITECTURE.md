# Architecture

**Analysis Date:** 2026-04-10

## Pattern Overview

**Overall:** Two-app Splunk TA split — collection vs. knowledge. A thin bash orchestrator (`TA-ODIN/bin/odin.sh`) auto-discovers and runs discovery modules on endpoints, emitting space-separated `key=value` events to stdout. A Universal Forwarder ships those events to Splunk, where the companion app (`ODIN_app_for_splunk/`) defines the index, parses events, enriches them via classification lookups at search time, and aggregates per-host signals into role-based host inventory via saved searches.

**Key Characteristics:**
- **Two deployable apps, different targets.** `TA-ODIN/` ships to Universal Forwarders via Deployment Server. `ODIN_app_for_splunk/` ships to indexers (for `indexes.conf`) and search heads (for lookups, props, transforms, saved searches). No collection logic on the search side, no knowledge objects on the forwarder side.
- **Modular enumerator with zero-config auto-discovery.** The orchestrator globs `bin/modules/*.sh` — dropping in a new `.sh` file is sufficient to add a discovery domain. No registry, no config file.
- **Full enumeration, not rule-based detection.** Modules report everything they find (services, ports, packages, cron, processes, mounts). Classification and role assignment happen at search time in Splunk via CSV lookups. This decouples collection frequency (30 days) from knowledge updates (seconds to edit a CSV).
- **Metadata only, never log content.** Modules never read log files or transmit data payloads; they only enumerate "what exists" on the host.
- **Signal-based host classification over rule engines.** A single lookup (`odin_log_sources.csv`) maps `(signal_type, signal_value)` pairs to host roles and recommended TAs. SPL aggregates multi-signal matches per host.
- **Fail-soft orchestration.** Module failures never abort the run. The orchestrator captures exit codes, emits `odin_error` events, and continues to the next module.

## Layers

**Collection Layer (Endpoint / Universal Forwarder):**
- Purpose: Enumerate host state and emit structured events.
- Location: `TA-ODIN/`
- Contains:
  - Orchestrator: `TA-ODIN/bin/odin.sh`
  - Windows stub: `TA-ODIN/bin/odin.ps1` (placeholder, not implemented)
  - Discovery modules: `TA-ODIN/bin/modules/{services,ports,packages,cron,processes,mounts}.sh`
  - Scripted input definition: `TA-ODIN/default/inputs.conf`
  - Minimal forwarder parsing: `TA-ODIN/default/props.conf` (line-breaking + timestamp only)
- Depends on: bash, coreutils (`timeout`, `date`, `hostname`), per-module tools (`systemctl`, `ss`/`netstat`, `dpkg`/`rpm`, `ps`, `mount`).
- Used by: Splunk Universal Forwarder (via scripted input), which reads stdout and forwards to indexers.

**Transport Layer (Universal Forwarder):**
- Purpose: Receive stdout from the scripted input, apply line-breaking from forwarder-side `props.conf`, and forward to indexers.
- Configured by: `TA-ODIN/default/inputs.conf` (scripted input, 30-day interval, 120s timeout) and `TA-ODIN/default/props.conf` (line-breaking only — no KV_MODE, no lookups on forwarders).

**Indexing Layer (Indexers):**
- Purpose: Persist events to the `odin_discovery` index with full parsing and key=value field extraction.
- Location: `ODIN_app_for_splunk/default/indexes.conf` (index definition, 1-year retention, 1024 MB cap)
- Location: `ODIN_app_for_splunk/default/props.conf` (full parsing: `KV_MODE = auto`, CIM field aliases, search-time lookup bindings)
- Depends on: transforms and lookups.
- Used by: search heads at search time.

**Knowledge Layer (Search Heads):**
- Purpose: Enrich raw enumeration events at search time and aggregate per-host signals into role assignments.
- Location: `ODIN_app_for_splunk/default/transforms.conf` (lookup definitions, including `WILDCARD` match types)
- Location: `ODIN_app_for_splunk/lookups/odin_classify_services.csv`, `odin_classify_ports.csv`, `odin_classify_packages.csv` — per-signal classification (category, vendor, role).
- Location: `ODIN_app_for_splunk/lookups/odin_log_sources.csv` — signal-to-role-to-log-source-to-TA mapping (Phase 2).
- Location: `ODIN_app_for_splunk/lookups/odin_recommended_tas.csv` — TA metadata (Splunkbase ID, URL, status).
- Used by: saved searches and dashboards.

**Reporting Layer (Search Heads):**
- Purpose: Produce scheduled aggregates (host inventory, log source details, TA deployment matrix).
- Location: `ODIN_app_for_splunk/default/savedsearches.conf`
  - `ODIN - Host Inventory` — nightly 01:05 cron, outputs `odin_host_inventory.csv`.
  - `ODIN - Log Source Details` — nightly 01:10 cron, outputs `odin_log_source_details.csv`.
  - `ODIN - TA Deployment Matrix` — nightly 01:15 cron, joins inventory with recommended-TA metadata.
- Export scope: all lookups/props/transforms/savedsearches exported to `system` via `ODIN_app_for_splunk/metadata/default.meta`.

## Data Flow

**End-to-end pipeline: endpoint to host inventory**

1. **Splunk UF triggers the scripted input.** Every 2,592,000 seconds (30 days), the UF executes `./bin/odin.sh` as defined in `TA-ODIN/default/inputs.conf`, with a 120-second hard timeout.
2. **Orchestrator bootstraps shared context.** `TA-ODIN/bin/odin.sh` sets `LC_ALL=C`, exports `ODIN_VERSION`, `ODIN_HOSTNAME` (via `hostname -f`), `ODIN_OS=linux`, and generates `ODIN_RUN_ID="$(date +%s)-$$"` (epoch-PID) — unique per execution. It also exports `ODIN_MAX_EVENTS=50000` and `ODIN_EVENT_COUNT=0`.
3. **Start event emitted.** The orchestrator calls `emit "type=odin_start run_as=$run_user euid=$EUID ..."`. Every event line includes `timestamp=`, `hostname=`, `os=`, `run_id=`, `odin_version=`. If running non-root, warning events are emitted for `ports` and `cron` modules (which yield degraded data as non-root).
4. **Modules auto-discovered and run serially.** The orchestrator loops `for module in "$MODULES_DIR"/*.sh`, resets `ODIN_EVENT_COUNT=0` per module, and executes each under `timeout 90` (if `timeout` is available). Modules: `services.sh`, `ports.sh`, `packages.sh`, `cron.sh`, `processes.sh`, `mounts.sh`. Exit code 124 → timeout → emit `odin_error` with `message="Module X timed out after 90s"`. Any non-zero exit → emit `odin_error` with the exit code. The orchestrator never aborts; failed modules increment `module_fail` and the loop continues.
5. **Modules emit events via shared `emit()`.** Each module inherits the exported `emit` bash function from the orchestrator. `emit()` enforces `ODIN_MAX_EVENTS` — once exceeded, it emits a single `type=truncated` marker and silently drops the rest for that module. Modules define a fallback `emit` for standalone execution (e.g., `bash TA-ODIN/bin/modules/services.sh` with `ODIN_*` env vars manually set — see `services.sh` lines 19–26).
6. **Completion event emitted.** The orchestrator emits `type=odin_complete modules_total=N modules_success=N modules_failed=N`. Exit non-zero if any module failed.
7. **Universal Forwarder captures stdout.** The UF reads each line as an event. `TA-ODIN/default/props.conf` applies line-breaking (`LINE_BREAKER = ([\r\n]+)`, `SHOULD_LINEMERGE = false`) and timestamp extraction (`TIME_PREFIX = timestamp=`, `TIME_FORMAT = %Y-%m-%dT%H:%M:%SZ`). No field extraction on the forwarder.
8. **Forwarder ships to indexer(s).** Events route to the `odin_discovery` index with sourcetype `odin:enumeration`.
9. **Indexer parses with full props.** `ODIN_app_for_splunk/default/props.conf` applies `KV_MODE = auto` (automatic space-separated key=value extraction), CIM aliases (`hostname AS dest`, `hostname AS dvc`), and binds three search-time lookups:
   - `LOOKUP-classify_services` → `odin_classify_services` (WILDCARD on `service_pattern`)
   - `LOOKUP-classify_ports` → `odin_classify_ports` (exact match on `port` + `transport`)
   - `LOOKUP-classify_packages` → `odin_classify_packages` (WILDCARD on `package_pattern`)
10. **Search-time enrichment on every search.** Raw events get enriched with `service_category`, `service_role`, `port_category`, `package_vendor`, etc. without re-scanning hosts.
11. **Nightly saved searches aggregate per host.** `ODIN - Host Inventory` (01:05), `ODIN - Log Source Details` (01:10), `ODIN - TA Deployment Matrix` (01:15) run over `-45d` to `now`:
    - Normalize `type` → `signal_type`, derive `signal_value` via `case(type="service", service_name, type="port", listen_port."/".transport, type="package", package_name)`.
    - Deduplicate `(hostname, signal_type, signal_value)` so a role triggered by three signals counts once.
    - Join against `odin_log_sources.csv` to map signal → `host_role` / `log_source` / `recommended_ta`.
    - `| stats values(host_role) values(log_source) values(recommended_ta) ... by hostname` — a host with both `mysql` service AND `mysql-server` package gets the `database_mysql` role once.
    - `| outputlookup odin_host_inventory.csv` — persisted for dashboards and the `ODIN - TA Deployment Matrix` downstream search.
12. **TA Deployment Matrix joins inventory with TA metadata.** The matrix search reads `odin_host_inventory.csv`, explodes `recommended_tas`, groups by TA, and joins `odin_recommended_tas.csv` for Splunkbase IDs/URLs/status. The output drives deployment planning.

**State Management:**
- **Ephemeral per run:** `ODIN_RUN_ID`, `ODIN_EVENT_COUNT`, `ODIN_EVENTS_TRUNCATED` — live only for the duration of `odin.sh`.
- **Persistent in Splunk:** events in `odin_discovery` index (1-year retention), host inventory lookup `odin_host_inventory.csv`, log source details lookup `odin_log_source_details.csv` (regenerated nightly).
- **Static knowledge:** classification CSVs in `ODIN_app_for_splunk/lookups/` — edited manually, picked up on next search.

## Key Abstractions

**Discovery Module:**
- Purpose: Self-contained enumerator for a single discovery domain.
- Examples: `TA-ODIN/bin/modules/services.sh`, `TA-ODIN/bin/modules/ports.sh`, `TA-ODIN/bin/modules/packages.sh`, `TA-ODIN/bin/modules/cron.sh`, `TA-ODIN/bin/modules/processes.sh`, `TA-ODIN/bin/modules/mounts.sh`
- Pattern: Receives context via exported `ODIN_*` environment variables, uses the inherited `emit()` function, wraps all external commands with `timeout`, defines a standalone-mode fallback `emit()` for testing, and always exits 0 unless it cannot start at all. Modules emit `type=none_found` if nothing is discovered.

**Orchestrator:**
- Purpose: Thin auto-discovery wrapper that sets shared context and runs modules with guardrails.
- Location: `TA-ODIN/bin/odin.sh`
- Pattern: Glob-based module discovery (`for module in "$MODULES_DIR"/*.sh`), per-module `timeout 90`, per-module event counter reset, bracketed by `odin_start` / `odin_complete` marker events.

**Shared `emit()` function:**
- Purpose: Uniform event output with `MAX_EVENTS` guardrail.
- Location: `TA-ODIN/bin/odin.sh` lines 51–66, exported via `export -f emit`.
- Pattern: Every line prefixed with `timestamp= hostname= os= run_id= odin_version=`, then module-specific fields. Once `ODIN_EVENT_COUNT >= ODIN_MAX_EVENTS`, emits a single `type=truncated` marker and suppresses the rest.

**Classification Lookup:**
- Purpose: Search-time mapping from raw enumeration signal to category/role/vendor.
- Examples: `ODIN_app_for_splunk/lookups/odin_classify_services.csv`, `odin_classify_ports.csv`, `odin_classify_packages.csv`
- Pattern: CSV file + `transforms.conf` stanza with optional `WILDCARD` match type, bound to the sourcetype via `LOOKUP-*` in `props.conf`. Updating a CSV takes effect immediately without re-indexing.

**Log Source Mapping (Phase 2):**
- Purpose: Single lookup table that maps `(signal_type, signal_value)` to `host_role`, `log_source`, `sourcetype`, `log_path`, and `recommended_ta`.
- Location: `ODIN_app_for_splunk/lookups/odin_log_sources.csv`
- Pattern: A host is classified as a given role if any one of its signals matches. Multi-signal matches are deduplicated via `| stats values(host_role) ... by hostname`.

**Host Inventory Lookup (output):**
- Purpose: Pre-aggregated per-host role and TA assignments for dashboards and the deployment matrix.
- Location: `odin_host_inventory.csv` (generated nightly by the `ODIN - Host Inventory` saved search).
- Pattern: Materialized view regenerated from 45 days of enumeration events.

## Entry Points

**Scripted input (Linux):**
- Location: `TA-ODIN/default/inputs.conf` stanza `[script://./bin/odin.sh]`
- Triggers: Splunk UF scheduler, every 2,592,000 seconds (30 days), 120-second hard timeout.
- Responsibilities: Launch the orchestrator, capture stdout as events, tag with `index=odin_discovery` and `sourcetype=odin:enumeration`.

**Scripted input (Windows, placeholder):**
- Location: `TA-ODIN/default/inputs.conf` stanza `[script://.\bin\odin.ps1]`
- Triggers: Same schedule as Linux.
- Responsibilities: Currently emits a single "not yet implemented" marker event. Full Windows enumeration is a future phase.

**Manual module execution (testing):**
- Location: any `TA-ODIN/bin/modules/*.sh`
- Triggers: `bash TA-ODIN/bin/modules/services.sh` with `ODIN_HOSTNAME`, `ODIN_OS`, `ODIN_RUN_ID`, `ODIN_VERSION` set manually.
- Responsibilities: Modules fall back to a standalone `emit()` definition if the orchestrator function isn't exported (see `services.sh` lines 19–26).

**Scheduled saved searches:**
- Location: `ODIN_app_for_splunk/default/savedsearches.conf`
- Triggers: Splunk search head scheduler — `5 1 * * *` (Host Inventory), `10 1 * * *` (Log Source Details), `15 1 * * *` (TA Deployment Matrix).
- Responsibilities: Regenerate host inventory and deployment lookups nightly.

## Error Handling

**Strategy:** Fail-soft at every layer. Collection never blocks on a single broken command; search-time enrichment degrades gracefully when signals are unclassified.

**Patterns:**
- **Module-level:** Every external command wrapped in `timeout N` (5s for init.d status checks, 30s for `systemctl show`, up to 90s per module wall-clock). Exit code 124 triggers an `odin_error` event with `message="Module X timed out after 90s"`.
- **Orchestrator-level:** Module failures are logged via `emit "type=odin_error module=..."` but never abort the run. Final `odin_complete` event reports `modules_failed=N`. Orchestrator exits non-zero only if at least one module failed (signals Splunk that something went wrong, without preventing the rest of the data from being ingested).
- **Bash availability check:** `odin.sh` lines 16–19 detect missing bash and emit a single `odin_error` event before exiting 1 — so even a total failure produces at least one Splunk event.
- **Event-flood guardrail:** `ODIN_MAX_EVENTS=50000` per module. On hosts with 100K+ packages/processes, the first 50K are emitted, then a `type=truncated` marker, then silence.
- **Search-time graceful degradation:** Unclassified signals produce events with null `service_category`, `host_role`, etc. Saved searches use `| where isnotnull(host_role)` so they only aggregate matched signals — unclassified signals aren't errors, they're just "unknown" and don't pollute the inventory.
- **Privilege degradation:** Non-root runs emit `odin_warning` events up front for the modules that yield partial data (`ports`, `cron`), so the consumer knows the data is incomplete rather than absent.

## Cross-Cutting Concerns

**Logging:**
- Collection: stdout only — every event line IS a log line. No separate log file. `odin_error`, `odin_warning`, `odin_start`, `odin_complete`, `truncated`, and `none_found` event types carry diagnostic information alongside the enumeration data.
- Search: standard Splunk internal logs for saved-search execution.

**Validation:**
- `safe_val()` helper in each module escapes embedded double-quotes and wraps values containing spaces in quotes (see `TA-ODIN/bin/modules/services.sh` lines 29–37).
- `LC_ALL=C` forced at both orchestrator and module entry points for deterministic command output parsing across locales.
- Search-time `KV_MODE = auto` in `ODIN_app_for_splunk/default/props.conf` relies on the strict space-separated `key=value` format the modules produce.

**Authentication / Privilege:**
- Scripts run as whatever user the Splunk UF runs as (typically root on Linux, which is recommended). `ODIN_RUNNING_AS_ROOT` is tracked in `odin.sh` lines 73–76 and surfaces via `odin_warning` events when privileges are insufficient.
- No credentials, no secrets — the scripts never authenticate to anything.

**Versioning:**
- Single `ODIN_VERSION="2.1.0"` constant in `TA-ODIN/bin/odin.sh` line 30 (note: lags the app.conf `version = 2.2.0` — the script header and env var are the authoritative runtime version string embedded in every event). App metadata in `TA-ODIN/default/app.conf` and `ODIN_app_for_splunk/default/app.conf` both report `version = 2.2.0`.

## Phase Roadmap

**Phase 1 (Complete) — Enumeration:**
- Six Linux discovery modules, orchestrator with guardrails, forwarder app, indexer/SH app, classification lookups, CIM aliases.

**Phase 2 (Complete) — Host Role Classification:**
- `odin_log_sources.csv` signal-to-role mapping lookup.
- Three saved searches: `ODIN - Host Inventory`, `ODIN - Log Source Details`, `ODIN - TA Deployment Matrix`.
- Output lookups: `odin_host_inventory.csv`, `odin_log_source_details.csv`.

**Phase 3 (Planned) — Deployment Server Automation:**
- Auto-generate Splunk Deployment Server serverclasses from `odin_host_inventory.csv`.
- Map `recommended_tas` per host into `serverclass.conf` app assignments.
- Close the loop: enumeration → classification → automatic TA deployment, eliminating CMDB dependency.

**Future — Windows Enumeration:**
- `TA-ODIN/bin/odin.ps1` is currently a placeholder. A full Windows implementation will mirror the Linux module pattern with equivalents for services (Get-Service), ports (Get-NetTCPConnection), packages (Get-Package/registry), scheduled tasks (Get-ScheduledTask), processes (Get-Process), and mounts (Get-Volume).

**Future — Dashboards:**
- Will live in `ODIN_app_for_splunk/default/data/ui/views/` (the directory already exists with a stub `odin_overview.xml`). Dashboards will consume `odin_host_inventory.csv` and `odin_log_source_details.csv`.

---

*Architecture analysis: 2026-04-10*
