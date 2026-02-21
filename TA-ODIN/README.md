# TA-ODIN - Endpoint Enumeration Add-on for Splunk

## ODIN - Organized Discovery and Identification of eNdpoints

In Norse mythology, Odin was the all-seeing god who sacrificed his eye for wisdom and knowledge. He had two ravens, Hugin (thought) and Munin (memory), who flew across the world each day and reported back everything they observed. This mirrors exactly what TA-ODIN does: it sends out enumeration scripts to endpoints across your infrastructure, and they report back what they find.

---

## Overview

TA-ODIN is a Splunk Technology Add-on that performs **full enumeration** of everything running on endpoints. Unlike traditional approaches that only find predefined items, TA-ODIN discovers all services, listening ports, installed packages, scheduled tasks, running processes, and filesystem mounts - giving you complete visibility without relying on incomplete CMDB data.

**Key Features:**
- Full enumeration of services, ports, packages, cron jobs, processes, and mounts
- Reports only metadata - never the actual log content
- Modular architecture - easy to extend with new discovery modules
- Classification lookups map raw data to host roles at search time
- Supports any Linux distribution (systemd, SysV init, or init.d)
- Deploys via Splunk Deployment Server to Universal Forwarders

## Architecture

```
TA-ODIN/
├── bin/
│   ├── odin.sh                       # Orchestrator (autodiscovers modules)
│   ├── odin.ps1                      # Windows orchestrator (placeholder)
│   └── modules/                      # Discovery modules
│       ├── services.sh               # Service enumeration
│       ├── ports.sh                  # Listening port enumeration
│       ├── packages.sh               # Installed package enumeration
│       ├── cron.sh                   # Scheduled task enumeration
│       ├── processes.sh              # Running process enumeration
│       └── mounts.sh                 # Filesystem mount enumeration
├── default/
│   ├── app.conf                      # App metadata (v2.0.0)
│   ├── inputs.conf                   # Scripted inputs (30-day interval)
│   ├── props.conf                    # Event parsing + classification lookups
│   ├── transforms.conf               # Lookup transform definitions
│   └── indexes.conf                  # Index definition (deploy to indexers)
├── local/                            # Customer-specific overrides
├── lookups/
│   ├── odin_classify_services.csv    # Service -> category/role mapping
│   ├── odin_classify_ports.csv       # Port -> expected service mapping
│   └── odin_classify_packages.csv    # Package -> category/role mapping
└── README.md
```

### How It Works

1. **Orchestrator** (`odin.sh`) sets shared context via environment variables and autodiscovers all modules in `bin/modules/`
2. **Modules** each enumerate one domain (services, ports, packages, etc.) and emit space-separated key=value events
3. **Splunk** indexes the raw enumeration data with sourcetype `odin:enumeration`
4. **Classification lookups** enrich events at search time, mapping service names, ports, and packages to categories and host roles

## Installation

### On Indexers
Deploy `indexes.conf` to create the `odin_discovery` index:
```bash
cp TA-ODIN/default/indexes.conf $SPLUNK_HOME/etc/apps/TA-ODIN/local/
```

### On Deployment Server
1. Copy TA-ODIN to `$SPLUNK_HOME/etc/deployment-apps/`
2. Create a server class for all forwarders
3. Deploy the app

### Verification
After deployment, check that events are arriving:
```spl
index=odin_discovery sourcetype=odin:enumeration
| stats count by type
| sort - count
```

## Output Format

All events are space-separated key=value pairs. Every event includes common fields:

```
timestamp=2026-02-21T10:00:00Z hostname=web01 os=linux run_id=1740100800-1234 odin_version=2.0.0
```

### Service Events
```
timestamp=2026-02-21T10:00:00Z hostname=web01 os=linux run_id=1740100800-1234 odin_version=2.0.0 type=service service_name=nginx service_status=running service_enabled=enabled service_type=forking
```

### Port Events
```
timestamp=2026-02-21T10:00:00Z hostname=web01 os=linux run_id=1740100800-1234 odin_version=2.0.0 type=port transport=tcp listen_address=0.0.0.0 listen_port=443 process_name=nginx process_pid=1234
```

### Package Events
```
timestamp=2026-02-21T10:00:00Z hostname=web01 os=linux run_id=1740100800-1234 odin_version=2.0.0 type=package package_name=nginx package_version=1.24.0-1 package_arch=amd64 package_manager=dpkg
```

### Cron Events
```
timestamp=2026-02-21T10:00:00Z hostname=web01 os=linux run_id=1740100800-1234 odin_version=2.0.0 type=cron cron_source=user_crontab cron_user=root cron_schedule="0 2 * * *" cron_command="/usr/local/bin/backup.sh"
```

### Process Events
```
timestamp=2026-02-21T10:00:00Z hostname=web01 os=linux run_id=1740100800-1234 odin_version=2.0.0 type=process process_pid=1234 process_ppid=1 process_user=www-data process_state=Ss process_cpu=0.1 process_mem=2.3 process_elapsed=10-05:23:15 process_name=nginx process_command="nginx: master process /usr/sbin/nginx"
```

### Mount Events
```
timestamp=2026-02-21T10:00:00Z hostname=web01 os=linux run_id=1740100800-1234 odin_version=2.0.0 type=mount mount_device=/dev/sda1 mount_point=/ mount_type=ext4 mount_size_kb=20511312 mount_used_kb=8234560 mount_avail_kb=11213304 mount_use_pct=42
```

