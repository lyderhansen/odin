# TA-ODIN Change History

All entries use ISO 8601 timestamps in CET timezone.

---

## v2.2.0 - Phase 2: Host Role Classification & Log Source Identification

### Log source mapping lookup
[2026-02-21T22:00:00+01:00] - Created ODIN_app_for_splunk/lookups/odin_log_sources.csv (~95 rows)
[2026-02-21T22:00:00+01:00] - Maps discovery signals (service, port, package) to host roles, log sources, sourcetypes, and recommended TAs
[2026-02-21T22:00:00+01:00] - Covers: web servers, load balancers, databases, syslog, cache, search engines, containers/Kubernetes, security tools, logging infrastructure, DNS, mail, monitoring, VPN, proxies, message brokers, CI/CD, SSH, file servers, directory services, secrets management
[2026-02-21T22:00:00+01:00] - Added odin_log_sources lookup definition to transforms.conf

### Saved searches for host classification
[2026-02-21T22:00:00+01:00] - Created ODIN_app_for_splunk/default/savedsearches.conf with 3 scheduled searches
[2026-02-21T22:00:00+01:00] - "ODIN - Host Inventory": Aggregates signals per host into roles/TAs, outputs odin_host_inventory.csv (daily at 01:05)
[2026-02-21T22:00:00+01:00] - "ODIN - Log Source Details": Per-host breakdown of roles/log sources, outputs odin_log_source_details.csv (daily at 01:10)
[2026-02-21T22:00:00+01:00] - "ODIN - TA Deployment Matrix": Actionable TA-to-host mapping for Deployment Server planning (daily at 01:15)

### Configuration updates
[2026-02-21T22:00:00+01:00] - Bumped ODIN_app_for_splunk version to 2.2.0 in app.conf
[2026-02-21T22:00:00+01:00] - Bumped TA-ODIN version to 2.2.0 in app.conf
[2026-02-21T22:00:00+01:00] - Added savedsearches export to metadata/default.meta

### Documentation
[2026-02-21T22:00:00+01:00] - Updated ARCHITECTURE.md with Phase 2 classification layer and data flow
[2026-02-21T22:00:00+01:00] - Updated CLAUDE.md with Phase 2 status, log source lookup docs, and verification queries

---

## v2.1.0 - Two-App Split & Script Guardrails

### ODIN_app_for_splunk - New indexer/search head app
[2026-02-22T01:00:00+01:00] - Created ODIN_app_for_splunk as standalone indexer/search head app
[2026-02-22T01:00:00+01:00] - Moved indexes.conf from TA-ODIN to ODIN_app_for_splunk
[2026-02-22T01:00:00+01:00] - Moved transforms.conf from TA-ODIN to ODIN_app_for_splunk
[2026-02-22T01:00:00+01:00] - Moved all classification lookup CSVs from TA-ODIN to ODIN_app_for_splunk
[2026-02-22T01:00:00+01:00] - Created full props.conf in ODIN_app_for_splunk (parsing + KV_MODE + CIM aliases + lookup bindings)
[2026-02-22T01:00:00+01:00] - Created metadata/default.meta exporting lookups, props, transforms to system scope
[2026-02-22T01:00:00+01:00] - Deleted odin_rules_windows.csv (dead v1 artifact)

### TA-ODIN slimmed down - Forwarder-only app
[2026-02-22T01:00:00+01:00] - Removed indexes.conf from TA-ODIN (now in ODIN_app_for_splunk)
[2026-02-22T01:00:00+01:00] - Removed transforms.conf from TA-ODIN (now in ODIN_app_for_splunk)
[2026-02-22T01:00:00+01:00] - Removed lookups/ directory from TA-ODIN (now in ODIN_app_for_splunk)
[2026-02-22T01:00:00+01:00] - Slimmed props.conf to line-breaking and timestamp only (forwarder-minimal)
[2026-02-22T01:00:00+01:00] - Updated app.conf to v2.1.0, references ODIN_app_for_splunk as companion app

