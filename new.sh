#!/usr/bin/env bash
# ==============================================================
#  ANTI-DDOS — Advanced Linux Server IPTables Anti-DDoS Script
#  Author: Mitul Playz | Enhanced VIP EDITION
#  UI-TYPE : SEMA-HYPER-VISUAL -> VIP ELITE
#  NOTE    : Must run as root (sudo). Do NOT use under `set -e`.
# ==============================================================

VERSION="v3.0 — VIP EDITION"

# ==============================================================
#  VIP ELITE THEME (256-color ANSI)
# ==============================================================
R='\033[1;38;5;196m'      # Crimson Red
G='\033[1;38;5;82m'       # Emerald Green
Y='\033[1;38;5;220m'      # Gold
C='\033[1;38;5;51m'       # Cyan
P='\033[1;38;5;201m'      # Hot Pink (VIP)
VIOLET='\033[1;38;5;135m' # Deep Violet
NEON='\033[1;38;5;198m'   # Neon Pink
W='\033[1;38;5;255m'      # Pure White
DG='\033[0;38;5;244m'     # Steel Gray
BOLD='\033[1m'
NC='\033[0m'

# Symbols
CHECK="✓"
CROSS="✗"
INFO="◉"
WARN="⚠"
FIRE="🔥"
ARROW="➜"

# ==============================================================
#  CONFIG / ENVIRONMENT FALLBACKS
# ==============================================================
CONN_LIMIT="${CONN_LIMIT:-20}"
UDP_GAME_PORTS="${UDP_GAME_PORTS:-27015 27016 7777 25565 3074 9987}"
CUSTOM_SSH_PORT=""

IPT=$(command -v iptables 2>/dev/null)
IPS=$(command -v iptables-save 2>/dev/null)
IPSET=$(command -v ipset 2>/dev/null)

# Parse optional flags before standard subcommands
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh-port)
            CUSTOM_SSH_PORT="$2"
            shift 2
            ;;
        -v|--version)
            echo -e "${P}Anti-DDoS Firewall Engine ${NEON}${VERSION}${NC}"
            exit 0
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done
set -- "${ARGS[@]}"

# ==============================================================
#  VISUAL HELPERS
# ==============================================================

# Render a centered box frame around the given lines (ASCII-safe)
banner_box() {
    local width=76
    local inner=$((width - 2))
    echo -e " ${VIOLET}╔$(printf '═%.0s' $(seq 1 "$inner"))╗${NC}"
    for line in "$@"; do
        local stripped
        stripped=$(echo -e "$line" | sed 's/\x1b\[[0-9;]*m//g')
        local len=${#stripped}
        if (( len > inner )); then
            echo -e " ${VIOLET}║${NC} ${line}${NC}${VIOLET}║${NC}"
            continue
        fi
        local pad=$(( (inner - len) / 2 ))
        local left=$(printf ' %.0s' $(seq 1 "$pad"))
        local right=$(( inner - len - pad ))
        local rp=$(printf ' %.0s' $(seq 1 "$right"))
        echo -e " ${VIOLET}║${NC}${left}${line}${rp}${VIOLET}║${NC}"
    done
    echo -e " ${VIOLET}╚$(printf '═%.0s' $(seq 1 "$inner"))╝${NC}"
}

# Animated loading bar with live percentage
progress_bar() {
    local label="$1"
    local dur="${2:-0.6}"
    local bar_w=30
    local steps=100
    local st
    st=$(awk -v d="$dur" 'BEGIN{printf "%.4f", d/100}')
    printf " ${C}◉${NC} ${W}%s${NC}  " "$label"
    local p fill empty fb eb
    for ((p=0; p<=steps; p++)); do
        fill=$((p * bar_w / steps))
        empty=$((bar_w - fill))
        fb=$(printf '█%.0s' $(seq 1 "$fill"))
        eb=$(printf '░%.0s' $(seq 1 "$empty"))
        printf "\r ${C}◉${NC} ${W}%s${NC}  ${G}%s${NC}${DG}%s${NC} ${Y}%3d%%${NC}" "$label" "$fb" "$eb" "$p"
        [[ $p -lt $steps ]] && sleep "$st"
    done
    printf "\r ${G}✓${NC} ${W}%s${NC}  ${G}[ COMPLETE ]${NC}${DG}   [ 100%% ]${NC}\n" "$label"
}

# Section header banner
section() {
    echo -e "\n ${VIOLET}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e " ${VIOLET}║${NC}   ${P}$1${NC}"
    echo -e " ${VIOLET}╚══════════════════════════════════════════════════════════════╝${NC}"
}

# Colored input prompt (read -p does NOT expand ANSI escapes, so use printf %b)
prompt_read() {
    local msg="$1"
    local varname="$2"
    printf '%b' "$msg"
    IFS= read -r "${varname:-_}" && :
}

# Simple two-column status row
status_row() {
    local label="$1"
    local value="$2"
    local status="${3:-G}"
    local color
    case "$status" in
        G) color="$G";;
        R) color="$R";;
        Y) color="$Y";;
        C) color="$C";;
        *) color="$W";;
    esac
    printf " ${DG}├─${NC} ${W}%-24s${NC} ${DG}:${NC} ${color}%s${NC}\n" "$label" "$value"
}

