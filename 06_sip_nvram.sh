#!/bin/bash
# Manage SIP (System Integrity Protection) and NVRAM from Recovery Terminal.
# SIP changes only take effect after reboot from Recovery.
# Usage:  ./06_sip_nvram.sh [status|disable|enable|reset-nvram|delete-key <key>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="06_sip_nvram.sh"
# shellcheck source=lib_log.sh
source "$SCRIPT_DIR/lib_log.sh"
log_start "$@"

ACTION="${1:-status}"

case "$ACTION" in

    status)
        log_section "SIP Status"
        log_cmd csrutil status

        log_section "NVRAM"
        log_cmd nvram -p
        ;;

    disable)
        log_warn "Disabling SIP — this weakens macOS security. Re-enable after recovery."
        log_cmd csrutil disable
        log_info "Reboot from Recovery for the change to take effect."
        ;;

    enable)
        log_info "Enabling SIP (restoring full protection)..."
        log_cmd csrutil enable
        log_info "Reboot from Recovery for the change to take effect."
        ;;

    reset-nvram)
        log_info "Resetting NVRAM..."
        log_cmd nvram -c
        log_info "NVRAM cleared. Reboot for changes to take effect."
        ;;

    delete-key)
        KEY="${2:-}"
        if [[ -z "$KEY" ]]; then
            log_error "Usage: $0 delete-key <nvram-key>"
            log_end 1; exit 1
        fi
        log_info "Deleting NVRAM key: $KEY"
        log_cmd nvram -d "$KEY"
        log_info "Deleted NVRAM key: $KEY"
        ;;

    *)
        log_error "Unknown action: $ACTION"
        log_info "Usage: $0 [status|disable|enable|reset-nvram|delete-key <key>]"
        log_end 1; exit 1
        ;;
esac

log_end 0
