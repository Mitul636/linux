#!/bin/bash
# antiddos - Advanced Linux Server IPTables Anti-DDoS Script
# Author: Ismail Tasdelen | Enhanced Edition

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

# Default Environment Variable Fallbacks
CONN_LIMIT="${CONN_LIMIT:-50}"
UDP_GAME_PORTS="${UDP_GAME_PORTS:-27015 7777}"
CUSTOM_SSH_PORT=""

# Paths
IPT=$(which iptables 2>/dev/null)
IPS=$(which iptables-save 2>/dev/null)
IPSET=$(which ipset 2>/dev/null)

# Parse optional flags before standard subcommands
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh-port)
            CUSTOM_SSH_PORT="$2"
            shift 2
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done
set -- "${ARGS[@]}"

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

function get_ssh_port() {
    if [[ -n "$CUSTOM_SSH_PORT" && "$CUSTOM_SSH_PORT" =~ ^[0-9]+$ ]]; then
        echo "$CUSTOM_SSH_PORT"
        return
    fi

    local port=""
    if command -v ss >/dev/null 2>&1; then
        port=$(ss -tlpn 2>/dev/null | grep sshd | awk '{print $4}' | awk -F':' '{print $NF}' | grep -E '^[0-9]+$' | head -n1)
    fi

    if [[ -z "$port" || ! "$port" =~ ^[0-9]+$ ]]; then
        echo "22"
    else
        echo "$port"
    fi
}

function scan_system() {
    echo -e "${PURPLE}${BOLD}--- SCANNING SYSTEM & DEPENDENCIES ---${NC}"
    local missing_pkgs=""

    for pkg in iptables ipset ss sysctl; do
        if ! command -v $pkg >/dev/null 2>&1; then
            echo -e "${RED}${CROSS} Missing dependency: $pkg${NC}"
            missing_pkgs="$missing_pkgs $pkg"
        else
            echo -e "${GREEN}${CHECK} Found: $pkg${NC}"
        fi
    done

    if [[ ! -d "/etc/iptables" ]]; then
        echo -e "${RED}${CROSS} Missing dependency directory: /etc/iptables${NC}"
        missing_pkgs="$missing_pkgs iptables-persistent"
    else
        echo -e "${GREEN}${CHECK} Found: /etc/iptables persistence folder${NC}"
    fi

    if [[ -n "$missing_pkgs" ]]; then
        echo -e "${YELLOW}${INFO} Installing missing dependencies...${NC}"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y iptables ipset iproute2 procps iptables-persistent
        elif command -v yum >/dev/null 2>&1; then
            yum install -y iptables ipset iproute procps-ng iptables-services
        else
            echo -e "${RED}${CROSS} Unknown package manager. Install manually: $missing_pkgs${NC}"
            exit 1
        fi
        IPT=$(which iptables)
        IPS=$(which iptables-save)
        IPSET=$(which ipset)
        echo -e "${GREEN}${CHECK} All dependencies installed successfully!${NC}"
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
    echo -e "${GREEN}${CHECK} Kernel tuning complete.${NC}"
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
    
    $IPT -t mangle -A PREROUTING -m set --match-set antiddos_whitelist src -j ACCEPT
    $IPT -t mangle -A PREROUTING -m set --match-set antiddos_blacklist src -j DROP

    # 2. Localhost & Established Connections
    echo -e "${CYAN} - Permitting Loopback and Established Connections...${NC}"
    $IPT -A INPUT -i lo -j ACCEPT
    $IPT -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Detect SSH Port Safely
    SSH_PORT=$(get_ssh_port)
    echo -e "${CYAN} - Protecting SSH Port ($SSH_PORT)...${NC}"
    $IPT -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT

    # 3. High-Performance Packet Filtering (Mangle PREROUTING)
    echo -e "${CYAN} - Setting up Mangle PREROUTING (Invalid, Flags, MSS)...${NC}"
    $IPT -t mangle -A PREROUTING -m conntrack --ctstate INVALID -j DROP
    $IPT -t mangle -A PREROUTING -p tcp ! --syn -m conntrack --ctstate NEW -j DROP
    $IPT -t mangle -A PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP
    
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

    # 5. SYNPROXY for Web Traffic
    echo -e "${CYAN} - Enabling SYNPROXY for HTTP/HTTPS (Port 80, 443)...${NC}"
    $IPT -t raw -A PREROUTING -p tcp -m tcp --dport 80 --syn -j NOTRACK
    $IPT -t raw -A PREROUTING -p tcp -m tcp --dport 443 --syn -j NOTRACK
    $IPT -A INPUT -p tcp -m tcp --dport 80 -m conntrack --ctstate UNTRACKED,INVALID -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460
    $IPT -A INPUT -p tcp -m tcp --dport 443 -m conntrack --ctstate UNTRACKED,INVALID -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460

    # 6. Global Connlimit & UDP Protection
    echo -e "${CYAN} - Applying Connection Limit ($CONN_LIMIT/IP)...${NC}"
    $IPT -A INPUT -p tcp --syn -m connlimit --connlimit-above "$CONN_LIMIT" -j DROP

    if [[ "$UDP_GAME_PORTS" == "*" ]]; then
        echo -e "${CYAN} - Guarding ALL UDP Ports...${NC}"
        $IPT -A INPUT -p udp -m conntrack --ctstate NEW -m limit --limit 20/s --limit-burst 40 -j ACCEPT
        $IPT -A INPUT -p udp -m conntrack --ctstate NEW -j DROP
    else
        for port in $UDP_GAME_PORTS; do
            if [[ "$port" =~ ^[0-9]+$ ]]; then
                echo -e "${CYAN} - Guarding UDP Port: $port...${NC}"
                $IPT -A INPUT -p udp --dport "$port" -m conntrack --ctstate NEW -m limit --limit 20/s --limit-burst 40 -j ACCEPT
                $IPT -A INPUT -p udp --dport "$port" -m conntrack --ctstate NEW -j DROP
            fi
        done
    fi

    # ICMP Flood Protection
    $IPT -A INPUT -p icmp -m limit --limit 2/s --limit-burst 5 -j ACCEPT
    $IPT -A INPUT -p icmp -j DROP

    echo -e "${GREEN}${CHECK}${BOLD} Architecture applied successfully!${NC}"
}

