#!/bin/bash
# Reset a local macOS user password from Recovery Terminal.
# Works on the offline volume — does NOT require the old password.
# Usage:  ./04_reset_password.sh [volume-root] [username]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="04_reset_password.sh"
# shellcheck source=lib_log.sh
source "$SCRIPT_DIR/lib_log.sh"
log_start "$@"

VOL="${1:-${MAC_VOL:-}}"
USERNAME="${2:-}"

# ── Resolve volume root ────────────────────────────────────────────────────────
if [[ -z "$VOL" ]]; then
    for candidate in "/Volumes/Macintosh HD" "/Volumes/Data" "/Volumes/Recovery_HD"; do
        [[ -d "$candidate" ]] && VOL="$candidate" && break
    done
fi

if [[ -z "$VOL" || ! -d "$VOL" ]]; then
    log_error "Cannot find volume. Pass as first argument or set MAC_VOL."
    log_end 1; exit 1
fi

log_info "Volume root: $VOL"

# ── List users if none given ───────────────────────────────────────────────────
if [[ -z "$USERNAME" ]]; then
    log_section "Local user accounts"
    ls "$VOL/Users/" | grep -v -E '^\.|Shared' | nl
    echo ""
    read -r -p "Enter username to reset: " USERNAME
    log_info "Selected username: $USERNAME"
fi

USERHOME="$VOL/Users/$USERNAME"
if [[ ! -d "$USERHOME" ]]; then
    log_error "Home directory $USERHOME not found."
    log_end 1; exit 1
fi

echo ""
read -r -s -p "New password for '$USERNAME' (input hidden): " NEWPASS
echo ""
read -r -s -p "Confirm new password: " NEWPASS2
echo ""

if [[ "$NEWPASS" != "$NEWPASS2" ]]; then
    log_error "Passwords do not match."
    unset NEWPASS NEWPASS2
    log_end 1; exit 1
fi

if [[ -z "$NEWPASS" ]]; then
    log_error "Password cannot be empty."
    unset NEWPASS NEWPASS2
    log_end 1; exit 1
fi

# ── Apply with dscl on the offline DirectoryService database ──────────────────
log_info "Resetting password for $USERNAME via offline dscl..."
dscl -f "$VOL/private/var/db/dslocal/nodes/Default" localonly \
    -passwd "/Local/Default/Users/$USERNAME" "$NEWPASS" \
    >> "$LOG_FILE" 2>&1 && echo "Password reset succeeded." || {
        unset NEWPASS NEWPASS2
        log_error "dscl -passwd failed. Check log: $LOG_FILE"
        log_end 1; exit 1
    }
unset NEWPASS NEWPASS2

log_info "Password reset complete for '$USERNAME'."
log_info "Note: If FileVault is enabled the account's keychain password will mismatch"
log_info "      until the user updates it at first login (macOS prompts automatically)."
log_end 0
