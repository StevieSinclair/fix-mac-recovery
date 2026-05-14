# macOS Recovery Toolkit

A collection of bash scripts for diagnosing and repairing macOS from Recovery Terminal. Designed for situations where the normal macOS GUI recovery options (Reinstall macOS, Disk Utility, etc.) are looping, stalling, or otherwise failing.

## Quick start

Boot into Recovery Terminal and run:

```bash
curl -fsSL https://raw.githubusercontent.com/StevieSinclair/fix-mac-recovery/master/fetch.sh | bash
bash 09_recovery_menu.sh
```

This downloads all scripts and opens the interactive menu.

---

## Scripts

### Main menu

**`09_recovery_menu.sh`** — interactive menu that chains all scripts below. Run this first.

### Core recovery

| Script | Purpose |
|--------|---------|
| `01_find_volumes.sh` | Scan disks and list all APFS/HFS+ volumes |
| `02_unlock_apfs.sh` | Unlock an encrypted APFS volume |
| `03_disable_launch_agents.sh` | Disable launch agents/daemons (interactive, all, or per-user) |
| `04_reset_password.sh` | Reset a local user password |
| `05_repair_disk.sh` | Run `fsck_apfs` to check or repair the filesystem |
| `06_sip_nvram.sh` | Check/toggle SIP and reset NVRAM |
| `07_restore_launch_agents.sh` | Re-enable previously disabled launch agents |
| `08_fix_permissions.sh` | Fix home-directory permissions |
| `lib_log.sh` | Shared logging library (sourced by all scripts) |

### Updates

| Script | Purpose |
|--------|---------|
| `10_install_updates.sh` | Install macOS updates via `softwareupdate` from Recovery Terminal, bypassing the GUI reinstall loop. Checks network, lists available updates, supports all-updates or macOS-only mode. |
| `11_download_verify.sh` | Download update packages, verify hashes, and inspect contents. See [below](#download--verify). |

### Troubleshooting

| Script | Purpose |
|--------|---------|
| `troubleshooting/ts_disk_usage.sh` | Disk usage breakdown |
| `troubleshooting/ts_logs.sh` | System, crash, and panic logs |
| `troubleshooting/ts_plist_inspect.sh` | Inspect a plist file |
| `troubleshooting/ts_startup_items.sh` | Startup items and kexts |
| `troubleshooting/ts_filesystem_check.sh` | Filesystem health check |
| `troubleshooting/ts_user_accounts.sh` | User accounts and groups |
| `troubleshooting/ts_microsoft.sh` | Microsoft / Intune / DDM / Defender |
| `troubleshooting/ts_mdm_profiles.sh` | MDM enrollment and config profiles |
| `troubleshooting/ts_system_extensions.sh` | System and kernel extensions |
| `troubleshooting/ts_network.sh` | Network configuration |
| `troubleshooting/ts_keychain.sh` | Keychain and certificates |
| `troubleshooting/ts_installed_apps.sh` | Installed applications |
| `troubleshooting/ts_time_machine.sh` | Time Machine |

---

## Download & Verify

`11_download_verify.sh` provides tools for safely obtaining and validating macOS update packages without trusting the GUI reinstall path.

| Option | What it does |
|--------|-------------|
| Fetch installer | `softwareupdate --fetch-full-installer [--full-installer-version X.Y.Z]`; automatically computes SHA-256 of all payload files |
| Browse catalog | Downloads and parses Apple's sucatalog; lists macOS products with package URLs, sizes, SHA-1 digests, and `IntegrityDataURL` pointers |
| Download by URL | `curl`-downloads any package URL and prints SHA-256/SHA-1/MD5 |
| Hash a file | SHA-256, SHA-1, and MD5 for any local file |
| Compare hash | Computes SHA-256 and compares against a value you supply; clear MATCH/MISMATCH output |
| IntegrityData verify | Downloads Apple's chunk-level integrity plist and verifies each 1 MB chunk of a PKG against its SHA-256 — the same check the OS installer uses internally |
| Extract PKG | `pkgutil --expand` unpacks a `.pkg` with a tree listing |
| Mount DMG | `hdiutil attach` with unmount instructions |

Can also be called non-interactively:

```bash
bash 11_download_verify.sh hash /path/to/file.pkg
bash 11_download_verify.sh compare /path/to/file.pkg <expected-sha256>
bash 11_download_verify.sh catalog
bash 11_download_verify.sh fetch-installer 15.4.1
bash 11_download_verify.sh download <url> /tmp/pkg.pkg
bash 11_download_verify.sh extract /tmp/pkg.pkg /tmp/out
bash 11_download_verify.sh mount /tmp/image.dmg
bash 11_download_verify.sh integrity /tmp/pkg.pkg <integrity-data-url>
```

---

## Logging

All scripts log to `/tmp/mac_recovery.log`. Use option `l` in the main menu to tail the log, or:

```bash
tail -f /tmp/mac_recovery.log
```

---

## If you're still looping back to Recovery

1. **Disk repair first** — run option 5 (`fsck_apfs`). Filesystem corruption is a common cause.
2. **Install updates via terminal** — option `u` runs `softwareupdate` directly, bypassing the GUI.
3. **Reset NVRAM** — option 6 → reset NVRAM, then reboot.
4. **Apple Silicon startup disk** — hold Power → Options → select the startup disk explicitly.
5. **Manual NVRAM reset** — hold Cmd+Opt+P+R at startup until you hear the chime twice (Intel) or see the Apple logo twice (Apple Silicon).
