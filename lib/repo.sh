# shellcheck shell=bash
# repo.sh - clone the project into APP_DIR: owned by root,
# readable by every user, writable only by root (changes come via git + app-deploy)

# _ensure_deploy_key - create root's GitHub deploy key once and trust github.com
_ensure_deploy_key() {
    install -d -m 0700 /root/.ssh
    
    if [ -f "$DEPLOY_KEY" ]; then
        log "Deploy key already exists: $DEPLOY_KEY"
    else
        ssh-keygen -t ed25519 -N "" -C "deploy@$(hostname)" -f "$DEPLOY_KEY" >> "$LOG_FILE" 2>&1
        warn "New deploy key created. Add it to GitHub: repo -> Settings -> Deploy keys:"
        warn "$(cat "${DEPLOY_KEY}.pub")"
    fi
    
    # Without a known_hosts entry the first ssh connection asks "yes/no" and hangs
    if ! ssh-keygen -F github.com -f /root/.ssh/known_hosts &>/dev/null; then
        ssh-keyscan -t ed25519 github.com >> /root/.ssh/known_hosts 2>/dev/null
        log "Added github.com to root's known_hosts"
    fi
}

# setup_app_repo - clone REPO_URL into APP_DIR if it is not there yet.
# If the clone fails (deploy key not added to GitHub yet) it only warns:
# add the key and re-run setup.sh
setup_app_repo() {
    install_packages git
    
    # Lets other users run read-only git commands (git log, git status) in the
    # root-owned repo; without it git refuses with "dubious ownership"
    if ! git config --system --get-all safe.directory 2>/dev/null | grep -qxF -- "$APP_DIR"; then
        git config --system --add safe.directory "$APP_DIR"
        log "Marked as safe git directory: $APP_DIR"
    fi
    
    _ensure_deploy_key
    
    if [ -d "${APP_DIR}/.git" ]; then
        log "Repository already cloned: $APP_DIR"
        return 0
    fi
    
    if [ -d "$APP_DIR" ] && [ -n "$(ls -A "$APP_DIR")" ]; then
        error "$APP_DIR exists, is not empty and is not a git repo - not touching it"
        return 1
    fi
    
    log "Cloning $REPO_URL ($REPO_BRANCH) into $APP_DIR"
    if GIT_SSH_COMMAND="ssh -i ${DEPLOY_KEY} -o IdentitiesOnly=yes" \
        git clone --branch "$REPO_BRANCH" "$REPO_URL" "$APP_DIR" >> "$LOG_FILE" 2>&1; then
        # Later "git pull" (app-deploy) uses the same deploy key automatically
        git -C "$APP_DIR" config core.sshCommand "ssh -i ${DEPLOY_KEY} -o IdentitiesOnly=yes"
        log "Repository cloned: $APP_DIR"
    else
        warn "Clone failed. Add the deploy key above to GitHub and re-run setup.sh"
    fi
}