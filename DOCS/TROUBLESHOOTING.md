# TA-ODIN Troubleshooting

Common failure modes per OS, with symptom / diagnostic / fix triples. Audience: Splunk
admin who already knows `splunk btool`, `splunkd.log`, Deployment Server semantics.
For alert-driven response procedures (after activation) see `DOCS/RUNBOOK.md`.

## Linux

### Issue: orchestrator never runs

**Symptom:** No `odin:enumeration` events from a host that previously scanned, or no
events ever from a fresh deploy.

**Diagnostic:**

```bash
splunk list forward-server
splunk btool inputs list 'script://./bin/odin.sh' --debug
ls -l $SPLUNK_HOME/etc/apps/TA-ODIN/bin/odin.sh
```

The `btool` output should show `disabled = false`. If `disabled = true` is sourced from
a `local/inputs.conf`, the rollback overlay is still active — see `DOCS/ROLLBACK.md`
"Reverting the rollback".

**Fix:** Confirm Deployment Server pushed `TA-ODIN/` to the UF (`ls $SPLUNK_HOME/etc/apps/`
should list it), bind to the right serverclass (`splunk btool serverclass list --debug |
grep -i ta-odin`), and `splunk reload deploy-server` from the DS. If the file is present
but not executable, `chmod +x $SPLUNK_HOME/etc/apps/TA-ODIN/bin/odin.sh
$SPLUNK_HOME/etc/apps/TA-ODIN/bin/modules/*.sh`.

### Issue: services.sh reports zero services

**Symptom:** `index=odin_discovery type=service` returns empty for a Linux host known to
run services.

**Diagnostic:**

```bash
ssh <host> 'systemctl list-units --failed; systemctl list-units --type=service --all | head'
```

If `systemctl list-units --failed` shows units in an `auto-restart` loop or `loaded
failed`, the batch `systemctl show` query in `services.sh` may be timing out before
returning useful data.

**Fix:** Resolve the underlying failed-unit state per organization change-control. The
module's 30s `timeout` wrapper prevents the orchestrator from blocking; missing data is
the cost. For non-systemd hosts (SysV init), the `service --status-all` and
`/etc/init.d/<script> status` fallbacks should still produce output — verify via
`bash TA-ODIN/bin/modules/services.sh` standalone (see `DOCS/COMMANDS.md`).

### Issue: packages.sh hangs / times out

**Symptom:** `type=odin_error module=packages exit_code=124` events on Debian/Ubuntu
hosts during `unattended-upgrades` cycles.

**Diagnostic:**

```bash
ssh <host> 'sudo lsof /var/lib/dpkg/lock-frontend; ps -ef | grep -E "apt|dpkg|unattended"'
```

A held lock means another package operation is in progress (typically
`unattended-upgrades` or a manual `apt install`).

**Fix:** Wait for the holding process to finish, or kill it per change-control policy.
The 30s `dpkg-query` timeout is intentional — raising it just hides the symptom.
Persistent contention indicates the host's update window overlaps the TA-ODIN scan
interval; consider shifting `interval` in a `local/inputs.conf` overlay so scans land
outside the typical maintenance window.

### Issue: mounts.sh slow on hosts with hung NFS

**Symptom:** `type=odin_error module=mounts exit_code=124` events, or `type=mount_error
message="df command timed out after 30 seconds (possible hung NFS mount)"` events.

**Diagnostic:**

```bash
ssh <host> 'dmesg | grep -iE "nfs|stale" | tail; df 2>/dev/null'
```

Kernel `nfs: server <name> not responding` or `stale file handle` messages confirm a
hung NFS mount. The `df` command blocks on `stat()` for any unresponsive mount.

**Fix:** `umount -f -l <hung-mount>` per change-control. If the NFS server is
permanently gone, remove the entry from `/etc/fstab`. The `mounts.sh` 30s timeout
prevents the orchestrator from blocking; a `mount_error` event in lieu of mount data is
the documented degraded behavior.

### Issue: type=truncated events from processes.sh

**Symptom:** `type=truncated message="Event limit reached (max=50000) ..."` events on
container hosts or build servers.

**Diagnostic:**

```spl
index=odin_discovery sourcetype=odin:enumeration type=truncated module=processes
| stats count by hostname
| sort -count
```

