#!/bin/bash
# ===========================================
# 🔐 TigerHost Premium SSH Setup Tool
# ===========================================

set -e

# ===== Colors =====
ORANGE="\e[38;5;208m"
YELLOW="\e[38;5;220m"
GREEN="\e[38;5;82m"
CYAN="\e[38;5;51m"
BLUE="\e[38;5;39m"
GRAY="\e[38;5;245m"
RED="\e[31m"
RESET="\e[0m"

# Clear screen
clear

# ===== Banner =====
echo -e "${ORANGE}"
echo "========================================="
echo "       🐯 TIGERHOST SSH SETUP TOOL"
echo "========================================="
echo -e "${RESET}"

# ===== Safety Check: Root Privileges =====
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[✗] Critical Error: Please run this script as root! (sudo)${RESET}"
  exit 1
fi

echo -e "${YELLOW}[!] Warning: This will overwrite your current SSH configuration.${RESET}"
read -p "Do you want to continue? (y/n): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo -e "${RED}[✗] Installation cancelled by user.${RESET}"
  exit 1
fi

sleep 1

# ===== Step 1: Backup Configuration =====
echo -e "\n${BLUE}▶ [1/4] Backing up current SSH config...${RESET}"
if [ -f /etc/ssh/sshd_config ]; then
  cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
  echo -e "${GREEN}✔ Backup saved to /etc/ssh/sshd_config.bak${RESET}"
else
  echo -e "${GRAY}🔸 No existing config found to back up.${RESET}"
fi

# ===== Step 2: Apply Secure Configuration =====
echo -e "\n${BLUE}▶ [2/4] Applying optimized SSH settings...${RESET}"

cat << 'EOF' > /etc/ssh/sshd_config
# ===========================================
# 🔐 TIGERHOST PREMIUM SSH CONFIGURATION
# ===========================================

Port 22
Protocol 2

# AUTHENTICATION SETTINGS
PasswordAuthentication yes
PermitRootLogin yes
PubkeyAuthentication no
ChallengeResponseAuthentication no
UsePAM yes

# SECURITY & PERFORMANCE TUNING
X11Forwarding no
AllowTcpForwarding yes
ClientAliveInterval 300
ClientAliveCountMax 2

# SFTP SUBSYSTEM
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✔ Configuration applied successfully!${RESET}"
else
  echo -e "${RED}[✗] Error writing SSH configuration file!${RESET}"
  exit 1
fi

# ===== Step 3: Restart SSH Service =====
echo -e "\n${BLUE}▶ [3/4] Restarting SSH daemon...${RESET}"
if systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || service ssh restart 2>/dev/null; then
  echo -e "${GREEN}✔ SSH service restarted successfully!${RESET}"
else
  echo -e "${RED}[✗] Warning: Failed to restart SSH service automatically. Please restart manually.${RESET}"
fi

sleep 1

# ===== Step 4: Secure Root Password Setup =====
echo -e "\n${BLUE}▶ [4/4] Configuring ROOT password...${RESET}"
echo -e "${YELLOW}🔑 Please input your desired root password below:${RESET}"

while true; do
  read -s -p "Enter new root password: " pass1
  echo
  read -s -p "Confirm new root password: " pass2
  echo

  if [ -z "$pass1" ]; then
    echo -e "${RED}[✗] Password cannot be blank! Please try again.${RESET}"
  elif [[ "$pass1" == "$pass2" ]]; then
    echo "root:$pass1" | chpasswd
    echo -e "${GREEN}✔ Root password updated successfully!${RESET}"
    break
  else
    echo -e "${RED}[✗] Passwords do not match! Please try again.${RESET}"
  fi
done

# ===== Final Confirmation Screen =====
clear
echo -e "${ORANGE}"
cat << "LOGO"
  _______ _                  _    _                 _   
 |__   __(_)                | |  | |               | |  
    | |   _  __ _  ___ _ __ | |__| | ___  ___  ___ | |_ 
    | |  | |/ _` |/ _ \ '__||  __  |/ _ \/ __|/ _ \| __|
    | |  | | (_| |  __/ |   | |  | | (_) \__ \ (_) | |_ 
    |_|  |_|\__, |\___|_|   |_|  |_|\___/|___/\___/ \__|
             __/ |                                      
            |___/                                       
LOGO
echo -e "${RESET}"

echo -e "${GREEN}🎉 SSH Setup Completed Successfully!${RESET}"
echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# Display Connection Context
IP=$(hostname -I | awk '{print $1}')
echo -e "${CYAN}📌 Server Access Info:${RESET}"
echo -e "   ${YELLOW}Command :${RESET} ssh root@$IP"
echo -e "   ${YELLOW}Port    :${RESET} 22"
echo -e "   ${YELLOW}Auth    :${RESET} Password Authentication Active"
echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${CYAN}✨ System is ready. Enjoy your high-performance server! 🚀${RESET}\n"
