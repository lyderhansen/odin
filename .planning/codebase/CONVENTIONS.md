# Conventions

**Analysis Date:** 2026-04-10

This project is a Splunk Technology Add-on. The primary source languages are **Bash** (discovery modules and orchestrator), **Splunk `.conf` INI-style files** (inputs/props/transforms/savedsearches/indexes), **CSV** (classification and mapping lookups), and **SPL** (embedded in `savedsearches.conf`). A small Python helper lives under `tools/` for synthetic test data generation.

There is no linter, formatter, or style tool configured. Conventions below are derived from the existing files and should be matched exactly when adding new code.

## Bash Module Conventions

All discovery modules live in `TA-ODIN/bin/modules/` and are auto-discovered by the orchestrator `TA-ODIN/bin/odin.sh`. Any file named `*.sh` in that directory will be executed.

### File header

Every module starts with a fixed header. See `TA-ODIN/bin/modules/services.sh`, `TA-ODIN/bin/modules/ports.sh`, `TA-ODIN/bin/modules/cron.sh`.

```bash
#!/bin/bash
#
# TA-ODIN Module: <Human Name> Enumeration
# <One-line description of what this module enumerates.>
#
# Output fields:
#   type=<type> <field1>= <field2>= ...
#
# Guardrails:
#   - <timeout/batch/limits description>
#
```

Requirements:
- Shebang is always `#!/bin/bash`. The orchestrator verifies `$BASH_VERSION` and modules rely on bash features (`[[ ]]`, `<<<`, `${var//a/b}`, `declare -f`).
- Header documents the output `type=` and all fields the module emits.
- Header documents guardrails (timeouts, batch query strategies).

### Locale pinning

Every module sets locale immediately after the header so command output is parseable regardless of host locale:

```bash
# Force C locale for consistent command output parsing
export LC_ALL=C
```

Also done in the orchestrator at `TA-ODIN/bin/odin.sh:22`.

### Standalone-capable modules

Each module must work both under the orchestrator **and** when invoked directly for local testing. The pattern (identical in every module):

```bash
# Use orchestrator functions if available, otherwise define standalone versions
if ! declare -f emit &>/dev/null; then
    ODIN_HOSTNAME="${ODIN_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}"
    ODIN_OS="${ODIN_OS:-linux}"
    ODIN_RUN_ID="${ODIN_RUN_ID:-standalone-$$}"
    ODIN_VERSION="${ODIN_VERSION:-2.1.0}"
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
    emit() { echo "timestamp=$(get_timestamp) hostname=$ODIN_HOSTNAME os=$ODIN_OS run_id=$ODIN_RUN_ID odin_version=$ODIN_VERSION $*"; }
fi
```

Reference: `TA-ODIN/bin/modules/services.sh:19-26`, `TA-ODIN/bin/modules/ports.sh:17-24`, `TA-ODIN/bin/modules/cron.sh:18-25`.

Rules:
- Never call `emit` without the guard — the orchestrator exports `emit` via `export -f emit` at `TA-ODIN/bin/odin.sh:70` and modules must reuse it so MAX_EVENTS accounting works.
- Fallback `run_id` values use the `standalone-$$` prefix so ad-hoc runs are distinguishable.
- Never hardcode `ODIN_VERSION` — let the orchestrator override it, default only for standalone runs.

### Shared `ODIN_*` context variables

The orchestrator exports the following. Modules read them as-is and never parse arguments or config files:

| Variable | Set by | Purpose |
|----------|--------|---------|
| `ODIN_VERSION` | orchestrator | Version tag emitted on every event |
| `ODIN_HOSTNAME` | orchestrator (`hostname -f` with fallback) | `hostname=` field |
| `ODIN_OS` | orchestrator | Currently hardcoded to `linux` |
| `ODIN_RUN_ID` | orchestrator (`$(date +%s)-$$`) | Correlates events from one scan |
| `ODIN_MAX_EVENTS` | orchestrator (default `50000`) | Per-module cap, enforced in `emit()` |
| `ODIN_EVENT_COUNT` | orchestrator, reset per module | Running counter |
| `ODIN_EVENTS_TRUNCATED` | orchestrator, reset per module | Sticky flag once cap is hit |
| `ODIN_RUNNING_AS_ROOT` | orchestrator | `1` if `$EUID -eq 0`, else `0` |

Never mutate `ODIN_EVENT_COUNT` / `ODIN_EVENTS_TRUNCATED` directly from a module — that logic lives only in the orchestrator's exported `emit()` at `TA-ODIN/bin/odin.sh:51-66`.

