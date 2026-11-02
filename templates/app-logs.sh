# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# Last log lines of every container:
#   sudo app-logs        APP_LOGS_TAIL lines (setup.sh)
#   sudo app-logs 1000   1000 lines, at most APP_LOGS_MAX
# The sudo rule lets through one argument made of digits only; the range is checked here

if [ "$#" -gt 1 ]; then
    echo "Usage: sudo app-logs [LINES]" >&2
    exit 1
fi

lines="${1:-$APP_LOGS_TAIL}"

# At most 7 digits before the numeric comparison: a huge number would make "[" fail
# with an error instead of saying "too big"
if ! [[ "$lines" =~ ^[1-9][0-9]{0,6}$ ]] || [ "$lines" -gt "$APP_LOGS_MAX" ]; then
    echo "LINES must be a number from 1 to ${APP_LOGS_MAX} (default: ${APP_LOGS_TAIL}), got: ${lines}" >&2
    exit 1
fi

"${COMPOSE[@]}" logs --tail="$lines"
