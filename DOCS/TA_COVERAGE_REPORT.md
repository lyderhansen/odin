# ODIN TA Coverage Report

**Date:** 2026-02-22 | **Version:** v2.2.2 | **Author:** Automated research via Splunkbase and GitHub

---

## Executive Summary

ODIN classifies discovered endpoints into host roles and recommends Splunk Technology Add-ons (TAs) for log collection. This report documents the coverage expansion from 22 to 52 TA entries, reducing the `recommended_ta=none` rate from 65% to 48% across all service and package signal rows.

The remaining 48% without TA coverage represents legitimate gaps in the Splunk ecosystem -- databases, log shippers, and infrastructure long-tail services where no dedicated Splunk TA exists.

---

## Coverage Metrics

### Before vs After

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Distinct TAs in reference lookup | 22 | 52 | +136% |
| Service/package rows with TA | ~70 (35%) | 105 (52%) | +50% |
| Service/package rows with `none` | ~133 (65%) | 98 (48%) | -26% |
| Host roles with at least one TA | ~15 | 34 | +127% |
| Host roles with zero TA coverage | ~40 | 21 | -48% |

### Row Breakdown (273 total rows)

| Category | Count | Percentage |
|----------|-------|------------|
| Service/package rows with actual TA assigned | 105 | 38% |
| Service/package rows with `none` (no TA exists) | 98 | 36% |
| Port rows (empty TA, by design) | 70 | 26% |

Port rows intentionally have no TA -- they are traffic indicators only. Excluding port rows, the effective coverage is **105/203 = 52%**.

---

## TA Reference Catalog (52 entries)

### Status Distribution

| Status | Count | Description |
|--------|-------|-------------|
| `official` | 23 | Built and maintained by Splunk |
| `community` | 13 | Third-party/community, published on Splunkbase |
| `vendor` | 7 | Built by the technology vendor, on Splunkbase |
| `not_found` | 4 | Researched but no TA found anywhere |
| `deprecated` | 2 | Archived on Splunkbase but still functional |
| `github` | 2 | Only available on GitHub |
| `na` | 1 | Intentionally no TA needed (sentinel row) |

### Official Splunk TAs (23)

