# TA-ODIN Data Dictionary

Field reference for every event type emitted by TA-ODIN orchestrators (Linux + Windows)
and the six discovery modules. Audience: Splunk admin or detection engineer authoring
search-time enrichment, dashboards, or alerts against `index=odin_discovery
sourcetype=odin:enumeration`.

## Cross-platform parity

Linux modules (`bin/modules/*.sh`) and Windows modules (`bin/modules/*.ps1`) emit
**identical** field names per event type (WIN-08 contract — see
`.planning/REQUIREMENTS.md` and the Phase 1 Nyquist parity harness at
`tools/tests/windows-parity-harness.sh`). Same `service_name`, same `listen_port`,
same `package_name`, etc. — search-time lookups and saved searches are platform-
agnostic by design.

The **one documented divergence**: Linux emits `type=cron` with `cron_*` prefixed
fields; Windows emits `type=scheduled_task` with `task_*` prefixed fields. Different
event type, different field namespace, identical semantic role (scheduled-task
enumeration). The Nyquist parity harness explicitly skips `type=scheduled_task`
parity for this reason (`tools/tests/windows-parity-harness.sh` dimension 5).

## Common envelope fields

Every event — regardless of `type=` — carries these envelope fields, prepended by the
orchestrator's `emit()` function (see `TA-ODIN/bin/odin.sh:55-71` and
`TA-ODIN/bin/modules/_common.ps1`):

