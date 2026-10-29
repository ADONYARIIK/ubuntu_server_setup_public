# shellcheck shell=bash
# system.sh - basic OS settings

# configure_timezone TZ - e.g. "Europe/Warsaw", "UTC"
configure_timezone() {
    local tz="$1"
    
    if [ "$(timedatectl show -p Timezone --value)" = "$tz" ]; then
        log "Timezone already set: $tz"
    else
        timedatectl set-timezone "$tz"
        log "Timezone set to: $tz"
    fi
}

# configure_auto_updates - daily package lists + automatic security updates
# (only Ubuntu security updates by default; Docker is NOT auto-updated)
configure_auto_updates() {
    install_packages unattended-upgrades
    write_config /etc/apt/apt.conf.d/20auto-upgrades 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";'
}