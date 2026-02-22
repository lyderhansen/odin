# TA-ODIN Change History

All timestamps are ISO 8601 in CET timezone.

---

## v2.2.2 — Splunkbase TA Coverage Expansion

**Date:** 2026-02-22

### Summary

Expanded TA coverage in `odin_recommended_tas.csv` and `odin_log_sources.csv` by researching Splunkbase and GitHub for every technology in the ODIN classification lookups. Reduced `recommended_ta=none` rate from 65% to 48% (service/package rows), added 30 new TA entries, and corrected 3 phantom TA references.

### Coverage metrics (before -> after)

| Metric | Before | After |
|--------|--------|-------|
| Distinct TAs in reference lookup | 22 | 52 |
| Service/package rows with TA assigned | ~70 | 105 (52%) |
| Service/package rows with `none` | ~133 (65%) | 98 (48%) |
| Host roles with at least one TA | ~15 | 34 |

### Status taxonomy expansion

| Status | Count | Description |
|--------|-------|-------------|
| `official` | 23 | Built by Splunk, on Splunkbase |
| `community` | 13 | Third-party/community, on Splunkbase |
| `vendor` | 7 | Built by the technology vendor, on Splunkbase |
| `not_found` | 4 | No TA found (PostgreSQL, MongoDB, Elasticsearch, Trend Micro) |
| `deprecated` | 2 | Archived on Splunkbase (Kubernetes, Nagios) |
| `github` | 2 | GitHub only (Prometheus modinput, Telegraf) |
| `na` | 1 | Intentionally no TA needed |

### New TA entries added

| Category | TAs Added |
|----------|-----------|
| Security tools | TA-SentinelOne, TA-cylance, TA-Tanium, TA-QualysCloudPlatform, TA-tenable, Splunk_TA_mcafee-epo-syslog, Splunk_TA_sophos, Splunk_TA-ossec |
| VPN/Network | TA-wireguard, Splunk_TA_squid, TA-suricata-ccx, TA-snort_alert, TA-zeek, TA-fail2ban, TA-pritunl |
| CI/CD | splunk-app-for-jenkins, gitlab-add-on-for-splunk, jfrog-logs, splunk-kafka-connect |
| Monitoring | Splunk_TA_nagios, Zabbix_Addon_for_Splunk, Datadog_Addon_for_Splunk, Splunk_OTEL_Collector, splunk_modinput_prometheus, TA-influxdata-telegraf |
| App servers | Splunk_TA_tomcat, Splunk_TA_jboss |
| DNS | TA-unbound, TA-pihole_dns |
| Containers | TA_docker_simple |
| Identity | hashicorp-vault-app |
| Windows | Splunk_TA_microsoft-iis |

### Corrections

| Old value | New value | Reason |
|-----------|-----------|--------|
| `Splunk_TA_docker` | `TA_docker_simple` | Splunk_TA_docker does not exist on Splunkbase; real TA is app 4468 |
| `Splunk_TA_snort` | `TA-snort_alert` | No official Splunk TA; community alternative app 5488 |
| `Splunk_TA_suricata` | `TA-suricata-ccx` | No official Splunk TA; community alternative app 6994 |
| IIS W3SVC -> `Splunk_TA_windows` | `Splunk_TA_microsoft-iis` | Dedicated IIS TA (app 3185) provides richer W3C log parsing |

### Modified files

| File | Changes |
|------|---------|
| `ODIN_app_for_splunk/lookups/odin_recommended_tas.csv` | 30 new entries, 3 corrected entries, `github_url` column added |
| `ODIN_app_for_splunk/lookups/odin_log_sources.csv` | 30 rows updated from `none` to actual TAs, 4 corrections |

---

## v2.2.1 — Synthetic Data Generator

**Date:** 2026-02-22

### New files

| File | Description |
|------|-------------|
| `tools/generate_odin_data.py` | Synthetic ODIN data generator (15 host profiles, 700 events) |
| `tools/tests/test_generate_odin_data.py` | Unit tests for event format, profiles, scan generation (17 tests) |
| `tools/tests/test_classification_coverage.py` | Validation tests against classification lookups (5 tests) |
| `tools/output/odin_enumeration.log` | Sample generated data |
| `DOCS/plans/2026-02-22-odin-synthetic-data.md` | Implementation plan |

### Host profiles

15 Linux hosts covering 20 distinct host roles:

