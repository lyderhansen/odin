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
        id=$(sed -n 's/^ID=//p' /etc/os-release 2>/dev/null | tr -d '"')
        id_like=$(sed -n 's/^ID_LIKE=//p' /etc/os-release 2>/dev/null | tr -d '"')

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
emitted=0

case "$pkg_manager" in
    dpkg)
        # dpkg-query: Name Version Architecture
        while IFS=$'\t' read -r name version arch; do
            [[ -z "$name" ]] && continue
            emit "event_type=package package_name=$name package_version=$version package_arch=$arch package_manager=dpkg"
            emitted=1
        done < <(dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' 2>/dev/null)
        ;;
    rpm)
        # rpm: Name Version Architecture
        while IFS=$'\t' read -r name version arch; do
            [[ -z "$name" ]] && continue
            emit "event_type=package package_name=$name package_version=$version package_arch=$arch package_manager=rpm"
            emitted=1
        done < <(rpm -qa --queryformat '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\n' 2>/dev/null)
        ;;
    apk)
        # apk info -v output: "name-version" where version starts at the last segment matching a digit
        # e.g. "perl-test-warn-0.32-r0" -> name=perl-test-warn version=0.32-r0
        # Use apk list with --installed for cleaner output if available, otherwise parse -v
        if apk list --installed >/dev/null 2>&1; then
            # apk list output: "name-version description" with name highlighted
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                # Format: "name-version {arch} {repo} [installed]" or similar
                # Extract first field and split name/version
                pkg_field="${line%% *}"
                # Version starts at first hyphen followed by a digit
                name=$(echo "$pkg_field" | sed 's/-[0-9].*//')
                version=$(echo "$pkg_field" | sed 's/^[^0-9]*-\([0-9]\)/\1/' | sed 's/^[^-]*-//' )
                version="${pkg_field#"$name"-}"
                [[ -z "$name" ]] && continue
                emit "event_type=package package_name=$name package_version=$version package_manager=apk"
                emitted=1
            done < <(apk list --installed 2>/dev/null)
        else
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                # Split at first hyphen followed by a digit: name-VERSION
                name=$(echo "$line" | sed 's/-[0-9].*//')
                version="${line#"$name"-}"
                [[ -z "$name" ]] && continue
                emit "event_type=package package_name=$name package_version=$version package_manager=apk"
                emitted=1
            done < <(apk info -v 2>/dev/null)
        fi
        ;;
    pacman)
        # pacman: Name Version
        while read -r name version; do
            [[ -z "$name" ]] && continue
            emit "event_type=package package_name=$name package_version=$version package_manager=pacman"
            emitted=1
        done < <(pacman -Q 2>/dev/null)
        ;;
    *)
        emit "event_type=none_found module=packages message=\"No supported package manager detected\""
        emitted=1
        ;;
esac

# Emit none_found if package manager was detected but returned no packages
if [[ $emitted -eq 0 ]]; then
    emit "event_type=none_found module=packages message=\"No installed packages found (package_manager=$pkg_manager)\""
fi

exit 0
