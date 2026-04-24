# TA-ODIN On-Call Runbook

On-call response procedures for the four alert classes emitted (or implied) by TA-ODIN
fleet enumeration. This runbook is the operator-side counterpart to the alert stanzas in
`ODIN_app_for_splunk/default/savedsearches.conf`.

## When to use this runbook

Reach for this document when:

- A Splunk-scheduled saved search defined in `savedsearches.conf` fires (one of the three
  `[alert_odin_*]` stanzas).
- An ad-hoc dashboard panel surfaces a `type=odin_error` cluster, `type=truncated` spike,
  or fleet-scan-success-rate dip.
- A pilot or operator escalation references "TA-ODIN is not reporting from host X" or
  "module Y is failing on a class of hosts."

This runbook assumes the reader knows Splunk Deployment Server, `inputs.conf` semantics,
and the TA-ODIN two-app split (`TA-ODIN/` for forwarders, `ODIN_app_for_splunk/` for
indexers/SHs). For deeper architecture context see `DOCS/ARCHITECTURE.md`. For the full
command surface enumerated by each module see `DOCS/COMMANDS.md`.

## Activating alerts

All three alert stanzas ship in `definition-only` state per Phase 2 + Phase 5 D2:

- `disabled = 1`
- `cron_schedule =` (empty)

This is intentional. Activating fleet-wide alerts before establishing a baseline (PROD-02
pilot, 7-day observation window across 5+ Linux + 5+ Windows hosts) risks a false-positive
storm. Once the pilot has produced a baseline scan-success rate and a tolerable
truncation/timeout floor, an operator activates each alert by:

1. Editing `ODIN_app_for_splunk/local/savedsearches.conf` (NOT default — preserve upgrade
   path) with stanza overlays:

   ```ini
   [alert_odin_truncated_events]
   disabled = 0
   cron_schedule = 0 */6 * * *

   [alert_odin_module_timeouts]
   disabled = 0
   cron_schedule = 0 */6 * * *

   [alert_odin_fleet_scan_success_rate_below_slo]
   disabled = 0
   cron_schedule = 0 */6 * * *
   ```

2. Setting per-stanza `action.email = 1` + `action.email.to = <list>` (or other action) per
   org notification convention.
3. Reloading: `splunk reload deploy-server` is NOT relevant here (the savedsearch lives on
   the search head). Use the Splunk UI **Settings → Searches, reports, and alerts**
   refresh, or `splunkd` restart on the search head.

The recommended success-rate threshold for the SLO alert (95%) is a starting value, not a
hard SLO. Tune per-org based on observed pilot baseline.

For a future operator activation procedure see `DOCS/UPGRADE.md` (planned, Plan 04 of
Phase 5).

## Emergency rollback

If a TA-ODIN deployment regression is causing cascading failures across the fleet
(every host emitting `type=odin_error`, modules across the board hitting timeout, or the
forwarder `splunkd` segfaulting), do NOT spend time triaging individual modules. Execute
the rollback procedure in `DOCS/ROLLBACK.md` to halt enumeration fleet-wide via a
Deployment Server `disabled = true` toggle on the `[script://...odin.sh]` and
`[script://.\bin\odin.path]` stanzas in `TA-ODIN/default/inputs.conf`.

The dry-run validation log at `.planning/artifacts/rollback-dryrun.md` proves the toggle
semantics work in fixture form. Live fleet validation is PROD-02 territory.

---

## Alert response procedures

### Alert: type=truncated events

#### What it means

A discovery module on one or more hosts hit the `ODIN_MAX_EVENTS` cap (default 50000) and
the orchestrator emitted a `type=truncated` event in place of the remaining items. Once
truncated, every subsequent `emit()` call in that module on that scan cycle is silently
suppressed — enumeration data for that module is provably incomplete on that host.

Typical drivers:

- Hosts with 100k+ installed packages (build/dev workstations with snaps + flatpaks +
  language toolchains all installed)
- Hosts with 50k+ running processes (container hosts running thousands of short-lived
  shells, broken process-supervisor loops)
- Hosts with thousands of cron timers (badly authored CI runners that schedule per-build)
- Compromised hosts dropping persistence files into `/etc/cron.d/` or per-user crontabs

