#!/bin/bash
# ================================
# TigerHost Premium MOTD Installer
# ================================

set -e

echo "🔧 Installing TigerHost Premium MOTD..."

# ================================
# Disable ALL default MOTD scripts
# ================================
if [ -d /etc/update-motd.d ]; then
  chmod -x /etc/update-motd.d/* 2>/dev/null || true
fi

# ================================
# Create Custom MOTD
# ================================
cat << 'EOF' > /etc/update-motd.d/00-tigerhost
#!/bin/bash

# ===== Colors =====
ORANGE="\e[38;5;208m"
YELLOW="\e[38;5;220m"
CYAN="\e[38;5;51m"
BLUE="\e[38;5;39m"
GRAY="\e[38;5;245m"
RESET="\e[0m"

# ===== System Info =====
HOSTNAME=$(hostname)
OS=$(awk -F= '/PRETTY_NAME/ {print $2}' /etc/os-release | tr -d '"')
KERNEL=$(uname -r)
UPTIME=$(uptime -p | sed 's/up //')
LOAD=$(cut -d " " -f1 /proc/loadavg)

# Memory Info
read MEM_TOTAL MEM_USED <<< $(free -m | awk '/Mem:/ {print $2, $3}')
MEM_PERC=$((MEM_USED * 100 / MEM_TOTAL))

# Disk Info
read DISK_USED DISK_TOTAL DISK_PERC <<< $(df -h / | awk 'NR==2 {print $3, $2, $5}')

# Network, Users & Processes
IP=$(hostname -I | awk '{print $1}')
USERS=$(who | wc -l)
PROCS=$(ps -e --no-headers | wc -l)

# ===== Clear spacing =====
echo ""

# ===== Logo =====
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

# ===== Welcome =====
echo -e "${ORANGE}Welcome to TigerHost Datacenter 🐯🚀${RESET}"
echo -e "${BLUE}High Performance • Secure • Reliable Infrastructure${RESET}"
echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ===== Stats =====
printf "${CYAN}%-16s${RESET} %s\n" "Hostname:" "$HOSTNAME"
printf "${CYAN}%-16s${RESET} %s\n" "Operating OS:" "$OS"
printf "${CYAN}%-16s${RESET} %s\n" "Kernel:" "$KERNEL"
printf "${CYAN}%-16s${RESET} %s\n" "Uptime:" "$UPTIME"
printf "${CYAN}%-16s${RESET} %s\n" "CPU Load:" "$LOAD"
printf "${CYAN}%-16s${RESET} %sMB / %sMB (${YELLOW}%s%%${RESET})\n" "Memory:" "$MEM_USED" "$MEM_TOTAL" "$MEM_PERC"
printf "${CYAN}%-16s${RESET} %s / %s (${YELLOW}%s${RESET})\n" "Disk:" "$DISK_USED" "$DISK_TOTAL" "$DISK_PERC"
printf "${CYAN}%-16s${RESET} %s\n" "Processes:" "$PROCS"
printf "${CYAN}%-16s${RESET} %s\n" "Users Online:" "$USERS"
printf "${CYAN}%-16s${RESET} %s\n" "IP Address:" "$IP"

echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ===== Footer =====
echo -e "${ORANGE}Support:${RESET}  support@tigerhost.site"
echo -e "${ORANGE}Discord:${RESET}  https://dsc.gg/tigerhost"
echo -e "${ORANGE}Website:${RESET}  https://www.tigerhost.space/"
echo -e "${CYAN}Quality Wise — No Compromise 👑${RESET}"
echo ""
EOF

chmod +x /etc/update-motd.d/00-tigerhost

echo "🎉 TigerHost Premium MOTD Installed Successfully!"
echo "➡ Logout & SSH again to view your new MOTD."
