#!/bin/bash
# List system extensions, kernel extensions, and endpoint security clients
# from the offline volume. Useful for diagnosing boot hangs from security tools.
# Usage: ./ts_system_extensions.sh [volume-root]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="ts_system_extensions.sh"
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

# ── System extensions (macOS 10.15+) ─────────────────────────────────────────
log_section "System extensions database"
SEXT_DB="$VOL/Library/SystemExtensions"
if [[ -d "$SEXT_DB" ]]; then
    ls -laR "$SEXT_DB" 2>/dev/null | tee -a "$LOG_FILE"

    # The db.plist holds the extension state
    DB_PLIST="$SEXT_DB/db.plist"
    if [[ -f "$DB_PLIST" ]]; then
        log_section "System extensions db.plist"
        plutil -convert xml1 -o - "$DB_PLIST" 2>/dev/null | tee -a "$LOG_FILE" \
            || log_warn "Could not parse db.plist"
    fi
else
    log_info "No system extensions database found."
fi

# ── Pending system extension approvals ────────────────────────────────────────
log_section "Pending system extension activation requests"
PENDING="$VOL/Library/SystemExtensions/db.plist"
if [[ -f "$PENDING" ]]; then
    plutil -convert xml1 -o - "$PENDING" 2>/dev/null \
        | grep -A 2 -E "teamID|bundleID|state|validatedTeam" | head -60 | tee -a "$LOG_FILE"
fi

# ── Legacy kernel extensions ──────────────────────────────────────────────────
log_section "Third-party kernel extensions (/Library/Extensions)"
find "$VOL/Library/Extensions" -maxdepth 1 -name "*.kext" 2>/dev/null | sort | while read -r kext; do
    name="$(basename "$kext")"
    info="$kext/Contents/Info.plist"
    if [[ -f "$info" ]]; then
        ver=$(plutil -convert xml1 -o - "$info" 2>/dev/null \
            | awk '/<key>CFBundleVersion<\/key>/{getline; gsub(/<[^>]*>/,""); print}')
        id=$(plutil -convert xml1 -o - "$info" 2>/dev/null \
            | awk '/<key>CFBundleIdentifier<\/key>/{getline; gsub(/<[^>]*>/,""); print}')
        log_info "  $name  id=$id  ver=$ver"
    else
        log_info "  $name  (no Info.plist)"
    fi
done

log_section "Kexts in /System/Library/Extensions (non-Apple — rare)"
find "$VOL/System/Library/Extensions" -maxdepth 1 -name "*.kext" 2>/dev/null \
    | grep -v "com.apple" | sort | while read -r kext; do
    log_info "  $(basename "$kext")"
done || log_info "(none found)"

# ── Endpoint security / network extensions ────────────────────────────────────
log_section "Network / endpoint security extension bundles"
find "$VOL/Applications" -maxdepth 4 \
    -name "*.systemextension" -o -name "*.networkextension" 2>/dev/null \
    | sort | while read -r ext; do
    log_info "  $ext"
done

# ── Privacy / TCC database (who has what access) ──────────────────────────────
log_section "TCC database (privacy permissions)"
TCC="$VOL/Library/Application Support/com.apple.TCC/TCC.db"
if [[ -f "$TCC" ]]; then
    log_info "TCC database found: $TCC"
    log_info "Use 'sqlite3 \"$TCC\" .tables' after booting normally or in a subshell."
    ls -la "$TCC" | tee -a "$LOG_FILE"
else
    log_info "TCC database not found at $TCC"
fi

log_end 0