#### Diagnostic SPL

```spl
index=odin_discovery sourcetype=odin:enumeration type=truncated earliest=-7d
| stats count by hostname module
| sort -count
```

Drill into a specific host to find which modules are truncating and how often:

```spl
index=odin_discovery sourcetype=odin:enumeration type=truncated hostname="<host>" earliest=-30d
| stats count, latest(_time) AS last_truncated by module
```

Quantify the actual cardinality (run a one-off scan with raised cap to learn the true
count):

```spl
index=odin_discovery sourcetype=odin:enumeration type=package hostname="<host>" earliest=-1d
| stats dc(package_name) AS unique_packages
```

#### Remediation

1. Identify the high-cardinality hosts via the diagnostic SPL above.
2. Decide per-host class:
   - **Legitimate high cardinality** (build server, container host): raise
     `ODIN_MAX_EVENTS` for that host class via `local/inputs.conf` overlay on the
     forwarder. Either set the env var directly or edit the scripted-input stanza:

     ```ini
     [script://./bin/odin.sh]
     env.ODIN_MAX_EVENTS = 200000
     ```

     Push via Deployment Server serverclass scoped to the affected host class.
   - **Pathological cardinality** (compromised, runaway process loop, bloated cron
     dropper): treat as security incident. Do NOT raise the cap — that hides the symptom.
     Open an investigation ticket against the host owner.
3. Re-validate after the next scan cycle (next `interval` = 30 days by default; force a
   one-off run with `splunk reload deploy-server` after stanza change + manual UF restart
   if needed).

#### Escalation

`<TBD per organization>` — typically the platform team owning Splunk forwarder config
changes. For suspected-compromise cardinality drivers, also page the security-on-call
rotation per organization runbook.

---

### Alert: type=odin_error exit_code=124

#### What it means

A discovery module hit the per-module `ODIN_MODULE_TIMEOUT` cap (default 90s, leaving
30s margin within Splunk's 120s scripted-input timeout). The `timeout(1)` wrapper in
`odin.sh` killed the module process and the orchestrator emitted
`type=odin_error exit_code=124 module=<name>`. That module's data for that scan cycle on
that host is partial-or-empty.

Typical drivers:

- `packages.sh` blocked on `/var/lib/dpkg/lock` held by `unattended-upgrades` or a stuck
  apt operation
- `services.sh` blocked on a broken `systemctl` unit (failed `ExecStart` looping in
  `auto-restart` state, hung D-Bus reply)
- `mounts.sh` blocked on a hung NFS mount (kernel `stat()` blocks indefinitely; `df`
  inherits)
- `cron.sh` blocked on a broken systemd timer with malformed calendar spec
- `processes.sh` blocked on `/proc` read storms during fork bombs

#### Diagnostic SPL

```spl
index=odin_discovery sourcetype=odin:enumeration type=odin_error exit_code=124 earliest=-7d
| stats count by hostname module
| sort -count
```

Identify whether the timeout is host-class-wide (a distro/OS issue) or host-specific
(local fault):

```spl
index=odin_discovery sourcetype=odin:enumeration type=odin_error exit_code=124 earliest=-7d
| stats dc(hostname) AS affected_hosts, count AS total_timeouts by module, os
| sort -affected_hosts
```

Cross-reference with module run-time trend to see whether the module was creeping toward
the cap before hitting it:

```spl
index=odin_discovery sourcetype=odin:enumeration type=odin_complete earliest=-7d
| stats avg(duration_seconds), max(duration_seconds), p95(duration_seconds) by module, os
```

#### Remediation

1. SSH to a representative affected host (or open a remote shell session per org policy).
2. Reproduce the slow module manually:

   ```bash
   ODIN_HOSTNAME=$(hostname -f) ODIN_OS=linux ODIN_RUN_ID=manual-$$ ODIN_VERSION=1.0.0 \
     time bash /opt/splunkforwarder/etc/apps/TA-ODIN/bin/modules/<module>.sh
   ```

3. If `packages.sh`: check `lsof /var/lib/dpkg/lock-frontend` and `ps -ef | grep apt` —
   wait for or kill the holding process per change-control policy.
4. If `services.sh`: check `systemctl --failed` and `systemctl list-units --state=loaded`
   for units in `auto-restart` looping; resolve the underlying unit failure.
5. If `mounts.sh`: check `df` output directly; `umount -f -l <hung-mount>` per change
   control.
6. If `cron.sh`: check `systemctl list-timers --all` for `n/a` calendar specs; fix or
   remove the offending timer unit.
7. If the underlying issue is legitimate (host genuinely takes longer than 90s for that
   module on that hardware class), consider raising `ODIN_MODULE_TIMEOUT` via
   `local/inputs.conf` overlay — but do NOT raise above 100s (Splunk's scripted-input
   timeout is 120s and the orchestrator needs the 30s margin).

#### Escalation

`<TBD per organization>` — typically the platform team. For mount-related timeouts on
shared NFS, also notify the storage team that owns the NFS server.

---

### Alert: type=odin_error (non-124)

#### What it means

A discovery module exited non-zero for a reason other than `timeout(1)` killing it. The
orchestrator emits `type=odin_error module=<name> exit_code=<n>` where `<n>` is the
underlying module exit code. Common values:

- `1` — generic bash error (often missing required binary)
- `2` — bash usage error (typically a syntax error in the module — should never happen
  in shipped code, indicates a corrupted forwarder install or a local-overlay typo)
- `126` — command found but not executable (permissions stripped)
- `127` — command not found (e.g., `systemctl` on systems without systemd, `dpkg-query`
  on RPM systems with no fallback path triggered)
- `130` — interrupted (SIGINT, typically only seen in manual debug sessions)
- Anything else — module's own error semantics (rare; modules are written to swallow
  errors and emit `type=none_found` or `type=privilege_warning` instead)