| Field | Example | Description |
|---|---|---|
| `timestamp` | `2026-04-24T10:00:00Z` | ISO 8601 UTC, generated per-event |
| `hostname` | `web01.example.com` | FQDN from `hostname -f` (Linux) or `[Net.Dns]::GetHostName()` (Windows) |
| `os` | `linux` or `windows` | Set by orchestrator at startup |
| `run_id` | `1740100800-1234` | Unique per-execution: `<epoch>-<pid>` (Linux) or PS equivalent (Windows) |
| `odin_version` | `1.0.0` | Pinned to orchestrator version constant |
| `type` | `service` | Event-type discriminator (this document's organizing axis) |

The remaining fields per event type are described below.

## type=odin_start

Fires once per orchestrator invocation, immediately after privilege detection and
before the first module dispatch.

**Fields:**

- Common envelope (above)
- `run_as` — username running the orchestrator (`id -un` on Linux; current identity
  on Windows)
- `euid` — effective UID (Linux only; omitted on Windows)
- `message` — fixed string `"TA-ODIN enumeration started"`

**Example:**

```
timestamp=2026-04-24T10:00:00Z hostname=web01.example.com os=linux run_id=1740100800-1234 odin_version=1.0.0 type=odin_start run_as=splunk euid=998 message="TA-ODIN enumeration started"
```

## type=odin_host_info

Fires once per orchestrator invocation, immediately after `type=odin_start`
and before any module events. Provides rich host metadata for fleet
classification: OS distribution, hardware profile, network identity,
virtualization detection, and cloud-provider identification.

This event is the foundation for v1.0.2 dashboards (`OS Distribution` and
`Virtualization Breakdown` panels in `odin_overview.xml`) and the
prerequisite for v1.1.0 container observability (the `virtualization=container`
field hints whether a host is running INSIDE a container, before the
v1.1.0 enumerator iterates the actual containers on a container host).

**Worked example event line:**

```
timestamp=2026-04-29T10:00:00Z hostname=web01.prod.example.com os=linux run_id=1740100800-1234 odin_version=1.0.2 type=odin_host_info os_distro=rocky os_version=9.3 os_pretty="Rocky Linux 9.3 (Blue Onyx)" os_kernel=5.14.0-362.el9.x86_64 os_arch=x86_64 cpu_cores=8 mem_total_mb=16384 uptime_seconds=432000 fqdn=web01.prod.example.com ip_primary=10.0.5.123 virtualization=kvm cloud_provider=aws cloud_region=eu-north-1
```

**Fields:** Common envelope (timestamp, hostname, os, run_id, odin_version, type) plus the 13 host metadata fields documented below.

### Field reference

#### `os_distro`

- **Description:** OS family identifier — short lowercase string identifying the OS distribution. Stable enough to use as a `stats` grouping key.
- **Source (Linux):** parse `/etc/os-release` `ID=` field
- **Source (Windows):** hardcoded `windows` (Win32_OperatingSystem.Caption always starts with "Microsoft Windows")
- **Example:** `os_distro=rocky`, `os_distro=ubuntu`, `os_distro=windows`, `os_distro=alpine`

#### `os_version`

- **Description:** OS version string. Format varies per distro/platform but is stable per OS family.
- **Source (Linux):** parse `/etc/os-release` `VERSION_ID=` field
- **Source (Windows):** `[System.Environment]::OSVersion.Version` formatted as `Major.Minor.Build`; PSCL fallback `(Get-CimInstance Win32_OperatingSystem).Version`
- **Example:** `os_version=9.3` (Rocky), `os_version=22.04` (Ubuntu), `os_version=10.0.26100` (Windows 11)

#### `os_pretty`

- **Description:** Human-readable OS name including marketing string. Useful for tooltips and report headers; do NOT use as grouping key (high cardinality due to patch level differences).
- **Source (Linux):** parse `/etc/os-release` `PRETTY_NAME=` field
- **Source (Windows):** `(Get-CimInstance Win32_OperatingSystem).Caption.Trim()`
- **Example:** `os_pretty="Rocky Linux 9.3 (Blue Onyx)"`, `os_pretty="Microsoft Windows 11 Pro"`. (Note: always quoted because contains spaces.)

#### `os_kernel`

- **Description:** Kernel/build identifier. Linux returns the `uname -r` string; Windows returns the OS BuildNumber.
- **Source (Linux):** `uname -r`
- **Source (Windows):** `(Get-CimInstance Win32_OperatingSystem).BuildNumber`
- **Example:** `os_kernel=5.14.0-362.el9.x86_64` (Linux), `os_kernel=26100` (Windows)

#### `os_arch`

- **Description:** CPU architecture identifier. Lowercase to ensure parity-friendly comparison across platforms.
- **Source (Linux):** `uname -m`
- **Source (Windows):** `$env:PROCESSOR_ARCHITECTURE.ToLower()`
- **Example:** `os_arch=x86_64` (Linux x86-64), `os_arch=amd64` (Windows x86-64), `os_arch=aarch64` (Linux ARM64), `os_arch=arm64` (Windows ARM64)

#### `cpu_cores`

- **Description:** Total physical CPU core count, summed across all sockets. Always a string per D-03 sentinel discipline (returns `"unknown"` on detection failure, never `-1` or empty).
- **Source (Linux):** `nproc`
- **Source (Windows):** `(Get-CimInstance Win32_Processor | Measure-Object NumberOfCores -Sum).Sum` (multi-socket aware)
- **Example:** `cpu_cores=8`, `cpu_cores=64`, `cpu_cores=unknown`

#### `mem_total_mb`

- **Description:** Total physical RAM in megabytes (integer, no decimal). Always a string per D-03.
- **Source (Linux):** `awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo` (kB -> MB)
- **Source (Windows):** `[int]((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1024)` (KB -> MB)
- **Example:** `mem_total_mb=16384`, `mem_total_mb=131072`, `mem_total_mb=unknown`

#### `uptime_seconds`

- **Description:** Time since last boot in integer seconds. Always a string per D-03.
- **Source (Linux):** `awk '{print int($1)}' /proc/uptime`
- **Source (Windows):** `[int]((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalSeconds`
- **Example:** `uptime_seconds=432000` (5 days), `uptime_seconds=unknown`

#### `fqdn`

- **Description:** Fully qualified domain name of the host. On personal/lab hosts without domain configuration, this is the unqualified hostname (which IS the FQDN in that environment). Quoted only when it contains spaces (rare).
- **Source (Linux):** `hostname -f`
- **Source (Windows):** `[System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName`; PSCL fallback `$env:COMPUTERNAME`
- **Example:** `fqdn=web01.prod.example.com`, `fqdn=WIN-WEB01.contoso.local`, `fqdn=desktop-abc123` (unqualified — no domain)

#### `ip_primary`

- **Description:** Primary IPv4 address (the one used for the default route). Distinct from the `hostname` envelope field which may be FQDN-only.
- **Source (Linux):** `ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}'`
- **Source (Windows):** `(Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1 | Get-NetIPAddress -AddressFamily IPv4).IPAddress`
- **Example:** `ip_primary=10.0.5.123`, `ip_primary=192.168.1.50`, `ip_primary=none` (no default route configured), `ip_primary=unknown` (system tooling unavailable)

#### `virtualization`

- **Description:** Virtualization platform identifier. Single field with a 7-value enum per D-04. Used by `Virtualization Breakdown` dashboard panel.
- **Source (Linux):** `systemd-detect-virt` (preferred), with fallback chain via `dmidecode -s system-manufacturer` and `/proc/1/cgroup` content inspection
- **Source (Windows):** `Win32_ComputerSystem.Manufacturer`+`.Model` cascade matching against known hypervisor signatures (Microsoft Virtual, VMware, QEMU, Xen, Amazon EC2, Google Compute Engine), plus `Win32_OperatingSystem.OperatingSystemSKU` for Container OS edition detection
- **Enum values:**
  - `baremetal` — physical hardware
  - `kvm` — KVM/QEMU/EC2 nitro/GCE (all collapsed)
  - `vmware` — VMware ESXi/Workstation
  - `hyperv` — Microsoft Hyper-V
  - `xen` — Xen hypervisor
  - `container` — Linux container (Docker/Podman/LXC/nspawn/WSL/rkt/openvz) OR Windows Container OS
  - `unknown` — detection failed (PSCL block, missing tooling, unknown signature)

#### `cloud_provider`

- **Description:** Cloud platform identifier from IMDS probe. Used for fleet-by-cloud reporting and v1.1.0 cloud asset enrichment.
- **Source (Linux):** sequential `curl` to AWS IMDSv2 -> GCP metadata.google.internal -> Azure IMDS, 1s timeout per probe (D-02)
- **Source (Windows):** sequential `Invoke-RestMethod -TimeoutSec 1 -UseBasicParsing` to same endpoints (D-05)
- **Enum values:** `aws`, `gcp`, `azure`, `none` (no IMDS responded — host is not in supported cloud), `unknown` (curl/Invoke-RestMethod unavailable or all probes raised exceptions)

#### `cloud_region`

- **Description:** Cloud region identifier from IMDS probe. Format is provider-specific.
- **Source (Linux):** AWS = `/latest/meta-data/placement/region` (e.g., `eu-north-1`); GCP = derived from zone (zone `europe-west1-b` -> region `europe-west1`); Azure = `/metadata/instance/compute/location` (e.g., `eastus`)
- **Source (Windows):** Same endpoints, parsed via `Invoke-RestMethod`
- **Example:** `cloud_region=eu-north-1` (AWS), `cloud_region=europe-west1` (GCP), `cloud_region=eastus` (Azure), `cloud_region=none` (when cloud_provider=none), `cloud_region=unknown`

## type=odin_complete

Fires once per orchestrator invocation, after every module has either succeeded,
failed, or hit the per-module timeout. Always emitted, even if individual modules
fail (fail-soft per WIN-12 / Linux orchestrator design).

**Fields:**

- Common envelope (above)
- `modules_total` — count of modules dispatched this run
- `modules_success` — count of modules that exited 0
- `modules_failed` — count of modules that exited non-zero (including timeout 124)
- `duration_ms` — total wall-clock orchestrator runtime in milliseconds, captured
  immediately before the start emit and finalized immediately before the complete
  emit. On Linux production (GNU date) this is true millisecond precision; on BSD
  date (macOS dev environment) it falls back to second precision (rounded). Useful
  for SLO tracking and identifying slow hosts.
- `message` — fixed string `"TA-ODIN enumeration completed"` (or `"... completed with errors"`)

**Example:**

```
timestamp=2026-04-24T10:00:42Z hostname=web01.example.com os=linux run_id=1740100800-1234 odin_version=1.0.0 type=odin_complete modules_total=6 modules_success=6 modules_failed=0 duration_ms=4823 message="TA-ODIN enumeration completed"
```

## type=odin_error

Emitted by the orchestrator when a module fails. One event per failed module. Drives
the `alert_odin_module_timeouts` saved search (when `exit_code=124`) and the implicit
non-124 module-error pattern (see `DOCS/RUNBOOK.md` for both alert response procedures).

**Fields:**

- Common envelope
- `module` — short name of the failing module (e.g., `services`, `packages`)
- `exit_code` — module's exit code (`124` for timeout, `127` for command-not-found,
  module-specific for everything else)
