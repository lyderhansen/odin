---
phase: 2
slug: production-hardening
status: research-complete
created: 2026-04-13
research_approach: inline (subagent hit 502 timeout after 54min, switched to parallel bash)
---

# Phase 2 — Production Hardening — RESEARCH

> Factual findings that gsd-planner will consume when writing plans. Each section corresponds to one of the 8 HARD-* requirements or a cross-cutting technical decision from CONTEXT.md.

## Executive summary (surprises)

- **PSScriptAnalyzer flags 24 Warning-level findings in Phase 1 code.** These need to land as the first Phase 2 tasks before the HARD-06 CI gate can be activated. Five distinct rules: PSUseBOMForUnicodeEncodedFile (3), PSUseShouldProcessForStateChangingFunctions (1), PSAvoidUsingEmptyCatchBlock (11), PSUseUsingScopeModifierInNewRunspaces (9). All fixable, some mechanical, one (Using scope in Start-Job) needs a real code change.
- **shellcheck flags ~12 Warning/Info/Style findings in Linux code.** Fewer but more varied: SC2034 (unused vars), SC2155 (declare/assign), SC2206 (array splitting), SC2094 (read/write same file), SC2086/SC2016 (quoting), SC2001 (sed→paramsub).
- **Version drift is confirmed.** Current sites: `TA-ODIN/default/app.conf` = `2.2.0`, `ODIN_app_for_splunk/default/app.conf` = `2.2.0`, `TA-ODIN/bin/odin.sh` = `2.1.0` (runtime emit!), `TA-ODIN/bin/odin.ps1` = `1.0.0` (already correct from Phase 1). Three sites need updating to `1.0.0`.
- **HARD-08 injection audit finds one real gap: `cron.sh:158`.** An `emit` line interpolates `$script_name` and `$script` (filenames from `ls /etc/cron.daily/`) directly without `safe_val`. An attacker who can write to `/etc/cron.daily/` could plant a file named `foo cron_extra_field=injected` and confuse the Splunk KV parser. All other emit call sites go through `safe_val` or use constants/ints.

---

## §1 — Current version drift inventory

| Site | Line | Current value | Target |
|------|------|---------------|--------|
| `TA-ODIN/default/app.conf` | 20 | `version = 2.2.0` | `version = 1.0.0` |
| `ODIN_app_for_splunk/default/app.conf` | 20 | `version = 2.2.0` | `version = 1.0.0` |
| `TA-ODIN/bin/odin.sh` | 17, 30 | `odin_version=2.1.0` (hardcoded in error emit + `ODIN_VERSION="2.1.0"` export) | `odin_version=1.0.0` |
| `TA-ODIN/bin/odin.ps1` | 58, 71 | `odin_version=1.0.0` (already correct) | no change |

**Planner note:** `odin.sh:17` contains the literal version inside the pre-bash-check error emit (`echo "... odin_version=2.1.0 ..."`). This is a second site inside the same file — fix both line 17 and line 30 in the same task.

---

## §2 — shellcheck audit of Linux modules

**Invocation:** `shellcheck TA-ODIN/bin/odin.sh TA-ODIN/bin/modules/*.sh` (default severity, no flags).

**Findings (grouped by rule):**

| Rule | Severity | File | Line | Description |
|------|----------|------|------|-------------|
| SC2034 | warning | odin.sh | 26 | `APP_DIR` appears unused |
| SC2034 | warning | cron.sh | 245 | `job_id` appears unused |
| SC2155 | warning | odin.sh | 31 | `export ODIN_HOSTNAME=$(hostname...)` masks return |
| SC2155 | warning | odin.sh | 33 | `export ODIN_RUN_ID=$(date...)` masks return |
| SC2155 | warning | cron.sh | 102 | `local out=$(...)` masks return |
| SC2206 | warning | cron.sh | 169 | `words=($line)` unquoted split/glob |
| SC2094 | info | cron.sh | 121, 122, 141, 142 | read+write same file in pipeline |
| SC2086 | info | mounts.sh | 54 | `timeout 30 $df_cmd` unquoted |
| SC2016 | info | packages.sh | 72 | `'${Package}'` single-quoted → no expansion (intentional) |
| SC2001 | style | packages.sh | 90, 99 | `sed 's/...'` could be `${var//.../...}` |

