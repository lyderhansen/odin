# TA-ODIN Upgrade Guide: v1.0.0 -> v1.0.1

In-place upgrade procedure for fleets already running v1.0.0. Audience: Splunk admin
who already pushed v1.0.0 via Deployment Server and is now staging v1.0.1.

## What changed in v1.0.1

v1.0.1 closes the seven `PROD-*` requirements that v1.0.0 deferred to "production
readiness". No event format changes, no schema changes, no breaking changes —
upgrade is safe in-place.

- **Windows classification rows** (PROD-01 / Phase 4): 25 Windows service rows added
  to `odin_classify_services.csv`, 18 Windows port rows added to
  `odin_classify_ports.csv`, 34 Windows package wildcard rows added to
  `odin_classify_packages.csv`, 23 Windows log-source mapping rows added to
  `odin_log_sources.csv`. Pre-existing Linux rows preserved byte-for-byte.
- **Operational dashboard** (PROD-06): new Dashboard Studio v2 view at
  `ODIN_app_for_splunk/default/data/ui/views/odin_ops.xml` with 7 panels
  (per-OS scan success rate, p95 module runtime, distinct hosts over time,
  event volume top-20 hosts, module-failure heatmap, top truncating hosts).
- **On-call runbook** (PROD-03): new `DOCS/RUNBOOK.md` with 4 alert-response
  entries covering all current alert classes plus the implicit non-124
  module-error pattern. Each entry: what it means / diagnostic SPL /
  remediation / escalation.
- **Rollback procedure** (PROD-05): new `DOCS/ROLLBACK.md` (Strategy A overlay +
  Strategy B uninstall) plus `tools/tests/rollback-dryrun.sh` (CI-gated
  configparser-emulator dry-run). Validates the `disabled = true` overlay
  semantics on both `[script://./bin/odin.sh]` and `[script://.\bin\odin.path]`
  stanzas without requiring a running Splunk instance.
- **Admin docs** (PROD-04): this document plus `DOCS/INSTALL.md`,
  `DOCS/TROUBLESHOOTING.md`, `DOCS/DATA-DICTIONARY.md`. Existing
  `DOCS/ARCHITECTURE.md` and `DOCS/COMMANDS.md` left untouched.
- **Linux module hygiene** (PROD-07): all 6 Linux module standalone fallbacks
  (`bin/modules/{cron,mounts,packages,ports,processes,services}.sh`) bumped from
  `ODIN_VERSION:-2.1.0` to `ODIN_VERSION:-1.0.0` and gained an `ODIN_MAX_EVENTS`
  guard mirroring the orchestrator's `emit()` behavior. New
  `tools/tests/check-version-sync.sh` Section 3 greps modules for stale
  version strings and exits 1 on drift (CI hard gate).
- **Pilot validation** (PROD-02 / Phase 6): TBD — the 7-day fleet observation
  window is the release gate for shipping v1.0.1 publicly. Operators upgrading
  internally before the public release should run their own representative-host
  validation per PROD-02 acceptance criteria.

## Pre-upgrade checks

Before pulling v1.0.1, confirm the v1.0.0 baseline is intact:

```bash
# Verify v1.0.0 tag exists and current branch tracks expected history
git log --oneline v1.0.0..HEAD | head
git rev-parse v1.0.0   # should output ad12450 or your local fork's equivalent

# Confirm Phase 1+2+3 regression suite passes on the v1.0.0 baseline
git checkout v1.0.0 -- TA-ODIN/ ODIN_app_for_splunk/   # only if you've drifted
bash tools/tests/check-version-sync.sh
bash tools/tests/check-two-app-split.sh
bash tools/tests/injection-fixtures/run.sh
bash tools/tests/windows-parity-harness.sh
shellcheck tools/tests/*.sh
```

All five should exit 0 against v1.0.0. If any fail on the v1.0.0 baseline, the
upgrade is not the right next step — open an issue against the local fork first.

Run `splunk-appinspect inspect` on both apps and capture the baseline summary
(`failure=0, error=0, warning=<N>, success=<M>, na=<K>`):

```bash
~/Library/Python/3.9/bin/splunk-appinspect inspect TA-ODIN \
  --mode precert --excluded-tags cloud --output-file /tmp/ta-baseline.json --data-format json
~/Library/Python/3.9/bin/splunk-appinspect inspect ODIN_app_for_splunk \
  --mode precert --excluded-tags cloud --output-file /tmp/odin-baseline.json --data-format json
```

The post-upgrade run should match this baseline (zero new failures, zero new errors).

## Upgrade steps

1. **Pull or merge the v1.0.1 release tag** into your local working copy:

   ```bash
   git fetch origin --tags
   git merge --ff-only v1.0.1   # or: git checkout v1.0.1
   ```

   No conflicts expected — v1.0.1 is additive over v1.0.0 (new docs, new dashboard,
   new lookup rows, module fallback patches).

2. **Re-deploy `TA-ODIN/` via Deployment Server** (forwarders). Module patches in
   `bin/modules/*.sh` are the only TA-ODIN code change; no schema change, safe in-
   place re-push:

   ```bash
   cp -r TA-ODIN $SPLUNK_HOME/etc/deployment-apps/
   splunk reload deploy-server
   ```

   See `DOCS/INSTALL.md` "TA-ODIN deployment (forwarders)" for the full procedure
   if this is your first DS push.

