#!/bin/bash

# =======================================================
#  Airlink Custom Auto-Installer
#  Panel Repository:  https://github.com/Mitul636/panel-v1
#  Daemon Repository: https://github.com/Mitul636/daemon-v1
# =======================================================

set -e

# Visual colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Repositories
PANEL_REPO="https://github.com/Mitul636/panel-v1.git"
DAEMON_REPO="https://github.com/Mitul636/daemon-v1.git"

# Paths
PANEL_DIR="/var/www/airlink"
DAEMON_DIR="/etc/airlink-daemon"

# Check root privileges
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run this script as root or with sudo.${NC}"
  exit 1
fi

print_banner() {
  clear
  echo -e "${BLUE}"
  echo "======================================================"
  echo "         Airlink Panel & Daemon Installer             "
  echo "       (Custom Fork: Mitul636 Panel / Daemon)        "
  echo "======================================================"
  echo -e "${NC}"
}

install_base_deps() {
  echo -e "${YELLOW}[1/4] Updating packages and installing base dependencies...${NC}"
  apt-get update -y
  apt-get install -y curl git unzip tar build-essential software-properties-common ca-certificates gnupg

  # Install Bun if missing
  if ! command -v bun &> /dev/null; then
    echo -e "${YELLOW}Installing Bun runtime...${NC}"
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
    ln -sf "$HOME/.bun/bin/bun" /usr/local/bin/bun
  fi

  # Install Node.js (v20 LTS) if missing
  if ! command -v node &> /dev/null; then
    echo -e "${YELLOW}Installing Node.js...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
  fi
}

install_docker() {
  if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Installing Docker...${NC}"
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
  fi
}

install_panel() {
  echo -e "${GREEN}==> Installing Airlink Panel...${NC}"
  install_base_deps

  # Prepare directory
  mkdir -p "$PANEL_DIR"
  if [ -d "$PANEL_DIR/.git" ]; then
    echo -e "${YELLOW}Existing panel directory found. Pulling latest updates...${NC}"
    cd "$PANEL_DIR"
    git pull
  else
    echo -e "${YELLOW}Cloning custom panel repository...${NC}"
    rm -rf "$PANEL_DIR"
    git clone "$PANEL_REPO" "$PANEL_DIR"
    cd "$PANEL_DIR"
  fi

  echo -e "${YELLOW}Installing dependencies and building panel...${NC}"
  bun install || npm install
  bun run build || npm run build

  # Environment Setup
  if [ ! -f "$PANEL_DIR/.env" ]; then
    if [ -f "$PANEL_DIR/.env.example" ]; then
      cp "$PANEL_DIR/.env.example" "$PANEL_DIR/.env"
      echo -e "${YELLOW}Created .env file from .env.example. Please review and edit $PANEL_DIR/.env as needed.${NC}"
    fi
  fi

  # Systemd Service Setup
  echo -e "${YELLOW}Creating systemd service for Panel...${NC}"
  cat <<EOF > /etc/systemd/system/airlink-panel.service
[Unit]
Description=Airlink Panel Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PANEL_DIR
ExecStart=$(which bun) run start
Restart=always
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now airlink-panel.service

  echo -e "${GREEN}✔ Airlink Panel installation complete!${NC}"
  echo -e "${BLUE}Directory: $PANEL_DIR${NC}"
  echo -e "${BLUE}Service Status: systemctl status airlink-panel${NC}"
}

install_daemon() {
  echo -e "${GREEN}==> Installing Airlink Daemon...${NC}"
  install_base_deps
  install_docker

  # Prepare directory
  mkdir -p "$DAEMON_DIR"
  if [ -d "$DAEMON_DIR/.git" ]; then
    echo -e "${YELLOW}Existing daemon directory found. Pulling latest updates...${NC}"
    cd "$DAEMON_DIR"
    git pull
  else
    echo -e "${YELLOW}Cloning custom daemon repository...${NC}"
    rm -rf "$DAEMON_DIR"
    git clone "$DAEMON_REPO" "$DAEMON_DIR"
    cd "$DAEMON_DIR"
  fi

  echo -e "${YELLOW}Installing dependencies and building daemon...${NC}"
  bun install || npm install
  bun run build || npm run build

  # Systemd Service Setup
  echo -e "${YELLOW}Creating systemd service for Daemon...${NC}"
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
  systemctl enable --now airlink-daemon.service

  echo -e "${GREEN}✔ Airlink Daemon installation complete!${NC}"
  echo -e "${BLUE}Directory: $DAEMON_DIR${NC}"
  echo -e "${BLUE}Service Status: systemctl status airlink-daemon${NC}"
}

# Main Interactive Menu
print_banner
echo "Select what you want to install:"
echo "1) Install Airlink Panel"
echo "2) Install Airlink Daemon"
echo "3) Install Both (Panel + Daemon)"
echo "4) Exit"
echo ""
read -p "Enter your choice [1-4]: " CHOICE

case $CHOICE in
  1)
    install_panel
    ;;
  2)
    install_daemon
    ;;
  3)
    install_panel
    echo -e "\n------------------------------------------------------\n"
    install_daemon
    ;;
  4)
    echo -e "${YELLOW}Installation cancelled.${NC}"
    exit 0
    ;;
  *)
    echo -e "${RED}Invalid choice.${NC}"
    exit 1
    ;;
esac
