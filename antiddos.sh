#!/bin/bash
# antiddos - Advanced Linux Server IPTables Anti-DDoS Script
# Description: Combines mangle/PREROUTING optimization, SYNPROXY, IPSet, and Kernel tuning.

# Colors & Symbols
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CHECK="✅"
CROSS="❌"
INFO="ℹ️"
WARN="⚠️"
FIRE="🔥"

# Paths
IPT=$(which iptables 2>/dev/null)
IPS=$(which iptables-save 2>/dev/null)
IPSET=$(which ipset 2>/dev/null)

function show_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "    ___          __  _ ____  ____       ____ "
    echo "   /   |  ____  / /_(_) __ \/ __ \____ / ___|"
    echo "  / /| | / __ \/ __/ / / / / / / / __ \\___ \ "
    echo " / ___ |/ / / / /_/ / /_/ / /_/ / /_/ /___) |"
    echo "/_/  |_/_/ /_/\__/_/_____/_____/\____/|____/ "
    echo -e "${NC}"
    echo -e "${BLUE} High-Performance Anti-DDoS Firewall Management Tool${NC}"
    echo ""
}

function check_root() {
    if [[ $EUID -ne 0 ]]; then
        show_banner
        echo -e "${RED}${CROSS} Error: This script must be run with root privileges (sudo).${NC}"
        exit 1
    fi
}

function scan_system() {
    echo -e "${PURPLE}${BOLD}--- SCANNING SYSTEM & DEPENDENCIES ---${NC}"
    local missing_pkgs=""

    # Check for basic tools
    for pkg in iptables ipset ss sysctl; do
        if ! command -v $pkg >/dev/null 2>&1; then
            echo -e "${RED}${CROSS} Missing dependency: $pkg${NC}"
            missing_pkgs="$missing_pkgs $pkg"
        else
            echo -e "${GREEN}${CHECK} Found: $pkg${NC}"
        fi
    done

    # Check for persistence packages
    if [[ ! -d "/etc/iptables" ]]; then
        echo -e "${RED}${CROSS} Missing dependency: iptables-persistent (Debian/Ubuntu) or iptables-services (RHEL/CentOS)${NC}"
        missing_pkgs="$missing_pkgs iptables-persistent"
    else
        echo -e "${GREEN}${CHECK} Found: iptables-persistent config directory${NC}"
    fi

    # Auto-install missing packages
    if [[ -n "$missing_pkgs" ]]; then
        echo -e "${YELLOW}${INFO} Attempting to install missing packages...${NC}"
        if command -v apt-get >/dev/null; then
            apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y iptables ipset iproute2 procps iptables-persistent
        elif command -v yum >/dev/null; then
            yum install -y iptables ipset iproute procps-ng iptables-services
        else
            echo -e "${RED}${CROSS} Unsupported package manager. Please install missing packages manually.${NC}"
            exit 1
        fi
        # Re-evaluate paths after install
        IPT=$(which iptables)
        IPS=$(which iptables-save)
        IPSET=$(which ipset)
        echo -e "${GREEN}${CHECK} Dependencies resolved!${NC}"
    else
        echo -e "${GREEN}${CHECK} System is fully supported and ready.${NC}"
    fi
    echo ""
}

function tune_kernel() {
    echo -e "${CYAN} - Tuning Kernel (sysctl) for High-Throughput DDoS Mitigation...${NC}"
    sysctl -w net.netfilter.nf_conntrack_max=10000000 >/dev/null 2>&1
    sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=1800 >/dev/null 2>&1
    sysctl -w net.netfilter.nf_conntrack_tcp_timeout_syn_recv=20 >/dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=262144 >/dev/null 2>&1
    sysctl -w net.core.somaxconn=65535 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_synack_retries=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.conf.all.rp_filter=1 >/dev/null 2>&1
}

function clear_rules() {
    echo -e "${YELLOW}${INFO} Clearing all iptables rules...${NC}"
    $IPT -P INPUT ACCEPT
    $IPT -P FORWARD ACCEPT
    $IPT -P OUTPUT ACCEPT
    $IPT -t nat -F
    $IPT -t mangle -F
    $IPT -t raw -F
    $IPT -F
    $IPT -X
    
    # Flush ipsets
    $IPSET destroy antiddos_blacklist 2>/dev/null
    $IPSET destroy antiddos_whitelist 2>/dev/null
    echo -e "${GREEN}${CHECK} Rules and sets cleared successfully.${NC}"
}

