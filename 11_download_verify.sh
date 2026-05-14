#!/bin/bash
# Download macOS update packages, verify hashes, and inspect their contents.
#
# Actions:
#   fetch-installer [version]  — download full macOS installer via softwareupdate
#   hash <file>                — print SHA-1 / SHA-256 / MD5 of a file
#   compare <file> <hash>      — verify a file's SHA-256 matches a known-good value
#   catalog                    — fetch & parse Apple's sucatalog; shows packages + checksums
#   download <url> <dest>      — curl-download a package to a path
#   extract <pkg> <dest-dir>   — expand a .pkg with pkgutil
#   mount <dmg>                — attach a .dmg and show contents
#   interactive                — interactive menu (default)
#
# Usage:  bash 11_download_verify.sh [action] [args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_SCRIPT="11_download_verify.sh"
# shellcheck source=lib_log.sh
source "$SCRIPT_DIR/lib_log.sh"
log_start "$@"

ACTION="${1:-interactive}"

# Apple's merged sucatalog — covers macOS 10.9 through 15.x
SUCATALOG_URL="https://swscan.apple.com/content/catalogs/others/index-15-14-13-12-10.16-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog.gz"
CATALOG_CACHE="/tmp/mac_sucatalog.plist"

# ── Helpers ────────────────────────────────────────────────────────────────────

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "Must be run as root."
        log_end 1; exit 1
    fi
}

require_network() {
    if ! ping -c 1 -W 3 swscan.apple.com >/dev/null 2>&1; then
        log_warn "Cannot reach swscan.apple.com — network may be down."
        echo "  Tip: networksetup -setairportnetwork en0 <SSID> <password>"
        return 1
    fi
}

do_hash() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    log_section "Hashes for: $file"
    local size
    size=$(du -sh "$file" | awk '{print $1}')
    echo "  Size:    $size"
    echo ""
    echo "  Computing SHA-256 (this may take a while for large files)..."
    local sha256 sha1 md5val
    sha256=$(shasum -a 256 "$file" | awk '{print $1}')
    sha1=$(shasum -a 1   "$file" | awk '{print $1}')
    md5val=$(md5 -q      "$file" 2>/dev/null || md5sum "$file" | awk '{print $1}')
    echo ""
    echo "  SHA-256: $sha256"
    echo "  SHA-1:   $sha1"
    echo "  MD5:     $md5val"
    echo ""
    log_info "SHA-256: $sha256"
    log_info "SHA-1:   $sha1"
    log_info "MD5:     $md5val"
}

do_compare() {
    local file="$1"
    local known="$2"
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    log_section "Hash verification"
    echo "  File:     $file"
    echo "  Expected: $known"
    echo ""
    echo "  Computing SHA-256..."
    local actual
    actual=$(shasum -a 256 "$file" | awk '{print $1}')
    echo "  Actual:   $actual"
    echo ""
    # normalise case for comparison
    local known_lc actual_lc
    known_lc=$(echo "$known" | tr '[:upper:]' '[:lower:]')
    actual_lc=$(echo "$actual" | tr '[:upper:]' '[:lower:]')
    if [[ "$known_lc" == "$actual_lc" ]]; then
        log_info "MATCH — hash verified OK"
        echo "  RESULT:   ✓  MATCH — file is intact"
    else
        log_warn "MISMATCH — file may be corrupt or tampered"
        echo "  RESULT:   ✗  MISMATCH — file does not match expected hash"
        echo ""
        echo "  Do NOT use this file for installation."
    fi
    echo ""
}