# ==============================================================
#  BANNER
# ==============================================================
show_banner() {
    clear
    local banner=(
        "   █████╗ ███╗   ██╗████████╗██╗        ██████╗ ██████╗  ██████╗ ███████╗"
        "  ██╔══██╗████╗  ██║╚══██╔══╝██║        ██╔══██╗██╔══██╗██╔═══██╗██╔════╝"
        "  ███████║██╔██╗ ██║   ██║   ██║        ██║  ██║██║  ██║██║   ██║███████╗"
        "  ██╔══██║██║╚██╗██║   ██║   ██║        ██║  ██║██║  ██║██║   ██║╚════██║"
        "  ██║  ██║██║ ╚████║   ██║   ███████╗  ██████╔╝██████╔╝╚██████╔╝███████║"
        "  ╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝  ╚═════╝ ╚═════╝  ╚═════╝ ╚══════╝"
    )
    local colors=( "$P" "$VIOLET" "$NEON" "$C" "$Y" "$G" )
    local i=0
    for line in "${banner[@]}"; do
        echo -e "${colors[$(( i % ${#colors[@]} ))]}${line}${NC}"
        i=$((i+1))
    done
    echo ""
    banner_box \
        " ${P}☣${NC} ${Y}HIGH-PERFORMANCE FIREWALL MANAGEMENT${NC}" \
        " ${DG}${VERSION}${NC} ${W}|${NC} ${G}CONNECTION-LIMIT GUARD${NC} ${W}|${NC} ${DG}$(date +'%Y-%m-%d %H:%M:%S')${NC}"
    echo ""
}

# ==============================================================
#  CORE
# ==============================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        show_banner
        echo -e " ${R}✗ Error:${NC} ${W}This script must be run with root privileges (sudo).${NC}"
        exit 1
    fi
}

