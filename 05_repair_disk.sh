#!/bin/bash
# Run fsck_apfs on an unmounted APFS volume to check and repair filesystem errors.
# The volume must be UNMOUNTED for fsck. Unlock first with 02_unlock_apfs.sh,
# then unmount before running this script, or pass the raw device directly.
# Usage:  ./05_repair_disk.sh [/dev/diskXsY] [--repair]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="05_repair_disk.sh"
# shellcheck source=lib_log.sh
source "$SCRIPT_DIR/lib_log.sh"
log_start "$@"

DEVICE="${1:-}"

if [[ -z "$DEVICE" ]]; then
    log_info "Scanning for APFS Data volumes..."
    DEVICE=$(diskutil apfs list 2>/dev/null \
        | grep -A 3 "Data" \
        | grep "APFS Volume Disk" \
        | awk '{print "/dev/"$NF}' | head -1 || true)

    if [[ -z "$DEVICE" ]]; then
        log_error "No APFS Data volume auto-detected. Pass /dev/diskXsY as argument."
        log_end 1; exit 1
    fi
    log_info "Auto-detected device: $DEVICE"
fi

log_info "Target device: $DEVICE"

# ── Unmount if mounted ─────────────────────────────────────────────────────────
CURRENT_MOUNT=$(diskutil info "$DEVICE" 2>/dev/null | awk '/Mount Point/{print $NF}' || true)
if [[ -n "$CURRENT_MOUNT" && "$CURRENT_MOUNT" != "(not" ]]; then
    log_info "Volume is mounted at $CURRENT_MOUNT. Unmounting for fsck..."
    diskutil unmount "$DEVICE" >> "$LOG_FILE" 2>&1 || {
        log_error "Could not unmount $DEVICE. Close any open files on the volume."
        log_end 1; exit 1
    }
    log_info "Unmounted successfully."
fi

# ── Run fsck ───────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--repair" || "${2:-}" == "--repair" ]]; then
    log_info "Mode: REPAIR (writing fixes)"
    echo ""
    echo "Running fsck_apfs -y $DEVICE (this may take several minutes)..."
    fsck_apfs -y "$DEVICE" 2>&1 | tee -a "$LOG_FILE"
else
    log_info "Mode: CHECK ONLY (pass --repair to write fixes)"
    echo ""
    echo "Running fsck_apfs -n $DEVICE (this may take several minutes)..."
    fsck_apfs -n "$DEVICE" 2>&1 | tee -a "$LOG_FILE"
fi

FSCK_EXIT="${PIPESTATUS[0]}"
log_info "fsck_apfs finished. Exit code: $FSCK_EXIT"
log_end "$FSCK_EXIT"
exit "$FSCK_EXIT"
