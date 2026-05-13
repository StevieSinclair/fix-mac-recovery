#!/bin/bash
# Dump user account info from the offline DirectoryService database.
# Usage: ./ts_user_accounts.sh [volume-root]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="ts_user_accounts.sh"
source "$SCRIPT_DIR/../lib_log.sh"
log_start "$@"

VOL="${1:-${MAC_VOL:-}}"
if [[ -z "$VOL" ]]; then
    for c in "/Volumes/Macintosh HD" "/Volumes/Data" "/Volumes/Recovery_HD"; do
        [[ -d "$c" ]] && VOL="$c" && break
    done
fi
[[ -z "$VOL" || ! -d "$VOL" ]] && { log_error "Volume not found."; log_end 1; exit 1; }

log_info "Volume: $VOL"

DSLOCAL="$VOL/private/var/db/dslocal/nodes/Default"
if [[ ! -d "$DSLOCAL" ]]; then
    log_error "DirectoryService database not found at $DSLOCAL"
    log_end 1; exit 1
fi

log_section "Local user accounts"
dscl -f "$DSLOCAL" localonly -list /Local/Default/Users 2>/dev/null | while read -r user; do
    uid=$(dscl -f "$DSLOCAL" localonly -read "/Local/Default/Users/$user" UniqueID 2>/dev/null \
        | awk '/UniqueID:/{print $2}')
    shell=$(dscl -f "$DSLOCAL" localonly -read "/Local/Default/Users/$user" UserShell 2>/dev/null \
        | awk '/UserShell:/{print $2}')
    home=$(dscl -f "$DSLOCAL" localonly -read "/Local/Default/Users/$user" NFSHomeDirectory 2>/dev/null \
        | awk '/NFSHomeDirectory:/{print $2}')
    line="  uid=$uid  user=$user  shell=$shell  home=$home"
    log_info "$line"
done

log_section "Local groups"
dscl -f "$DSLOCAL" localonly -list /Local/Default/Groups 2>/dev/null \
    | tee -a "$LOG_FILE"

log_section "Admin group members"
dscl -f "$DSLOCAL" localonly -read /Local/Default/Groups/admin GroupMembership 2>/dev/null \
    | tee -a "$LOG_FILE"

log_end 0
