#!/bin/bash
# antiddos - Advanced Dual-Stack (IPv4 & IPv6) IPTables Anti-DDoS Script

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
IPT4=$(which iptables 2>/dev/null)
IPT6=$(which ip6tables 2>/dev/null)
IPS4=$(which iptables-save 2>/dev/null)
IPS6=$(which ip6tables-save 2>/dev/null)
IPSET=$(which ipset 2>/dev/null)

function show_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "    ___          __  _ ____  ____       ____ "
    echo "   /   |  ____  / /_(_) __ \/ __ \____ / ___|"
    echo "  / /| | / __ \/ __/ / / / / / / / __ \\___ \ "
    echo " / ___ |/ / / / /_/ / /_/ / /_/ / /_/ /___) |"
    echo "/_/  |_/_/ /_/\__/_/_____/_____/\____/|____/ "
    echo -e "${NC}"
    echo -e "${BLUE} High-Performance Dual-Stack Anti-DDoS Firewall Tool${NC}"
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

    for pkg in iptables ip6tables ipset ss sysctl; do
        if ! command -v $pkg >/dev/null 2>&1; then
            echo -e "${RED}${CROSS} Missing dependency: $pkg${NC}"
            missing_pkgs="$missing_pkgs $pkg"
        else
            echo -e "${GREEN}${CHECK} Found: $pkg${NC}"
        fi
    done

    if [[ ! -d "/etc/iptables" ]]; then
        echo -e "${RED}${CROSS} Missing dependency: iptables-persistent / iptables-services${NC}"
        missing_pkgs="$missing_pkgs iptables-persistent"
    else
        echo -e "${GREEN}${CHECK} Found: iptables persistence directory${NC}"
    fi

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
        IPT4=$(which iptables)
        IPT6=$(which ip6tables)
        IPS4=$(which iptables-save)
        IPS6=$(which ip6tables-save)
        IPSET=$(which ipset)
        echo -e "${GREEN}${CHECK} Dependencies resolved!${NC}"
    else
        echo -e "${GREEN}${CHECK} System is fully supported and ready.${NC}"
    fi
    echo ""
}

function tune_kernel() {
    echo -e "${CYAN} - Tuning Kernel (sysctl) for IPv4 & IPv6 DDoS Mitigation...${NC}"
    # IPv4 Tuning
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

    # IPv6 Tuning
    sysctl -w net.ipv6.conf.all.accept_redirects=0 >/dev/null 2>&1
    sysctl -w net.ipv6.conf.all.accept_source_route=0 >/dev/null 2>&1
}

function clear_rules() {
    echo -e "${YELLOW}${INFO} Clearing all IPv4 & IPv6 iptables rules...${NC}"
    for IPT in "$IPT4" "$IPT6"; do
        if [[ -x "$IPT" ]]; then
            $IPT -P INPUT ACCEPT
            $IPT -P FORWARD ACCEPT
            $IPT -P OUTPUT ACCEPT
            $IPT -t nat -F 2>/dev/null
            $IPT -t mangle -F
            $IPT -t raw -F
            $IPT -F
            $IPT -X
        fi
    done
    
    # Destroy ipsets
    $IPSET destroy antiddos_blacklist4 2>/dev/null
    $IPSET destroy antiddos_blacklist6 2>/dev/null
    $IPSET destroy antiddos_whitelist4 2>/dev/null
    $IPSET destroy antiddos_whitelist6 2>/dev/null
    echo -e "${GREEN}${CHECK} Dual-stack rules and sets cleared successfully.${NC}"
}

