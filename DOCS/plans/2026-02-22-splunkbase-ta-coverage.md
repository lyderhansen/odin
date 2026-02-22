# Splunkbase TA Coverage Expansion Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expand `odin_recommended_tas.csv` from 22 entries to comprehensive coverage by researching Splunkbase and GitHub for every technology in the ODIN classification lookups, reducing the 65% "none" rate in `odin_log_sources.csv`.

**Architecture:** Research-then-update. Each task researches a category of technologies on Splunkbase and GitHub, then updates both `odin_recommended_tas.csv` (TA reference) and `odin_log_sources.csv` (signal-to-TA mapping). The `odin_recommended_tas.csv` status taxonomy expands to distinguish official Splunk TAs from vendor-built, community, and GitHub-only options.

**Tech Stack:** Splunkbase web search, GitHub search, CSV editing

---

## Status Taxonomy

Update `odin_recommended_tas.csv` to use these status values:

| Status | Meaning | Example |
|--------|---------|---------|
| `official` | Built by Splunk, on Splunkbase | Splunk_TA_nginx (app 3258) |
| `vendor` | Built by the technology vendor, on Splunkbase | CrowdStrike Falcon Event Streams (app 5082) |
| `community` | Third-party/community, on Splunkbase | CCX Add-on for Suricata (app 6994) |
| `deprecated` | On Splunkbase but archived/end-of-life | Splunk_TA_kubernetes (app 3991) |
| `github` | Only on GitHub, not on Splunkbase | Custom TA for X on github.com/user/repo |
| `none` | No known TA exists anywhere | Mosquitto MQTT broker |

## CSV Column Updates

**`odin_recommended_tas.csv`** -- add `github_url` column:

```csv
recommended_ta,splunkbase_id,splunkbase_url,official_name,status,github_url,notes
```

**`odin_log_sources.csv`** -- update `recommended_ta` column from `none` to actual TA name where found.

## Research Method Per Technology

For each technology with `recommended_ta=none`:

1. **Splunkbase search**: Search `splunkbase.splunk.com` for the technology name (e.g., "Redis", "Kafka"). Check:
   - Official Splunk TAs (`Splunk_TA_*`, `Splunk Add-on for *`)
   - Vendor-built add-ons (e.g., vendor published their own)
   - Community add-ons (third-party, CIM-compliant preferred)
   - Note: Some TAs cover multiple technologies (e.g., Splunk_TA_nix covers syslog, auth, ps, etc.)

2. **GitHub search**: Search for `splunk TA <technology>` or `splunk add-on <technology>`. Look for:
   - Repositories with props.conf/transforms.conf (real TAs)
   - Active maintenance (recent commits)
   - Stars/forks as quality signal

3. **Record findings** in `odin_recommended_tas.csv` with appropriate status.

4. **Update `odin_log_sources.csv`** -- replace `none` with the TA name for matching rows.

---

## Task 1: Monitoring & Observability

**Technologies:** Prometheus, Grafana, AlertManager, Zabbix, Nagios, Icinga2, Netdata, Jaeger, Thanos, OTEL Collector, node_exporter, Telegraf, Datadog agent, ntopng, Cacti, LibreNMS

**Affected host_roles:** monitoring_server, monitoring_agent, nagios_server, netdata_server

**Files:**
- Modify: `ODIN_app_for_splunk/lookups/odin_recommended_tas.csv`
- Modify: `ODIN_app_for_splunk/lookups/odin_log_sources.csv`

**Step 1: Research each technology on Splunkbase**

Search Splunkbase for each: "Prometheus Splunk", "Grafana Splunk add-on", "Zabbix Splunk", "Nagios Splunk", "Icinga Splunk", "Jaeger Splunk", "Datadog Splunk add-on", "Telegraf Splunk", "OTEL Splunk", "ntopng Splunk", "Cacti Splunk", "LibreNMS Splunk".

**Step 2: Research each technology on GitHub**

Search GitHub for: `splunk TA prometheus`, `splunk add-on grafana`, etc.

**Step 3: Update odin_recommended_tas.csv**

Add a row for each TA found. Use the status taxonomy above.

**Step 4: Update odin_log_sources.csv**

For each row where `host_role` is monitoring_server/monitoring_agent and `recommended_ta=none`, update to the found TA name.

**Step 5: Commit**

