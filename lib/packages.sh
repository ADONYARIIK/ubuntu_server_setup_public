# shellcheck shell=bash

# package_installed PKG - returns 0 if PKG is installed
# ("ii" in dpkg -l = desired: install, status: installed)
package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

# install_packages PKG... - install only missing packages, with a single apt-get call.
# Expects "apt-get update" to have been run before.
install_packages() {
    local packages=("$@")
    local to_install=()
    local pkg
    
    for pkg in "${packages[@]}"; do
        if package_installed "$pkg"; then
            log "Package already installed: $pkg"
        else
            to_install+=("$pkg")
        fi
    done
    
    if [ ${#to_install[@]} -gt 0 ]; then
        log "Installing packages: ${to_install[*]}"
        # Full apt output goes to the log, the terminal stays clean
        apt-get install -y "${to_install[@]}" >> "$LOG_FILE" 2>&1
    fi
}

# remove_packages PKG... - remove only the packages that are actually installed
# (config files stay; use "apt-get purge" to delete them too)
remove_packages() {
    local packages=("$@")
    local to_remove=()
    local pkg
    
    for pkg in "${packages[@]}"; do
        if package_installed "$pkg"; then
            to_remove+=("$pkg")
        else
            log "Package not installed: $pkg"
        fi
    done
    
    if [ ${#to_remove[@]} -gt 0 ]; then
        log "Removing packages: ${to_remove[*]}"
        # Full apt output goes to the log, the terminal stays clean
        apt-get remove -y "${to_remove[@]}" >> "$LOG_FILE" 2>&1
    fi
}