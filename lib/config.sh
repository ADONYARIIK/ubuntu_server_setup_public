# shellcheck shell=bash

# Write a config file only if it differs from what's already there
# Usage: write_config FILE CONTENT
# Sets global CONFIG_CHANGED: 1 = file was (re)written, 0 = already up to date.
# Callers check CONFIG_CHANGED right after the call to decide whether to reload/restart.
# CONTENT is written verbatim, including leading whitespace: don't indent it!
write_config() {
    local file="$1"
    local content="$2"
    local backup_suffix=".bak.$(date +%Y%m%d_%H%M%S)"
    local backup_path="/var/backups/server_setup/"
    # Intentionally global (no "local"): callers read it after this function returns
    CONFIG_CHANGED=0
    
    if [ -f "$file" ]; then
        local current_content
        # $(...) strips trailing newlines, so a trailing newline difference is ignored
        current_content=$(cat "$file")
        
        if [ "$current_content" = "$content" ]; then
            log "Config already up to date: $file"
            return 0
        fi
        
        # Backup existing file before overwriting (keeps the original path inside backup_path)
        local backup_file="${backup_path}${file#/}${backup_suffix}"
        mkdir -p "$(dirname "$backup_file")"
        cp "$file" "$backup_file"
        warn "Backed up existing config to: $backup_file"
    fi
    
    mkdir -p "$(dirname "$file")"
    # Write the new content
    printf '%s\n' "$content" > "$file"
    CONFIG_CHANGED=1
    log "Wrote config: $file"
}