```bash
git add ODIN_app_for_splunk/lookups/odin_recommended_tas.csv ODIN_app_for_splunk/lookups/odin_log_sources.csv
git commit -m "feat(lookups): add monitoring TA coverage from Splunkbase/GitHub research"
```

---

## Task 2: Message Brokers & Streaming

**Technologies:** RabbitMQ, Apache Kafka, ActiveMQ, Mosquitto, NATS, Apache Pulsar, ZeroMQ

**Affected host_roles:** rabbitmq_server, kafka_server, activemq_server, mosquitto_server, nats_server, message_broker

**Steps:** Same pattern as Task 1. Search Splunkbase and GitHub for each technology. Update both CSVs. Commit.

---

## Task 3: CI/CD, Artifacts & Version Control

**Technologies:** Jenkins, GitLab (Runner + Server), Gitea, Nexus, Artifactory, Drone, Concourse, SonarQube, ArgoCD, Flux

**Affected host_roles:** jenkins_server, gitlab_server, gitea_server, cicd_server

**Steps:** Same pattern. Commit message: `"feat(lookups): add CI/CD TA coverage from Splunkbase/GitHub research"`

---

## Task 4: Databases (Gaps)

**Technologies:** PostgreSQL (gap), MongoDB (gap), Redis, Memcached, Elasticsearch, OpenSearch, CockroachDB, ScyllaDB, TimescaleDB, InfluxDB, Cassandra, CouchDB, Neo4j, ArangoDB, RethinkDB

**Affected host_roles:** database_server, cache_server, search_server

**Note:** PostgreSQL and MongoDB were `not_found` for official Splunk TAs. Redis, Memcached, Elasticsearch, OpenSearch also have `none`. Search for community/vendor alternatives.

**Steps:** Same pattern. Commit message: `"feat(lookups): add database/cache/search TA coverage from Splunkbase/GitHub research"`

---

## Task 5: VPN & Network Security

**Technologies:** OpenVPN, WireGuard, strongSwan, Tailscale, Nebula, ZeroTier, Pritunl, Squid proxy, Suricata (community gap), Snort (community gap), Zeek

**Affected host_roles:** vpn_server, proxy_server, ids_host

**Note:** Suricata and Snort were `not_found` for official TAs. The notes in `odin_recommended_tas.csv` already mention community alternatives -- verify and promote them.

**Steps:** Same pattern. Commit message: `"feat(lookups): add VPN/network security TA coverage from Splunkbase/GitHub research"`

---

## Task 6: Directory, Identity & Authentication

**Technologies:** OpenLDAP, FreeIPA, Keycloak, Authentik, Shibboleth, FreeRADIUS, SSSD, Kerberos (Linux), Vault (HashiCorp)

**Affected host_roles:** directory_server, identity_server, secrets_server

**Steps:** Same pattern. Commit message: `"feat(lookups): add directory/identity TA coverage from Splunkbase/GitHub research"`

---

## Task 7: Application Servers & Runtimes

**Technologies:** Tomcat, WildFly/JBoss, Jetty, Gunicorn, uWSGI, PHP-FPM, PM2, Node.js

**Affected host_roles:** tomcat_server, wildfly_server, jetty_server, application_server

**Steps:** Same pattern. Commit message: `"feat(lookups): add application server TA coverage from Splunkbase/GitHub research"`

---

## Task 8: Container & Orchestration (Gaps)

**Technologies:** Docker (gap), Podman, CRI-O, K3s, RKE2, Harbor, Consul, Nomad

**Affected host_roles:** container_host, orchestration_server

**Note:** Docker was `not_found`. Kubernetes is `deprecated`. Search for current replacements and container runtime TAs.

**Steps:** Same pattern. Commit message: `"feat(lookups): add container/orchestration TA coverage from Splunkbase/GitHub research"`

---

## Task 9: Log Shippers & Aggregation

**Technologies:** Filebeat, Fluent-bit, Fluentd, Promtail, Vector, Logstash, Graylog, Grafana Loki

**Affected host_roles:** log_shipper, logstash_server, loki_log_aggregator

**Steps:** Same pattern. Commit message: `"feat(lookups): add log shipper TA coverage from Splunkbase/GitHub research"`

---

## Task 10: DNS (Gaps)

**Technologies:** Unbound, Dnsmasq, CoreDNS, PowerDNS, Knot, Pi-hole

**Affected host_roles:** dns_server (partial -- BIND already covered)

**Steps:** Same pattern. Commit message: `"feat(lookups): add DNS TA coverage from Splunkbase/GitHub research"`