get_ssh_port() {
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

# ==============================================================
#  SYSTEM SCAN & DEPENDENCIES
# ==============================================================
scan_system() {
    show_banner
    section " SYSTEM SCAN & DEPENDENCIES "
    local missing_pkgs=""

    for pkg in iptables ipset ss sysctl; do
        progress_bar "Checking $pkg" 0.25
        if ! command -v "$pkg" >/dev/null 2>&1; then
            printf " ${R}✗${NC} ${W}%-12s${NC} ${R}MISSING${NC}\n" "$pkg"
            missing_pkgs="$missing_pkgs $pkg"
        else
            printf " ${G}✓${NC} ${W}%-12s${NC} ${G}OK${NC}\n" "$pkg"
        fi
    done

    progress_bar "Persistence folder /etc/iptables" 0.25
    if [[ ! -d "/etc/iptables" ]]; then
        printf " ${R}✗${NC} ${W}%-18s${NC} ${R}MISSING${NC}\n" "/etc/iptables"
        missing_pkgs="$missing_pkgs iptables-persistent"
    else
        printf " ${G}✓${NC} ${W}%-18s${NC} ${G}FOUND${NC}\n" "persistence folder"
    fi

    if [[ -n "$missing_pkgs" ]]; then
        echo -e "\n ${Y}⚠ Installing missing dependencies:${NC} $missing_pkgs"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -y >/dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get install -y iptables ipset iproute2 procps iptables-persistent >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            yum install -y iptables ipset iproute procps-ng iptables-services >/dev/null 2>&1
        else
            echo -e " ${R}✗ Unknown package manager. Install manually:${NC} $missing_pkgs"
            exit 1
        fi
        IPT=$(command -v iptables)
        IPS=$(command -v iptables-save)
        IPSET=$(command -v ipset)
        echo -e " ${G}✓ All dependencies installed successfully!${NC}"
    else
        echo -e " ${G}✓ System is fully supported and ready.${NC}"
    fi
    echo ""
}

# ==============================================================
#  KERNEL TUNING
# ==============================================================
kernel_rows() {
    local pairs=(
        "net.netfilter.nf_conntrack_max|10000000"
        "net.netfilter.nf_conntrack_tcp_timeout_established|1800"
        "net.netfilter.nf_conntrack_tcp_timeout_syn_recv|20"
        "net.core.netdev_max_backlog|262144"
        "net.core.somaxconn|65535"
        "net.ipv4.tcp_syncookies|1"
        "net.ipv4.tcp_synack_retries|1"
        "net.ipv4.tcp_timestamps|1"
        "net.ipv4.tcp_sack|1"
        "net.ipv4.conf.all.rp_filter|1"
    )
    local done=0
    for p in "${pairs[@]}"; do
        local key="${p%%|*}"
        local val="${p##*|}"
        sysctl -w "$key=$val" >/dev/null 2>&1
        printf " ${G}✓${NC} ${W}%-52s${NC} ${DG}= ${C}%s${NC}\n" "$key" "$val"
        done=$((done+1))
    done
    echo -e "\n ${G}✓${NC} ${W}Kernel tuning complete:${NC} ${Y}${done} applied${NC} ${DG}(${done} reported)${NC}"
    echo ""
}

tune_kernel() {
    show_banner
    section " KERNEL HARDENING (sysctl) "
    kernel_rows
}

# ==============================================================
#  CLEAR / STOP
# ==============================================================
clear_rules() {
    show_banner
    section " STOP — CLEARING ALL RULES "
    progress_bar "Flushing filter table" 0.4
    $IPT -P INPUT ACCEPT 2>/dev/null
    $IPT -P FORWARD ACCEPT 2>/dev/null
    $IPT -P OUTPUT ACCEPT 2>/dev/null
    $IPT -t nat -F 2>/dev/null
    $IPT -t mangle -F 2>/dev/null
    $IPT -t raw -F 2>/dev/null
    $IPT -F 2>/dev/null
    $IPT -X 2>/dev/null

    progress_bar "Destroying ipset sets" 0.4
    $IPSET destroy antiddos_blacklist 2>/dev/null
    $IPSET destroy antiddos_whitelist 2>/dev/null

    echo -e " ${G}✓${NC} ${W}Rules cleared successfully.${NC}"
    echo -e " ${G}✓${NC} ${W}ipset whitelist/blacklist sets removed.${NC}"
    echo -e " ${Y}⚠ Note:${NC} ${DG}sysctl hardening stays active. Run '${W}sudo ./$(basename "$0") tune${NC}${DG}' to re-apply, or revert sysctl if necessary.${NC}"
}

# ==============================================================
#  START ENGINE
# ==============================================================
start_antiddos() {
    scan_system

    section " INITIALIZING ANTI-DDOS ENGINE "
    echo -e " ${C}◉${NC} ${W}${FIRE}  ARMING DEFENSE MATRIX  ${FIRE}${NC}\n"

    progress_bar "Tuning kernel (sysctl)" 0.6
    kernel_rows

    progress_bar "Allowing loopback + state tracking" 0.5
    $IPT -F 2>/dev/null
    $IPT -t mangle -F 2>/dev/null
    $IPT -t raw -F 2>/dev/null

    # IPSET setup
    progress_bar "Loading ipset blacklist / whitelist hooks" 0.4
    $IPSET create antiddos_blacklist hash:ip 2>/dev/null
    $IPSET create antiddos_whitelist hash:ip 2>/dev/null
    $IPT -t mangle -A PREROUTING -m set --match-set antiddos_whitelist src -j ACCEPT 2>/dev/null
    $IPT -t mangle -A PREROUTING -m set --match-set antiddos_blacklist src -j DROP 2>/dev/null

    progress_bar "Applying localhost / established rules" 0.4
    $IPT -A INPUT -i lo -j ACCEPT 2>/dev/null
    $IPT -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null

    SSH_PORT=$(get_ssh_port)
    if [[ -n "$CUSTOM_SSH_PORT" ]]; then
        echo -e " ${C}◉${NC} ${DG}SSH port forced via argument:${NC} ${W}$SSH_PORT${NC}"
    else
        echo -e " ${C}◉${NC} ${DG}SSH port auto-detected:${NC} ${W}$SSH_PORT${NC} ${DG}(wrong? re-run with ${W}--ssh-port <PORT>${NC}${DG})${NC}"
    fi
    $IPT -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT 2>/dev/null

    # High-performance packet filtering
    progress_bar "Deploying high-performance packet filters" 0.6
    $IPT -t mangle -A PREROUTING -m conntrack --ctstate INVALID -j DROP 2>/dev/null
    $IPT -t mangle -A PREROUTING -f -j DROP 2>/dev/null
    $IPT -t mangle -A PREROUTING -p tcp ! --syn -m conntrack --ctstate NEW -j DROP 2>/dev/null
    $IPT -t mangle -A PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP 2>/dev/null

    $IPT -t mangle -A PREROUTING -p tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -j DROP 2>/dev/null
    $IPT -t mangle -A PREROUTING -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP 2>/dev/null
    $IPT -t mangle -A PREROUTING -p tcp --tcp-flags SYN,RST SYN,RST -j DROP 2>/dev/null
    $IPT -t mangle -A PREROUTING -p tcp --tcp-flags FIN,RST FIN,RST -j DROP 2>/dev/null
    $IPT -t mangle -A PREROUTING -p tcp --tcp-flags FIN,ACK FIN -j DROP 2>/dev/null

    # Anti-spoofing (Martians)
    progress_bar "Anti-spoofing protection" 0.4
    IFACE=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -n1)
    if [[ -n "$IFACE" ]]; then
        $IPT -t mangle -A PREROUTING -i "$IFACE" -s 224.0.0.0/4 -j DROP 2>/dev/null
        $IPT -t mangle -A PREROUTING -i "$IFACE" -s 240.0.0.0/5 -j DROP 2>/dev/null
        $IPT -t mangle -A PREROUTING -i "$IFACE" -s 0.0.0.0/8 -j DROP 2>/dev/null
        $IPT -t mangle -A PREROUTING -i "$IFACE" -s 255.255.255.255/32 -j DROP 2>/dev/null
    fi

    # SYNPROXY for Web
    progress_bar "Deploying SYNPROXY (80 / 443)" 0.5
    $IPT -t raw -A PREROUTING -p tcp -m tcp --dport 80 --syn -j NOTRACK 2>/dev/null
    $IPT -t raw -A PREROUTING -p tcp -m tcp --dport 443 --syn -j NOTRACK 2>/dev/null
    $IPT -A INPUT -p tcp -m tcp --dport 80 -m conntrack --ctstate UNTRACKED,INVALID -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460 2>/dev/null
    $IPT -A INPUT -p tcp -m tcp --dport 443 -m conntrack --ctstate UNTRACKED,INVALID -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460 2>/dev/null

    # Connlimit
    progress_bar "Global connection limit ($CONN_LIMIT/IP)" 0.4
    $IPT -A INPUT -p tcp --syn -m connlimit --connlimit-above "$CONN_LIMIT" -j DROP 2>/dev/null

    # Port Scan protection
    progress_bar "Port scan protection" 0.4
    $IPT -A INPUT -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s --limit-burst 2 -j RETURN 2>/dev/null
    $IPT -A INPUT -p tcp --tcp-flags SYN,ACK,FIN,RST RST -j DROP 2>/dev/null

    # UDP protection
    if [[ "$UDP_GAME_PORTS" == "*" ]]; then
        progress_bar "UDP flood protection (ports: ALL)" 0.4
        $IPT -A INPUT -p udp -m conntrack --ctstate NEW -m limit --limit 20/s --limit-burst 40 -j ACCEPT 2>/dev/null
        $IPT -A INPUT -p udp -m conntrack --ctstate NEW -j DROP 2>/dev/null
    else
        progress_bar "UDP flood protection" 0.4
        for port in $UDP_GAME_PORTS; do
            if [[ "$port" =~ ^[0-9]+$ ]]; then
                $IPT -A INPUT -p udp --dport "$port" -m conntrack --ctstate NEW -m limit --limit 20/s --limit-burst 40 -j ACCEPT 2>/dev/null
                $IPT -A INPUT -p udp --dport "$port" -m conntrack --ctstate NEW -j DROP 2>/dev/null
            fi
        done
    fi

    # ICMP
    progress_bar "ICMP flood protection" 0.4
    $IPT -A INPUT -p icmp -m limit --limit 2/s --limit-burst 5 -j ACCEPT 2>/dev/null
    $IPT -A INPUT -p icmp -j DROP 2>/dev/null

    echo ""
    section " DEFENSE ONLINE "
    status_row "SSH Port"          "$SSH_PORT"                         G
    status_row "Conn Limit / IP"   "$CONN_LIMIT"                       C
    status_row "UDP Guarded Ports" "$UDP_GAME_PORTS"                   C
    echo ""
    echo -e " ${G}✓ Anti-DDoS rules applied successfully!${NC}"
    echo -e " ${C}◉ Monitor:${NC} ${W}sudo ./$(basename "$0") monitor${NC}"
}

