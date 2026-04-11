# Research — Phase 1: Windows Parity

**Phase:** 01-windows-parity
**Created:** 2026-04-11
**Inputs:** 01-CONTEXT.md (D1–D6), REQUIREMENTS.md (WIN-01..12), CLAUDE.md
**Method:** Inline web research (~15 queries) after `gsd-phase-researcher` subagent failed with 502

---

## Summary

Phase 1 requires a PowerShell 5.1+ orchestrator and six modules that emit byte-for-byte identical `key=value` events to the Linux side so existing search-time lookups, CIM aliases, and saved searches work unchanged on Windows data. Research validates the core architecture from CONTEXT.md but surfaces **two Constrained Language Mode (CLM) compatibility risks** that must be addressed before implementation:

1. **D1 risk — `Start-Job` under system-wide WDAC/UMCI:** When the host enforces CLM globally and TA-ODIN is not allowlisted, `Start-Job` fails with a language-mode-mismatch error. Mitigation: fall back to a Runspace-based timeout wrapper, or require customers to allowlist the TA via their WDAC policy.
2. **D5 risk — `[System.Console]` is not a CLM-allowed type:** `[Console]::OutputEncoding = ...` and `[Console]::Out.Write(...)` both throw under CLM. Mitigation: use `Write-Output` + `$OutputEncoding` + explicit `-NoNewline` line assembly, which stays inside CLM-permitted surface.

Everything else (Win32_Product hazard, registry Uninstall schema, function-over-cmdlet precedence, pwsh-on-macOS parity, Splunk UF `.path` wrapper invocation) confirms the locked decisions.

---

## 1. PowerShell 5.1 Cmdlet Reference (per module)

All cmdlets below ship **in-box** on Windows Server 2019/2022 and Windows 10/11 and are callable under `LocalSystem`.

| Module | Primary cmdlet(s) | Key output properties | Notes |
|---|---|---|---|
| services | `Get-Service` + `Get-CimInstance Win32_Service` | Name, DisplayName, Status, StartMode (Cim), PathName (Cim), StartName (Cim) | `Get-Service` alone lacks StartMode and ImagePath — CIM join required |
| ports | `Get-NetTCPConnection -State Listen` + `Get-NetUDPEndpoint` | LocalAddress, LocalPort, State, OwningProcess | UInt16 port, UInt32 pid; available since Win 8 / Server 2012 |
| packages | `Get-ChildItem HKLM:\...\Uninstall` + `Get-ItemProperty` | DisplayName, DisplayVersion, Publisher, SystemComponent, ParentKeyName | **Never `Win32_Product`** — see §5 |
| scheduled_tasks | `Get-ScheduledTask` + `Get-ScheduledTaskInfo` | TaskName, TaskPath, State, Author; LastRunTime, LastTaskResult, NextRunTime | Two cmdlets because Get-ScheduledTask lacks run-time metadata |
| processes | `Get-Process` + `Get-CimInstance Win32_Process` | Id, Name, Path; CommandLine (Cim) | `Get-Process` has no CommandLine; CIM join required |
| mounts | `Get-Volume` + `Get-PSDrive -PSProvider FileSystem` | DriveLetter, FileSystemLabel, FileSystemType, Size, SizeRemaining | Get-Volume for physical, Get-PSDrive for mapped/virtual |

**Reference:** Microsoft Learn — `Get-NetTCPConnection` (NetTCPIP module), `Get-ScheduledTask` (ScheduledTasks module), `Get-CimInstance` (CimCmdlets).

---

## 2. Start-Job / Wait-Job / Stop-Job Behavior (D1 validation)

**Canonical pattern** for bounded per-module execution:

```powershell
$job = Start-Job -ScriptBlock { . $using:ModulePath }
if (Wait-Job $job -Timeout $TimeoutSec) {
    Receive-Job $job
} else {
    Stop-Job $job
    Remove-Job $job -Force
    # synthesize exit_code=124 (D4)
}
Remove-Job $job -Force
```

### Validated
- `Wait-Job -Timeout` returns `$null` on timeout (not an exception) — clean branching.
- `Stop-Job` terminates the background PowerShell process synchronously.
- `Receive-Job` surfaces the job's stdout as pipeline objects; combined with `Out-String` it gives raw text for emit.

