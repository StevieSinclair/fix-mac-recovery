#!/bin/bash
# Downloads all recovery scripts to the current directory.
# Usage: curl -fsSL https://raw.githubusercontent.com/StevieSinclair/fix-mac-recovery/master/fetch.sh | bash

set -euo pipefail

BASE="https://raw.githubusercontent.com/StevieSinclair/fix-mac-recovery/master"

SCRIPTS=(
    lib_log.sh
    01_find_volumes.sh
    02_unlock_apfs.sh
    03_disable_launch_agents.sh
    04_reset_password.sh
    05_repair_disk.sh
    06_sip_nvram.sh
    07_restore_launch_agents.sh
    08_fix_permissions.sh
    09_recovery_menu.sh
    fetch.sh
)

TROUBLESHOOTING=(
    troubleshooting/ts_disk_usage.sh
    troubleshooting/ts_logs.sh
    troubleshooting/ts_plist_inspect.sh
    troubleshooting/ts_startup_items.sh
    troubleshooting/ts_filesystem_check.sh
    troubleshooting/ts_user_accounts.sh
    troubleshooting/ts_microsoft.sh
    troubleshooting/ts_mdm_profiles.sh
    troubleshooting/ts_system_extensions.sh
    troubleshooting/ts_network.sh
    troubleshooting/ts_keychain.sh
    troubleshooting/ts_installed_apps.sh
    troubleshooting/ts_time_machine.sh
)

echo "Downloading recovery scripts to: $(pwd)"
echo ""

for script in "${SCRIPTS[@]}"; do
    curl -fsSL "$BASE/$script" -o "$script"
    chmod +x "$script"
    echo "  [ok] $script"
done

echo ""
echo "Downloading troubleshooting scripts..."
echo ""

mkdir -p troubleshooting
for script in "${TROUBLESHOOTING[@]}"; do
    curl -fsSL "$BASE/$script" -o "$script"
    chmod +x "$script"
    echo "  [ok] $script"
done

echo ""
echo "Done. Run: bash 09_recovery_menu.sh"
