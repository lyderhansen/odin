"""
ODIN Synthetic Data Generator

Generates realistic odin:enumeration events for multiple host profiles.
Output matches TA-ODIN v2.2.0 space-separated key=value format.

Usage:
    python3 tools/generate_odin_data.py [--output FILE] [--hosts HOST,...] [--date YYYY-MM-DD]
"""

import random
from datetime import datetime

ODIN_VERSION = "2.2.0"


def format_event(
    timestamp: str,
    hostname: str,
    os: str,
    run_id: str,
    version: str,
    type_: str,
    fields: dict,
) -> str:
    """Format a single ODIN event as space-separated key=value."""
    parts = [
        f"timestamp={timestamp}",
        f"hostname={hostname}",
        f"os={os}",
        f"run_id={run_id}",
        f"odin_version={version}",
        f"type={type_}",
    ]
    for key, val in fields.items():
        if val is None or val == "":
            continue
        val_str = str(val)
        if " " in val_str:
            parts.append(f'{key}="{val_str}"')
        else:
            parts.append(f"{key}={val_str}")
    return " ".join(parts)


# ---------------------------------------------------------------------------
# Base constants: common to every Linux host
# ---------------------------------------------------------------------------

BASE_SERVICES = [
    {"service_name": "sshd", "service_status": "running", "service_enabled": "enabled"},
    {"service_name": "crond", "service_status": "running", "service_enabled": "enabled"},
    {"service_name": "rsyslog", "service_status": "running", "service_enabled": "enabled"},
    {"service_name": "auditd", "service_status": "running", "service_enabled": "enabled"},
    {"service_name": "node_exporter", "service_status": "running", "service_enabled": "enabled"},
    {"service_name": "chronyd", "service_status": "running", "service_enabled": "enabled"},
    {"service_name": "systemd-journald", "service_status": "running", "service_enabled": "static"},
    {"service_name": "systemd-logind", "service_status": "running", "service_enabled": "static"},
    {"service_name": "NetworkManager", "service_status": "running", "service_enabled": "enabled"},
    {"service_name": "tuned", "service_status": "running", "service_enabled": "enabled"},
]

BASE_PORTS = [
    {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "22", "process_name": "sshd", "process_pid": ""},
    {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "9100", "process_name": "node_exporter", "process_pid": ""},
]

