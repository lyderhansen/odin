# TA-ODIN Change History

All entries use ISO 8601 timestamps in CET timezone.

---

## v2.0.1 - Portability & Observability Improvements

### none_found events - All modules now report when nothing is discovered
[2026-02-21T22:00:00+01:00] - Added event_type=none_found to all modules when no results are discovered
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
