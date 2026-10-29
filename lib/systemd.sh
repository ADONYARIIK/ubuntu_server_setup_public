# shellcheck shell=bash
# systemd.sh - install and manage systemd service units

# deploy_service NAME CONTENT - install /etc/systemd/system/NAME.service from CONTENT
# (full unit file text), enable it at boot and make sure it is running:
#   unit changed -> daemon-reload + enable + restart
#   not enabled  -> enable --now
#   otherwise    -> nothing to do
# Used by register_autostart / register_boot_script; call it directly for units
# that need options those helpers don't support (Environment=, Restart=always, ...)
deploy_service() {
    local name="$1"
    local content="$2"
    local unit_file="/etc/systemd/system/${name}.service"
    
    write_config "$unit_file" "$content"
    
    if [ "$CONFIG_CHANGED" -eq 1 ]; then
        # Required after any change to unit files, otherwise systemd uses the old version
        systemctl daemon-reload
        systemctl enable "$name" >> "$LOG_FILE" 2>&1
        # restart (not try-restart): also starts a unit that isn't running yet
        systemctl restart "$name"
        log "Service (re)started: $name"
    elif ! systemctl is-enabled --quiet "$name"; then
        systemctl enable --now "$name" >> "$LOG_FILE" 2>&1
        log "Service enabled: $name"
    else
        log "Service unchanged: $name"
    fi
}
