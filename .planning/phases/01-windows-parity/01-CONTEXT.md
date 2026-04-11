# Phase 1: Windows Parity — Context

**Gathered:** 2026-04-10
**Status:** Ready for research + planning
**Source:** `/gsd-discuss-phase 1` (discuss mode) — user accepted all Claude leans in one shot

<domain>
## Phase Boundary

Build a Windows-side collection layer (`TA-ODIN/bin/odin.ps1` orchestrator + six PowerShell modules under `TA-ODIN/bin/modules/*.ps1`) that mirrors the Linux orchestrator and six modules **byte-for-byte in event format**, using only built-in PowerShell 5.1+ cmdlets, so `ODIN_app_for_splunk`'s existing search-time lookups, props, transforms, and saved searches (`odin_classify_*.csv`, `odin_log_sources.csv`, the three nightly saved searches, the CIM aliases) work unchanged against Windows-originated events.

**Not in this phase** (deferred to v1.1 per REQUIREMENTS.md):
- Full cross-platform testing harness (group D) — Phase 1 ships only the *minimum* fixture mechanism needed to verify its own success criteria
- End-user documentation (group E)
- Windows-specific classification CSV rows (group F)
- Reproducible packaging (group G)

**Not in this phase** (deferred to Phase 2):
- Version drift fix (HARD-01) — Phase 1 will hardcode `ODIN_VERSION = "1.0.0"` in both orchestrators as an interim; Phase 2 formalizes the single-source-of-truth
- Tunable guardrails via env vars (HARD-02) — Phase 1 honors `$env:ODIN_MAX_EVENTS` and `$env:ODIN_MODULE_TIMEOUT` if set, but Phase 2 proves the tunability on both orchestrators with test fixtures
- Alerting saved searches for `type=truncated` and `type=odin_error exit_code=124` (HARD-03, HARD-04)
- CI lint gates (HARD-05, HARD-06) and two-app-split mechanical guard (HARD-07)
- Shell-injection audit + regression fixture (HARD-08)
- AppInspect (all of group C — Phase 3)

</domain>

<decisions>
## Implementation Decisions

### D1. Per-module timeout mechanism — `Start-Job` + `Wait-Job -Timeout`

**Locked.** The orchestrator spawns each module as a separate PowerShell background job and waits up to 90 seconds (or `$env:ODIN_MODULE_TIMEOUT` if set).

**Pattern:**
```powershell
$job = Start-Job -ScriptBlock {
    param($ModulePath, $SharedEnv)
    foreach ($kv in $SharedEnv.GetEnumerator()) { Set-Item "env:$($kv.Key)" $kv.Value }
    & $ModulePath
} -ArgumentList $modulePath, $envHashtable

if (Wait-Job -Job $job -Timeout $timeoutSeconds) {
    Receive-Job -Job $job          # stream module stdout to orchestrator stdout
    $exitCode = (Get-Job -Id $job.Id).State -eq 'Completed' ? 0 : 1
} else {
    Stop-Job -Job $job
    $exitCode = 124                # synthesized — see D4
}
Remove-Job -Job $job -Force
```

**Rationale:** Overhead is acceptable (6 modules × ~150 ms subprocess spawn = ~1 s total, inside the 120 s Splunk input timeout). Subprocess isolation matches Linux `timeout 90 bash $module` semantically — a runaway module cannot corrupt the orchestrator's process state. Runspaces (in-process) were rejected because disposal/exception surface is fiddly under Constrained Language Mode.

**Alternative ruled out:** `Start-ThreadJob` (PS 7+, not available on 5.1 built-in).

### D2. Shared library — dot-sourced `_common.ps1`

**Locked.** Helpers live in `TA-ODIN/bin/modules/_common.ps1`. Every module and the orchestrator dot-source it at the top with a guard identical in spirit to the Linux `if ! declare -f emit` pattern:

```powershell
# Use orchestrator helpers if already loaded, otherwise dot-source
if (-not (Get-Command Invoke-OdinEmit -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\_common.ps1"
}
```

