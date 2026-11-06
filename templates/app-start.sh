# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# Start the containers (images are built only if missing; to update the code: app-deploy)

usage="Usage: sudo app-start

Start the app's containers (docker compose up -d).
Images are built only if they are missing: to get new code, use sudo app-deploy."
no_args "$usage" "$@"

"${COMPOSE[@]}" up -d
