#!/bin/bash
# Shared logging library — source this file at the top of each recovery script.
# Creates a timestamped log file at $LOG_FILE (default: /tmp/mac_recovery.log).
# In Recovery, /tmp is always writable as root.

LOG_FILE="${LOG_FILE:-/tmp/mac_recovery.log}"
LOG_SCRIPT="${LOG_SCRIPT:-$(basename "${BASH_SOURCE[1]:-unknown}")}"

_log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local line="[$ts] [$level] [$LOG_SCRIPT] $msg"
    echo "$line" >> "$LOG_FILE"
    case "$level" in
        ERROR) echo "ERROR: $msg" >&2 ;;
        WARN)  echo "WARNING: $msg" ;;
        *)     echo "$msg" ;;
    esac
}

log_info()  { _log INFO  "$@"; }
log_warn()  { _log WARN  "$@"; }
log_error() { _log ERROR "$@"; }

log_cmd() {
    # Run a command, log its output and exit code.
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [CMD]  [$LOG_SCRIPT] + $*" >> "$LOG_FILE"
    local output exit_code
    output=$("$@" 2>&1) && exit_code=0 || exit_code=$?
    if [[ -n "$output" ]]; then
        while IFS= read -r out_line; do
            echo "[$ts] [OUT]  [$LOG_SCRIPT] $out_line" >> "$LOG_FILE"
        done <<< "$output"
        echo "$output"
    fi
    if [[ $exit_code -ne 0 ]]; then
        echo "[$ts] [CMD]  [$LOG_SCRIPT] exited $exit_code" >> "$LOG_FILE"
    fi
    return $exit_code
}

log_section() {
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local sep="[$ts] [====] [$LOG_SCRIPT] === $* ==="
    echo "$sep" >> "$LOG_FILE"
    echo ""
    echo "=== $* ==="
}

log_start() {
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "" >> "$LOG_FILE"
    echo "[$ts] [START] [$LOG_SCRIPT] invoked as: $0 $*" >> "$LOG_FILE"
    echo "[$ts] [START] [$LOG_SCRIPT] log file: $LOG_FILE" >> "$LOG_FILE"
}

log_end() {
    local code="${1:-0}"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [END]  [$LOG_SCRIPT] exit code: $code" >> "$LOG_FILE"
}

# Print log file location once on source
echo "(logging to $LOG_FILE)"
