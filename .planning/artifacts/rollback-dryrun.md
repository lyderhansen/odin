# Rollback dry-run record

Generated: 2026-04-27T18:45:13Z
Commit: 78b259f08116fc8604adf037e596a68ffcc11202
Verdict: PASS

## Pre-toggle baseline (live odin.sh invocation)

- Pre-toggle timestamp: 2026-04-27T18:45:13Z
- Pre-toggle event count: 10

## Rollback patch (applied to temp copy of inputs.conf)

Patch: `sed 's/^disabled = false$/disabled = true/g'` over both
`[script://...]` stanzas (Linux odin.sh + Windows odin.path).

Parser emulator (configparser) report:
```
  [script://./bin/odin.sh] disabled=true -> INACTIVE
  [script://.\bin\odin.path] disabled=true -> INACTIVE
ALL_STANZAS_INACTIVE
```

## Post-revert (temp patch discarded; real file untouched)

- Revert timestamp: 2026-04-27T18:45:13Z
- Post-revert timestamp: 2026-04-27T18:45:13Z
- Post-revert event count: 10

## Real-file integrity check

- `git diff --quiet -- TA-ODIN/default/inputs.conf` exit: 0 (no real-file modification)

## What this dry-run proves

- The `disabled = true` toggle semantics are correctly understood
  and applied to both Linux (`[script://./bin/odin.sh]`) and Windows
  (`[script://.\bin\odin.path]`) scripted-input stanzas.
- A Splunk-equivalent parser (Python configparser) confirms both
  stanzas would NOT be dispatched after rollback.
- The procedure is reversible: discarding the temp patch restores
  enumeration (post-revert event count > 0).
- The real inputs.conf in the repo is never modified by this script
  (working-tree `git diff` is empty).

## What this dry-run does NOT prove (deferred to PROD-02 pilot)

- Real Deployment Server reload-cycle delivers the patched
  inputs.conf to UFs within expected propagation time.
- Real Splunk forwarders honor the `disabled = true` flag
  immediately on next reload (vs queued in-flight scan).
- No partial-state failure (e.g., inputs.conf syntax error after
  edit causes UF to reject the entire stanza).

These three are explicitly verified during PROD-02 pilot, not here.
