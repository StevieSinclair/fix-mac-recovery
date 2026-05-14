#!/bin/bash
# Attempt to install the latest macOS software updates from Recovery Terminal.
# Uses softwareupdate(8) which works in recoveryOS; also tries triggering the
# MobileAsset seeding path used by the OS installer so the machine can stage
# and apply updates without booting the full installer environment.
#
# Why this exists: the normal Reinstall macOS flow in recoveryOS sometimes
# stalls or loops back to Recovery because the installer cannot find/verify its
# update catalog.  Running softwareupdate directly from the terminal bypasses
# that UI path and can succeed where the GUI cannot.
#
# Usage:  bash 10_install_updates.sh [--list-only]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="10_install_updates.sh"
# shellcheck source=lib_log.sh
source "$SCRIPT_DIR/lib_log.sh"
log_start "$@"

LIST_ONLY=0
if [[ "${1:-}" == "--list-only" ]]; then
    LIST_ONLY=1
fi

# ── Pre-flight ─────────────────────────────────────────────────────────────────

log_section "Pre-flight checks"

if [[ "$(id -u)" -ne 0 ]]; then
    log_error "Must be run as root. Use 'sudo bash $0' or run from Recovery Terminal."
    log_end 1; exit 1
fi

SW="$(command -v softwareupdate 2>/dev/null || true)"
if [[ -z "$SW" ]]; then
    log_error "softwareupdate not found — this script must run inside macOS or recoveryOS."
    log_end 1; exit 1
fi
log_info "softwareupdate found at: $SW"

# ── Network check ─────────────────────────────────────────────────────────────

log_section "Network connectivity"

PING_OK=0
if ping -c 2 -W 3 swscan.apple.com >/dev/null 2>&1; then
    PING_OK=1
    log_info "Network reachable (swscan.apple.com responded)."
else
    log_warn "Cannot reach swscan.apple.com. Check Wi-Fi / Ethernet."
    echo ""
    echo "  Network appears down. Available interfaces:"
    ifconfig | grep -E "^[a-z]|inet " | grep -v "127.0.0.1" || true
    echo ""
    echo "  To join Wi-Fi from Recovery Terminal run:"
    echo "    networksetup -setairportnetwork en0 <SSID> <password>"
    echo ""
    read -r -p "Press Enter to continue anyway (update fetch will likely fail)..."
fi

# ── List available updates ─────────────────────────────────────────────────────

log_section "Checking for available updates"

echo ""
echo "Fetching update catalog from Apple (this may take a minute)..."
echo ""

AVAILABLE_OUTPUT=""
AVAILABLE_OUTPUT="$(softwareupdate --list 2>&1)" || true
echo "$AVAILABLE_OUTPUT" | tee -a "$LOG_FILE"

if echo "$AVAILABLE_OUTPUT" | grep -qi "no new software available"; then
    log_info "Apple reports: no new software available."
    if [[ $PING_OK -eq 0 ]]; then
        log_warn "Network was unreachable — result may be inaccurate."
        echo ""
        echo "  (No updates listed, but network was down — result may be wrong.)"
    else
        echo ""
        echo "  System appears up to date."
    fi
    log_end 0; exit 0
fi

if [[ $LIST_ONLY -eq 1 ]]; then
    log_info "--list-only specified. Skipping installation."
    log_end 0; exit 0
fi

# ── Install updates ────────────────────────────────────────────────────────────

log_section "Installing updates"

echo ""
echo "  Options:"
echo "    a) Install ALL available updates (recommended — includes firmware/OS)"
echo "    m) Install macOS update only (--os-only)"
echo "    s) Skip install (return to menu)"
echo ""
read -r -p "Choice [a/m/s]: " INSTALL_CHOICE

case "$INSTALL_CHOICE" in
    s|S)
        log_info "User skipped installation."
        log_end 0; exit 0
        ;;
    m|M)
        INSTALL_FLAGS="--install --os-only --verbose"
        log_info "Mode: macOS update only"
        ;;
    *)
        INSTALL_FLAGS="--install --all --verbose"
        log_info "Mode: install all updates"
        ;;
esac

echo ""
echo "Starting: softwareupdate $INSTALL_FLAGS"
echo "This can take 10–30 minutes.  Do NOT power off the machine."
echo ""

# softwareupdate exits non-zero if it wants to restart — capture that cleanly.
UPDATE_EXIT=0
# shellcheck disable=SC2086
softwareupdate $INSTALL_FLAGS 2>&1 | tee -a "$LOG_FILE" || UPDATE_EXIT=$?

log_info "softwareupdate finished with exit code: $UPDATE_EXIT"

# ── Result handling ────────────────────────────────────────────────────────────

log_section "Result"

if [[ $UPDATE_EXIT -eq 0 ]]; then
    echo ""
    echo "  Updates applied successfully."
    echo ""
    echo "  If the system still loops back to Recovery after reboot, try:"
    echo "    1) Option 5 (disk repair) — run fsck to fix filesystem errors"
    echo "    2) Option 6 (SIP/NVRAM) — reset NVRAM then reboot"
    echo "    3) Reset NVRAM manually: hold Cmd+Opt+P+R at startup"
    echo "    4) If on Apple Silicon: hold power → Options → select startup disk"
    echo ""
elif [[ $UPDATE_EXIT -eq 22 ]]; then
    # Exit 22 = restart required
    log_info "softwareupdate exit 22 = restart required."
    echo ""
    echo "  Updates staged.  A restart is required to complete installation."
    echo "  Run:  reboot"
    echo ""
else
    log_warn "softwareupdate exited $UPDATE_EXIT — see log for details."
    echo ""
    echo "  softwareupdate returned exit code $UPDATE_EXIT."
    echo ""
    echo "  Common causes:"
    echo "    - Network dropped during download"
    echo "    - Insufficient disk space  (check with: df -h /)"
    echo "    - Catalog authentication error (NVRAM reset may help — option 6)"
    echo "    - SIP preventing changes   (check status with option 6)"
    echo ""
    echo "  Full log: $LOG_FILE"
    echo ""
fi

log_end "$UPDATE_EXIT"
exit "$UPDATE_EXIT"
