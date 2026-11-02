# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# Download the models of languages added to ENV_TRANSLATE_LANGUAGES
# (LibreTranslate: LIBRETRANSLATE_LANGUAGES) in .env, and newer versions of the models
# already there. The service normally starts with ENV_TRANSLATE_UPDATE_MODELS
# (LIBRETRANSLATE_UPDATE_MODELS) = false, so a newly added language is silently missing
# until this runs. Afterwards the service is started again with updates off: otherwise
# any later restart (reboot, crash) would quietly fetch new models and change the translations

take_lock

echo "Starting ${TRANSLATE_SERVICE} with model updates on. The download can take several minutes..."
# For ${...} in the compose file a variable of the shell wins over the same one in .env.
# "env" is needed: "${NAME}=true cmd" is not an assignment, bash would look for a command.
# A value that comes from "env_file:" is NOT overridden this way
env "${ENV_TRANSLATE_UPDATE_MODELS}"=true "${COMPOSE[@]}" up -d --wait --wait-timeout 1800 "$TRANSLATE_SERVICE"

echo "Models are up to date. Restarting ${TRANSLATE_SERVICE} with updates off..."
"${COMPOSE[@]}" up -d --wait --wait-timeout 600 "$TRANSLATE_SERVICE"

echo "Done: ${TRANSLATE_SERVICE} runs with every language from ${ENV_TRANSLATE_LANGUAGES} in ${ENV_FILE}"