function start_antiddos() {
    show_banner
    scan_system
    
    echo -e "${YELLOW}${INFO} Applying Anti-DDoS Architecture...${NC}"
    $IPT -F
    $IPT -t mangle -F
    $IPT -t raw -F
    
    tune_kernel

    # 1. IPSet Setup
    echo -e "${CYAN} - Initializing IPSet (Whitelist & Blacklist)...${NC}"
    $IPSET create antiddos_blacklist hash:ip 2>/dev/null
    $IPSET create antiddos_whitelist hash:ip 2>/dev/null
    
    # Whitelist & Blacklist hooks (Highest priority in mangle/PREROUTING)
    $IPT -t mangle -A PREROUTING -m set --match-set antiddos_whitelist src -j ACCEPT
    $IPT -t mangle -A PREROUTING -m set --match-set antiddos_blacklist src -j DROP

    # 2. Localhost and Established connections
    echo -e "${CYAN} - Permitting Loopback and Established Connections...${NC}"
    $IPT -A INPUT -i lo -j ACCEPT
    $IPT -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Allow SSH immediately to prevent admin lockout
    SSH_PORT=$(ss -tlpn | grep sshd | awk '{print $4}' | awk -F':' '{print $NF}' | head -n1 || echo 22)
    $IPT -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT

    # 3. High-Performance Packet Filtering (mangle PREROUTING)
    echo -e "${CYAN} - Setting up Mangle PREROUTING (Invalid, Flags, MSS)...${NC}"
    # Drop Invalid states instantly
    $IPT -t mangle -A PREROUTING -m conntrack --ctstate INVALID -j DROP
    # Block new packets that are not SYN
    $IPT -t mangle -A PREROUTING -p tcp ! --syn -m conntrack --ctstate NEW -j DROP
    # Block uncommon MSS values
    $IPT -t mangle -A PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP
    
    # Bogus TCP Flags
    $IPT -t mangle -A PREROUTING -p tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -j DROP
    $IPT -t mangle -A PREROUTING -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
    $IPT -t mangle -A PREROUTING -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
    $IPT -t mangle -A PREROUTING -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
    $IPT -t mangle -A PREROUTING -p tcp --tcp-flags FIN,ACK FIN -j DROP

    # 4. Anti-Spoofing (Martians)
    echo -e "${CYAN} - Dropping Spoofed Private IPs from Public Interface...${NC}"
    IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [[ -n "$IFACE" ]]; then
        $IPT -t mangle -A PREROUTING -i "$IFACE" -s 224.0.0.0/4 -j DROP
        $IPT -t mangle -A PREROUTING -i "$IFACE" -s 240.0.0.0/5 -j DROP
        $IPT -t mangle -A PREROUTING -i "$IFACE" -s 0.0.0.0/8 -j DROP
        $IPT -t mangle -A PREROUTING -i "$IFACE" -s 255.255.255.255/32 -j DROP
    fi

    # 5. SYNPROXY for Web Traffic (80/443)
    echo -e "${CYAN} - Enabling SYNPROXY for HTTP/HTTPS (Port 80, 443)...${NC}"
    $IPT -t raw -A PREROUTING -p tcp -m tcp --dport 80 --syn -j NOTRACK
    $IPT -t raw -A PREROUTING -p tcp -m tcp --dport 443 --syn -j NOTRACK
    $IPT -A INPUT -p tcp -m tcp --dport 80 -m conntrack --ctstate UNTRACKED,INVALID -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460
    $IPT -A INPUT -p tcp -m tcp --dport 443 -m conntrack --ctstate UNTRACKED,INVALID -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460

    # 6. Global Connlimit & Rate Limits (For remaining protocols)
    echo -e "${CYAN} - Applying UDP/ICMP and Connection Limits...${NC}"
    $IPT -A INPUT -p tcp --syn -m connlimit --connlimit-above 50 -j DROP
    $IPT -A INPUT -p udp -m conntrack --ctstate NEW -m limit --limit 20/s --limit-burst 40 -j ACCEPT
    $IPT -A INPUT -p udp -m conntrack --ctstate NEW -j DROP
    $IPT -A INPUT -p icmp -m limit --limit 2/s --limit-burst 5 -j ACCEPT
    $IPT -A INPUT -p icmp -j DROP

    echo -e "${GREEN}${CHECK}${BOLD} Architecture applied successfully!${NC}"
}

