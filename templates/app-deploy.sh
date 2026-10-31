# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# Update code, rebuild images, recreate containers, run migrations, rebuild caches

take_lock

deploy