### ⚠ Risk: CLM behavior is conditional
Per Microsoft's `about_Language_Modes` documentation:
- **If the host is not locked down:** `Start-Job` launches a new `powershell.exe` child that runs in **FullLanguage** by default, regardless of the parent session's language mode.
- **If the host is locked down via system-wide WDAC/UMCI:** the child process inherits CLM from the OS policy. Because `Start-Job` serializes the ScriptBlock via the FullLanguage parent and deserializes it in the CLM child, the child refuses the script block with a language-mode-mismatch error **unless the TA-ODIN script files are allowlisted in the WDAC policy**.

### Mitigation options
1. **Allowlist path (preferred for enterprise customers):** Document that `TA-ODIN/bin/**/*.ps1` must be code-signed or path-allowlisted in the customer's WDAC policy. This is typical for any script-based Splunk TA on a locked-down host and is called out in `DOCS/SAFETY.md` (deferred to v1.1).
2. **Runspace fallback:** Implement timeout via `[RunspaceFactory]::CreateRunspace()` + `PowerShell.BeginInvoke()` + `AsyncWaitHandle.WaitOne($TimeoutSec*1000)`. Runspaces execute in-process and inherit the parent's language mode, so no cross-boundary serialization issue. Downside: `[System.Management.Automation.PowerShell]` and `[System.Management.Automation.Runspaces.RunspaceFactory]` are themselves **not** on the CLM allowed-types list, so this fallback is **also** CLM-incompatible without allowlisting.
3. **Serial fallback with external-command timeout:** If both Start-Job and Runspace are blocked, the only remaining option is to run modules serially in-process and rely on per-command `Stop-Process`-style watchdogs. This would break the "bounded per-module timeout" success criterion and is **not recommended**.

**Decision for the planner:** Keep D1 (Start-Job) as primary. Document the WDAC allowlisting requirement in the plan's "Operational Prerequisites" section. Do not add a Runspace fallback in Phase 1 — it doesn't actually solve the CLM problem and adds complexity.

---

## 3. Command Resolution: Function-over-Cmdlet Precedence (D3 validation)

Per Microsoft's `about_Command_Precedence`, PowerShell resolves unqualified names in this order:

1. **Alias**
2. **Function** ← our cmdlet-shadow stubs live here
3. **Cmdlet**
4. **External application**

A function named `Get-Service` reliably shadows the built-in `Get-Service` cmdlet for the remainder of the session. Dot-sourcing a stubs file under `$env:ODIN_TEST_FIXTURE` will therefore replace the Windows-only cmdlets with macOS-runnable stubs before any module calls them.

**Gotcha:** If a module uses the fully-qualified form `Microsoft.PowerShell.Management\Get-Service`, it bypasses the function and calls the cmdlet directly. **Discipline:** Windows modules must use unqualified cmdlet names throughout.

**Reference:** Microsoft Learn — `about_Command_Precedence`; confirmed by multiple community posts (stackoverflow.com/q/29538644, reddit r/PowerShell threads).

---

## 4. Cmdlet-Shadow Stubs on macOS pwsh (D6 validation)

`pwsh` on macOS (PowerShell 7+) **does not ship** the Windows-only modules (`ScheduledTasks`, `NetTCPIP`, `Microsoft.PowerShell.Management`'s Windows-specific cmdlets like `Get-Service`'s CIM join, registry drives). Attempting to invoke them produces `The term 'Get-NetTCPConnection' is not recognized...`.

However, because **function resolution beats cmdlet resolution** (§3), dot-sourcing a stubs file at the top of the orchestrator under `$env:ODIN_TEST_FIXTURE` registers functions with the same names before any module runs. Inside macOS `pwsh`:

```powershell
function Get-NetTCPConnection { ... return fixture objects ... }
function Get-ScheduledTask    { ... return fixture objects ... }
# etc.
```

These functions are resolved first — the fact that the underlying cmdlet doesn't exist on macOS is irrelevant.

**Validation command** (for the planner to bake into tests):
```bash
ODIN_TEST_FIXTURE=tests/windows-fixtures/hostA pwsh TA-ODIN/bin/odin.ps1 \
  | tee /tmp/odin-out.txt
grep -c '^type=' /tmp/odin-out.txt
```

---

## 5. Win32_Product MSI Self-Repair (confirms WIN-04 hard constraint)

