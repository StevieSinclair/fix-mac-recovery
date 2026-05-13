#!/bin/bash
# List installed applications and their versions from the offline volume.
# Usage: ./ts_installed_apps.sh [volume-root]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="ts_installed_apps.sh"
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

app_info() {
    local app="$1"
    local info="$app/Contents/Info.plist"
    [[ -f "$info" ]] || return
    local name ver id
    name="$(basename "$app" .app)"
    ver=$(plutil -convert xml1 -o - "$info" 2>/dev/null \
        | awk '/<key>CFBundleShortVersionString<\/key>/{getline; gsub(/[ \t]*<[^>]*>[ \t]*/,""); print}' | head -1)
    id=$(plutil -convert xml1 -o - "$info" 2>/dev/null \
        | awk '/<key>CFBundleIdentifier<\/key>/{getline; gsub(/[ \t]*<[^>]*>[ \t]*/,""); print}' | head -1)
    printf "  %-45s %-20s %s\n" "$name" "$ver" "$id" | tee -a "$LOG_FILE"
}

log_section "/Applications"
printf "  %-45s %-20s %s\n" "Name" "Version" "Bundle ID" | tee -a "$LOG_FILE"
printf "  %s\n" "$(printf '─%.0s' {1..80})" | tee -a "$LOG_FILE"
for app in "$VOL/Applications"/*.app; do
    [[ -d "$app" ]] && app_info "$app"
done

log_section "/Applications/Utilities"
for app in "$VOL/Applications/Utilities"/*.app; do
    [[ -d "$app" ]] && app_info "$app"
done

log_section "Per-user ~/Applications"
for home in "$VOL/Users"/*/; do
    user="$(basename "$home")"
    [[ "$user" == "Shared" ]] && continue
    [[ -d "$home/Applications" ]] || continue
    log_info "  User: $user"
    for app in "$home/Applications"/*.app; do
        [[ -d "$app" ]] && app_info "$app"
    done
done

log_section "macOS version"
SW="$VOL/System/Library/CoreServices/SystemVersion.plist"
if [[ -f "$SW" ]]; then
    plutil -convert xml1 -o - "$SW" 2>/dev/null \
        | grep -A 1 "ProductVersion\|ProductName\|ProductBuildVersion" \
        | grep "<string>" | tee -a "$LOG_FILE"
else
    log_info "SystemVersion.plist not found."
fi

log_end 0
