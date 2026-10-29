# shellcheck shell=bash

# install_from_script "cmd=url"... - install tools via their official install scripts.
# "cmd" is the binary name used to check if the tool is already installed.
# WARNING: runs remote code as root, use only trusted URLs.
install_from_script() {
    local entry cmd url installer
    
    for entry in "$@"; do
        # Split at the FIRST "=": the URL itself may contain "="
        cmd="${entry%%=*}"
        url="${entry#*=}"
        
        if command -v "$cmd" &>/dev/null; then
            log "Already installed: $cmd"
            continue
        fi
        
        log "Installing $cmd from $url"
        # Download to a temp file first so a partial download is never executed
        installer="$(mktemp)"
        
        if curl -fsSL "$url" -o "$installer" && bash "$installer" >> "$LOG_FILE" 2>&1; then
            rm -f "$installer"
            log "Installed: $cmd ($(command -v "$cmd" || echo "not in PATH"))"
        else
            rm -f "$installer"
            error "Failed to install $cmd"
            return 1
        fi
    done
}
