#!/bin/bash
# Restore previously disabled launch agents/daemons.
# Reverses the work done by 03_disable_launch_agents.sh.
# Usage:  ./07_restore_launch_agents.sh [volume-root]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="07_restore_launch_agents.sh"
# shellcheck source=lib_log.sh
source "$SCRIPT_DIR/lib_log.sh"
log_start "$@"

VOL="${1:-${MAC_VOL:-}}"

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

RESTORED=0

find "$VOL" -type d -name ".disabled" 2>/dev/null | while read -r disabled_dir; do
    parent="$(dirname "$disabled_dir")"
    plists=()
    while IFS= read -r _p; do plists+=("$_p"); done < <(find "$disabled_dir" -maxdepth 1 -name "*.plist" | sort)

    [[ ${#plists[@]} -eq 0 ]] && continue

    log_section "Restoring from $disabled_dir"
    for plist in "${plists[@]}"; do
        name="$(basename "$plist")"
        read -r -p "  Restore $name? [y/N] " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            mv "$plist" "$parent/$name"
            log_info "  [restored] $name"
            ((RESTORED++)) || true
        else
            log_info "  [skipped]  $name"
        fi
    done
done

log_info "Restore pass complete. $RESTORED plist(s) restored."
log_end 0
