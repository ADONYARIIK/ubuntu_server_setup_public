# shellcheck shell=bash
# common.sh - shared helpers: colored logging, exit handler, root check, run lock

# ANSI escape codes (\033 = ESC); NC = "no color", resets the color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging functions
# log MESSAGE - print an info message and append it to $LOG_FILE
log() {
    local message="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${GREEN}[${timestamp}] ${message}${NC}" | tee -a "$LOG_FILE"
}

# warn MESSAGE - non-fatal problem, script continues
warn() {
    local message="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${YELLOW}[${timestamp}] WARNING: ${message}${NC}" | tee -a "$LOG_FILE"
}

# error MESSAGE - only prints the message; the caller decides whether to exit
error() {
    local message="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${RED}[${timestamp}] ERROR: ${message}${NC}" | tee -a "$LOG_FILE"
}

# Exit handler
# Registered with "trap cleanup EXIT" in setup.sh.
# "local exit_code=$?" must stay the FIRST line, otherwise $? gets overwritten
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Script failed with exit code: $exit_code"
        error "Check log file: $LOG_FILE"
    else
        log "Script completed successfully"
    fi
}

# Root check
require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root" >&2
        exit 1
    fi
}

# Lock to prevent concurrent runs (flock on file descriptor 9).
# The kernel releases the lock when the process exits, even after kill -9,
# so the lock file never has to be deleted
acquire_lock() {
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        error "Another instance is running (lock file: $LOCK_FILE)"
        exit 1
    fi
}