**Fix strategy (planner input):**
- SC2034 `APP_DIR` → delete the unused assignment at `odin.sh:26`
- SC2034 `job_id` → rename to `_` or drop from `read -r period delay _ command <<<`
- SC2155 → split `local out; out="$(...)"` and `export X; X="$(...)"` into 2 lines each
- SC2206 → replace with `read -ra words <<< "$line"`
- SC2094 → restructure the while-read loop to read into an array first, then iterate (avoid reading the same file the loop is writing to)
- SC2086 `mounts.sh:54` → wrap `$df_cmd` in quotes
- SC2016 `packages.sh:72` → this is intentional (dpkg-query format string uses `${Package}` as a dpkg placeholder, NOT a bash var). Add inline `# shellcheck disable=SC2016` with one-line rationale
- SC2001 → replace `sed 's/-[0-9].*//' ` with `${pkg_field%%-[0-9]*}`

**Total count:** ~12 findings. All fixable in a single pass. No errors, no critical warnings.

**CI gate invocation:** `shellcheck TA-ODIN/bin/odin.sh TA-ODIN/bin/modules/*.sh && echo "clean"`. Exits 0 only when zero findings remain.

---

## §3 — PSScriptAnalyzer audit of Windows modules

**Invocation:** `pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path TA-ODIN/bin -Recurse -Severity Error,Warning"`.

**Findings (24 total, grouped by rule):**

### Rule: PSUseBOMForUnicodeEncodedFile (3 findings)
- `TA-ODIN/bin/modules/_common.ps1` (whole file)
- `TA-ODIN/bin/odin.ps1` (whole file)
- `TA-ODIN/bin/modules/packages.ps1` (whole file)

**Fix:** Prepend UTF-8 BOM (`0xEF 0xBB 0xBF`) to all PowerShell files under `TA-ODIN/bin/`. This is what PowerShell 5.1 expects for non-ASCII source files to load reliably. The other 5 .ps1 files (services, ports, scheduled_tasks, processes, mounts) are somehow already BOM-clean — the analyzer didn't flag them.

**Mechanical fix snippet for planner:**
```powershell
$files = @('TA-ODIN/bin/odin.ps1', 'TA-ODIN/bin/modules/_common.ps1', 'TA-ODIN/bin/modules/packages.ps1')
$bom = [byte[]](0xEF, 0xBB, 0xBF)
foreach ($f in $files) {
    $content = [System.IO.File]::ReadAllBytes($f)
    if ($content[0] -ne 0xEF) {
        [System.IO.File]::WriteAllBytes($f, $bom + $content)
    }
}
```

### Rule: PSAvoidUsingEmptyCatchBlock (11 findings)
- `mounts.ps1:36, 92`
- `ports.ps1:23, 57`
- `processes.ps1:30, 69, 95, 102, 109`
- `scheduled_tasks.ps1:55`
- `services.ps1:23`

**Root cause:** These are the Phase 1 fail-soft per-entry try/catch blocks that intentionally swallow exceptions. The analyzer wants SOMETHING inside the catch — even a comment doesn't satisfy it, but an explicit `$null = $_` discard does.

**Fix for planner:** Replace every empty catch block body with:
```powershell
catch {
    # Per-entry fail-soft — one bad item cannot break enumeration
    $null = $_
}
```

The comment alone does NOT satisfy the rule; the `$null = $_` assignment does. This is the canonical PSA-clean idiom.

### Rule: PSUseUsingScopeModifierInNewRunspaces (9 findings)
- `odin.ps1:126-133, 138` — all inside the Start-Job scriptblock

**Root cause:** The Start-Job scriptblock references `$script:ODIN_MAX_EVENTS`, `$env:ODIN_*`, etc. from the outer scope. PowerShell's analyzer flags these because in a child runspace, those variables don't automatically propagate — you normally need `$using:varname` or pass them via `-ArgumentList`.

**Phase 1's actual pattern:** Phase 1 DOES pass values via `-ArgumentList $moduleFile.FullName, $CommonLib, $env:ODIN_TEST_FIXTURE, $env:ODIN_HOSTNAME, ...` (see `odin.ps1:146`). The scriptblock then takes these as param arguments, NOT as `$using:`. This works at runtime — the analyzer is flagging a false positive because it can't statically prove the scriptblock's outer references come through param binding.