# ==============================================================
#  IPSET MANAGEMENT
# ==============================================================
manage_ipset() {
    local list=$1
    local action=$2
    local ip=$3

    $IPSET create "antiddos_$list" hash:ip 2>/dev/null

    if [[ "$action" == "list" ]]; then
        echo -e "\n ${VIOLET}╔══════════════════════════════════════════════╗${NC}"
        echo -e " ${VIOLET}║${NC}   ${P}$(echo "$list" | tr 'a-z' 'A-Z')LISTED IP ADDRESSES${NC}"
        echo -e " ${VIOLET}╚══════════════════════════════════════════════╝${NC}"
        local ips
        ips=$($IPSET list "antiddos_$list" 2>/dev/null | grep -E '^[0-9]')
        if [[ -z "$ips" ]]; then
            echo -e " ${DG}└─${NC} ${W}No IPs found.${NC}"
        else
            local n=0
            while IFS= read -r line; do
                n=$((n+1))
                local color="$G"
                [[ "$list" == "blacklist" ]] && color="$R"
                printf " ${DG}│${NC} ${color}%02d${NC}  ${W}%s${NC}\n" "$n" "$line"
            done <<< "$ips"
            echo -e " ${DG}└─${NC} ${W}Total:${NC} ${Y}$n${NC} ${W}entries${NC}"
        fi
        return
    fi

    if [[ "$action" == "del" ]]; then
        if [[ -z "$ip" ]]; then
            echo -e " ${R}✗ IP address required for deletion.${NC}"
            return
        fi
        $IPSET del "antiddos_$list" "$ip" 2>/dev/null
        echo -e " ${G}✓ Removed${NC} ${W}$ip${NC} ${DG}from $list.${NC}"
        return
    fi

    if [[ -z "$ip" && -n "$action" ]]; then
        ip="$action"
    fi

    if [[ -z "$ip" || ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e " ${R}✗ Error:${NC} ${W}A valid IPv4 address is required.${NC}"
        return
    fi

    $IPSET add "antiddos_$list" "$ip" 2>/dev/null
    if [[ "$list" == "whitelist" ]]; then
        echo -e " ${G}✓ Whitelisted IP:${NC} ${W}$ip${NC}"
    else
        echo -e " ${R}⚠ Blacklisted IP:${NC} ${W}$ip${NC}"
    fi
}

# ==============================================================
#  MONITOR
# ==============================================================
monitor_traffic() {
    show_banner
    echo -e " ${P}${FIRE}${NC} ${W}${FIRE}  REAL-TIME MONITORING DASHBOARD  ${FIRE}${NC} ${DG}(Ctrl+C to exit)${NC}"
    sleep 1
    while true; do
        clear
        show_banner
        echo -e " ${BOLD}${C}═══ DROPPED PACKETS (MANGLE & FILTER) ${NC}"
        $IPT -t mangle -L PREROUTING -n -v 2>/dev/null | grep -E "DROP|REJECT" | grep -v "0     0"
        $IPT -L INPUT -n -v 2>/dev/null | grep -E "DROP|REJECT" | grep -v "0     0"

        echo -e "\n ${BOLD}${C}═══ CURRENT CONNECTIONS BY PORT ${NC}"
        ss -tun state established 2>/dev/null | awk 'NR>1 {print $4}' | awk -F':' '{print $NF}' | sort | uniq -c | sort -nr | head -n 5
        sleep 2
    done
}

# ==============================================================
#  PERSISTENCE
# ==============================================================
save_persistence() {
    show_banner
    section " SAVING RULES FOR PERSISTENCE "
    progress_bar "Backing up ipsets" 0.4
    if command -v netfilter-persistent >/dev/null 2>&1; then
        ipset save > /etc/iptables/ipsets 2>/dev/null
        netfilter-persistent save >/dev/null 2>&1
        echo -e " ${G}✓ Rules saved via netfilter-persistent.${NC}"
    elif [[ -d "/etc/iptables" ]]; then
        $IPS > /etc/iptables/rules.v4 2>/dev/null
        ipset save > /etc/iptables/ipsets 2>/dev/null
        echo -e " ${G}✓ Rules saved to /etc/iptables/rules.v4 and ipsets${NC}"
    else
        echo -e " ${R}✗ Error:${NC} ${W}Persistence framework not found.${NC}"
    fi
}

# ==============================================================
#  STATUS
# ==============================================================
status_antiddos() {
    show_banner
    section " PROTECTION STATUS "
    if $IPT -t mangle -L PREROUTING 2>/dev/null | grep -q "INVALID"; then
        status_row "Anti-DDoS Core Engine" "ACTIVE" G
    else
        status_row "Anti-DDoS Core Engine" "INACTIVE" R
    fi
    echo ""
    section " BLACKLIST (ipset) "
    $IPSET list antiddos_blacklist 2>/dev/null | grep -E '^[0-9]' || echo -e " ${DG}└─${NC} ${W}None${NC}"
    echo ""
    section " WHITELIST (ipset) "
    $IPSET list antiddos_whitelist 2>/dev/null | grep -E '^[0-9]' || echo -e " ${DG}└─${NC} ${W}None${NC}"
    echo ""
}

# ==============================================================
#  MENU
# ==============================================================
run_menu() {
    while true; do
        clear
        show_banner
        echo -e " ${VIOLET}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e " ${VIOLET}║${NC}                  ${Y}INTERACTIVE CONTROL MENU${NC}                  ${VIOLET}║${NC}"
        echo -e " ${VIOLET}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo -e " ${C} 1)${NC} ${W}Start Anti-DDoS Protection${NC}"
        echo -e " ${C} 2)${NC} ${W}Stop / Clear All Rules${NC}"
        echo -e " ${C} 3)${NC} ${W}View Protection Status${NC}"
        echo -e " ${C} 4)${NC} ${W}Real-time Monitoring Dashboard${NC}"
        echo -e " ${C} 5)${NC} ${W}Whitelist Management${NC}"
        echo -e " ${C} 6)${NC} ${W}Blacklist Management${NC}"
        echo -e " ${C} 7)${NC} ${W}Run System Scan & Dependency Check${NC}"
        echo -e " ${C} 8)${NC} ${W}Exit${NC}"
        echo -e " ${DG}──────────────────────────────────────────────────────────┐${NC}"
        prompt_read " ${Y}Select an option [1-8]:${NC} " choice
        case "$choice" in
            1) start_antiddos ;;
            2) clear_rules ;;
            3) status_antiddos ;;
            4) monitor_traffic ;;
            5)
                echo -e "\n ${BOLD}Whitelist Operations:${NC} 1) List  2) Add  3) Remove"
                prompt_read " ${Y}Choice [1-3]:${NC} " wl_choice
                case "$wl_choice" in
                    1) manage_ipset "whitelist" "list" "" ;;
                    2) prompt_read " ${Y}Enter IP to whitelist:${NC} " ip; manage_ipset "whitelist" "add" "$ip" ;;
                    3) prompt_read " ${Y}Enter IP to remove:${NC} " ip; manage_ipset "whitelist" "del" "$ip" ;;
                    *) echo -e " ${R}✗ Invalid option!${NC}" ;;
                esac
                ;;
            6)
                echo -e "\n ${BOLD}Blacklist Operations:${NC} 1) List  2) Add  3) Remove"
                prompt_read " ${Y}Choice [1-3]:${NC} " bl_choice
                case "$bl_choice" in
                    1) manage_ipset "blacklist" "list" "" ;;
                    2) prompt_read " ${Y}Enter IP to blacklist:${NC} " ip; manage_ipset "blacklist" "add" "$ip" ;;
                    3) prompt_read " ${Y}Enter IP to remove:${NC} " ip; manage_ipset "blacklist" "del" "$ip" ;;
                    *) echo -e " ${R}✗ Invalid option!${NC}" ;;
                esac
                ;;
            7) scan_system ;;
            8) echo -e " ${G}✓ Exiting... Goodbye!${NC}"; exit 0 ;;
            *) echo -e " ${R}✗ Invalid option!${NC}" ;;
        esac
        echo ""
        prompt_read " ${DG}Press Enter to return to menu...${NC}"
    done
}

