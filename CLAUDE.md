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
- **Contains**: Orchestrator, modules, inputs.conf, props.conf (parsing), transforms.conf
- **Does NOT contain**: indexes.conf, dashboards, saved searches, reports

### ODIN (Search Head / Indexer App - Visualization & Reporting) — TODO
- **Deployed to**: Indexers and Search Heads (installed directly or via Cluster Manager)
- **Purpose**: Index definition, dashboards, reports, saved searches, classification lookups
- **Should contain**:
  - `indexes.conf` — odin_discovery index definition (indexers)
  - `props.conf` + `transforms.conf` — search-time lookup definitions (search heads)
  - `lookups/` — classification CSV files (search heads)
  - `default/data/ui/views/` — dashboards for visualizing enumeration data (search heads)
  - `default/savedsearches.conf` — scheduled reports and alerts (search heads)
  - `metadata/` — permissions and export settings

**Important**: `indexes.conf` must NEVER be deployed to forwarders. It belongs in the indexer/search head app only.

## Repository Structure

```
odin/
├── CLAUDE.md                             # Project guide (this file)
├── DOCS/
│   ├── CHANGEHISTORY.md                  # Change history with CET timestamps
│   └── ARCHITECTURE.md                   # ASCII architecture diagrams and file reference
├── TA-ODIN/                              # FORWARDER APP (deploy to UFs via deployment_apps/)
│   ├── bin/
│   │   ├── odin.sh                       # Orchestrator script (autodiscovers modules)
│   │   ├── odin.ps1                      # Windows orchestrator (placeholder/TODO)
│   │   └── modules/                      # Discovery modules (auto-loaded by odin.sh)
│   │       ├── services.sh               # Service enumeration
│   │       ├── ports.sh                  # Listening port enumeration
│   │       ├── packages.sh               # Package enumeration
│   │       ├── cron.sh                   # Scheduled task enumeration
│   │       ├── processes.sh              # Process enumeration
│   │       └── mounts.sh                 # Filesystem mount enumeration
│   ├── default/
│   │   ├── app.conf                      # App metadata, version 2.0.1
│   │   ├── inputs.conf                   # Scripted inputs (30-day interval, 120s timeout)
│   │   └── props.conf                    # Event line-breaking and timestamp parsing
│   ├── local/                            # Customer overrides (empty by default)
│   ├── static/                           # Empty
│   └── README.md                         # User documentation
└── ODIN/                                 # INDEXER/SEARCH HEAD APP (TODO)
    ├── default/
    │   ├── app.conf                      # App metadata
    │   ├── indexes.conf                  # odin_discovery index definition
    │   ├── props.conf                    # Search-time field extractions
    │   ├── transforms.conf               # Classification lookup transforms
    │   ├── savedsearches.conf            # Reports and scheduled searches
    │   └── data/ui/views/                # Dashboards
    ├── lookups/
    │   ├── odin_classify_services.csv    # Service-to-role classification
    │   ├── odin_classify_ports.csv       # Port-to-service classification
    │   └── odin_classify_packages.csv    # Package-to-role classification
    ├── metadata/
    │   └── default.meta                  # Permissions and export scope
    └── README.md                         # User documentation
```

## Key Technical Details

### Architecture (v2.0)

**Orchestrator** (`odin.sh`):
- Thin wrapper that autodiscovers and runs all `bin/modules/*.sh` files
- Sets shared context via `ODIN_*` environment variables
- Generates unique `run_id` per execution (epoch-PID)
- Emits start-event, runs all modules, emits completion-event with summary
- Never aborts on module failure - captures exit codes and continues

**Modules** (`bin/modules/*.sh`):
- Each module is self-contained and can run independently
- Receives context via `ODIN_*` environment variables
- Uses shared `emit()` function pattern for consistent output
- Modules: services, ports, packages, cron, processes, mounts

**Classification Lookups** (`lookups/`):
- CSV files used by Splunk at search time to enrich raw enumeration data
- Maps service names, ports, and packages to categories and host roles
- Replaces v1.0's detection-rule approach - no longer limits discovery to known items

