#!/bin/bash
# =====================================================================
# CUSTOM PROOT OS INSTALLER SCRIPT
# Supports: Ubuntu, Debian, CentOS with Multi-Version Selection
# Features: Auto-Detection, Error Logging, Multi-Level Menus
# =====================================================================

# --- Configurations ---
ROOTFS_DIR="$(pwd)/rootfs"
MAX_RETRIES=3
TIMEOUT=15
ERROR_LOG="install_error.log"

# --- Colors ---
RESET='\033[0m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'

# =====================================================================
# ERROR HANDLING SYSTEM
# =====================================================================
log_error() {
    local error_msg="$1"
    echo -e "${RED}[ERROR] $error_msg${RESET}"
    echo "[$(date)] ERROR: $error_msg" >> "$ERROR_LOG"
    echo -e "${YELLOW}Please check $ERROR_LOG for detailed failure history.${RESET}"
    exit 1
}

# Auto-detects if the last command failed and throws a specific error
check_status() {
    if [ $? -ne 0 ]; then
        log_error "$1"
    fi
}

# =====================================================================
# AUTO-DETECTION SYSTEM (Arch & Dependencies)
# =====================================================================
detect_system() {
    echo -e "${CYAN}[*] Detecting system architecture...${RESET}"
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64) ARCH_ALT="amd64" ;;
        aarch64|arm64) ARCH_ALT="arm64" ;;
        armv7l|armv8l) ARCH_ALT="armhf" ;;
        i386|i686) ARCH_ALT="i386" ;;
        *) log_error "Unsupported architecture: $ARCH. This script requires amd64, arm64, armhf, or i386." ;;
    esac
    echo -e "${GREEN}[+] Architecture detected: $ARCH_ALT ($ARCH)${RESET}"
    
    echo -e "${CYAN}[*] Checking required dependencies...${RESET}"
    for cmd in wget curl tar xz proot; do
        if ! command -v $cmd >/dev/null 2>&1; then
            echo -e "${YELLOW}[!] Missing dependency: $cmd. Attempting to install...${RESET}"
            # Auto-install missing packages based on the package manager
            if command -v apt >/dev/null; then apt update && apt install -y $cmd
            elif command -v apk >/dev/null; then apk add $cmd
            elif command -v yum >/dev/null; then yum install -y $cmd
            elif command -v pkg >/dev/null; then pkg install -y $cmd
            else
                log_error "Could not install '$cmd' automatically. Please install your package manager manually."
            fi
            check_status "Failed to auto-install dependency: $cmd"
        fi
    done
}

# =====================================================================
# MENU SYSTEM
# =====================================================================
main_menu() {
    clear
    echo -e "${MAGENTA}"
    echo "██████╗ ██████╗  ██████╗  ██████╗ ████████╗"
    echo "██╔══██╗██╔══██╗██╔═══██╗██╔═══██╗╚══██╔══╝"
    echo "██████╔╝██████╔╝██║   ██║██║   ██║   ██║   "
    echo "██╔═══╝ ██╔══██╗██║   ██║██║   ██║   ██║   "
    echo "██║     ██║  ██║╚██████╔╝╚██████╔╝   ██║   "
    echo "╚═╝     ╚═╝  ╚═╝ ╚═════╝  ╚═════╝    ╚═╝   "
    echo -e "${RESET}"
    echo -e "${CYAN}=======================================${RESET}"
    echo -e "${GREEN}      Proot OS Installer Menu          ${RESET}"
    echo -e "${CYAN}=======================================${RESET}"
    echo -e "1) ${YELLOW}Ubuntu${RESET}"
    echo -e "2) ${YELLOW}Debian${RESET}"
    echo -e "3) ${YELLOW}CentOS${RESET}"
    echo -e "4) ${RED}Exit${RESET}"
    echo -e "${CYAN}=======================================${RESET}"
    read -p "Select an OS [1-4]: " os_choice

    case $os_choice in
        1) OS_NAME="Ubuntu"; ubuntu_menu ;;
        2) OS_NAME="Debian"; debian_menu ;;
        3) OS_NAME="CentOS"; centos_menu ;;
        4) echo "Exiting..."; exit 0 ;;
        *) echo -e "${RED}Invalid option! Try again.${RESET}"; sleep 1; main_menu ;;
    esac
}

ubuntu_menu() {
    clear
    echo -e "${CYAN}--- Select Ubuntu Version ---${RESET}"
    echo "1) Ubuntu 24.04 LTS (Noble Numbat)"
    echo "2) Ubuntu 22.04 LTS (Jammy Jellyfish)"
    echo "3) Ubuntu 20.04 LTS (Focal Fossa)"
    echo "4) Go Back"
    read -p "Select Version [1-4]: " ver_choice

    case $ver_choice in
        1) 
            OS_VER="24.04"
            ROOTFS_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04-base-${ARCH_ALT}.tar.gz"
            ;;
        2) 
            OS_VER="22.04"
            ROOTFS_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.5-base-${ARCH_ALT}.tar.gz"
            ;;
        3) 
            OS_VER="20.04"
            ROOTFS_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.6-base-${ARCH_ALT}.tar.gz"
            ;;
        4) main_menu; return ;;
        *) echo -e "${RED}Invalid Selection!${RESET}"; sleep 1; ubuntu_menu; return ;;
    esac
    confirm_installation
}

