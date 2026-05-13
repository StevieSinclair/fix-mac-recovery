#!/bin/bash
# Inspect system logs from the offline volume.
# Usage: ./ts_logs.sh [volume-root] [lines]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="ts_logs.sh"
source "$SCRIPT_DIR/../lib_log.sh"
log_start "$@"

VOL="${1:-${MAC_VOL:-}}"
LINES="${2:-80}"

if [[ -z "$VOL" ]]; then
    for c in "/Volumes/Macintosh HD" "/Volumes/Data" "/Volumes/Recovery_HD"; do
        [[ -d "$c" ]] && VOL="$c" && break
    done
fi
[[ -z "$VOL" || ! -d "$VOL" ]] && { log_error "Volume not found."; log_end 1; exit 1; }

log_info "Volume: $VOL  |  Lines per file: $LINES"

show_tail() {
    local label="$1" path="$2"
    if [[ -f "$path" ]]; then
        log_section "$label"
        tail -n "$LINES" "$path" | tee -a "$LOG_FILE"
    else
        log_info "Not found: $path"
    fi
}

show_tail "system.log"        "$VOL/private/var/log/system.log"
show_tail "install.log"       "$VOL/private/var/log/install.log"
show_tail "kernel.log"        "$VOL/private/var/log/kernel.log"
show_tail "fsck_hfs.log"      "$VOL/private/var/log/fsck_hfs.log"

log_section "Crash reports (last 10)"
CRASH_DIR="$VOL/Library/Logs/DiagnosticReports"
if [[ -d "$CRASH_DIR" ]]; then
    ls -t "$CRASH_DIR"/*.crash 2>/dev/null | head -10 | while read -r f; do
        log_info "  $f"
        head -40 "$f" | tee -a "$LOG_FILE"
        echo "---"
    done
else
    log_info "No crash reports directory found."
fi

log_section "Panic logs"
PANIC_DIR="$VOL/Library/Logs/DiagnosticReports"
ls "$PANIC_DIR"/*.panic 2>/dev/null | head -5 | while read -r f; do
    log_info "  $f"
    cat "$f" | tee -a "$LOG_FILE"
    echo "---"
done || log_info "No panic logs found."

log_end 0
