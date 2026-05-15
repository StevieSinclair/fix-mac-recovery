#!/bin/bash
# chroot into a mounted macOS volume from Recovery Terminal.
#
# Why: running tools like softwareupdate, launchctl, installer, or pkgutil
# inside a chroot means they see the full macOS filesystem and frameworks
# rather than the minimal recoveryOS environment — no DYLD hacks needed.
#
# What this script does:
#   1. Detects or prompts for the target volume root (system volume)
#   2. Locates and mounts the matching Data volume under
#      <root>/System/Volumes/Data if not already linked
#   3. Bind-mounts devfs into <root>/dev so device nodes are available
#   4. Drops you into a chroot shell (or runs a single command)
#   5. On exit, cleanly unmounts devfs
#
# Usage:
#   bash 12_chroot.sh [volume-root] [-- command [args...]]
#
# Examples:
#   bash 12_chroot.sh
#   bash 12_chroot.sh "/Volumes/Macintosh HD"
#   bash 12_chroot.sh "/Volumes/Macintosh HD" -- softwareupdate --list
#   bash 12_chroot.sh "/Volumes/Macintosh HD" -- /bin/bash --login

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="12_chroot.sh"
# shellcheck source=lib_log.sh
source "$SCRIPT_DIR/lib_log.sh"
log_start "$@"

# ── Parse arguments ────────────────────────────────────────────────────────────

VOL_ROOT="${1:-}"
shift || true
# Strip leading -- separator if present
if [[ "${1:-}" == "--" ]]; then shift; fi
CHROOT_CMD=("$@")

# ── Pre-flight ─────────────────────────────────────────────────────────────────

log_section "Pre-flight checks"

if [[ "$(id -u)" -ne 0 ]]; then
    log_error "Must be run as root."
    log_end 1; exit 1
fi

# ── Locate the system volume ───────────────────────────────────────────────────

log_section "Locating system volume"

if [[ -z "$VOL_ROOT" ]]; then
    # Prefer MAC_VOL if set by menu option 2
    if [[ -n "${MAC_VOL:-}" && -d "${MAC_VOL}/usr" ]]; then
        VOL_ROOT="$MAC_VOL"
        log_info "Using MAC_VOL: $VOL_ROOT"
        echo "  Using MAC_VOL: $VOL_ROOT"
    else
        # Auto-detect: look for a volume with a recognisable macOS layout
        for candidate in \
            "/Volumes/Macintosh HD" \
            "/Volumes/Macintosh HD - Data" \
            "/Volumes/Data" \
            "/Volumes/Recovery_HD"; do
            if [[ -d "$candidate/usr/bin" && -d "$candidate/System" ]]; then
                VOL_ROOT="$candidate"
                log_info "Auto-detected system volume: $VOL_ROOT"
                echo "  Auto-detected system volume: $VOL_ROOT"
                break
            fi
        done
    fi
fi

if [[ -z "$VOL_ROOT" ]]; then
    echo ""
    echo "  Could not auto-detect a mounted macOS system volume."
    echo "  Available volumes:"
    ls /Volumes/ 2>/dev/null | sed 's/^/    /' || true
    echo ""
    read -r -p "  Enter volume path (e.g. /Volumes/Macintosh HD): " VOL_ROOT
fi

if [[ ! -d "$VOL_ROOT/usr" ]]; then
    log_error "Not a valid macOS volume root: $VOL_ROOT"
    echo "  Expected to find $VOL_ROOT/usr — is the volume unlocked and mounted?"
    log_end 1; exit 1
fi

log_info "System volume root: $VOL_ROOT"
echo ""
echo "  System volume: $VOL_ROOT"

# ── Mount Data volume into the firmlink path ───────────────────────────────────
# On APFS, /System/Volumes/Data is a firmlink target for /Users, /private/var,
# etc. If it is absent the chroot will be missing home dirs and var storage.

log_section "Checking Data volume firmlink"

