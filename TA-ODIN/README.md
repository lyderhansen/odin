# TA-ODIN - Discovery Add-on for Splunk

## Overview

TA-ODIN is a Technology Add-on for Splunk that automatically discovers log files and services on endpoints. It is designed to be deployed via Deployment Server to all forwarders in your environment.

**Key Features:**
- Discovers log files and running services without ingesting actual log data
- Reports only metadata (file existence, size, service status)
- Rule-based detection using CSV configuration files
- Supports both Linux and Windows (Windows coming soon)
- Enables rapid identification of data sources during onboarding

## Architecture

```
TA-ODIN/
├── bin/
│   ├── odin.sh              # Linux discovery script
│   └── odin.ps1             # Windows discovery script (placeholder)
├── default/
│   ├── app.conf             # App metadata
│   ├── inputs.conf          # Scripted input configuration
│   ├── props.conf           # Event parsing
│   ├── transforms.conf      # Field extractions
│   └── indexes.conf         # Index definition (deploy to indexers)
├── local/
│   └── inputs.conf          # Customer-specific overrides
├── lookups/
│   ├── odin_rules_linux.csv   # Linux detection rules
│   └── odin_rules_windows.csv # Windows detection rules
└── README.md
```

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
After deployment, search for discovery events:
```spl
index=odin_discovery sourcetype=odin:discovery
| stats count by hostname, category, detection_type
```

## Output Format

### File Detection
```
timestamp=2025-01-09T10:00:00, hostname=server01, os=linux, detection_type=file, 
category=apache, path=/var/log/apache2/, file=access.log, exists=true, 
empty=false, size_bytes=1048576, description="Apache logs (Debian/Ubuntu)"
```

### Service Detection
```
timestamp=2025-01-09T10:00:00, hostname=server01, os=linux, detection_type=service, 
category=apache, service_name=apache2, status=running, description="Apache HTTP Server"
```

## Customizing Rules

### Adding New Detection Rules

Edit the appropriate CSV file in `lookups/`:

**odin_rules_linux.csv columns:**
| Column | Description |
|--------|-------------|
| detection_type | `file` or `service` |
| category | Category name (e.g., apache, mysql, nginx) |
| check_path | Path to check (supports wildcards) |
| check_service | Service name(s) to check (comma-separated) |
| file_pattern | File pattern to match (e.g., *.log) |
| description | Human-readable description |

**Example - Adding Redis detection:**
```csv
file,redis,/var/log/redis/,,*.log,Redis cache server logs
service,redis,,redis-server,,Redis cache server
```

### Changing Scan Frequency

By default, the scan runs once at deployment, then every 30 days.

To change this, create `local/inputs.conf`:
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

## Phase 2 - Automatic Host Classification (Coming Soon)

Future versions will include:
- Scheduled searches to categorize hosts by role
- Automatic server class assignment
- CSV output for Deployment Server integration

## Troubleshooting

### Script Not Running
Check the script is executable:
```bash
ls -la $SPLUNK_HOME/etc/apps/TA-ODIN/bin/odin.sh
chmod +x $SPLUNK_HOME/etc/apps/TA-ODIN/bin/odin.sh
```

### No Events in Index
1. Verify index exists on indexers
2. Check forwarder outputs.conf points to correct indexers
3. Check `$SPLUNK_HOME/var/log/splunk/splunkd.log` for errors

### Rules File Not Found
Ensure the lookups directory exists and contains CSV files:
```bash
ls -la $SPLUNK_HOME/etc/apps/TA-ODIN/lookups/
```

## Version History

- **1.0.0** - Initial release with Linux file/service discovery

## Support

Contact: Your Organization