## Classification Lookups

Classification happens at **search time** using Splunk lookup tables. This means you can update classification rules without re-scanning hosts.

### Service Classification (`odin_classify_services.csv`)
Maps service names to categories and roles:
| Column | Description |
|--------|-------------|
| service_pattern | Service name pattern (supports wildcards) |
| category | Category (e.g., web_server, database, security) |
| subcategory | Subcategory (e.g., reverse_proxy, relational) |
| vendor | Vendor name |
| role | Host role indicator |
| description | Human-readable description |

### Port Classification (`odin_classify_ports.csv`)
Maps well-known ports to expected services:
| Column | Description |
|--------|-------------|
| port | Port number |
| transport | Protocol (tcp/udp) |
| expected_service | Expected service name |
| category | Service category |
| description | Human-readable description |

### Package Classification (`odin_classify_packages.csv`)
Maps package names to host roles:
| Column | Description |
|--------|-------------|
| package_pattern | Package name pattern (supports wildcards) |
| category | Category |
| vendor | Vendor name |
| role | Host role indicator |
| description | Human-readable description |

### Example: Classify hosts by role
```spl
index=odin_discovery sourcetype=odin:enumeration type=service
| lookup odin_classify_services service_name AS service_name OUTPUT role AS service_role
| where isnotnull(service_role)
| stats values(service_role) AS roles by hostname
```

## Customization

### Adding a New Discovery Module
Create a new `.sh` file in `bin/modules/`. The orchestrator will auto-discover it:

```bash
#!/bin/bash
# Module template
if ! declare -f emit &>/dev/null; then
    ODIN_HOSTNAME="${ODIN_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}"
    ODIN_OS="${ODIN_OS:-linux}"
    ODIN_RUN_ID="${ODIN_RUN_ID:-standalone-$$}"
    ODIN_VERSION="${ODIN_VERSION:-2.0.0}"
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
    emit() { echo "timestamp=$(get_timestamp) hostname=$ODIN_HOSTNAME os=$ODIN_OS run_id=$ODIN_RUN_ID odin_version=$ODIN_VERSION $*"; }
fi

# Your enumeration logic here
emit "type=custom_type field1=value1 field2=value2"
```

### Adding Classification Rules
Add rows to the appropriate CSV in `lookups/`:
- `odin_classify_services.csv` - Service-to-role mappings
- `odin_classify_ports.csv` - Port-to-service mappings
- `odin_classify_packages.csv` - Package-to-role mappings

### Changing Scan Frequency
Create `local/inputs.conf`:
```ini
[script://./bin/odin.sh]
interval = 86400  # Run daily

# Or for one-time only:
# interval = -1
```

## Data Retention

Default retention is 1 year. To change, edit `indexes.conf`:
```ini
[odin_discovery]
# 2 years
frozenTimePeriodInSecs = 63072000
```

## Useful Searches

### Event type distribution
```spl
index=odin_discovery sourcetype=odin:enumeration
| stats count by type
| sort - count
```

### Hosts with most services
```spl
index=odin_discovery sourcetype=odin:enumeration type=service service_status=running
| stats dc(service_name) AS service_count by hostname
| sort - service_count
```

### Find hosts listening on unusual ports
```spl
index=odin_discovery sourcetype=odin:enumeration type=port
| lookup odin_classify_ports listen_port AS port, transport OUTPUT expected_service
| where isnull(expected_service) AND listen_port>1024
| stats values(listen_port) AS unknown_ports by hostname
```

### Host role summary
```spl
index=odin_discovery sourcetype=odin:enumeration type=service
| lookup odin_classify_services service_name OUTPUT role
| where isnotnull(role)
| stats values(role) AS roles, dc(service_name) AS service_count by hostname
| sort - service_count
```

## Phase 2 - Automatic Host Classification (Planned)

Future versions will include:
- Scheduled searches to categorize hosts by role based on enumeration data
- Automatic server class generation for Deployment Server
- CSV output for automated app deployment

## Troubleshooting

### Script Not Running
```bash
ls -la $SPLUNK_HOME/etc/apps/TA-ODIN/bin/odin.sh
chmod +x $SPLUNK_HOME/etc/apps/TA-ODIN/bin/odin.sh
chmod +x $SPLUNK_HOME/etc/apps/TA-ODIN/bin/modules/*.sh
```

### No Events in Index
1. Verify the `odin_discovery` index exists on indexers
2. Check forwarder `outputs.conf` points to correct indexers
3. Check `$SPLUNK_HOME/var/log/splunk/splunkd.log` for errors

### Testing Locally
Run the full orchestrator:
```bash
cd TA-ODIN && bash bin/odin.sh
```

Test a single module:
```bash
export ODIN_HOSTNAME=test ODIN_OS=linux ODIN_RUN_ID=test-001 ODIN_VERSION=2.0.0
bash TA-ODIN/bin/modules/services.sh
```

## Version History

- **2.0.0** - Full enumeration restructure: modular architecture, 6 discovery modules, classification lookups
- **1.0.0** - Initial release with CSV-rule-based Linux file/service discovery

## Support

Contact: Your Organization