do_fetch_installer() {
    local ver="${1:-}"
    log_section "Fetch full macOS installer"
    require_root

    if [[ -n "$ver" ]]; then
        log_info "Fetching installer version: $ver"
        echo "Running: softwareupdate --fetch-full-installer --full-installer-version $ver"
        echo "(This can take 20–60 minutes depending on connection speed.)"
        echo ""
        softwareupdate --fetch-full-installer --full-installer-version "$ver" 2>&1 | tee -a "$LOG_FILE" || {
            local code=$?
            log_warn "softwareupdate exited $code — trying without --full-installer-version"
            softwareupdate --fetch-full-installer 2>&1 | tee -a "$LOG_FILE" || true
        }
    else
        log_info "Fetching latest available installer"
        echo "Running: softwareupdate --fetch-full-installer"
        echo "(This can take 20–60 minutes depending on connection speed.)"
        echo ""
        softwareupdate --fetch-full-installer 2>&1 | tee -a "$LOG_FILE" || true
    fi

    # Find what landed in /Applications
    log_section "Installer files in /Applications"
    local installers
    installers=$(find /Applications -maxdepth 1 -name "Install macOS*" -type d 2>/dev/null || true)
    if [[ -z "$installers" ]]; then
        log_warn "No installer found in /Applications after fetch."
        echo "  Nothing found in /Applications. The download may have failed."
        echo "  Check log: $LOG_FILE"
        return 1
    fi

    echo "$installers"
    echo ""

    while IFS= read -r app; do
        echo "  Found: $app"
        # Hash the primary payload files inside the installer bundle
        local shared_support="$app/Contents/SharedSupport"
        if [[ -d "$shared_support" ]]; then
            echo ""
            echo "  Payload files in $shared_support:"
            find "$shared_support" -maxdepth 1 -type f | while read -r payload; do
                local fname size
                fname=$(basename "$payload")
                size=$(du -sh "$payload" | awk '{print $1}')
                echo "    $fname  ($size)"
            done
            echo ""
            echo "  Hashing payload files (SHA-256)..."
            find "$shared_support" -maxdepth 1 -type f | while read -r payload; do
                local fname hash
                fname=$(basename "$payload")
                echo -n "    $fname: "
                hash=$(shasum -a 256 "$payload" | awk '{print $1}')
                echo "$hash"
                log_info "SHA-256 $fname: $hash"
            done
        fi
        echo ""
    done <<< "$installers"
}

fetch_catalog() {
    log_section "Fetching Apple sucatalog"
    echo "  URL: $SUCATALOG_URL"
    echo ""
    if [[ -f "$CATALOG_CACHE" ]]; then
        local age_min
        age_min=$(( ( $(date +%s) - $(stat -f %m "$CATALOG_CACHE" 2>/dev/null || echo 0) ) / 60 ))
        if [[ $age_min -lt 60 ]]; then
            log_info "Using cached catalog ($age_min min old): $CATALOG_CACHE"
            echo "  Using cached catalog ($age_min min old). Delete $CATALOG_CACHE to force refresh."
            return 0
        fi
    fi
    require_network || return 1
    echo "  Downloading catalog..."
    curl -fsSL "$SUCATALOG_URL" | gunzip > "$CATALOG_CACHE" 2>&1
    log_info "Catalog saved to $CATALOG_CACHE"
    echo "  Saved to $CATALOG_CACHE"
}

do_catalog() {
    fetch_catalog || return 1
    log_section "Parsing catalog for macOS update packages"

    # Use python3 if available; fall back to awk-based grep
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$CATALOG_CACHE" <<'PYEOF'
import sys, plistlib, os

path = sys.argv[1]
with open(path, "rb") as f:
    cat = plistlib.load(f)

products = cat.get("Products", {})
entries = []
for pid, prod in products.items():
    # Only products with a ServerMetadataURL that looks like macOS
    meta_url = prod.get("ServerMetadataURL", "")
    dists = prod.get("Distributions", {})
    en_dist = dists.get("English", dists.get("en", ""))
    packages = prod.get("Packages", [])
    # Filter to products that have packages with macOS-style names
    pkg_names = [p.get("URL","") for p in packages]
    is_macos = any(
        "macOS" in u or "OSInstall" in u or "InstallAssistant" in u or "macOSUpd" in u
        for u in pkg_names + [meta_url, en_dist]
    )
    if not is_macos:
        continue
    post_date = str(prod.get("PostDate", ""))[:10]
    entry_pkgs = []
    for pkg in packages:
        url  = pkg.get("URL", "")
        size = pkg.get("Size", 0)
        sha1 = pkg.get("Digest", "")        # Apple stores SHA-1 as "Digest"
        iurl = pkg.get("IntegrityDataURL", "")
        entry_pkgs.append((url, size, sha1, iurl))
    entries.append((post_date, pid, en_dist, entry_pkgs))

entries.sort(key=lambda x: x[0], reverse=True)

if not entries:
    print("  No macOS-related products found in catalog.")
    sys.exit(0)

print(f"  Found {len(entries)} macOS product(s) in catalog (newest first):\n")
for post_date, pid, dist_url, pkgs in entries[:30]:
    print(f"  [{post_date}] Product ID: {pid}")
    if dist_url:
        print(f"    Distribution: {dist_url}")
    for url, size, sha1, iurl in pkgs:
        mb = size // (1024*1024) if size else 0
        print(f"    PKG: {os.path.basename(url)}  ({mb} MB)")
        print(f"         URL:    {url}")
        if sha1:
            print(f"         SHA-1:  {sha1}")
        if iurl:
            print(f"         IntegrityData: {iurl}")
    print()
PYEOF
    else
        # Fallback: grep the raw plist for macOS-related URLs and their checksums
        log_warn "python3 not found — using basic grep parser (less detail)"
        echo ""
        echo "  macOS-related package URLs found in catalog:"
        echo ""
        grep -o 'https://[^<]*\(macOS\|OSInstall\|InstallAssistant\|macOSUpd\)[^<]*\.pkg' \
            "$CATALOG_CACHE" 2>/dev/null | sort -u | while read -r url; do
            fname=$(basename "$url")
            echo "  $fname"
            echo "    $url"
            echo ""
        done | tee -a "$LOG_FILE"
    fi
}

