#!/bin/bash
# Inspect network configuration from the offline volume.
# Usage: ./ts_network.sh [volume-root]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="ts_network.sh"
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

show_file() {
    local label="$1" path="$2"
    if [[ -f "$path" ]]; then
        log_section "$label"
        cat "$path" | tee -a "$LOG_FILE"
    else
        log_info "Not found: $path"
    fi
}

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

# ── Live network (Recovery environment) ───────────────────────────────────────
log_section "Current Recovery network state"
ifconfig 2>/dev/null | tee -a "$LOG_FILE" || log_info "ifconfig not available."
echo ""
netstat -rn 2>/dev/null | tee -a "$LOG_FILE" || log_info "netstat not available."

# ── Offline volume network config ─────────────────────────────────────────────
show_file "hosts file"        "$VOL/private/etc/hosts"
show_file "resolv.conf"       "$VOL/private/etc/resolv.conf"

show_plist "SystemConfiguration preferences (interfaces, proxies)" \
    "$VOL/Library/Preferences/SystemConfiguration/preferences.plist"

show_plist "NetworkInterfaces"  \
    "$VOL/Library/Preferences/SystemConfiguration/NetworkInterfaces.plist"

show_plist "com.apple.wifi.known-networks" \
    "$VOL/Library/Preferences/com.apple.wifi.known-networks.plist"

# ── VPN configs ────────────────────────────────────────────────────────────────
log_section "VPN configuration plists"
find "$VOL/Library/Preferences/SystemConfiguration" \
     "$VOL/Library/Managed Preferences" \
     "$VOL/private/var/db/ConfigurationProfiles" \
    -maxdepth 3 -name "*vpn*" -o -name "*VPN*" 2>/dev/null | sort | while read -r f; do
    log_info "  $f"
    plutil -convert xml1 -o - "$f" 2>/dev/null | head -30 | tee -a "$LOG_FILE" || true
done

# ── Proxy settings ────────────────────────────────────────────────────────────
show_plist "Proxy preferences" \
    "$VOL/Library/Preferences/com.apple.networkextension.plist"

# ── Firewalls ─────────────────────────────────────────────────────────────────
show_plist "Application firewall (socketfilterfw)" \
    "$VOL/Library/Preferences/com.apple.alf.plist"

# ── DNS override / mDNS ───────────────────────────────────────────────────────
show_file "mDNSResponder" "$VOL/private/etc/mDNSResponder.conf"

log_end 0
