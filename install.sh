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

# Download and Setup Package
setup_package() {
    log "🚀 Setting up KralPanel via Pre-built Package..."
    log "Downloading KralPanel package..."
    # BURAYA KENDİ İNDİRME LİNKİNİ KOYACAKSIN KRAL
    PACKAGE_URL="https://github.com/kubilayyil/mimipanel-sh/raw/main/kralpanel.tar.gz"
    
    rm -rf $INSTALL_DIR
    mkdir -p $INSTALL_DIR
    
    if ! curl -sSL "$PACKAGE_URL" -o /tmp/kralpanel.tar.gz; then
        die "Failed to download package from $PACKAGE_URL"
    fi

    log "Extracting package contents..."
    tar -xzf /tmp/kralpanel.tar.gz -C $INSTALL_DIR 2>/dev/null
    rm /tmp/kralpanel.tar.gz
}

# Start Services
setup_services() {
    log "Configuring Backend API..."
    chmod +x "$INSTALL_DIR/backend/kralpanel-api"
    
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
Environment=PORT=8080

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable -q kralpanel-api
    systemctl start kralpanel-api

    log "Setting up Frontend UI..."
    cd "$INSTALL_DIR/frontend"
    
    # Get server IP for frontend config
    IP=$(curl -s ifconfig.me)
    
    # Create environment file with API URL
    log "Configuring Frontend environment..."
    echo "NEXT_PUBLIC_API_URL=http://$IP" > .env.local
    
    # Install production dependencies
    npm install --quiet --only=production
    
    log "Starting Frontend with PM2..."
    pm2 delete kralpanel-ui 2>/dev/null || true
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
setup_package
setup_services

echo -e "\n${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Installation Successful! 🎉${NC}"
echo -e "  URL: ${CYAN}http://$(curl -s ifconfig.me)${NC}"
echo -e "  Admin: ${YELLOW}admin / admin123${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}\n"