| Host | Primary Role | Key Signals |
|------|-------------|-------------|
| `web-prod-01` | web_server | nginx, 80/tcp, 443/tcp |
| `web-prod-02` | web_server | httpd, php-fpm, 80/tcp, 443/tcp |
| `db-prod-01` | database_server | postgresql, 5432/tcp |
| `db-prod-02` | database_server | mysqld, 3306/tcp |
| `app-prod-01` | container_host | docker, containerd, 8080/tcp |
| `cache-prod-01` | cache_server | redis, memcached, 6379/tcp, 11211/tcp |
| `log-prod-01` | splunk_server + syslog_receiver | splunkd, rsyslog, 514/tcp, 9997/tcp |
| `mon-prod-01` | monitoring_server | prometheus, grafana-server, 9090/tcp, 3000/tcp |
| `k8s-master-01` | kubernetes_master | kube-apiserver, etcd, 6443/tcp |
| `k8s-worker-01` | kubernetes_node | kubelet, containerd, 10250/tcp |
| `mail-prod-01` | mail_server | postfix, dovecot, 25/tcp, 993/tcp |
| `vpn-prod-01` | vpn_server | openvpn, 1194/udp |
| `ci-prod-01` | cicd_server | jenkins, docker, 8080/tcp, 50000/tcp |
| `dns-prod-01` | dns_server | named, 53/tcp, 53/udp |
| `mq-prod-01` | message_broker | rabbitmq-server, 5672/tcp, 15672/tcp |

### Classification coverage

| Metric | Count |
|--------|-------|
| Service signal matches | 32 |
| Port signal matches | 31 |
| Package signal matches | 23 |
| Log source signal matches | 55 |
| Distinct host roles covered | 20 |

---

## v2.2.0 — Phase 2: Host Role Classification & Log Source Identification

**Date:** 2026-02-21

### New files

| File | Description |
|------|-------------|
| `ODIN_app_for_splunk/lookups/odin_log_sources.csv` | Signal → host role / log source / TA mapping (273 rows) |
| `ODIN_app_for_splunk/default/savedsearches.conf` | 3 scheduled saved searches for host classification |

### Saved searches

| Search | Schedule | Output | Purpose |
|--------|----------|--------|---------|
| ODIN - Host Inventory | Daily 01:05 | `odin_host_inventory.csv` | Per-host: roles, log sources, recommended TAs |
| ODIN - Log Source Details | Daily 01:10 | `odin_log_source_details.csv` | Per-host per-role: signals, sourcetypes, log paths |
| ODIN - TA Deployment Matrix | Daily 01:15 | (display only) | Which TAs to deploy where, sorted by host count |

### Configuration changes

- Bumped both app.conf files to v2.2.0
- Added `odin_log_sources` lookup definition to transforms.conf
- Added `[savedsearches]` export to metadata/default.meta

### Lookup expansion — comprehensive coverage + Windows

Final row counts:

| Lookup | Rows | Delta |
|--------|------|-------|
| `odin_classify_services.csv` | 331 | +208 from v2.0 |
| `odin_classify_ports.csv` | 205 | +134 from v2.0 |
| `odin_classify_packages.csv` | 273 | +182 from v2.0 |
| `odin_log_sources.csv` | 273 | new |

**Windows services added:**
- Web: IIS (`W3SVC`, `IISADMIN`, `WAS`)
- Database: `MSSQLSERVER`, `SQLSERVERAGENT`, `MSSQLServerOLAPService`, `ReportServer`
- Active Directory: `NTDS`, `Netlogon`, `ADFS`, `CertSvc`
- Exchange: `MSExchangeTransport`, `MSExchangeIS`, `MSExchangeMailboxAssistants`
- Virtualization: `vmms`, `vmcompute` (Hyper-V)
- Remote access: `TermService`, `WinRM`
- File services: `LanmanServer`, `Dfs`, `DFSR`
- Print: `Spooler`
- HA: `ClusSvc` (Failover Clustering)
- Network: `DNS`, `DHCPServer`, `RemoteAccess` (RRAS), `MpsSvc` (Firewall), `SNMP`
- Management: `wuauserv` (Windows Update), `WSUS`, `BITS`, `gpsvc`, `W32Time`, `Schedule`
- Security: `WinDefend`, `MsSense` (MDE), `CSFalconService` (CrowdStrike), `CbDefense` (Carbon Black), `SentinelAgent`, `SEPMasterService` (Symantec), `McAfeeFramework`, `mcshield`, `CylanceSvc`, `TaniumClient`, `QualysAgent`, `OssecSvc` (Wazuh)
- Logging: `EventLog`, `SplunkForwarder`
- Other: `SharePoint`, `BizTalkServerApplication`, `MSDTC`, `WSearch`, `MSiSCSI`