debian_menu() {
    clear
    echo -e "${CYAN}--- Select Debian Version ---${RESET}"
    echo "1) Debian 12 (Bookworm)"
    echo "2) Debian 11 (Bullseye)"
    echo "3) Debian 10 (Buster)"
    echo "4) Go Back"
    read -p "Select Version [1-4]: " ver_choice

    # Relying on termux proot-distro archives for reliable non-ubuntu files
    case $ver_choice in
        1) 
            OS_VER="12 (Bookworm)"
            ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v3.15.0/debian-bookworm-${ARCH}.tar.xz"
            ;;
        2) 
            OS_VER="11 (Bullseye)"
            ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v3.15.0/debian-bullseye-${ARCH}.tar.xz"
            ;;
        3) 
            OS_VER="10 (Buster)"
            ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v3.15.0/debian-buster-${ARCH}.tar.xz"
            ;;
        4) main_menu; return ;;
        *) echo -e "${RED}Invalid Selection!${RESET}"; sleep 1; debian_menu; return ;;
    esac
    confirm_installation
}

centos_menu() {
    clear
    echo -e "${CYAN}--- Select CentOS Version ---${RESET}"
    echo "1) CentOS Stream 9"
    echo "2) CentOS 8"
    echo "3) CentOS 7"
    echo "4) Go Back"
    read -p "Select Version [1-4]: " ver_choice

    case $ver_choice in
        1) 
            OS_VER="Stream 9"
            ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v3.15.0/centos-stream-9-${ARCH}.tar.xz"
            ;;
        2) 
            OS_VER="8"
            ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v3.15.0/centos-8-${ARCH}.tar.xz"
            ;;
        3) 
            OS_VER="7"
            ROOTFS_URL="https://github.com/termux/proot-distro/releases/download/v3.15.0/centos-7-${ARCH}.tar.xz"
            ;;
        4) main_menu; return ;;
        *) echo -e "${RED}Invalid Selection!${RESET}"; sleep 1; centos_menu; return ;;
    esac
    confirm_installation
}

confirm_installation() {
    echo -e "\n${GREEN}You have selected: ${OS_NAME} ${OS_VER}${RESET}"
    echo -e "${YELLOW}Rootfs Source URL:${RESET} $ROOTFS_URL"
    read -p "Proceed with downloading & installation? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Installation aborted by user."
        sleep 1
        main_menu
    else
        install_os
    fi
}

# =====================================================================
# CORE INSTALLATION LOGIC
# =====================================================================
install_os() {
    echo -e "\n${CYAN}[*] Preparing Environment for $OS_NAME $OS_VER...${RESET}"
    
    # Clean previous installation if exists
    if [ -d "$ROOTFS_DIR" ]; then
        echo -e "${YELLOW}[!] Existing rootfs found. Wiping to install fresh OS...${RESET}"
        rm -rf "$ROOTFS_DIR"
    fi
    mkdir -p "$ROOTFS_DIR"

    # Step 1: Downloading
    echo -e "${CYAN}[*] Downloading RootFS...${RESET}"
    
    # Detect extension to determine extraction method
    ARCHIVE_EXT="${ROOTFS_URL##*.}"
    if [[ "$ROOTFS_URL" == *".tar.gz"* ]]; then ARCHIVE_EXT="tar.gz"; fi
    if [[ "$ROOTFS_URL" == *".tar.xz"* ]]; then ARCHIVE_EXT="tar.xz"; fi
    
    wget --tries="$MAX_RETRIES" --timeout="$TIMEOUT" --show-progress -O "/tmp/rootfs.$ARCHIVE_EXT" "$ROOTFS_URL"
    check_status "Failed to download $OS_NAME $OS_VER rootfs. The URL might be down, or you have no internet access."

    # Step 2: Extraction
    echo -e "${CYAN}[*] Extracting RootFS... This may take a moment.${RESET}"
    if [ "$ARCHIVE_EXT" = "tar.gz" ]; then
        tar -zxf "/tmp/rootfs.$ARCHIVE_EXT" -C "$ROOTFS_DIR"
    else
        tar -xJf "/tmp/rootfs.$ARCHIVE_EXT" -C "$ROOTFS_DIR"
    fi
    check_status "Failed to extract rootfs archive. The archive might be corrupted or incomplete."
    
    # Cleanup archive
    rm -f "/tmp/rootfs.$ARCHIVE_EXT"

    # Step 3: DNS Setup
    echo -e "${CYAN}[*] Configuring DNS & Environment...${RESET}"
    echo "nameserver 1.1.1.1" > "$ROOTFS_DIR/etc/resolv.conf"
    echo "nameserver 8.8.8.8" >> "$ROOTFS_DIR/etc/resolv.conf"
    
    # Generate Launch Script
    create_launch_script
    
    echo -e "${GREEN}[+] Installation Completed Successfully!${RESET}"
    echo -e "${YELLOW}To start your new OS, simply run:${RESET} ./start_os.sh"
    exit 0
}

create_launch_script() {
    cat > start_os.sh <<- EOF
#!/bin/bash
ROOTFS_DIR="$ROOTFS_DIR"
export PATH="\$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echo -e "\\033[1;32m[*] Launching $OS_NAME $OS_VER Environment...\\033[0m"

# Execute Proot based on HopinBoyz / FoxyTouxxx logic
exec proot \\
    --rootfs="\$ROOTFS_DIR" \\
    -0 -w /root \\
    -b /dev -b /sys -b /proc -b /tmp \\
    -b /etc/resolv.conf \\
    --kill-on-exit \\
    /usr/bin/env -i \\
    HOME=/root \\
    TERM="\$TERM" \\
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \\
    /bin/bash --login
EOF
    chmod +x start_os.sh
}

# --- Start Script ---
detect_system
main_menu
