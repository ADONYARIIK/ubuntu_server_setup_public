# shellcheck shell=bash
# app.sh - management scripts for the docker compose project

# One lock for every script that changes the code or the containers
# (app-deploy, app-fetch, app-branch, app-update-languages): two people deploying
# at the same time would mix up checkouts and builds
APP_LOCK="/run/app-scripts.lock"

# Bodies of all app-* and admin scripts: normal .sh files, so the editor,
# bash -n and shellcheck see the code (inside a heredoc it is just text)
APP_TEMPLATES="$SCRIPT_DIR/templates"

# First lines of every admin script: a non-root admin is re-run through sudo
# (asks for the admin's password), so "app-db" works without typing "sudo"
# shellcheck disable=SC2016 # $0 / $@ must stay literal: they belong to the generated script
ADMIN_ELEVATE='if [ "$(id -u)" -ne 0 ]; then exec sudo -- "$0" "$@"; fi'

# _app_script_header - settings baked into the generated scripts at setup time.
# printf %q quotes every value, so paths with spaces etc. cannot break the script.
# --project-directory = the compose file's own directory: compose resolves the build
# context, env_file, volumes and reads .env (for ${VAR} in the file) from there
_app_script_header() {
    local compose_path="${APP_DIR}/${COMPOSE_FILE}"

    printf 'APP_DIR=%q\n' "$APP_DIR"
    printf 'REPO_BRANCH=%q\n' "$REPO_BRANCH"
    printf 'IS_PRODUCTION=%q\n' "$IS_PRODUCTION"
    printf 'ENV_EXAMPLE=%q\n' "$ENV_EXAMPLE"
    printf 'ENV_FILE=%q\n' "$ENV_FILE"
    printf 'APP_SERVICE=%q\n' "$APP_SERVICE"
    printf 'DB_SERVICE=%q\n' "$DB_SERVICE"
    printf 'TRANSLATE_SERVICE=%q\n' "$TRANSLATE_SERVICE"
    printf 'ENV_TRANSLATE_UPDATE_MODELS=%q\n' "$ENV_TRANSLATE_UPDATE_MODELS"
    printf 'ENV_TRANSLATE_LANGUAGES=%q\n' "$ENV_TRANSLATE_LANGUAGES"
    printf 'APP_LOGS_TAIL=%q\n' "$APP_LOGS_TAIL"
    printf 'APP_LOGS_MAX=%q\n' "$APP_LOGS_MAX"
    printf 'APP_LOCK=%q\n' "$APP_LOCK"
    printf 'COMPOSE=(docker compose -f %q --project-directory %q)\n' \
        "$compose_path" "$(dirname "$compose_path")"
}

# _build_script NAME [PREFIX] - print the full body of script NAME:
# PREFIX + generated header + templates/app-common.sh + templates/NAME.sh.
# A missing template makes this function fail; callers must assign its output
# to a variable first (see create_app_scripts) so set -e stops setup
_build_script() {
    local name="$1"
    local prefix="${2:-}"
    local header common body

    # "|| return 1" is required: this function runs inside "$(...)", and there
    # bash turns set -e off, so a failed cat would NOT stop it by itself
    header="$(_app_script_header)" || return 1
    common="$(cat "$APP_TEMPLATES/app-common.sh")" || return 1
    body="$(cat "$APP_TEMPLATES/${name}.sh")" || return 1

    if [ -n "$prefix" ]; then
        printf '%s\n\n' "$prefix"
    fi
    printf '%s\n\n%s\n\n%s\n' "$header" "$common" "$body"
}

# create_app_scripts - install the team's app-* scripts into /usr/local/bin
# (every name in APP_SCRIPTS has a templates/<name>.sh)
create_app_scripts() {
    local name script

    for name in "${APP_SCRIPTS[@]}"; do
        # Separate assignment on purpose: with "$(...)" written directly in the
        # create_script call a missing template would NOT stop setup (set -e ignores it),
        # the script would just be installed without its body
        script="$(_build_script "$name")"
        create_script "$name" "$script"
    done

    # "sudo app-logs 1000": the only script whose sudo rule allows arguments.
    # '*' because sudo-rs has no patterns inside arguments; templates/app-logs.sh
    # accepts exactly one number and refuses everything else.
    # shellcheck disable=SC2034,SC2154 # associative array declared in scripts.sh
    SCRIPT_ARGS[app-logs]='*'

    # Turned off by a setting: the file is deleted, and grant_scripts_to_team
    # (called after this) drops its sudo rule
    if [ "$IS_PRODUCTION" = true ]; then
        remove_script app-branch
    fi
    if [ -z "$TRANSLATE_SERVICE" ]; then
        remove_script app-update-languages
    fi
}

# create_admin_scripts - install ADMIN_SCRIPTS into /usr/local/bin as root:sudo 0750:
# only members of the sudo group (ADMIN_USERS) can run or even read them
create_admin_scripts() {
    local name script

    for name in "${ADMIN_SCRIPTS[@]}"; do
        script="$(_build_script "$name" "$ADMIN_ELEVATE")"
        create_script "$name" "$script" 0750 sudo
    done
}
