#!/bin/bash
# Run from macOS Recovery Terminal (Utilities > Terminal) as root.
# Identifies all APFS containers and volumes — run this first to find your disk.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="01_find_volumes.sh"
# shellcheck source=lib_log.sh
source "$SCRIPT_DIR/lib_log.sh"
log_start "$@"

log_section "Physical Disks"
log_cmd diskutil list

log_section "APFS Containers & Volumes"
log_cmd diskutil apfs list

log_section "Currently Mounted Volumes"
mount | grep -E '^/dev/' | awk '{print $1, "->", $3}' | tee -a "$LOG_FILE"

log_info "Tip: Note the /dev/diskXsY identifier for your encrypted Data or System volume."
log_info "     Pass it to 02_unlock_apfs.sh."
log_end 0
