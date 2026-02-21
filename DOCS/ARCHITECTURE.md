# ODIN Architecture Overview

Last updated: 2026-02-21

## Deployment Architecture

The project consists of **two separate Splunk apps**:

| App | Deploy to | Purpose |
|-----|-----------|---------|
| **TA-ODIN** | Universal Forwarders (via `deployment_apps/`) | Collection - runs scripts on endpoints |
| **ODIN** | Indexers + Search Heads | Index, lookups, dashboards, reports |

## Project Structure

```
odin/
│
├── CLAUDE.md                                  # Development guide (conventions, tasks, architecture decisions)
│
├── DOCS/
│   ├── ARCHITECTURE.md                        # This file - project overview and file reference
│   └── CHANGEHISTORY.md                       # Change log with CET timestamps
│
├── TA-ODIN/                                   # FORWARDER APP (deploy to UFs via deployment_apps/)
│   │
│   ├── bin/
│   │   ├── odin.sh                            # Linux orchestrator - autodiscovers and runs modules
│   │   ├── odin.ps1                           # [TODO] Windows orchestrator - placeholder stub
│   │   └── modules/                           # Discovery modules (auto-loaded by odin.sh)
│   │       ├── services.sh                    # Service enumeration (systemctl/service/init.d)
│   │       ├── ports.sh                       # Listening port enumeration (ss/netstat)
│   │       ├── packages.sh                    # Installed package enumeration (dpkg/rpm/apk/pacman)
│   │       ├── cron.sh                        # Scheduled task enumeration (cron/systemd timers/anacron)
│   │       ├── processes.sh                   # Running process enumeration (ps)
│   │       └── mounts.sh                      # Filesystem mount enumeration (df)
│   │
│   ├── default/
│   │   ├── app.conf                           # App metadata (v2.0.1)
│   │   ├── inputs.conf                        # Scripted inputs (30-day interval, 120s timeout)
│   │   └── props.conf                         # Event line-breaking and timestamp parsing
│   │
│   ├── local/                                 # Customer overrides (empty by default)
│   ├── static/                                # Empty (reserved for app icons)
│   └── README.md                              # End-user documentation
│
└── ODIN/                                      # INDEXER/SEARCH HEAD APP [TODO]
    │
    ├── default/
    │   ├── app.conf                           # App metadata
    │   ├── indexes.conf                       # odin_discovery index definition
    │   ├── props.conf                         # Search-time KV_MODE, CIM aliases, lookup bindings
    │   ├── transforms.conf                    # Lookup table definitions
    │   ├── savedsearches.conf                 # Reports and scheduled searches
    │   └── data/ui/views/                     # Dashboards
    │
    ├── lookups/
    │   ├── odin_classify_services.csv         # Service name → category/role mapping
    │   ├── odin_classify_ports.csv            # Port → expected service mapping
    │   ├── odin_classify_packages.csv         # Package → category/role mapping
    │   └── odin_rules_windows.csv             # [TODO] Windows classification rules
    │
    ├── metadata/
    │   └── default.meta                       # Permissions and export scope
    │
    └── README.md                              # End-user documentation
```

## Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                  ENDPOINT (Universal Forwarder + TA-ODIN)                │
│                                                                         │
│  Splunk UF runs odin.sh every 30 days (configurable in inputs.conf)     │
│                                                                         │
│  ┌─────────────┐                                                        │
│  │   odin.sh   │  Orchestrator: sets ODIN_* env vars, runs modules      │
│  └──────┬──────┘                                                        │
│         │  autodiscovers bin/modules/*.sh                                │
│         │                                                                │
│         ├──► services.sh   → type=service                               │
│         ├──► ports.sh      → type=port                                  │
│         ├──► packages.sh   → type=package                               │
│         ├──► cron.sh       → type=cron                                  │
│         ├──► processes.sh  → type=process                               │
│         └──► mounts.sh     → type=mount                                 │
│                                                                         │
│  Output: space-separated key=value → stdout → Splunk UF                 │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │ forwards to
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      INDEXER (ODIN app installed)                        │
│                                                                         │
│  index=odin_discovery  sourcetype=odin:enumeration                      │
│  indexes.conf defines odin_discovery with 1-year retention              │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │ searched by
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    SEARCH HEAD (ODIN app installed)                      │
│                                                                         │
│  KV_MODE=auto parses key=value pairs into fields                        │
│  CIM aliases: hostname → dest, hostname → dvc                           │
│                                                                         │
│  Search-time lookups enrich raw data:                                   │
│    service_name  ──► odin_classify_services.csv  ──► category, role     │
│    listen_port   ──► odin_classify_ports.csv     ──► expected_service   │
│    package_name  ──► odin_classify_packages.csv  ──► category, role     │
│                                                                         │
│  Dashboards, reports, and saved searches for visualization              │
└─────────────────────────────────────────────────────────────────────────┘
```

## File Reference

### Orchestrator

| File | Description | Status |
|------|-------------|--------|
| `bin/odin.sh` | Linux orchestrator. Autodiscovers modules, sets ODIN_* env vars, emits start/complete events. Forces LC_ALL=C. Exits non-zero if any module fails. | Complete |
| `bin/odin.ps1` | Windows orchestrator. Currently outputs "not yet implemented". | **TODO** |

### Discovery Modules

All modules follow the same pattern:
- Self-contained and can run standalone or via orchestrator
- Receive context via ODIN_* environment variables
- Use `emit()` for consistent output format
- Emit `type=none_found` if nothing is discovered
- Force LC_ALL=C for locale-safe output parsing
- Use `read -r` for field splitting (no awk)
- Include fallback chains for minimal/BusyBox systems

| Module | Event type | Fields | Fallback chain | Status |
|--------|-----------|--------|----------------|--------|
| `services.sh` | `service` | service_name, service_status, service_enabled, service_type | systemctl → service --status-all → /etc/init.d/ | Complete |
| `ports.sh` | `port` | transport, listen_address, listen_port, process_name, process_pid | ss → netstat | Complete |
| `packages.sh` | `package` | package_name, package_version, package_arch, package_manager | dpkg → rpm → apk → pacman | Complete |
| `cron.sh` | `cron` | cron_source, cron_user, cron_schedule, cron_command, cron_file | /etc/crontab, /etc/cron.d, user crontabs, cron.daily/etc, systemd timers, anacron | Complete |
| `processes.sh` | `process` | process_pid, process_ppid, process_user, process_state, process_cpu, process_mem, process_elapsed, process_name, process_command | GNU ps -eo → BusyBox ps -o → basic ps -ef | Complete |
| `mounts.sh` | `mount` | mount_device, mount_point, mount_type, mount_size_kb, mount_used_kb, mount_avail_kb, mount_use_pct | df -PT → df -P → df (with optional timeout) | Complete |

### Splunk Configuration — TA-ODIN (Forwarders)

| File | Description | Status |
|------|-------------|--------|
| `TA-ODIN/default/app.conf` | App identity: TA-ODIN v2.0.1 | Complete |
| `TA-ODIN/default/inputs.conf` | Scripted inputs. Linux (odin.sh) + Windows (odin.ps1). 30-day interval, 120s timeout. | Complete |
| `TA-ODIN/default/props.conf` | Event line-breaking and timestamp parsing. | Complete |

### Splunk Configuration — ODIN (Indexers / Search Heads)

| File | Description | Status |
|------|-------------|--------|
| `ODIN/default/app.conf` | App identity | **TODO** |
| `ODIN/default/indexes.conf` | odin_discovery index. 1-year retention, 1GB max. | **TODO** |
| `ODIN/default/props.conf` | KV_MODE=auto, CIM aliases (hostname→dest, hostname→dvc), classification lookup bindings. | **TODO** |
| `ODIN/default/transforms.conf` | Lookup definitions for 3 classification CSVs. Case-insensitive, wildcard matching for services and packages. | **TODO** |
| `ODIN/default/savedsearches.conf` | Reports, scheduled searches, alerts. | **TODO** |
| `ODIN/default/data/ui/views/` | Dashboards for visualization and reporting. | **TODO** |
| `ODIN/metadata/default.meta` | Permissions and export scope. | **TODO** |

### Classification Lookups

| File | Matches on | Enriches with | Status |
|------|------------|---------------|--------|
| `lookups/odin_classify_services.csv` | service_name (wildcard) | category, subcategory, vendor, role, description | Partial - sample data |
| `lookups/odin_classify_ports.csv` | listen_port + transport | expected_service, category, description | Partial - sample data |
| `lookups/odin_classify_packages.csv` | package_name (wildcard) | category, vendor, role, description | Partial - sample data |
| `lookups/odin_rules_windows.csv` | — | — | **TODO** - header only |

### Documentation

| File | Description | Status |
|------|-------------|--------|
| `CLAUDE.md` | Development guide. Project vision, conventions, architecture decisions, common tasks. | Complete |
| `DOCS/ARCHITECTURE.md` | This file. Project structure, data flow, file reference. | Complete |
| `DOCS/CHANGEHISTORY.md` | Change log with ISO 8601 CET timestamps per entry. | Complete |
| `TA-ODIN/README.md` | End-user documentation. Installation, configuration, Splunk searches, troubleshooting. | Complete |

## Output Format

All events use space-separated key=value pairs:

```
timestamp=2026-02-21T10:30:45Z hostname=server.example.com os=linux run_id=1740149445-12345 odin_version=2.0.0 type=service service_name=sshd service_status=running service_enabled=enabled service_type=notify
```

**Core fields** (present in every event):

| Field | Example | Description |
|-------|---------|-------------|
| timestamp | 2026-02-21T10:30:45Z | ISO 8601 UTC |
| hostname | server.example.com | FQDN (hostname -f) |
| os | linux | Operating system |
| run_id | 1740149445-12345 | Unique per-execution ID (epoch-PID) |
| odin_version | 2.0.0 | TA-ODIN version |
| type | service | Event type (see modules table above) |

**Special event types** (emitted by orchestrator/modules):

| type | When |
|------|------|
| odin_start | Orchestrator begins execution |
| odin_complete | Orchestrator finishes (includes modules_total, modules_success, modules_failed) |
| odin_error | Module failed or bash not available |
| none_found | Module ran but discovered nothing (includes module= field) |
| mount_error | df timed out (possible hung NFS) |

## TODO

### ODIN App (Indexer / Search Head)
- [ ] Create ODIN app skeleton (app.conf, metadata/default.meta)
- [ ] Move indexes.conf from TA-ODIN to ODIN app
- [ ] Move transforms.conf from TA-ODIN to ODIN app
- [ ] Move lookups/ from TA-ODIN to ODIN app
- [ ] Split props.conf (line-breaking stays in TA-ODIN, search-time lookups move to ODIN)
- [ ] Create dashboards for endpoint enumeration visualization
- [ ] Create saved searches and reports
- [ ] Clean up TA-ODIN (remove configs that moved to ODIN)

### Windows Support
- [ ] Windows orchestrator (odin.ps1) - full PowerShell implementation
- [ ] Windows discovery modules (services, ports, packages, scheduled tasks, processes, mounts)
- [ ] Windows classification lookup (odin_rules_windows.csv)

### Enhancements
- [ ] Expand classification CSVs with more services, ports, and packages
- [ ] Phase 2: Host classification - assign roles based on enumeration data
- [ ] Phase 2: Deployment Server integration - auto-generate serverclasses from classification
