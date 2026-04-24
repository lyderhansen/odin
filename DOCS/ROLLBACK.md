# TA-ODIN Rollback Procedure

Operator-facing playbook for halting TA-ODIN enumeration via Splunk Deployment Server. Audience: Splunk admin who already knows `serverclass.conf`, `splunk reload deploy-server`, and forwarder/indexer/search-head topology.

## When to roll back

Roll back when one or more of the following is observed for >= 1 scan cycle (i.e., >= 1 hour after the last interval-driven dispatch, or sooner under your shorter `interval` setting):

- Fleet-wide scan-success rate drops below the SLO floor (`alert_odin_fleet_scan_success_rate_below_slo` firing or its query returning `failing_hosts > 0` ad-hoc)
- Truncation alert storm — `alert_odin_truncated_events` firing on more than ~5% of fleet within 24h, suggesting an enumeration code path is producing far more events than expected
- Module-timeout alert storm — `alert_odin_module_timeouts` firing repeatedly (exit 124) on hosts that previously scanned cleanly, suggesting a regression in a module's command or a host-side change (e.g., new dpkg lock pattern, hung NFS mount class)
- New TA-ODIN release (e.g., post-`v1.0.1` upgrade) producing visibly degraded data or unexpected cardinality on the indexer
- Endpoint-team reports user-visible CPU or I/O contention attributable to `odin.sh` or `odin.path` execution

If only a single host is misbehaving, prefer host-targeted exclusion in `serverclass.conf` (`whitelist`/`blacklist`) over a fleet-wide rollback. A fleet-wide rollback is for systemic issues only.

## Two strategies

| Strategy | When to use | Reversible? | Files removed? |
|---|---|---|---|
| **A — Disable enumeration without uninstall** (recommended) | First response. Stops all scanning fleet-wide via a `local/inputs.conf` overlay that flips `disabled = true` on both stanzas. | Yes — repush with `disabled = false` to resume. | No. |
| **B — Full uninstall** (last resort) | Strategy A is stuck (e.g., Deployment Server itself misbehaving), or the TA must be fully removed for compliance / app store re-registration. | Manually — re-add to serverclass + repush. | Yes, on next UF reload after empty-deployment. |

## Strategy A — Disable enumeration via overlay

The shipped `TA-ODIN/default/inputs.conf` has two scripted-input stanzas:

```ini
[script://./bin/odin.sh]
disabled = false
...
[script://.\bin\odin.path]
disabled = false
...
```

Both must be toggled to `disabled = true`. Splunkd skips dispatching disabled scripted inputs at the next reload-cycle.

### Steps

1. **On the Deployment Server**, prepare a `local/inputs.conf` overlay inside the deployment-apps directory for `TA-ODIN`:

   ```bash
   DEPLOY_APPS=$SPLUNK_HOME/etc/deployment-apps
   mkdir -p "$DEPLOY_APPS/TA-ODIN/local"
   cat > "$DEPLOY_APPS/TA-ODIN/local/inputs.conf" <<'EOF'
   [script://./bin/odin.sh]
   disabled = true

   [script://.\bin\odin.path]
   disabled = true
   EOF
   ```

   Splunk's btool merge order means `local/inputs.conf` overrides `default/inputs.conf` per-stanza. The overlay leaves `index`, `sourcetype`, `interval`, and `timeout` from the default file untouched and only flips `disabled`.

2. **Bind the overlay** in `serverclass.conf` if not already done — `TA-ODIN` should already be in the same serverclass(es) you originally deployed to; no edit needed if so. Verify:

   ```bash
   splunk btool serverclass list --debug | grep -i ta-odin
   ```

3. **Reload the deployment server**:

   ```bash
   splunk reload deploy-server
   ```

4. **Wait for forwarder phone-home cycle**. Default phone-home is 60s on idle UFs; bursty environments may take 2–5 minutes for the entire fleet. Watch the deployment-server activity log:

   ```bash
   tail -f $SPLUNK_HOME/var/log/splunk/splunkd.log | grep -i deploymentclient
   ```

5. **Verify on a target UF** (pick one host that was previously scanning):

   ```bash
   splunk btool inputs list 'script://./bin/odin.sh' --debug
   ```

   Should show `disabled = true` sourced from the local overlay path.

## Strategy B — Full uninstall

Use only when overlays are not viable (e.g., Deployment Server itself broken, or compliance requires file removal).

