#!/bin/bash
# Inspect keychain files and certificate stores on the offline volume.
# Keychains cannot be unlocked from Recovery without the user password,
# but this script maps what exists and flags common problems.
# Usage: ./ts_keychain.sh [volume-root]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="ts_keychain.sh"
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

# ── System keychains ──────────────────────────────────────────────────────────
log_section "System keychain files"
SYSTEM_KC_DIRS=(
    "$VOL/Library/Keychains"
    "$VOL/System/Library/Keychains"
    "$VOL/private/var/db/SystemKey"
)
for d in "${SYSTEM_KC_DIRS[@]}"; do
    if [[ -d "$d" || -f "$d" ]]; then
        log_info "  $d"
        ls -la "$d" 2>/dev/null | tee -a "$LOG_FILE"
    fi
done

# ── Per-user keychains ────────────────────────────────────────────────────────
log_section "Per-user keychain files"
for home in "$VOL/Users"/*/; do
    user="$(basename "$home")"
    [[ "$user" == "Shared" ]] && continue
    kc_dir="$home/Library/Keychains"
    if [[ -d "$kc_dir" ]]; then
        log_info "  User: $user"
        ls -la "$kc_dir" 2>/dev/null | tee -a "$LOG_FILE"
    fi
done

# ── Login keychain metadata ────────────────────────────────────────────────────
log_section "Login keychain metadata (plist, not contents)"
for home in "$VOL/Users"/*/; do
    user="$(basename "$home")"
    [[ "$user" == "Shared" ]] && continue
    meta="$home/Library/Keychains/login.keychain-db"
    if [[ -f "$meta" ]]; then
        log_info "  $user: login.keychain-db exists ($(du -sh "$meta" | awk '{print $1}'))"
    else
        log_warn "  $user: login.keychain-db MISSING — may cause login issues"
    fi
done

# ── System root certificates ──────────────────────────────────────────────────
log_section "System root certificate store"
CERT_STORE="$VOL/System/Library/Keychains/SystemRootCertificates.keychain"
if [[ -f "$CERT_STORE" ]]; then
    log_info "SystemRootCertificates.keychain present ($(du -sh "$CERT_STORE" | awk '{print $1}'))"
else
    log_warn "SystemRootCertificates.keychain MISSING — TLS will likely fail on boot."
fi

# ── MDM/Intune identity certificates ─────────────────────────────────────────
log_section "MDM identity certificate plists"
find "$VOL/Library/Keychains" "$VOL/private/var/db/ConfigurationProfiles" \
    -name "*.p12" -o -name "*.cer" -o -name "*.crt" 2>/dev/null \
    | sort | while read -r f; do
    log_info "  $f  ($(du -sh "$f" | awk '{print $1}'))"
done || log_info "None found."

log_end 0
