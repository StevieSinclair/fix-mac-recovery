#!/bin/bash
# List all startup/login items and kernel extensions on the offline volume.
# Usage: ./ts_startup_items.sh [volume-root]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="ts_startup_items.sh"
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

list_dir() {
    local label="$1" path="$2"
    log_section "$label"
    if [[ -d "$path" ]]; then
        ls -la "$path" 2>/dev/null | tee -a "$LOG_FILE"
    else
        log_info "(not present)"
    fi
}

list_dir "LaunchDaemons (system)"     "$VOL/Library/LaunchDaemons"
list_dir "LaunchAgents (system)"      "$VOL/Library/LaunchAgents"
list_dir "StartupItems (legacy)"      "$VOL/Library/StartupItems"
list_dir "Login Items DB"             "$VOL/private/var/db/com.apple.backgroundtaskmanagementagent"

log_section "Kernel Extensions (/Library/Extensions)"
find "$VOL/Library/Extensions" -maxdepth 1 -name "*.kext" 2>/dev/null \
    | sort | tee -a "$LOG_FILE" || log_info "(none)"

log_section "Kernel Extensions (/System/Library/Extensions — third-party)"
find "$VOL/System/Library/Extensions" -maxdepth 1 -name "*.kext" 2>/dev/null \
    | sort | tee -a "$LOG_FILE" || log_info "(none)"

log_section "Per-user LaunchAgents"
for home in "$VOL/Users"/*/; do
    udir="$home/Library/LaunchAgents"
    [[ -d "$udir" ]] || continue
    user="$(basename "$home")"
    log_info "  User: $user"
    ls "$udir" 2>/dev/null | while read -r f; do log_info "    $f"; done
done

log_end 0