**Windows log sources added:**
- Event Logs: Security, System, Application, PowerShell, Sysmon
- IIS access/error, MSSQL errorlog/audit, SQL Agent
- AD DS directory service, DNS Server, DHCP, Certificate Services, ADFS
- Exchange transport/store, Hyper-V, Windows Firewall
- RDP sessions, Print, SMB, Failover Cluster
- Windows Update, Task Scheduler
- EDR agents: Defender, CrowdStrike, Carbon Black, SentinelOne, Symantec, McAfee, Cylance, Tanium, Wazuh

**Windows ports added:** WinRM (5985/5986/47001), AD Global Catalog (3268/3269), DCOM (49152)

**New Linux categories added:**

| Category | Technologies |
|----------|-------------|
| API gateways | Kong, Apache APISIX, Tyk, Gravitee |
| Database proxies/HA | PgBouncer, ProxySQL, MaxScale, Patroni, Vitess |
| Databases | TiDB, YugabyteDB, QuestDB, TimescaleDB, CockroachDB, ScyllaDB, ArangoDB, RethinkDB, VictoriaMetrics |
| Service mesh / GitOps | Istio, Linkerd, ArgoCD, Flux |
| Data pipeline | Apache Airflow, NiFi, Spark, Flink |
| Identity | Keycloak, FreeIPA, Shibboleth, Authentik |
| Observability | Jaeger, Thanos, Mimir, Tempo, Cortex, OpenTelemetry Collector, Grafana Agent/Alloy |
| Network monitoring | Zeek, ntopng, Cacti, LibreNMS |
| DNS | CoreDNS, PowerDNS, Knot, Pi-hole |
| VPN | Tailscale, Nebula, ZeroTier, Pritunl |
| Logging | Graylog, Grafana Loki, Vector |
| Collaboration | Mattermost, Rocket.Chat, Nextcloud |
| CI/CD / artifacts | Nexus, Artifactory, Drone, Concourse, SonarQube, Gitea, GitLab |
| Automation | AWX, Rundeck, StackStorm, Packer, Vagrant |
| Messaging | NATS, Apache Pulsar |
| HA cluster | Corosync, Pacemaker |
| Backup | Bacula, Bareos, Amanda, Borg, Restic, Veeam, NetWorker |
| Virtualization | libvirtd, QEMU, VMware Tools, VirtualBox, Citrix XenServer |
| Storage | Ceph, GlusterFS, MinIO, DRBD, iSCSI, multipath, LVM2 |
| Telephony | Asterisk, FreeSWITCH, Kamailio |
| Management | Cockpit, Webmin |
| Container | Podman, CRI-O, K3s, RKE2, Harbor |
| Search | Manticore, Meilisearch |

### Documentation

- Updated ARCHITECTURE.md with Phase 2 classification layer and data flow
- Updated CLAUDE.md with Phase 2 status, log source lookup docs, and verification queries

---

## v2.1.0 — Two-App Split & Script Guardrails

**Date:** 2026-02-22

### Two-app architecture

Created `ODIN_app_for_splunk` as a separate indexer/search head app:

| Moved from TA-ODIN | To ODIN_app_for_splunk |
|---------------------|------------------------|
| `indexes.conf` | `default/indexes.conf` |
| `transforms.conf` | `default/transforms.conf` |
| `lookups/*.csv` | `lookups/*.csv` |
| _(new)_ | `default/props.conf` (full parsing, KV_MODE, CIM aliases, lookups) |
| _(new)_ | `metadata/default.meta` (system-scope exports) |

- Deleted `odin_rules_windows.csv` (dead v1 artifact)
- Slimmed TA-ODIN `props.conf` to line-breaking and timestamp only

### Script guardrails

