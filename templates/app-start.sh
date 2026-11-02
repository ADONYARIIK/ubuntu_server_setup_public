# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# Start the containers (images are built only if missing; to update the code: app-deploy)

"${COMPOSE[@]}" up -d
