#!/bin/bash
# Disable launch agents and daemons on the *offline* mounted volume.
# Run AFTER 02_unlock_apfs.sh.
# Usage:  ./03_disable_launch_agents.sh [volume-root] [--all | --user <username>]
#
# Modes:
#   --all            move every plist in LaunchAgents + LaunchDaemons to .disabled/
#   --user <name>    only disable plists in /Users/<name>/Library/LaunchAgents/
#   (default)        interactive — list each plist and ask y/n

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="03_disable_launch_agents.sh"
# shellcheck source=lib_log.sh
source "$SCRIPT_DIR/lib_log.sh"
log_start "$@"

VOL="${1:-}"
shift || true
MODE="${1:-interactive}"
USERNAME="${2:-}"

# ── Resolve volume root ────────────────────────────────────────────────────────
if [[ -z "$VOL" ]]; then
    VOL="${MAC_VOL:-}"
fi

if [[ -z "$VOL" ]]; then
    for candidate in "/Volumes/Macintosh HD" "/Volumes/Data" "/Volumes/Recovery_HD"; do
        if [[ -d "$candidate" ]]; then
            VOL="$candidate"
            break
        fi
    done
fi

if [[ -z "$VOL" || ! -d "$VOL" ]]; then
    log_error "Volume root not found. Pass it as the first argument or set MAC_VOL."
    log_info "Example: $0 '/Volumes/Macintosh HD' --all"
    log_end 1; exit 1
fi

log_info "Volume root: $VOL"
log_info "Mode: $MODE${USERNAME:+ (user: $USERNAME)}"

# ── Build list of agent/daemon directories to process ─────────────────────────
DIRS=()

if [[ "$MODE" == "--user" && -n "$USERNAME" ]]; then
    DIRS+=("$VOL/Users/$USERNAME/Library/LaunchAgents")
else
    DIRS+=(
        "$VOL/Library/LaunchAgents"
        "$VOL/Library/LaunchDaemons"
        "$VOL/System/Library/LaunchAgents"
        "$VOL/System/Library/LaunchDaemons"
    )
    for home in "$VOL/Users"/*/; do
        [[ -d "$home/Library/LaunchAgents" ]] && DIRS+=("$home/Library/LaunchAgents")
    done
fi

# ── Helper: disable one plist ─────────────────────────────────────────────────
disable_plist() {
    local plist="$1"
    local dir
    dir="$(dirname "$plist")/.disabled"
    mkdir -p "$dir"
    mv "$plist" "$dir/"
    log_info "  [disabled] $(basename "$plist")"
}

# ── Process each directory ─────────────────────────────────────────────────────
TOTAL=0
DISABLED=0

for dir in "${DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    log_section "$dir"

    plists=()
    while IFS= read -r _p; do plists+=("$_p"); done < <(find "$dir" -maxdepth 1 -name "*.plist" 2>/dev/null | sort)

    if [[ ${#plists[@]} -eq 0 ]]; then
        log_info "  (empty)"
        continue
    fi

    for plist in "${plists[@]}"; do
        ((TOTAL++))
        name="$(basename "$plist")"

        if [[ "$MODE" == "--all" ]]; then
            disable_plist "$plist"
            ((DISABLED++))
        else
            read -r -p "  Disable $name? [y/N] " answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                disable_plist "$plist"
                ((DISABLED++))
            else
                log_info "  [kept]     $name"
            fi
        fi
    done
done

log_info "Done. $DISABLED of $TOTAL plists disabled."
log_info "Disabled plists are in .disabled/ subdirectories — restore with:"
log_info "  mv '$VOL/Library/LaunchDaemons/.disabled/'*.plist '$VOL/Library/LaunchDaemons/'"
log_end 0
