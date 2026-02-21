# CLAUDE.md - TA-ODIN Project Guide

## Project Vision

TA-ODIN aims to provide **complete endpoint visibility** for Splunk environments. The long-term goal is a fully automated pipeline:

1. **Enumerate** - Discover everything running on every host (services, ports, packages, cron, processes, mounts)
2. **Classify** - Map raw enumeration data to host roles using Splunk lookup tables
3. **Automate** - Generate Deployment Server serverclasses and app assignments based on classification data

This eliminates reliance on incomplete CMDB data and enables data-driven Splunk onboarding.

## Project Overview

TA-ODIN (Organized Discovery and Identification of eNdpoints) is a Splunk Technology Add-on that performs full enumeration of endpoints. It deploys via Splunk Deployment Server to Universal Forwarders, enumerates all services, listening ports, installed packages, scheduled tasks, running processes, and filesystem mounts - reporting metadata only, never actual log content.

Named after the Norse god Odin and his ravens Hugin and Munin who reported back everything they observed.

## Deployment Architecture (Two Apps)

The project consists of **two separate Splunk apps** with different deployment targets:

### TA-ODIN (Forwarder App - Collection)
- **Deployed to**: Universal Forwarders via Deployment Server (`deployment_apps/`)
- **Purpose**: Runs enumeration scripts on endpoints, collects and forwards data
- **Contains**: Orchestrator, modules, inputs.conf, props.conf (line-breaking only)
- **Does NOT contain**: indexes.conf, transforms.conf, lookups, dashboards, savedsearches.conf

### ODIN_app_for_splunk (Search Head / Indexer App - Visibility & Reporting)
- **Deployed to**: Indexers and Search Heads (installed directly or via Cluster Manager)
- **Purpose**: Index definition, classification lookups, search-time enrichment, host role classification
- **Contains**:
  - `indexes.conf` — odin_discovery index definition (indexers)
  - `props.conf` + `transforms.conf` — full parsing, KV_MODE, CIM aliases, lookup bindings (search heads)
  - `lookups/` — classification CSV files + log source mapping (search heads)
  - `savedsearches.conf` — host inventory, log source details, TA deployment matrix (search heads)
  - `metadata/default.meta` — exports lookups/props/transforms/savedsearches to system scope

**Important**: `indexes.conf` must NEVER be deployed to forwarders. It belongs in ODIN_app_for_splunk only.

## Repository Structure

```
odin/
├── CLAUDE.md                             # Project guide (this file)
├── DOCS/
│   ├── CHANGEHISTORY.md                  # Change history with CET timestamps
│   ├── ARCHITECTURE.md                   # ASCII architecture diagrams and file reference
│   └── COMMANDS.md                       # Command reference (root vs non-root, risks)
├── TA-ODIN/                              # FORWARDER APP (deploy to UFs via deployment_apps/)
│   ├── bin/
│   │   ├── odin.sh                       # Orchestrator script (per-module timeout, MAX_EVENTS)
│   │   ├── odin.ps1                      # Windows orchestrator (placeholder/TODO)
│   │   └── modules/                      # Discovery modules (auto-loaded by odin.sh)
│   │       ├── services.sh               # Service enumeration (batch systemctl)
│   │       ├── ports.sh                  # Listening port enumeration
│   │       ├── packages.sh               # Package enumeration
│   │       ├── cron.sh                   # Scheduled task enumeration (batch timers)
│   │       ├── processes.sh              # Process enumeration (single ps call)
│   │       └── mounts.sh                 # Filesystem mount enumeration
│   ├── default/
│   │   ├── app.conf                      # App metadata, version 2.2.0
│   │   ├── inputs.conf                   # Scripted inputs (30-day interval, 120s timeout)
│   │   └── props.conf                    # Line-breaking and timestamp only (forwarder)
│   ├── local/                            # Customer overrides (empty by default)
│   ├── static/                           # Empty
│   └── README.md                         # User documentation
└── ODIN_app_for_splunk/                  # INDEXER/SEARCH HEAD APP
    ├── default/
    │   ├── app.conf                      # App metadata, version 2.2.0
    │   ├── indexes.conf                  # odin_discovery index definition
    │   ├── props.conf                    # Full parsing + search-time lookups + CIM aliases
    │   ├── savedsearches.conf            # Host classification and TA deployment searches
    │   └── transforms.conf               # Classification lookup transforms
    ├── lookups/
    │   ├── odin_classify_services.csv    # Service-to-role classification
    │   ├── odin_classify_ports.csv       # Port-to-service classification
    │   ├── odin_classify_packages.csv    # Package-to-role classification
    │   └── odin_log_sources.csv          # Signal → host role / log source / TA mapping
    ├── metadata/
    │   └── default.meta                  # Permissions and export scope
    └── README.md                         # User documentation
```