do_download() {
    local url="${1:-}"
    local dest="${2:-}"

    if [[ -z "$url" ]]; then
        echo ""
        read -r -p "  Package URL: " url
    fi
    if [[ -z "$dest" ]]; then
        local fname
        fname=$(basename "$url")
        read -r -p "  Save to [/tmp/$fname]: " dest
        dest="${dest:-/tmp/$fname}"
    fi

    log_section "Downloading package"
    echo "  URL:  $url"
    echo "  Dest: $dest"
    echo ""
    require_network || return 1

    curl -L --progress-bar -o "$dest" "$url" 2>&1 | tee -a "$LOG_FILE"
    local code=$?
    if [[ $code -ne 0 ]]; then
        log_error "curl failed with exit code $code"
        return $code
    fi
    log_info "Download complete: $dest"
    echo ""
    echo "  Download complete. Computing SHA-256..."
    do_hash "$dest"
}

do_extract() {
    local pkg="${1:-}"
    local destdir="${2:-}"

    if [[ -z "$pkg" ]]; then
        echo ""
        read -r -p "  PKG path: " pkg
    fi
    if [[ ! -f "$pkg" ]]; then
        log_error "File not found: $pkg"
        return 1
    fi
    if [[ -z "$destdir" ]]; then
        local base
        base=$(basename "$pkg" .pkg)
        destdir="/tmp/${base}_extracted"
        echo "  Extracting to: $destdir"
    fi

    log_section "Extracting PKG: $pkg"
    rm -rf "$destdir"
    pkgutil --expand "$pkg" "$destdir" 2>&1 | tee -a "$LOG_FILE"
    log_info "Extracted to: $destdir"
    echo ""
    echo "  Contents of $destdir:"
    find "$destdir" -maxdepth 3 | sed "s|$destdir/||" | sort | tee -a "$LOG_FILE"
    echo ""
    echo "  To inspect a Payload archive inside:"
    echo "    cd $destdir/<component>.pkg && cpio -i < Payload"
}

do_mount() {
    local dmg="${1:-}"

    if [[ -z "$dmg" ]]; then
        echo ""
        read -r -p "  DMG path: " dmg
    fi
    if [[ ! -f "$dmg" ]]; then
        log_error "File not found: $dmg"
        return 1
    fi

    log_section "Mounting DMG: $dmg"
    local output
    output=$(hdiutil attach "$dmg" -nobrowse 2>&1) || {
        log_error "hdiutil attach failed"
        echo "$output"
        return 1
    }
    echo "$output" | tee -a "$LOG_FILE"
    local mount_point
    mount_point=$(echo "$output" | awk '/\/Volumes\//{print $NF}' | tail -1)
    log_info "Mounted at: $mount_point"
    echo ""
    echo "  Contents of $mount_point:"
    ls -lh "$mount_point" 2>/dev/null || true
    echo ""
    echo "  To unmount:  hdiutil detach '$mount_point'"
}

