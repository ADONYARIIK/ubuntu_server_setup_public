# shellcheck shell=bash

# Create a user if they do not already exist
# create_service_user NAME [HOME] [SHELL] - system account to run a service under
# (--system: UID < 1000, no password, hidden from the login screen)
create_service_user() {
    local username="$1"
    local home_dir="${2:-/home/$username}"
    local shell="${3:-/usr/sbin/nologin}"
    
    if id "$username" &>/dev/null; then
        log "User already exists: $username"
        return 0
    fi
    
    useradd \
    --create-home \
    --home-dir "$home_dir" \
    --shell "$shell" \
    --system \
    "$username"
    
    log "Created user: $username"
}

# is_admin USER - returns 0 if USER is listed in ADMIN_USERS
is_admin() {
    local u

    for u in "${ADMIN_USERS[@]}"; do
        [ "$u" = "$1" ] && return 0
    done

    return 1
}

# setup_admins - give every ADMIN_USERS member full sudo and remove
# leftover restricted script rules (e.g. after promoting a team member)
setup_admins() {
    local user status

    for user in "${ADMIN_USERS[@]}"; do
        if ! id "$user" &>/dev/null; then
            error "Admin user does not exist: $user (add keys/${user}.pub)"
            return 1
        fi

        add_to_group "$user" sudo
        revoke_script_access "$user"

        # sudo asks for the USER's password; team users are created without one
        status="$(passwd -S "$user" | awk '{print $2}')"

        if [ "$status" != "P" ]; then
            warn "Admin $user has no password, sudo will not work. Set it once: sudo passwd $user"
        fi
    done
}

# Add a user to group safely
# add_to_group USER GROUP - no-op if USER is already a member.
# -a in "usermod -aG" is required: without it usermod REPLACES all supplementary groups
add_to_group() {
    local user="$1"
    local group="$2"
    
    if id -nG "$user" | tr ' ' '\n' | grep -qxF -- "$group"; then
        log "User $user already in group $group"
        return 0
    fi
    
    usermod -aG "$group" "$user"
    log "Added $user to group $group"
}

# Deploy SSH authorized keys for a user
# deploy_authorized_keys USER KEY - append KEY to ~USER/.ssh/authorized_keys if missing
deploy_authorized_keys() {
    local user="$1"
    local key="$2"
    local home_dir
    home_dir=$(getent passwd "$user" | cut -d: -f6) || true
    
    if [ -z "$home_dir" ]; then
        error "User does not exist: $user"
        return 1
    fi
    
    local user_group
    user_group=$(id -gn "$user")
    local ssh_dir="${home_dir}/.ssh"
    local auth_keys="${ssh_dir}/authorized_keys"
    
    # sshd ignores keys with loose permissions (StrictModes):
    # ~/.ssh must be 700, authorized_keys 600, both owned by the user
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    chown "$user:$user_group" "$ssh_dir"
    
    if [ -z "$key" ]; then
        error "Empty SSH key for $user"
        return 1
    fi
    
    if grep -qxF -- "$key" "$auth_keys" 2>/dev/null; then
        log "SSH key already present for $user"
    else
        echo "$key" >> "$auth_keys"
        log "Added SSH key for $user"
    fi
    
    chmod 600 "$auth_keys"
    chown "$user:$user_group" "$auth_keys"
}

