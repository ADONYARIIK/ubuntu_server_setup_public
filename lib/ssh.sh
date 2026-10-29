# shellcheck shell=bash

# ensure_admin_keys - check authorized_keys for every admin.
# Missing key = warning (that admin loses SSH access after password login is disabled).
# No admin with a key at all = stop, otherwise nobody can get in anymore
ensure_admin_keys() {
    local user home_dir with_key=0
    
    for user in "${ADMIN_USERS[@]}"; do
        home_dir="$(getent passwd "$user" | cut -d: -f6)" || true
        
        if [ -n "$home_dir" ] && [ -s "${home_dir}/.ssh/authorized_keys" ]; then
            log "Admin SSH key present: $user"
            # Not ((with_key++)): it returns status 1 when the value was 0, and set -e exits
            with_key=$((with_key + 1))
        else
            warn "Admin $user has NO SSH key and will be locked out of SSH"
        fi
    done
    
    if [ "$with_key" -eq 0 ]; then
        error "No admin has an SSH key - refusing to disable password login"
        return 1
    fi
}

# configure_sshd - SSH hardening via a drop-in file (main sshd_config stays untouched).
# sshd uses the FIRST value found for each option and reads sshd_config.d/*.conf
# alphabetically, so this file must sort before 50-cloud-init.conf.
# Check the effective config with: sshd -T
configure_sshd() {
    local config_file="/etc/ssh/sshd_config.d/00-hardened.conf"
    
    # PermitRootLogin no          - log in as a normal user, then use sudo
    # PasswordAuthentication no   - keys only (deploy keys BEFORE this runs!)
    # MaxAuthTries 3              - drop the connection after 3 failed attempts
    # ClientAlive* 300 x 2        - disconnect dead clients after ~10 min
    # X11/Agent/TcpForwarding no  - no forwarding (breaks VS Code Remote-SSH and ssh -L)
    # UseDNS no                   - no reverse DNS lookup, faster login
    write_config "$config_file" "Port ${SSH_PORT}
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PrintMotd no
UseDNS no"
    
    # Validate the config before restarting
    # A broken sshd config = lost remote access, so never reload without checking
    if sshd -t >> "$LOG_FILE" 2>&1; then
        systemctl try-reload-or-restart ssh
        log "SSH configuration applied"
    else
        error "SSH config validation failed - not restarting ssh"
        rm -f "$config_file"
        return 1
    fi
}
