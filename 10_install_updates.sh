#!/bin/bash
# Attempt to install the latest macOS software updates from Recovery Terminal.
#
# Strategy (tried in order):
#   1. softwareupdate(8) — works when booted into full macOS, and on some
#      recoveryOS builds where /usr/sbin is present.
#   2. startosinstall — uses a downloaded "Install macOS X.app" to trigger
#      a clean OS install/upgrade.  Works from recoveryOS even when
#      softwareupdate is absent.
#
# Why this exists: the normal Reinstall macOS flow in recoveryOS sometimes
# stalls or loops back to Recovery because the installer cannot find/verify
# its update catalog.  Running these tools directly from a terminal bypasses
# that GUI path and can succeed where the GUI cannot.
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

# ── Locate softwareupdate ──────────────────────────────────────────────────────

log_section "Locating softwareupdate"

# Auto-detect a mounted macOS volume if MAC_VOL is not already set
if [[ -z "${MAC_VOL:-}" ]]; then
    for vol_candidate in \
        "/Volumes/Macintosh HD" \
        "/Volumes/Macintosh HD - Data" \
        "/Volumes/Data"; do
        if [[ -d "$vol_candidate/usr/sbin" ]]; then
            MAC_VOL="$vol_candidate"
            log_info "Auto-detected mounted volume: $MAC_VOL"
            echo "  Auto-detected mounted volume: $MAC_VOL"
            break
        fi
    done
fi

# If still not found, prompt to mount
if [[ -z "${MAC_VOL:-}" ]]; then
    echo ""
    echo "  No mounted macOS volume detected."
    echo "  Run option 1 (find volumes) and option 2 (unlock APFS) first,"
    echo "  or enter the volume path manually."
    read -r -p "  Volume path (e.g. /Volumes/Macintosh HD) or Enter to skip: " MAC_VOL_INPUT
    if [[ -n "$MAC_VOL_INPUT" && -d "$MAC_VOL_INPUT" ]]; then
        MAC_VOL="$MAC_VOL_INPUT"
        log_info "User-supplied volume: $MAC_VOL"
    fi
fi

SW=""
# Build candidate list: recoveryOS paths first, then the mounted volume
CANDIDATES=(
    /usr/sbin/softwareupdate
    /sbin/softwareupdate
)
if [[ -n "${MAC_VOL:-}" ]]; then
    CANDIDATES+=( "${MAC_VOL}/usr/sbin/softwareupdate" )
fi
# Also check $PATH
CANDIDATES+=( "$(command -v softwareupdate 2>/dev/null || true)" )

for candidate in "${CANDIDATES[@]}"; do
    if [[ -x "$candidate" ]]; then
        SW="$candidate"
        log_info "softwareupdate found at: $SW"
        echo "  softwareupdate found at: $SW"
        break
    fi
done

if [[ -z "$SW" ]]; then
    log_warn "softwareupdate not found in recoveryOS or on mounted volume."
    echo ""
    echo "  softwareupdate is only present in full macOS, not in all recoveryOS builds."
    echo "  Falling through to startosinstall method."
else
    # If the binary came from the mounted volume it will fail with
    # "library not loaded: OSUpdate" because dyld can't find the frameworks.
    # Test-run it and if that error appears, set DYLD paths and retry.
    SYS_VOL="/Volumes/Macintosh HD"
    TEST_OUT="$("$SW" --list 2>&1 | head -5)" || true
    if echo "$TEST_OUT" | grep -q "Library not loaded"; then
        log_warn "softwareupdate: library not loaded — setting DYLD paths from $SYS_VOL"
        echo ""
        echo "  Library not loaded error detected. Setting DYLD paths from $SYS_VOL..."
        export DYLD_FRAMEWORK_PATH="${SYS_VOL}/System/Library/Frameworks:${SYS_VOL}/System/Library/PrivateFrameworks"
        export DYLD_LIBRARY_PATH="${SYS_VOL}/usr/lib"
        log_info "DYLD_FRAMEWORK_PATH=$DYLD_FRAMEWORK_PATH"
        log_info "DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH"
        # Verify the fix worked
        if ! "$SW" --list >/dev/null 2>&1; then
            log_warn "DYLD fix did not resolve the error — falling through to startosinstall."
            echo "  DYLD fix failed. Falling through to startosinstall."
            SW=""
        else
            echo "  DYLD fix worked. softwareupdate is usable."
            log_info "DYLD fix successful."
        fi
    fi
fi

# ── softwareupdate path ────────────────────────────────────────────────────────