Multiple authoritative sources confirm that enumerating installed software via `Get-CimInstance Win32_Product` or `Get-WmiObject Win32_Product` triggers the Windows Installer service to perform a **consistency check on every installed MSI package**, and **silently initiates repair** on any package where the consistency check fails.

**Sources:**
- Microsoft KB 974524 — "Event log message indicates that the Windows Installer reconfigured all installed applications"
- xkln.net — "Stop using Win32_Product" (2020)
- Greg Ramsey, Microsoft MVP — blog post on MSI repair side-effects

**Impact for TA-ODIN:** Running `Win32_Product` on a 10k-host fleet during an ODIN scan could silently reinstall or repair arbitrary MSIs, causing:
- Unintended service restarts
- Configuration resets on packages with broken uninstall data
- Event log noise that looks like a malware-triggered remediation

**Validates WIN-04's registry-only approach without exception.** The planner should add a PSScriptAnalyzer custom rule or a grep gate in Phase 2 HARD-06 to fail CI if `Win32_Product` ever appears in the Windows code.

---

## 6. Registry Uninstall Key Schema (WIN-04 implementation detail)

**Keys to scan:**
- `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` (64-bit + 32-bit-on-32-bit)
- `HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall` (32-bit-on-64-bit)
- `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` — **skip** (per-user installs are rare under LocalSystem and not relevant to host-wide enumeration)

**Guaranteed properties (present on almost all entries):**
| Property | Type | Notes |
|---|---|---|
| DisplayName | String | Primary field for `package_name=` — **skip entry if absent** (system components, patches) |
| DisplayVersion | String | Maps to `package_version=` |
| Publisher | String | Maps to `vendor=` |
| UninstallString | String | Command to uninstall — useful for disambiguation but not emitted |

**Filter properties (exclude entries where any are truthy):**
| Property | Type | Reason to filter |
|---|---|---|
| SystemComponent | DWORD (0/1) | `=1` means Windows treats this as invisible system update |
| ParentKeyName | String | Non-null means this is a patch/update under a parent product |
| ReleaseType | String | Values like `"Hotfix"`, `"Security Update"`, `"Update Rollup"` should be filtered to reduce noise |

**Reference pattern (from CONTEXT.md, validated):**
```powershell
$keys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
foreach ($key in $keys) {
    if (Test-Path $key) {
        Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {
            $props = $_ | Get-ItemProperty -ErrorAction SilentlyContinue
            if ($props.DisplayName -and -not $props.SystemComponent -and -not $props.ParentKeyName) {
                Invoke-OdinEmit "type=package package_name=$(Format-OdinValue $props.DisplayName) package_version=$(Format-OdinValue $props.DisplayVersion) vendor=$(Format-OdinValue $props.Publisher)"
            }
        }
    }
}
```

---

## 7. Output Encoding Under CLM (D5 risk — blocker)

### Finding
Microsoft's `about_Language_Modes` for PowerShell 5.1 publishes an explicit whitelist of types that CLM permits. The whitelist includes common primitives (`[string]`, `[int]`, `[array]`, `[hashtable]`, `[xml]`, `[pscredential]`, `[wmi]`, `[CimInstance]`, `[CimSession]`, …) but **does NOT include**:
- `[System.Console]`
- `[System.Text.UTF8Encoding]`
- `[System.Text.Encoding]`
- `[System.IO.StreamWriter]`

D5's canonical pattern from CONTEXT.md:
```powershell
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::Out.Write("$line`n")
```

**Both lines throw under CLM** with `Cannot invoke method. Method invocation is supported only on core types in this language mode.`

### Mitigation — CLM-safe output path
Use only allowed surface:

```powershell
# In odin.ps1 top, before any emit:
$OutputEncoding = New-Object System.Text.UTF8Encoding $false  # NOT allowed under CLM either