| Guardrail | Where | Value | Purpose |
|-----------|-------|-------|---------|
| Per-module timeout | `odin.sh` | 90s | Prevents exceeding Splunk's 120s input timeout |
| MAX_EVENTS cap | `odin.sh` emit() | 50,000/module | Prevents output flooding |
| Batch systemctl show | `services.sh` | 1 call | Replaces 2N per-unit subprocess calls |
| Batch systemctl show | `cron.sh` | 1 call | Replaces N per-timer subprocess calls |
| Command timeouts | All modules | 5–30s | Prevents hangs on locks, broken units, hung NFS |
| Single ps call | `processes.sh` | 1 call | Captures output once instead of test-then-run |
| Truncation warning | `odin.sh` | `type=truncated` | Emitted when MAX_EVENTS is hit |

### Privilege awareness

- `odin.sh`: EUID check, emits `type=odin_warning` for ports/cron when non-root
- Start event now includes `run_as=` and `euid=` fields
- `ports.sh`: Emits `type=privilege_warning` when process info missing (non-root)
- `cron.sh`: Emits `type=privilege_warning` when crontabs unreadable (non-root)
- Created `DOCS/COMMANDS.md`: full command reference with root vs non-root output

### Documentation

- Updated CLAUDE.md, ARCHITECTURE.md, TA-ODIN/README.md
- Created ODIN_app_for_splunk/README.md
- All scripts: Updated `ODIN_VERSION` fallback to 2.1.0

---

## v2.0.1 — Portability & Observability Improvements

**Date:** 2026-02-21 / 2026-02-22

### `none_found` events

All modules now emit `type=none_found` when nothing is discovered:
`services.sh`, `ports.sh`, `packages.sh`, `cron.sh`, `processes.sh`, `mounts.sh`

### Portability fixes

- `odin.sh`: Bash availability check with clear error event
- `packages.sh`: POSIX-compatible sed (replaces `grep -oP`), fixed apk multi-hyphen parsing, `apk list --installed` support
- `processes.sh`: Three-tier ps fallback (GNU → BusyBox → basic `ps -ef`)
- `mounts.sh`: df flag detection (`df -PT` → `df -P` → `df`), optional timeout
- Variable scoping fix: pipe-based `while` loops → process substitution

### Hardening

- `LC_ALL=C` in all modules and orchestrator
- `mounts.sh`: Fixed mount points with spaces (uses `read` instead of `awk`)
- `packages.sh`: Removed dead code in apk parsing
- `services.sh`, `ports.sh`: Added `safe_val()` for consistent value escaping
- All modules: `read -r` replaces `awk` for field splitting (performance)
- `cron.sh`: Shared `parse_system_cron_line()`, bash array indexing for timers
- `odin.sh`: Exit code reflects module failures

### Output changes

- Renamed `event_type=` → `type=` in all output

### Documentation

- Created `DOCS/ARCHITECTURE.md` with ASCII diagrams and file reference
- Documented two-app deployment architecture decision

---

## v2.0.0 — Full Enumeration Restructure

**Date:** 2026-02-21

Complete rewrite from CSV-rule-based detection to full host enumeration.

### Architecture

- Rewrote `odin.sh` as thin orchestrator with modular autodiscovery (`bin/modules/*.sh`)
- Added `ODIN_*` environment variables (`ODIN_HOSTNAME`, `ODIN_OS`, `ODIN_RUN_ID`, `ODIN_VERSION`)
- Unique `run_id` per execution (epoch-PID format)
- Changed output from comma-separated to space-separated key=value pairs

### Modules

| Module | Event type | Source |
|--------|-----------|--------|
| `services.sh` | `type=service` | systemctl / service / init.d |
| `ports.sh` | `type=port` | ss / netstat |
| `packages.sh` | `type=package` | dpkg / rpm / apk / pacman |
| `cron.sh` | `type=cron` | crontab / systemd timers / anacron |
| `processes.sh` | `type=process` | ps |
| `mounts.sh` | `type=mount` | df |

### Splunk config

- New sourcetype `odin:enumeration` (replaces `odin:discovery`)
- Classification lookups: `odin_classify_services.csv`, `odin_classify_ports.csv`, `odin_classify_packages.csv`
- Search-time lookup transforms for automatic enrichment
- Script timeout: 120s, scan interval: 30 days

---

## v1.0.0 — Initial Release

**Date:** 2025-01-09

- Initial release with Linux file/service discovery
- CSV-driven rule-based detection (~187 rules)
- Splunk `odin:discovery` sourcetype
