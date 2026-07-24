#!/bin/bash

set -e

######################################################################################
#                                                                                    #
# Project 'pelican-installer'                                                        #
# Native Automated Installer for Pelican Panel & Wings                               #
# Official Guide: https://pelican.dev/docs/panel/getting-started/                   #
#                                                                                    #
######################################################################################

# Text Colors
C_RESET="\033[0m"
C_RED="\033[0;31m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[0;33m"
C_BLUE="\033[0;34m"
C_CYAN="\033[0;36m"

LOG_PATH="/var/log/pelican-installer.log"

output() {
  echo -e "${C_CYAN}*${C_RESET} $1"
}

success() {
  echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"
}

warning() {
  echo -e "${C_YELLOW}[WARNING]${C_RESET} $1"
}

error() {
  echo -e "${C_RED}[ERROR]${C_RESET} $1"
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root. Please run: sudo bash $0"
    exit 1
  fi
}

install_dependencies() {
  output "Updating package lists and installing core dependencies..."
  apt-get update -y
  apt-get install -y software-properties-common curl tar unzip git gnupg lsb-release

  output "Configuring PHP Repository (Direct Import)..."
  CODENAME=$(lsb_release -sc)
  mkdir -p /etc/apt/keyrings

  # Direct key import (Bypasses Launchpad API timeouts)
  curl -sS "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x4F4EA0AAE5267A6C" | gpg --dearmor -o /etc/apt/keyrings/ondrej-php.gpg --yes
  echo "deb [signed-by=/etc/apt/keyrings/ondrej-php.gpg] https://ppa.launchpadcontent.net/ondrej/php/ubuntu ${CODENAME} main" > /etc/apt/sources.list.d/ondrej-ubuntu-php.list

  apt-get update -y

  output "Installing PHP 8.3 and required extensions..."
  apt-get install -y \
    php8.3 \
    php8.3-fpm \
    php8.3-cli \
    php8.3-gd \
    php8.3-mysql \
    php8.3-mbstring \
    php8.3-bcmath \
    php8.3-xml \
    php8.3-curl \
    php8.3-zip \
    php8.3-intl \
    php8.3-sqlite3 \
    nginx
}

install_composer() {
  if ! [ -x "$(command -v composer)" ]; then
    output "Installing Composer globally..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
  else
    output "Composer is already installed."
  fi
}

install_panel() {
  output "Starting Pelican Panel Native Installation..."
  install_dependencies
  install_composer

  echo ""
  read -rp "* Enter your Domain Name or Server IP (e.g., panel.example.com or 192.168.1.100): " PANEL_FQDN
  [ -z "$PANEL_FQDN" ] && PANEL_FQDN="localhost"

  output "Creating panel directory (/var/www/pelican)..."
  mkdir -p /var/www/pelican
  cd /var/www/pelican

  output "Downloading and extracting latest Pelican Panel release..."
  curl -L https://github.com/pelican-dev/panel/releases/latest/download/panel.tar.gz | tar -xzv

  chmod -R 755 storage/* bootstrap/cache/

  output "Installing Composer dependencies..."
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

  output "Running Pelican environment setup CLI..."
  php artisan p:environment:setup

  output "Setting webserver permissions (www-data)..."
  chown -R www-data:www-data /var/www/pelican

  output "Configuring Nginx web server..."
  rm -f /etc/nginx/sites-enabled/default

  cat <<EOF > /etc/nginx/sites-available/pelican.conf
server {
    listen 80;
    server_name ${PANEL_FQDN};
    root /var/www/pelican/public;
    index index.php;

    access_log /var/log/nginx/pelican.app-access.log;
    error_log /var/log/nginx/pelican.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/pelican.conf /etc/nginx/sites-enabled/pelican.conf
  
  output "Restarting Nginx and PHP-FPM services..."
  systemctl restart php8.3-fpm
  systemctl restart nginx

  success "Pelican Panel core installation complete!"
  echo ""
  output "FINAL STEP: Complete the installation in your web browser:"
  output "👉 http://${PANEL_FQDN}/installer"
  echo ""
}

install_docker() {
  if ! [ -x "$(command -v docker)" ]; then
    output "Installing Docker for Wings..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
  else
    output "Docker is already installed."
  fi
}

install_wings() {
  output "Starting Pelican Wings Installation..."
  install_docker

  output "Creating Wings directory structure..."
  mkdir -p /etc/pelican /var/log/pelican /var/lib/pelican/volumes

  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) WINGS_ARCH="amd64" ;;
    aarch64) WINGS_ARCH="arm64" ;;
    *) error "Unsupported architecture: $ARCH"; exit 1 ;;
  esac

  output "Downloading Wings binary..."
  curl -L -o /usr/local/bin/wings "https://github.com/pelican-dev/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"
  chmod +x /usr/local/bin/wings

  output "Creating systemd service for Wings..."
  cat <<EOF > /etc/systemd/system/wings.service
[Unit]
Description=Pelican Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pelican
LimitNOFILE=65535
ExecStart=/usr/local/bin/wings
Restart=always
RestartSec=5s
StartLimitInterval=0

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable wings

  success "Pelican Wings installation complete!"
  warning "NEXT STEP: Create a Node in Pelican Panel, copy the generated config to '/etc/pelican/config.yml', then run: systemctl start wings"
}

execute() {
  echo -e "\n\n* pelican-installer $(date) \n\n" >> $LOG_PATH
  case "$1" in
    panel)
      install_panel
      ;;
    wings)
      install_wings
      ;;
    both)
      install_panel
      echo "----------------------------------------"
      install_wings
      ;;
    *)
      error "Invalid selection."
      exit 1
      ;;
  esac
}

# --- Main Entry Point ---
check_root

echo -e "${C_BLUE}"
echo "  ___  ___| (_) ___ __ _ _ __    ___   __ _ _ __   ___| |"
echo " / _ \/ _ \ | |/ __/ _\` | '_ \  / _ \ / _\` | '_ \ / _ \ |"
echo "|  __/  __/ | | (_| (_| | | | || (_) | (_| | | | |  __/ |"
echo " \___|\___|_|_|\___\__,_|_| |_| \___/ \__,_|_| |_|\___|_|"
echo -e "${C_RESET}"
echo " Pelican Panel & Wings Official Guide Installer"
echo "--------------------------------------------------------"

done=false
while [ "$done" == false ]; do
  options=(
    "Install Pelican Panel (Official Native Method)"
    "Install Pelican Wings"
    "Install both Panel and Wings on this machine"
    "Exit"
  )

  actions=(
    "panel"
    "wings"
    "both"
    "exit"
  )

  output "What would you like to do?"

  for i in "${!options[@]}"; do
    output "[$i] ${options[$i]}"
  done

  echo -n "* Input 0-$((${#actions[@]} - 1)): "
  read -r action

  if [ -z "$action" ]; then
    error "Input is required"
    continue
  fi

  if [[ ! "$action" =~ ^[0-3]$ ]]; then
    error "Invalid option"
    continue
  fi

  if [ "${actions[$action]}" == "exit" ]; then
    output "Exiting script."
    exit 0
  fi

  done=true
  execute "${actions[$action]}"
done
