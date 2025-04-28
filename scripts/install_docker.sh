#!/bin/bash
# Set error handling
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Log functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get the factory IP from command line arguments
FACTORY_IP=$1

# Display script usage
log "Docker Installation Script"
log "------------------------"
log "Usage: $0 [FACTORY_IP]"
log "  FACTORY_IP: Optional - IP address for Docker registry (for remote registry configuration)"
log "  If no FACTORY_IP is provided, Docker will be installed with default configuration"
log "------------------------"

# Get current user
CURRENT_USER=$(whoami)
log "Installing Docker for user: $CURRENT_USER"

# Update package index
log "Updating package index..."
sudo apt-get update || { error "Failed to update package index"; exit 1; }

# Install prerequisites
log "Installing prerequisites..."
sudo apt-get install -y ca-certificates curl || { error "Failed to install ca-certificates and curl"; exit 1; }

# Setup Docker repository
log "Setting up Docker repository..."
sudo install -m 0755 -d /etc/apt/keyrings || { error "Failed to create keyrings directory"; exit 1; }

# Download Docker GPG key with retry
log "Downloading Docker GPG key..."
for i in {1..3}; do
    if sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc; then
        log "Docker GPG key downloaded successfully"
        break
    fi
    if [ $i -eq 3 ]; then
        error "Failed to download Docker GPG key after 3 attempts"
        exit 1
    fi
    warn "Retry $i downloading Docker GPG key..."
    sleep 3
done

# Set permissions for the key
sudo chmod a+r /etc/apt/keyrings/docker.asc || { error "Failed to set permissions for Docker GPG key"; exit 1; }

# Detect architecture and OS codename
ARCHITECTURE=$(dpkg --print-architecture)
CODENAME=$(lsb_release -cs)
log "Detected architecture: $ARCHITECTURE, OS codename: $CODENAME"

# Add Docker repository
log "Adding Docker repository..."
sudo tee /etc/apt/sources.list.d/docker.list << EOL
deb [arch=$ARCHITECTURE signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $CODENAME stable
EOL

# Update package index again
log "Updating package index with Docker repository..."
sudo apt-get update || { error "Failed to update package index with Docker repository"; exit 1; }

# Install Docker
log "Installing Docker packages..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { error "Failed to install Docker packages"; exit 1; }

# Configure Docker daemon
log "Configuring Docker daemon..."
sudo rm -f /etc/docker/daemon.json

# 检测是否在中国
log "Detecting location..."
IN_CHINA=false
if curl -s -H "User-Agent: Mozilla/5.0" https://ipapi.co/country/ | grep -q "CN"; then
    log "Detected location: China - will use China mirror"
    IN_CHINA=true
else
    log "Detected location: Outside China - will use default settings"
fi

if [ -z "$FACTORY_IP" ]; then
    # Default configuration without insecure registry
    if [ "$IN_CHINA" = true ]; then
        log "Using standard Docker configuration with China mirror"
        echo '{
    "experimental": true,
    "registry-mirrors": ["https://docker.zhai.cm"]
}' | sudo tee /etc/docker/daemon.json > /dev/null
    else
        log "Using standard Docker configuration"
        echo '{
    "experimental": true
}' | sudo tee /etc/docker/daemon.json > /dev/null
    fi
else
    # Configuration with insecure registry
    if [ "$IN_CHINA" = true ]; then
        log "Configuring Docker with insecure registry and China mirror"
        echo '{
    "experimental": true,
    "insecure-registries": ["sensecraft-missionpack.seeed.cn:5000"],
    "registry-mirrors": ["https://docker.zhai.cm"]
}' | sudo tee /etc/docker/daemon.json > /dev/null
    else
        log "Configuring Docker with insecure registry"
        echo '{
    "experimental": true,
    "insecure-registries": ["sensecraft-missionpack.seeed.cn:5000"]
}' | sudo tee /etc/docker/daemon.json > /dev/null
    fi
fi

# Add user to Docker group
log "Adding user to Docker group..."
sudo usermod -aG docker $CURRENT_USER || { error "Failed to add user to Docker group"; exit 1; }

# Restart and enable Docker service
log "Restarting Docker service..."
sudo systemctl restart docker || { error "Failed to restart Docker service"; exit 1; }
log "Enabling Docker service..."
sudo systemctl enable docker || { error "Failed to enable Docker service"; exit 1; }

# Success message
log "Docker installation complete. Docker service has been restarted."
warn "IMPORTANT: You must log out and log back in, or reboot your system, for the group changes to take effect."

# Reboot if not in a script
if [ -t 1 ]; then
    read -p "Do you want to reboot now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Rebooting system..."
        sudo reboot
    else
        warn "Remember to reboot later for changes to take full effect."
    fi
else
    # If running in a script, reboot automatically
    log "Rebooting system automatically..."
    sudo reboot
fi
