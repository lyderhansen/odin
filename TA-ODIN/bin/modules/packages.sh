#!/bin/bash
#
# TA-ODIN Module: Package Enumeration
# Enumerates all installed packages using the detected package manager.
# Supports dpkg (Debian/Ubuntu), rpm (RHEL/CentOS/SUSE), apk (Alpine), pacman (Arch).
#
# Output fields:
#   event_type=package package_name= package_version= package_arch= package_manager=
#

# Use orchestrator functions if available, otherwise define standalone versions
if ! declare -f emit &>/dev/null; then
    ODIN_HOSTNAME="${ODIN_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}"
    ODIN_OS="${ODIN_OS:-linux}"
    ODIN_RUN_ID="${ODIN_RUN_ID:-standalone-$$}"
    ODIN_VERSION="${ODIN_VERSION:-2.0.0}"
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
    emit() { echo "timestamp=$(get_timestamp) hostname=$ODIN_HOSTNAME os=$ODIN_OS run_id=$ODIN_RUN_ID odin_version=$ODIN_VERSION $*"; }
fi

# Detect package manager
# Check /etc/os-release first, then fall back to binary detection
detect_package_manager() {
    if [[ -f /etc/os-release ]]; then
        local id_like=""
        local id=""
        id=$(grep -oP '^ID=\K.*' /etc/os-release 2>/dev/null | tr -d '"')
        id_like=$(grep -oP '^ID_LIKE=\K.*' /etc/os-release 2>/dev/null | tr -d '"')

        case "$id" in
            alpine) echo "apk"; return ;;
            arch|manjaro) echo "pacman"; return ;;
        esac

        case "$id_like" in
            *debian*|*ubuntu*) echo "dpkg"; return ;;
            *rhel*|*fedora*|*centos*|*suse*) echo "rpm"; return ;;
        esac

        # ID itself for common distros
        case "$id" in
            debian|ubuntu|linuxmint|pop|kali) echo "dpkg"; return ;;
            rhel|centos|fedora|rocky|alma|ol|sles|opensuse*) echo "rpm"; return ;;
        esac
    fi

    # Fallback to binary detection
    command -v dpkg-query &>/dev/null && echo "dpkg" && return
    command -v rpm &>/dev/null && echo "rpm" && return
    command -v apk &>/dev/null && echo "apk" && return
    command -v pacman &>/dev/null && echo "pacman" && return

    echo "unknown"
}

pkg_manager=$(detect_package_manager)

case "$pkg_manager" in
    dpkg)
        # dpkg-query: Name Version Architecture
        dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' 2>/dev/null | while IFS=$'\t' read -r name version arch; do
            [[ -z "$name" ]] && continue
            emit "event_type=package package_name=$name package_version=$version package_arch=$arch package_manager=dpkg"
        done
        ;;
    rpm)
        # rpm: Name Version Architecture
        rpm -qa --queryformat '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\n' 2>/dev/null | while IFS=$'\t' read -r name version arch; do
            [[ -z "$name" ]] && continue
            emit "event_type=package package_name=$name package_version=$version package_arch=$arch package_manager=rpm"
        done
        ;;
    apk)
        # apk info: name-version format
        apk info -v 2>/dev/null | while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            # apk format: name-version  (last hyphen separates name from version)
            name="${line%-*}"
            version="${line##*-}"
            emit "event_type=package package_name=$name package_version=$version package_manager=apk"
        done
        ;;
    pacman)
        # pacman: Name Version
        pacman -Q 2>/dev/null | while read -r name version; do
            [[ -z "$name" ]] && continue
            emit "event_type=package package_name=$name package_version=$version package_manager=pacman"
        done
        ;;
    *)
        emit "event_type=package_error message=\"No supported package manager detected\""
        ;;
esac

exit 0
