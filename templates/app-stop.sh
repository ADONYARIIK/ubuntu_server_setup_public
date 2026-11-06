# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# Stop the containers; data and containers stay (start again: app-start)

usage="Usage: sudo app-stop

Stop the app's containers. The containers and the data stay:
start them again with sudo app-start."
no_args "$usage" "$@"

"${COMPOSE[@]}" stop