`_common.ps1` defines:
- `Get-OdinTimestamp` — ISO 8601 UTC via `(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')`
- `Format-OdinValue` — PowerShell equivalent of `safe_val()` (escapes embedded `"`, wraps in `"..."` if value contains space)
- `Invoke-OdinEmit` (noun-verb cmdlet-style, so PSScriptAnalyzer stays happy; referred to as `emit` in conversation) — builds the event line with the standard prelude, enforces MAX_EVENTS accounting, emits `type=truncated` marker once when cap is hit
- `Set-OdinContext` — populates `$env:ODIN_HOSTNAME`, `$env:ODIN_OS = 'windows'`, `$env:ODIN_RUN_ID`, `$env:ODIN_VERSION` with standalone fallback if not already set (mirrors Linux standalone fallback block at `services.sh:19-26`)

**Module naming note:** Because `Start-Job` runs the module in a fresh runspace, the module script itself (not the orchestrator) is responsible for dot-sourcing `_common.ps1`. The orchestrator's own dot-source is for its *own* use (emitting start/complete markers), not for inheriting into jobs.

**Rationale:** Closest Linux parity, works in both orchestrator and standalone mode, compatible with `Start-Job` (the job's scriptblock dot-sources `_common.ps1` itself). The orchestrator passes the shared `ODIN_*` env vars into the job via `-ArgumentList` + a small bootstrap header, so the module's dot-source resolves to the same helper state the orchestrator would have produced.

**Alternative ruled out:** `New-Module` / `Import-Module` approaches — may trip AppInspect heuristics around dynamic code loading, and obscure the "dot-source for parity" symmetry with Linux.

### D3. Mock fixture harness — cmdlet-shadow stubs gated by `$env:ODIN_TEST_FIXTURE`

**Locked.** Each module has a small block near the top, immediately after the `_common.ps1` dot-source:

```powershell
if ($env:ODIN_TEST_FIXTURE) {
    . (Join-Path $PSScriptRoot '..\..\tests\windows-fixtures\stubs.ps1')
}
```

`tests/windows-fixtures/stubs.ps1` defines PowerShell functions named `Get-Service`, `Get-CimInstance`, `Get-NetTCPConnection`, `Get-NetUDPEndpoint`, `Get-ScheduledTask`, `Get-ScheduledTaskInfo`, `Get-Process`, `Get-Volume`, `Get-PSDrive`, and a registry accessor for `HKLM:\...\Uninstall` reads. PowerShell resolves function names before cmdlets, so the stubs shadow the real cmdlets when `$env:ODIN_TEST_FIXTURE` is set. The stubs read canned data from `tests/windows-fixtures/<module>/<fixture-name>.json`.

**Canonical fixtures for Phase 1 (minimum viable to satisfy WIN-08):**
- `services/iis-box.json`, `services/sql-box.json`, `services/minimal-workstation.json`
- `ports/web-server.json`, `ports/domain-controller.json`
- `packages/basic.json` (5 registry entries, one with a space in `DisplayName`, one with a `"` in `DisplayName`)
- `scheduled_tasks/basic.json`
- `processes/basic.json`
- `mounts/basic.json`
- `empty/` fixtures for every module (to exercise `type=none_found`)
- `failing/throw.json` for WIN-12 fail-soft verification (a stub that `throw`s mid-enumeration)

**How tests run on macOS:** `pwsh` (PS 7 on macOS) parses PS 5.1 code and will execute the modules in test mode. The cmdlet-shadow approach works identically on `pwsh` and `powershell.exe` because function-vs-cmdlet resolution is the same.

**Rationale:**
1. Ships with zero external dependencies (no Pester install) — matches the "no PS Gallery" constraint at the project level
2. Works identically on `pwsh` (macOS dev) and `powershell.exe` (Windows pilot) — one harness for both
3. Doesn't pull Pester into AppInspect-vetted code — Pester under `tests/` is fine, but keeping production modules vanilla PS 5.1 is safest for APPI-06
4. Defers the full test harness cleanly to v1.1 group D — Phase 1 ships *just enough* to satisfy its own 5 success criteria

**Ugliness acknowledged:** The in-production `if ($env:ODIN_TEST_FIXTURE) { . stubs.ps1 }` block is explicit and auditable. PSScriptAnalyzer will see it as "dot-sourcing under a conditional" which is legal. AppInspect will see a conditional dot-source — this should pass because the stubs file is under `tests/`, not `bin/`, and the block is a no-op without the env var. Phase 3 (AppInspect) should verify.

**Alternative ruled out:** Pester + `Mock` — heavier, not built into PS 5.1 (even though macOS `pwsh` ships with it), and more code paths to audit for AppInspect. Reserved for v1.1's full test harness.

### D4. Windows exit-code convention for `odin_error` — synthesize `exit_code=124` on timeout

**Locked.** When the Windows orchestrator's `Wait-Job -Timeout 90` returns without completion, it emits:

```
type=odin_error module=<name> exit_code=124 message="module exceeded ODIN_MODULE_TIMEOUT" timeout_reason=orchestrator_kill
```

**Rationale:** Preserves platform-symmetric alerting. Phase 2's HARD-04 saved search can be a single stanza: `index=odin_discovery sourcetype=odin:enumeration type=odin_error exit_code=124` — and it will alert on both Linux and Windows timeout patterns with no platform branching. The `timeout_reason=orchestrator_kill` field is additive context for humans, not a new alerting key.

**Comment required at emission site** explaining this is a deliberate cross-platform convention, not a bug:
```powershell
# exit_code=124 is synthesized to match the POSIX `timeout(1)` convention used by
# the Linux orchestrator. Preserves a single cross-platform alerting saved search
# for type=odin_error exit_code=124 (see Phase 2 HARD-04). Do NOT change this
# value without also revising the Phase 2 saved search.
```

Also document in `DOCS/DATA-DICTIONARY.md` when v1.1 group E lands.

### D5. Output encoding and line endings — UTF-8 no BOM, explicit LF

**Locked.** The Windows orchestrator sets the console output encoding explicitly at startup:

```powershell
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)  # $false = no BOM
[Console]::InputEncoding  = New-Object System.Text.UTF8Encoding($false)
```

And every event-emitting path uses `[Console]::Out.Write("$line`n")` with a **literal LF**, not `Write-Output` (which adds CRLF on Windows). `Invoke-OdinEmit` in `_common.ps1` is the only place that writes events, so the LF discipline lives in exactly one function.

**Rationale:** The only way to produce bytes indistinguishable from Linux output. Silent field-extraction failures from a CRLF buried mid-event or a CP1252 byte in a non-English service display name are high-cost, low-visibility bugs at 10k-host scale.

**Splunk side (props.conf) verification:** `TA-ODIN/default/props.conf` currently uses `LINE_BREAKER = ([\r\n]+)` which already tolerates both CRLF and LF, so this is a belt-and-braces choice — producer and parser both agree on LF.

**Non-ASCII characters in service/package/mount names are preserved.** Non-English Windows Server hosts (German, Japanese, Chinese) emit their native-language Unicode values unchanged. This works because:
1. We force UTF-8 at the console boundary — no CP1252 transliteration
2. The `safe_val` helper quotes and escapes but never re-encodes
3. Splunk `KV_MODE = auto` is Unicode-safe
4. Classification lookups match on English-normalized fields (service executable names, port numbers, package GUIDs), not display names

### D6. Standalone-mode parity for modules — full parity

**Locked.** Every Windows module can be invoked directly for ad-hoc testing:

```bash
# On macOS dev machine
pwsh TA-ODIN/bin/modules/services.ps1

# On a real Windows host (eventual pilot)
powershell.exe -NoProfile -File TA-ODIN\bin\modules\services.ps1
```

This works because each module dot-sources `_common.ps1` unconditionally (per D2), and `_common.ps1`'s `Set-OdinContext` function populates `$env:ODIN_HOSTNAME`, `$env:ODIN_OS`, `$env:ODIN_RUN_ID`, `$env:ODIN_VERSION` with `standalone-<PID>` fallbacks when they're not already set (mirroring `services.sh:19-26` exactly).

When combined with D3, standalone + test fixture mode is:
```bash
ODIN_TEST_FIXTURE=1 pwsh TA-ODIN/bin/modules/services.ps1
```

— which will print a `type=service` line per fixture entry, deterministically, on macOS, with zero Windows host access. **This is how WIN-08 byte-parity will be verified in Phase 1's success criteria.**

**Rationale:** ~5 lines per module given D2's helpers, and it preserves the Linux developer experience. Also, it's your *only* path to exercising Windows modules before pilot.

### Claude's Discretion (not user-decided — planner's choice)

- Exact file layout within `tests/windows-fixtures/` — subdirectory per module vs. flat with prefixed names
- Naming of the bootstrap header that `Start-Job` runs (e.g. `_job-bootstrap.ps1` vs inline scriptblock)
- Whether `Invoke-OdinEmit` takes positional or named parameters
- Precise wording of `#Requires` directive in the orchestrator (PS 5.1 baseline)
- How to detect PS version and fail loudly on PS 2.0 / 3.0 hosts (Windows 7/8 relics)
- Whether modules use `Begin`/`Process`/`End` blocks or flat scripts (Linux modules are flat; parity suggests flat)
- Exact PSScriptAnalyzer suppression list (Phase 2 will set the lint gate, but Phase 1 should aim for zero findings at default severity so Phase 2 is a rubber-stamp)

### Prior decisions locked from PROJECT.md (re-stated for the planner)

- **Full 6-module parity** — not a subset. All six Windows modules ship in Phase 1.
- **Registry-based package enumeration only** — `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` + `HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall`. **Never** `Win32_Product`. This is not negotiable — `Win32_Product` triggers MSI self-repair across every installed package and would violate the "won't break the host" constraint on 10k+ hosts.
- **No PS Gallery modules, no `Add-Type`, no `Invoke-Expression`, no `iex`, no base64 commands, no `FromBase64String`, no `Net.WebClient`, no `DownloadString`, no network calls of any kind.**
- **EDR / AppLocker / WDAC / Constrained Language Mode compatible** — the orchestrator must run cleanly under CLM. This rules out several otherwise-idiomatic PS patterns (notably `Add-Type` and anything that requires full language mode for reflection).
- **`LocalSystem` service account** — default Splunk UF service account on Windows. Modules must not assume a user profile, `HKCU`, or interactive desktop.
- **Event format is frozen** — `timestamp= hostname= os= run_id= odin_version= type=<type> <fields>`, space-separated, values with spaces double-quoted, embedded quotes backslash-escaped.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (researcher, planner) MUST read these before producing their outputs.**

### Project-level canon
- `CLAUDE.md` — project vision, two-app split, architecture decisions
- `.planning/PROJECT.md` — milestone scope, constraints, key decisions
- `.planning/REQUIREMENTS.md` — v1.0.0 REQ-IDs (WIN-01..12 are this phase's mandate)
- `.planning/ROADMAP.md` — Phase 1 goal + 5 concrete success criteria (grep/command-verifiable)
- `.planning/STATE.md` — milestone state, accumulated context

### Codebase conventions (mandatory reading for planner)
- `.planning/codebase/CONVENTIONS.md` — **the** authoritative source for the Linux module pattern that Windows must mirror. Pay special attention to:
  - Section "Standalone-capable modules" (lines 48–68) — the `declare -f emit` pattern to replicate on Windows
  - Section "Shared `ODIN_*` context variables" (lines 70–85) — the env var contract
  - Section "Output format — space-separated `key=value`" (lines 87–119) — all 8 rules
  - Section "Guardrails — project-wide invariants" (lines 121–136) — the 90s/MAX_EVENTS/timeout-wrapping invariants
  - Section "Error and warning events" (lines 138–142) — the `type=odin_error`/`odin_warning`/`none_found` conventions
  - Section "Things That Must Never Happen" (lines 281–289) — project-wide bans
- `.planning/codebase/STACK.md` — tech stack constraints
- `.planning/codebase/ARCHITECTURE.md` — orchestrator + modules + classification layering
- `.planning/codebase/CONCERNS.md` — known technical debt, especially around Windows gaps
- `.planning/codebase/TESTING.md` — existing test patterns (mostly Python/synthetic-data for tools)

### Reference implementations in the Linux code (planner must read these to produce faithful parity)
- `TA-ODIN/bin/odin.sh` — orchestrator pattern, especially lines 51–66 (`emit()` with MAX_EVENTS accounting) and lines 111–115 (module wrap with `timeout 90`)
- `TA-ODIN/bin/modules/services.sh` — services module reference; lines 19–37 (standalone fallback + `safe_val`)
- `TA-ODIN/bin/modules/ports.sh` — ports module reference; lines 17–35 (same pattern)
- `TA-ODIN/bin/modules/packages.sh` — packages module reference (note: Linux uses `dpkg`/`rpm` batch; Windows uses registry — enumeration source differs, output format does NOT)
- `TA-ODIN/bin/modules/cron.sh` — scheduled task module reference; the Windows equivalent is `scheduled_tasks.ps1`
- `TA-ODIN/bin/modules/processes.sh` — processes module reference
- `TA-ODIN/bin/modules/mounts.sh` — mounts module reference
- `TA-ODIN/default/inputs.conf` — scripted input stanza (`interval = 2592000`, `timeout = 120`)
- `TA-ODIN/default/props.conf` — line-breaking (`LINE_BREAKER = ([\r\n]+)`, `SHOULD_LINEMERGE = false`)

### Splunk-side knowledge (reference only — not modified in Phase 1)
- `ODIN_app_for_splunk/default/props.conf` — `KV_MODE = auto`, CIM aliases, `LOOKUP-*` stanzas
- `ODIN_app_for_splunk/default/transforms.conf` — classification lookup transforms
- `ODIN_app_for_splunk/lookups/odin_classify_*.csv` — classification data (untouched in Phase 1; F group adds Windows rows in v1.1)
- `ODIN_app_for_splunk/default/savedsearches.conf` — three nightly saved searches that aggregate per-host

### External / protocol references
- Microsoft Docs: PowerShell 5.1 built-in cmdlets reference (`Get-Service`, `Get-NetTCPConnection`, `Get-NetUDPEndpoint`, `Get-ScheduledTask`, `Get-ScheduledTaskInfo`, `Get-Process`, `Get-Volume`, `Get-PSDrive`) — researcher should verify parameter sets and output object properties
- Microsoft Docs: `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` registry schema (`DisplayName`, `DisplayVersion`, `Publisher`, `InstallDate`, `UninstallString`)
- Microsoft Docs: `Start-Job` / `Wait-Job -Timeout` / `Stop-Job` / `Receive-Job` semantics under PS 5.1
- Splunk Docs: `splunk-appinspect` check list (Phase 3 reference; Phase 1 should proactively avoid known red flags)
- Splunk Docs: `KV_MODE = auto` parsing rules (to verify the UTF-8 no-BOM + LF choice is safe)

</canonical_refs>

<specifics>
## Specific Ideas

- **WIN-08 verification command (golden-path):** `ODIN_TEST_FIXTURE=1 pwsh TA-ODIN/bin/odin.ps1 | diff - tests/windows-fixtures/expected/golden-iis-box.txt` — this exact invocation should produce zero diff lines against a frozen expected-output file. This is how Phase 1's success criterion #1 ("emits `type=odin_complete modules_total=6 modules_success=6 modules_failed=0`") gets verified on macOS.
- **WIN-12 verification command (fail-soft):** `ODIN_TEST_FIXTURE=1 ODIN_INJECT_FAILURE=services pwsh TA-ODIN/bin/odin.ps1 | grep 'type=odin_error module=services' && grep 'type=odin_complete modules_total=6 modules_success=5 modules_failed=1'` — this verifies that injecting a failure in `services.ps1` yields the correct error event *and* a correct complete marker.
- **Registry enumeration canonical pattern:**
  ```powershell
  $keys = @(
      'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
      'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )
  foreach ($key in $keys) {
      if (Test-Path $key) {
          Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {
              $props = $_ | Get-ItemProperty -ErrorAction SilentlyContinue
              if ($props.DisplayName) {
                  Invoke-OdinEmit "type=package package_name=$(Format-OdinValue $props.DisplayName) package_version=$(Format-OdinValue $props.DisplayVersion) vendor=$(Format-OdinValue $props.Publisher)"
              }
          }
      }
  }
  ```
- **Listening port enumeration canonical pattern:**
  ```powershell
  Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
      Invoke-OdinEmit "type=port listen_port=$($_.LocalPort) transport=tcp listen_address=$(Format-OdinValue $_.LocalAddress) owning_pid=$($_.OwningProcess)"
  }
  Get-NetUDPEndpoint -ErrorAction SilentlyContinue | ForEach-Object {
      Invoke-OdinEmit "type=port listen_port=$($_.LocalPort) transport=udp listen_address=$(Format-OdinValue $_.LocalAddress) owning_pid=$($_.OwningProcess)"
  }
  ```
- **Version string for Phase 1:** hardcode `$ODIN_VERSION = '1.0.0'` in `odin.ps1` and the standalone fallback in `_common.ps1`. This matches the fresh-restart version agreed at milestone kickoff and gives Phase 2 a clean target for HARD-01's single-source-of-truth.
- **CIM aliases on the Splunk side do not care about `os=`**, but we set `ODIN_OS=windows` (not `linux`) in the Windows orchestrator. This matches the Linux convention (`ODIN_OS=linux`) and lets future dashboards partition by `os=` cleanly without needing a new field.

</specifics>

<deferred>
## Deferred Ideas

### To Phase 2 (Production Hardening)
- Full version single-source-of-truth across `app.conf`, `odin.sh`, `odin.ps1` (HARD-01) — Phase 1 hardcodes `1.0.0` in both orchestrators
- Proof of `ODIN_MODULE_TIMEOUT` / `ODIN_MAX_EVENTS` tunability on both orchestrators (HARD-02) — Phase 1 honors env vars if set, but the explicit test fixture for this lives in Phase 2
- Alerting saved searches (HARD-03, HARD-04) — `type=truncated` and `type=odin_error exit_code=124`
- PSScriptAnalyzer CI gate (HARD-06) — Phase 1 aims for zero findings at default severity so this is a rubber-stamp, but the gate itself is Phase 2
- CI two-app-split guard (HARD-07)
- Shell-injection audit of the Linux `safe_val` / `emit` paths (HARD-08) — Linux-side work, scoped into Phase 2

### To Phase 3 (AppInspect)
- All AppInspect compliance work (APPI-01..06)
- Running `splunk-appinspect inspect TA-ODIN/` against the Windows code produced in Phase 1 — Phase 1 should avoid known red flags proactively but Phase 3 is the verification gate

### To v1.1+ (milestones after v1.0.0)
- **Full cross-platform testing harness (group D):** Pester migration for Windows tests, `pwsh`-based parse gate on CI, containerized Linux integration per distro family, `type=odin_complete modules_failed=0` as automated release signal. Phase 1's cmdlet-shadow stubs are the *minimum viable* test bed; v1.1 replaces it with something more maintainable.
- **Documentation (group E):** `DOCS/INSTALL.md`, `DOCS/DATA-DICTIONARY.md` (including the `exit_code=124` convention from D4, the `timeout_reason` field, the UTF-8 no-BOM discipline from D5), `DOCS/SAFETY.md`, `DOCS/TROUBLESHOOTING.md`, `DOCS/RELEASE.md`, README updates.
- **Windows classification coverage (group F):** rows in `odin_classify_services.csv`, `odin_classify_ports.csv`, `odin_classify_packages.csv`, `odin_log_sources.csv` for IIS, MSSQL, AD DS, DNS, DHCP, Exchange, WinRM, etc. None of this lives in Phase 1 — the collection layer ships first, the classification rows ship in v1.1.
- **Reproducible packaging (group G):** Single-source version stamping build script.
- **Windows live-host pilot validation:** User has no Windows hosts during development. Live pilot happens post-release.

### Out of scope entirely (not revisited)
- PowerShell 7 exclusive features — baseline is 5.1
- `Add-Type` / .NET reflection — blocked by Constrained Language Mode and EDR constraints
- Binary / compiled Windows agents — scripting-only is a hard constraint
- Windows service or scheduled-task installation from the TA — Splunk UF itself is the scheduling mechanism

</deferred>

---

*Phase: 01-windows-parity*
*Context gathered: 2026-04-10 via `/gsd-discuss-phase 1` — user accepted 6 leans in one shot*
*Next: `/gsd-plan-phase 1` — research and plan generation will read this file*
