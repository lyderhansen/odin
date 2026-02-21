# TA-ODIN Change History

All entries use ISO 8601 timestamps in CET timezone.

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
