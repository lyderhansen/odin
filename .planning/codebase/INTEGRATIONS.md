# External Integrations

**Analysis Date:** 2026-04-10

## APIs & External Services

**No outbound HTTP/API integrations.** TA-ODIN performs zero network calls to external services. It does not contact Splunkbase, cloud providers, vendor APIs, or any remote HTTP endpoint. All discovery is local to the endpoint. The only "external" data path is the forwarder-to-indexer channel, which uses Splunk's native S2S/splunktcp protocol managed by the Universal Forwarder itself — not by TA-ODIN code.

**Splunk platform integrations (native, not HTTP):**

- **Splunk Universal Forwarder → Indexer pipeline**
  - Direction: Outbound from endpoint
  - Mechanism: Scripted input in `TA-ODIN/default/inputs.conf` (`[script://./bin/odin.sh]`) produces stdout key=value events; UF forwards via standard splunktcp to configured indexers.
  - Payload: Space-separated `key=value` lines, sourcetype `odin:enumeration`, routed to index `odin_discovery`.
  - Auth: Managed entirely by the UF (outputs.conf, certificates). TA-ODIN handles no credentials.

- **Splunk Deployment Server (current + planned Phase 3)**
  - Current: TA-ODIN is distributed to UFs via DS `deployment_apps/`.
  - Phase 3 goal (per `CLAUDE.md`): Auto-generate `serverclass.conf` stanzas from `ODIN_app_for_splunk/lookups/odin_host_inventory.csv` and `odin_log_sources.csv`.

## Data Storage

**Databases:**
- **Splunk index `odin_discovery`** — Sole datastore. Defined in `ODIN_app_for_splunk/default/indexes.conf`.
  - Paths: `$SPLUNK_DB/odin_discovery/{db,colddb,thaweddb}`
  - Retention: `frozenTimePeriodInSecs = 31536000` (1 year)
  - Size cap: `maxTotalDataSizeMB = 1024`

**File Storage:**
- Local endpoint filesystem reads only: `/etc/crontab`, `/etc/cron.d/`, `/etc/cron.{hourly,daily,weekly,monthly}/`, `/var/spool/cron/crontabs/`, `/var/spool/cron/`, `/etc/anacrontab`, `/etc/os-release`, `/etc/init.d/`.
- Splunk lookup CSVs at `ODIN_app_for_splunk/lookups/`.
- Generated lookups written by saved searches via `| outputlookup`: `odin_host_inventory.csv`, `odin_log_source_details.csv` (see `ODIN_app_for_splunk/default/savedsearches.conf`).
- No object storage, no cloud buckets.

**Caching:** None. Each run is stateless and tagged with `ODIN_RUN_ID`.

## Authentication & Identity

- No auth provider for TA-ODIN itself. Forwarder-to-indexer authentication is Splunk's built-in mechanism.
- Endpoint privilege tracking: `TA-ODIN/bin/odin.sh` sets `ODIN_RUNNING_AS_ROOT` from `$EUID`. Non-root limits visibility for port PIDs (`TA-ODIN/bin/modules/ports.sh`) and user crontabs (`TA-ODIN/bin/modules/cron.sh`). Modules emit `type=privilege_warning` events when degraded.

## Monitoring & Observability

**Error Tracking:**
- No external tracking service (no Sentry/Datadog/etc.).
- Structured error events emitted in-band to `odin_discovery`:
  - `type=odin_error` — module failures, 30s timeouts, missing modules directory
  - `type=odin_warning` — non-root warnings
  - `type=privilege_warning` — per-module permission degradation
  - `type=truncated` — `ODIN_MAX_EVENTS` (50,000) cap hit
  - `type=none_found` — module completed empty
  - `type=odin_start` / `type=odin_complete` — run markers with module totals

**Logs:**
- All stdout goes via Splunk UF to `index=odin_discovery sourcetype=odin:enumeration`. No separate log file.
- UF's `splunkd.log` captures script execution, exit codes, and script-timeout events.

## CI/CD & Deployment

**Hosting:**
- Source: GitHub `https://github.com/lyderhansen/odin.git`, branch `main`.
- Ships as two Splunk app directories.

**CI Pipeline:**
- None detected. No `.github/workflows/`, no GitLab CI, no Jenkinsfile, no pre-commit config in the repo.

**Deployment Flow:**
1. `TA-ODIN/` → Splunk Deployment Server `deployment_apps/TA-ODIN/` → Linux UFs via serverclass.
2. `ODIN_app_for_splunk/` → installed directly on indexers (for `indexes.conf`) and search heads (for lookups, props, transforms, savedsearches, dashboard).
3. Scripted input fires on first check-in, then every 30 days (`interval = 2592000` in `TA-ODIN/default/inputs.conf`).

## Environment Configuration

**Required env vars:** None at operator level. All `ODIN_*` variables are set internally by `TA-ODIN/bin/odin.sh` and exported to modules. Modules honor the variables standalone for testing: `ODIN_HOSTNAME`, `ODIN_OS`, `ODIN_RUN_ID`, `ODIN_VERSION`, `ODIN_MAX_EVENTS`. `LC_ALL=C` is forced by every script.

