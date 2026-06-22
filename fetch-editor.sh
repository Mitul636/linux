#!/bin/bash

# --- Color Variables ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root.${NC}"
   exit 1
fi

# Target user for config files (if run via sudo, gets the real user)
TARGET_USER="${SUDO_USER:-$USER}"
HOME_DIR=$(eval echo ~$TARGET_USER)

# --- Core Functions ---

detect_environment() {
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${YELLOW}Running Auto-Detection...${NC}"
    # Running the user's detection script
    if curl -sSL https://raw.githubusercontent.com/Mitul636/linux/main/detect-vps.sh | bash; then
        echo -e "${GREEN}Detection Complete.${NC}"
    else
        echo -e "${RED}Failed to fetch remote detection script. Using local fallback...${NC}"
        if command -v systemd-detect-virt >/dev/null 2>&1; then
            echo -e "Detected Virt: ${GREEN}$(systemd-detect-virt)${NC}"
        else
            echo -e "Detected Virt: ${YELLOW}Unknown/Physical${NC}"
        fi
    fi
    echo -e "${CYAN}=========================================${NC}"
    echo ""
}

apply_local_spoof() {
    local new_name="$1"
    
    # Neofetch Spoofing
    local neo_conf="$HOME_DIR/.config/neofetch/config.conf"
    if [ -f "$neo_conf" ]; then
        # Replace the model line with a custom print line
        sed -i "s/info \"Host\" model.*/prin \"Host\" \"$new_name\"/" "$neo_conf"
        echo -e "${GREEN}[✔] Neofetch config updated.${NC}"
    else
        echo -e "${YELLOW}[!] Neofetch config not found at $neo_conf. Run 'neofetch' once to generate it.${NC}"
    fi

    # Fastfetch Spoofing
    local ff_conf="$HOME_DIR/.config/fastfetch/config.jsonc"
    if [ -f "$ff_conf" ]; then
        # Replace the standard "host" module with a custom module containing the new name
        sed -i "s/\"host\",/{ \"type\": \"custom\", \"key\": \"Host\", \"format\": \"$new_name\" },/g" "$ff_conf"
        echo -e "${GREEN}[✔] Fastfetch config updated.${NC}"
    else
         echo -e "${YELLOW}[!] Fastfetch config not found at $ff_conf. Run 'fastfetch --gen-config' once to generate it.${NC}"
    fi
}

reset_local_spoof() {
    local neo_conf="$HOME_DIR/.config/neofetch/config.conf"
    if [ -f "$neo_conf" ]; then
        sed -i "s/prin \"Host\".*/info \"Host\" model/" "$neo_conf"
        echo -e "${GREEN}[✔] Neofetch reverted to default.${NC}"
    fi

    local ff_conf="$HOME_DIR/.config/fastfetch/config.jsonc"
    if [ -f "$ff_conf" ]; then
        sed -i 's/{ "type": "custom", "key": "Host".*}/"host",/g' "$ff_conf"
        echo -e "${GREEN}[✔] Fastfetch reverted to default.${NC}"
    fi
}

apply_system_spoof() {
    local new_name="$1"
    echo "$new_name" > /etc/custom_host_model

    # Create a systemd service to make the bind mount persistent across reboots
    cat <<EOF > /etc/systemd/system/spoof-host.service
[Unit]
Description=Spoof Host Name for Fetch Tools & Future LXC Containers
After=multi-user.target

[Service]
Type=oneshot
ExecStart=-/bin/mount -o bind /etc/custom_host_model /sys/class/dmi/id/product_name
ExecStart=-/bin/mount -o bind /etc/custom_host_model /sys/devices/virtual/dmi/id/product_name
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now spoof-host.service >/dev/null 2>&1
    
    # Apply immediately
    mount -o bind /etc/custom_host_model /sys/class/dmi/id/product_name 2>/dev/null
    mount -o bind /etc/custom_host_model /sys/devices/virtual/dmi/id/product_name 2>/dev/null
    echo -e "${GREEN}[✔] System-wide Host Spoofing applied! Future LXC containers will inherit this automatically.${NC}"
}

reset_system_spoof() {
    systemctl disable --now spoof-host.service >/dev/null 2>&1
    umount /sys/class/dmi/id/product_name 2>/dev/null
    umount /sys/devices/virtual/dmi/id/product_name 2>/dev/null
    rm -f /etc/custom_host_model /etc/systemd/system/spoof-host.service
    systemctl daemon-reload
    echo -e "${GREEN}[✔] System-wide Host Spoofing removed.${NC}"
}

check_default() {
    echo -e "${CYAN}--- Current Output ---${NC}"
    if command -v neofetch >/dev/null 2>&1; then
        neofetch | grep -i "Host"
    fi
    if command -v fastfetch >/dev/null 2>&1; then
        fastfetch | grep -i "Host"
    fi
    echo "----------------------"
}

# --- Menus ---

handle_submenu() {
    local env_type="$1"
    while true; do
        echo -e "\n${YELLOW}--- Actions for: $env_type ---${NC}"
        echo "1) Change Host Name"
        echo "2) Reset to Default"
        echo "3) Check Current (Default Viewer)"
        echo "4) Return to Main Menu"
        read -p "Select an action [1-4]: " sub_choice

        case $sub_choice in
            1)
                read -p "Enter the NEW Host Name: " new_host
                if [ "$env_type" == "Main_VPS" ]; then
                    apply_system_spoof "$new_host"
                else
                    apply_local_spoof "$new_host"
                fi
                ;;
            2)
                if [ "$env_type" == "Main_VPS" ]; then
                    reset_system_spoof
                else
                    reset_local_spoof
                fi
                ;;
            3)
                check_default
                ;;
            4)
                return
                ;;
            *)
                echo -e "${RED}Invalid option. Try again.${NC}"
                ;;
        esac
    done
}

main_menu() {
    while true; do
        clear
        echo -e "${CYAN}====================================================${NC}"
        echo -e "${GREEN}      Neofetch & Fastfetch Host Spoofer Script      ${NC}"
        echo -e "${CYAN}====================================================${NC}"
        echo "1) Inside LXC / LXC --vm (Applies local config override)"
        echo "2) Main VPS Node (Applies global hypervisor spoof for future LXC)"
        echo "3) Inside QEMU VPS (Applies local config override)"
        echo "4) Exit"
        echo -e "${CYAN}====================================================${NC}"
        read -p "Select your environment [1-4]: " choice

        case $choice in
            1)
                detect_environment
                handle_submenu "Inside_LXC"
                ;;
            2)
                detect_environment
                handle_submenu "Main_VPS"
                ;;
            3)
                detect_environment
                handle_submenu "Inside_QEMU"
                ;;
            4)
                echo -e "${GREEN}Exiting...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Press Enter to try again.${NC}"
                read
                ;;
        esac
    done
}

# Start the script
main_menu