Hosts with 50k+ running processes are typically container hosts (thousands of
short-lived shells), broken process-supervisor loops, or fork bombs.

**Fix:** For legitimate high-cardinality hosts (build servers, container nodes), raise
`ODIN_MAX_EVENTS` for that host class via `local/inputs.conf` overlay:

```ini
[script://./bin/odin.sh]
env.ODIN_MAX_EVENTS = 200000
```

Push via Deployment Server scoped to the affected serverclass. For pathological
cardinality (fork bomb, runaway loop, suspected compromise) treat as security incident
— do NOT raise the cap, that hides the symptom. See `DOCS/RUNBOOK.md` "Alert: type=
truncated events" for the full triage flow.

## Windows

### Issue: odin.ps1 fails to launch under AppLocker / WDAC

**Symptom:** No events from Windows hosts; Splunk UF `splunkd.log` shows
`ExecProcessor: message from "powershell.exe ..." Cannot execute script` or similar.

**Diagnostic:**

```powershell
# On the affected host
Get-AppLockerPolicy -Effective -Xml | Select-String -Pattern "powershell|odin"
Get-WinEvent -LogName "Microsoft-Windows-AppLocker/MSI and Script" -MaxEvents 50 |
  Where-Object { $_.Message -match 'odin' }
```

WDAC blocks show under `Microsoft-Windows-CodeIntegrity/Operational`. Constrained
Language Mode shows `$ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage'`
when checked from a CLM-affected session.

**Fix:** Coordinate with the EDR/security team to add a publisher rule for the Splunk
UF (the script lives at `$SPLUNK_HOME\etc\apps\TA-ODIN\bin\odin.ps1` and is invoked via
`bin\odin.path`). TA-ODIN code is compatible with Constrained Language Mode by design
(WIN-10 / WIN-09: built-in cmdlets only, no `Add-Type`, no `Invoke-Expression`,
no base64-encoded commands), so once the publisher rule is in place no further
remediation is needed.

### Issue: packages.ps1 returns zero results

**Symptom:** `index=odin_discovery type=package` empty for Windows hosts.

**Diagnostic:**

```powershell
# On the affected host, run as the same identity as the UF (default LocalSystem)
psexec.exe -s powershell.exe -NoProfile -Command "Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' | Select-Object -First 5"
psexec.exe -s powershell.exe -NoProfile -Command "Get-ChildItem 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall' | Select-Object -First 5"
```

LocalSystem should have full read access to both registry hives. If `psexec -s` returns
"Access is denied", the security baseline has been hardened beyond default — uncommon
on member servers, sometimes seen on STIG'd workstations.

**Fix:** Verify the UF service is actually running as `LocalSystem` (default) and not
re-configured to a domain user. `Get-WmiObject Win32_Service -Filter "Name='SplunkForwarder'"
| Select-Object StartName`. If running as a domain user, grant that user Read on the
two `Uninstall` registry keys. TA-ODIN never enumerates via `Win32_Product` (WIN-04
constraint — `Win32_Product` triggers MSI self-repair on every query).

### Issue: scheduled_tasks.ps1 produces excessive noise on member servers

**Symptom:** Hundreds of `type=scheduled_task` events per scan, mostly built-in
Microsoft tasks (`\Microsoft\Windows\...`).

**Diagnostic:**

```spl
index=odin_discovery sourcetype=odin:enumeration type=scheduled_task
| stats count by task_path
| sort -count
```

Top entries dominated by `\Microsoft\Windows\<feature>\...` paths is the documented
default — every Windows install ships with 100+ built-in maintenance tasks.

**Fix:** This is **not a bug**. The classification layer in
`ODIN_app_for_splunk/lookups/odin_log_sources.csv` is responsible for filtering
non-actionable tasks at search time — the enumeration layer faithfully reports
everything per WIN-05. If the noise is interfering with downstream dashboards, add a
search-time `where NOT match(task_path, "^\\\\Microsoft\\\\Windows")` filter rather
than modifying the module.

### Issue: UAC edge cases on workstations causing modules to fail silently

**Symptom:** Sporadic missing events from Windows 10/11 workstations (vs Windows
Server hosts of the same patch level) — usually `services.ps1` or `packages.ps1`.

**Diagnostic:**

```powershell
# On the affected host
Get-WinEvent -LogName Application -MaxEvents 100 |
  Where-Object { $_.ProviderName -match 'Splunk|WUA' } |
  Format-List TimeCreated, LevelDisplayName, Message
```