do_integrity_check() {
    # Download and apply an Apple IntegrityDataV1 file to verify a PKG
    local pkg="${1:-}"
    local iurl="${2:-}"

    if [[ -z "$pkg" ]]; then
        read -r -p "  PKG path to verify: " pkg
    fi
    if [[ ! -f "$pkg" ]]; then
        log_error "File not found: $pkg"
        return 1
    fi
    if [[ -z "$iurl" ]]; then
        read -r -p "  IntegrityDataURL (from catalog): " iurl
    fi

    log_section "Apple IntegrityData verification"
    echo "  PKG:  $pkg"
    echo "  Data: $iurl"
    echo ""

    local idata="/tmp/$(basename "$iurl")"
    curl -fsSL -o "$idata" "$iurl" 2>&1 | tee -a "$LOG_FILE"
    log_info "IntegrityData saved to $idata"

    # IntegrityDataV1 is a binary plist containing a "chunkChecksum" array
    # of SHA-256 hashes for 1 MB chunks.  We verify each chunk manually.
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$pkg" "$idata" <<'PYEOF'
import sys, plistlib, hashlib, os

pkg_path  = sys.argv[1]
data_path = sys.argv[2]

with open(data_path, "rb") as f:
    idata = plistlib.load(f)

chunks   = idata.get("chunkChecksum", [])
chunk_sz = idata.get("chunkSize", 1024*1024)

if not chunks:
    print("  No chunkChecksum entries found — cannot verify.")
    sys.exit(1)

print(f"  Verifying {len(chunks)} chunk(s) of {chunk_sz//1024} KB each...")
pkg_size = os.path.getsize(pkg_path)
mismatch = False

with open(pkg_path, "rb") as f:
    for idx, expected in enumerate(chunks):
        data = f.read(chunk_sz)
        actual = hashlib.sha256(data).digest()
        if actual != bytes(expected):
            print(f"  FAIL chunk {idx}: expected {bytes(expected).hex()}")
            print(f"                   actual   {actual.hex()}")
            mismatch = True
        else:
            sys.stdout.write(f"\r  chunk {idx+1}/{len(chunks)} OK")
            sys.stdout.flush()

print()
if mismatch:
    print("\n  RESULT: ✗  INTEGRITY FAILURE — package is corrupt or tampered.")
    sys.exit(1)
else:
    print(f"\n  RESULT: ✓  All {len(chunks)} chunks verified. Package is intact.")
PYEOF
    else
        log_warn "python3 not found — cannot parse IntegrityData plist."
        echo "  IntegrityData downloaded to $idata but cannot be parsed without python3."
        echo "  You can manually inspect it with:  plutil -p $idata"
    fi
}

# ── Interactive menu ───────────────────────────────────────────────────────────

interactive_menu() {
    while true; do
        printf '\033c'
        echo ""
        echo "=== Download & Verify macOS Updates ==="
        echo ""
        echo "  1) Fetch full macOS installer via softwareupdate"
        echo "  2) Browse Apple's update catalog (lists packages + checksums)"
        echo "  3) Download a package by URL"
        echo "  4) Compute hashes (SHA-256 / SHA-1 / MD5) for a file"
        echo "  5) Compare a file's SHA-256 against a known-good value"
        echo "  6) Verify via Apple IntegrityData (chunk-level SHA-256)"
        echo "  7) Extract / inspect a .pkg file"
        echo "  8) Mount a .dmg file"
        echo "  b) Back"
        echo ""
        read -r -p "Choice: " CH
        echo ""
        case "$CH" in
            1)
                read -r -p "  macOS version to fetch (e.g. 15.4.1) or Enter for latest: " VER
                do_fetch_installer "$VER"
                read -r -p "Press Enter to continue..."
                ;;
            2)
                do_catalog
                read -r -p "Press Enter to continue..."
                ;;
            3)
                do_download "" ""
                read -r -p "Press Enter to continue..."
                ;;
            4)
                read -r -p "  File path: " FPATH
                do_hash "$FPATH"
                read -r -p "Press Enter to continue..."
                ;;
            5)
                read -r -p "  File path: " FPATH
                read -r -p "  Expected SHA-256: " KHASH
                do_compare "$FPATH" "$KHASH"
                read -r -p "Press Enter to continue..."
                ;;
            6)
                do_integrity_check "" ""
                read -r -p "Press Enter to continue..."
                ;;
            7)
                read -r -p "  PKG path: " PKGPATH
                read -r -p "  Destination dir (Enter for /tmp/<name>_extracted): " DSTDIR
                do_extract "$PKGPATH" "$DSTDIR"
                read -r -p "Press Enter to continue..."
                ;;
            8)
                read -r -p "  DMG path: " DMGPATH
                do_mount "$DMGPATH"
                read -r -p "Press Enter to continue..."
                ;;
            b|B) break ;;
            *) echo "Unknown option."; sleep 1 ;;
        esac
    done
}

# ── Dispatch ───────────────────────────────────────────────────────────────────

case "$ACTION" in
    fetch-installer)  do_fetch_installer "${2:-}" ;;
    hash)             do_hash "${2:-}" ;;
    compare)          do_compare "${2:-}" "${3:-}" ;;
    catalog)          do_catalog ;;
    download)         do_download "${2:-}" "${3:-}" ;;
    extract)          do_extract "${2:-}" "${3:-}" ;;
    mount)            do_mount "${2:-}" ;;
    integrity)        do_integrity_check "${2:-}" "${3:-}" ;;
    interactive)      interactive_menu ;;
    *)
        log_error "Unknown action: $ACTION"
        echo "Usage: bash $0 [fetch-installer|hash|compare|catalog|download|extract|mount|integrity|interactive]"
        log_end 1; exit 1
        ;;
esac

log_end 0
