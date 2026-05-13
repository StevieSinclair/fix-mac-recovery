#!/bin/bash
# Fix common permission issues on user home directories and critical paths
# after mounting the volume in Recovery.
# Usage:  ./08_fix_permissions.sh [volume-root] [username]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="08_fix_permissions.sh"
# shellcheck source=lib_log.sh
source "$SCRIPT_DIR/lib_log.sh"
log_start "$@"

VOL="${1:-${MAC_VOL:-}}"
USERNAME="${2:-}"

if [[ -z "$VOL" ]]; then
    for candidate in "/Volumes/Macintosh HD" "/Volumes/Data" "/Volumes/Recovery_HD"; do
        [[ -d "$candidate" ]] && VOL="$candidate" && break
    done
fi

if [[ -z "$VOL" || ! -d "$VOL" ]]; then
    log_error "Volume not found. Pass it as the first argument or set MAC_VOL."
    log_end 1; exit 1
fi

log_info "Volume root: $VOL"

resolve_uid() {
    local user="$1"
    dscl -f "$VOL/private/var/db/dslocal/nodes/Default" localonly \
        -read "/Local/Default/Users/$user" UniqueID 2>/dev/null \
        | awk '/UniqueID:/{print $2}' | head -1
}

if [[ -z "$USERNAME" ]]; then
    log_section "Available user home directories"
    ls "$VOL/Users/" | grep -v -E '^\.|Shared' | nl
    read -r -p "Enter username (or leave blank to skip home-dir fixes): " USERNAME
    log_info "Selected username: ${USERNAME:-(none)}"
fi

if [[ -n "$USERNAME" ]]; then
    USERHOME="$VOL/Users/$USERNAME"
    if [[ ! -d "$USERHOME" ]]; then
        log_error "$USERHOME does not exist."
        log_end 1; exit 1
    fi

    UID_NUM=$(resolve_uid "$USERNAME")
    if [[ -z "$UID_NUM" ]]; then
        log_warn "Could not resolve UID for $USERNAME from offline DB."
        read -r -p "Enter UID manually (e.g. 501): " UID_NUM
        log_info "Manual UID: $UID_NUM"
    else
        log_info "Resolved UID for $USERNAME: $UID_NUM"
    fi

    GID_NUM=20  # staff group

    log_info "Fixing home directory ownership: $USERHOME (uid=$UID_NUM gid=$GID_NUM)"
    chown -R "${UID_NUM}:${GID_NUM}" "$USERHOME" >> "$LOG_FILE" 2>&1
    log_info "chown -R complete."

    log_info "Setting home directory permissions (755)..."
    chmod 755 "$USERHOME"

    if [[ -d "$USERHOME/Library" ]]; then
        log_info "Fixing Library permissions (700)..."
        chmod 700 "$USERHOME/Library"
    fi

    log_info "Home directory permissions corrected."
fi

log_section "Fixing /tmp and /var/folders"
TMPDIR="$VOL/private/tmp"
if [[ -d "$TMPDIR" ]]; then
    chmod 1777 "$TMPDIR"
    log_info "/private/tmp -> 1777"
fi

log_info "Permission fixes complete."
log_end 0