BASE_PACKAGES = [
    {"package_name": "bash", "package_version": "5.2.26-3.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "coreutils", "package_version": "8.32-36.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "openssl", "package_version": "3.0.7-27.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "curl", "package_version": "7.76.1-29.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "systemd", "package_version": "252-32.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "openssh-server", "package_version": "8.7p1-38.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "rsyslog", "package_version": "8.2208.0-3.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "audit", "package_version": "3.0.7-104.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "chrony", "package_version": "4.3-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "ca-certificates", "package_version": "2023.2.60-1.el9", "package_arch": "noarch", "package_manager": "rpm"},
    {"package_name": "node_exporter", "package_version": "1.7.0-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "glibc", "package_version": "2.34-100.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "python3", "package_version": "3.9.18-3.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "vim-minimal", "package_version": "8.2.2637-20.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "tar", "package_version": "1.34-6.el9", "package_arch": "x86_64", "package_manager": "rpm"},
]

BASE_MOUNTS = [
    {"mount_device": "/dev/sda2", "mount_point": "/", "mount_type": "xfs", "mount_size_kb": "52428800", "mount_used_kb": "8388608", "mount_avail_kb": "44040192", "mount_use_pct": "16"},
    {"mount_device": "/dev/sda1", "mount_point": "/boot", "mount_type": "xfs", "mount_size_kb": "1048576", "mount_used_kb": "262144", "mount_avail_kb": "786432", "mount_use_pct": "25"},
    {"mount_device": "tmpfs", "mount_point": "/dev/shm", "mount_type": "tmpfs", "mount_size_kb": "8177772", "mount_used_kb": "0", "mount_avail_kb": "8177772", "mount_use_pct": "0"},
    {"mount_device": "tmpfs", "mount_point": "/tmp", "mount_type": "tmpfs", "mount_size_kb": "8177772", "mount_used_kb": "4096", "mount_avail_kb": "8173676", "mount_use_pct": "1"},
]

BASE_PROCESSES = [
    {"process_pid": "1", "process_ppid": "0", "process_user": "root", "process_state": "Ss", "process_cpu": "0.0", "process_mem": "0.1", "process_elapsed": "30-00:00:00", "process_name": "systemd", "process_command": "/usr/lib/systemd/systemd --switched-root --system"},
    {"process_pid": "2", "process_ppid": "0", "process_user": "root", "process_state": "S", "process_cpu": "0.0", "process_mem": "0.0", "process_elapsed": "30-00:00:00", "process_name": "kthreadd", "process_command": ""},
]

BASE_CRON = [
    {"cron_source": "cron.daily", "cron_user": "root", "cron_schedule": "", "cron_command": "logrotate /etc/logrotate.conf", "cron_file": "/etc/cron.daily/logrotate"},
    {"cron_source": "cron.daily", "cron_user": "root", "cron_schedule": "", "cron_command": "man-db-cache-update", "cron_file": "/etc/cron.daily/man-db"},
]


# ---------------------------------------------------------------------------
# Host profiles: 15 Linux hosts with role-specific services, ports, packages
# ---------------------------------------------------------------------------

HOST_PROFILES = {
    # -----------------------------------------------------------------------
    # 1. web-prod-01: Nginx web server
    # -----------------------------------------------------------------------
    "web-prod-01.odin.local": {
        "os": "linux",
        "services": [
            *BASE_SERVICES,
            {"service_name": "nginx", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "firewalld", "service_status": "running", "service_enabled": "enabled"},
        ],
        "ports": [
            *BASE_PORTS,
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "80", "process_name": "nginx", "process_pid": ""},
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "443", "process_name": "nginx", "process_pid": ""},
        ],
        "packages": [
            *BASE_PACKAGES,
            {"package_name": "nginx", "package_version": "1.24.0-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
        ],
        "processes": [
            *BASE_PROCESSES,
            {"process_pid": "1200", "process_ppid": "1", "process_user": "root", "process_state": "Ss", "process_cpu": "0.0", "process_mem": "0.1", "process_elapsed": "30-00:00:00", "process_name": "nginx", "process_command": "nginx: master process /usr/sbin/nginx"},
            {"process_pid": "1201", "process_ppid": "1200", "process_user": "nginx", "process_state": "S", "process_cpu": "0.1", "process_mem": "0.3", "process_elapsed": "30-00:00:00", "process_name": "nginx", "process_command": "nginx: worker process"},
            {"process_pid": "1202", "process_ppid": "1200", "process_user": "nginx", "process_state": "S", "process_cpu": "0.1", "process_mem": "0.3", "process_elapsed": "30-00:00:00", "process_name": "nginx", "process_command": "nginx: worker process"},
        ],
        "mounts": [*BASE_MOUNTS],
        "cron": [*BASE_CRON],
    },

    # -----------------------------------------------------------------------
    # 2. web-prod-02: Apache + PHP web server
    # -----------------------------------------------------------------------
    "web-prod-02.odin.local": {
        "os": "linux",
        "services": [
            *BASE_SERVICES,
            {"service_name": "httpd", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "php-fpm", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "firewalld", "service_status": "running", "service_enabled": "enabled"},
        ],
        "ports": [
            *BASE_PORTS,
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "80", "process_name": "httpd", "process_pid": ""},
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "443", "process_name": "httpd", "process_pid": ""},
            {"transport": "tcp", "listen_address": "127.0.0.1", "listen_port": "9000", "process_name": "php-fpm", "process_pid": ""},
        ],
        "packages": [
            *BASE_PACKAGES,
            {"package_name": "httpd", "package_version": "2.4.57-5.el9", "package_arch": "x86_64", "package_manager": "rpm"},
            {"package_name": "php-fpm", "package_version": "8.1.27-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
        ],
        "processes": [
            *BASE_PROCESSES,
            {"process_pid": "1300", "process_ppid": "1", "process_user": "root", "process_state": "Ss", "process_cpu": "0.0", "process_mem": "0.2", "process_elapsed": "30-00:00:00", "process_name": "httpd", "process_command": "/usr/sbin/httpd -DFOREGROUND"},
            {"process_pid": "1301", "process_ppid": "1300", "process_user": "apache", "process_state": "S", "process_cpu": "0.1", "process_mem": "0.4", "process_elapsed": "30-00:00:00", "process_name": "httpd", "process_command": "/usr/sbin/httpd -DFOREGROUND"},
            {"process_pid": "1400", "process_ppid": "1", "process_user": "root", "process_state": "Ss", "process_cpu": "0.0", "process_mem": "0.1", "process_elapsed": "30-00:00:00", "process_name": "php-fpm", "process_command": "php-fpm: master process (/etc/php-fpm.conf)"},
            {"process_pid": "1401", "process_ppid": "1400", "process_user": "apache", "process_state": "S", "process_cpu": "0.2", "process_mem": "0.5", "process_elapsed": "30-00:00:00", "process_name": "php-fpm", "process_command": "php-fpm: pool www"},
        ],
        "mounts": [*BASE_MOUNTS],
        "cron": [*BASE_CRON],
    },

    # -----------------------------------------------------------------------
    # 3. db-prod-01: PostgreSQL database server
    # -----------------------------------------------------------------------
    "db-prod-01.odin.local": {
        "os": "linux",
        "services": [
            *BASE_SERVICES,
            {"service_name": "postgresql", "service_status": "running", "service_enabled": "enabled"},
        ],
        "ports": [
            *BASE_PORTS,
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "5432", "process_name": "postgres", "process_pid": ""},
        ],
        "packages": [
            *BASE_PACKAGES,
            {"package_name": "postgresql-server", "package_version": "15.6-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
        ],
        "processes": [
            *BASE_PROCESSES,
            {"process_pid": "1500", "process_ppid": "1", "process_user": "postgres", "process_state": "Ss", "process_cpu": "0.1", "process_mem": "1.2", "process_elapsed": "30-00:00:00", "process_name": "postgres", "process_command": "/usr/pgsql-15/bin/postgres -D /var/lib/pgsql/15/data"},
            {"process_pid": "1501", "process_ppid": "1500", "process_user": "postgres", "process_state": "Ss", "process_cpu": "0.0", "process_mem": "0.3", "process_elapsed": "30-00:00:00", "process_name": "postgres", "process_command": "postgres: checkpointer"},
            {"process_pid": "1502", "process_ppid": "1500", "process_user": "postgres", "process_state": "Ss", "process_cpu": "0.0", "process_mem": "0.2", "process_elapsed": "30-00:00:00", "process_name": "postgres", "process_command": "postgres: background writer"},
            {"process_pid": "1503", "process_ppid": "1500", "process_user": "postgres", "process_state": "Ss", "process_cpu": "0.0", "process_mem": "0.4", "process_elapsed": "30-00:00:00", "process_name": "postgres", "process_command": "postgres: walwriter"},
        ],
        "mounts": [
            *BASE_MOUNTS,
            {"mount_device": "/dev/sdb1", "mount_point": "/var/lib/pgsql", "mount_type": "xfs", "mount_size_kb": "104857600", "mount_used_kb": "31457280", "mount_avail_kb": "73400320", "mount_use_pct": "30"},
        ],
        "cron": [
            *BASE_CRON,
            {"cron_source": "crontab", "cron_user": "postgres", "cron_schedule": "0 2 * * *", "cron_command": "pg_dump -U postgres mydb | gzip > /backup/mydb_$(date +\\%F).sql.gz", "cron_file": "/var/spool/cron/postgres"},
        ],
    },

    # -----------------------------------------------------------------------
    # 4. db-prod-02: MySQL database server
    # -----------------------------------------------------------------------
    "db-prod-02.odin.local": {
        "os": "linux",
        "services": [
            *BASE_SERVICES,
            {"service_name": "mysqld", "service_status": "running", "service_enabled": "enabled"},
        ],
        "ports": [
            *BASE_PORTS,
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "3306", "process_name": "mysqld", "process_pid": ""},
        ],
        "packages": [
            *BASE_PACKAGES,
            {"package_name": "mysql-server", "package_version": "8.0.36-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
        ],
        "processes": [
            *BASE_PROCESSES,
            {"process_pid": "1600", "process_ppid": "1", "process_user": "mysql", "process_state": "Ssl", "process_cpu": "0.5", "process_mem": "5.2", "process_elapsed": "30-00:00:00", "process_name": "mysqld", "process_command": "/usr/sbin/mysqld --defaults-file=/etc/my.cnf"},
        ],
        "mounts": [
            *BASE_MOUNTS,
            {"mount_device": "/dev/sdb1", "mount_point": "/var/lib/mysql", "mount_type": "xfs", "mount_size_kb": "104857600", "mount_used_kb": "20971520", "mount_avail_kb": "83886080", "mount_use_pct": "20"},
        ],
        "cron": [
            *BASE_CRON,
            {"cron_source": "crontab", "cron_user": "root", "cron_schedule": "0 3 * * *", "cron_command": "mysqldump --all-databases | gzip > /backup/all_db_$(date +\\%F).sql.gz", "cron_file": "/var/spool/cron/root"},
        ],
    },

    # -----------------------------------------------------------------------
    # 5. app-prod-01: Docker container host
    # -----------------------------------------------------------------------
    "app-prod-01.odin.local": {
        "os": "linux",
        "services": [
            *BASE_SERVICES,
            {"service_name": "docker", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "containerd", "service_status": "running", "service_enabled": "enabled"},
        ],
        "ports": [
            *BASE_PORTS,
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "8080", "process_name": "docker-proxy", "process_pid": ""},
        ],
        "packages": [
            *BASE_PACKAGES,
            {"package_name": "docker-ce", "package_version": "24.0.7-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
            {"package_name": "containerd.io", "package_version": "1.6.28-3.1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
        ],
        "processes": [
            *BASE_PROCESSES,
            {"process_pid": "1700", "process_ppid": "1", "process_user": "root", "process_state": "Ssl", "process_cpu": "0.3", "process_mem": "1.8", "process_elapsed": "30-00:00:00", "process_name": "dockerd", "process_command": "/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock"},
            {"process_pid": "1701", "process_ppid": "1", "process_user": "root", "process_state": "Ssl", "process_cpu": "0.2", "process_mem": "0.8", "process_elapsed": "30-00:00:00", "process_name": "containerd", "process_command": "/usr/bin/containerd"},
        ],
        "mounts": [
            *BASE_MOUNTS,
            {"mount_device": "/dev/sdb1", "mount_point": "/var/lib/docker", "mount_type": "xfs", "mount_size_kb": "209715200", "mount_used_kb": "52428800", "mount_avail_kb": "157286400", "mount_use_pct": "25"},
        ],
        "cron": [
            *BASE_CRON,
            {"cron_source": "crontab", "cron_user": "root", "cron_schedule": "0 4 * * 0", "cron_command": "docker system prune -af --volumes > /dev/null 2>&1", "cron_file": "/var/spool/cron/root"},
        ],
    },

    # -----------------------------------------------------------------------
    # 6. cache-prod-01: Redis + Memcached cache server
    # -----------------------------------------------------------------------
    "cache-prod-01.odin.local": {
        "os": "linux",
        "services": [
            *BASE_SERVICES,
            {"service_name": "redis", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "memcached", "service_status": "running", "service_enabled": "enabled"},
        ],
        "ports": [
            *BASE_PORTS,
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "6379", "process_name": "redis-server", "process_pid": ""},
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "11211", "process_name": "memcached", "process_pid": ""},
        ],
        "packages": [
            *BASE_PACKAGES,
            {"package_name": "redis-server", "package_version": "7.0.15-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
            {"package_name": "memcached", "package_version": "1.6.22-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
        ],
        "processes": [
            *BASE_PROCESSES,
            {"process_pid": "1800", "process_ppid": "1", "process_user": "redis", "process_state": "Ssl", "process_cpu": "0.2", "process_mem": "2.5", "process_elapsed": "30-00:00:00", "process_name": "redis-server", "process_command": "/usr/bin/redis-server 0.0.0.0:6379"},
            {"process_pid": "1900", "process_ppid": "1", "process_user": "memcached", "process_state": "Ssl", "process_cpu": "0.1", "process_mem": "1.0", "process_elapsed": "30-00:00:00", "process_name": "memcached", "process_command": "/usr/bin/memcached -u memcached -p 11211 -m 512"},
        ],
        "mounts": [*BASE_MOUNTS],
        "cron": [*BASE_CRON],
    },

    # -----------------------------------------------------------------------
    # 7. log-prod-01: Splunk server + syslog receiver
    # -----------------------------------------------------------------------
    "log-prod-01.odin.local": {
        "os": "linux",
        "services": [
            *BASE_SERVICES,
            {"service_name": "splunkd", "service_status": "running", "service_enabled": "enabled"},
        ],
        "ports": [
            *BASE_PORTS,
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "514", "process_name": "rsyslogd", "process_pid": ""},
            {"transport": "udp", "listen_address": "0.0.0.0", "listen_port": "514", "process_name": "rsyslogd", "process_pid": ""},
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "9997", "process_name": "splunkd", "process_pid": ""},
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "8089", "process_name": "splunkd", "process_pid": ""},
        ],
        "packages": [
            *BASE_PACKAGES,
            {"package_name": "splunk", "package_version": "9.2.1-1.x86_64", "package_arch": "x86_64", "package_manager": "rpm"},
        ],
        "processes": [
            *BASE_PROCESSES,
            {"process_pid": "2000", "process_ppid": "1", "process_user": "splunk", "process_state": "Ssl", "process_cpu": "2.5", "process_mem": "12.3", "process_elapsed": "30-00:00:00", "process_name": "splunkd", "process_command": "/opt/splunk/bin/splunkd -p 8089 start"},
            {"process_pid": "2001", "process_ppid": "2000", "process_user": "splunk", "process_state": "Sl", "process_cpu": "1.2", "process_mem": "8.7", "process_elapsed": "30-00:00:00", "process_name": "splunkd", "process_command": "splunkd -p 8089 restart"},
        ],
        "mounts": [
            *BASE_MOUNTS,
            {"mount_device": "/dev/sdb1", "mount_point": "/opt/splunk", "mount_type": "xfs", "mount_size_kb": "524288000", "mount_used_kb": "157286400", "mount_avail_kb": "367001600", "mount_use_pct": "30"},
        ],
        "cron": [
            *BASE_CRON,
            {"cron_source": "crontab", "cron_user": "splunk", "cron_schedule": "0 0 * * *", "cron_command": "/opt/splunk/bin/splunk clean eventdata -index _internalold -f", "cron_file": "/var/spool/cron/splunk"},
        ],
    },

    # -----------------------------------------------------------------------
    # 8. mon-prod-01: Monitoring server (Prometheus + Grafana + Alertmanager)
    # -----------------------------------------------------------------------
    "mon-prod-01.odin.local": {
        "os": "linux",
        "services": [
            *BASE_SERVICES,
            {"service_name": "prometheus", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "grafana-server", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "alertmanager", "service_status": "running", "service_enabled": "enabled"},
        ],
        "ports": [
            *BASE_PORTS,
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "9090", "process_name": "prometheus", "process_pid": ""},
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "3000", "process_name": "grafana-server", "process_pid": ""},
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "9093", "process_name": "alertmanager", "process_pid": ""},
        ],
        "packages": [
            *BASE_PACKAGES,
            {"package_name": "prometheus", "package_version": "2.48.1-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
            {"package_name": "grafana", "package_version": "10.2.3-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
        ],
        "processes": [
            *BASE_PROCESSES,
            {"process_pid": "2100", "process_ppid": "1", "process_user": "prometheus", "process_state": "Ssl", "process_cpu": "1.5", "process_mem": "4.2", "process_elapsed": "30-00:00:00", "process_name": "prometheus", "process_command": "/usr/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus"},
            {"process_pid": "2200", "process_ppid": "1", "process_user": "grafana", "process_state": "Ssl", "process_cpu": "0.3", "process_mem": "1.5", "process_elapsed": "30-00:00:00", "process_name": "grafana-server", "process_command": "/usr/share/grafana/bin/grafana server --config=/etc/grafana/grafana.ini"},
            {"process_pid": "2300", "process_ppid": "1", "process_user": "prometheus", "process_state": "Ssl", "process_cpu": "0.1", "process_mem": "0.5", "process_elapsed": "30-00:00:00", "process_name": "alertmanager", "process_command": "/usr/bin/alertmanager --config.file=/etc/alertmanager/alertmanager.yml"},
        ],
        "mounts": [
            *BASE_MOUNTS,
            {"mount_device": "/dev/sdb1", "mount_point": "/var/lib/prometheus", "mount_type": "xfs", "mount_size_kb": "104857600", "mount_used_kb": "41943040", "mount_avail_kb": "62914560", "mount_use_pct": "40"},
        ],
        "cron": [*BASE_CRON],
    },

    # -----------------------------------------------------------------------
    # 9. k8s-master-01: Kubernetes master node
    # -----------------------------------------------------------------------
    "k8s-master-01.odin.local": {
        "os": "linux",
        "services": [
            *BASE_SERVICES,
            {"service_name": "kube-apiserver", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "etcd", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "kube-scheduler", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "kube-controller-manager", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "kubelet", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "containerd", "service_status": "running", "service_enabled": "enabled"},
        ],
        "ports": [
            *BASE_PORTS,
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "6443", "process_name": "kube-apiserver", "process_pid": ""},
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "2379", "process_name": "etcd", "process_pid": ""},
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "2380", "process_name": "etcd", "process_pid": ""},
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "10250", "process_name": "kubelet", "process_pid": ""},
        ],
        "packages": [
            *BASE_PACKAGES,
            {"package_name": "kubeadm", "package_version": "1.29.2-0", "package_arch": "x86_64", "package_manager": "rpm"},
            {"package_name": "kubectl", "package_version": "1.29.2-0", "package_arch": "x86_64", "package_manager": "rpm"},
            {"package_name": "kubelet", "package_version": "1.29.2-0", "package_arch": "x86_64", "package_manager": "rpm"},
            {"package_name": "containerd.io", "package_version": "1.6.28-3.1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
        ],
        "processes": [
            *BASE_PROCESSES,
            {"process_pid": "2400", "process_ppid": "1", "process_user": "root", "process_state": "Ssl", "process_cpu": "3.0", "process_mem": "6.5", "process_elapsed": "30-00:00:00", "process_name": "kube-apiserver", "process_command": "kube-apiserver --advertise-address=10.0.0.10 --etcd-servers=https://127.0.0.1:2379"},
            {"process_pid": "2401", "process_ppid": "1", "process_user": "etcd", "process_state": "Ssl", "process_cpu": "2.0", "process_mem": "3.8", "process_elapsed": "30-00:00:00", "process_name": "etcd", "process_command": "/usr/bin/etcd --data-dir=/var/lib/etcd"},
            {"process_pid": "2402", "process_ppid": "1", "process_user": "root", "process_state": "Ssl", "process_cpu": "0.5", "process_mem": "1.2", "process_elapsed": "30-00:00:00", "process_name": "kube-scheduler", "process_command": "kube-scheduler --kubeconfig=/etc/kubernetes/scheduler.conf"},
            {"process_pid": "2403", "process_ppid": "1", "process_user": "root", "process_state": "Ssl", "process_cpu": "1.0", "process_mem": "2.0", "process_elapsed": "30-00:00:00", "process_name": "kube-controller-manager", "process_command": "kube-controller-manager --kubeconfig=/etc/kubernetes/controller-manager.conf"},
            {"process_pid": "2404", "process_ppid": "1", "process_user": "root", "process_state": "Ssl", "process_cpu": "0.5", "process_mem": "1.5", "process_elapsed": "30-00:00:00", "process_name": "kubelet", "process_command": "/usr/bin/kubelet --config=/var/lib/kubelet/config.yaml"},
            {"process_pid": "2405", "process_ppid": "1", "process_user": "root", "process_state": "Ssl", "process_cpu": "0.3", "process_mem": "0.8", "process_elapsed": "30-00:00:00", "process_name": "containerd", "process_command": "/usr/bin/containerd"},
        ],
        "mounts": [*BASE_MOUNTS],
        "cron": [*BASE_CRON],
    },

    # -----------------------------------------------------------------------
    # 10. k8s-worker-01: Kubernetes worker node
    # -----------------------------------------------------------------------
    "k8s-worker-01.odin.local": {
        "os": "linux",
        "services": [
            *BASE_SERVICES,
            {"service_name": "kubelet", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "containerd", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "kube-proxy", "service_status": "running", "service_enabled": "enabled"},
        ],
        "ports": [
            *BASE_PORTS,
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "10250", "process_name": "kubelet", "process_pid": ""},
        ],
        "packages": [
            *BASE_PACKAGES,
            {"package_name": "kubelet", "package_version": "1.29.2-0", "package_arch": "x86_64", "package_manager": "rpm"},
            {"package_name": "containerd.io", "package_version": "1.6.28-3.1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
        ],
        "processes": [
            *BASE_PROCESSES,
            {"process_pid": "2500", "process_ppid": "1", "process_user": "root", "process_state": "Ssl", "process_cpu": "0.8", "process_mem": "2.0", "process_elapsed": "30-00:00:00", "process_name": "kubelet", "process_command": "/usr/bin/kubelet --config=/var/lib/kubelet/config.yaml"},
            {"process_pid": "2501", "process_ppid": "1", "process_user": "root", "process_state": "Ssl", "process_cpu": "0.3", "process_mem": "0.8", "process_elapsed": "30-00:00:00", "process_name": "containerd", "process_command": "/usr/bin/containerd"},
            {"process_pid": "2502", "process_ppid": "1", "process_user": "root", "process_state": "Ssl", "process_cpu": "0.1", "process_mem": "0.3", "process_elapsed": "30-00:00:00", "process_name": "kube-proxy", "process_command": "/usr/bin/kube-proxy --config=/var/lib/kube-proxy/config.conf"},
        ],
        "mounts": [*BASE_MOUNTS],
        "cron": [*BASE_CRON],
    },

    # -----------------------------------------------------------------------
    # 11. mail-prod-01: Mail server (Postfix + Dovecot)
    # -----------------------------------------------------------------------
    "mail-prod-01.odin.local": {
        "os": "linux",
        "services": [
            *BASE_SERVICES,
            {"service_name": "postfix", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "dovecot", "service_status": "running", "service_enabled": "enabled"},
        ],
        "ports": [
            *BASE_PORTS,
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "25", "process_name": "master", "process_pid": ""},
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "587", "process_name": "master", "process_pid": ""},
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "993", "process_name": "dovecot", "process_pid": ""},
        ],
        "packages": [
            *BASE_PACKAGES,
            {"package_name": "postfix", "package_version": "3.5.9-24.el9", "package_arch": "x86_64", "package_manager": "rpm"},
            {"package_name": "dovecot-core", "package_version": "2.3.16-11.el9", "package_arch": "x86_64", "package_manager": "rpm"},
        ],
        "processes": [
            *BASE_PROCESSES,
            {"process_pid": "2600", "process_ppid": "1", "process_user": "root", "process_state": "Ss", "process_cpu": "0.0", "process_mem": "0.2", "process_elapsed": "30-00:00:00", "process_name": "master", "process_command": "/usr/libexec/postfix/master -w"},
            {"process_pid": "2601", "process_ppid": "2600", "process_user": "postfix", "process_state": "S", "process_cpu": "0.0", "process_mem": "0.1", "process_elapsed": "30-00:00:00", "process_name": "pickup", "process_command": "pickup -l -t unix -u"},
            {"process_pid": "2602", "process_ppid": "2600", "process_user": "postfix", "process_state": "S", "process_cpu": "0.0", "process_mem": "0.1", "process_elapsed": "30-00:00:00", "process_name": "qmgr", "process_command": "qmgr -l -t unix -u"},
            {"process_pid": "2700", "process_ppid": "1", "process_user": "root", "process_state": "Ss", "process_cpu": "0.0", "process_mem": "0.2", "process_elapsed": "30-00:00:00", "process_name": "dovecot", "process_command": "/usr/sbin/dovecot -F"},
        ],
        "mounts": [
            *BASE_MOUNTS,
            {"mount_device": "/dev/sdb1", "mount_point": "/var/mail", "mount_type": "xfs", "mount_size_kb": "104857600", "mount_used_kb": "10485760", "mount_avail_kb": "94371840", "mount_use_pct": "10"},
        ],
        "cron": [*BASE_CRON],
    },

    # -----------------------------------------------------------------------
    # 12. vpn-prod-01: OpenVPN server
    # -----------------------------------------------------------------------
    "vpn-prod-01.odin.local": {
        "os": "linux",
        "services": [
            *BASE_SERVICES,
            {"service_name": "openvpn", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "firewalld", "service_status": "running", "service_enabled": "enabled"},
        ],
        "ports": [
            *BASE_PORTS,
            {"transport": "udp", "listen_address": "0.0.0.0", "listen_port": "1194", "process_name": "openvpn", "process_pid": ""},
        ],
        "packages": [
            *BASE_PACKAGES,
            {"package_name": "openvpn", "package_version": "2.5.9-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
        ],
        "processes": [
            *BASE_PROCESSES,
            {"process_pid": "2800", "process_ppid": "1", "process_user": "nobody", "process_state": "Ss", "process_cpu": "0.0", "process_mem": "0.1", "process_elapsed": "30-00:00:00", "process_name": "openvpn", "process_command": "/usr/sbin/openvpn --config /etc/openvpn/server.conf"},
        ],
        "mounts": [*BASE_MOUNTS],
        "cron": [*BASE_CRON],
    },

    # -----------------------------------------------------------------------
    # 13. ci-prod-01: Jenkins CI/CD server + Docker
    # -----------------------------------------------------------------------
    "ci-prod-01.odin.local": {
        "os": "linux",
        "services": [
            *BASE_SERVICES,
            {"service_name": "jenkins", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "docker", "service_status": "running", "service_enabled": "enabled"},
        ],
        "ports": [
            *BASE_PORTS,
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "8080", "process_name": "java", "process_pid": ""},
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "50000", "process_name": "java", "process_pid": ""},
        ],
        "packages": [
            *BASE_PACKAGES,
            {"package_name": "jenkins", "package_version": "2.440.1-1.1", "package_arch": "noarch", "package_manager": "rpm"},
            {"package_name": "docker-ce", "package_version": "24.0.7-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
            {"package_name": "git", "package_version": "2.39.3-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
        ],
        "processes": [
            *BASE_PROCESSES,
            {"process_pid": "2900", "process_ppid": "1", "process_user": "jenkins", "process_state": "Ssl", "process_cpu": "5.0", "process_mem": "15.2", "process_elapsed": "30-00:00:00", "process_name": "java", "process_command": "/usr/bin/java -Djava.awt.headless=true -jar /usr/share/java/jenkins.war --httpPort=8080"},
            {"process_pid": "2901", "process_ppid": "1", "process_user": "root", "process_state": "Ssl", "process_cpu": "0.3", "process_mem": "1.8", "process_elapsed": "30-00:00:00", "process_name": "dockerd", "process_command": "/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock"},
        ],
        "mounts": [
            *BASE_MOUNTS,
            {"mount_device": "/dev/sdb1", "mount_point": "/var/lib/jenkins", "mount_type": "xfs", "mount_size_kb": "104857600", "mount_used_kb": "31457280", "mount_avail_kb": "73400320", "mount_use_pct": "30"},
        ],
        "cron": [
            *BASE_CRON,
            {"cron_source": "crontab", "cron_user": "jenkins", "cron_schedule": "0 5 * * 0", "cron_command": "find /var/lib/jenkins/jobs/*/builds -maxdepth 1 -mtime +30 -exec rm -rf {} \\;", "cron_file": "/var/spool/cron/jenkins"},
        ],
    },

    # -----------------------------------------------------------------------
    # 14. dns-prod-01: BIND DNS server
    # -----------------------------------------------------------------------
    "dns-prod-01.odin.local": {
        "os": "linux",
        "services": [
            *BASE_SERVICES,
            {"service_name": "named", "service_status": "running", "service_enabled": "enabled"},
        ],
        "ports": [
            *BASE_PORTS,
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "53", "process_name": "named", "process_pid": ""},
            {"transport": "udp", "listen_address": "0.0.0.0", "listen_port": "53", "process_name": "named", "process_pid": ""},
        ],
        "packages": [
            *BASE_PACKAGES,
            {"package_name": "bind", "package_version": "9.16.23-14.el9", "package_arch": "x86_64", "package_manager": "rpm"},
        ],
        "processes": [
            *BASE_PROCESSES,
            {"process_pid": "3000", "process_ppid": "1", "process_user": "named", "process_state": "Ssl", "process_cpu": "0.2", "process_mem": "0.8", "process_elapsed": "30-00:00:00", "process_name": "named", "process_command": "/usr/sbin/named -u named -c /etc/named.conf"},
        ],
        "mounts": [*BASE_MOUNTS],
        "cron": [*BASE_CRON],
    },

    # -----------------------------------------------------------------------
    # 15. mq-prod-01: RabbitMQ message broker
    # -----------------------------------------------------------------------
    "mq-prod-01.odin.local": {
        "os": "linux",
        "services": [
            *BASE_SERVICES,
            {"service_name": "rabbitmq-server", "service_status": "running", "service_enabled": "enabled"},
        ],
        "ports": [
            *BASE_PORTS,
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "5672", "process_name": "beam.smp", "process_pid": ""},
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "15672", "process_name": "beam.smp", "process_pid": ""},
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "25672", "process_name": "beam.smp", "process_pid": ""},
        ],
        "packages": [
            *BASE_PACKAGES,
            {"package_name": "rabbitmq-server", "package_version": "3.12.12-1.el9", "package_arch": "noarch", "package_manager": "rpm"},
            {"package_name": "erlang", "package_version": "26.2.1-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
        ],
        "processes": [
            *BASE_PROCESSES,
            {"process_pid": "3100", "process_ppid": "1", "process_user": "rabbitmq", "process_state": "Ssl", "process_cpu": "1.5", "process_mem": "4.0", "process_elapsed": "30-00:00:00", "process_name": "beam.smp", "process_command": "/usr/lib64/erlang/erts-14.2.1/bin/beam.smp -W w -MBas ageffcbf -MHas ageffcbf"},
            {"process_pid": "3101", "process_ppid": "3100", "process_user": "rabbitmq", "process_state": "Ss", "process_cpu": "0.0", "process_mem": "0.1", "process_elapsed": "30-00:00:00", "process_name": "erl_child_setup", "process_command": "erl_child_setup 1048576"},
        ],
        "mounts": [
            *BASE_MOUNTS,
            {"mount_device": "/dev/sdb1", "mount_point": "/var/lib/rabbitmq", "mount_type": "xfs", "mount_size_kb": "52428800", "mount_used_kb": "5242880", "mount_avail_kb": "47185920", "mount_use_pct": "10"},
        ],
        "cron": [*BASE_CRON],
    },
}