function manage_ipset() {
    local list=$1
    local action=$2
    local ip=$3

    $IPSET create "antiddos_$list" hash:ip 2>/dev/null

    if [[ "$action" == "list" ]]; then
        echo -e "${BLUE}${BOLD}--- $list IPs ---${NC}"
        $IPSET list "antiddos_$list" | grep -E '^[0-9]' || echo "No IPs found."
        return
    fi

    if [[ "$action" == "del" ]]; then
        if [[ -z "$ip" ]]; then
            echo -e "${RED}${CROSS} IP address required for deletion.${NC}"
            return
        fi
        $IPSET del "antiddos_$list" "$ip" 2>/dev/null
        echo -e "${GREEN}${CHECK} Removed $ip from $list.${NC}"
        return
    fi

    # If action was passed directly as IP address
    if [[ -z "$ip" && -n "$action" ]]; then
        ip="$action"
    fi

    if [[ -z "$ip" || ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}${CROSS} Error: A valid IPv4 address is required.${NC}"
        return
    fi

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
    if command -v netfilter-persistent >/dev/null 2>&1; then
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
    if $IPT -t mangle -L PREROUTING 2>/dev/null | grep -q "INVALID"; then
        echo -e "${GREEN}${CHECK} Anti-DDoS Core Engine: ACTIVE${NC}"
    else
        echo -e "${RED}${CROSS} Anti-DDoS Core Engine: INACTIVE${NC}"
    fi
    echo -e "\n${BLUE}${BOLD}Blacklisted IPs (IPSet):${NC}"
    $IPSET list antiddos_blacklist 2>/dev/null | grep -E '^[0-9]' || echo "None"
    echo -e "\n${BLUE}${BOLD}Whitelisted IPs (IPSet):${NC}"
    $IPSET list antiddos_whitelist 2>/dev/null | grep -E '^[0-9]' || echo "None"
}

function run_menu() {
    while true; do
        clear
        show_banner
        echo -e "${PURPLE}${BOLD}=================== INTERACTIVE MENU ===================${NC}"
        echo -e " ${CYAN}1)${NC} Start Anti-DDoS Protection"
        echo -e " ${CYAN}2)${NC} Stop / Clear All Rules"
        echo -e " ${CYAN}3)${NC} View Protection Status"
        echo -e " ${CYAN}4)${NC} Real-time Monitoring Dashboard"
        echo -e " ${CYAN}5)${NC} Whitelist Management"
        echo -e " ${CYAN}6)${NC} Blacklist Management"
        echo -e " ${CYAN}7)${NC} Run System Scan & Dependency Check"
        echo -e " ${CYAN}8)${NC} Exit"
        echo -e "${PURPLE}${BOLD}========================================================${NC}"
        read -rp "Select an option [1-8]: " choice
        case "$choice" in
            1) start_antiddos ;;
            2) clear_rules ;;
            3) status_antiddos ;;
            4) monitor_traffic ;;
            5)
                echo -e "\n${BOLD}Whitelist Operations:${NC} 1) List | 2) Add | 3) Remove"
                read -rp "Choice [1-3]: " wl_choice
                case "$wl_choice" in
                    1) manage_ipset "whitelist" "list" "" ;;
                    2) read -rp "Enter IP to whitelist: " ip; manage_ipset "whitelist" "add" "$ip" ;;
                    3) read -rp "Enter IP to remove: " ip; manage_ipset "whitelist" "del" "$ip" ;;
                esac
                ;;
            6)
                echo -e "\n${BOLD}Blacklist Operations:${NC} 1) List | 2) Add | 3) Remove"
                read -rp "Choice [1-3]: " bl_choice
                case "$bl_choice" in
                    1) manage_ipset "blacklist" "list" "" ;;
                    2) read -rp "Enter IP to blacklist: " ip; manage_ipset "blacklist" "add" "$ip" ;;
                    3) read -rp "Enter IP to remove: " ip; manage_ipset "blacklist" "del" "$ip" ;;
                esac
                ;;
            7) scan_system ;;
            8) echo -e "${GREEN}Exiting... Goodbye!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid option!${NC}" ;;
        esac
        echo ""
        read -rp "Press Enter to return to menu..."
    done
}

