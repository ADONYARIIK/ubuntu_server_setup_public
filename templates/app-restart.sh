# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# Restart the running containers with their current settings.
# A changed .env or compose file needs app-start / app-deploy (they recreate containers)

usage="Usage: sudo app-restart

Restart the running containers with their current settings.
A changed ${ENV_FILE} or compose file is NOT picked up: use sudo app-start
or sudo app-deploy, they recreate the containers."
no_args "$usage" "$@"

"${COMPOSE[@]}" restart
