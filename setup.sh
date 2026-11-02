#!/bin/bash
# setup.sh - Ubuntu server base configuration
# Requires: Ubuntu 24.04+ (tested target: 24.04), must be run as root
# Log: /var/log/server_setup_<date>_<time>.log (one file per run)


# Version: 1.2.0
# Usage: sudo ./setup.sh

set -euo pipefail

# Never let apt/needrestart stop to ask a question: output goes to the log,
# so the prompt would be invisible and the script would just hang
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a

# Script metadata
# Keep in sync with "Version:" in the header
SCRIPT_VERSION="1.2.0"
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
# Ports UFW opens besides SSH. Ports published by Docker ("ports:") bypass UFW
# anyway; these rules matter for servers listening on the host itself.
# Empty when the app is reached only through an outbound tunnel (e.g. Cloudflare Tunnel)
FIREWALL_PORTS=(80/tcp 443/tcp)
# Full sudo, never get the restricted script rules. Each one must have keys/<name>.pub
# (or an existing account with authorized_keys, like the one made by the installer)
ADMIN_USERS=("admin")
# Group that marks team users created from keys/*.pub. Only its members are
# deleted when their key file disappears (see remove_stale_users)
TEAM_GROUP="team"
# Server timezone (affects log timestamps and cron)
TIMEZONE="Europe/Warsaw"
# Where the project lives (git repo with compose files)
APP_DIR="/srv/app"
# Compose files, paths inside APP_DIR (e.g. "backend/compose.prod.yaml").
# IS_PRODUCTION picks the one the app-* scripts use; an empty COMPOSE_FILE_DEV means
# the test server runs COMPOSE_FILE_PROD too. Relative paths in the file
# (build context, env_file, volumes) and its .env are taken from the file's own directory
COMPOSE_FILE_PROD="compose.prod.yaml"
COMPOSE_FILE_DEV=""
# Name of the Laravel service in the compose files (used for artisan commands)
APP_SERVICE="app"
# Database service (PostgreSQL, MySQL or MariaDB image), used by the admin script app-db
DB_SERVICE="pgsql"
# Translate service (e.g. LibreTranslate): adds app-update-languages for the team.
# Empty = no such script
TRANSLATE_SERVICE=""
# Names of the variables app-update-languages works with (LibreTranslate's by default):
# the on/off switch for model downloads it sets for one run (the compose file must use it
# as ${...} in "environment:"), and the language list in .env it mentions in its output
ENV_TRANSLATE_UPDATE_MODELS="LIBRETRANSLATE_UPDATE_MODELS"
ENV_TRANSLATE_LANGUAGES="LIBRETRANSLATE_LANGUAGES"
# Scripts every team member (keys/*.pub except ADMIN_USERS) may run with sudo
# app-branch (IS_PRODUCTION=false) and app-update-languages (TRANSLATE_SERVICE
# set) are added automatically
APP_SCRIPTS=(app-start app-stop app-restart app-status app-logs app-deploy app-fetch)
# Scripts for ADMIN_USERS only (templates/<name>.sh). They are not in the team's sudo
# rules and cannot even be read by the team; an admin runs them without "sudo",
# they ask for the password themselves
ADMIN_SCRIPTS=(app-db)
# app-logs: lines shown by "sudo app-logs" and the most "sudo app-logs <N>" may ask for
APP_LOGS_TAIL=200
APP_LOGS_MAX=5000
# Test server only (IS_PRODUCTION=false): ports on the server's 127.0.0.1 users may
# reach through "ssh -L", e.g. (8025 9001) for Mailpit and a storage console published
# as "127.0.0.1:8025:8025" in the compose file. Empty = no forwarding, as on production
TUNNEL_PORTS=()
# Git repository of the project (SSH URL, cloned with a read-only deploy key)
REPO_URL="git@github.com:USER/REPO.git"
REPO_BRANCH="main"
# Private key root uses to pull from GitHub (add the .pub as a Deploy key)
DEPLOY_KEY="/root/.ssh/deploy_key"
# The project's .env and its template, paths inside APP_DIR
# (e.g. "backend/.env" and "backend/.env.example" if Laravel is in a subfolder).
# ENV_EXAMPLE is copied to ENV_FILE once, right after the clone;
# an existing ENV_FILE is never overwritten
ENV_EXAMPLE=".env.example"
ENV_FILE=".env"

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

    # Renamed in 1.2.0: an old setup.sh would otherwise silently run compose.prod.yaml
    if [ -n "${COMPOSE_FILE:-}" ]; then
        error "COMPOSE_FILE was renamed to COMPOSE_FILE_PROD (and COMPOSE_FILE_DEV for a test server), see the changelog"
        exit 1
    fi

    # Checked before anything on the server is changed: a typo ("True", "yes")
    # must not silently pick a mode
    case "$IS_PRODUCTION" in
        true) COMPOSE_FILE="$COMPOSE_FILE_PROD"
              log "Mode: PRODUCTION (only ${REPO_BRANCH}, no app-branch, ${COMPOSE_FILE})" ;;
        false) COMPOSE_FILE="${COMPOSE_FILE_DEV:-$COMPOSE_FILE_PROD}"
               log "Mode: TEST (team can switch branches with app-branch, ${COMPOSE_FILE})"
               APP_SCRIPTS+=(app-branch) ;;
        *) error "IS_PRODUCTION must be true or false, got: '${IS_PRODUCTION}'"
               exit 1 ;;
    esac

    if [ -n "$TRANSLATE_SERVICE" ]; then
        APP_SCRIPTS+=(app-update-languages)
    fi

    # Paths inside APP_DIR: they are joined to it ("${APP_DIR}/${path}"), so an absolute
    # "/srv/app/backend/.env" would become "/srv/app//srv/app/backend/.env" (and .env would
    # silently stay unprotected), ".." could point outside the project, and an empty path
    # would point at APP_DIR itself. ${!name} = the value of the variable named in $name,
    # so the error says which setting is wrong
    local name path
    for name in COMPOSE_FILE_PROD COMPOSE_FILE_DEV ENV_EXAMPLE ENV_FILE; do
        path="${!name}"
        case "$path" in
            "")
                # Empty COMPOSE_FILE_DEV = the test server uses COMPOSE_FILE_PROD
                if [ "$name" = COMPOSE_FILE_DEV ]; then continue; fi
                error "${name} must not be empty"
                exit 1 ;;
            /*|..|../*|*/..|*/../*)
                error "${name} must be a path inside APP_DIR (like backend/compose.prod.yaml or backend/.env), got: '${path}'"
                exit 1 ;;
        esac
    done

    # Baked into app-logs; a typo would only show up when someone runs it
    if ! [[ "$APP_LOGS_TAIL" =~ ^[1-9][0-9]*$ && "$APP_LOGS_MAX" =~ ^[1-9][0-9]*$ ]] \
        || [ "$APP_LOGS_TAIL" -gt "$APP_LOGS_MAX" ]; then
        error "APP_LOGS_TAIL and APP_LOGS_MAX must be positive numbers, TAIL <= MAX, got: ${APP_LOGS_TAIL} / ${APP_LOGS_MAX}"
        exit 1
    fi

    # Written into sshd's config: a bad value fails "sshd -t" in the middle of the run
    local port
    for port in "${TUNNEL_PORTS[@]}"; do
        if ! [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] || [ "$port" -gt 65535 ]; then
            error "TUNNEL_PORTS must be port numbers (1-65535), got: '${port}'"
            exit 1
        fi
    done

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
    configure_firewall "${FIREWALL_PORTS[@]}"
    
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
    if [ -d "${APP_DIR}/.git" ] && [ ! -f "${APP_DIR}/${COMPOSE_FILE}" ]; then
        warn "${APP_DIR}/${COMPOSE_FILE} not found on branch $(git -C "$APP_DIR" branch --show-current) - the app-* commands will fail"
    fi
    
    # Root-owned scripts in /usr/local/bin: the only way team members touch Docker
    log "=== Creating App Management Scripts ==="
    create_app_scripts
    
    log "=== Granting Team Access To Scripts ==="
    grant_scripts_to_team "${APP_SCRIPTS[@]}"
    
    # Need the sudo group membership given by setup_admins
    log "=== Creating Admin Scripts ==="
    create_admin_scripts
    
    log "=== Manual steps (only once) ==="
    log "1. sudo tailscale up  (authorize the server in Tailscale)"
    log "2. If the clone failed: add root's deploy key to GitHub and re-run setup.sh"
    log "3. Fill in ${APP_DIR}/${ENV_FILE} (created from ${ENV_EXAMPLE}): sudo vim ${APP_DIR}/${ENV_FILE}"
    log "4. First start: sudo app-deploy"
}

main "$@"