1. Remove `TA-ODIN` from every `[serverClass:*]` stanza in `serverclass.conf` that previously included it (or set `restartSplunkWeb = 0` and `restartSplunkd = 0` if you only want to stop dispatching but keep files).
2. Push an empty deployment for those serverclasses:

   ```bash
   splunk reload deploy-server
   ```

3. Verify on each affected UF that `TA-ODIN` has been removed by the deployment client:

   ```bash
   ls $SPLUNK_HOME/etc/apps/ | grep -i ta-odin
   ```

   Should return nothing within ~5 minutes of the reload.

4. To re-deploy, re-add to the serverclass and repush — there is no `default/local` overlay to clean up because the entire app directory is gone.

## Verification — confirm enumeration has stopped

Run on the search head:

```spl
index=odin_discovery sourcetype=odin:enumeration earliest=-1h
| stats count AS new_events_last_hour
```

After the rollback has propagated (Strategy A: ~5 min; Strategy B: ~5 min after empty deployment), `new_events_last_hour` for previously-enumerating hosts should drop to zero on subsequent search runs (allow one full `interval` cycle to be sure — default `interval = 2592000` is 30 days, but you should see in-flight scans complete within ~2 minutes max).

For finer-grained per-host verification:

```spl
index=odin_discovery sourcetype=odin:enumeration type=odin_complete earliest=-1h
| stats max(_time) AS last_scan by hostname
| eval age_min=round((now()-last_scan)/60, 1)
| sort -age_min
```

Hosts that have NOT scanned since rollback show `age_min` growing past their scan interval — those are the ones the rollback successfully halted.

## Reverting the rollback (re-enabling enumeration)

To re-enable after Strategy A:

```bash
rm $SPLUNK_HOME/etc/deployment-apps/TA-ODIN/local/inputs.conf
splunk reload deploy-server
```

UFs phone home, the local overlay disappears, the default `disabled = false` re-applies on next reload. Enumeration resumes on the next scheduled `interval` boundary (or immediately if you also bump `interval` in a temporary overlay — not recommended for fleet-wide).

To re-enable after Strategy B: re-add `TA-ODIN` to the serverclass and `splunk reload deploy-server`. Files are redeployed fresh; first-scan happens at the next scheduled interval.

## Reference — dry-run validation

This procedure has been validated end-to-end in shell-fixture form (no live Splunk required) by `tools/tests/rollback-dryrun.sh`, which:

- Patches a `mktemp` copy of `TA-ODIN/default/inputs.conf` with the same `disabled = true` substitution
- Runs a Python `configparser` emulator confirming both `[script://./bin/odin.sh]` and `[script://.\bin\odin.path]` would be skipped by splunkd at next reload
- Asserts `git diff --quiet -- TA-ODIN/default/inputs.conf` (real file untouched)

The latest dry-run record is at `.planning/artifacts/rollback-dryrun.md` (regenerated on every CI run via the `Rollback dry-run guard` step in `.github/workflows/ci.yml`).

## What this procedure does NOT cover (deferred)

- **Real-fleet propagation timing** — `splunk reload deploy-server` -> UF receives change is environment-dependent and depends on `phoneHomeIntervalInSecs`, network latency, and serverclass size. Will be measured during PROD-02 pilot (Phase 6); update this doc with observed median + p95 once the pilot runs.
- **In-flight scan termination** — a `disabled = true` flip does NOT kill an already-running `odin.sh` invocation; it only prevents the NEXT dispatch. The 90s per-module timeout + 120s total `inputs.conf` timeout cap any in-flight scan. Monitor the runbook's `alert_odin_module_timeouts` query for stragglers.
- **Splunk Cloud Victoria** — overlay semantics differ; the `local/inputs.conf` mechanism above is Enterprise-on-prem only. Cloud Victoria deferred per Phase 3 D9.
- **Partial-state failure** — if your overlay `inputs.conf` has a syntax error, splunkd will reject the entire stanza on UFs (silent failure, visible only in `splunkd.log`). Test the overlay syntactically (`splunk btool inputs list --debug`) before pushing.
- **Re-keying or app-cert rotation** — out of scope for rollback; covered by your normal Splunk app-certificate hygiene.

If any of the above bites you during a real rollback, file a follow-up against PROD-02 with the specific symptoms — those gaps are exactly what the live pilot is meant to surface.