### Privilege awareness - Non-root warnings
[2026-02-22T02:00:00+01:00] - odin.sh: Added EUID check, emits type=odin_warning for ports and cron when running as non-root
[2026-02-22T02:00:00+01:00] - odin.sh: Start event now includes run_as= and euid= fields for audit trail
[2026-02-22T02:00:00+01:00] - ports.sh: Emits type=privilege_warning with counts when ports are missing process info due to non-root
[2026-02-22T02:00:00+01:00] - cron.sh: Emits type=privilege_warning when /var/spool/cron/crontabs is unreadable (non-root)
[2026-02-22T02:00:00+01:00] - Created DOCS/COMMANDS.md: Full command reference with root vs non-root expected output

### Script guardrails - Per-module timeout and MAX_EVENTS
[2026-02-22T01:00:00+01:00] - odin.sh: Added per-module 90s timeout via `timeout` command (leaves 30s margin within Splunk's 120s)
[2026-02-22T01:00:00+01:00] - odin.sh: Added MAX_EVENTS cap of 50,000 per module in emit() function
[2026-02-22T01:00:00+01:00] - odin.sh: Emits type=truncated warning when MAX_EVENTS cap is hit
[2026-02-22T01:00:00+01:00] - odin.sh: Resets ODIN_EVENT_COUNT and ODIN_EVENTS_TRUNCATED per module run

### Script guardrails - Batch systemctl queries
[2026-02-22T01:00:00+01:00] - services.sh: Replaced per-unit systemctl is-enabled + systemctl show calls with single batch `systemctl show --type=service --all`
[2026-02-22T01:00:00+01:00] - services.sh: Parses blank-line-separated property blocks (Id, ActiveState, SubState, Type, UnitFileState)
[2026-02-22T01:00:00+01:00] - cron.sh: Replaced per-timer systemctl show calls with single batch `systemctl show` for all timer units
[2026-02-22T01:00:00+01:00] - cron.sh: Collects timer unit names first, then batch queries TimersCalendar/TimersMonotonic

### Script guardrails - Command timeouts
[2026-02-22T01:00:00+01:00] - services.sh: Added timeout 30 to systemctl show batch query
[2026-02-22T01:00:00+01:00] - services.sh: Added timeout 30 to `service --status-all` fallback
[2026-02-22T01:00:00+01:00] - services.sh: Added timeout 5 per init.d script status check (prevents hanging on broken scripts)
[2026-02-22T01:00:00+01:00] - ports.sh: Added timeout 30 to `ss -tulpn` and `netstat -tulpn`
[2026-02-22T01:00:00+01:00] - packages.sh: Added timeout 30 to dpkg-query, rpm, apk, and pacman commands
[2026-02-22T01:00:00+01:00] - processes.sh: Added timeout 30 to all ps invocations
[2026-02-22T01:00:00+01:00] - cron.sh: Added timeout 30 to systemctl list-timers and batch systemctl show

### Script guardrails - Eliminated redundant subprocess calls
[2026-02-22T01:00:00+01:00] - processes.sh: Removed double ps invocation (was: test ps then run ps again). Now captures output once and parses from variable.

### Documentation
[2026-02-22T01:00:00+01:00] - Updated CLAUDE.md: Renamed ODIN → ODIN_app_for_splunk throughout, added guardrails section and environment variables
[2026-02-22T01:00:00+01:00] - Updated ARCHITECTURE.md: Renamed ODIN → ODIN_app_for_splunk, marked configs as Complete, added guardrails table
[2026-02-22T01:00:00+01:00] - Updated TA-ODIN/README.md: References ODIN_app_for_splunk, updated version to 2.1.0
[2026-02-22T01:00:00+01:00] - Created ODIN_app_for_splunk/README.md with installation and usage docs
[2026-02-22T01:00:00+01:00] - All scripts: Updated ODIN_VERSION fallback to 2.1.0

---

## v2.0.1 (continued) - Two-App Architecture

### Architecture decision - Separate forwarder and indexer/search head apps
[2026-02-22T00:00:00+01:00] - Documented two-app deployment architecture in CLAUDE.md and ARCHITECTURE.md
[2026-02-22T00:00:00+01:00] - TA-ODIN: Forwarder app (collection) - deployed via deployment_apps/ on Deployment Server
[2026-02-22T00:00:00+01:00] - ODIN: Indexer/Search Head app (visualization & reporting) - TODO, will contain indexes.conf, lookups, dashboards, saved searches
[2026-02-22T00:00:00+01:00] - Updated ARCHITECTURE.md with two-app data flow diagram and split config tables
[2026-02-22T00:00:00+01:00] - Updated repository structure in CLAUDE.md and ARCHITECTURE.md to show both apps

---

## v2.0.1 - Portability & Observability Improvements

### none_found events - All modules now report when nothing is discovered
[2026-02-21T22:00:00+01:00] - Added type=none_found to all modules when no results are discovered
[2026-02-21T22:00:00+01:00] - cron.sh: Added emitted tracking and none_found event (No scheduled tasks found)
[2026-02-21T22:00:00+01:00] - services.sh: Added none_found event when no services discovered
[2026-02-21T22:00:00+01:00] - ports.sh: Added none_found event when no listening ports discovered
[2026-02-21T22:00:00+01:00] - packages.sh: Added none_found event when no packages found, replaced package_error with none_found for consistency
[2026-02-21T22:00:00+01:00] - processes.sh: Added none_found event when no processes found
[2026-02-21T22:00:00+01:00] - mounts.sh: Added none_found event when no mounts found

### Portability fixes - Compatibility across Linux distros and minimal installs
[2026-02-21T22:00:00+01:00] - odin.sh: Added bash availability check with clear error event if bash is not installed
[2026-02-21T22:00:00+01:00] - packages.sh: Replaced grep -oP (PCRE) with POSIX-compatible sed for /etc/os-release parsing
[2026-02-21T22:00:00+01:00] - packages.sh: Fixed apk package name parsing for packages with multiple hyphens (e.g. perl-test-warn-0.32-r0)
[2026-02-21T22:00:00+01:00] - packages.sh: Added apk list --installed support as preferred method with apk info -v fallback
[2026-02-21T22:00:00+01:00] - processes.sh: Added three-tier ps fallback (GNU ps -eo → BusyBox ps -o → basic ps -ef/aux)
[2026-02-21T22:00:00+01:00] - mounts.sh: Added df flag detection with fallback chain (df -PT → df -P → df) for BusyBox/minimal systems
[2026-02-21T22:00:00+01:00] - mounts.sh: Added timeout command detection - skips timeout gracefully if not available
[2026-02-21T22:00:00+01:00] - processes.sh, mounts.sh, packages.sh: Changed pipe-based while loops to process substitution to fix variable scoping

### Hardening - Locale, performance, and correctness fixes for production deployment
[2026-02-21T23:00:00+01:00] - All modules + odin.sh: Added export LC_ALL=C to prevent locale-dependent output parsing failures on non-English systems
[2026-02-21T23:00:00+01:00] - mounts.sh: Fixed mount point parsing - mount points with spaces (e.g. /mnt/my share) are now correctly captured using read instead of awk
[2026-02-21T23:00:00+01:00] - packages.sh: Removed dead code in apk parsing (redundant sed calls that were overwritten by parameter expansion)
[2026-02-21T23:00:00+01:00] - services.sh, ports.sh: Added safe_val() function for consistent value escaping
[2026-02-21T23:00:00+01:00] - services.sh, ports.sh: Applied safe_val() to service_name and process_name output fields
[2026-02-21T23:00:00+01:00] - All modules: Replaced multiple awk calls per line with bash read builtin for field splitting (major performance improvement on systems with 1000+ items)
[2026-02-21T23:00:00+01:00] - cron.sh: Refactored /etc/crontab and /etc/cron.d parsing into shared parse_system_cron_line() function, eliminating code duplication
[2026-02-21T23:00:00+01:00] - cron.sh: Replaced awk-based field extraction with read -r in parse_cron_line(), parse_system_cron_line(), and anacron parsing
[2026-02-21T23:00:00+01:00] - cron.sh: Replaced awk-based systemd timer field extraction with bash array indexing for last two fields
[2026-02-21T23:00:00+01:00] - odin.sh: Exit code now reflects module failures (exit 1 if any module failed, exit 0 if all succeeded)

### Output changes
[2026-02-21T23:30:00+01:00] - All scripts + documentation: Renamed event_type= field to type= in all output for brevity
[2026-02-21T23:30:00+01:00] - Updated CLAUDE.md, README.md, and CHANGEHISTORY.md to reflect type= field name

### Documentation
[2026-02-21T23:30:00+01:00] - Created DOCS/ARCHITECTURE.md with ASCII project structure, data flow diagram, and full file reference

---

## v2.0.0 - Full Enumeration Restructure

[2026-02-21T15:00:00+01:00] - Restructured TA-ODIN from CSV-rule-based detection to full host enumeration architecture
[2026-02-21T15:00:00+01:00] - Rewrote odin.sh as thin orchestrator with modular autodiscovery (bin/modules/*.sh)
[2026-02-21T15:00:00+01:00] - Added ODIN_* environment variables for module context (ODIN_HOSTNAME, ODIN_OS, ODIN_RUN_ID, ODIN_VERSION)
[2026-02-21T15:00:00+01:00] - Added unique run_id per execution (epoch-PID format)
[2026-02-21T15:00:00+01:00] - Changed output format from comma-separated to space-separated key=value pairs
[2026-02-21T15:00:00+01:00] - Added module: services.sh - Full service enumeration via systemctl/service/init.d
[2026-02-21T15:00:00+01:00] - Added module: ports.sh - Listening port enumeration via ss/netstat
[2026-02-21T15:00:00+01:00] - Added module: packages.sh - Installed package enumeration (dpkg/rpm/apk/pacman)
[2026-02-21T15:00:00+01:00] - Added module: cron.sh - Scheduled task enumeration (crontab/systemd timers/anacron)
[2026-02-21T15:00:00+01:00] - Added module: processes.sh - Running process enumeration via ps
[2026-02-21T15:00:00+01:00] - Added module: mounts.sh - Filesystem/mount enumeration via df
[2026-02-21T15:00:00+01:00] - Replaced odin_rules_linux.csv with classification lookups (odin_classify_services.csv, odin_classify_ports.csv, odin_classify_packages.csv)
[2026-02-21T15:00:00+01:00] - Added new sourcetype odin:enumeration (replaces odin:discovery)
[2026-02-21T15:00:00+01:00] - Added search-time lookup transforms for automatic classification enrichment
[2026-02-21T15:00:00+01:00] - Updated app.conf to version 2.0.0
[2026-02-21T15:00:00+01:00] - Added script timeout of 120 seconds in inputs.conf
[2026-02-21T15:00:00+01:00] - Created DOCS/ directory for project documentation
[2026-02-21T15:00:00+01:00] - Updated CLAUDE.md with v2.0 architecture decisions and project vision
[2026-02-21T15:00:00+01:00] - Updated README.md with new architecture, output format, and classification documentation

---

## v1.0.0 - Initial Release

[2025-01-09T00:00:00+01:00] - Initial release with Linux file/service discovery
[2025-01-09T00:00:00+01:00] - CSV-driven rule-based detection for files and services
[2025-01-09T00:00:00+01:00] - ~187 detection rules for Linux
[2025-01-09T00:00:00+01:00] - Splunk configuration with odin:discovery sourcetype
