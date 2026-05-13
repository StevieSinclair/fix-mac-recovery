#!/bin/bash
# Inspect Time Machine configuration and backup state from the offline volume.
# Usage: ./ts_time_machine.sh [volume-root]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="ts_time_machine.sh"
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

show_plist() {
    local label="$1" path="$2"
    if [[ -f "$path" ]]; then
        log_section "$label"
        plutil -convert xml1 -o - "$path" 2>/dev/null | tee -a "$LOG_FILE" \
            || log_warn "Could not parse $path"
    else
        log_info "Not found: $path"
    fi
}

show_plist "Time Machine preferences" \
    "$VOL/Library/Preferences/com.apple.TimeMachine.plist"

log_section "Local Time Machine snapshots"
find "$VOL/.MobileBackups" -maxdepth 3 -type d 2>/dev/null | head -20 | tee -a "$LOG_FILE" \
    || log_info "No local snapshots found (.MobileBackups)."

log_section "APFS local snapshots"
log_cmd diskutil apfs listSnapshots "$VOL" 2>/dev/null || log_info "Could not list APFS snapshots."

log_section "Backup exclusions"
plutil -convert xml1 -o - \
    "$VOL/Library/Preferences/com.apple.TimeMachine.plist" 2>/dev/null \
    | awk '/<key>SkipPaths<\/key>/,/<\/array>/' | tee -a "$LOG_FILE" \
    || log_info "Could not read exclusion list."

log_section "Time Machine log (last 40 lines)"
TM_LOG="$VOL/private/var/log/com.apple.backupd.log"
if [[ -f "$TM_LOG" ]]; then
    tail -40 "$TM_LOG" | tee -a "$LOG_FILE"
else
    log_info "Time Machine log not found at $TM_LOG"
fi

log_end 0
