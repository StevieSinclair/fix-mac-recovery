#!/bin/bash
# Broad filesystem health check: permissions, broken symlinks, missing critical paths.
# Usage: ./ts_filesystem_check.sh [volume-root]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="ts_filesystem_check.sh"
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

log_section "Critical path existence"
CRITICAL=(
    private/etc/passwd
    private/etc/hosts
    private/var/db/dslocal/nodes/Default
    usr/bin
    usr/sbin
    bin
    sbin
    System/Library/CoreServices
)
for p in "${CRITICAL[@]}"; do
    full="$VOL/$p"
    if [[ -e "$full" ]]; then
        log_info "  [ok]      $p"
    else
        log_warn "  [MISSING] $p"
    fi
done

log_section "Broken symlinks (top-level dirs, may take a moment)"
find "$VOL/usr" "$VOL/bin" "$VOL/sbin" "$VOL/private/etc" \
    -maxdepth 3 -type l ! -exec test -e {} \; -print 2>/dev/null \
    | tee -a "$LOG_FILE" || log_info "(none found)"

log_section "World-writable files outside /tmp (security check)"
find "$VOL" -xdev -not -path "$VOL/private/tmp/*" \
    -perm -0002 -type f 2>/dev/null | head -30 | tee -a "$LOG_FILE" \
    || log_info "(none found)"

log_section "SUID/SGID binaries outside /usr/bin /usr/sbin /bin /sbin"
find "$VOL" -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null \
    | grep -v -E "^$VOL/(usr/(bin|sbin)|bin|sbin)/" \
    | head -30 | tee -a "$LOG_FILE" || log_info "(none found)"

log_section "Filesystem mount info"
log_cmd df -hT "$VOL" 2>/dev/null || log_cmd df -h "$VOL"

log_end 0