**Secrets location:** None. TA-ODIN stores and uses zero secrets.

## Webhooks & Callbacks

Incoming: None. Outgoing: None.

## Host OS Command Integrations

| Subsystem | Commands / Paths | Module |
|-----------|------------------|--------|
| systemd services | `systemctl show --type=service --all --property=Id,ActiveState,SubState,Type,UnitFileState` | `TA-ODIN/bin/modules/services.sh` |
| SysV init | `service --status-all`, `/etc/init.d/<name> status` | `TA-ODIN/bin/modules/services.sh` |
| Listening ports | `ss -tulpn`, `netstat -tulpn` (fallback) | `TA-ODIN/bin/modules/ports.sh` |
| Debian packages | `dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n'` | `TA-ODIN/bin/modules/packages.sh` |
| RPM packages | `rpm -qa --queryformat '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\n'` | `TA-ODIN/bin/modules/packages.sh` |
| Alpine packages | `apk list --installed`, `apk info -v` | `TA-ODIN/bin/modules/packages.sh` |
| Arch packages | `pacman -Q` | `TA-ODIN/bin/modules/packages.sh` |
| Distro detection | `/etc/os-release` (ID, ID_LIKE) | `TA-ODIN/bin/modules/packages.sh` |
| System crontab | `/etc/crontab` | `TA-ODIN/bin/modules/cron.sh` |
| Drop-in cron | `/etc/cron.d/*` | `TA-ODIN/bin/modules/cron.sh` |
| User crontabs | `/var/spool/cron/crontabs/`, `/var/spool/cron/` | `TA-ODIN/bin/modules/cron.sh` |
| Periodic cron | `/etc/cron.{hourly,daily,weekly,monthly}/` | `TA-ODIN/bin/modules/cron.sh` |
| systemd timers | `systemctl list-timers --all`, batch `systemctl show --property=Id,TimersCalendar,TimersMonotonic` | `TA-ODIN/bin/modules/cron.sh` |
| Anacron | `/etc/anacrontab` | `TA-ODIN/bin/modules/cron.sh` |
| Processes | `ps -eo pid,ppid,user,stat,%cpu,%mem,etime,comm,args`, fallback `ps -ef` / `ps aux` | `TA-ODIN/bin/modules/processes.sh` |
| Mounts | `df -PT`, `df -P`, `df` (fallback chain) | `TA-ODIN/bin/modules/mounts.sh` |
| Identity | `hostname -f`, `id -un`, `$EUID` | `TA-ODIN/bin/odin.sh` |

All external commands are wrapped in `timeout` (5–30 seconds) to prevent hangs on broken systemd units, dpkg locks, or unresponsive NFS mounts.

## Splunk Search-time Integrations

- **Splunk Common Information Model (CIM)** — `ODIN_app_for_splunk/default/props.conf` defines `FIELDALIAS-dest = hostname AS dest` and `FIELDALIAS-dvc = hostname AS dvc`, making ODIN events compatible with CIM data models referencing `dest`/`dvc`.

- **Automatic classification lookups** (declared in `ODIN_app_for_splunk/default/transforms.conf`, bound via `LOOKUP-*` stanzas in `ODIN_app_for_splunk/default/props.conf`):
  - `odin_classify_services` — WILDCARD match on `service_name` → `service_category`, `service_subcategory`, `service_vendor`, `service_role`, `service_description`. Backed by `ODIN_app_for_splunk/lookups/odin_classify_services.csv`.
  - `odin_classify_ports` — Exact match on `listen_port` + `transport` → `expected_service`, `port_category`, `port_description`. Backed by `ODIN_app_for_splunk/lookups/odin_classify_ports.csv`.
  - `odin_classify_packages` — WILDCARD match on `package_name` → `package_category`, `package_vendor`, `package_role`, `package_description`. Backed by `ODIN_app_for_splunk/lookups/odin_classify_packages.csv`.

- **Explicit `| lookup` inside saved searches** (`ODIN_app_for_splunk/default/savedsearches.conf`):
  - `odin_log_sources` — Maps `(signal_type, signal_value)` tuples to `host_role`, `log_source`, `sourcetype`, `recommended_ta`, `log_path`. Backed by `ODIN_app_for_splunk/lookups/odin_log_sources.csv`.
  - `odin_recommended_tas` — Enriches `recommended_ta` with Splunkbase metadata (`splunkbase_id`, `splunkbase_url`, `official_name`, `status`). Backed by `ODIN_app_for_splunk/lookups/odin_recommended_tas.csv`.

- **Generated lookups** produced by scheduled saved searches:
  - `odin_host_inventory.csv` — cron `5 1 * * *`, per-host roles / log sources / recommended TAs.
  - `odin_log_source_details.csv` — cron `10 1 * * *`, per-host signal breakdown.
  - TA Deployment Matrix — cron `15 1 * * *`, runtime search result (not persisted as a lookup).

- **Splunkbase metadata** is stored as static reference data in `ODIN_app_for_splunk/lookups/odin_recommended_tas.csv`. TA-ODIN does not call the Splunkbase API; the CSV is hand-curated.
