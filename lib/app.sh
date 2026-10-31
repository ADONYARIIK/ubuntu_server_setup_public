# shellcheck shell=bash
# app.sh - management scripts for the docker compose project

# One lock for every script that changes the code or the containers
# (app-deploy, app-fetch, app-branch): two people deploying at the same time
# would mix up checkouts and builds
APP_LOCK="/run/app-scripts.lock"

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

# _app_script_functions - runtime helpers shared by app-deploy / app-fetch / app-branch.
# Quoted heredoc ('EOF'): nothing here is expanded at setup time, the $variables
# are read when the installed script runs
_app_script_functions() {
    cat <<'EOF'

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
EOF
}

# create_app_scripts - install app-* scripts into /usr/local/bin.
# Values like ${APP_DIR} are substituted NOW (at setup time), so the
# installed scripts contain fixed paths and take no arguments
create_app_scripts(){
    local compose="docker compose -f ${APP_DIR}/${COMPOSE_FILE} --project-directory ${APP_DIR}"
    local common
    common="$(_app_script_header)$(_app_script_functions)"

    create_script app-start "${compose} up -d"
    create_script app-stop "${compose} stop"
    create_script app-restart "${compose} restart"
    create_script app-status "${compose} ps"
    create_script app-logs "${compose} logs --tail=200"
    
    # Update code, rebuild images, recreate containers, run migrations, rebuild caches
    create_script app-deploy "${common}

take_lock
deploy"

    # Refresh the list of branches from GitHub and show what is deployed now.
    # Allowed on production too: it only updates refs/remotes/*, the code is not touched
    create_script app-fetch "${common}
$(cat <<'EOF'

take_lock
cd "$APP_DIR"

# --prune: also forget branches that were deleted on GitHub
git fetch --prune origin

current="$(git branch --show-current)"
echo
echo "Current branch: ${current:-<detached HEAD>}"
echo "Branches on GitHub:"
while read -r branch; do
    if [ "$branch" = "$current" ]; then
        echo "  * $branch"
    else
        echo "    $branch"
    fi
done < <(remote_branches)

# How many new commits of the current branch are not deployed yet
if behind="$(git rev-list --count 'HEAD..@{upstream}' 2>/dev/null)" && [ "$behind" -gt 0 ]; then
    echo
    echo "$current is $behind commit(s) behind GitHub. Update it with: sudo app-deploy"
fi
EOF
)"

    # Branch switching only on test servers. On production the script is removed,
    # and grant_scripts_to_team (called after this) drops its sudo rule
    if [ "$IS_PRODUCTION" = true ]; then
        remove_script app-branch
        return 0
    fi

    # Interactive (sudo rules allow NO arguments): pick a branch from a numbered list.
    # Only branches that really exist on GitHub can be chosen
    create_script app-branch "${common}
$(cat <<'EOF'

take_lock
cd "$APP_DIR"

# The repo is changed only through git; local edits would be lost or block the checkout
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "Uncommitted changes in $APP_DIR - refusing to switch:" >&2
    git status --short --untracked-files=no >&2
    exit 1
fi

echo "Updating the branch list from GitHub..."
git fetch --prune --quiet origin

mapfile -t branches < <(remote_branches)
if [ "${#branches[@]}" -eq 0 ]; then
    echo "No branches found on GitHub" >&2
    exit 1
fi

current="$(git branch --show-current)"
echo
echo "Current branch: ${current:-<detached HEAD>}   (main branch: $REPO_BRANCH)"
echo

branch=""
PS3="Branch number (Ctrl+C to cancel): "
select choice in "${branches[@]}"; do
    if [ -n "$choice" ]; then
        branch="$choice"
        break
    fi
    echo "No such number, try again"
done

if [ -z "$branch" ]; then
    echo "Cancelled"
    exit 1
fi

# Second check: refuse anything git would not accept as a branch name (e.g. "-x")
if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
    echo "Invalid branch name: $branch" >&2
    exit 1
fi

read -r -p "Switch to '$branch' and redeploy (build, migrate)? [y/N] " answer
case "$answer" in
    y|Y|yes) ;;
    *) echo "Cancelled"; exit 1 ;;
esac

# -B: create the local branch or reset it to the GitHub version
# (also handles branches that were force-pushed). --track: later "git pull" in
# app-deploy pulls this branch
git checkout --quiet -B "$branch" --track "refs/remotes/origin/$branch"
echo "Now on branch: $branch ($(git log -1 --format='%h %s'))"

# The new branch may expect variables the current .env does not have.
# Only names are printed, never values
if [ -f .env ] && [ -f "$ENV_EXAMPLE" ]; then
    missing="$(comm -23 \
        <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_EXAMPLE" | tr -d '=' | sort -u) \
        <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' .env | tr -d '=' | sort -u))"
    if [ -n "$missing" ]; then
        echo "WARNING: $ENV_EXAMPLE of this branch has variables missing in .env (ask an admin to add them):"
        printf '  %s\n' $missing
    fi
fi

deploy

echo
echo "Done. Branch '$branch' is running. Back to the main branch: sudo app-branch -> $REPO_BRANCH"
EOF
)"
}
