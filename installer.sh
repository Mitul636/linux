#!/bin/bash

# ==============================================================================
# Airlink Modified Panel & Daemon Installer
# Repositories:
#   - Panel:  https://github.com/Mitul636/panel-v1
#   - Daemon: https://github.com/Mitul636/daemon-v1
# ==============================================================================

set -e

# --- Colors for Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Repository & Directory Config ---
PANEL_REPO="https://github.com/Mitul636/panel-v1.git"
DAEMON_REPO="https://github.com/Mitul636/daemon-v1.git"

PANEL_DIR="/var/www/airlink-panel"
DAEMON_DIR="/etc/airlink-daemon"

# --- Helper Functions ---
print_banner() {
  clear
  echo -e "${CYAN}"
  echo "=========================================================="
  echo "         Airlink Custom Installer (Mitul636 Edition)      "
  echo "=========================================================="
  echo -e "${NC}"
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Please run this script as root (use sudo).${NC}"
    exit 1
  fi
}

install_system_deps() {
  echo -e "${YELLOW}[1/4] Updating packages and installing basic tools...${NC}"
  if command -v apt-get &> /dev/null; then
    apt-get update -y
    apt-get install -y curl git unzip tar build-essential ca-certificates gnupg
  elif command -v dnf &> /dev/null; then
    dnf install -y curl git unzip tar gcc gcc-c++ make ca-certificates
  else
    echo -e "${RED}[ERROR] Unsupported package manager. Please use Ubuntu/Debian or RHEL/CentOS.${NC}"
    exit 1
  fi
}

install_nodejs() {
  if ! command -v node &> /dev/null; then
    echo -e "${YELLOW}Installing Node.js 20 LTS...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs || dnf install -y nodejs
  else
    echo -e "${GREEN}[OK] Node.js is already installed: $(node -v)${NC}"
  fi
}

install_bun() {
  if ! command -v bun &> /dev/null; then
    echo -e "${YELLOW}Installing Bun...${NC}"
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
    ln -sf "$HOME/.bun/bin/bun" /usr/local/bin/bun
  else
    echo -e "${GREEN}[OK] Bun is already installed: $(bun -v)${NC}"
  fi
}

install_docker() {
  if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Installing Docker...${NC}"
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
  else
    echo -e "${GREEN}[OK] Docker is already installed.${NC}"
  fi
}

# --- Installation Procedures ---
install_panel() {
  echo -e "${CYAN}--- Starting Installation: Airlink Panel ---${NC}"
  
  install_system_deps
  install_nodejs
  install_bun

  # Clone or update panel repository
  if [ -d "$PANEL_DIR" ]; then
    echo -e "${YELLOW}Existing panel directory found at $PANEL_DIR. Updating...${NC}"
    cd "$PANEL_DIR"
    git pull
  else
    echo -e "${YELLOW}Cloning Panel repository from $PANEL_REPO...${NC}"
    mkdir -p /var/www
    git clone "$PANEL_REPO" "$PANEL_DIR"
    cd "$PANEL_DIR"
  fi

  # Dependencies & Build
  echo -e "${YELLOW}Installing Panel dependencies...${NC}"
  if [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then
    bun install
  else
    npm install
  fi

  # Environment setup
  if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
      cp .env.example .env
    else
      echo -e "${YELLOW}Creating default .env file...${NC}"
      cat <<EOF > .env
PORT=3000
DATABASE_URL="file:./dev.db"
NODE_ENV="production"
EOF
    fi
    echo -e "${GREEN}Created .env configuration file.${NC}"
  fi

  # Database setup (Prisma)
  if [ -f "prisma/schema.prisma" ]; then
    echo -e "${YELLOW}Setting up database schema (Prisma)...${NC}"
    npx prisma db push --accept-data-loss || true
  fi

  # Build Panel
  if grep -q '"build"' package.json; then
    echo -e "${YELLOW}Building Panel static/server assets...${NC}"
    npm run build || bun run build || true
  fi

  # Create Systemd Service for Panel
  echo -e "${YELLOW}Configuring systemd service for Panel...${NC}"
  cat <<EOF > /etc/systemd/system/airlink-panel.service
[Unit]
Description=Airlink Panel Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PANEL_DIR
ExecStart=$(which bun || which npm) start
Restart=always
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now airlink-panel

  echo -e "${GREEN}=========================================================="
  echo "      Airlink Panel Installation Complete!"
  echo "      Status: systemctl status airlink-panel"
  echo "==========================================================${NC}"
}

install_daemon() {
  echo -e "${CYAN}--- Starting Installation: Airlink Daemon ---${NC}"
  
  install_system_deps
  install_bun
  install_docker

  # Clone or update daemon repository
  if [ -d "$DAEMON_DIR" ]; then
    echo -e "${YELLOW}Existing daemon directory found at $DAEMON_DIR. Updating...${NC}"
    cd "$DAEMON_DIR"
    git pull
  else
    echo -e "${YELLOW}Cloning Daemon repository from $DAEMON_REPO...${NC}"
    git clone "$DAEMON_REPO" "$DAEMON_DIR"
    cd "$DAEMON_DIR"
  fi

  # Set Permissions
  chown -R root:root "$DAEMON_DIR"
  chmod -R 755 "$DAEMON_DIR"

  # Dependencies & Build
  echo -e "${YELLOW}Installing Daemon dependencies via Bun...${NC}"
  bun install

  if grep -q '"build"' package.json; then
    echo -e "${YELLOW}Building Daemon binaries/dist...${NC}"
    bun run build || true
  fi

  # Create Systemd Service for Daemon
  echo -e "${YELLOW}Configuring systemd service for Daemon...${NC}"
  cat <<EOF > /etc/systemd/system/airlink-daemon.service
[Unit]
Description=Airlink Daemon Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$DAEMON_DIR
ExecStart=$(which bun) run start
Restart=always
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now airlink-daemon

  echo -e "${GREEN}=========================================================="
  echo "      Airlink Daemon Installation Complete!"
  echo "      Status: systemctl status airlink-daemon"
  echo "==========================================================${NC}"
}

# --- Main Menu ---
main() {
  check_root
  print_banner

  echo "What would you like to install?"
  echo "  1) Install Panel ($PANEL_REPO)"
  echo "  2) Install Daemon ($DAEMON_REPO)"
  echo "  3) Install Both (Panel + Daemon)"
  echo "  4) Exit"
  echo ""
  read -rp "Enter choice [1-4]: " choice </dev/tty

  case $choice in
    1)
      install_panel
      ;;
    2)
      install_daemon
      ;;
    3)
      install_panel
      install_daemon
      ;;
    4)
      echo "Exiting installer."
      exit 0
      ;;
    *)
      echo -e "${RED}Invalid selection.${NC}"
      exit 1
      ;;
  esac
}

main "$@"
