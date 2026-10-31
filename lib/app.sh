# shellcheck shell=bash
# app.sh - management scripts for the docker compose project

# One lock for every script that changes the code or the containers
# (app-deploy, app-fetch, app-branch): two people deploying at the same time
# would mix up checkouts and builds
APP_LOCK="/run/app-scripts.lock"

# Bodies of app-deploy / app-fetch / app-branch: normal .sh files, so the editor,
# bash -n and shellcheck see the code (inside a heredoc it is just text)
APP_TEMPLATES="$SCRIPT_DIR/templates"

# _app_script_header - settings baked into the generated scripts at setup time.
# printf %q quotes every value, so paths with spaces etc. cannot break the script
_app_script_header() {
    printf 'APP_DIR=%q\n' "$APP_DIR"
    printf 'REPO_BRANCH=%q\n' "$REPO_BRANCH"
    printf 'IS_PRODUCTION=%q\n' "$IS_PRODUCTION"
    printf 'ENV_EXAMPLE=%q\n' "$ENV_EXAMPLE"
    printf 'APP_SERVICE=%q\n' "$APP_SERVICE"
    printf 'APP_LOCK=%q\n' "$APP_LOCK"
    printf 'COMPOSE=(docker compose -f %q --project-directory %q)\n' \
        "${APP_DIR}/${COMPOSE_FILE}" "$APP_DIR"
}

# create_app_scripts - install app-* scripts into /usr/local/bin.
# Each script = generated header + templates/app-common.sh + templates/<name>.sh.
create_app_scripts() {
    local compose="docker compose -f ${APP_DIR}/${COMPOSE_FILE} --project-directory ${APP_DIR}"
    local header common body name
    local scripts=(app-deploy app-fetch)

    create_script app-start "${compose} up -d"
    create_script app-stop "${compose} stop"
    create_script app-restart "${compose} restart"
    create_script app-status "${compose} ps"
    create_script app-logs "${compose} logs --tail=200"

    # Branch switching only on test servers
    if [ "$IS_PRODUCTION" = false ]; then
        scripts+=(app-branch)
    fi

    # Separate assignments on purpose: with "$(cat ...)" written directly in the
    # create_script call a missing template would NOT stop setup (set -e ignores it),
    # the script would just be installed without its body
    header="$(_app_script_header)"
    common="$(cat "$APP_TEMPLATES/app-common.sh")"

    for name in "${scripts[@]}"; do
        body="$(cat "$APP_TEMPLATES/${name}.sh")"
        create_script "$name" "${header}

${common}

${body}"
    done

    # On production the file is deleted, and grant_scripts_to_team
    # (called after this) drops its sudo rule
    if [ "$IS_PRODUCTION" = true ]; then
        remove_script app-branch
    fi
}