### Output format — space-separated `key=value`

Every event is a single stdout line:

```
timestamp=<iso8601> hostname=<host> os=<os> run_id=<id> odin_version=<ver> type=<type> <field>=<value> ...
```

Rules from the orchestrator and modules:

1. **Space-separated**, never comma-separated (v1 used commas, v2+ uses spaces). Splunk parses with `KV_MODE = auto` in `ODIN_app_for_splunk/default/props.conf:17`.
2. **Timestamps are ISO 8601 UTC** formatted `%Y-%m-%dT%H:%M:%SZ`. Always generated via `date -u +"%Y-%m-%dT%H:%M:%SZ"` via the `get_timestamp` helper. `TIME_PREFIX = timestamp=` and `TIME_FORMAT = %Y-%m-%dT%H:%M:%SZ` in `TA-ODIN/default/props.conf` depend on this exact format.
3. **Every event has the prelude** `timestamp= hostname= os= run_id= odin_version=` then module-specific fields starting with `type=`. The prelude is added by `emit()` — modules pass only the suffix.
4. **Module fields always begin with `type=<kind>`**. Known values: `service`, `port`, `package`, `cron`, `process`, `mount`, `none_found`, `odin_start`, `odin_complete`, `odin_error`, `odin_warning`, `truncated`.
5. **Empty fields are omitted**, not emitted as `field=`. Example from `services.sh:81`: `[[ -n "$service_type" ]] && out="$out service_type=$service_type"`.
6. **Values containing spaces must be double-quoted**, embedded double quotes backslash-escaped. Use the `safe_val` helper, copied verbatim into every module that emits user-provided strings:

```bash
safe_val() {
    local val="$1"
    val="${val//\"/\\\"}"
    if [[ "$val" == *" "* ]]; then
        echo "\"$val\""
    else
        echo "$val"
    fi
}
```

Reference: `TA-ODIN/bin/modules/services.sh:29-37`, `TA-ODIN/bin/modules/ports.sh:27-35`, `TA-ODIN/bin/modules/cron.sh:28-36`.

7. **Free-form `message=` fields are always double-quoted**, even for short strings, because they often contain spaces (e.g. `message="TA-ODIN enumeration started"`).
8. **Never emit multi-line values** — `SHOULD_LINEMERGE = false` and `LINE_BREAKER = ([\r\n]+)` mean newlines always break the event.

### Guardrails — project-wide invariants

From `TA-ODIN/bin/odin.sh`:

| Guardrail | Value | Enforcement |
|-----------|-------|-------------|
| Per-module wall-clock | 90 s | Orchestrator wraps module with `timeout 90 bash $module` at `odin.sh:111-115` |
| Per-module event cap | `ODIN_MAX_EVENTS=50000` | `emit()` increments `ODIN_EVENT_COUNT` and emits one `type=truncated` marker at `odin.sh:57-62` |
| External command timeouts | 5–30 s | Every `systemctl`, `ss`, `netstat`, `service`, `dpkg`, `rpm` call wrapped in `timeout N` |
| Input timeout | 120 s | `timeout = 120` in `TA-ODIN/default/inputs.conf:17` |
| Scan interval | 2592000 s (30 d) | `interval = 2592000` in `TA-ODIN/default/inputs.conf:15` |

When adding a new module:
- Wrap every external command with `timeout N <cmd>`; worst-case N is 30s.
- Prefer one batch query returning many records over a loop that spawns a subprocess per item (see `services.sh` batch `systemctl show --type=service --all`, `cron.sh` batch timer query).
- Never abort on error — return 0 whenever possible. The orchestrator treats non-zero exit as module failure.

### Error and warning events

- Errors: `type=odin_error module=<name> message="<why>"` with optional `exit_code=`. Orchestrator emits on timeout (`odin.sh:121`) and non-zero exit (`odin.sh:124`).
- Warnings: `type=odin_warning module=<name> message="<why>"`. Orchestrator warns about non-root execution for `ports` and `cron` at `odin.sh:84-85`.
- When a module finds nothing legitimately, emit `type=none_found module=<name> message="..."` rather than silence. Example: `services.sh:175`.

### Bash style

- `[[ ]]` for tests, never `[ ]`.
- `$((...))` for arithmetic, never `expr`.
- `local` for all variables inside functions.
- Parameter expansion (`${var%suffix}`, `${var##prefix}`, `${var//a/b}`) preferred over `sed`/`awk` when possible.
- Process substitution (`<(cmd)`) and heredoc strings (`<<<`) are used freely.
- `command -v <cmd> &>/dev/null` gates every optional tool.
- Fallback chains follow "primary → fallback 1 → fallback 2" with comments `# --- Primary: ss ---`, `# --- Fallback 1: service ---`, `# --- Fallback 2: /etc/init.d/ ---` (see `services.sh` and `ports.sh`).