def generate_scan(
    hostname: str,
    profile: dict,
    scan_timestamp: str,
    run_id: str,
) -> list:
    """Generate all events for one full ODIN scan of a host."""
    os_name = profile["os"]
    events = []
    sec_offset = 0

    def next_ts():
        nonlocal sec_offset
        # Increment seconds within the same minute
        ts = scan_timestamp[:-3] + f"{sec_offset:02d}Z"
        sec_offset = min(sec_offset + 1, 59)
        return ts

    # 1. Start event
    events.append(format_event(
        timestamp=next_ts(), hostname=hostname, os=os_name,
        run_id=run_id, version=ODIN_VERSION, type_="odin_start",
        fields={"run_as": "root", "euid": "0", "message": "TA-ODIN enumeration started"},
    ))

    # 2. Service events
    for svc in profile["services"]:
        events.append(format_event(
            timestamp=next_ts(), hostname=hostname, os=os_name,
            run_id=run_id, version=ODIN_VERSION, type_="service", fields=svc,
        ))

    # 3. Port events
    for port in profile["ports"]:
        events.append(format_event(
            timestamp=next_ts(), hostname=hostname, os=os_name,
            run_id=run_id, version=ODIN_VERSION, type_="port", fields=port,
        ))

    # 4. Package events
    for pkg in profile["packages"]:
        events.append(format_event(
            timestamp=next_ts(), hostname=hostname, os=os_name,
            run_id=run_id, version=ODIN_VERSION, type_="package", fields=pkg,
        ))

    # 5. Cron events
    for cron in profile["cron"]:
        events.append(format_event(
            timestamp=next_ts(), hostname=hostname, os=os_name,
            run_id=run_id, version=ODIN_VERSION, type_="cron", fields=cron,
        ))

    # 6. Process events
    for proc in profile["processes"]:
        events.append(format_event(
            timestamp=next_ts(), hostname=hostname, os=os_name,
            run_id=run_id, version=ODIN_VERSION, type_="process", fields=proc,
        ))

    # 7. Mount events
    for mnt in profile["mounts"]:
        events.append(format_event(
            timestamp=next_ts(), hostname=hostname, os=os_name,
            run_id=run_id, version=ODIN_VERSION, type_="mount", fields=mnt,
        ))

    # 8. Complete event
    module_count = sum(1 for k in ["services", "ports", "packages", "cron", "processes", "mounts"] if profile[k])
    events.append(format_event(
        timestamp=next_ts(), hostname=hostname, os=os_name,
        run_id=run_id, version=ODIN_VERSION, type_="odin_complete",
        fields={
            "modules_total": "6",
            "modules_success": str(module_count),
            "modules_failed": str(6 - module_count),
            "message": "TA-ODIN enumeration completed",
        },
    ))

    return events


