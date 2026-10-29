# shellcheck shell=bash
# autostart.sh - simple wrappers around deploy_service (systemd.sh)
# for the two common cases: a long-running process and a run-at-boot script

# register_autostart NAME COMMAND [USER=root] [WORKDIR=/] - long-running process
# started at boot and restarted 5s after a crash.
# COMMAND must start with an absolute path; for pipes/&&/cd use: /bin/bash -c '...'
# Example: register_autostart myapp "/usr/bin/python3 /opt/myapp/app.py" myapp /opt/myapp
register_autostart() {
    local name="$1"
    local command="$2"
    local user="${3:-root}"
    local workdir="${4:-/}"
    
    deploy_service "$name" "[Unit]
Description=${name} (autostart)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${user}
WorkingDirectory=${workdir}
ExecStart=${command}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target"
}

# register_boot_script NAME COMMAND [USER=root] - run COMMAND once at every boot
# after the network is up. RemainAfterExit=yes keeps the unit "active" after it
# finishes, so systemctl status shows whether it succeeded.
register_boot_script() {
    local name="$1"
    local command="$2"
    local user="${3:-root}"
    
    deploy_service "$name" "[Unit]
Description=${name} (run at boot)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=${user}
ExecStart=${command}

[Install]
WantedBy=multi-user.target"
}

# unregister_autostart NAME - stop, disable and delete a unit created by the functions above
unregister_autostart() {
    local name="$1"
    local unit_file="/etc/systemd/system/${name}.service"
    
    if [ ! -f "$unit_file" ]; then
        log "Not registered: $name"
        return 0
    fi
    
    systemctl disable --now "$name" >> "$LOG_FILE" 2>&1
    rm -f "$unit_file"
    systemctl daemon-reload
	systemctl reset-failed "$name" 2>/dev/null || true
    log "Removed from autostart: $name"
}