## Splunk `.conf` File Conventions

### File header

Every `.conf` file starts with a commented description block:

```
#
# <Purpose> for <App Name> v<version>
#
# <Where this deploys and what it does.>
# <Any cross-app split notes.>
#
```

Reference: `TA-ODIN/default/props.conf:1-6`, `ODIN_app_for_splunk/default/props.conf:1-6`, `ODIN_app_for_splunk/default/transforms.conf:1-6`, `ODIN_app_for_splunk/default/savedsearches.conf:1-7`.

### Stanza style

- Stanza headers are lowercase snake_case for lookups (`[odin_classify_services]`), colon-separated for sourcetypes (`[odin:enumeration]`), `script://` URL style for inputs (`[script://./bin/odin.sh]`).
- Saved search names use human-readable titles with `ODIN - ` prefix: `[ODIN - Host Inventory]`, `[ODIN - Log Source Details]`, `[ODIN - TA Deployment Matrix]`.
- Key-value lines use `key = value` with spaces around `=` (Splunk convention).
- Blank line between stanzas; inline `#` comments allowed on their own lines.
- Long SPL values in `savedsearches.conf` use trailing-backslash line continuation with two-space indent (`ODIN_app_for_splunk/default/savedsearches.conf:11-32`).

### Cross-app split (hard rule)

| Config | TA-ODIN | ODIN_app_for_splunk |
|--------|---------|---------------------|
| `inputs.conf` | Yes — scripted input | Never |
| `indexes.conf` | Never | Yes — `odin_discovery` |
| `props.conf` | Line-breaking + timestamp only | Full parsing + `KV_MODE=auto` + CIM aliases + `LOOKUP-*` |
| `transforms.conf` | Never | Yes — classification lookup definitions |
| `savedsearches.conf` | Never | Yes — host inventory and TA matrix |
| `lookups/*.csv` | Never | Yes |

Never copy search-time props into `TA-ODIN/default/props.conf`.

### Metadata export

`ODIN_app_for_splunk/metadata/default.meta` exports `lookups`, `props`, `transforms`, `savedsearches`, and `views` to `system` scope. Keep the list in sync when adding new object types.

## CSV Lookup Conventions

All lookups live in `ODIN_app_for_splunk/lookups/` and are bound to transform stanzas in `ODIN_app_for_splunk/default/transforms.conf`.

### File naming

- `odin_classify_<domain>.csv` — classification lookups mapping a raw signal to `category`/`role`/`vendor`. Domains: `services`, `ports`, `packages`.
- `odin_log_sources.csv` — signal → `(host_role, log_source, sourcetype, recommended_ta, log_path, description)` mapping. Central Phase 2 table.
- `odin_recommended_tas.csv` — TA reference table keyed by `recommended_ta` name.
- Generated output lookups from saved searches use `odin_<topic>.csv`: `odin_host_inventory.csv`, `odin_log_source_details.csv`.

### Header conventions

- First row is the header. Fields are lowercase `snake_case`.
- A classification lookup's first column is the match key (`service_pattern`, `package_pattern`, `port`).
- `service_pattern` and `package_pattern` are matched as wildcards (`match_type = WILDCARD(...)` in `transforms.conf:11,20`) — entries can contain `*` globs.
- `port` lookups match `(port, transport)` tuples, no wildcards.
- `odin_log_sources.csv` is keyed on `(signal_type, signal_value)` where `signal_type` is `service|port|package` and `signal_value` is the exact enumerated value (e.g. `nginx`, `443/tcp`, `mysql-server`).

Reference headers (exact):

```
odin_classify_services.csv:  service_pattern,category,subcategory,vendor,role,description
odin_classify_ports.csv:     port,transport,expected_service,category,description
odin_classify_packages.csv:  package_pattern,category,vendor,role,description
odin_log_sources.csv:        signal_type,signal_value,host_role,log_source,sourcetype,recommended_ta,log_path,description,daily_volume_low_mb,daily_volume_high_mb
odin_recommended_tas.csv:    recommended_ta,splunkbase_id,splunkbase_url,official_name,status,github_url,notes
```

### Content rules

