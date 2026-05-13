#!/bin/bash
# Master interactive recovery menu — run this first from Recovery Terminal.
# It chains the individual scripts in a logical order.
# Usage: bash 09_recovery_menu.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="09_recovery_menu.sh"
# shellcheck source=lib_log.sh
source "$SCRIPT_DIR/lib_log.sh"
log_start "$@"

# Make all scripts executable
chmod +x "$SCRIPT_DIR"/*.sh

print_banner() {
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║        macOS Recovery Toolkit  (run as root)        ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    if [[ -n "${MAC_VOL:-}" ]]; then
        echo "  Active volume: $MAC_VOL"
    else
        echo "  Active volume: (not yet unlocked)"
    fi
    echo "  Log file:      $LOG_FILE"
    echo ""
}

print_menu() {
    echo "  1) Scan disks / list volumes          (01_find_volumes.sh)"
    echo "  2) Unlock APFS encrypted volume       (02_unlock_apfs.sh)"
    echo "  3) Disable launch agents / daemons    (03_disable_launch_agents.sh)"
    echo "  4) Reset local user password          (04_reset_password.sh)"
    echo "  5) Check / repair APFS filesystem     (05_repair_disk.sh)"
    echo "  6) SIP status / disable / NVRAM reset (06_sip_nvram.sh)"
    echo "  7) Restore disabled launch agents     (07_restore_launch_agents.sh)"
    echo "  8) Fix home-directory permissions     (08_fix_permissions.sh)"
    echo "  9) Open a subshell (manual commands)"
    echo "  l) Show log tail (last 40 lines)"
    echo "  q) Quit"
    echo ""
}

run_script() {
    local script="$1"
    shift
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [MENU] [09_recovery_menu.sh] --- Launching: $script $* ---" >> "$LOG_FILE"
    echo ""
    echo "─── Running $script ───"
    bash "$SCRIPT_DIR/$script" "$@" || {
        local code=$?
        echo "[$ts] [MENU] [09_recovery_menu.sh] $script exited with code $code" >> "$LOG_FILE"
        echo "(script exited with error — see log: $LOG_FILE)"
    }
    echo ""
    read -r -p "Press Enter to return to menu..."
}

while true; do
    clear
    print_banner
    print_menu
    read -r -p "Choice: " CHOICE

    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [MENU] [09_recovery_menu.sh] User selected: $CHOICE" >> "$LOG_FILE"

    case "$CHOICE" in
        1) run_script 01_find_volumes.sh ;;

        2)
            run_script 02_unlock_apfs.sh
            for candidate in "/Volumes/Macintosh HD" "/Volumes/Macintosh HD - Data" \
                             "/Volumes/Data" "/Volumes/Recovery_HD"; do
                if [[ -d "$candidate" ]]; then
                    export MAC_VOL="$candidate"
                    ts="$(date '+%Y-%m-%d %H:%M:%S')"
                    echo "[$ts] [MENU] [09_recovery_menu.sh] MAC_VOL set to: $MAC_VOL" >> "$LOG_FILE"
                    echo "MAC_VOL set to: $MAC_VOL"
                    break
                fi
            done
            ;;

        3)
            if [[ -z "${MAC_VOL:-}" ]]; then
                echo "WARNING: Volume not set. Run option 2 first, or set MAC_VOL manually."
                read -r -p "Enter volume path manually (e.g. /Volumes/Macintosh HD): " MAC_VOL
                export MAC_VOL
            fi
            echo ""
            echo "Mode options:"
            echo "  a) Interactive (ask per-plist)"
            echo "  b) Disable ALL agents and daemons"
            echo "  c) Disable one specific user's agents"
            read -r -p "Choose [a/b/c]: " SUBMODE
            case "$SUBMODE" in
                a) run_script 03_disable_launch_agents.sh "$MAC_VOL" interactive ;;
                b) run_script 03_disable_launch_agents.sh "$MAC_VOL" --all ;;
                c)
                    read -r -p "Username: " UNAME
                    run_script 03_disable_launch_agents.sh "$MAC_VOL" --user "$UNAME"
                    ;;
            esac
            ;;

        4) run_script 04_reset_password.sh "${MAC_VOL:-}" ;;

        5)
            echo ""
            echo "  a) Check only (safe, no writes)"
            echo "  b) Check AND repair"
            read -r -p "Choose [a/b]: " SUBMODE
            case "$SUBMODE" in
                a) run_script 05_repair_disk.sh ;;
                b) run_script 05_repair_disk.sh "" --repair ;;
            esac
            ;;

        6)
            echo ""
            echo "  1) Status"
            echo "  2) Disable SIP"
            echo "  3) Enable SIP"
            echo "  4) Reset NVRAM"
            read -r -p "Choose: " SUBMODE
            case "$SUBMODE" in
                1) run_script 06_sip_nvram.sh status ;;
                2) run_script 06_sip_nvram.sh disable ;;
                3) run_script 06_sip_nvram.sh enable ;;
                4) run_script 06_sip_nvram.sh reset-nvram ;;
            esac
            ;;

        7) run_script 07_restore_launch_agents.sh "${MAC_VOL:-}" ;;

        8) run_script 08_fix_permissions.sh "${MAC_VOL:-}" ;;

        9)
            echo "Opening subshell. Type 'exit' to return to menu."
            bash || true
            ;;

        l|L)
            echo ""
            echo "=== Last 40 lines of $LOG_FILE ==="
            tail -40 "$LOG_FILE" 2>/dev/null || echo "(log is empty)"
            echo ""
            read -r -p "Press Enter to return to menu..."
            ;;

        q|Q)
            log_info "User quit the menu."
            log_end 0
            echo "Exiting. Remember to reboot: 'reboot' or use Apple menu."
            exit 0
            ;;

        *)
            echo "Unknown option: $CHOICE"
            sleep 1
            ;;
    esac
done