- `message` — human-readable failure description (optional; usually present)

**Example:**

```
timestamp=2026-04-24T10:00:31Z hostname=db01.example.com os=linux run_id=1740100800-9012 odin_version=1.0.0 type=odin_error module=packages exit_code=124 message="Module packages timed out after 90s"
```

## type=truncated

Emitted by the `emit()` guard when a module's per-module event count reaches the
`ODIN_MAX_EVENTS` cap (default 50000). Once truncated, every subsequent `emit()` in
that module on that run is silently suppressed — enumeration data for that module on
that host is provably incomplete. Drives `alert_odin_truncated_events`.

**Fields:**

- Common envelope
- `message` — fixed format
  `"Event limit reached (max=<N>). Remaining events suppressed."`

**Example:**

```
timestamp=2026-04-24T10:00:25Z hostname=builder42.example.com os=linux run_id=1740100800-5678 odin_version=1.0.0 type=truncated message="Event limit reached (max=50000). Remaining events suppressed."
```

## type=service

Emitted by `services.sh` (Linux: `systemctl show` batch query, with SysV init and
`/etc/init.d/` fallbacks) and `services.ps1` (Windows: `Get-Service` plus
`Get-CimInstance Win32_Service` for start mode and image path). Identical field names
per WIN-08 — same field set used regardless of source OS.