DATA_LINK="${VOL_ROOT}/System/Volumes/Data"

if [[ -d "$DATA_LINK/private" || -d "$DATA_LINK/Users" ]]; then
    log_info "Data volume already linked at $DATA_LINK"
    echo "  Data volume already linked."
else
    # Try to find the matching Data volume from diskutil
    DATA_VOL=""
    while IFS= read -r line; do
        if echo "$line" | grep -q "Data$\|Macintosh HD - Data"; then
            DATA_VOL=$(echo "$line" | grep -o '/dev/disk[^ ]*' || true)
        fi
    done < <(diskutil apfs list 2>/dev/null || true)

    if [[ -z "$DATA_VOL" ]]; then
        log_warn "Could not auto-detect Data volume. /Users and /private/var may be missing inside chroot."
        echo "  WARNING: Data volume not found — /Users and /private/var will be absent."
    else
        log_info "Mounting Data volume $DATA_VOL at $DATA_LINK"
        echo "  Mounting Data volume $DATA_VOL → $DATA_LINK"
        mkdir -p "$DATA_LINK"
        diskutil mount -mountPoint "$DATA_LINK" "$DATA_VOL" >> "$LOG_FILE" 2>&1 || {
            log_warn "Could not mount Data volume — chroot will continue without it."
            echo "  WARNING: Could not mount Data volume."
        }
    fi
fi

# ── Mount devfs ────────────────────────────────────────────────────────────────
# Many macOS binaries need /dev/null, /dev/random, etc. to function.

log_section "Mounting devfs"

DEV_PATH="${VOL_ROOT}/dev"
mkdir -p "$DEV_PATH"

DEVFS_MOUNTED=0
if mount | grep -q "devfs on ${DEV_PATH}"; then
    log_info "devfs already mounted at $DEV_PATH"
    echo "  devfs already mounted."
    DEVFS_MOUNTED=1
else
    if mount -t devfs devfs "$DEV_PATH" >> "$LOG_FILE" 2>&1; then
        log_info "devfs mounted at $DEV_PATH"
        echo "  devfs mounted at $DEV_PATH"
        DEVFS_MOUNTED=1
    else
        log_warn "Could not mount devfs — some tools may fail inside the chroot."
        echo "  WARNING: devfs mount failed."
    fi
fi

# Unmount devfs on exit (only if we mounted it)
cleanup() {
    if [[ $DEVFS_MOUNTED -eq 1 ]]; then
        echo ""
        echo "  Unmounting devfs..."
        umount "$DEV_PATH" 2>/dev/null && log_info "devfs unmounted." || log_warn "devfs unmount failed — run: umount '$DEV_PATH'"
    fi
}
trap cleanup EXIT

# ── Enter chroot ───────────────────────────────────────────────────────────────

log_section "Entering chroot: $VOL_ROOT"
echo ""

if [[ ${#CHROOT_CMD[@]} -gt 0 ]]; then
    echo "  Running inside chroot: ${CHROOT_CMD[*]}"
    echo ""
    log_info "chroot command: ${CHROOT_CMD[*]}"
    CHROOT_EXIT=0
    chroot "$VOL_ROOT" "${CHROOT_CMD[@]}" 2>&1 | tee -a "$LOG_FILE" || CHROOT_EXIT=$?
    log_info "chroot command exited: $CHROOT_EXIT"
    log_end "$CHROOT_EXIT"
    exit "$CHROOT_EXIT"
else
    echo "  Dropping into interactive chroot shell."
    echo "  Type 'exit' or Ctrl-D to return to Recovery Terminal."
    echo ""
    echo "  Useful commands once inside:"
    echo "    softwareupdate --list"
    echo "    softwareupdate --install --all --verbose"
    echo "    installer -pkg /path/to/update.pkg -target /"
    echo ""
    log_info "Opening interactive chroot shell"
    chroot "$VOL_ROOT" /bin/bash --login || true
    log_info "Interactive chroot shell exited."
fi

log_end 0
