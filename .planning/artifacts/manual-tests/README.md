# Manual Test Outputs

Real-host test outputs from manual orchestrator runs, captured outside the formal
PROD-02 pilot framework. These artifacts serve as evidence of cross-platform
parity and end-to-end functional correctness on actual production-target
operating systems.

These are NOT replacements for PROD-02 (the formal 7-day, ≥10-host pilot defined
in REQUIREMENTS.md). They are dev-cycle confidence anchors captured opportunistically
during development and review.

## Files

| File | Date | Host | OS | Modules | Events | Runtime | Notes |
|---|---|---|---|---|---|---|---|
| `windows11-2026-04-27_test.txt` | 2026-04-27 | `test` (VM) | Windows 11 | 6/6 success | 690 | 23.5s | First end-to-end Windows validation post-PROD-07 (d) consolidation. Validated on Microsoft Edge–heavy desktop. `modules_total=6` confirms `_common.ps1` correctly excluded from discovery. |
| `linux_rocky-2026-04-27_test.txt` | 2026-04-27 | `e0c0ddd5630b` (Docker) | Rocky Linux 9.3 | 6/6 success | 196 | ~6s | Linux counterpart to the Windows capture above. Captured INSIDE a minimal Rocky 9 Docker container (no systemd, no application services), proving graceful degradation: cron/services emit `none_found`, packages emit 169 RPM-base events, ports show only Docker DNS resolver, processes captures the orchestrator's own subprocess tree. Note: this run was BEFORE commit `718f76b`, so `duration_ms` is absent from the `odin_complete` event. Future Linux captures should include it. |

## What these prove

For the Windows 2026-04-27 capture specifically:

1. **PROD-07 (d) refactor works on Windows** — `_common.ps1` consolidation
   doesn't break orchestrator execution.
2. **`modules_total=6` discovery filter works** — `_common.ps1` correctly
   excluded from module discovery (mirrors the Linux fix in commit `9cb4894`).
3. **Cross-platform field-format parity** — Windows event format byte-for-byte
   matches Linux pattern (timestamp, hostname, os, run_id, odin_version, type
   prefix; key=value pairs; quoted strings with whitespace; backslash preservation
   in Windows paths).
4. **All 6 modules functional** — service (258), scheduled_task (236), process
   (151), port (35), package (4), mount (4) — full enumeration coverage.
5. **No errors, no truncation** — zero `type=odin_error`, zero `type=truncated`.
6. **Sub-120s runtime** — 23.5s well within the Splunk scripted-input timeout.

## What these do NOT prove

- **7-day stability** — only single-run snapshots
- **Fleet-scale behavior** — only one host per capture
- **SLO tracking** — `modules_failed=0` on ≥95% of events over 7 days requires
  pilot infrastructure
- **Production deployment** — these were manual invocations, not Splunk
  Universal Forwarder via Deployment Server with `odin.path` wrapper

PROD-02 (Phase 6 Pilot Validation) is the formal qualifier for those guarantees.

## Reproducing

### Windows
```powershell
cd <TA-ODIN-path>\bin
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\odin.ps1 |
  Tee-Object -FilePath "windows-$ts.txt"
```

### Linux
```bash
cd <TA-ODIN-path>/bin
ts=$(date +%Y%m%d-%H%M%S)
./odin.sh > "linux-$ts.txt" 2>&1
```

Output files can be saved here (`.planning/artifacts/manual-tests/`) following
the convention `<os><version>-<YYYY-MM-DD>_test.txt` for traceability.
