#!/bin/sh
#====================================================================
# Mimipanel - Professional One-Click Installer
# (C) 2025 Kubilay Yildirim. All rights reserved.
#====================================================================

set -efu

# --- Config ---
MIMIPANEL_VERSION="1.0.0"
INSTALL_DIR="/opt/mimipanel"
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
        die "You must have superuser privileges to install Mimipanel."
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
        die "Mimipanel currently only supports Ubuntu. Detected: $OS_NAME"
    fi

    log "Detected OS: $NAME $VERSION"
}

# Install core dependencies
install_dependencies() {
    log "Updating system and installing base components..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    
    # Base packages
    apt-get install -qq -y \
        curl wget git build-essential software-properties-common \
        ufw fail2ban nginx unzip zip acl > /dev/null
    
    # Add PHP repository
    log "Adding PHP repository..."
    add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1
    apt-get update -qq
    
    # Install PHP versions (7.4, 8.0, 8.1, 8.2, 8.3)
    log "Installing PHP versions..."
    for PHP_VER in 7.4 8.0 8.1 8.2 8.3; do
        apt-get install -qq -y \
            php${PHP_VER}-fpm php${PHP_VER}-cli php${PHP_VER}-common \
            php${PHP_VER}-mysql php${PHP_VER}-pgsql php${PHP_VER}-sqlite3 \
            php${PHP_VER}-curl php${PHP_VER}-gd php${PHP_VER}-mbstring \
            php${PHP_VER}-xml php${PHP_VER}-zip php${PHP_VER}-bcmath \
            php${PHP_VER}-intl php${PHP_VER}-soap php${PHP_VER}-imap \
            php${PHP_VER}-redis php${PHP_VER}-imagick > /dev/null 2>&1
    done
    
    # Install MariaDB
    log "Installing MariaDB..."
    apt-get install -qq -y mariadb-server mariadb-client > /dev/null
    systemctl enable mariadb
    systemctl start mariadb
    
    # Install Mail Server (Postfix + Dovecot)
    log "Installing Mail Server..."
    debconf-set-selections <<< "postfix postfix/mailname string $(hostname -f)"
    debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
    apt-get install -qq -y postfix dovecot-core dovecot-imapd dovecot-pop3d > /dev/null
    systemctl enable postfix dovecot
    systemctl start postfix dovecot
    
    # Install Certbot for SSL
    log "Installing Certbot..."
    apt-get install -qq -y certbot python3-certbot-nginx > /dev/null
    
    # Install additional tools
    log "Installing additional tools..."
    apt-get install -qq -y \
        redis-server memcached \
        pure-ftpd \
        supervisor > /dev/null 2>&1
    
    # Enable services
    systemctl enable nginx redis-server > /dev/null 2>&1
    systemctl start nginx redis-server > /dev/null 2>&1
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
    log "🚀 Setting up Mimipanel via Pre-built Package..."
    log "Downloading Mimipanel package..."
    # BURAYA KENDİ İNDİRME LİNKİNİ KOYACAKSIN KRAL
    PACKAGE_URL="https://github.com/kubilayyil/mimipanel-sh/raw/main/mimipanel.tar.gz"
    
    rm -rf $INSTALL_DIR
    mkdir -p $INSTALL_DIR
    
    if ! curl -sSL "$PACKAGE_URL" -o /tmp/mimipanel.tar.gz; then
        die "Failed to download package from $PACKAGE_URL"
    fi

    log "Extracting package contents..."
    tar -xzf /tmp/mimipanel.tar.gz -C $INSTALL_DIR 2>/dev/null
    rm /tmp/mimipanel.tar.gz
}

# Start Services
setup_services() {
    log "Configuring Backend API..."
    chmod +x "$INSTALL_DIR/backend/mimipanel-api"
    
    # Ensure backend directory is writable for SQLite database
    chmod 755 "$INSTALL_DIR/backend"
    
    log "Configuring Systemd..."
    cat > /etc/systemd/system/mimipanel-api.service << EOF
[Unit]
Description=Mimipanel API
After=network.target

[Service]
ExecStart=$INSTALL_DIR/backend/mimipanel-api
WorkingDirectory=$INSTALL_DIR/backend
Restart=always
User=root
Environment=PORT=8080

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable -q mimipanel-api
    systemctl start mimipanel-api

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
    pm2 delete mimipanel-ui 2>/dev/null || true
    pm2 start npm --name "mimipanel-ui" -- start
    pm2 save --silent

    log "Configuring Nginx..."
    IP=$(curl -s ifconfig.me)
    cat > /etc/nginx/sites-available/mimipanel << EOF
server {
    listen 80;
    server_name $IP;
    location / { proxy_pass http://localhost:3000; proxy_set_header Host \$host; }
    location /api { proxy_pass http://localhost:8080; }
}
EOF
    ln -sf /etc/nginx/sites-available/mimipanel /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    systemctl restart nginx
}

# --- Main Execution ---

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════╗"
echo "║          MIMIPANEL One-Click Installer             ║"
echo "║             v${MIMIPANEL_VERSION} - Linux Center              ║"
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
