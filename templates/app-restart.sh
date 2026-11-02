# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# Restart the running containers with their current settings.
# A changed .env or compose file needs app-start / app-deploy (they recreate containers)

"${COMPOSE[@]}" restart