function manage_ipset() {
    local list=$1
    local ip=$2
    if [[ -z "$ip" || ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}${CROSS} Error: A valid IPv4 address is required.${NC}"
        return
    fi
    $IPSET create "antiddos_$list" hash:ip 2>/dev/null
    $IPSET add "antiddos_$list" "$ip"
    
    if [[ "$list" == "whitelist" ]]; then
        echo -e "${GREEN}${CHECK} Whitelisted IP: $ip${NC}"
    else
        echo -e "${RED}${WARN} Blacklisted IP: $ip${NC}"
    fi
}

function monitor_traffic() {
    show_banner
    echo -e "${BOLD}${FIRE} Entering real-time monitoring mode (Press Ctrl+C to exit)...${NC}"
    sleep 1
    while true; do
        clear
        show_banner
        echo -e "${BOLD}${BLUE}--- REAL-TIME DROPPED PACKETS (MANGLE & FILTER) ---${NC}"
        $IPT -t mangle -L PREROUTING -n -v | grep -E "DROP|REJECT" | grep -v "0     0"
        $IPT -L INPUT -n -v | grep -E "DROP|REJECT" | grep -v "0     0"
        
        echo -e "\n${BOLD}${BLUE}--- CURRENT CONNECTIONS BY PORT ---${NC}"
        ss -tun state established | awk 'NR>1 {print $4}' | awk -F':' '{print $NF}' | sort | uniq -c | sort -nr | head -n 5
        sleep 2
    done
}

function save_persistence() {
    echo -e "${YELLOW}${INFO} Saving current rules and ipsets for persistence...${NC}"
    if command -v netfilter-persistent >/dev/null; then
        ipset save > /etc/iptables/ipsets
        netfilter-persistent save
        echo -e "${GREEN}${CHECK} Rules saved via netfilter-persistent.${NC}"
    elif [[ -d "/etc/iptables" ]]; then
        $IPS > /etc/iptables/rules.v4
        ipset save > /etc/iptables/ipsets
        echo -e "${GREEN}${CHECK} Rules saved to /etc/iptables/rules.v4 and ipsets${NC}"
    else
        echo -e "${RED}${CROSS} Error: Persistence framework not found.${NC}"
    fi
}

function status_antiddos() {
    show_banner
    echo -e "${PURPLE}${BOLD}--- PROTECTION STATUS ---${NC}"
    if $IPT -t mangle -L PREROUTING | grep -q "INVALID"; then
        echo -e "${GREEN}${CHECK} Anti-DDoS Core Engine: ACTIVE${NC}"
    else
        echo -e "${RED}${CROSS} Anti-DDoS Core Engine: INACTIVE${NC}"
    fi
    echo -e "\n${BLUE}${BOLD}Blacklisted IPs (IPSet):${NC}"
    $IPSET list antiddos_blacklist 2>/dev/null | grep -E '^[0-9]' || echo "None"
    echo -e "\n${BLUE}${BOLD}Whitelisted IPs (IPSet):${NC}"
    $IPSET list antiddos_whitelist 2>/dev/null | grep -E '^[0-9]' || echo "None"
}

function show_usage() {
    show_banner
    echo -e "${BOLD}Usage Configuration:${NC} Requires Root Privileges"
    echo ""
    echo -e "${BOLD}Command and Description${NC}"
    echo -e "------------------------------------------------------------"
    echo -e " ${CYAN}sudo ./antiddos.sh start${NC}     Apply all Anti-DDoS protection rules"
    echo -e " ${CYAN}sudo ./antiddos.sh stop${NC}      Remove all rules and revert to defaults"
    echo -e " ${CYAN}sudo ./antiddos.sh status${NC}    View current protection and rule status"
    echo -e " ${CYAN}sudo ./antiddos.sh monitor${NC}   Launch real-time monitoring dashboard"
    echo -e " ${CYAN}sudo ./antiddos.sh whitelist${NC} Add an IP address to the whitelist (${YELLOW}<IP>${NC})"
    echo -e " ${CYAN}sudo ./antiddos.sh blacklist${NC} Block a specific IP address (${YELLOW}<IP>${NC})"
    echo -e " ${CYAN}sudo ./antiddos.sh save${NC}      Make current rules persistent across reboots"
    echo -e " ${CYAN}sudo ./antiddos.sh clear${NC}     Flush all iptables rules"
    echo -e "------------------------------------------------------------"
    echo -e "${INFO} First time run will automatically scan and install missing packages."
}

check_root

case "$1" in
    start)     start_antiddos ;;
    stop|clear) clear_rules ;;
    status)    status_antiddos ;;
    monitor)   monitor_traffic ;;
    whitelist) manage_ipset "whitelist" "$2" ;;
    blacklist) manage_ipset "blacklist" "$2" ;;
    save)      save_persistence ;;
    scan)      scan_system ;;
    *)         show_usage ; exit 1 ;;
esac
exit 0
