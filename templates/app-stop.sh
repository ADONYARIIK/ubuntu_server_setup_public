# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# Stop the containers; data and containers stay (start again: app-start)

"${COMPOSE[@]}" stop