## Key Technical Details

### Architecture (v2.1)

**Orchestrator** (`odin.sh`):
- Thin wrapper that autodiscovers and runs all `bin/modules/*.sh` files
- Sets shared context via `ODIN_*` environment variables
- Generates unique `run_id` per execution (epoch-PID)
- Emits start-event, runs all modules, emits completion-event with summary
- Never aborts on module failure - captures exit codes and continues
- **Per-module timeout**: 90 seconds (leaves 30s margin within Splunk's 120s input timeout)
- **MAX_EVENTS cap**: 50,000 events per module to prevent output flooding

**Modules** (`bin/modules/*.sh`):
- Each module is self-contained and can run independently
- Receives context via `ODIN_*` environment variables
- Uses shared `emit()` function pattern for consistent output (with MAX_EVENTS guardrail)
- All external commands wrapped with `timeout` to prevent hangs
- Batch systemctl queries in services.sh and cron.sh (no per-unit subprocess spawning)
- Modules: services, ports, packages, cron, processes, mounts

**Classification Lookups** (`ODIN_app_for_splunk/lookups/`):
- CSV files used by Splunk at search time to enrich raw enumeration data
- Maps service names, ports, and packages to categories and host roles
- Replaces v1.0's detection-rule approach - no longer limits discovery to known items

### Output Format (v2.0+)
- Space-separated key=value pairs (changed from comma-separated in v1)
- All events include: `timestamp=`, `hostname=`, `os=`, `run_id=`, `type=`
- String values with spaces are double-quoted
- Empty fields are omitted

### Environment Variables
| Variable | Description |
|----------|-------------|
| `ODIN_HOSTNAME` | Fully qualified hostname |
| `ODIN_OS` | Operating system (e.g., `linux`) |
| `ODIN_RUN_ID` | Unique run identifier (epoch-PID) |
| `ODIN_VERSION` | TA-ODIN version string |
| `ODIN_MAX_EVENTS` | Max events per module (default 50,000) |
| `ODIN_EVENT_COUNT` | Current event count (reset per module) |

### Script Guardrails
| Guardrail | Value | Purpose |
|-----------|-------|---------|
| Per-module timeout | 90s | Prevents any single module from exceeding Splunk's 120s input timeout |
| MAX_EVENTS per module | 50,000 | Prevents hosts with 100K+ packages/processes from flooding Splunk |
| Command timeouts | 5-30s | Prevents hangs on broken systemctl units, dpkg locks, hung NFS mounts |
| Batch systemctl | 1 call | Replaces 2N per-unit subprocess calls in services.sh and cron.sh |

### Splunk Configuration
- Index: `odin_discovery`
- Sourcetype: `odin:enumeration`
- Default scan interval: 2592000 seconds (30 days)
- Script timeout: 120 seconds
- Default retention: 1 year (31536000 seconds)
- Search-time lookups for automatic classification enrichment (ODIN_app_for_splunk)
- CIM aliases: hostname -> dest, hostname -> dvc (ODIN_app_for_splunk)

**Config split between apps:**
| Config | TA-ODIN (Forwarders) | ODIN_app_for_splunk (Indexers/SH) |
|--------|---------------------|-----------------------------------|
| `inputs.conf` | Scripted input | - |
| `props.conf` | Line-breaking, timestamp | Full parsing, KV_MODE, CIM aliases, lookups |
| `transforms.conf` | - | Lookup definitions |
| `indexes.conf` | - | Index definition |
| `lookups/` | - | Classification CSVs + log source mapping |
| `savedsearches.conf` | - | Host classification and TA deployment |

## Development Status

- **TA-ODIN (forwarder app)**: Complete (v2.2.0 - guardrails, batch queries, two-app split)
- **ODIN_app_for_splunk (indexer/SH app)**: Complete (v2.2.0 - index, lookups, props, transforms, saved searches)
- **Linux enumeration**: Complete (6 modules: services, ports, packages, cron, processes, mounts)
- **Windows enumeration**: Not implemented (odin.ps1 is a placeholder)
- **Classification lookups**: Implemented for services, ports, and packages (in ODIN_app_for_splunk)
- **Phase 2 - Host role classification**: Complete (v2.2.0 - odin_log_sources.csv, 3 saved searches, host inventory)
- **Dashboards**: Not started (will live in ODIN_app_for_splunk)
- **Phase 3 planned**: Deployment Server integration - auto-generate serverclasses from classification

## Architecture Decisions (v2.0+)

1. **Full enumeration over rule-based detection**: v1 only found what was defined in CSV rules. v2 enumerates everything and uses lookups for classification at search time.
2. **Modular script architecture**: Each discovery domain is a separate module. Easy to add new modules without touching the orchestrator.
3. **Space-separated key=value format**: Simpler parsing, works with Splunk KV_MODE=auto without custom regex.
4. **Classification at search time**: Lookup tables map raw data to categories/roles. Updates to classification don't require re-scanning hosts.
5. **ODIN_* environment variables**: Modules receive shared context without argument parsing or config file reading.
6. **Two-app split (TA-ODIN + ODIN_app_for_splunk)**: Forwarders only need the collection scripts and minimal parsing. Indexers/search heads need the index definition, lookups, and full search-time config. Follows Splunk best practices for separating collection from knowledge.
7. **Script guardrails**: Per-module timeouts, MAX_EVENTS caps, command-level timeouts, and batch systemctl queries prevent runaway resource consumption on large hosts.
8. **Signal-based host classification (Phase 2)**: A single `odin_log_sources.csv` lookup maps discovery signals to host roles and log sources. Saved searches aggregate per-host, deduplicating multi-signal matches. This avoids complex rule engines — just CSV rows and SPL.

## Conventions

- Discovery modules go in `TA-ODIN/bin/modules/` - the orchestrator auto-discovers them
- Classification mappings go in CSV files under `ODIN_app_for_splunk/lookups/`
- Default config in `default/`, customer overrides in `local/`
- `indexes.conf` belongs in ODIN_app_for_splunk (indexers/SH), NEVER in TA-ODIN (forwarders)
- `inputs.conf` belongs in TA-ODIN (forwarders), NEVER in ODIN_app_for_splunk
- Search-time props/transforms/lookups belong in ODIN_app_for_splunk (search heads)
- Output format is always space-separated key=value pairs with ISO 8601 UTC timestamps
- Script outputs start and completion marker events for each scan
- All change history entries use ISO 8601 CET timestamps

## Common Tasks

### Adding a new discovery module
Create `bin/modules/<name>.sh` following the existing module template. The orchestrator will auto-discover and run it.

### Adding classification mappings
Add rows to the appropriate CSV in `ODIN_app_for_splunk/lookups/`:
- `odin_classify_services.csv` for service-to-role mappings
- `odin_classify_ports.csv` for port-to-service mappings
- `odin_classify_packages.csv` for package-to-role mappings

### Adding log source mappings (Phase 2)
Add rows to `ODIN_app_for_splunk/lookups/odin_log_sources.csv`:
- Each row maps a `(signal_type, signal_value)` pair to a host role, log source, sourcetype, and recommended TA
- `signal_type` is one of: `service`, `port`, `package`
- `signal_value` is the detected value (e.g., `nginx`, `443/tcp`, `mysql-server`)
- Multiple rows can map to the same `host_role` for multi-signal reinforcement

### Testing the orchestrator locally
```bash
cd TA-ODIN && bash bin/odin.sh
```

### Testing a single module
```bash
export ODIN_HOSTNAME=test ODIN_OS=linux ODIN_RUN_ID=test-001 ODIN_VERSION=2.1.0
bash TA-ODIN/bin/modules/services.sh
```

### Verifying events in Splunk
```spl
index=odin_discovery sourcetype=odin:enumeration
| stats count by type
| sort - count
```

### Verifying classification enrichment
```spl
index=odin_discovery sourcetype=odin:enumeration type=service
| lookup odin_classify_services service_name OUTPUT category, role
| stats count by hostname, role
```

### Verifying host role classification (Phase 2)
```spl
index=odin_discovery sourcetype=odin:enumeration (type=service OR type=port OR type=package)
| eval signal_type=type
| eval signal_value=case(type="service", service_name, type="port", listen_port."/".transport, type="package", package_name)
| lookup odin_log_sources signal_type, signal_value
| where isnotnull(host_role)
| stats values(host_role) AS host_roles by hostname
```

### Viewing the host inventory
```spl
| inputlookup odin_host_inventory.csv
```

### Viewing TA deployment recommendations
```spl
| inputlookup odin_host_inventory.csv
| makemv delim="," recommended_tas
| mvexpand recommended_tas
| stats values(hostname) AS hosts, dc(hostname) AS host_count by recommended_tas
| sort - host_count
```

## Remote
- GitHub: `https://github.com/lyderhansen/odin.git`
- Branch: `main`
