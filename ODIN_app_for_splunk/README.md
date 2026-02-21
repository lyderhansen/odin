# ODIN_app_for_splunk - Indexer & Search Head App

## Overview

ODIN_app_for_splunk is the indexer and search head companion to **TA-ODIN**. It provides:

- **Index definition** (`odin_discovery`) for storing enumeration data
- **Classification lookups** that map raw services, ports, and packages to categories and host roles
- **Search-time props/transforms** for field extraction, CIM compliance, and lookup enrichment

## Deployment

| Component | Deploy to |
|-----------|-----------|
| `ODIN_app_for_splunk` | Indexers + Search Heads |
| `TA-ODIN` | Universal Forwarders (via Deployment Server) |

### Install on Indexers
```bash
cp -r ODIN_app_for_splunk $SPLUNK_HOME/etc/apps/
$SPLUNK_HOME/bin/splunk restart
```

For clustered indexers, deploy via Cluster Manager (`manager-apps/`).

### Install on Search Heads
```bash
cp -r ODIN_app_for_splunk $SPLUNK_HOME/etc/apps/
$SPLUNK_HOME/bin/splunk restart
```

For search head clusters, deploy via the Deployer (`shcluster/apps/`).

## What's Included

### Index (`indexes.conf`)
- `odin_discovery` - 1 year retention, 1GB max size

### Classification Lookups
| File | Matches on | Enriches with |
|------|------------|---------------|
| `odin_classify_services.csv` | service_name (wildcard) | category, subcategory, vendor, role, description |
| `odin_classify_ports.csv` | listen_port + transport | expected_service, category, description |
| `odin_classify_packages.csv` | package_name (wildcard) | category, vendor, role, description |

### Props & Transforms
- `KV_MODE=auto` for space-separated key=value parsing
- CIM field aliases: `hostname` -> `dest`, `hostname` -> `dvc`
- Automatic lookup bindings for all three classification CSVs
- Legacy `odin:discovery` sourcetype support (v1 backward compatibility)

## Example Searches

### Event type distribution
```spl
index=odin_discovery sourcetype=odin:enumeration
| stats count by type
| sort - count
```

### Classify hosts by role
```spl
index=odin_discovery sourcetype=odin:enumeration type=service
| lookup odin_classify_services service_name AS service_name OUTPUT role AS service_role
| where isnotnull(service_role)
| stats values(service_role) AS roles by hostname
```

### Find unclassified ports
```spl
index=odin_discovery sourcetype=odin:enumeration type=port
| lookup odin_classify_ports listen_port AS port, transport OUTPUT expected_service
| where isnull(expected_service) AND listen_port>1024
| stats values(listen_port) AS unknown_ports by hostname
```

## Customizing Lookups

Add rows to the CSV files in `lookups/` to classify additional services, ports, or packages. Changes take effect immediately at search time — no need to re-scan endpoints.

## Version History

- **2.1.0** - Initial release as standalone indexer/search head app (split from TA-ODIN)