# Create one user per keys/<username>.pub and install that key.
# The file name without ".pub" becomes the login name (lowercase only).
# Users get no password (--disabled-password): SSH key login only
setup_team_users() {
    local keyfile username

    if ! getent group "$TEAM_GROUP" &>/dev/null; then
        groupadd "$TEAM_GROUP"
        log "Created group: $TEAM_GROUP"
    fi

    for keyfile in "$SCRIPT_DIR"/keys/*.pub; do
        [ -e "$keyfile" ] || continue
        username="$(basename "$keyfile" .pub)"

        # adduser accepts only these names (NAME_REGEX); its own error is visible only in the log
        if ! [[ "$username" =~ ^[a-z][-a-z0-9_]*$ ]]; then
            error "Bad key file name: keys/${username}.pub (a-z, 0-9, - and _, must start with a letter)"
            return 1
        fi

        if ! id "$username" &>/dev/null; then
            adduser --disabled-password --comment "" "$username" >> "$LOG_FILE" 2>&1
            add_to_group "$username" "$TEAM_GROUP"
            log "Created user: $username"
        fi
        deploy_authorized_keys "$username" "$(cat "$keyfile")"
    done
}

# remove_stale_users - delete team members whose keys/<name>.pub was removed.
# Only members of TEAM_GROUP are considered (accounts this script created),
# so accounts made by the installer, packages or by hand are never touched.
# Extra guards, even for TEAM_GROUP members:
#   - ADMIN_USERS are never deleted
#   - system accounts (UID outside UID_MIN..UID_MAX from /etc/login.defs) are never deleted
#   - the admin running this script via sudo is never deleted
# The home directory is deleted together with the user (userdel --remove)
remove_stale_users() {
    local uid_min uid_max members username uid home_dir
    local keys_dir="$SCRIPT_DIR/keys"

    # No keys/ at all most likely means a broken checkout, not "remove everyone"
    if [ ! -d "$keys_dir" ]; then
        error "Directory not found: $keys_dir - refusing to remove users"
        return 1
    fi

    # 4th field of the group entry: comma-separated member list
    members="$(getent group "$TEAM_GROUP" | cut -d: -f4)" || true
    if [ -z "$members" ]; then
         log "No members in group $TEAM_GROUP, nothing to remove"
        return 0
    fi

    # Human accounts live in this UID range; Ubuntu defaults: 1000..60000
    uid_min="$(awk '$1 == "UID_MIN" {print $2}' /etc/login.defs)"
    uid_max="$(awk '$1 == "UID_MAX" {print $2}' /etc/login.defs)"
    uid_min="${uid_min:-1000}"
    uid_max="${uid_max:-60000}"

    for username in ${members//,/ }; do
        if [ -e "$keys_dir/${username}.pub" ]; then continue; fi

        uid="$(id -u "$username" 2>/dev/null)" || continue
        if [ "$uid" -lt "$uid_min" ] || [ "$uid" -gt "$uid_max" ]; then
            warn "Not removing $username: system account (UID $uid)"
            continue
        fi
        if is_admin "$username"; then
            warn "Not removing $username: listed in ADMIN_USERS"
            continue
        fi
        if [ "$username" = "${SUDO_USER:-}" ]; then
            warn "Not removing $username: this script is running as that user (via sudo)"
            continue
        fi

        log "Removing user without a key in keys/: $username"

        # Remove sudo rules first, so the user can do nothing while being deleted
        revoke_script_access "$username"

        # userdel refuses to delete a user that still has running processes (open SSH sessions etc.)
        if pgrep -u "$username" &>/dev/null; then
            loginctl terminate-user "$username" &>/dev/null || true
            pkill -KILL -u "$username" || true
            sleep 1
        fi

        home_dir="$(getent passwd "$username" | cut -d: -f6)" || true
        if [ -d "$home_dir" ]; then
            # 0700 dir + umask 077: home archives contain private files (keys, history)
            install -d -m 700 /var/backups/server_setup
            (umask 077; tar -czf "/var/backups/server_setup/home-${username}-$(date +%Y%m%d_%H%M%S).tar.gz" \
                -C "$(dirname "$home_dir")" "$(basename "$home_dir")")
        fi

        # --remove: also delete the home directory and mail spool
        if userdel --remove "$username" >> "$LOG_FILE" 2>&1; then
            log "Removed user: $username"
        else
            error "Failed to remove user: $username"
            return 1
        fi
    done 
}