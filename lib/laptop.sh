# shellcheck shell=bash

# configure_laptop_server - make a laptop usable as a 24/7 server:
# ignore lid close, suspend/hibernate keys and idle, and block all sleep states
configure_laptop_server() {
    log "Configuring laptop to never sleep..."
    
    # Drop-in file: the original /etc/systemd/logind.conf stays untouched
    # HandleLidSwitch*    - do nothing when the lid is closed (on battery / AC / docked)
    # IdleAction=ignore   - never suspend on inactivity
    write_config /etc/systemd/logind.conf.d/no-sleep.conf "[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
IdleAction=ignore"
    
    if [ "$CONFIG_CHANGED" -eq 1 ]; then
        # logind reads its config only at startup
        systemctl restart systemd-logind
    fi
    log "logind: lid and idle actions set to ignore"
    
    # Masking makes these targets impossible to start, so nothing
    # (not even "systemctl suspend") can put the machine to sleep
    local targets=(sleep.target suspend.target hibernate.target hybrid-sleep.target)
    local t
    for t in "${targets[@]}"; do
        if [ "$(systemctl is-enabled "$t" 2>/dev/null)" = "masked" ]; then
            log "Already masked: $t"
        else
            systemctl mask "$t" >> "$LOG_FILE" 2>&1
            log "Masked: $t"
        fi
    done
}
