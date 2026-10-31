#!/bin/bash
# setup.sh - Ubuntu server base configuration
# Requires: Ubuntu 24.04+ (tested target: 24.04), must be run as root
# Log: /var/log/server_setup_<date>_<time>.log (one file per run)


# Version: 1.1.0
# Usage: sudo ./setup.sh

set -euo pipefail

# Never let apt/needrestart stop to ask a question: output goes to the log,
# so the prompt would be invisible and the script would just hang
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a

# Script metadata
# Keep in sync with "Version:" in the header
SCRIPT_VERSION="1.1.0"
# Absolute path of the directory with this script, so lib/ is found from any cwd
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/server_setup_$(date +%Y%m%d_%H%M%S).log"
# Prevents two copies of the script from running at the same time
LOCK_FILE="/var/run/server_setup.lock"

# ===== Settings =====
# true  = production server: always runs REPO_BRANCH, the branch switch script
#         (app-branch) does not exist on the server at all
# false = test server: team members can switch branches with "sudo app-branch"
#         to test a feature branch before it is merged into REPO_BRANCH
IS_PRODUCTION=true
# Used by ssh.sh and firewall.sh: change the SSH port only here
SSH_PORT=22
# Full sudo, never get the restricted script rules. Each one must have keys/<name>.pub
# (or an existing account with authorized_keys, like the one made by the installer)
ADMIN_USERS=("admin")
# Group that marks team users created from keys/*.pub. Only its members are
# deleted when their key file disappears (see remove_stale_users)
TEAM_GROUP="team"
# Server timezone (affects log timestamps and cron)
TIMEZONE="Europe/Warsaw"
# Where the production project lives (git repo with compose.prod.yaml)
APP_DIR="/srv/app"
COMPOSE_FILE="compose.prod.yaml"
# Name of the Laravel service in compose.prod.yaml (used for artisan commands)
APP_SERVICE="app"
# Scripts every team member (keys/*.pub except ADMIN_USERS) may run with sudo
# app-branch is added automatically when IS_PRODUCTION=false
APP_SCRIPTS=(app-start app-stop app-restart app-status app-logs app-deploy app-fetch)
# Git repository of the project (SSH URL, cloned with a read-only deploy key)
REPO_URL="git@github.com:USER/REPO.git"
REPO_BRANCH="main"
# Private key root uses to pull from GitHub (add the .pub as a Deploy key)
DEPLOY_KEY="/root/.ssh/deploy_key"
# Template for the project's .env (path inside APP_DIR). Copied to .env once,
# right after the clone; an existing .env is never overwritten
ENV_EXAMPLE=".env.example"

# Load common.sh first: every other module uses log/warn/error from it
source "$SCRIPT_DIR"/lib/common.sh
for f in "$SCRIPT_DIR"/lib/*.sh; do
    [ "$f" = "$SCRIPT_DIR/lib/common.sh" ] && continue
    source "$f"
done

require_root
acquire_lock
# Always run cleanup on exit: print the final status
trap cleanup EXIT

# Configurations
main() {
    log "=== Server Setup Script v${SCRIPT_VERSION} ==="
    
    # Checked first: a typo ("True", "yes") must not silently pick a mode
    case "$IS_PRODUCTION" in
        true) log "Mode: PRODUCTION (only ${REPO_BRANCH}, no app-branch)" ;;
        false) log "Mode: TEST (team can switch branches with app-branch)"
               APP_SCRIPTS+=(app-branch) ;;
        *) error "IS_PRODUCTION must be true or false, got: '${IS_PRODUCTION}'"
               exit 1 ;;
    esac

    # Fresh server: unattended-upgrades holds the dpkg lock right after boot.
    # apt-get install/remove (also inside the Tailscale installer) wait instead of failing
    write_config /etc/apt/apt.conf.d/90lock-timeout 'DPkg::Lock::Timeout "600";'

    log "=== Refresh Package List ==="
    apt_update
    
    log "=== Install Tools From Packages ==="
    install_packages curl wget vim htop tmux git unzip jq fail2ban ufw tree
    
    # Format: "<command>=<installer URL>", skipped if <command> is already in PATH
    log "=== Install Tools That Are Not In Package Lists ==="
    # Tailscale still needs to be authorized manually: sudo tailscale up
    install_from_script \
    "spf=https://superfile.dev/install.sh" \
    "tailscale=https://tailscale.com/install.sh"
    
    log "=== Base System Settings ==="
    configure_timezone "$TIMEZONE"
    configure_auto_updates
    
    # Keep the laptop running with the lid closed, disable all sleep modes
    log "=== Configuring Laptop For Work As Server ==="
    configure_laptop_server
    
    log "=== Deploying Team SSH Keys ==="
    setup_team_users
    
    # Team users whose keys/<name>.pub was deleted lose their account (admins and system users are kept)
    log "=== Removing Users Without Keys ==="
    remove_stale_users
    
    log "=== Configuring Admins ==="
    setup_admins
    
    log "=== Checking Admin SSH Keys ==="
    ensure_admin_keys
    
    # Key-only SSH login, no root login
    log "=== Configuring SSH ==="
    configure_sshd
    
    # SSH is always allowed (LAN + Tailscale); arguments = extra ports
    log "=== Configuring Firewall ==="
    configure_firewall 80/tcp 443/tcp
    
    # Bans IPs after repeated failed SSH logins (sshd jail is on by default in Ubuntu)
    log "=== Enabling fail2ban ==="
    systemctl enable --now fail2ban >> "$LOG_FILE" 2>&1
    
    log "=== Install Docker ==="
    install_docker
    configure_docker_daemon
    # Admin already has full sudo, so the docker group adds no extra risk here
    for admin in "${ADMIN_USERS[@]}"; do
        add_to_group "$admin" docker
    done
    
    # Needs team users to exist
    log "=== Setting Up App Repository ==="
    setup_app_repo
    
    # Root-owned scripts in /usr/local/bin: the only way team members touch Docker
    log "=== Creating App Management Scripts ==="
    create_app_scripts
    
    log "=== Granting Team Access To Scripts ==="
    grant_scripts_to_team "${APP_SCRIPTS[@]}"
    
    log "=== Manual steps (only once) ==="
    log "1. sudo tailscale up  (authorize the server in Tailscale)"
    log "2. If the clone failed: add root's deploy key to GitHub and re-run setup.sh"
    log "3. Fill in ${APP_DIR}/.env (created from ${ENV_EXAMPLE}): sudo vim ${APP_DIR}/.env"
    log "4. First start: sudo app-deploy"
}

main "$@"
