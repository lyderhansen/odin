# Plan: Log Discovery Module (`logs.sh`)

**Status:** Parked (saved for future implementation)
**Date:** 2026-02-23

---

## Goal

Add a new ODIN module that discovers log files on endpoints and reports metadata about them. This closes the gap between "we know nginx is running" and "we know where its logs are, how big they are, and what format they use."

## Design Principles

- Follows ODIN's "enumerate everything, classify at search time" philosophy
- Reports **metadata only** — file path, size, owner, permissions, format hint
- Optional single-line `head` sample for sourcetype detection (controlled by `ODIN_LOG_SAMPLE`)
- No mapping file needed on the forwarder — scans known log directories automatically
- Classification happens in Splunk via lookup join on `log_path` column in `odin_log_sources.csv`

## Architecture

```
Forwarder (logs.sh)                    Search Head (Splunk)
┌──────────────────────┐               ┌────────────────────────────┐
│ Scan log directories │               │ odin_log_sources.csv       │
│ /var/log/            │  type=log_file │ (has log_path column)      │
│ /opt/*/logs/         │──────────────>│                            │
│ /var/log/containers/ │               │ lookup join on path field  │
│ etc.                 │               │ → host_role, sourcetype,   │
│                      │               │   recommended_ta           │
│ Report: path, size,  │               └────────────────────────────┘
│ owner, perms, mtime, │
│ format, head (opt)   │
└──────────────────────┘
```

## Output Format

```
type=log_file path="/var/log/nginx/access.log" size_bytes=4829103 last_modified="2026-02-23T08:41:00Z" owner=www-data group=adm perms=644 format=text line_count=48291
type=log_file path="/var/log/mysql/error.log" size_bytes=12044 last_modified="2026-02-23T07:12:33Z" owner=mysql group=mysql perms=640 format=text line_count=203
type=log_file path="/var/log/suricata/eve.json" size_bytes=891204422 last_modified="2026-02-23T08:41:59Z" owner=suricata group=suricata perms=644 format=json line_count=1204433
```

With `ODIN_LOG_SAMPLE=true`:
```
type=log_sample path="/var/log/nginx/access.log" head="172.16.0.1 - - [23/Feb/2026:08:41:22 +0000] \"GET /api/health HTTP/1.1\" 200 15"
```

## Scan Targets

### Directories to scan

| Path | What lives here |
|------|-----------------|
| `/var/log/` | System and application logs (recursive) |
| `/var/log/containers/` | Container stdout/stderr logs |
| `/opt/*/logs/` | Application-specific log dirs |
| `/opt/*/log/` | Alternate naming |
| `/var/opt/*/log/` | Vendor-installed apps (e.g., mssql) |
| `/home/*/logs/` | User-space applications |

### File selection criteria

- Regular files only (no symlinks to avoid double-counting)
- Extensions: `.log`, `.json`, `.csv`, `.txt`, or no extension
- Exclude: `.gz`, `.bz2`, `.xz`, `.zip` (rotated/archived)
- Exclude: binary files (check with `file` command or first-byte heuristic)
- Minimum size: 1 byte (skip empty files)
- Maximum age: configurable, default 90 days (skip stale logs)

## Format Detection

Detect log format from first line without reading entire file:

| Check | Format |
|-------|--------|
| Line starts with `{` | `json` |
| Line matches `<\d+>` | `syslog_rfc5424` |
| Line matches `Mon DD HH:MM:SS` | `syslog_bsd` |
| Line matches `YYYY-MM-DD HH:MM:SS` | `timestamp_prefix` |
| Line contains `date time s-ip cs-method` | `w3c` (IIS) |
| Line is CSV-like (3+ commas) | `csv` |
| Fallback | `text` |

## Implementation Tasks

### Task 1: Core module (`TA-ODIN/bin/modules/logs.sh`)
- Scan configured directories
- Emit `type=log_file` events with metadata fields
- Format detection via first-line heuristic
- Respect `ODIN_MAX_EVENTS` cap
- Per-file timeout (2s) to handle hung NFS mounts
- Skip files the Splunk user can't read (check permissions, don't error)

### Task 2: Optional sample collection
- Controlled by `ODIN_LOG_SAMPLE` environment variable (default: false)
- Emit separate `type=log_sample` events with first line
- Sanitize/truncate head to max 500 chars
- Security note: document that this sends actual log content

### Task 3: Volume estimation (handled by lookup)
- **Volume estimation is now provided by `odin_log_sources.csv`** via `daily_volume_low_mb` and `daily_volume_high_mb` columns
- The lookup provides industry-typical daily volume ranges (quiet host → busy prod host) for every log source
- No file-based calculation needed — avoids complexity of rotation detection, file age heuristics, and permission issues
- The `logs.sh` module focuses on **existence and metadata** (path, size, permissions, format), not volume estimation
- Search-time aggregation uses the lookup values:
  - Per-host daily volume estimate (`lookup odin_log_sources ... | stats sum(daily_volume_low_mb) by hostname`)
  - Per-sourcetype volume estimate (after lookup join)
  - Per-TA volume estimate (what would each TA ingest if deployed)
  - Fleet-wide license impact projection (`sum(daily_volume_high_mb)` across all hosts)
- Actual observed file sizes from `logs.sh` can complement lookup estimates for more precise capacity planning

### Task 4: Search-time enrichment
- Add `odin_log_files` lookup transform in `transforms.conf`
- Add lookup binding in `props.conf` to join `path` against `log_path` in `odin_log_sources.csv`
- This automatically enriches discovered files with host_role, sourcetype, recommended_ta

### Task 5: Synthetic data support
- Add log_file events to `tools/generate_odin_data.py` host profiles
- Include realistic file paths, sizes, age_days, daily_bytes_est, and format values per host type

### Task 6: Dashboard panels
- Add "Discovered Log Files" panel to `odin_overview.xml`
- Table: hostname, path, size, format, matched sourcetype, recommended TA
- Highlight unmatched files (potential new log sources to classify)
- Add "Estimated Daily Ingest Volume" panel — bar chart by sourcetype or host_role (MB/day)
- Add "License Impact" single value — total estimated daily ingest across fleet

## Considerations

### Permissions
The Splunk forwarder user (`splunk` or `splunkfwd`) may not have read access to all log files. The module should:
- Attempt to `stat` each file (works without read permission)
- Only attempt `head` if readable
- Report `readable=yes/no` as a field

### Sensitivity
- `type=log_file` events contain only metadata — safe by default
- `type=log_sample` events contain actual log content — opt-in only
- Document clearly that `ODIN_LOG_SAMPLE=true` may expose PII/tokens in index

### Performance
- Directory scanning with `find` can be slow on large filesystems
- Use `timeout 30` on the overall find command
- Exclude known noisy dirs: `/var/log/journal/` (binary), `/var/log/pods/` (symlinks)
- MAX_EVENTS cap prevents flooding from hosts with thousands of log files

## Value

| Use case | How this helps |
|----------|---------------|
| TA deployment validation | Verify log files exist before deploying a TA |
| Gap analysis | Find log files that no TA covers (unmatched paths) |
| Volume estimation | Lookup-based daily_volume_low/high_mb per log source → aggregate per sourcetype, host_role, or TA |
| License impact | Fleet-wide daily ingest projection from lookup estimates, refined by observed file sizes |
| Capacity planning | Log file sizes across fleet |
| Sourcetype detection | Format field helps choose correct props.conf config |
| Stale log detection | last_modified shows if a service stopped logging |
| Permission auditing | readable=no shows where forwarder can't collect |
