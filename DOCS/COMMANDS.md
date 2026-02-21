# TA-ODIN Command Reference

Every external command used by TA-ODIN, what it does, privilege requirements, and expected output as root vs non-root.

---

## Orchestrator (odin.sh)

| Command | Purpose | Root needed? |
|---------|---------|-------------|
| `hostname -f` | Get FQDN for `ODIN_HOSTNAME` | No |
| `date -u +"%Y-%m-%dT%H:%M:%SZ"` | ISO 8601 UTC timestamps | No |
| `date +%s` | Epoch seconds for `run_id` | No |
| `id -un` | Get username for `run_as` field | No |
| `timeout 90 bash <module>` | Run module with 90s kill timer | No |

---

## services.sh — Service Enumeration

### `systemctl show --type=service --all --property=Id,ActiveState,SubState,Type,UnitFileState --no-pager`

**Purpose:** Single batch query to get all service properties. Replaces per-unit `systemctl is-enabled` + `systemctl show` calls.

**As root:**
```
Id=sshd.service
ActiveState=active
SubState=running
Type=notify
UnitFileState=enabled

Id=nginx.service
ActiveState=active
SubState=running
Type=forking
UnitFileState=enabled

Id=bluetooth.service
ActiveState=inactive
SubState=dead
Type=dbus
UnitFileState=disabled
```
Full output for all system and user services. All states are accurate.

**As non-root:**
```
Id=sshd.service
ActiveState=active
SubState=running
Type=notify
UnitFileState=enabled
```
Same output. `systemctl show` reads service state from D-Bus and does **not** require root for reading. Full visibility.

**Risk:** None. This is a read-only query.

**Timeout:** 30 seconds.

---

### `service --status-all` (fallback 1)

**Purpose:** List services with running/stopped status on SysV init systems.

**As root:**
```
 [ + ]  apache2
 [ - ]  bluetooth
 [ + ]  cron
 [ + ]  ssh
 [ ? ]  hwclock.sh
```

**As non-root:**
Same output. `service --status-all` queries init scripts which are world-readable.

**Risk:** None. Read-only.

**Timeout:** 30 seconds.

---

### `timeout 5 /etc/init.d/<script> status` (fallback 2)

**Purpose:** Per-script status check for init.d services.

**As root:** Returns exit code 0 (running) or non-zero (stopped/unknown).

**As non-root:** Most scripts work. Some may fail if they check PID files in `/var/run/` that are root-only readable. Result: `service_status=unknown` for those services.

**Risk:** Broken init scripts can hang forever. The 5-second timeout prevents this.

**Timeout:** 5 seconds per script.

---

## ports.sh — Port Enumeration

### `ss -tulpn`

**Purpose:** List all listening TCP/UDP sockets with process information.