function show_usage() {
    show_banner
    echo -e "${BOLD}Usage Configuration:${NC} Requires Root Privileges"
    echo ""
    echo -e "${BOLD}COMMANDS${NC}"
    echo -e "  sudo ./antiddos.sh start                         Apply all Anti-DDoS protection rules"
    echo -e "  sudo ./antiddos.sh stop                          Remove all rules and revert to defaults"
    echo -e "  sudo ./antiddos.sh status                        View current protection and rule status"
    echo -e "  sudo ./antiddos.sh monitor                       Launch real-time monitoring dashboard"
    echo -e "  sudo ./antiddos.sh whitelist <IP>                Add an IP address to the whitelist"
    echo -e "  sudo ./antiddos.sh blacklist <IP>                Block a specific IP address"
    echo -e "  sudo ./antiddos.sh save                          Make current rules persistent across reboots"
    echo -e "  sudo ./antiddos.sh clear                         Flush all iptables rules"
    echo -e "  sudo ./antiddos.sh menu                          Open interactive dashboard menu"
    echo ""
    echo -e "${BOLD}EXTRA COMMANDS${NC}"
    echo -e "  sudo ./antiddos.sh restart                       Restart protection (stop + start)"
    echo -e "  sudo ./antiddos.sh scan                          Re-run system/dependency scan"
    echo -e "  sudo ./antiddos.sh tune                          Re-apply sysctl kernel hardening"
    echo -e "  sudo ./antiddos.sh whitelist list                Show whitelisted IPs"
    echo -e "  sudo ./antiddos.sh whitelist del <IP>            Remove an IP from the whitelist"
    echo -e "  sudo ./antiddos.sh blacklist list                Show blacklisted IPs"
    echo -e "  sudo ./antiddos.sh blacklist del <IP>            Remove an IP from the blacklist"
    echo ""
    echo -e "${BOLD}OPTIONS & ENVIRONMENT${NC}"
    echo -e "  --ssh-port <PORT>                                Force SSH port (skips auto-detection)"
    echo -e "  UDP_GAME_PORTS=\"27015 7777\"                      UDP ports guarded against flood (* = all)"
    echo -e "  CONN_LIMIT=<n>                                   Max concurrent connections per source IP"
}

check_root

case "$1" in
    start)     start_antiddos ;;
    stop|clear) clear_rules ;;
    restart)   clear_rules; start_antiddos ;;
    status)    status_antiddos ;;
    monitor)   monitor_traffic ;;
    scan)      scan_system ;;
    tune)      tune_kernel ;;
    whitelist) manage_ipset "whitelist" "$2" "$3" ;;
    blacklist) manage_ipset "blacklist" "$2" "$3" ;;
    save)      save_persistence ;;
    menu)      run_menu ;;
    *)         show_usage; exit 1 ;;
esac
exit 0
