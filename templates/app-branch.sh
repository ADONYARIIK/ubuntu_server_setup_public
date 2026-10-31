# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# Interactive (sudo rules allow NO arguments): pick a branch from a numbered list.
# Only branches that really exist on GitHub can be chosen

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
if [ -f "$ENV_FILE" ] && [ -f "$ENV_EXAMPLE" ]; then
    mapfile -t missing < <(comm -23 \
        <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_EXAMPLE" | tr -d '=' | sort -u) \
        <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" | tr -d '=' | sort -u))
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "WARNING: $ENV_EXAMPLE of this branch has variables missing in $ENV_FILE (ask an admin to add them):"
        printf '  %s\n' "${missing[@]}"
    fi
fi

deploy

echo
echo "Done. Branch '$branch' is running. Back to the main branch: sudo app-branch -> $REPO_BRANCH"