Flags:
- `-t` TCP
- `-u` UDP
- `-l` listening only
- `-p` show process name/PID (requires privilege for other users' sockets)
- `-n` numeric (no DNS resolution)

**As root:**
```
Netid State  Recv-Q Send-Q  Local Address:Port  Peer Address:Port  Process
tcp   LISTEN 0      128     0.0.0.0:22          0.0.0.0:*          users:(("sshd",pid=1234,fd=3))
tcp   LISTEN 0      511     0.0.0.0:80          0.0.0.0:*          users:(("nginx",pid=5678,fd=6))
tcp   LISTEN 0      128     127.0.0.1:5432      0.0.0.0:*          users:(("postgres",pid=9012,fd=4))
udp   LISTEN 0      0       0.0.0.0:68          0.0.0.0:*          users:(("dhclient",pid=345,fd=6))
```
All ports visible. Process name and PID included for every socket.

**As non-root:**
```
Netid State  Recv-Q Send-Q  Local Address:Port  Peer Address:Port  Process
tcp   LISTEN 0      128     0.0.0.0:22          0.0.0.0:*
tcp   LISTEN 0      511     0.0.0.0:80          0.0.0.0:*
tcp   LISTEN 0      128     127.0.0.1:5432      0.0.0.0:*
udp   LISTEN 0      0       0.0.0.0:68          0.0.0.0:*
```
All ports still visible. **Process info is missing** for sockets not owned by the current user. The kernel hides `/proc/<pid>/fd` entries for other users' processes unless you have `CAP_NET_ADMIN` or are root.

**Impact:** `process_name` and `process_pid` fields are empty for ~95% of ports on a typical server.

**Risk:** None. Read-only.

**Timeout:** 30 seconds.

---

### `netstat -tulpn` (fallback)

**Purpose:** Same as `ss -tulpn` on systems without `ss`.

**As root:** Same as ss — full process info.

**As non-root:** Same as ss — ports visible, process info missing for other users' sockets. Additionally, `netstat` may print `(Not all processes could be identified, non-owned process info will not be shown, you would have to be root to see it all.)` to stderr (which we redirect to /dev/null).

**Timeout:** 30 seconds.

---

## packages.sh — Package Enumeration

### `dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n'`

**Purpose:** List all installed Debian/Ubuntu packages with version and architecture.

**As root:**
```
openssh-server    1:8.9p1-3ubuntu0.6    amd64
nginx             1.24.0-1              amd64
libc6             2.35-0ubuntu3.6       amd64
```

**As non-root:** Identical output. The dpkg database at `/var/lib/dpkg/` is world-readable.

**Risk:** Can hang if another process holds the dpkg lock (`/var/lib/dpkg/lock`). Timeout prevents this.

**Timeout:** 30 seconds.

---

### `rpm -qa --queryformat '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\n'`

**Purpose:** List all installed RPM packages (RHEL/CentOS/SUSE/Fedora).

**As root:**
```
openssh-server    8.7p1-34.el9    x86_64
nginx             1.22.1-3.el9    x86_64
glibc             2.34-60.el9     x86_64
```

**As non-root:** Identical output. RPM database is world-readable.

**Risk:** None. Read-only query.

**Timeout:** 30 seconds.

---

### `apk list --installed` / `apk info -v`

**Purpose:** List installed Alpine Linux packages.

**As root/non-root:** Identical output. No privilege needed.

**Timeout:** 30 seconds.

---

### `pacman -Q`

**Purpose:** List installed Arch Linux packages.

**As root/non-root:** Identical output. No privilege needed.

**Timeout:** 30 seconds.

---

## processes.sh — Process Enumeration

### `ps -eo pid,ppid,user,stat,%cpu,%mem,etime,comm,args --no-headers`

**Purpose:** List all running processes with resource usage and command line.

Flags:
- `-e` all processes
- `-o` custom output format
- `--no-headers` skip header line

**As root:**
```
    1     0 root     Ss   0.0  0.1 30-02:15:30 systemd  /sbin/init
  456     1 root     Ss   0.0  0.0 30-02:15:28 sshd     sshd: /usr/sbin/sshd -D
 1234   456 root     Ss   0.0  0.1   01:23:45 sshd     sshd: user@pts/0
 5678     1 www-data Ss   0.1  2.3 15-00:30:00 nginx    nginx: master process /usr/sbin/nginx
 9012     1 postgres Ss   0.2  1.5 15-00:30:00 postgres /usr/lib/postgresql/15/bin/postgres
```
All processes visible, all fields populated.

**As non-root:**
On standard Linux (default `/proc` mount options): **identical output**. The `ps` command reads `/proc` which is world-readable by default.

Exception: If the system has `hidepid=1` or `hidepid=2` set on `/proc` mount:
- `hidepid=1` — other users' `/proc/<pid>/cmdline` is hidden → `args` field empty for other users
- `hidepid=2` — other users' `/proc/<pid>/` directories are completely hidden → only your own processes visible

To check: `mount | grep "proc.*hidepid"`

**Risk:** None. Read-only.

**Timeout:** 30 seconds.

---

### `ps -o pid,ppid,user,stat,comm,args` (fallback 1, BusyBox)

**Purpose:** Reduced field set for minimal systems without GNU ps.

**Root/non-root:** Same behavior as above (depends on `/proc` hidepid setting).

**Timeout:** 30 seconds.

---

### `ps -ef` / `ps aux` (fallback 2)

**Purpose:** Absolute fallback for systems where custom `-o` format fails.

**Root/non-root:** Same behavior.

**Timeout:** 30 seconds.

---

## cron.sh — Scheduled Task Enumeration

### File reads (no commands)

| Path | Purpose | Root needed? |
|------|---------|-------------|
| `/etc/crontab` | System crontab | No — world-readable |
| `/etc/cron.d/*` | Drop-in crontab files | No — world-readable |
| `/etc/cron.{hourly,daily,weekly,monthly}/*` | Periodic script directories | No — world-readable |
| `/etc/anacrontab` | Anacron schedule | No — world-readable |
| `/var/spool/cron/crontabs/*` | Per-user crontabs | **YES — directory is mode 700 root:root** |

**As root:** All user crontabs are readable. Full enumeration.

**As non-root:** `/var/spool/cron/crontabs/` returns "Permission denied". All user crontabs are invisible. System crontabs, cron.d, periodic scripts, and anacron are still visible. TA-ODIN emits a `type=privilege_warning` event when this happens.

---

### `systemctl list-timers --all --no-pager --no-legend`

**Purpose:** List all systemd timer units with their activation targets.

**As root:**
```
Sun 2026-02-22 00:00:00 UTC  logrotate.timer         logrotate.service
Mon 2026-02-23 06:00:00 UTC  apt-daily.timer         apt-daily.service
```

**As non-root:** Same output. `systemctl list-timers` is a read-only D-Bus query.

**Timeout:** 30 seconds.

---

### `systemctl show <timer_units...> --property=Id,TimersCalendar,TimersMonotonic --no-pager`

**Purpose:** Batch query timer schedule properties for all timers at once.

**As root/non-root:** Identical output. Read-only D-Bus query.

**Timeout:** 30 seconds.

---

## mounts.sh — Filesystem Mount Enumeration

### `df -PT` / `df -P` / `df`

**Purpose:** List mounted filesystems with size, usage, and type.

Flags:
- `-P` POSIX output format (consistent column layout)
- `-T` include filesystem type column

**As root:**
```
Filesystem     Type  1024-blocks    Used Available Capacity Mounted on
/dev/sda1      ext4    20511312 8234560  11213304      42% /
tmpfs          tmpfs    4053456       0   4053456       0% /dev/shm
/dev/sdb1      xfs    104857600 2345678 102511922       3% /data
nfs01:/exports nfs    524288000 1234567 523053433       1% /mnt/nfs
```

**As non-root:** Identical output. `/proc/mounts` is world-readable.

**Risk:** `df` can hang on unresponsive NFS mounts (kernel blocks on stat()). Timeout prevents this.

**Timeout:** 30 seconds.

---

## Summary: Privilege Impact

| Module | Command | Data as root | Data as non-root | Loss |
|--------|---------|-------------|-----------------|------|
| services | systemctl show | Full | Full | None |
| services | service --status-all | Full | Full | None |
| services | init.d status | Full | Mostly full | Some scripts may fail |
| **ports** | **ss -tulpn** | **Ports + processes** | **Ports only** | **process_name, process_pid** |
| packages | dpkg-query / rpm / apk / pacman | Full | Full | None |
| processes | ps -eo | Full | Full (unless hidepid) | None (standard config) |
| **cron** | **file reads** | **All crontabs** | **System only** | **User crontabs** |
| cron | systemctl list-timers | Full | Full | None |
| mounts | df | Full | Full | None |

### Recommendation

For full visibility, run TA-ODIN as root. If the Splunk Universal Forwarder runs as the `splunk` user, add a sudoers entry:

```
# /etc/sudoers.d/ta-odin
splunk ALL=(root) NOPASSWD: /opt/splunkforwarder/etc/apps/TA-ODIN/bin/odin.sh
```

Then in `local/inputs.conf` on the forwarder:
```ini
[script://./bin/odin.sh]
disabled = false
index = odin_discovery
sourcetype = odin:enumeration
interval = 2592000
timeout = 120
```

Note: Splunk scripted inputs run scripts directly as the Splunk user. To use sudo, create a wrapper script:

```bash
#!/bin/bash
# bin/odin_sudo.sh - Wrapper to run odin.sh as root
exec sudo /opt/splunkforwarder/etc/apps/TA-ODIN/bin/odin.sh
```

And point `inputs.conf` at the wrapper instead.
