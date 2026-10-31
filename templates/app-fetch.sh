# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# Refresh the list of branches from GitHub and show what is deployed now.
# Allowed on production too: it only updates refs/remotes/*, the code is not touched

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