### Output Format (v2.0)
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

### Splunk Configuration
- Index: `odin_discovery`
- Sourcetype: `odin:enumeration`
- Default scan interval: 2592000 seconds (30 days)
- Script timeout: 120 seconds
- Default retention: 1 year (31536000 seconds)
- Search-time lookups for automatic classification enrichment (ODIN app)
- CIM aliases: hostname -> dest, hostname -> dvc (ODIN app)

**Config split between apps:**
| Config | TA-ODIN (Forwarders) | ODIN (Indexers/SH) |
|--------|---------------------|-------------------|
| `inputs.conf` | Scripted input | - |
| `props.conf` | Line-breaking, timestamp | Search-time lookups, KV_MODE |
| `transforms.conf` | - | Lookup definitions |
| `indexes.conf` | - | Index definition |
| `savedsearches.conf` | - | Reports, alerts |
| `lookups/` | - | Classification CSVs |

## Development Status

- **TA-ODIN (forwarder app)**: Complete (v2.0.1 - full Linux enumeration with portability and hardening)
- **ODIN (indexer/SH app)**: Not started - needs to be created with indexes.conf, lookups, dashboards
- **Linux enumeration**: Complete (6 modules: services, ports, packages, cron, processes, mounts)
- **Windows enumeration**: Not implemented (odin.ps1 is a placeholder)
- **Classification lookups**: Implemented for services, ports, and packages (currently in TA-ODIN, needs to move to ODIN app)
- **Dashboards**: Not started (will live in ODIN app)
- **Phase 2 planned**: Host classification, automatic server class assignment via Deployment Server

## Architecture Decisions (v2.0)

1. **Full enumeration over rule-based detection**: v1 only found what was defined in CSV rules. v2 enumerates everything and uses lookups for classification at search time.
2. **Modular script architecture**: Each discovery domain is a separate module. Easy to add new modules without touching the orchestrator.
3. **Space-separated key=value format**: Simpler parsing, works with Splunk KV_MODE=auto without custom regex.
4. **Classification at search time**: Lookup tables map raw data to categories/roles. Updates to classification don't require re-scanning hosts.
5. **ODIN_* environment variables**: Modules receive shared context without argument parsing or config file reading.
6. **Two-app split (TA-ODIN + ODIN)**: Forwarders only need the collection scripts and basic parsing. Indexers/search heads need the index definition, lookups, dashboards, and reports. Keeps forwarder deployments lightweight and follows Splunk best practices for separating collection from knowledge.

## Conventions

- Discovery modules go in `TA-ODIN/bin/modules/` - the orchestrator auto-discovers them
- Classification mappings go in CSV files under `ODIN/lookups/`
- Default config in `default/`, customer overrides in `local/`
- `indexes.conf` belongs in the ODIN app (indexers/SH), NEVER in TA-ODIN (forwarders)
- `inputs.conf` belongs in TA-ODIN (forwarders), NEVER in the ODIN app
- Search-time props/transforms/lookups belong in the ODIN app (search heads)
- Output format is always space-separated key=value pairs with ISO 8601 UTC timestamps
- Script outputs start and completion marker events for each scan
- All change history entries use ISO 8601 CET timestamps

## Common Tasks

### Adding a new discovery module
Create `bin/modules/<name>.sh` following the existing module template. The orchestrator will auto-discover and run it.

### Adding classification mappings
Add rows to the appropriate CSV in `lookups/`:
- `odin_classify_services.csv` for service-to-role mappings
- `odin_classify_ports.csv` for port-to-service mappings
- `odin_classify_packages.csv` for package-to-role mappings

### Testing the orchestrator locally
```bash
cd TA-ODIN && bash bin/odin.sh
```

### Testing a single module
```bash
export ODIN_HOSTNAME=test ODIN_OS=linux ODIN_RUN_ID=test-001 ODIN_VERSION=2.0.0
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

## Remote
- GitHub: `https://github.com/lyderhansen/odin.git`
- Branch: `main`
