# shellcheck shell=bash
# scripts.sh - install admin helper scripts into /usr/local/bin and let
# specific users run them via sudo without a password

# Where managed scripts are installed (already in everyone's PATH)
SCRIPTS_BIN="/usr/local/bin"

# _install_file TMP TARGET MODE - internal helper: install TMP as TARGET
# (owner root:root, permissions MODE) unless TARGET is already identical.
# TMP is deleted in every case.
_install_file() {
    local tmp="$1"
    local target="$2"
    local mode="$3"
    
    if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
        log "Already up to date: $target"
        rm -f "$tmp"
        return 0
    fi
    
    install -m "$mode" -o root -g root "$tmp" "$target"
    rm -f "$tmp"
    log "Installed: $target"
}

# create_script NAME BODY - create /usr/local/bin/NAME from BODY
# (shebang and "set -euo pipefail" are added automatically)
# Example: create_script restart-app 'systemctl restart myapp'
create_script() {
    local name="$1"
    local body="$2"
    local tmp
    tmp="$(mktemp)"
    
    {
        echo '#!/bin/bash'
        echo 'set -euo pipefail'
        echo '# Managed by server-setup. Do not edit by hand.'
        echo
        printf '%s\n' "$body"
    } > "$tmp"
    
    # Syntax check first: never replace a working script with a broken one
    if ! bash -n "$tmp"; then
        rm -f "$tmp"
        error "Syntax error in script: $name"
        return 1
    fi
    
    _install_file "$tmp" "${SCRIPTS_BIN}/${name}" 0755
}

# remove_script NAME - delete /usr/local/bin/NAME if it exists.
# For scripts turned off by a setting (app-branch when IS_PRODUCTION=true):
# the file must disappear, not just lose its sudo rule
remove_script() {
    local target="$SCRIPTS_BIN/$1"

    if [ -e "$target" ]; then
        rm -f "$target"
        log "Removed script: $target"
    else
        log "Script not installed (nothing to remove): $target"
    fi
}

# grant_script_access USER SCRIPT... - allow USER to run the given scripts
# with "sudo SCRIPT" without a password. Rewrites the user's rule file
# from scratch, so always pass the FULL list of scripts.
grant_script_access() {
    local user="$1"
    shift
    local sudoers_file="/etc/sudoers.d/scripts-${user}"
    local tmp script
    
    if ! id "$user" &>/dev/null; then
        error "User does not exist: $user"
        return 1
    fi
    
    tmp="$(mktemp)"
    echo "# Managed by server-setup. Do not edit by hand." > "$tmp"
    
    for script in "$@"; do
        if [ ! -x "${SCRIPTS_BIN}/${script}" ]; then
            rm -f "$tmp"
            error "Script not found: ${SCRIPTS_BIN}/${script}"
            return 1
        fi
        # The trailing "" means: only WITHOUT arguments ("sudo script --x" is refused)
        echo "${user} ALL=(root) NOPASSWD: ${SCRIPTS_BIN}/${script} \"\"" >> "$tmp"
    done
    
    # Validate before installing: one broken file in /etc/sudoers.d breaks sudo entirely
    if ! visudo -cf "$tmp" >> "$LOG_FILE" 2>&1; then
        rm -f "$tmp"
        error "Invalid sudoers rules for user: $user"
        return 1
    fi
    
    # sudo refuses rule files not owned by root or writable by others; 0440 is the standard
    _install_file "$tmp" "$sudoers_file" 0440
}

# revoke_script_access USER - remove all sudo rules created by grant_script_access
revoke_script_access() {
    local user="$1"
    local sudoers_file="/etc/sudoers.d/scripts-${user}"
    
    if [ -f "$sudoers_file" ]; then
        rm -f "$sudoers_file"
        log "Revoked script access: $user"
    else
        log "No script access to revoke: $user"
    fi
}

# grant_scripts_to_team SCRIPT... - give every user from keys/*.pub
# (except ADMIN_USERS) sudo access to exactly these scripts
grant_scripts_to_team() {
    local keyfile user
    for keyfile in "$SCRIPT_DIR"/keys/*.pub; do
        [ -e "$keyfile" ] || continue
        user="$(basename "$keyfile" .pub)"
        if is_admin "$user"; then continue; fi
        grant_script_access "$user" "$@"
    done
}