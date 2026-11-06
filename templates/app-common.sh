# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# handle_help TEXT ARGS... - print TEXT and exit when the only argument is -h or --help.
# Every script calls it before any lock or docker command, so the help changes nothing
# and also works without sudo (the team scripts can be read and run by everyone)
handle_help() {
    local text="$1"
    shift
    if [ "$#" -eq 1 ] && { [ "$1" = --help ] || [ "$1" = -h ]; }; then
        printf '%s\n' "$text"
        exit 0
    fi
}

# no_args TEXT ARGS... - for the scripts that take no arguments: --help prints TEXT,
# anything else is refused (with sudo it never gets here: the sudo rules refuse it first)
no_args() {
    handle_help "$@"
    if [ "$#" -gt 1 ]; then
        printf 'Unknown argument: %s\n\n%s\n' "$2" "$1" >&2
        exit 1
    fi
}

# Exit if another app-deploy/app-fetch/app-branch/app-update-languages/app-seed is running right now
take_lock() {
    exec 9>"$APP_LOCK"
    if ! flock -n 9; then
        echo "Another app-deploy / app-fetch / app-branch is running. Try again later." >&2
        exit 1
    fi
}

# Branch names on GitHub, one per line (origin/HEAD is skipped)
remote_branches() {
    git -C "$APP_DIR" for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/ \
        | awk '$0 != "HEAD"'
}

# Update the code of the CURRENT branch, rebuild and restart the containers
deploy() {
    cd "$APP_DIR"

    # ENV_FILE is relative to APP_DIR (the current directory here)
    if [ -f "$ENV_FILE" ]; then chmod 600 "$ENV_FILE"; fi

    # Production always runs REPO_BRANCH, even if this server was a test server before
    if [ "$IS_PRODUCTION" = true ] && [ "$(git branch --show-current)" != "$REPO_BRANCH" ]; then
        echo "Production server: switching back to $REPO_BRANCH"
        git checkout --quiet "$REPO_BRANCH"
    fi

    git pull --ff-only
    "${COMPOSE[@]}" build
    "${COMPOSE[@]}" up -d --wait --remove-orphans
    "${COMPOSE[@]}" exec -T "$APP_SERVICE" php artisan migrate --force
    "${COMPOSE[@]}" exec -T "$APP_SERVICE" php artisan optimize
}