There is no dedicated saved-search alert stanza for this case in v1.0.1 — the same data
that powers `[alert_odin_module_timeouts]` (search: `type=odin_error exit_code=124`) is
queried with a different `where` clause to surface non-124 errors.

#### Diagnostic SPL

```spl
index=odin_discovery sourcetype=odin:enumeration type=odin_error NOT exit_code=124 earliest=-7d
| stats count by hostname module exit_code
| sort -count
```

Cluster non-124 errors by `os` + `exit_code` to spot OS-class regressions (a recent
distro upgrade dropping `dpkg-query` from a Debian-derivative would show as a fleet-wide
`exit_code=127` for `packages.sh` on hosts with `os=linux` and a specific
`os_distribution`):

```spl
index=odin_discovery sourcetype=odin:enumeration type=odin_error NOT exit_code=124 earliest=-7d
| stats dc(hostname) AS affected_hosts, count AS total_failures by module exit_code os
| sort -affected_hosts
```

Pull the orchestrator log fragment for one affected host (the orchestrator emits
`type=odin_warning` and `type=odin_start`/`type=odin_complete` events around the failure
that may explain the context):

```spl
index=odin_discovery sourcetype=odin:enumeration hostname="<host>" earliest=-1d
| where type IN ("odin_start","odin_warning","odin_error","odin_complete")
| sort _time
```

#### Remediation

1. Read the orchestrator events surrounding the failure (above SPL) — orchestrator emits
   `type=odin_warning` for known-but-non-fatal conditions (privilege limitations, missing
   commands with available fallback) before they manifest as `type=odin_error`.
2. Check whether the module's required commands exist on the host. Per
   `DOCS/COMMANDS.md`, each module has a documented fallback chain. A `127` (command
   not found) on a module that has fallbacks indicates either (a) all fallbacks also
   missing — host platform is unsupported, or (b) the orchestrator failed to dispatch to
   the right fallback — log the case for module hardening.
3. Check for recent OS upgrades or package-manager state changes on the affected host
   class. Common regression: a CentOS Stream / Rocky / RHEL minor-version bump that
   silently changes `systemctl` flag semantics or removes a `service` shim.
4. For permission errors (`126` or `EPERM` in stderr): check whether the Splunk forwarder
   user changed (e.g., from `root` to `splunk`) and whether the wrapper sudoers entry
   documented in `DOCS/COMMANDS.md` is still in place.
5. If the module is genuinely broken on that host class (reproducible failure not driven
   by transient state), open an issue against the TA-ODIN repo with the host's distro,
   kernel, and reproduction steps.

