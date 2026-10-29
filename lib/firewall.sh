# shellcheck shell=bash

# configure_firewall [PORT/PROTO...] - bring UFW to a known state:
# deny all incoming, allow all outgoing, allow SSH + the ports given as arguments
# Example: configure_firewall 80/tcp 443/tcp
configure_firewall() {
    local port

    log "Configuring UFW firewall..."
    
    # Resets creates a repeatable baseline, but removes existing UFW rules
    ufw --force reset >> "$LOG_FILE" 2>&1
    ufw default deny incoming >> "$LOG_FILE" 2>&1
    ufw default allow outgoing >> "$LOG_FILE" 2>&1
    
    # Allow SSH
    ufw allow "${SSH_PORT}/tcp" >> "$LOG_FILE" 2>&1
    
    # Allow additional ports passed as arguments
    for port in "$@"; do
        ufw allow "$port" >> "$LOG_FILE" 2>&1
        log "Opened port: $port"
    done
    
    # Enable without interactive prompt
    # --force skips the "may disrupt existing ssh connections" prompt
    # (safe here: SSH was allowed above)
    ufw --force enable >> "$LOG_FILE" 2>&1
    log "Firewall enabled"
    ufw status verbose | tee -a "$LOG_FILE"
}