- All CSVs end with a newline, Unix line endings.
- Commas inside a field require double-quoting the whole field. Prefer to avoid commas in descriptions.
- Empty cells are acceptable — `lookup` returns null and SPL filters with `where isnotnull(host_role)`.
- Use `none` (literal, lowercase) for `recommended_ta` when no TA exists. The TA Deployment Matrix search filters `where recommended_tas!="none"` (`savedsearches.conf:72`).
- The `status` taxonomy for TAs: `official`, `community`, `vendor` (see `DOCS/CHANGEHISTORY.md`).
- Multi-signal reinforcement is by design: multiple CSV rows can map to the same `host_role`; saved searches dedup per host.
- Adding rows does not require changes to bash code, props, or transforms — the classification layer is fully data-driven at search time.

## SPL Conventions (in `savedsearches.conf`)

Observed patterns in `ODIN_app_for_splunk/default/savedsearches.conf`:

- Base search always scopes to `index=odin_discovery sourcetype=odin:enumeration` and restricts types with parentheses: `(type=service OR type=port OR type=package)`.
- Synthesize a normalized `(signal_type, signal_value)` pair before lookup:
  ```
  | eval signal_type=type
  | eval signal_value=case(
      type="service", service_name,
      type="port", listen_port."/".transport,
      type="package", package_name
    )
  ```
- Always `dedup hostname, signal_type, signal_value` before a lookup to avoid double-counting.
- Lookup then filter nulls: `| lookup odin_log_sources signal_type, signal_value | where isnotnull(host_role)`.
- Aggregate multi-valued results with `stats values(...) AS ... by hostname` and flatten with `| eval x=mvjoin(x, ",")` before writing to an output lookup.
- All output lookups use `outputlookup create_empty=false <name>.csv` so empty runs do not clobber existing data.
- Schedule window: `dispatch.earliest_time = -45d` (covers the 30-day scan interval with margin), `dispatch.latest_time = now`.
- Cron schedules staggered by 5 minutes at 01:xx UTC to avoid overlap: `5 1 * * *`, `10 1 * * *`, `15 1 * * *`.
- `enableSched = 1` and `is_visible = true` on scheduled searches.

## Naming Conventions Summary

| Artifact | Pattern | Examples |
|----------|---------|----------|
| Bash module file | `TA-ODIN/bin/modules/<domain>.sh` | `services.sh`, `ports.sh` |
| Event `type=` | `<singular_noun>` | `service`, `port`, `cron` |
| Event field | `snake_case` | `service_name`, `listen_port`, `cron_schedule` |
| CSV lookup file | `odin_<purpose>.csv` | `odin_classify_services.csv` |
| CSV column | `snake_case` | `signal_type`, `host_role`, `recommended_ta` |
| Splunk sourcetype stanza | `odin:<kind>` | `odin:enumeration` |
| Splunk lookup stanza | `odin_<purpose>` | `odin_classify_ports` |
| Saved search | `ODIN - <Title Case>` | `ODIN - Host Inventory` |
| Index | `odin_<purpose>` | `odin_discovery` |
| Env var | `ODIN_<UPPER_SNAKE>` | `ODIN_RUN_ID`, `ODIN_MAX_EVENTS` |
| `run_id` format | `<epoch>-<pid>` or `standalone-<pid>` | `1718800000-12345` |

## Documentation Conventions

- `DOCS/CHANGEHISTORY.md` — all entries use **ISO 8601 CET** timestamps (not UTC). Project-wide rule, called out at the top of the file.
- `DOCS/ARCHITECTURE.md` — ASCII diagrams over images.
- `DOCS/COMMANDS.md` — documents each enumerated command, whether root is required, and the risks/side effects. When adding a new module, add its commands here.
- `CLAUDE.md` at the repo root is the source of truth for project vision, architecture decisions, and the two-app split.
- All `.md` files use ATX headings, fenced code blocks with a language tag, and relative file paths in backticks.

## Things That Must Never Happen

- Never place `indexes.conf` in `TA-ODIN/` — it belongs only in `ODIN_app_for_splunk/`.
- Never place `inputs.conf` in `ODIN_app_for_splunk/` — scripted inputs run on forwarders only.
- Never emit log content, file contents, or command output bodies. Modules report **metadata only** (service name, port, package, schedule, mount point, process name).
- Never use commas as field separators in event output (v1 legacy). Always space-separated `key=value`.
- Never add a per-unit subprocess loop for systemctl — always batch with `systemctl show --all`.
- Never drop the MAX_EVENTS guardrail. If data volume grows, fix the cap or aggregate, do not remove the check.
- Never hardcode a hostname, run_id, or timestamp — always use the `ODIN_*` context.