function start_antiddos() {
    show_banner
    scan_system
    
    echo -e "${YELLOW}${INFO} Applying Dual-Stack (IPv4/IPv6) Anti-DDoS Architecture...${NC}"
    clear_rules >/dev/null 2>&1
    tune_kernel

    # 1. IPSet Setup (IPv4 inet & IPv6 inet6)
    echo -e "${CYAN} - Initializing IPSet (IPv4 + IPv6)...${NC}"
    $IPSET create antiddos_blacklist4 hash:ip family inet 2>/dev/null
    $IPSET create antiddos_blacklist6 hash:ip family inet6 2>/dev/null
    $IPSET create antiddos_whitelist4 hash:ip family inet 2>/dev/null
    $IPSET create antiddos_whitelist6 hash:ip family inet6 2>/dev/null
    
    # Set up whitelist/blacklist hooks
    $IPT4 -t mangle -A PREROUTING -m set --match-set antiddos_whitelist4 src -j ACCEPT
    $IPT6 -t mangle -A PREROUTING -m set --match-set antiddos_whitelist6 src -j ACCEPT
    $IPT4 -t mangle -A PREROUTING -m set --match-set antiddos_blacklist4 src -j DROP
    $IPT6 -t mangle -A PREROUTING -m set --match-set antiddos_blacklist6 src -j DROP

    # 2. Localhost & Established connections
    echo -e "${CYAN} - Permitting Loopback & Established Connections...${NC}"
    for IPT in "$IPT4" "$IPT6"; do
        $IPT -A INPUT -i lo -j ACCEPT
        $IPT -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    done

    # Allow Essential ICMPv6 Neighbor Discovery (CRITICAL for IPv6 routing)
    $IPT6 -A INPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -j ACCEPT
    $IPT6 -A INPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -j ACCEPT
    $IPT6 -A INPUT -p ipv6-icmp --icmpv6-type router-solicitation -j ACCEPT
    $IPT6 -A INPUT -p ipv6-icmp --icmpv6-type router-advertisement -j ACCEPT

    # SSH Protection
    SSH_PORT=$(ss -tlpn | grep sshd | awk '{print $4}' | awk -F':' '{print $NF}' | head -n1 || echo 22)
    $IPT4 -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
    $IPT6 -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT

    # 3. High-Performance Packet Filtering (Mangle PREROUTING)
    echo -e "${CYAN} - Applying Mangle PREROUTING Filters (IPv4 + IPv6)...${NC}"
    for IPT in "$IPT4" "$IPT6"; do
        # Drop Invalid states
        $IPT -t mangle -A PREROUTING -m conntrack --ctstate INVALID -j DROP
        # Block non-SYN new TCP packets
        $IPT -t mangle -A PREROUTING -p tcp ! --syn -m conntrack --ctstate NEW -j DROP
        # Block uncommon MSS values
        $IPT -t mangle -A PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP
        
        # Bogus TCP Flags
        $IPT -t mangle -A PREROUTING -p tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -j DROP
        $IPT -t mangle -A PREROUTING -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
        $IPT -t mangle -A PREROUTING -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
        $IPT -t mangle -A PREROUTING -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
        $IPT -t mangle -A PREROUTING -p tcp --tcp-flags FIN,ACK FIN -j DROP
    done

    # 4. SYNPROXY for Web Traffic (IPv4 + IPv6)
    echo -e "${CYAN} - Enabling SYNPROXY for HTTP/HTTPS (Port 80, 443)...${NC}"
    for IPT in "$IPT4" "$IPT6"; do
        $IPT -t raw -A PREROUTING -p tcp -m tcp --dport 80 --syn -j NOTRACK
        $IPT -t raw -A PREROUTING -p tcp -m tcp --dport 443 --syn -j NOTRACK
        $IPT -A INPUT -p tcp -m tcp --dport 80 -m conntrack --ctstate UNTRACKED,INVALID -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460
        $IPT -A INPUT -p tcp -m tcp --dport 443 -m conntrack --ctstate UNTRACKED,INVALID -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460
    done

    # 5. Rate Limits & Protocol Controls
    echo -e "${CYAN} - Applying UDP/ICMP & Connection Limits...${NC}"
    for IPT in "$IPT4" "$IPT6"; do
        $IPT -A INPUT -p tcp --syn -m connlimit --connlimit-above 50 -j DROP
        $IPT -A INPUT -p udp -m conntrack --ctstate NEW -m limit --limit 20/s --limit-burst 40 -j ACCEPT
        $IPT -A INPUT -p udp -m conntrack --ctstate NEW -j DROP
    done

    # Ping rate limits (ICMPv4 vs ICMPv6)
    $IPT4 -A INPUT -p icmp -m limit --limit 2/s --limit-burst 5 -j ACCEPT
    $IPT4 -A INPUT -p icmp -j DROP
    $IPT6 -A INPUT -p ipv6-icmp -m limit --limit 2/s --limit-burst 5 -j ACCEPT
    $IPT6 -A INPUT -p ipv6-icmp -j DROP

    echo -e "${GREEN}${CHECK}${BOLD} Dual-Stack Anti-DDoS Protection Active!${NC}"
}

function manage_ipset() {
    local list=$1
    local ip=$2
    if [[ -z "$ip" ]]; then
        echo -e "${RED}${CROSS} Error: IP address required.${NC}"
        return
    fi

    # Detect IPv4 vs IPv6
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        local target_set="antiddos_${list}4"
    elif [[ "$ip" =~ : ]]; then
        local target_set="antiddos_${list}6"
    else
        echo -e "${RED}${CROSS} Error: Invalid IPv4 or IPv6 address format.${NC}"
        return
    fi

    $IPSET add "$target_set" "$ip"
    
    if [[ "$list" == "whitelist" ]]; then
        echo -e "${GREEN}${CHECK} Whitelisted IP: $ip${NC}"
    else
        echo -e "${RED}${WARN} Blacklisted IP: $ip${NC}"
    fi
}

