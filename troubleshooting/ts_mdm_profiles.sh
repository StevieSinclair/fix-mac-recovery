#!/bin/bash
# Inspect MDM enrollment and configuration profiles from the offline volume.
# Usage: ./ts_mdm_profiles.sh [volume-root]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="ts_mdm_profiles.sh"
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

show_plist() {
    local label="$1" path="$2"
    if [[ -f "$path" ]]; then
        log_section "$label"
        plutil -convert xml1 -o - "$path" 2>/dev/null | tee -a "$LOG_FILE" \
            || log_warn "Could not parse $path"
    else
        log_info "Not found: $path"
    fi
}

# ── MDM enrollment state ───────────────────────────────────────────────────────
log_section "MDM enrollment database"
ENROLL_DIRS=(
    "$VOL/private/var/db/ConfigurationProfiles"
    "$VOL/private/var/db/MDMAppleConfig"
    "$VOL/Library/Application Support/com.apple.mdmclient"
)
for d in "${ENROLL_DIRS[@]}"; do
    if [[ -d "$d" ]]; then
        log_info "Found: $d"
        ls -la "$d" 2>/dev/null | tee -a "$LOG_FILE"
    fi
done

show_plist "Enrollment profile" \
    "$VOL/private/var/db/ConfigurationProfiles/enrollmentProfile.mobileconfig"
show_plist "MDM client config" \
    "$VOL/private/var/db/mdmclient/ClientConfig.plist"

# ── Installed configuration profiles ──────────────────────────────────────────
log_section "Installed configuration profiles"
PROFILE_DIR="$VOL/private/var/db/ConfigurationProfiles/Store/Managed Preferences"
if [[ -d "$PROFILE_DIR" ]]; then
    find "$PROFILE_DIR" -name "*.plist" 2>/dev/null | sort | while read -r plist; do
        log_info ""
        log_info "  Profile: $plist"
        plutil -convert xml1 -o - "$plist" 2>/dev/null \
            | grep -E "<key>|<string>|<true|<false" | head -20 | tee -a "$LOG_FILE" \
            || log_warn "  Could not parse."
    done
else
    log_info "No configuration profile store found at expected path."
fi

# ── Raw profile files ──────────────────────────────────────────────────────────
log_section "Raw .mobileconfig files on volume"
find "$VOL" -xdev -name "*.mobileconfig" 2>/dev/null | head -20 | while read -r f; do
    log_info "  $f"
done

# ── Managed preferences ────────────────────────────────────────────────────────
log_section "Managed Preferences (MDM-pushed)"
MGMT="$VOL/Library/Managed Preferences"
if [[ -d "$MGMT" ]]; then
    for plist in "$MGMT"/*.plist; do
        [[ -f "$plist" ]] || continue
        log_info ""
        log_info "  $(basename "$plist")"
        plutil -convert xml1 -o - "$plist" 2>/dev/null \
            | grep -E "<key>|<string>|<true|<false" | head -10 | tee -a "$LOG_FILE"
    done
else
    log_info "No managed preferences found."
fi

# ── Device enrollment program ──────────────────────────────────────────────────
show_plist "DEP activation record" \
    "$VOL/private/var/db/MDMAppleConfig/ActivationRecord.plist"

log_section "Bootstrap token presence"
BT="$VOL/private/var/db/MDMAppleConfig/bootstraptoken"
if [[ -f "$BT" ]]; then
    log_info "Bootstrap token file present: $BT"
    ls -la "$BT" | tee -a "$LOG_FILE"
else
    log_info "No bootstrap token file found."
fi

log_end 0
