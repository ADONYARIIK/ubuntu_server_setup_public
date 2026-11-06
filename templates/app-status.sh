# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# State of the containers: running, healthy, exited

usage="Usage: sudo app-status

Show the state of the app's containers: running, healthy, exited."
no_args "$usage" "$@"

"${COMPOSE[@]}" ps