#### Escalation

`<TBD per organization>` — platform team for module-side issues; the OS owner team (Linux
admins / Windows admins) for host-side issues like permission stripping or distro
regressions. For Splunk-forwarder-user changes, also notify whoever owns the Splunk UF
package recipe.

---

### Alert: fleet scan success rate below SLO

#### What it means

The aggregate fleet-wide scan success rate (defined as the fraction of hosts emitting
`type=odin_complete modules_failed=0` over the last 24h) dropped below the configured
threshold (default 95% — operator-tunable per-org after PROD-02 pilot baseline). This is
the canary alert: a sustained dip indicates a systemic problem, not a per-host fault.

Typical drivers:

- A bad Deployment Server push (a recent serverclass change overlaid a broken
  `local/inputs.conf` or `app.conf`)
- An OS-patch wave that broke a module on a large fraction of the fleet (e.g., a kernel
  update that broke `/proc/<pid>/cmdline` reads under `hidepid=1`)
- An infrastructure outage (e.g., NFS server outage causing every NFS-mounting host to
  emit `mounts.sh` errors)
- A regression in TA-ODIN itself shipped via Deployment Server (e.g., a v1.0.x → v1.0.y
  module-side change that introduced a new code path with a defect)
- Splunk indexer-side ingest backpressure causing `type=odin_complete` events to be
  dropped (unlikely under normal operation but possible under index-storm conditions)

#### Diagnostic SPL

Compute the success rate by OS class to see whether the dip is OS-specific:

```spl
index=odin_discovery sourcetype=odin:enumeration type=odin_complete earliest=-24h
| stats avg(eval(if(modules_failed=0,1,0))) AS success_rate by os
| eval success_pct=round(success_rate*100,1)
```

Identify which modules are failing on the affected hosts:

```spl
index=odin_discovery sourcetype=odin:enumeration type=odin_complete modules_failed>0 earliest=-24h
| stats values(failed_modules) AS failed_modules, dc(hostname) AS affected_hosts by os
| sort -affected_hosts
```

Compare success_rate trend over the last 30 days to find the regression onset:

```spl
index=odin_discovery sourcetype=odin:enumeration type=odin_complete earliest=-30d
| timechart span=1d avg(eval(if(modules_failed=0,1,0))) AS success_rate by os
```

Cross-reference with Deployment Server change history (operator's CMDB or change ticket
log — outside TA-ODIN's surface):

```spl
index=_internal sourcetype=splunkd component=DeploymentMetrics earliest=-30d
| timechart span=1h count by serverclass
```

#### Remediation

1. Drill into the `modules_failed > 0` events to identify the common failure pattern
   (above SPL).
2. Check Deployment Server logs for recent serverclass changes that overlap with the
   regression onset. Roll back any TA-ODIN deployment overlay made in the last 24h via
   the standard DS revert procedure.
3. Validate that the existing CI guards still pass against the currently-deployed
   TA-ODIN version:

   ```bash
   bash tools/tests/check-version-sync.sh
   bash tools/tests/check-two-app-split.sh
   bash tools/tests/check-windows-classification.sh
   bash tools/tests/windows-parity-harness.sh
   bash tools/tests/injection-fixtures/run.sh
   ```

   A regression in the CI guards on the deployed version indicates a deploy hash
   mismatch — verify the Deployment Server is shipping the expected commit.
4. If the regression is widespread (>20% of fleet affected) AND root cause is not
   immediately clear AND a recent TA-ODIN change is the suspected cause, **execute the
   rollback procedure** documented in `DOCS/ROLLBACK.md`. The rollback halts enumeration
   fleet-wide; once stopped, a controlled investigation can proceed without ongoing
   alert noise.
5. Once root cause is identified and fixed, re-enable enumeration via the rollback
   document's revert procedure. Verify the success rate recovers in the next 24h
   alerting window before considering the incident resolved.

#### Escalation

`<TBD per organization>` — platform lead + on-call SRE for fleet-wide regressions. For
suspected indexer-side ingest backpressure, also page the Splunk-platform team. For
suspected Deployment Server misconfiguration, page whoever owns the DS serverclass
change-control process (often a separate team from the Splunk-search team).