**Fields:**

- Common envelope
- `service_name` — service identifier (`sshd`, `nginx`, `W3SVC`, `MSSQLSERVER`)
- `service_status` — current state (`running`, `stopped`, `unknown`)
- `service_enabled` — startup mode (`enabled`, `disabled`, `static`, `unknown`)
- `service_path` — service binary path (Windows present, Linux usually absent)
- `service_type` — systemd Type= property (Linux only; e.g., `forking`, `notify`)

**Example:**

```
timestamp=2026-04-24T10:00:01Z hostname=web01.example.com os=linux run_id=1740100800-1234 odin_version=1.0.0 type=service service_name=nginx service_status=running service_enabled=enabled service_type=forking
```

## type=port

Emitted by `ports.sh` (Linux: `ss -tulpn` / `netstat -tulpn` fallback) and
`ports.ps1` (Windows: `Get-NetTCPConnection -State Listen` and `Get-NetUDPEndpoint`).

**Fields:**

- Common envelope
- `transport` — `tcp` or `udp`
- `listen_address` — bind address (`0.0.0.0`, `::`, `127.0.0.1`)
- `listen_port` — numeric port
- `process_name` — owning process command name (often empty when running as non-root
  on Linux — see `DOCS/COMMANDS.md` "Privilege Impact")
- `process_pid` — owning process PID (same caveat)

**Example:**

```
timestamp=2026-04-24T10:00:05Z hostname=web01.example.com os=linux run_id=1740100800-1234 odin_version=1.0.0 type=port transport=tcp listen_address=0.0.0.0 listen_port=443 process_name=nginx process_pid=1234
```

## type=package

Emitted by `packages.sh` (Linux: `dpkg-query` / `rpm -qa` / `apk` / `pacman -Q`
fallback chain) and `packages.ps1` (Windows: `HKLM:\...\Uninstall` registry scan,
both 64-bit and 32-bit hives — never `Win32_Product` per WIN-04).

**Fields:**

- Common envelope
- `package_name` — package identifier (`nginx`, `libssl1.1`; or registry display name
  on Windows)
- `package_version` — version string (`1:8.9p1-3ubuntu0.6`, `2.34-60.el9`)
- `package_arch` — architecture (`amd64`, `x86_64`, `noarch`); may be empty on
  Windows registry entries lacking arch metadata
- `package_manager` — source: `dpkg`, `rpm`, `apk`, `pacman`, or `registry` (Windows)

**Example:**

```
timestamp=2026-04-24T10:00:08Z hostname=web01.example.com os=linux run_id=1740100800-1234 odin_version=1.0.0 type=package package_name=nginx package_version=1.24.0-1 package_arch=amd64 package_manager=dpkg
```

## type=cron

Emitted by `cron.sh` (Linux only). Aggregates four sources: traditional `/etc/crontab`
and `/etc/cron.d/`, periodic script directories (`cron.{hourly,daily,weekly,monthly}`),
per-user crontabs (`/var/spool/cron/crontabs/`, root-only), systemd timers (batch
`systemctl show` query), and anacron schedules.

**Fields:**

- Common envelope
- `cron_source` — `system_crontab`, `cron.d`, `cron.hourly`/`daily`/`weekly`/`monthly`,
  `user_crontab`, `systemd_timer`, `anacron`
- `cron_user` — user the entry runs as (`root`, `splunk`, etc.); blank for system
  crontabs that don't specify a user column
- `cron_schedule` — cron expression (`0 2 * * *`), systemd OnCalendar string
  (`Sun *-*-* 00:00:00`), or anacron `period=Nd delay=Mm` form
- `cron_command` — command line or systemd unit name
- `cron_file` — source file path (e.g., `/etc/cron.d/logrotate`,
  `/etc/anacrontab`); absent for `user_crontab`

**Example:**

```
timestamp=2026-04-24T10:00:12Z hostname=web01.example.com os=linux run_id=1740100800-1234 odin_version=1.0.0 type=cron cron_source=user_crontab cron_user=root cron_schedule="0 2 * * *" cron_command="/usr/local/bin/backup.sh"
```

## type=scheduled_task

Emitted by `scheduled_tasks.ps1` (Windows only). Semantic counterpart to Linux
`type=cron` (different event type, different field namespace — the one documented
field-name divergence per WIN-08 Nyquist exception). Sources: `Get-ScheduledTask`
plus `Get-ScheduledTaskInfo` for last/next-run enrichment.

