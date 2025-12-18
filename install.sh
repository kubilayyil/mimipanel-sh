#!/bin/sh
#====================================================================
# KralPanel - Professional One-Click Installer
# (C) 2025 Kubilay Yildirim. All rights reserved.
#====================================================================

set -efu

# --- Config ---
KRALPANEL_VERSION="1.0.0"
INSTALL_DIR="/opt/kralpanel"
REPO_URL="github.com/kubilayyil/mimipanel.git" # Private Repo Path
# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Functions ---

# Plesk-style die function
die() {
    /bin/echo -e "${RED}ERROR: $*${NC}" >&2
    exit 1
}

# Plesk-style log function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "You must have superuser privileges to install KralPanel."
    fi
}

# Detect OS (Plesk-style structure)
get_os_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
        OS_VERSION=$VERSION_ID
    else
        die "Unable to detect OS: /etc/os-release not found."
    fi

    # Only support Ubuntu for now
    if [ "$OS_NAME" != "ubuntu" ]; then
        die "KralPanel currently only supports Ubuntu. Detected: $OS_NAME"
    fi

    log "Detected OS: $NAME $VERSION"
}

# Install core dependencies
install_dependencies() {
    log "Updating system and installing base components..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -qq -y \
        curl wget git build-essential software-properties-common \
        ufw fail2ban nginx unzip > /dev/null
}

# Install Runtimes (Go & Node)
install_runtimes() {
    # Install Go
    if ! command -v go >/dev/null 2>&1; then
        log "Installing Go 1.22..."
        wget -q https://go.dev/dl/go1.22.0.linux-amd64.tar.gz
        rm -rf /usr/local/go && tar -C /usr/local -xzf go1.22.0.linux-amd64.tar.gz
        rm go1.22.0.linux-amd64.tar.gz
        export PATH=$PATH:/usr/local/go/bin
    fi

    # Install Node.js
    if ! command -v node >/dev/null 2>&1; then
        log "Installing Node.js 20..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null
        apt-get install -qq -y nodejs > /dev/null
    fi
    npm install -g pm2 -g > /dev/null
}

# Clone Project (Handles Private Repo)
clone_project() {
    log "Setting up source code..."
    rm -rf $INSTALL_DIR
    
    # Check if we need token
    # We try a public clone first, if it fails, ask for token
    log "Cloning from $REPO_URL..."
    
    echo -e "${YELLOW}Kral! Repo gizliyse GitHub Personal Access Token (PAT) gerekecek.${NC}"
    read -p "GitHub Token (ghp_xxx): " GH_TOKEN
    
    if [ -z "$GH_TOKEN" ]; then
        die "Token cannot be empty for private repository."
    fi

    AUTH_URL="https://${GH_TOKEN}@${REPO_URL}"
    
    if ! git clone -q $AUTH_URL $INSTALL_DIR; then
        die "Failed to clone repository. Check your Token and URL."
    fi
}

# Build and Start Services
setup_services() {
    log "Building Backend API..."
    cd "$INSTALL_DIR/backend"
    /usr/local/go/bin/go build -o kralpanel-api ./cmd/api
    
    log "Configuring Systemd..."
    cat > /etc/systemd/system/kralpanel-api.service << EOF
[Unit]
Description=KralPanel API
After=network.target

[Service]
ExecStart=$INSTALL_DIR/backend/kralpanel-api
WorkingDirectory=$INSTALL_DIR/backend
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable -q kralpanel-api
    systemctl start kralpanel-api

    log "Building Frontend UI..."
    cd "$INSTALL_DIR/frontend"
    npm install --quiet
    npm run build --quiet
    pm2 start npm --name "kralpanel-ui" -- start
    pm2 save --silent

    log "Configuring Nginx..."
    IP=$(curl -s ifconfig.me)
    cat > /etc/nginx/sites-available/kralpanel << EOF
server {
    listen 80;
    server_name $IP;
    location / { proxy_pass http://localhost:3000; proxy_set_header Host \$host; }
    location /api { proxy_pass http://localhost:8080; }
}
EOF
    ln -sf /etc/nginx/sites-available/kralpanel /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    systemctl restart nginx
}

# --- Main Execution ---

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════╗"
echo "║          KRALPANEL One-Click Installer             ║"
echo "║             v${KRALPANEL_VERSION} - Linux Center              ║"
echo "╚════════════════════════════════════════════════════╝"
echo -e "${NC}"

check_root
get_os_info
install_dependencies
install_runtimes
clone_project
setup_services

echo -e "\n${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Installation Successful! 🎉${NC}"
echo -e "  URL: ${CYAN}http://$(curl -s ifconfig.me)${NC}"
echo -e "  Admin: ${YELLOW}admin / admin123${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}\n"