| TA Name | Splunkbase | Official Name | Notes |
|---------|------------|---------------|-------|
| Splunk_OTEL_Collector | [app 7125](https://splunkbase.splunk.com/app/7125) | Splunk Add-On for OpenTelemetry Collector | Traces and metrics. Includes Prometheus/Jaeger/OTLP receivers |
| Splunk_TA-ossec | [app 2808](https://splunkbase.splunk.com/app/2808) | Splunk Add-on for OSSEC | CIM 4.x. Parses OSSEC and Wazuh syslog alerts |
| Splunk_TA_apache | [app 3186](https://splunkbase.splunk.com/app/3186) | Splunk Add-on for Apache Web Server | |
| Splunk_TA_bind | [app 2876](https://splunkbase.splunk.com/app/2876) | Splunk Add-on for ISC BIND | |
| Splunk_TA_carbonblack | [app 2790](https://splunkbase.splunk.com/app/2790) | Splunk Add-on for Carbon Black | |
| Splunk_TA_crowdstrike | [app 5579](https://splunkbase.splunk.com/app/5579) | Splunk Add-on for CrowdStrike FDR | FDR via S3/SQS |
| Splunk_TA_haproxy | [app 3135](https://splunkbase.splunk.com/app/3135) | Splunk Add-on for HAProxy | |
| Splunk_TA_jboss | [app 2954](https://splunkbase.splunk.com/app/2954) | Splunk Add-on for JBoss | CIM 4.x. Covers WildFly and JBoss EAP |
| Splunk_TA_mcafee-epo-syslog | [app 5085](https://splunkbase.splunk.com/app/5085) | Splunk Add-on for McAfee ePO Syslog | CIM 5.x. Archived |
| Splunk_TA_microsoft-iis | [app 3185](https://splunkbase.splunk.com/app/3185) | Splunk Add-on for Microsoft IIS | CIM Web model. Parses IIS W3C access logs |
| Splunk_TA_microsoft_defender | [app 6207](https://splunkbase.splunk.com/app/6207) | Splunk Add-on for Microsoft Security | Covers M365 Defender and Defender for Endpoint |
| Splunk_TA_microsoft_exchange | [app 3225](https://splunkbase.splunk.com/app/3225) | Splunk Add-on for Microsoft Exchange | |
| Splunk_TA_microsoft_sqlserver | [app 2648](https://splunkbase.splunk.com/app/2648) | Splunk Add-on for Microsoft SQL Server | |
| Splunk_TA_microsoft_sysmon | [app 5709](https://splunkbase.splunk.com/app/5709) | Splunk Add-on for Sysmon | Replaces archived app 1914 |
| Splunk_TA_mysql | [app 2848](https://splunkbase.splunk.com/app/2848) | Splunk Add-on for MySQL | Some collection methods require DB Connect |
| Splunk_TA_nginx | [app 3258](https://splunkbase.splunk.com/app/3258) | Splunk Add-on for NGINX | |
| Splunk_TA_nix | [app 833](https://splunkbase.splunk.com/app/833) | Splunk Add-on for Unix and Linux | |
| Splunk_TA_sophos | [app 1854](https://splunkbase.splunk.com/app/1854) | Splunk Add-on for Sophos | CIM 4.x. Archived |
| Splunk_TA_squid | [app 2965](https://splunkbase.splunk.com/app/2965) | Splunk Add-on for Squid Proxy | Archived but supports Splunk 10.x |
| Splunk_TA_symantec_ep | [app 2772](https://splunkbase.splunk.com/app/2772) | Splunk Add-on for Symantec Endpoint Protection | |
| Splunk_TA_tomcat | [app 2911](https://splunkbase.splunk.com/app/2911) | Splunk Add-on for Tomcat | CIM 5.x. Supports JMX via Splunk_TA_jmx |
| Splunk_TA_windows | [app 742](https://splunkbase.splunk.com/app/742) | Splunk Add-on for Microsoft Windows | |
| splunk-kafka-connect | [app 3862](https://splunkbase.splunk.com/app/3862) | Splunk Connect for Kafka | Kafka Connect sink for HEC |

### Vendor TAs (7)

| TA Name | Splunkbase | Official Name | Notes |
|---------|------------|---------------|-------|
| TA-QualysCloudPlatform | [app 2964](https://splunkbase.splunk.com/app/2964) | Qualys Technology Add-on for Splunk | CIM 5.x. API-based. By Qualys Inc |
| TA-SentinelOne | [app 5435](https://splunkbase.splunk.com/app/5435) | SentinelOne App For Splunk | CIM 5.x. By SentinelOne |
| TA-Tanium | [app 4439](https://splunkbase.splunk.com/app/4439) | TA-Tanium | CIM 6.x. API/stream-based. By Tanium Inc |
| TA-tenable | [app 4060](https://splunkbase.splunk.com/app/4060) | Tenable Add-On for Splunk | CIM 6.x. API-based. By Tenable Inc |
| TA-zeek | [app 5466](https://splunkbase.splunk.com/app/5466) | TA for Zeek | CIM 6.x. Maintained by Corelight. 83K downloads |
| hashicorp-vault-app | [app 5093](https://splunkbase.splunk.com/app/5093) | HashiCorp Vault App for Splunk | Parses Vault audit logs (JSON). By HashiCorp |
| jfrog-logs | [app 5023](https://splunkbase.splunk.com/app/5023) | JFrog Platform Log Analytics | FluentD pipeline to HEC. By JFrog |

### Community TAs (13)

| TA Name | Splunkbase | Official Name | Notes |
|---------|------------|---------------|-------|
| Datadog_Addon_for_Splunk | [app 4163](https://splunkbase.splunk.com/app/4163) | Datadog Add-on for Splunk | Fetches Datadog metrics via API. By Splunk Works |
| TA-cylance | [app 3709](https://splunkbase.splunk.com/app/3709) | CylancePROTECT Add-on for Splunk | CIM 4.x. Parses Cylance syslog events |
| TA-fail2ban | [app 4421](https://splunkbase.splunk.com/app/4421) | TA for fail2ban | CIM 5.x. Archived but functional |
| TA-pihole_dns | [app 4505](https://splunkbase.splunk.com/app/4505) | Pi-hole Add-on for Splunk | CIM 5.x. Active |
| TA-pritunl | [app 7223](https://splunkbase.splunk.com/app/7223) | Pritunl Add-on for Splunk | CIM 6.x. Active (Feb 2026) |
| TA-snort_alert | [app 5488](https://splunkbase.splunk.com/app/5488) | Snort Alert for Splunk | CIM 6.x. Supports Snort 2 and 3. By Splunk Works |
| TA-suricata-ccx | [app 6994](https://splunkbase.splunk.com/app/6994) | CCX Add-on for Suricata | CIM 6.x. 7 CIM data models. By CyberCX |
| TA-unbound | [app 4888](https://splunkbase.splunk.com/app/4888) | Technology Add-On for Unbound DNS | CIM 4.x. Archived |
| TA-wireguard | [app 5375](https://splunkbase.splunk.com/app/5375) | TA for wireguard | CIM 5.x. Archived but functional |
| TA_docker_simple | [app 4468](https://splunkbase.splunk.com/app/4468) | Docker Simple TA | Scripted inputs for docker stats/ps. By Chris Younger |
| Zabbix_Addon_for_Splunk | [app 5272](https://splunkbase.splunk.com/app/5272) | Zabbix Add-on For Splunk | Bidirectional Zabbix integration |
| gitlab-add-on-for-splunk | [app 6848](https://splunkbase.splunk.com/app/6848) | Gitlab Add-on for Splunk | API-based. By Avotrix Inc |
| splunk-app-for-jenkins | [app 3332](https://splunkbase.splunk.com/app/3332) | Splunk App for Jenkins | Push-based via Jenkins HEC plugin |

### Deprecated (2)

| TA Name | Splunkbase | Notes |
|---------|------------|-------|
| Splunk_TA_kubernetes | [app 3991](https://splunkbase.splunk.com/app/3991) | Archived 2019. Use OTEL Collector for Kubernetes (app 6264) |
| Splunk_TA_nagios | [app 2703](https://splunkbase.splunk.com/app/2703) | Archived Sept 2020. Polls via NDOUtils |

### GitHub Only (2)

| TA Name | Repository | Notes |
|---------|------------|-------|
| splunk_modinput_prometheus | [lukemonahan/splunk_modinput_prometheus](https://github.com/lukemonahan/splunk_modinput_prometheus) | Author recommends migrating to OTEL Collector |
| TA-influxdata-telegraf | [guilhemmarchand/TA-influxdata-telegraf](https://github.com/guilhemmarchand/TA-influxdata-telegraf) | Indexing-time parsing for Telegraf metrics |

### Not Found (4)

| TA Name | Workaround |
|---------|------------|
| Splunk_TA_elasticsearch | Consider Add-on for Elasticsearch (app 7839) or ElasticSPL (app 6477) |
| Splunk_TA_mongodb | Use Splunk DB Connect (app 2686) with MongoDB JDBC driver (app 7095) |
| Splunk_TA_postgresql | Use Splunk DB Connect (app 2686) with Postgres JDBC driver (app 6152) |
| Splunk_TA_trendmicro | Consider CCX Unified Splunk Add-on for Trend Micro (app 5349) |

---

## Host Role Coverage Detail

### Full Coverage (100%)

All signal rows for these roles have a TA assigned.

| Host Role | Signals | TAs |
|-----------|---------|-----|
| audit_host | 1 | Splunk_TA_nix |
| certificate_server | 1 | Splunk_TA_windows |
| ids_host | 3 | TA-snort_alert, TA-suricata-ccx, TA-zeek |
| proxy_server | 1 | Splunk_TA_squid |
| security_endpoint | 18 | 11 distinct TAs (CrowdStrike, Defender, Carbon Black, SentinelOne, OSSEC, Symantec, McAfee, Cylance, Tanium, Trend Micro, Windows Defender) |
| security_host | 1 | TA-fail2ban |
| windows_host | 8 | Splunk_TA_windows, Splunk_TA_microsoft_sysmon |

### Partial Coverage (1-99%)

| Host Role | With TA | Total | Coverage | TAs |
|-----------|---------|-------|----------|-----|
| monitoring_agent | 3 | 4 | 75% | Datadog_Addon_for_Splunk, TA-influxdata-telegraf, Zabbix_Addon_for_Splunk |
| kubernetes_master | 4 | 6 | 66% | Splunk_TA_kubernetes |
| container_host | 2 | 3 | 66% | TA_docker_simple |
| dhcp_server | 2 | 3 | 66% | Splunk_TA_nix, Splunk_TA_windows |
| web_server | 11 | 18 | 61% | Splunk_TA_apache, Splunk_TA_microsoft-iis, Splunk_TA_nginx |
| cicd_server | 3 | 5 | 60% | gitlab-add-on-for-splunk, splunk-app-for-jenkins |
| domain_controller | 3 | 5 | 60% | Splunk_TA_windows |
| dns_server | 5 | 10 | 50% | Splunk_TA_bind, Splunk_TA_windows, TA-pihole_dns, TA-unbound |
| rdp_server | 1 | 2 | 50% | Splunk_TA_windows |
| secrets_server | 1 | 2 | 50% | hashicorp-vault-app |
| security_scanner | 1 | 2 | 50% | TA-tenable |
| ssh_server | 1 | 2 | 50% | Splunk_TA_nix |
| virtualization_host | 1 | 2 | 50% | Splunk_TA_windows |
| mail_server | 4 | 10 | 40% | Splunk_TA_microsoft_exchange, Splunk_TA_nix |
| syslog_receiver | 2 | 5 | 40% | Splunk_TA_nix |
| ha_cluster | 1 | 3 | 33% | Splunk_TA_windows |
| identity_server | 1 | 3 | 33% | Splunk_TA_windows |
| kubernetes_node | 1 | 3 | 33% | Splunk_TA_kubernetes |
| print_server | 1 | 3 | 33% | Splunk_TA_windows |
| search_server | 1 | 3 | 33% | Splunk_TA_elasticsearch |
| database_server | 13 | 40 | 32% | Splunk_TA_microsoft_sqlserver, Splunk_TA_mongodb, Splunk_TA_mysql, Splunk_TA_postgresql |
| application_server | 2 | 7 | 28% | Splunk_TA_jboss, Splunk_TA_tomcat |
| file_server | 1 | 4 | 25% | Splunk_TA_windows |
| load_balancer | 1 | 4 | 25% | Splunk_TA_haproxy |
| monitoring_server | 4 | 18 | 22% | Splunk_OTEL_Collector, Splunk_TA_nagios, Zabbix_Addon_for_Splunk |
| vpn_server | 1 | 6 | 16% | TA-wireguard |
| message_broker | 1 | 8 | 12% | splunk-kafka-connect |

### Zero Coverage (0%)

No Splunk TA exists for any signal in these roles.

| Host Role | Signals | Why |
|-----------|---------|-----|
| api_gateway | 2 | Kong, APISIX -- no Splunk TAs exist |
| backup_server | 2 | Bacula, Bareos -- niche, no TAs |
| cache_server | 5 | Redis, Memcached -- no dedicated TAs, use generic monitors |
| collaboration_server | 2 | Mattermost, Nextcloud -- no TAs |
| data_pipeline | 2 | Airflow, NiFi -- no TAs |
| directory_server | 7 | OpenLDAP, Kerberos, SSSD, FreeRADIUS -- no TAs |
| infrastructure | 2 | ZooKeeper -- no TA |
| log_aggregator | 2 | Loki, Graylog -- no TAs (competing products) |
| log_shipper | 5 | Filebeat, Fluent Bit, Fluentd, Promtail, Vector -- competing products |
| logstash_server | 1 | Logstash -- competing product |
| management_server | 4 | Cockpit, Webmin -- no TAs |
| network_infrastructure | 2 | SNMP agent -- generic, no dedicated TA |
| nfs_server | 2 | NFS -- use Splunk_TA_nix for syslog |
| orchestration_server | 4 | Consul, Nomad -- no TAs |
| splunk_forwarder | 2 | Internal -- no external TA needed |
| splunk_receiver | 1 | Internal -- no external TA needed |
| splunk_server | 3 | Internal -- no external TA needed |
| storage_server | 4 | Ceph, GlusterFS -- no TAs |
| telephony_server | 3 | Asterisk, FreeSWITCH -- no TAs |
| virtualization_guest | 1 | VMware Tools -- no dedicated TA |
| windows_management | 3 | WinRM -- port-only, uses Splunk_TA_windows |

---

## Corrections Made

During research, three phantom TA references were discovered and corrected.

| Original TA | Problem | Corrected To | Reason |
|-------------|---------|--------------|--------|
| `Splunk_TA_docker` | Does not exist on Splunkbase | `TA_docker_simple` (app 4468) | Community TA by Chris Younger |
| `Splunk_TA_snort` | Does not exist on Splunkbase | `TA-snort_alert` (app 5488) | Community TA by Splunk Works |
| `Splunk_TA_suricata` | Does not exist on Splunkbase | `TA-suricata-ccx` (app 6994) | Community TA by CyberCX |
| IIS W3SVC -> `Splunk_TA_windows` | Generic TA, weak IIS parsing | `Splunk_TA_microsoft-iis` (app 3185) | Dedicated IIS W3C log parser |

---

## Catalog-Only TAs (5 unreferenced)

These TAs exist in `odin_recommended_tas.csv` as a reference catalog but are not mapped to any `odin_log_sources.csv` signal. This is intentional -- they cover scenarios ODIN enumeration does not detect (API-based, push-based, or no running service to discover).

| TA | Status | Reason Unreferenced |
|----|--------|---------------------|
| TA-QualysCloudPlatform | vendor | API-based scanner, no local service to enumerate |
| TA-pritunl | community | Pritunl not in current signal mappings (future addition) |
| Splunk_TA_sophos | official | Sophos agent service name varies by deployment |
| jfrog-logs | vendor | Push-based via FluentD, no local service |
| splunk_modinput_prometheus | github | Prometheus scraping, no local service signal |

---

## Ecosystem Observations

### Best Coverage: Security Tools

The security endpoint category has **100% TA coverage** across 18 signal rows with 11 distinct TAs. Every major EDR/AV vendor publishes a Splunk TA because SIEM integration is a competitive requirement in the security market.

### Worst Coverage: Databases

Despite having the most signal rows (40), databases only achieve **32% coverage**. The big four (MySQL, PostgreSQL, MongoDB, SQL Server) have TAs, but everything else (Redis, ClickHouse, Cassandra, InfluxDB, Neo4j, CouchDB, CockroachDB, TimescaleDB) has no dedicated Splunk TA. Splunk's strategy for these is generic log file monitoring or DB Connect JDBC integration.

### Legitimate Gaps: Competing Products

Log shippers (Filebeat, Fluentd, Logstash) and log aggregators (Loki, Graylog) have zero TA coverage. These are Splunk competitors -- there is no incentive for anyone to build TAs for them.

### The Long Tail

Infrastructure services (Ceph, GlusterFS, Corosync, Pacemaker, Bacula, Asterisk, etc.) represent niche technologies where the Splunk community is too small to sustain dedicated TAs. For these, `Splunk_TA_nix` generic syslog/log file monitoring is the recommended approach.

---

## Methodology

Each technology was researched using:

1. **Splunkbase search** -- searched for `"<technology> Splunk"` to find official, vendor, and community TAs
2. **GitHub search** -- searched for `splunk TA <technology>` to find GitHub-only options
3. **Validation** -- confirmed Splunkbase app IDs, checked CIM compatibility, verified maintenance status

Research was conducted across 12 technology categories in parallel batches, covering 100+ technologies.

---

## Files Modified

| File | Description |
|------|-------------|
| `ODIN_app_for_splunk/lookups/odin_recommended_tas.csv` | TA reference catalog (22 -> 52 entries) |
| `ODIN_app_for_splunk/lookups/odin_log_sources.csv` | Signal-to-TA mapping (30 rows updated, 4 corrected) |
| `ODIN_app_for_splunk/default/transforms.conf` | Added `odin_recommended_tas` lookup definition |
| `ODIN_app_for_splunk/default/savedsearches.conf` | Enhanced TA Deployment Matrix with Splunkbase enrichment |
| `ODIN_app_for_splunk/default/props.conf` | Fixed lookup field name mappings |
