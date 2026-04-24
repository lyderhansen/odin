# TA-ODIN Installation

Deployment Server rollout playbook for both apps. Audience: Splunk admin who already
knows `serverclass.conf`, `splunk reload deploy-server`, `splunk apply cluster-bundle`,
and forwarder/indexer/search-head topology.

## Two-app split

The project ships two separate Splunk apps with different deployment targets. Full
architecture in `DOCS/ARCHITECTURE.md` and `CLAUDE.md`; the short version:

| App | Deploy to | Mechanism |
|---|---|---|
| `TA-ODIN` (forwarder app) | Universal Forwarders | Deployment Server `deployment-apps/` |
| `ODIN_app_for_splunk` (indexer + search head app) | Indexers + Search Heads | `etc/apps/` directly, or Cluster Manager / SH Deployer for clustered setups |

`indexes.conf` MUST NEVER ship to UFs (CI guard `tools/tests/check-two-app-split.sh`
enforces this on every push). `inputs.conf` MUST NEVER ship to indexers/SHs.

## TA-ODIN deployment (forwarders)

1. Copy the `TA-ODIN/` directory into the Deployment Server's deployment-apps:

   ```bash
   cp -r TA-ODIN $SPLUNK_HOME/etc/deployment-apps/
   ```

2. Bind `TA-ODIN` to the relevant serverclass(es) via
   `$SPLUNK_HOME/etc/system/local/serverclass.conf`. See "Serverclass binding examples"
   below for concrete snippets covering Linux-only, Windows-only, and mixed fleets.

3. Reload the Deployment Server:

   ```bash
   splunk reload deploy-server
   ```

4. Wait for the forwarder phone-home cycle (default `phoneHomeIntervalInSecs = 60` on
   idle UFs; 2-5 minutes for bursty environments).

5. Verify on a target UF that `TA-ODIN` was received:

   ```bash
   ls $SPLUNK_HOME/etc/apps/TA-ODIN/
   splunk list forward-server
   splunk btool inputs list 'script://./bin/odin.sh' --debug
   ```

   The `btool` output should show the scripted-input stanza sourced from
   `etc/apps/TA-ODIN/default/inputs.conf` with `disabled = false`.

## ODIN_app_for_splunk deployment (indexers + search heads)

1. Copy `ODIN_app_for_splunk/` into the Splunk apps directory of every indexer and
   every search head:

   ```bash
   cp -r ODIN_app_for_splunk $SPLUNK_HOME/etc/apps/
   $SPLUNK_HOME/bin/splunk restart
   ```

2. **Indexer cluster:** stage in Cluster Manager `manager-apps/`, then push the bundle:

   ```bash
   cp -r ODIN_app_for_splunk $SPLUNK_HOME/etc/manager-apps/
   splunk apply cluster-bundle --answer-yes
   ```

3. **Search head cluster:** stage in the Deployer `shcluster/apps/`, then push:

   ```bash
   cp -r ODIN_app_for_splunk $SPLUNK_HOME/etc/shcluster/apps/
   splunk apply shcluster-bundle -target https://<sh-captain>:8089
   ```

4. Verify on each indexer that the `odin_discovery` index exists:

   ```bash
   splunk btool indexes list odin_discovery --debug
   ```

5. Verify on each search head that lookups, props, and saved searches are loaded:

   ```bash
   splunk btool transforms list --app=ODIN_app_for_splunk | grep odin_classify
   splunk btool savedsearches list --app=ODIN_app_for_splunk | grep -E 'ODIN -|alert_odin'
   ```

## Verification (post-install)

Within one scan cycle of a fresh install (immediate on first deploy; otherwise governed
by `interval = 2592000` = 30 days in `default/inputs.conf`), events should appear:

```spl
index=odin_discovery sourcetype=odin:enumeration earliest=-1h
| stats count by type
| sort - count
```

Expect to see at minimum: `odin_start`, `odin_complete`, `service`, `port`, `package`,
`process`, `mount`, plus `cron` (Linux) or `scheduled_task` (Windows).

After the first nightly run of the saved searches (default 01:05/01:10/01:15 UTC), the
host inventory lookup should populate:

```spl
| inputlookup odin_host_inventory.csv
```

If the lookup is empty after a full nightly cycle, see `DOCS/TROUBLESHOOTING.md` —
specifically the "host_role is null" cross-platform issue.

## Per-OS prerequisites

### Linux

- `bash` 4+ (orchestrator and modules require bash features; `/bin/sh` will not work).
- coreutils: `timeout`, `awk`, `grep`, `sort`, `head`, `tail`, `tr`, `wc`, `date`,
  `hostname`, `id`. All shipped in default `coreutils` on every supported distro.
- Optional but recommended: `ss` (iproute2), `systemctl` (systemd), `dpkg-query` /
  `rpm` / `apk` / `pacman` for package enumeration. Each module documents its fallback
  chain in `DOCS/COMMANDS.md`.
- No sudo. Splunk UF service account read-only access is sufficient for full
  enumeration; running as root improves port-process attribution and user-crontab
  visibility (see `DOCS/COMMANDS.md` "Privilege Impact" section).

### Windows

- PowerShell 5.1+ built-in (ships with Windows Server 2016+ and Windows 10/11). No
  PS Gallery modules; no `Add-Type`; no `Invoke-Expression`; no compiled binaries
  (HARD constraint per `CLAUDE.md`).
- Splunk UF runs as `LocalSystem` (default service account); no privilege elevation
  needed. The orchestrator is invoked via the `bin/odin.path` `.path` wrapper which
  Splunk maps to `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass
  -File odin.ps1` (see `CLAUDE.md` deployment notes).
- AppLocker / WDAC environments: see `DOCS/TROUBLESHOOTING.md` "AppLocker / WDAC"
  entry. Coordinate publisher-rule allowlisting with the EDR/security team before
  pilot deployment; testing on a Constrained Language Mode host is recommended
  pre-pilot.

## Serverclass binding examples

Add these stanzas to `$SPLUNK_HOME/etc/system/local/serverclass.conf` on the
Deployment Server. After editing, run `splunk reload deploy-server` to apply.

### Linux-only fleet

```ini
[serverClass:linux_endpoints]
whitelist.0 = *.linux.example.com
machineTypesFilter = linux-x86_64,linux-i686,linux-armhf,linux-aarch64

[serverClass:linux_endpoints:app:TA-ODIN]
restartSplunkd = 0
```

### Windows-only fleet

```ini
[serverClass:windows_endpoints]
whitelist.0 = *.win.example.com
machineTypesFilter = windows-x64,windows-x86

[serverClass:windows_endpoints:app:TA-ODIN]
restartSplunkd = 0
```

### Mixed Linux + Windows fleet

```ini
[serverClass:all_endpoints]
whitelist.0 = *
# No machineTypesFilter — TA-ODIN auto-detects OS at runtime via the .sh / .path
# stanza split in inputs.conf. Linux UFs ignore the Windows stanza and vice versa.

[serverClass:all_endpoints:app:TA-ODIN]
restartSplunkd = 0
```

`restartSplunkd = 0` keeps the UF running across reload-cycles — TA-ODIN's scripted
inputs are picked up on the next interval boundary without restart.

## Next steps

- Configure scan frequency: copy `TA-ODIN/default/inputs.conf` to `local/inputs.conf`
  and adjust `interval` (default 30 days = 2592000s).
- Activate the 3 alert stanzas after a baseline pilot — see `DOCS/UPGRADE.md`.
- On-call response procedures: `DOCS/RUNBOOK.md`.
- If something goes wrong fleet-wide: `DOCS/ROLLBACK.md`.