---

## Task 11: Mail (Gaps)

**Technologies:** Dovecot, Exim4 (Postfix/Sendmail already covered via Splunk_TA_nix)

**Affected host_roles:** mail_server (partial)

**Steps:** Same pattern. Commit message: `"feat(lookups): add mail TA coverage from Splunkbase/GitHub research"`

---

## Task 12: Infrastructure & Storage

**Technologies:** Ceph, GlusterFS, MinIO, DRBD, iSCSI, NFS, Samba/SMB, Corosync, Pacemaker, Bacula, Bareos, Borg, Restic, libvirtd, QEMU, CUPS, Asterisk, FreeSWITCH, Mattermost, Nextcloud, Cockpit, Webmin, Airflow, NiFi, Kong, APISIX

**Affected host_roles:** storage_server, nfs_server, file_server, ha_cluster, backup_server, virtualization_host, print_server, telephony_server, collaboration_server, management_server, data_pipeline, api_gateway

**Note:** This is the "long tail" -- many niche technologies. Some will have GitHub-only TAs, many will remain `none`. That's OK -- documenting the gap is valuable.

**Steps:** Same pattern. Commit message: `"feat(lookups): add infrastructure TA coverage from Splunkbase/GitHub research"`

---

## Task 13: Security Tools (Gaps)

**Technologies:** Wazuh, SentinelOne, Cylance, Tanium, Qualys, Nessus/Tenable, OSSEC, ClamAV, Sophos, McAfee/Trellix

**Affected host_roles:** security_endpoint, security_host, security_scanner, nessus_server

**Note:** Some of these (CrowdStrike, Carbon Black, Symantec, Defender) are already covered. Check for gaps in the EDR/AV space.

**Steps:** Same pattern. Commit message: `"feat(lookups): add security tools TA coverage from Splunkbase/GitHub research"`

---

## Task 14: Windows Ecosystem (Verify & Expand)

**Technologies:** Verify all Windows services currently mapped to `Splunk_TA_windows` and check if there are more specialized TAs (e.g., Splunk Add-on for Active Directory, Splunk Add-on for IIS).

**Affected host_roles:** domain_controller, rdp_server, windows_management, windows_host, certificate_server

**Note:** `Splunk_TA_windows` covers 29 rows. Check if Splunk has dedicated TAs for AD, IIS, DHCP Server, DNS Server, etc. that provide richer field extractions.

**Steps:** Same pattern. Commit message: `"feat(lookups): verify and expand Windows TA coverage"`

---

## Task 15: Final Validation & Cleanup

**Files:**
- Read: `ODIN_app_for_splunk/lookups/odin_recommended_tas.csv`
- Read: `ODIN_app_for_splunk/lookups/odin_log_sources.csv`

**Step 1: Validate CSV integrity**

```bash
# Check header consistency
head -1 ODIN_app_for_splunk/lookups/odin_recommended_tas.csv
head -1 ODIN_app_for_splunk/lookups/odin_log_sources.csv

# Check for orphaned TAs (in log_sources but not in recommended_tas)
# Check for duplicate rows
```

**Step 2: Coverage report**

Calculate updated coverage:
- Count rows in `odin_log_sources.csv` where `recommended_ta != none`
- Count distinct TAs in `odin_recommended_tas.csv` by status
- Compare before/after coverage percentages

**Step 3: Update dashboard and saved searches if needed**

If new TAs are added that change the TA Deployment Matrix output, verify the dashboard still renders correctly.

**Step 4: Update transforms.conf if CSV columns changed**

The `github_url` column was added to `odin_recommended_tas.csv` -- no transforms.conf change needed (Splunk auto-detects CSV columns).

**Step 5: Update CHANGEHISTORY.md**

Add v2.2.2 entry documenting the coverage expansion.

**Step 6: Commit**

```bash
git add ODIN_app_for_splunk/lookups/ DOCS/CHANGEHISTORY.md
git commit -m "docs: add v2.2.2 TA coverage expansion to change history"
```

---

## Expected Outcomes

| Metric | Before | Target |
|--------|--------|--------|
| Rows with `recommended_ta=none` | 179/275 (65%) | <100/275 (<36%) |
| Distinct TAs in reference lookup | 22 | 60+ |
| Host roles with zero TA coverage | 30+ | <10 |
| Status breakdown | 14 official, 1 deprecated, 7 not_found | 14 official, 15+ vendor/community, 10+ github, <10 none |
