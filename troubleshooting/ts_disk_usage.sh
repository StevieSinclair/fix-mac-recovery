#!/bin/bash
# Show disk usage breakdown on the mounted volume.
# Usage: ./ts_disk_usage.sh [volume-root]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="ts_disk_usage.sh"
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

log_section "Overall disk usage"
log_cmd df -h "$VOL"

log_section "Top-level directory sizes"
du -hxd 1 "$VOL" 2>/dev/null | sort -hr | tee -a "$LOG_FILE"

log_section "Largest files (top 20)"
find "$VOL" -xdev -type f -size +50M 2>/dev/null \
    | xargs du -h 2>/dev/null | sort -hr | head -20 | tee -a "$LOG_FILE"

log_end 0