3. **Re-deploy `ODIN_app_for_splunk/`** to indexers and search heads. The new
   dashboard XML (`odin_ops.xml`), new SLO alert stanza in `savedsearches.conf`,
   and new lookup rows are all additive:

   - Single instance / unclustered: `cp -r ODIN_app_for_splunk
     $SPLUNK_HOME/etc/apps/ && $SPLUNK_HOME/bin/splunk restart`
   - Indexer cluster: stage in `manager-apps/` and run
     `splunk apply cluster-bundle --answer-yes` (per `DOCS/INSTALL.md`)
   - Search head cluster: stage in `shcluster/apps/` and run
     `splunk apply shcluster-bundle -target https://<sh-captain>:8089`

4. **Restart Splunkd** on all indexers and search heads (single-instance only —
   cluster bundles handle this automatically). The new dashboard view and the new
   alert stanza are picked up on next config reload.

## Post-upgrade verification

1. **Confirm host classification still works.** The Windows classification rows
   added in PROD-01 should now classify Windows hosts that were previously
   unclassified. Re-run the host inventory saved search manually (or wait for the
   next nightly schedule):

   ```spl
   | inputlookup odin_host_inventory.csv
   | where match(hostname, "(?i)win|dc|sql|exch")
   | stats count by host_role
   | sort -count
   ```

   Expect to see `host_role` values like `domain_controller`, `database_server`,
   `web_server`, `mail_server`, `windows_management` for hosts that previously
   showed empty `host_roles`.

2. **Verify the ops dashboard renders.** Navigate in Splunk Web:

   ```
   https://<your-search-head>/app/ODIN_app_for_splunk/odin_ops
   ```

   Expect 7 panels to render with data once the next scan cycle completes (or
   immediately if you have backfill data). If panels show "No results found" for
   recent timeframes, give the fleet a scan cycle to repopulate.

3. **Verify alerts are visible but disabled** (Phase 5 D2 — definition-only ships):

   ```bash
   splunk btool savedsearches list --app=ODIN_app_for_splunk | grep -E '^\[alert_odin'
   ```

   Should show 3 alert stanzas: `[alert_odin_truncated_events]`,
   `[alert_odin_module_timeouts]`, and the new
   `[alert_odin_fleet_scan_success_rate_below_slo]`. All three should have
   `disabled = 1` and empty `cron_schedule` until you activate them (next section).

## Activating the new SLO alert

The third alert stanza added in v1.0.1 (`alert_odin_fleet_scan_success_rate_below_slo`)
ships in definition-only state — same convention as the two pre-existing alerts. The
on-call response procedure for this alert is documented in `DOCS/RUNBOOK.md`
"Alert: fleet scan success rate below SLO".

To activate (recommended only after PROD-02 pilot has produced a baseline
success-rate floor):

1. **Copy the stanza to a `local/savedsearches.conf` overlay** — preserves upgrade
   path, `default/savedsearches.conf` is owned by the app:

   ```bash
   mkdir -p $SPLUNK_HOME/etc/apps/ODIN_app_for_splunk/local
   ```

   Then edit `$SPLUNK_HOME/etc/apps/ODIN_app_for_splunk/local/savedsearches.conf`
   to overlay the activation fields:

   ```ini
   [alert_odin_fleet_scan_success_rate_below_slo]
   disabled = 0
   cron_schedule = 0 */6 * * *
   action.email = 1
   action.email.to = sre-on-call@example.com
   ```

2. **Tune the SLO threshold per-org.** The shipped `search` field uses
   `where success_rate < 0.95` — 95% is a starting recommendation, not a hard
   SLO. After PROD-02 pilot baseline data is in hand, adjust the threshold
   in the overlay's `search` field to match your fleet's observed floor.

3. **Reload saved searches** so the activation takes effect without a restart:

   ```bash
   splunk reload savedsearches
   ```

   Or via Splunk Web: **Settings -> Searches, reports, and alerts -> Refresh**.

The same activation pattern applies to `[alert_odin_truncated_events]` and
`[alert_odin_module_timeouts]` — see `DOCS/RUNBOOK.md` "Activating alerts" for the
multi-stanza overlay form.

## If something goes wrong

If the upgrade produces fleet-wide regressions (cascading `type=odin_error` events,
modules timing out across the board, AppInspect failures on next CI run), do not
attempt to triage in-place under load. Execute the rollback procedure documented
in `DOCS/ROLLBACK.md`:

- **Strategy A (recommended first response):** push a `local/inputs.conf` overlay
  via Deployment Server flipping `disabled = true` on both `[script://]` stanzas.
  Fleet-wide enumeration halts within one phone-home cycle.
- **Strategy B (last resort):** remove `TA-ODIN` from the serverclass and push
  empty deployment.

Both strategies preserve `ODIN_app_for_splunk` (the indexer/SH side stays in place
— rollback is forwarder-only). Once the regression is contained, investigate the
root cause and re-deploy the fix using the same upgrade procedure as above. The
dry-run validation log at `.planning/artifacts/rollback-dryrun.md` proves the
toggle semantics work in fixture form.