def generate_all(
    scan_date: str = None,
    output_file: str = None,
    hosts: list = None,
) -> list:
    """Generate ODIN scans for all (or specified) host profiles."""
    if scan_date is None:
        scan_date = datetime.utcnow().strftime("%Y-%m-%d")

    profiles = HOST_PROFILES
    if hosts:
        profiles = {h: p for h, p in HOST_PROFILES.items() if h in hosts}

    all_events = []
    for hostname, profile in profiles.items():
        hour = random.randint(1, 5)
        minute = random.randint(0, 59)
        scan_timestamp = f"{scan_date}T{hour:02d}:{minute:02d}:00Z"
        run_id = f"{int(datetime.fromisoformat(scan_timestamp.replace('Z', '+00:00')).timestamp())}-{random.randint(1000, 9999)}"

        events = generate_scan(hostname, profile, scan_timestamp, run_id)
        all_events.extend(events)

    all_events.sort(key=lambda e: e.split()[0])

    if output_file:
        from pathlib import Path
        Path(output_file).parent.mkdir(parents=True, exist_ok=True)
        with open(output_file, "w") as f:
            for event in all_events:
                f.write(event + "\n")

    return all_events


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Generate synthetic ODIN enumeration data")
    parser.add_argument("--output", "-o", default="tools/output/odin_enumeration.log",
                        help="Output file path (default: tools/output/odin_enumeration.log)")
    parser.add_argument("--date", "-d", default=None,
                        help="Scan date in YYYY-MM-DD format (default: today)")
    parser.add_argument("--hosts", nargs="*", default=None,
                        help="Specific hostnames to generate (default: all)")
    parser.add_argument("--list-hosts", action="store_true",
                        help="List available host profiles and exit")
    args = parser.parse_args()

    if args.list_hosts:
        for h in sorted(HOST_PROFILES.keys()):
            print(h)
        raise SystemExit(0)

    events = generate_all(scan_date=args.date, output_file=args.output, hosts=args.hosts)
    print(f"Generated {len(events)} events for {len(set(e.split()[1].split('=')[1] for e in events))} hosts")
    if args.output:
        print(f"Written to: {args.output}")