function monitor_traffic() {
    show_banner
    echo -e "${BOLD}${FIRE} Real-time Dual-Stack Monitoring (Press Ctrl+C to exit)...${NC}"
    sleep 1
    while true; do
        clear
        show_banner
        echo -e "${BOLD}${BLUE}--- DROPPED IPv4 PACKETS ---${NC}"
        $IPT4 -t mangle -L PREROUTING -n -v | grep -E "DROP|REJECT" | grep -v "0     0"
        
        echo -e "\n${BOLD}${BLUE}--- DROPPED IPv6 PACKETS ---${NC}"
        $IPT6 -t mangle -L PREROUTING -n -v | grep -E "DROP|REJECT" | grep -v "0     0"
        
        echo -e "\n${BOLD}${BLUE}--- CURRENT ACTIVE CONNECTIONS ---${NC}"
        ss -tun state established | awk 'NR>1 {print $4}' | awk -F':' '{print $NF}' | sort | uniq -c | sort -nr | head -n 5
        sleep 2
    done
}

function save_persistence() {
    echo -e "${YELLOW}${INFO} Saving current IPv4/IPv6 rules & IPsets...${NC}"
    if command -v netfilter-persistent >/dev/null; then
        ipset save > /etc/iptables/ipsets
        netfilter-persistent save
        echo -e "${GREEN}${CHECK} Rules saved via netfilter-persistent.${NC}"
    elif [[ -d "/etc/iptables" ]]; then
        $IPS4 > /etc/iptables/rules.v4
        $IPS6 > /etc/iptables/rules.v6
        ipset save > /etc/iptables/ipsets
        echo -e "${GREEN}${CHECK} Rules saved to /etc/iptables/rules.v4 and rules.v6${NC}"
    else
        echo -e "${RED}${CROSS} Error: Persistence framework not found.${NC}"
    fi
}

function status_antiddos() {
    show_banner
    echo -e "${PURPLE}${BOLD}--- DUAL-STACK PROTECTION STATUS ---${NC}"
    
    local v4_active="${RED}${CROSS} INACTIVE${NC}"
    local v6_active="${RED}${CROSS} INACTIVE${NC}"
    
    $IPT4 -t mangle -L PREROUTING | grep -q "INVALID" && v4_active="${GREEN}${CHECK} ACTIVE${NC}"
    $IPT6 -t mangle -L PREROUTING | grep -q "INVALID" && v6_active="${GREEN}${CHECK} ACTIVE${NC}"

    echo -e " IPv4 Engine Status: $v4_active"
    echo -e " IPv6 Engine Status: $v6_active"

    echo -e "\n${BLUE}${BOLD}Blacklisted IPv4 IPs:${NC}"
    $IPSET list antiddos_blacklist4 2>/dev/null | grep -E '^[0-9]' || echo "None"
    echo -e "\n${BLUE}${BOLD}Blacklisted IPv6 IPs:${NC}"
    $IPSET list antiddos_blacklist6 2>/dev/null | grep -E '^[0-9a-fA-F:]' || echo "None"
}

function show_usage() {
    show_banner
    echo -e "${BOLD}Usage Configuration:${NC} Requires Root Privileges"
    echo ""
    echo -e "${BOLD}Command and Description${NC}"
    echo -e "------------------------------------------------------------"
    echo -e " ${CYAN}sudo ./antiddos.sh start${NC}     Apply all Anti-DDoS protection rules (IPv4 & IPv6)"
    echo -e " ${CYAN}sudo ./antiddos.sh stop${NC}      Remove all rules and revert to defaults"
    echo -e " ${CYAN}sudo ./antiddos.sh status${NC}    View current protection and rule status"
    echo -e " ${CYAN}sudo ./antiddos.sh monitor${NC}   Launch real-time monitoring dashboard"
    echo -e " ${CYAN}sudo ./antiddos.sh whitelist${NC} Add an IP (IPv4 or IPv6) to whitelist (${YELLOW}<IP>${NC})"
    echo -e " ${CYAN}sudo ./antiddos.sh blacklist${NC} Block an IP (IPv4 or IPv6) (${YELLOW}<IP>${NC})"
    echo -e " ${CYAN}sudo ./antiddos.sh save${NC}      Make current rules persistent across reboots"
    echo -e " ${CYAN}sudo ./antiddos.sh clear${NC}     Flush all iptables and ip6tables rules"
    echo -e "------------------------------------------------------------"
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