if [[ -n "$SW" ]]; then

    log_section "Checking for available updates"
    echo ""
    echo "Fetching update catalog from Apple (this may take a minute)..."
    echo ""

    AVAILABLE_OUTPUT=""
    AVAILABLE_OUTPUT="$("$SW" --list 2>&1)" || true
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
    elif [[ $LIST_ONLY -eq 0 ]]; then

        log_section "Installing updates"
        echo ""
        echo "  Options:"
        echo "    a) Install ALL available updates (recommended)"
        echo "    m) Install macOS update only (--os-only)"
        echo "    s) Skip — use startosinstall instead"
        echo ""
        read -r -p "Choice [a/m/s]: " INSTALL_CHOICE

        case "$INSTALL_CHOICE" in
            s|S)
                log_info "User chose to skip softwareupdate."
                SW=""   # fall through to startosinstall below
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

        if [[ -n "$SW" ]]; then
            echo ""
            echo "Starting: $SW $INSTALL_FLAGS"
            echo "This can take 10–30 minutes.  Do NOT power off the machine."
            echo ""

            UPDATE_EXIT=0
            # shellcheck disable=SC2086
            "$SW" $INSTALL_FLAGS 2>&1 | tee -a "$LOG_FILE" || UPDATE_EXIT=$?
            log_info "softwareupdate finished with exit code: $UPDATE_EXIT"

            log_section "Result"
            if [[ $UPDATE_EXIT -eq 0 ]]; then
                echo "  Updates applied successfully."
                echo ""
                echo "  If the system still loops back to Recovery after reboot, try:"
                echo "    1) Option 5 (disk repair) — run fsck to fix filesystem errors"
                echo "    2) Option 6 (SIP/NVRAM) — reset NVRAM then reboot"
                echo "    3) Reset NVRAM: hold Cmd+Opt+P+R at startup"
                echo "    4) Apple Silicon: hold power → Options → select startup disk"
            elif [[ $UPDATE_EXIT -eq 22 ]]; then
                log_info "softwareupdate exit 22 = restart required."
                echo "  Updates staged. A restart is required to complete installation."
                echo "  Run:  reboot"
            else
                log_warn "softwareupdate exited $UPDATE_EXIT — see log for details."
                echo "  softwareupdate returned exit code $UPDATE_EXIT."
                echo ""
                echo "  Common causes:"
                echo "    - Network dropped during download"
                echo "    - Insufficient disk space  (check: df -h /)"
                echo "    - Catalog auth error (NVRAM reset may help — option 6)"
                echo "    - SIP preventing changes   (check — option 6)"
                echo ""
                echo "  Full log: $LOG_FILE"
            fi

            log_end "$UPDATE_EXIT"
            exit "$UPDATE_EXIT"
        fi
    else
        log_info "--list-only specified. Skipping installation."
        log_end 0; exit 0
    fi
fi

# ── startosinstall fallback ────────────────────────────────────────────────────

log_section "startosinstall (installer app method)"

# Find any downloaded Install macOS app
INSTALLER_APP=""
while IFS= read -r -d '' app; do
    if [[ -x "$app/Contents/Resources/startosinstall" ]]; then
        INSTALLER_APP="$app"
        break
    fi
done < <(find /Applications /Volumes -maxdepth 3 -name "Install macOS*.app" -print0 2>/dev/null)

if [[ -z "$INSTALLER_APP" ]]; then
    echo ""
    echo "  No 'Install macOS X.app' found."
    echo ""
    echo "  To use startosinstall you first need to download the full macOS installer."
    echo "  Use menu option  d → 1  (Download & Verify → Fetch full macOS installer)."
    echo ""
    echo "  Once downloaded, re-run this option."
    log_warn "No installer app found for startosinstall."
    log_end 1; exit 1
fi

log_info "Found installer app: $INSTALLER_APP"
echo ""
echo "  Found: $INSTALLER_APP"
echo ""

STARTOSINSTALL="$INSTALLER_APP/Contents/Resources/startosinstall"

echo "  Options:"
echo "    a) Upgrade/reinstall macOS (keeps user data)"
echo "    e) Erase and install (wipes the target volume — use with caution)"
echo "    s) Skip"
echo ""
read -r -p "Choice [a/e/s]: " SI_CHOICE

case "$SI_CHOICE" in
    s|S)
        log_info "User skipped startosinstall."
        log_end 0; exit 0
        ;;
    e|E)
        echo ""
        echo "  WARNING: This will ERASE the target volume."
        read -r -p "  Type YES to confirm erase-install: " CONFIRM
        if [[ "$CONFIRM" != "YES" ]]; then
            echo "  Aborted."
            log_info "Erase-install aborted by user."
            log_end 0; exit 0
        fi
        SI_FLAGS="--eraseinstall --agreetolicense --newvolumename 'Macintosh HD'"
        log_info "Mode: erase-install"
        ;;
    *)
        SI_FLAGS="--agreetolicense"
        log_info "Mode: upgrade/reinstall"
        ;;
esac

echo ""
echo "Starting startosinstall — the machine will reboot automatically to complete the install."
echo ""
log_info "Running: $STARTOSINSTALL $SI_FLAGS"

SI_EXIT=0
# shellcheck disable=SC2086
"$STARTOSINSTALL" $SI_FLAGS 2>&1 | tee -a "$LOG_FILE" || SI_EXIT=$?

log_info "startosinstall exited: $SI_EXIT"
log_end "$SI_EXIT"
exit "$SI_EXIT"