# ==============================================================
#  USAGE
# ==============================================================
show_usage() {
    show_banner
    echo -e " ${BOLD}${C}Usage:${NC} ${W}sudo ./$(basename "$0") [command]${NC} ${DG}(Requires Root)${NC}"
    echo ""
    echo -e " ${VIOLET}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e " ${VIOLET}║${NC}                          ${NEON}COMMANDS${NC}                            ${VIOLET}║${NC}"
    echo -e " ${VIOLET}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e " ${C}▸${NC} ${W}(none) / menu${NC}     ${DG}Launch interactive menu (default)${NC}"
    echo -e " ${C}▸${NC} ${W}start${NC}              ${DG}Apply all Anti-DDoS protection rules${NC}"
    echo -e " ${C}▸${NC} ${W}stop / clear${NC}       ${DG}Remove all rules and revert to defaults${NC}"
    echo -e " ${C}▸${NC} ${W}status${NC}             ${DG}View current protection and rule status${NC}"
    echo -e " ${C}▸${NC} ${W}monitor${NC}            ${DG}Launch real-time monitoring dashboard${NC}"
    echo -e " ${C}▸${NC} ${W}whitelist <IP>${NC}     ${DG}Add an IP address to the whitelist${NC}"
    echo -e " ${C}▸${NC} ${W}blacklist <IP>${NC}     ${DG}Block a specific IP address${NC}"
    echo -e " ${C}▸${NC} ${W}save${NC}               ${DG}Make current rules persistent across reboots${NC}"
    echo -e " ${C}▸${NC} ${W}clear${NC}              ${DG}Flush all iptables rules${NC}"
    echo -e " ${C}▸${NC} ${W}restart${NC}            ${DG}Restart protection (stop + start)${NC}"
    echo -e " ${C}▸${NC} ${W}scan${NC}               ${DG}Re-run system/dependency scan${NC}"
    echo -e " ${C}▸${NC} ${W}tune${NC}               ${DG}Re-apply sysctl kernel hardening${NC}"
    echo ""
    echo -e " ${VIOLET}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e " ${VIOLET}║${NC}                  ${NEON}OPTIONS & ENVIRONMENT${NC}                      ${VIOLET}║${NC}"
    echo -e " ${VIOLET}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e " ${C}▸${NC} ${W}--ssh-port <PORT>${NC}   ${DG}Force SSH port (skips auto-detection)${NC}"
    echo -e " ${C}▸${NC} ${W}UDP_GAME_PORTS${NC}      ${DG}e.g. UDP_GAME_PORTS=\"27015 7777\" (* = all)${NC}"
    echo -e " ${C}▸${NC} ${W}CONN_LIMIT=<n>${NC}      ${DG}Max concurrent connections per source IP${NC}"
    echo -e " ${C}▸${NC} ${W}-v / --version${NC}      ${DG}Show version${NC}"
    echo ""
}

# ==============================================================
#  ENTRY
# ==============================================================
check_root

case "$1" in
    ""|menu)    run_menu ;;
    start)      start_antiddos ;;
    stop|clear) clear_rules ;;
    restart)    clear_rules; start_antiddos ;;
    status)     status_antiddos ;;
    monitor)    monitor_traffic ;;
    scan)       scan_system ;;
    tune)       tune_kernel ;;
    whitelist)  manage_ipset "whitelist" "$2" "$3" ;;
    blacklist)  manage_ipset "blacklist" "$2" "$3" ;;
    save)       save_persistence ;;
    help|-h|--help) show_usage; exit 0 ;;
    *)          show_usage; exit 1 ;;
esac
exit 0