**Fields:**

- Common envelope
- `task_name` — task identifier (e.g., `BackupJob`)
- `task_path` — task path/folder (e.g., `\Microsoft\Windows\TaskScheduler\`)
- `task_state` — current state (`ready`, `running`, `disabled`)
- `task_author` — task author (often `Microsoft Corporation` for built-in tasks;
  optional, present when populated)
- `task_last_run` — ISO 8601 UTC timestamp of last execution (optional)
- `task_next_run` — ISO 8601 UTC timestamp of next scheduled execution (optional)
- `task_last_result` — Windows result code from last run (`0` = success; optional)

**Example:**

```
timestamp=2026-04-24T10:00:14Z hostname=dc01.example.com os=windows run_id=ps-2026042410001 odin_version=1.0.0 type=scheduled_task task_name=BackupJob task_path=\Microsoft\Windows\TaskScheduler\ task_state=ready task_author=ContosoIT task_last_run=2026-04-23T02:00:00Z task_next_run=2026-04-24T02:00:00Z task_last_result=0
```

## type=process

Emitted by `processes.sh` (Linux: single `ps -eo` capture with BusyBox / `ps -ef`
fallbacks) and `processes.ps1` (Windows: `Get-Process` plus `Get-CimInstance
Win32_Process` for command-line where available).

**Fields:**

- Common envelope
- `process_pid` — process ID
- `process_ppid` — parent process ID
- `process_user` — user owning the process (`root`, `www-data`, `SYSTEM`)
- `process_state` — `ps -o stat` state code (Linux: `Ss`, `R`, `D`); equivalent
  state on Windows (`Running`, `Suspended`)
- `process_cpu` — `%CPU` (snapshot at sample time)
- `process_mem` — `%MEM` (snapshot at sample time)
- `process_elapsed` — wall-clock elapsed since start (`10-05:23:15` = 10 days, 5h
  23m 15s)
- `process_name` — short command name
- `process_command` — full command line with args (optional; subject to
  `/proc hidepid` settings on Linux and AppLocker logging restrictions on Windows)

**Example:**

```
timestamp=2026-04-24T10:00:18Z hostname=web01.example.com os=linux run_id=1740100800-1234 odin_version=1.0.0 type=process process_pid=1234 process_ppid=1 process_user=www-data process_state=Ss process_cpu=0.1 process_mem=2.3 process_elapsed=10-05:23:15 process_name=nginx process_command="nginx: master process /usr/sbin/nginx"
```

## type=mount

Emitted by `mounts.sh` (Linux: `df -PT` / `df -P` / `df` fallback) and `mounts.ps1`
(Windows: `Get-Volume` / `Get-PSDrive -PSProvider FileSystem`).

**Fields:**

- Common envelope
- `mount_device` — backing device or share (`/dev/sda1`, `nfs01:/exports`,
  drive letter on Windows)
- `mount_point` — mount path (`/`, `/data`, `C:\` on Windows)
- `mount_type` — filesystem type (`ext4`, `xfs`, `nfs`, `ntfs`, `tmpfs`)
- `mount_size_kb` — total size in KB
- `mount_used_kb` — used space in KB
- `mount_avail_kb` — available space in KB
- `mount_use_pct` — utilization percentage as a bare number (no `%` sign)

**Example:**

```
timestamp=2026-04-24T10:00:22Z hostname=web01.example.com os=linux run_id=1740100800-1234 odin_version=1.0.0 type=mount mount_device=/dev/sda1 mount_point=/ mount_type=ext4 mount_size_kb=20511312 mount_used_kb=8234560 mount_avail_kb=11213304 mount_use_pct=42
```

## Auxiliary event types (not in the canonical 11)

Modules also emit these supporting events for operational visibility. They are not
classification signals and are filtered out of search-time enrichment lookups by the
`type=service`/`type=port`/`type=package`/etc. predicate filters in
`ODIN_app_for_splunk/default/savedsearches.conf`.

| type | When | Module |
|---|---|---|
| `none_found` | Module ran but discovered nothing | All |
| `odin_warning` | Pre-run warning (privilege limitation, fallback in use) | Orchestrator |
| `privilege_warning` | Module detected limited data due to insufficient privileges | `ports.sh`, `cron.sh` |
| `mount_error` | `df` timed out (possible hung NFS) | `mounts.sh` |

These are documented in `DOCS/ARCHITECTURE.md` "Special event types" and surface in
the operational dashboard at `ODIN_app_for_splunk/default/data/ui/views/odin_ops.xml`.
