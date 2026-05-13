#!/bin/bash
# Read and pretty-print any plist file (binary or XML) from the offline volume.
# Usage: ./ts_plist_inspect.sh <path-to-plist>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="ts_plist_inspect.sh"
source "$SCRIPT_DIR/../lib_log.sh"
log_start "$@"

PLIST="${1:-}"

if [[ -z "$PLIST" ]]; then
    read -r -p "Enter full path to plist: " PLIST
fi

if [[ ! -f "$PLIST" ]]; then
    log_error "File not found: $PLIST"
    log_end 1; exit 1
fi

log_info "Inspecting: $PLIST"
log_section "plist contents"
plutil -convert xml1 -o - "$PLIST" 2>/dev/null | tee -a "$LOG_FILE" \
    || { log_error "plutil failed — file may not be a valid plist."; log_end 1; exit 1; }

log_end 0
