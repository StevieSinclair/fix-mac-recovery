#!/bin/bash
# Unlock and mount a FileVault-encrypted APFS volume from Recovery Terminal.
# Usage:  ./02_unlock_apfs.sh [/dev/diskXsY] [mount-point]
# If no arguments are given the script auto-detects the Data volume and prompts
# for the passphrase interactively (passphrase never appears in shell history).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="02_unlock_apfs.sh"
# shellcheck source=lib_log.sh
source "$SCRIPT_DIR/lib_log.sh"
log_start "$@"

DEVICE="${1:-}"
MOUNTPOINT="${2:-/Volumes/Recovery_HD}"

# ── Auto-detect if no device given ────────────────────────────────────────────
if [[ -z "$DEVICE" ]]; then
    log_info "No device specified. Scanning for encrypted APFS volumes..."
    LOCKED=$(diskutil apfs list 2>/dev/null \
        | grep -B 20 "Locked" \
        | grep "APFS Volume Disk" \
        | awk '{print $NF}' | head -1 || true)

    if [[ -z "$LOCKED" ]]; then
        log_error "No locked APFS volume auto-detected."
        log_info "Run 01_find_volumes.sh and pass the device manually."
        log_end 1; exit 1
    fi
    DEVICE="/dev/$LOCKED"
    log_info "Found locked volume: $DEVICE"
fi

log_info "Target device : $DEVICE"
log_info "Mount point   : $MOUNTPOINT"

# ── Passphrase ─────────────────────────────────────────────────────────────────
read -r -s -p "Enter FileVault passphrase (input hidden): " PASSPHRASE
echo ""

if [[ -z "$PASSPHRASE" ]]; then
    log_error "Passphrase cannot be empty."
    log_end 1; exit 1
fi

# ── Unlock ─────────────────────────────────────────────────────────────────────
log_info "Unlocking $DEVICE ..."
# Passphrase passed inline — not logged to avoid leaking it
diskutil apfs unlockVolume "$DEVICE" -passphrase "$PASSPHRASE" \
    >> "$LOG_FILE" 2>&1 && echo "Unlock succeeded." || {
        unset PASSPHRASE
        log_error "diskutil apfs unlockVolume failed — check passphrase and device."
        log_end 1; exit 1
    }
unset PASSPHRASE

log_section "Mounted APFS volumes after unlock"
log_cmd diskutil apfs list | grep -E "(APFS Volume Disk|Mount Point)"

# ── Confirm mount point ────────────────────────────────────────────────────────
ACTUAL_MOUNT=$(diskutil info "$DEVICE" 2>/dev/null | awk '/Mount Point/{print $NF}' || true)

if [[ -n "$ACTUAL_MOUNT" ]]; then
    log_info "Volume mounted at: $ACTUAL_MOUNT"
    log_info "Export this for downstream scripts:"
    log_info "  export MAC_VOL='$ACTUAL_MOUNT'"
else
    log_warn "Could not confirm mount point. Check 'mount' output."
fi

log_end 0
