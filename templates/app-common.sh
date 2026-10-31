# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# Exit if another app-deploy/app-fetch/app-branch is running right now
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

    if [ -f .env ]; then chmod 600 .env; fi

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