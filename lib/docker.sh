# shellcheck shell=bash

# install_docker - Docker CE + compose/buildx plugins from the official Docker apt repo
# (https://docs.docker.com/engine/install/ubuntu/), service enabled at boot
install_docker() {
    # Repo signing key; referenced by "Signed-By" in the .sources file
    local keyring="/etc/apt/keyrings/docker.asc"
    local sources_file="/etc/apt/sources.list.d/docker.sources"
    
    install_packages ca-certificates curl
    
    # Add Docker's official GPG key if not present
    install -m 0755 -d /etc/apt/keyrings
    if [ -f "$keyring" ]; then
        log "Docker GPG key already present"
    else
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$keyring"
        chmod a+r "$keyring"
        log "Downloaded docker GPG key"
    fi
    
    # Add the Docker's repository to Apt sources
    local codename arch
    # Ubuntu codename, e.g. "noble" (UBUNTU_CODENAME also works on Ubuntu-based distros)
    codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
    arch="$(dpkg --print-architecture)"
    
    # deb822 format. NO leading whitespace: an indented line is treated
    # as a continuation of the previous field and breaks the file
    write_config "$sources_file" "Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Architectures: ${arch}
Signed-By: ${keyring}"
    
    if [ "$CONFIG_CHANGED" -eq 1 ]; then
        # Refresh package lists so apt sees the newly added repository
        apt-get update -qq >> "$LOG_FILE" 2>&1
    fi
    
    # Distro/unofficial Docker packages conflict with docker-ce (per Docker docs)
    remove_packages docker.io docker-compose docker-compose-v2 podman-docker containerd runc
    install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    systemctl enable --now docker >> "$LOG_FILE" 2>&1
    log "Docker installed and running"
}

configure_docker_daemon() {
    write_config /etc/docker/daemon.json '{
    "log-driver": "json-file",
    "log-opts": { "max-size": "10m", "max-file": "3" },
    "live-restore": true
}'

    if [ "$CONFIG_CHANGED" -eq 1 ]; then
        systemctl restart docker
        log "Docker daemon config applied"
    fi
}