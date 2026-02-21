# ODIN Architecture Overview

Last updated: 2026-02-21 (v2.2.0)

## Deployment Architecture

The project consists of **two separate Splunk apps**:

| App | Deploy to | Purpose |
|-----|-----------|---------|
| **TA-ODIN** | Universal Forwarders (via `deployment_apps/`) | Collection - runs scripts on endpoints |
| **ODIN_app_for_splunk** | Indexers + Search Heads | Index, lookups, search-time enrichment |

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
│   │   ├── odin.sh                            # Linux orchestrator - per-module timeout, MAX_EVENTS
│   │   ├── odin.ps1                           # [TODO] Windows orchestrator - placeholder stub
│   │   └── modules/                           # Discovery modules (auto-loaded by odin.sh)
│   │       ├── services.sh                    # Service enumeration (batch systemctl)
│   │       ├── ports.sh                       # Listening port enumeration (ss/netstat)
│   │       ├── packages.sh                    # Installed package enumeration (dpkg/rpm/apk/pacman)
│   │       ├── cron.sh                        # Scheduled task enumeration (cron/systemd timers/anacron)
│   │       ├── processes.sh                   # Running process enumeration (single ps call)
│   │       └── mounts.sh                      # Filesystem mount enumeration (df)
│   │
│   ├── default/
│   │   ├── app.conf                           # App metadata (v2.1.0)
│   │   ├── inputs.conf                        # Scripted inputs (30-day interval, 120s timeout)
│   │   └── props.conf                         # Line-breaking and timestamp only (forwarder)
│   │
│   ├── local/                                 # Customer overrides (empty by default)
│   ├── static/                                # Empty (reserved for app icons)
│   └── README.md                              # End-user documentation
│
└── ODIN_app_for_splunk/                       # INDEXER/SEARCH HEAD APP
    │
    ├── default/
    │   ├── app.conf                           # App metadata (v2.2.0)
    │   ├── indexes.conf                       # odin_discovery index definition
    │   ├── props.conf                         # Full parsing, KV_MODE, CIM aliases, lookup bindings
    │   ├── savedsearches.conf                 # Host classification and TA deployment saved searches
    │   └── transforms.conf                    # Lookup table definitions
    │
    ├── lookups/
    │   ├── odin_classify_services.csv         # Service name → category/role mapping
    │   ├── odin_classify_ports.csv            # Port → expected service mapping
    │   ├── odin_classify_packages.csv         # Package → category/role mapping
    │   └── odin_log_sources.csv               # Signal → host role / log source / TA mapping
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
│  └──────┬──────┘  Per-module timeout: 90s. MAX_EVENTS: 50,000.          │
│         │  autodiscovers bin/modules/*.sh                                │
│         │                                                                │
│         ├──► services.sh   → type=service  (batch systemctl)            │
│         ├──► ports.sh      → type=port     (timeout 30s)                │
│         ├──► packages.sh   → type=package  (timeout 30s)                │
│         ├──► cron.sh       → type=cron     (batch timers)               │
│         ├──► processes.sh  → type=process  (single ps call)             │
│         └──► mounts.sh     → type=mount    (timeout 30s)                │
│                                                                         │
│  Output: space-separated key=value → stdout → Splunk UF                 │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │ forwards to
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                INDEXER (ODIN_app_for_splunk installed)                   │
│                                                                         │
│  index=odin_discovery  sourcetype=odin:enumeration                      │
│  indexes.conf defines odin_discovery with 1-year retention              │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │ searched by
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│              SEARCH HEAD (ODIN_app_for_splunk installed)                 │
│                                                                         │
│  KV_MODE=auto parses key=value pairs into fields                        │
│  CIM aliases: hostname → dest, hostname → dvc                           │
│                                                                         │
│  Search-time lookups enrich raw data:                                   │
│    service_name  ──► odin_classify_services.csv  ──► category, role     │
│    listen_port   ──► odin_classify_ports.csv     ──► expected_service   │
│    package_name  ──► odin_classify_packages.csv  ──► category, role     │
└─────────────────────────────────────────────────────────────────────────┘
```

## Phase 2: Host Role Classification

Phase 2 adds an aggregation layer on top of raw enumeration data. It turns per-event
classification into host-level role assignments and actionable TA deployment recommendations.

```
Layer 1: Raw Enumeration (TA-ODIN on forwarders)
  type=service service_name=nginx
  type=port listen_port=514 transport=udp
  type=package package_name=splunkforwarder
         │
         ▼
Layer 2: Per-Event Enrichment (odin_classify_*.csv lookups)
  service_name=nginx → service_role=web, service_category=web_server
  listen_port=514   → expected_service=syslog, port_category=logging
         │
         ▼
Layer 3: Log Source Mapping (odin_log_sources.csv)
  signal: service=nginx     → host_role=web_server, log=nginx_access, ta=Splunk_TA_nginx
  signal: port=514/udp      → host_role=syslog_receiver, log=syslog, ta=Splunk_TA_syslog
         │
         ▼
Layer 4: Host Classification (saved search → odin_host_inventory.csv)
  hostname=web01 → roles=web_server,syslog_receiver → tas=Splunk_TA_nginx,Splunk_TA_syslog
```

### Saved Searches

| Search | Schedule | Output | Purpose |
|--------|----------|--------|---------|
| `ODIN - Host Inventory` | Daily 01:05 | `odin_host_inventory.csv` | Per-host: roles, log sources, recommended TAs |
| `ODIN - Log Source Details` | Daily 01:10 | `odin_log_source_details.csv` | Per-host per-role: signals, sourcetypes, log paths |
| `ODIN - TA Deployment Matrix` | Daily 01:15 | (display only) | Which TAs to deploy where, sorted by host count |

### Signal Matching

The `odin_log_sources.csv` lookup matches on `(signal_type, signal_value)`:

- **signal_type=service**: Matches on `service_name` (e.g., `nginx`, `sshd`)
- **signal_type=port**: Matches on `listen_port/transport` (e.g., `443/tcp`, `514/udp`)
- **signal_type=package**: Matches on `package_name` (e.g., `mysql-server`, `nginx`)

Multiple signals can map to the same `host_role`, providing multi-signal reinforcement
(e.g., both `service=syslog-ng` and `port=514/udp` produce `host_role=syslog_receiver`).

## Script Guardrails

| Guardrail | Where | Value | Purpose |
|-----------|-------|-------|---------|
| Per-module timeout | `odin.sh` | 90s | Prevents any module from exceeding Splunk's 120s input timeout |
| MAX_EVENTS cap | `odin.sh` emit() | 50,000/module | Prevents output flooding from hosts with 100K+ items |
| Batch systemctl show | `services.sh` | 1 call | Replaces 2N per-unit subprocess calls |
| Batch systemctl show | `cron.sh` | 1 call | Replaces N per-timer subprocess calls |
| Command timeouts | All modules | 5-30s | Prevents hangs on locks, broken units, hung NFS |
| Single ps call | `processes.sh` | 1 call | Captures output once instead of test-then-run |

## File Reference

### Orchestrator

| File | Description | Status |
|------|-------------|--------|
| `bin/odin.sh` | Linux orchestrator. Autodiscovers modules, sets ODIN_* env vars, emits start/complete events. Per-module 90s timeout. MAX_EVENTS 50K cap. Forces LC_ALL=C. | Complete |
| `bin/odin.ps1` | Windows orchestrator. Currently outputs "not yet implemented". | **TODO** |

### Discovery Modules

All modules follow the same pattern:
- Self-contained and can run standalone or via orchestrator
- Receive context via ODIN_* environment variables
- Use `emit()` for consistent output format (with MAX_EVENTS guardrail)
- Emit `type=none_found` if nothing is discovered
- Force LC_ALL=C for locale-safe output parsing
- Use `read -r` for field splitting (no awk)
- Include fallback chains for minimal/BusyBox systems
- All external commands wrapped with `timeout`

| Module | Event type | Fields | Fallback chain | Status |
|--------|-----------|--------|----------------|--------|
| `services.sh` | `service` | service_name, service_status, service_enabled, service_type | batch systemctl show → service --status-all → /etc/init.d/ (5s per script) | Complete |
| `ports.sh` | `port` | transport, listen_address, listen_port, process_name, process_pid | timeout 30 ss → timeout 30 netstat | Complete |
| `packages.sh` | `package` | package_name, package_version, package_arch, package_manager | timeout 30 dpkg → rpm → apk → pacman | Complete |
| `cron.sh` | `cron` | cron_source, cron_user, cron_schedule, cron_command, cron_file | /etc/crontab, /etc/cron.d, user crontabs, cron.daily/etc, batch systemd timers, anacron | Complete |
| `processes.sh` | `process` | process_pid, process_ppid, process_user, process_state, process_cpu, process_mem, process_elapsed, process_name, process_command | timeout 30 GNU ps -eo → BusyBox ps -o → basic ps -ef (single capture) | Complete |
| `mounts.sh` | `mount` | mount_device, mount_point, mount_type, mount_size_kb, mount_used_kb, mount_avail_kb, mount_use_pct | df -PT → df -P → df (with optional timeout 30) | Complete |

### Splunk Configuration — TA-ODIN (Forwarders)

| File | Description | Status |
|------|-------------|--------|
| `TA-ODIN/default/app.conf` | App identity: TA-ODIN v2.2.0 | Complete |
| `TA-ODIN/default/inputs.conf` | Scripted inputs. Linux (odin.sh) + Windows (odin.ps1). 30-day interval, 120s timeout. | Complete |
| `TA-ODIN/default/props.conf` | Line-breaking and timestamp parsing only (forwarder-minimal). | Complete |

### Splunk Configuration — ODIN_app_for_splunk (Indexers / Search Heads)

| File | Description | Status |
|------|-------------|--------|
| `ODIN_app_for_splunk/default/app.conf` | App identity: ODIN_app_for_splunk v2.2.0 | Complete |
| `ODIN_app_for_splunk/default/indexes.conf` | odin_discovery index. 1-year retention, 1GB max. | Complete |
| `ODIN_app_for_splunk/default/props.conf` | Full parsing, KV_MODE=auto, CIM aliases (hostname→dest, hostname→dvc), classification lookup bindings. Legacy odin:discovery support. | Complete |
| `ODIN_app_for_splunk/default/transforms.conf` | Lookup definitions for 3 classification CSVs + odin_log_sources. Case-insensitive, wildcard matching for services and packages. | Complete |
| `ODIN_app_for_splunk/default/savedsearches.conf` | 3 saved searches: Host Inventory, Log Source Details, TA Deployment Matrix. Daily schedule. | Complete |
| `ODIN_app_for_splunk/metadata/default.meta` | Exports lookups, props, transforms, and saved searches to system scope. | Complete |

### Classification Lookups

| File | Matches on | Enriches with | Status |
|------|------------|---------------|--------|
| `lookups/odin_classify_services.csv` | service_name (wildcard) | category, subcategory, vendor, role, description | Partial - sample data |
| `lookups/odin_classify_ports.csv` | listen_port + transport | expected_service, category, description | Partial - sample data |
| `lookups/odin_classify_packages.csv` | package_name (wildcard) | category, vendor, role, description | Partial - sample data |
| `lookups/odin_log_sources.csv` | signal_type + signal_value | host_role, log_source, sourcetype, recommended_ta, log_path, description | Complete |

### Documentation

| File | Description | Status |
|------|-------------|--------|
| `CLAUDE.md` | Development guide. Project vision, conventions, architecture decisions, common tasks. | Complete |
| `DOCS/ARCHITECTURE.md` | This file. Project structure, data flow, file reference, guardrails. | Complete |
| `DOCS/CHANGEHISTORY.md` | Change log with ISO 8601 CET timestamps per entry. | Complete |
| `DOCS/COMMANDS.md` | Full command reference. Every command used, root vs non-root output, risks. | Complete |
| `TA-ODIN/README.md` | End-user documentation for forwarder app. | Complete |
| `ODIN_app_for_splunk/README.md` | End-user documentation for indexer/search head app. | Complete |

## Output Format

All events use space-separated key=value pairs:

```
timestamp=2026-02-21T10:30:45Z hostname=server.example.com os=linux run_id=1740149445-12345 odin_version=2.1.0 type=service service_name=sshd service_status=running service_enabled=enabled service_type=notify
```

**Core fields** (present in every event):

| Field | Example | Description |
|-------|---------|-------------|
| timestamp | 2026-02-21T10:30:45Z | ISO 8601 UTC |
| hostname | server.example.com | FQDN (hostname -f) |
| os | linux | Operating system |
| run_id | 1740149445-12345 | Unique per-execution ID (epoch-PID) |
| odin_version | 2.1.0 | TA-ODIN version |
| type | service | Event type (see modules table above) |

**Special event types** (emitted by orchestrator/modules):

| type | When |
|------|------|
| odin_start | Orchestrator begins execution |
| odin_complete | Orchestrator finishes (includes modules_total, modules_success, modules_failed) |
| odin_error | Module failed, timed out, or bash not available |
| none_found | Module ran but discovered nothing (includes module= field) |
| truncated | Module hit MAX_EVENTS limit (remaining events suppressed) |
| odin_warning | Pre-run warning (e.g., non-root privilege limitations) |
| privilege_warning | Module detected limited data due to insufficient privileges |
| mount_error | df timed out (possible hung NFS) |

## TODO

### Dashboards & Reports (ODIN_app_for_splunk)
- [x] Create saved searches for host classification and TA deployment (v2.2.0)
- [ ] Create dashboards for endpoint enumeration visualization
- [ ] Create dashboards for host role classification and TA deployment

### Windows Support
- [ ] Windows orchestrator (odin.ps1) - full PowerShell implementation
- [ ] Windows discovery modules (services, ports, packages, scheduled tasks, processes, mounts)
- [ ] Windows classification lookup

### Enhancements
- [ ] Expand classification CSVs with more services, ports, and packages
- [x] Phase 2: Host classification - assign roles based on enumeration data (v2.2.0)
- [x] Phase 2: Log source mapping and TA recommendations (v2.2.0)
- [ ] Phase 2: Deployment Server integration - auto-generate serverclasses from classification
