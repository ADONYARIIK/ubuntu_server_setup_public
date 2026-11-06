# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# Update code, rebuild images, recreate containers, run migrations, rebuild caches

usage="Usage: sudo app-deploy

Deploy the newest code of the current branch:
git pull -> build the images -> recreate the containers -> migrate --force -> optimize.
Production server: always switches back to ${REPO_BRANCH} first.
If another deploy is running right now, it stops with a message instead."
no_args "$usage" "$@"

take_lock

deploy