Look for `WUAUCLT` or `splunkd` errors around the scan timestamp. UAC-elevated
operations from a non-elevated session manifest as silent failures rather than
explicit errors in PowerShell 5.1.

**Fix:** Verify the UF is running as `LocalSystem` (Windows workstations sometimes get
the UF reinstalled under the interactive user during imaging — that loses elevation
implicitly). If a domain-user service identity is required, ensure the user has
"Replace a process level token" + "Adjust memory quotas for a process" privileges via
local security policy (`secpol.msc` → User Rights Assignment).

## Cross-platform

### Issue: events appear in Splunk but host_role is null

**Symptom:** `| inputlookup odin_host_inventory.csv` produces rows but `host_roles`
column is empty for some hosts.

**Diagnostic:**

```spl
index=odin_discovery sourcetype=odin:enumeration (type=service OR type=port OR type=package)
hostname="<affected_host>"
| eval signal_type=type
| eval signal_value=case(type="service", service_name, type="port", listen_port."/".transport, type="package", package_name)
| lookup odin_log_sources signal_type, signal_value OUTPUT host_role
| stats count by host_role
```

If the lookup returns rows but every `host_role` is `null`, the host's emitted signals
don't match any `(signal_type, signal_value)` row in `odin_log_sources.csv`.

**Fix:** Add classification rows for the missing signals. For Windows hosts,
verify the row uses **D1-canonical** role names (`web_server`, `domain_controller`,
`database_server`, etc.) — NOT legacy values. The Phase 4 deferred items doc
(`.planning/phases/04-windows-classification-data/deferred-items.md` D-04-02)
documents ~23 pre-existing legacy Windows service rows in
`odin_classify_services.csv` that use the old taxonomy (`web` instead of `web_server`,
`directory` instead of `domain_controller`, etc.). Until that cleanup ships, the
service lookup may return `role=web` for IIS hosts while `odin_log_sources.csv`
returns `host_role=web_server` from the same signals — both values are correct for
the underlying host but the search-time normalization layer hasn't been written yet.

### Issue: odin_host_inventory.csv is stale

**Symptom:** `inputlookup odin_host_inventory.csv` last-modified timestamp predates
the most recent fleet scan by more than 24h.

**Diagnostic:**

```spl
| rest /servicesNS/-/-/saved/searches
| where match(title, "^ODIN")
| table title, disabled, cron_schedule, next_scheduled_time, latest_dispatch_status
```

The 3 nightly searches (`ODIN - Host Inventory`, `ODIN - Log Source Details`,
`ODIN - TA Deployment Matrix`) should each show `disabled=0` and a recent
`latest_dispatch_status`.

**Fix:** If `disabled=1`, re-enable via the search-head UI (Settings → Searches,
Reports, and Alerts) or `local/savedsearches.conf` overlay. If `latest_dispatch_status`
shows errors, drill into the dispatch logs (`Settings → Searches, Reports, and Alerts
→ <search-name> → Job History`). Common cause: search-time lookup unavailable
(`odin_log_sources` lookup definition missing or transforms.conf broken on the SH).

### Issue: AppInspect failure during release build

**Symptom:** `splunk-appinspect inspect ...` returns `failure > 0` or `error > 0` after
a docs or config change.

**Diagnostic:**

```bash
~/Library/Python/3.9/bin/splunk-appinspect inspect ODIN_app_for_splunk \
  --mode precert --excluded-tags cloud --output-file /tmp/appinspect.json --data-format json
python3 -c "import json; r=json.load(open('/tmp/appinspect.json')); print(json.dumps(r['summary'], indent=2))"
```

Inspect the failing rule names in the JSON output. Compare against the baseline at
`.planning/artifacts/appinspect/odin-app-phase05-wave0-plan02.json` (or the most
recent passing baseline) to identify what changed.

**Fix:** Most failures during Phase 5 docs work indicate an accidental config-file
change inside `ODIN_app_for_splunk/` or `TA-ODIN/`. `git diff -- ODIN_app_for_splunk/
TA-ODIN/` should reveal the culprit; revert and re-run. Docs under `DOCS/` and tools
under `tools/` are outside the AppInspect scan scope and cannot cause regressions
on their own.
