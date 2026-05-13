#!/bin/bash
# Inspect Microsoft product state: Intune, DDM, Defender, AutoUpdate, Company Portal.
# Usage: ./ts_microsoft.sh [volume-root]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="ts_microsoft.sh"
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

# ── Helper: dump a plist if it exists ─────────────────────────────────────────
show_plist() {
    local label="$1" path="$2"
    if [[ -f "$path" ]]; then
        log_section "$label"
        plutil -convert xml1 -o - "$path" 2>/dev/null | tee -a "$LOG_FILE" || log_warn "Could not parse $path"
    else
        log_info "Not found: $path"
    fi
}

show_dir() {
    local label="$1" path="$2"
    log_section "$label"
    if [[ -d "$path" ]]; then
        ls -laR "$path" 2>/dev/null | tee -a "$LOG_FILE"
    else
        log_info "Not found: $path"
    fi
}

# ── Declarative Device Management (Apple DDM / Intune DDM) ────────────────────
log_section "Apple DDM — Declarative Management state"
DDM_DIRS=(
    "$VOL/private/var/db/MDMAppleConfig"
    "$VOL/private/var/db/mdmclient"
    "$VOL/Library/Application Support/com.apple.mdmclient"
)
for d in "${DDM_DIRS[@]}"; do
    if [[ -d "$d" ]]; then
        log_info "Found: $d"
        ls -la "$d" 2>/dev/null | tee -a "$LOG_FILE"
    fi
done

show_plist "DDM Activation record" \
    "$VOL/private/var/db/MDMAppleConfig/ActivationRecord.plist"
show_plist "DDM Client config" \
    "$VOL/private/var/db/mdmclient/ClientConfig.plist"

# ── Microsoft Intune ──────────────────────────────────────────────────────────
log_section "Microsoft Intune — agent and enrollment"
INTUNE_DIRS=(
    "$VOL/Library/Application Support/Microsoft/Intune"
    "$VOL/Library/Intune"
    "$VOL/Library/Logs/Microsoft/Intune"
    "$VOL/private/var/lib/microsoft/mdm"
)
for d in "${INTUNE_DIRS[@]}"; do
    [[ -d "$d" ]] && { log_info "Found: $d"; ls -la "$d" 2>/dev/null | tee -a "$LOG_FILE"; }
done

show_plist "Intune managed preferences" \
    "$VOL/Library/Managed Preferences/com.microsoft.intune.plist"

log_section "Intune logs (last 60 lines)"
INTUNE_LOG="$VOL/Library/Logs/Microsoft/Intune/intune_macos_agent.log"
if [[ -f "$INTUNE_LOG" ]]; then
    tail -60 "$INTUNE_LOG" | tee -a "$LOG_FILE"
else
    log_info "Intune agent log not found."
fi

# ── Microsoft Defender for Endpoint ──────────────────────────────────────────
log_section "Microsoft Defender for Endpoint"
DEFENDER_DIRS=(
    "$VOL/Library/Application Support/Microsoft/Defender"
    "$VOL/Library/Logs/Microsoft/mdatp"
    "$VOL/private/var/log/microsoft/mdatp"
)
for d in "${DEFENDER_DIRS[@]}"; do
    [[ -d "$d" ]] && { log_info "Found: $d"; ls -la "$d" 2>/dev/null | tee -a "$LOG_FILE"; }
done

show_plist "Defender managed config" \
    "$VOL/Library/Managed Preferences/com.microsoft.wdav.plist"
show_plist "Defender managed extensions" \
    "$VOL/Library/Managed Preferences/com.microsoft.wdav.ext.plist"

log_section "Defender logs (last 40 lines)"
for logf in \
    "$VOL/Library/Logs/Microsoft/mdatp/microsoft_defender_core.log" \
    "$VOL/private/var/log/microsoft/mdatp/microsoft_defender_core.log"; do
    if [[ -f "$logf" ]]; then
        tail -40 "$logf" | tee -a "$LOG_FILE"
        break
    fi
done

# ── Microsoft AutoUpdate ──────────────────────────────────────────────────────
log_section "Microsoft AutoUpdate (MAU)"
show_plist "MAU config" \
    "$VOL/Library/Preferences/com.microsoft.autoupdate2.plist"
show_plist "MAU managed config" \
    "$VOL/Library/Managed Preferences/com.microsoft.autoupdate2.plist"
show_dir  "MAU support dir" \
    "$VOL/Library/Application Support/Microsoft/MAU2.0"

# ── Company Portal ────────────────────────────────────────────────────────────
log_section "Company Portal"
CP_APP="$VOL/Applications/Company Portal.app"
if [[ -d "$CP_APP" ]]; then
    log_info "Company Portal installed."
    plutil -convert xml1 -o - "$CP_APP/Contents/Info.plist" 2>/dev/null \
        | grep -E "CFBundleVersion|CFBundleShortVersionString" | tee -a "$LOG_FILE"
else
    log_info "Company Portal.app not found."
fi

show_plist "Company Portal preferences" \
    "$VOL/Library/Preferences/com.microsoft.CompanyPortalMac.plist"

# ── Microsoft Office / M365 licensing ────────────────────────────────────────
log_section "Microsoft 365 / Office licensing"
show_plist "Office licensing" \
    "$VOL/Library/Preferences/com.microsoft.office.licensingV2.plist"
for user_home in "$VOL/Users"/*/; do
    lp="$user_home/Library/Group Containers/UBF8T346G9.Office/com.microsoft.Office.plist"
    [[ -f "$lp" ]] && { log_info "Found user Office plist: $lp"; plutil -convert xml1 -o - "$lp" 2>/dev/null | tee -a "$LOG_FILE"; }
done

# ── Managed preferences overview ──────────────────────────────────────────────
log_section "All managed preferences (MCX / MDM)"
MGMT_DIR="$VOL/Library/Managed Preferences"
if [[ -d "$MGMT_DIR" ]]; then
    ls "$MGMT_DIR" | tee -a "$LOG_FILE"
else
    log_info "No managed preferences directory found."
fi

log_end 0