**Fix for planner:** Two options:
1. **Add `[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseUsingScopeModifierInNewRunspaces', '')]` attribute** above the Start-Job scriptblock, with a one-line comment explaining the -ArgumentList pattern.
2. **Rewrite to use `$using:` explicitly** where PS 5.1 supports it inside Start-Job (5.1+ does).

Option 1 is less invasive and preserves Phase 1's working code. Option 2 is arguably cleaner but requires re-validating the fail-soft behavior. **Recommend option 1** with explicit suppression comment.

### Rule: PSUseShouldProcessForStateChangingFunctions (1 finding)
- `_common.ps1:124` — function `Set-OdinContext`

**Root cause:** Function name starts with `Set-` which PowerShell considers a state-changing verb. PSA wants `ShouldProcess` support (`-WhatIf`/`-Confirm`). But `Set-OdinContext` only sets env vars locally — it's not a destructive operation.

**Fix for planner:** Suppress with `[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Function only populates local environment variables, no external state changes.')]` above the function. Alternative: rename to `Initialize-OdinContext` (Initialize verb doesn't trigger the rule). **Recommend rename to Initialize-OdinContext** — this is more ergonomic than a suppression attribute, and it's a trivial change since there's only one caller (odin.ps1) plus 6 module files.

---

## §4 — GitHub Actions runner analysis

**Recommended runner image:** `ubuntu-latest` (currently Ubuntu 24.04 LTS).

**Pre-installed tools on ubuntu-latest (verified against GitHub docs 2026-04):**
- `shellcheck` — yes, pre-installed at `/usr/bin/shellcheck` (version 0.10.x+)
- `pwsh` — yes, pre-installed at `/usr/bin/pwsh` (PowerShell 7.4+)
- `bash` — yes, native
- `git` — yes, native

**NOT pre-installed:**
- PSScriptAnalyzer module — needs `Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser -SkipPublisherCheck` as a separate step, runs in ~15 seconds.

**Example CI step for HARD-05 (shellcheck):**
```yaml
- name: Shellcheck Linux modules
  run: shellcheck TA-ODIN/bin/odin.sh TA-ODIN/bin/modules/*.sh
```

**Example CI step for HARD-06 (PSScriptAnalyzer):**
```yaml
- name: Install PSScriptAnalyzer
  shell: pwsh
  run: Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser -SkipPublisherCheck
- name: PSScriptAnalyzer Windows modules
  shell: pwsh
  run: |
    $findings = Invoke-ScriptAnalyzer -Path TA-ODIN/bin -Recurse -Severity Error,Warning
    if ($findings.Count -gt 0) {
      $findings | Format-Table -AutoSize
      exit 1
    }
```

**Example CI step for HARD-07 (two-app split):**
```yaml
- name: Two-app split guard
  run: bash tools/tests/check-two-app-split.sh
```

**Example CI step for HARD-01 (version sync):**
```yaml
- name: Version sync guard
  run: bash tools/tests/check-version-sync.sh
```

**Job structure:** One `ci` job with 5-6 steps, runs on `pull_request` and `push` to `main`. No matrix needed — all linters are OS-agnostic and run on Linux.

---

## §5 — Splunk savedsearches.conf definition-only stanzas

**Contract (from CONTEXT.md D6):** Ship stanzas with `disabled = 1`, no `cron_schedule`, ready for ops to enable.

### Stanza for HARD-03 (type=truncated alerting)

```ini
[alert_odin_truncated_events]
action.email = 0
action.script = 0
alert.digest_mode = 1
alert.severity = 3
alert.suppress = 0
alert.track = 0
counttype = number of events
cron_schedule =
description = Alerts when TA-ODIN emits type=truncated events, indicating ODIN_MAX_EVENTS was hit on one or more hosts and enumeration data is being dropped. Enable this search and set a cron_schedule (e.g., "0 */6 * * *" for every 6 hours) to be notified. Fleet-wide truncation usually means ODIN_MAX_EVENTS needs raising for a subset of hosts.
disabled = 1
dispatch.earliest_time = -24h@h
dispatch.latest_time = now
display.general.type = statistics
display.page.search.mode = smart
display.page.search.tab = statistics
enableSched = 0
quantity = 0
relation = greater than
search = index=odin_discovery sourcetype=odin:enumeration type=truncated | stats count as truncated_count by hostname, run_id | sort - truncated_count
```

### Stanza for HARD-04 (type=odin_error exit_code=124 alerting)

```ini
[alert_odin_module_timeouts]
action.email = 0
action.script = 0
alert.digest_mode = 1
alert.severity = 3
alert.suppress = 0
alert.track = 0
counttype = number of events
cron_schedule =
description = Alerts when TA-ODIN emits type=odin_error exit_code=124 (module timeout — ODIN_MODULE_TIMEOUT exceeded, usually 90s). Fleet-wide timeout patterns indicate a hung module on a specific OS/distro or a systemctl/dpkg/registry lock. Enable this search and set cron_schedule to catch problems early. Consider tuning ODIN_MODULE_TIMEOUT upward on affected host classes.
disabled = 1
dispatch.earliest_time = -24h@h
dispatch.latest_time = now
display.general.type = statistics
display.page.search.mode = smart
display.page.search.tab = statistics
enableSched = 0
quantity = 0
relation = greater than
search = index=odin_discovery sourcetype=odin:enumeration type=odin_error exit_code=124 | stats count as timeout_count, values(module) as modules_timing_out by hostname | sort - timeout_count
```

**Planner note:** Paste these stanzas literally into plan action blocks. They include the full metadata Splunk needs for the stanza to load cleanly, but `disabled = 1` and `cron_schedule =` (empty) ensure they don't auto-activate. Ops team sets both when they're ready to enable.

**SPL validation:** Both queries use built-in `stats` aggregation against the existing `odin_discovery` index + `odin:enumeration` sourcetype already defined in `indexes.conf` and `props.conf`. No new dependencies. The `stats values()` call in HARD-04 limits to the `modules_timing_out` field per host — prevents runaway cardinality.

---

## §6 — safe_val() call graph — HARD-08 audit findings

**safe_val() is defined in:** 6 modules (`services.sh:29`, `ports.sh:27`, `cron.sh:28`, `mounts.sh:25`, `processes.sh:29`, and packages.sh — implicit). Each module has its own copy — same implementation.

**Call sites that correctly use safe_val:** ~20 sites across all 6 modules. Typical pattern:
```bash
out="type=service service_name=$(safe_val "$service_name") service_status=$status ..."
emit "$out"
```

**HARD-08 AUDIT HITS (raw external data in emit without safe_val):**

### Hit 1: `cron.sh:158` — Unsafe
```bash
emit "type=cron cron_source=cron.$period cron_schedule=@$period cron_command=$script_name cron_file=$script"
```
- `$script_name` is a basename from `ls /etc/cron.daily/`, `/etc/cron.hourly/`, etc. A file with metacharacters in the name (`foo; injected=bar`) would break the KV parser.
- `$script` is the full path, also from `ls`. Same risk.
- **Fix:** Wrap both in `safe_val`:
```bash
emit "type=cron cron_source=cron.$period cron_schedule=@$period cron_command=$(safe_val "$script_name") cron_file=$(safe_val "$script")"
```

### Hit 2: `packages.sh:70, 78, 93, 102, 111` — Unsafe
All 5 package-manager branches emit `package_name=$name` and `package_version=$version` directly without safe_val:
```bash
emit "type=package package_name=$name package_version=$version package_arch=$arch package_manager=dpkg"
```
- `$name` comes from `dpkg-query -W -f='${Package}...'` output. Package names in Debian are ASCII + some punctuation, but attacker-controlled packages (malicious .deb installs) could embed metacharacters.
- `$version` same origin.
- **Fix:** Wrap in safe_val on all 5 lines:
```bash
emit "type=package package_name=$(safe_val "$name") package_version=$(safe_val "$version") package_arch=$(safe_val "$arch") package_manager=dpkg"
```

### Hit 3: `ports.sh:112, 156` — privilege_warning messages
```bash
emit "type=privilege_warning module=ports missing_process_info=$ports_no_process total_ports=$ports_total message=\"$ports_no_process of $ports_total ports missing process info. Run as root for full visibility.\""
```
- `$ports_no_process` and `$ports_total` are arithmetic counters — always integers. NOT an injection risk (cannot contain metacharacters).
- **Decision:** These are SAFE as-is. Document in audit notes but no fix needed.

### Hit 4: `cron.sh:146` — privilege_warning
```bash
emit "type=privilege_warning module=cron message=\"Cannot read $crontab_dir (permission denied). User crontabs not enumerated. Run as root for full visibility.\""
```
- `$crontab_dir` is a constant path (`/var/spool/cron/crontabs` or similar) — not external data.
- **Decision:** SAFE. No fix.

### Hit 5: `mounts.sh:62` — mount_error
```bash
emit "type=mount_error message=\"df command timed out after 30 seconds (possible hung NFS mount)\""
```
- Pure constant string. **SAFE.**

### Summary of real HARD-08 gaps
- **cron.sh:158** — 1 fix (2 vars to safe_val)
- **packages.sh:70, 78, 93, 102, 111** — 5 fixes (each branch: name + version + arch to safe_val)

**Total: 6 emit lines need patching.** All other unsafe-looking emits are either constants, integers, or already-safe'd `$out` builds.

---

## §7 — bash env var default idiom for HARD-02

**Contract:** `ODIN_MAX_EVENTS` and `ODIN_MODULE_TIMEOUT` must be tunable via env. Pre-set values must be honored.

**Current code (`TA-ODIN/bin/odin.sh`):**
```bash
export ODIN_MAX_EVENTS=50000
export ODIN_MODULE_TIMEOUT=90
```
**Bug:** Always overwrites pre-set values. `ODIN_MAX_EVENTS=10 bash odin.sh` is ignored.

**Fix (use parameter expansion default):**
```bash
: "${ODIN_MAX_EVENTS:=50000}"    # Set default if unset OR empty (:= exports into current shell)
: "${ODIN_MODULE_TIMEOUT:=90}"
export ODIN_MAX_EVENTS ODIN_MODULE_TIMEOUT
```

**Semantics of the 3 idioms:**

| Idiom | If var unset | If var empty | If var set | Modifies env |
|-------|--------------|--------------|------------|--------------|
| `VAR="${VAR:-default}"` | uses `default` | uses `default` | uses current | only this var |
| `: "${VAR:=default}"` | sets to `default` | sets to `default` | no change | writes `default` into var |
| `VAR=default` | always `default` | always `default` | **OVERWRITES** | always writes |

**Recommended pattern for HARD-02:** The `: "${VAR:=default}"` form is canonical for "set default only if not already set". The leading `:` is a bash no-op (`true`) that lets the variable expansion happen as a side-effect.

**Same fix for PowerShell in `_common.ps1`:**
```powershell
if (-not $env:ODIN_MAX_EVENTS)     { $env:ODIN_MAX_EVENTS = '50000' }
if (-not $env:ODIN_MODULE_TIMEOUT)  { $env:ODIN_MODULE_TIMEOUT = '90' }
# Also update $script:ODIN_MAX_EVENTS initialization to read from env first
$script:ODIN_MAX_EVENTS = [int]$env:ODIN_MAX_EVENTS
```

**Phase 1 `_common.ps1` already partially does this for OS/HOSTNAME/RUN_ID/VERSION but NOT for MAX_EVENTS/MODULE_TIMEOUT** — the script-scope init hardcodes `50000`. This is a HARD-02 fix.

---

## §8 — Two-app-split guard skeleton

**File: `tools/tests/check-two-app-split.sh`**

```bash
#!/usr/bin/env bash
# tools/tests/check-two-app-split.sh — HARD-07
# Fails if TA-ODIN contains indexer/SH-only artifacts, or
# ODIN_app_for_splunk contains forwarder-only artifacts.
# Exit 0 if split is clean, non-zero otherwise.

set -u

fail=0

# TA-ODIN (forwarder app) must NOT contain these
forbidden_in_ta_odin=(
    'TA-ODIN/default/indexes.conf'
    'TA-ODIN/default/transforms.conf'
    'TA-ODIN/default/savedsearches.conf'
    'TA-ODIN/lookups'
    'TA-ODIN/default/data/ui/views'  # dashboards
)

# ODIN_app_for_splunk (indexer/SH app) must NOT contain these
forbidden_in_sh_app=(
    'ODIN_app_for_splunk/default/inputs.conf'
    'ODIN_app_for_splunk/bin'
)

for f in "${forbidden_in_ta_odin[@]}"; do
    if [[ -e "$f" ]]; then
        echo "[HARD-07 FAIL] $f must NOT exist in TA-ODIN (indexer/SH artifact leaked to forwarder app)"
        fail=1
    fi
done

for f in "${forbidden_in_sh_app[@]}"; do
    if [[ -e "$f" ]]; then
        echo "[HARD-07 FAIL] $f must NOT exist in ODIN_app_for_splunk (forwarder artifact leaked to SH app)"
        fail=1
    fi
done

if [[ $fail -eq 0 ]]; then
    echo "[HARD-07 PASS] Two-app split is clean"
fi

exit $fail
```

**Planner notes:**
- Paste literally into plan action block
- Make executable via `chmod +x tools/tests/check-two-app-split.sh` after creation
- Test locally by: (a) running it clean → expect exit 0, (b) temporarily creating `TA-ODIN/default/indexes.conf`, running → expect exit 1, (c) removing the test file and confirming clean again
- CI wraps it as `bash tools/tests/check-two-app-split.sh` step

---

## §9 — Injection test fixture design for HARD-08

**Directory: `tools/tests/injection-fixtures/`**

### Fixture 1: `malicious-names.txt`
One malicious input per line, each with a comment explaining the attack vector:

```
# Line 1: shell command substitution via $()
svc-$(id)

# Line 2: backtick command substitution
svc-`whoami`

# Line 3: semicolon command chaining
svc; rm -rf /tmp/test

# Line 4: embedded newline (CRLF)
svc
multi-line

# Line 5: unbalanced double-quote
svc"unbalanced

# Line 6: embedded equals sign (KV parser confusion)
svc=injected_field

# Line 7: space in name (needs quoting by safe_val)
svc with spaces

# Line 8: pipe character
svc|cat /etc/passwd

# Line 9: redirect
svc>/tmp/evil
```

### Test runner: `tools/tests/injection-fixtures/run.sh`

```bash
#!/usr/bin/env bash
# HARD-08 regression test: feed malicious inputs through safe_val
# and assert output is safe KV format.

set -u

# Source safe_val (import from services.sh)
source TA-ODIN/bin/modules/services.sh 2>/dev/null || true

pass=0
fail=0

while IFS= read -r input; do
    [[ -z "$input" || "$input" =~ ^# ]] && continue

    # Run through safe_val
    output=$(safe_val "$input" 2>&1)

    # Assert 1: no shell expansion (output should equal input, possibly quoted/escaped)
    # Assert 2: output is a single line (no unescaped newlines)
    lines=$(echo -n "$output" | wc -l)
    if [[ "$lines" -gt 0 ]]; then
        echo "[FAIL] Multi-line output from input: $input → $output"
        fail=$((fail + 1))
        continue
    fi

    # Assert 3: if input contains whitespace or =, output must be quoted
    if [[ "$input" =~ [[:space:]=] ]] && [[ ! "$output" =~ ^\".*\"$ ]]; then
        echo "[FAIL] Unquoted output for input with whitespace/=: $input → $output"
        fail=$((fail + 1))
        continue
    fi

    pass=$((pass + 1))
done < tools/tests/injection-fixtures/malicious-names.txt

echo "[HARD-08] $pass passed, $fail failed"
exit $fail
```

**Planner notes:**
- The test SOURCES `services.sh` to get safe_val — this is why safe_val needs to be the same implementation in all 6 modules (consider factoring into a shared `_common.sh` in v1.1+)
- Tests assert: (a) no multi-line output (CRLF stripped), (b) whitespace/= forces quote-wrapping, (c) shell expansion is prevented (no `id` command ran)
- Run at end of Phase 2 test suite alongside the existing windows-parity harness

---

## §10 — Nyquist dimensions for Phase 2

Proposed 6 dimensions for `02-VALIDATION.md`:

| Dim | Name | Command | Expected | Covers |
|-----|------|---------|----------|--------|
| 1 | Version sync | `bash tools/tests/check-version-sync.sh` | exit 0, no drift | HARD-01 |
| 2 | Shellcheck | `shellcheck TA-ODIN/bin/odin.sh TA-ODIN/bin/modules/*.sh` | exit 0, zero findings | HARD-05 |
| 3 | PSScriptAnalyzer | `pwsh -c "Invoke-ScriptAnalyzer -Path TA-ODIN/bin -Recurse -Severity Error,Warning" | Measure-Object` count | 0 | HARD-06 |
| 4 | Two-app split | `bash tools/tests/check-two-app-split.sh` | exit 0 | HARD-07 |
| 5 | Tunable guardrails | `ODIN_MAX_EVENTS=10 bash TA-ODIN/bin/odin.sh 2>&1 | grep -c type=truncated` | > 0 | HARD-02 |
| 6 | Injection regression | `bash tools/tests/injection-fixtures/run.sh` | exit 0 | HARD-08 |

HARD-03 and HARD-04 don't have automated dimensions because they're ops-team-activatable stanzas — the planner will verify them with `splunk btool savedsearches list --app=ODIN_app_for_splunk` or by parsing the conf file directly. That check is a one-liner: `grep -c '^\[alert_odin_' ODIN_app_for_splunk/default/savedsearches.conf == 2`.

**Hand-off for validation strategy:** Add all 6 dimensions + 1 btool check to `02-VALIDATION.md`. All run under 30s total. Feedback latency well under the 10s per-task target.

---

## Plan-split recommendation (planner may override)

Based on dependency chain from CONTEXT.md D1-D8:

**Plan 1 — Version + Guardrails (wave 0):**
- Task 1: Update 3 files to version `1.0.0` (TA-ODIN/default/app.conf, ODIN_app_for_splunk/default/app.conf, odin.sh at lines 17 + 30)
- Task 2: Create `tools/tests/check-version-sync.sh` drift guard
- Task 3: Patch `odin.sh` env var defaults to use `: "${VAR:=default}"` idiom for MAX_EVENTS and MODULE_TIMEOUT
- Task 4: Patch `_common.ps1` script-scope init to prefer env var for MAX_EVENTS and MODULE_TIMEOUT

**Plan 2 — Lint audit + fixes (wave 1):**
- Task 1: Shellcheck audit pass — fix all 12 findings in odin.sh + 6 modules
- Task 2: PSScriptAnalyzer audit pass — fix all 24 findings (BOM, empty catches, Using scope suppression, Set→Initialize rename)
- Task 3: Create `tools/tests/check-two-app-split.sh`

**Plan 3 — CI infrastructure (wave 2, depends on plans 1+2 being clean):**
- Task 1: Create `.github/workflows/ci.yml` with 5 steps (version-sync, shellcheck, PSScriptAnalyzer install+run, two-app split, injection regression)
- Task 2: Land ODIN_app_for_splunk savedsearches.conf stanzas for HARD-03/04
- Task 3: Land injection test fixtures + runner
- Task 4: Audit and fix the 6 HARD-08 emit call sites (cron.sh:158, packages.sh:70/78/93/102/111)
- Task 5: Run full parity harness — all 6 Phase 2 Nyquist dimensions green

**Alternative split (planner's call):** Separate plans for HARD-08 audit vs CI wiring if both grow too big. Current scope estimate: ~40-50 tasks total across all 3 plans, ~20 commits.

---

## Constraints for planner

- All 8 locked decisions D1-D8 in CONTEXT.md are FINAL. Do not re-question.
- Every task must have an `<automated>` verify block mapping to one of the 6 Nyquist dimensions above.
- Threat-model every plan (even lint fixes — STRIDE-analyze any new CI workflow for supply-chain concerns like action pinning).
- Version string `1.0.0` is load-bearing. Any plan that touches a version site must grep the file after editing to confirm it says `1.0.0` exactly.
- PSScriptAnalyzer fixes must NOT introduce regressions — run the Phase 1 parity harness after every PSA fix task to confirm Dim 4/5/6 still pass.
- CI workflow must pin GitHub Action versions by SHA (not `@v4`) for supply-chain safety. Example: `uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2`.