# CLM-compatible alternative: rely on PS 5.1 default pipeline encoding
# + use Write-Output (which goes through the Success stream, not [Console]).
```

**Problem:** `New-Object System.Text.UTF8Encoding` is also blocked under CLM because `[System.Text.UTF8Encoding]` is not on the allow-list.

**Working CLM-safe approach:**
1. **Do nothing about encoding in-script.** Rely on the fact that PowerShell 5.1's default output encoding for `powershell.exe` stdout is **the console's code page**, which defaults to UTF-8 on Windows 10 1903+ and Server 2019+ when the system locale is configured for UTF-8, and otherwise is the local ANSI code page.
2. **Force UTF-8 at the Splunk ingestion layer instead.** Set `CHARSET = UTF-8` in `TA-ODIN/default/props.conf` for the `odin:enumeration` sourcetype, which tells Splunk to decode the byte stream as UTF-8 regardless of what the forwarder sent.
3. **Use `Write-Output $line`** (no `-NoNewline`) to emit events — this goes through the success stream, hits the Splunk UF's stdout capture, and lands in the indexer where CHARSET takes over.

**Line ending discipline:** PowerShell's `Write-Output` on Windows emits CRLF by default. Splunk's default line-breaking handles CRLF and LF equivalently, so this is **not** a problem for parsing. It **is** a problem if we want byte-identical output to Linux — but byte-identical is only enforced inside the `key=value` payload, not line terminators. Success criterion #2 in ROADMAP.md talks about "identical set of field names," not identical line endings.

### Revised D5 (recommended for user approval)
**D5-revised:** Emit lines via `Write-Output` through the success stream. Do not touch `[Console]` or `[System.Text.Encoding]`. Declare `CHARSET = UTF-8` in `TA-ODIN/default/props.conf` to normalize encoding at parse time.

**Impact on CONTEXT.md:** D5 as written is incompatible with CLM and **must** be revised before planning proceeds. Flagging for user decision.

---

## 8. Splunk UF Script Input on Windows (WIN-10 implementation)

### Finding
Splunk Universal Forwarder on Windows does **not** directly execute `.ps1` files from `[script://]` stanzas. The documented pattern is a two-file wrapper:

**`TA-ODIN/bin/odin.path`** (plain text, one line):
```
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$SPLUNK_HOME\etc\apps\TA-ODIN\bin\odin.ps1"
```

**`TA-ODIN/default/inputs.conf`:**
```
[script://$SPLUNK_HOME\etc\apps\TA-ODIN\bin\odin.path]
disabled = 0
index = odin_discovery
sourcetype = odin:enumeration
interval = 2592000
source = odin
```

The UF reads the `.path` file, resolves `$SPLUNK_HOME`, and invokes the command as a child process.

**Source:** Splunk Docs — "Use Windows scripted inputs"; Splunk Community — "PowerShell script execution via Universal Forwarder".

### Implication for WIN-10
Success criterion "invokable via `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File odin.ps1`" is satisfied by the `.path` wrapper, not by a direct `[script://*.ps1]` stanza. The planner should add creation of `TA-ODIN/bin/odin.path` as an explicit task.

**Cross-platform complication:** The Linux side uses `[script://$SPLUNK_HOME/etc/apps/TA-ODIN/bin/odin.sh]` directly with no wrapper. This means `TA-ODIN/default/inputs.conf` needs **two separate stanzas** gated by OS, or a single stanza per OS-specific local file. The cleanest path is two stanzas:

```
[script://$SPLUNK_HOME/etc/apps/TA-ODIN/bin/odin.sh]
# Linux stanza — no-op on Windows UF (script not executable)

[script://$SPLUNK_HOME\etc\apps\TA-ODIN\bin\odin.path]
# Windows stanza — no-op on Linux UF (file doesn't exist)
```

Both stanzas use the same `index`, `sourcetype`, and `interval`. The UF on each OS silently ignores the stanza it can't execute. No runtime OS detection needed.

---

## 9. LocalSystem Enumeration Caveats (WIN-11)

`LocalSystem` (`NT AUTHORITY\SYSTEM`) is the default account for the Splunk UF Windows service. Confirmed capabilities under LocalSystem:

| Resource | Works under LocalSystem? | Notes |
|---|---|---|
| `HKLM:\SOFTWARE\...\Uninstall` | ✅ Yes | LocalSystem has full HKLM read |
| `Get-Service` + `Get-CimInstance Win32_Service` | ✅ Yes | Returns all services including protected ones |
| `Get-NetTCPConnection -State Listen` | ✅ Yes | OwningProcess populated |
| `Get-Process` + `Get-CimInstance Win32_Process` | ✅ Yes | CommandLine visible for all processes |
| `Get-ScheduledTask` | ✅ Yes | Sees tasks in all task folders including `\Microsoft\Windows\*` |
| `Get-Volume` / `Get-PSDrive` | ✅ Yes | All mounted volumes including hidden system drives |

**Caveats:**
- `HKCU` under LocalSystem points to `S-1-5-18` profile, not any interactive user — this is why §6 skips HKCU.
- `Get-Process -IncludeUserName` requires elevation; LocalSystem is not technically "elevated" in the UAC sense. **Do not** use `-IncludeUserName` — get the process owner from `Win32_Process.GetOwner()` if needed (deferred — `user=` field is not in the Linux process schema).

---

## 10. AppInspect Red Flags — Windows Code (Phase 3 preview)

This section is informational for Phase 1. The Phase 3 AppInspect check will cover it exhaustively.

**Known red-flag patterns from the AppInspect rule catalog:**

| Pattern | Severity | Why it trips |
|---|---|---|
| `Invoke-Expression`, `iex` | Fail | Arbitrary code execution |
| `Add-Type` | Fail | Compiles arbitrary C# — cannot be statically analyzed |
| `[Convert]::FromBase64String` | Manual review | Obfuscation vector |
| `Net.WebClient`, `Invoke-WebRequest`, `Invoke-RestMethod`, `DownloadString` | Fail | Outbound network from script |
| Hardcoded `http://` / `https://` URLs in scripts | Manual review | Potential exfiltration vector |
| Hardcoded Windows paths outside `$env:SPLUNK_HOME` | Manual review | Portability violation |
| `Start-Process -FilePath` with arbitrary exe | Fail | Binary execution |
| Dot-sourcing files outside the app dir | Fail | Escape from app sandbox |

**Phase 1 implications (preventative):**
- The grep gate in ROADMAP.md Phase 1 success criterion #3 already catches the top offenders (`Invoke-Expression|Add-Type|iex |FromBase64String|Net\.WebClient|DownloadString|IEX`) — this is the right list.
- Dot-sourcing `_common.ps1` and `stubs.ps1` is **intra-app** (`TA-ODIN/bin/modules/_common.ps1`) so it does not trip the dot-source rule.
- The `.path` wrapper file contains `powershell.exe` — AppInspect will flag this as "binary execution" in manual review, but it is **the documented Splunk pattern** and passes with justification. Phase 3 will document the justification.

---

## 11. PSScriptAnalyzer Likely Findings (Phase 2 preview, relevant to Phase 1 code we write)

PSScriptAnalyzer's default ruleset at `Error`/`Warning` severity will likely flag:

| Rule ID | Likely finding in our code | Fix |
|---|---|---|
| `PSAvoidUsingWriteHost` | None (we use Write-Output) | n/a |
| `PSAvoidUsingPositionalParameters` | Any `Get-ChildItem path` without `-Path` | Use named params |
| `PSUseDeclaredVarsMoreThanAssignments` | Loop variables that are assigned but only used via $_ | Rename to `$null` or suppress |
| `PSAvoidGlobalVars` | `$ODIN_EVENT_COUNT` if declared as `$global:` | Use script scope `$script:ODIN_EVENT_COUNT` |
| `PSUseShouldProcessForStateChangingFunctions` | None (we only read) | n/a |
| `PSAvoidUsingInvokeExpression` | None | n/a |
| `PSAvoidUsingCmdletAliases` | `%`, `?`, `gci`, `gc`, `iex` | Use full cmdlet names |

**Discipline for Phase 1:** Use full cmdlet names everywhere. Never use aliases. Use script-scope for counters. Phase 2 HARD-06 will then be a no-op.

---

## 12. Validation Architecture — Nyquist Dimensions 1–5

The Phase 1 plan must be verifiable from a cold checkout via command-line tests. Mapping each ROADMAP success criterion to a validation mechanism:

| Dim | What | How (command) | Covers |
|---|---|---|---|
| 1 | **Static grep gate** — zero forbidden patterns | `grep -RIEn 'Invoke-Expression\|Add-Type\|iex \|FromBase64String\|Net\.WebClient\|DownloadString\|IEX' TA-ODIN/bin/` | SC #3 |
| 2 | **Dependency gate** — no external modules | `grep -RIEn '#Requires -Module\|Import-Module [^M]' TA-ODIN/bin/` | SC #3 |
| 3 | **MSI hazard gate** — no Win32_Product | `grep -n 'Win32_Product' TA-ODIN/bin/modules/packages.ps1` | SC #5 |
| 4 | **Behavioral fixture test** — orchestrator emits markers and module events | `ODIN_TEST_FIXTURE=tests/windows-fixtures/hostA pwsh TA-ODIN/bin/odin.ps1 > out.txt; grep -c 'type=odin_start\|type=odin_complete' out.txt` | SC #1 |
| 5 | **Parity diff** — Linux and Windows events share field names | `pwsh TA-ODIN/bin/odin.ps1 | grep 'type=service' | head -1 > win.txt; bash TA-ODIN/bin/odin.sh | grep 'type=service' | head -1 > lin.txt; diff <(tr ' ' '\n' < win.txt | awk -F= '{print $1}' | sort) <(tr ' ' '\n' < lin.txt | awk -F= '{print $1}' | sort)` | SC #2 |
| 6 | **Fail-soft test** — induced module failure still reaches complete | Stub module that throws; assert `type=odin_error` AND `type=odin_complete` both present | SC #4 |

---

## 13. Risks and Mitigations (for user approval)

| ID | Risk | Severity | Mitigation | Needs user decision? |
|---|---|---|---|---|
| R1 | **D1 — Start-Job fails under system-wide WDAC/CLM** unless TA-ODIN is allowlisted | Medium | Document WDAC allowlisting as operational prerequisite in plan; no code-level fallback (Runspace is also blocked) | ❌ Accept risk; document |
| R2 | **D5 — `[Console]::Out.Write` is CLM-blocked** (`[System.Console]` not on allow-list) | **High — blocker** | Revise D5 to: use `Write-Output`; set `CHARSET=UTF-8` in `TA-ODIN/default/props.conf`; accept CRLF line endings on Windows | ✅ **Yes — user must approve D5 revision before planning** |
| R3 | **CRLF vs LF line endings** in Windows output | Low | Splunk accepts both; byte-parity only required within key=value payload | ❌ Accept |
| R4 | **pwsh on macOS lacks Windows-only modules** for D6 standalone test | Mitigated | Cmdlet-shadow stubs in `tests/windows-fixtures/stubs.ps1` (D3) | ❌ Validated |
| R5 | **`.path` wrapper file is an undocumented artifact** for first-time Windows TA authors | Low | Add explicit task in plan; reference Splunk Docs URL in file header comment | ❌ Accept |
| R6 | **Win32_Product regression** — someone copy-pastes from StackOverflow in a future PR | Low | Add grep gate to CI in Phase 2 HARD-06; comment in `packages.ps1` explaining the hazard | ❌ Accept |

---

## 14. Canonical References

**Microsoft Learn (PowerShell 5.1):**
- `about_Command_Precedence` — command resolution order
- `about_Language_Modes` — CLM allowed-types list, Start-Job caveats
- `about_Execution_Policies` — `-ExecutionPolicy Bypass`
- `Get-NetTCPConnection` — NetTCPIP module cmdlet reference
- `Get-ScheduledTask` / `Get-ScheduledTaskInfo` — ScheduledTasks module
- `Get-CimInstance` — CimCmdlets module
- `Start-Job` / `Wait-Job` / `Stop-Job` / `Receive-Job` — job cmdlets

**Splunk Docs:**
- "Use Windows scripted inputs" — `.path` wrapper pattern
- "props.conf CHARSET" — encoding override at parse time
- "Splunk AppInspect rule catalog" — red-flag pattern list

**Community / third-party (Win32_Product hazard):**
- Microsoft KB 974524
- xkln.net — "Stop using Win32_Product" (2020)
- Greg Ramsey (MSFT MVP) — MSI repair side-effects

**Internal:**
- `.planning/phases/01-windows-parity/01-CONTEXT.md` — D1–D6 design decisions
- `.planning/REQUIREMENTS.md` — WIN-01..WIN-12
- `.planning/ROADMAP.md` — Phase 1 success criteria
- `CLAUDE.md` — project conventions, two-app split rules
- `TA-ODIN/bin/odin.sh` — Linux orchestrator (parity reference)
- `TA-ODIN/bin/modules/*.sh` — Linux module reference implementations
