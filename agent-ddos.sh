#!/bin/bash

#===============================================================================
#  antiddos - Linux Server IPTables Anti-DDoS Script
#
#  Developer  : Mitul Playz
#  Version    : 3.0.0
#
#  Description: Sets up iptables + ipset rules to protect against common DDoS
#               attacks. Features first-run system scanning with automatic
#               dependency installation, SSH port auto-detection, connection
#               state tracking, O(1) ipset whitelist/blacklist, sysctl kernel
#               tuning and a built-in usage guide.
#
#  Quick start:  sudo ./antiddos.sh guide
#===============================================================================

VERSION="3.0.0"
DEV="Mitul Playz"

#------------------------------------------------------------------------------
# Configuration (values can be overridden via environment variables, e.g.:
#   sudo CONN_LIMIT=40 UDP_GAME_PORTS="27015 7777" ./antiddos.sh start
#------------------------------------------------------------------------------
CONN_LIMIT="${CONN_LIMIT:-20}"                    # max concurrent TCP connections per source IP
UDP_GAME_PORTS="${UDP_GAME_PORTS:-27015 27016 7777 25565 3074 9987}"  # UDP ports guarded against flood ("*" = every UDP port)
SYN_RATE="${SYN_RATE:-1/s}";    SYN_BURST="${SYN_BURST:-3}"
UDP_RATE="${UDP_RATE:-10/s}";   UDP_BURST="${UDP_BURST:-20}"
ICMP_RATE="${ICMP_RATE:-1/s}";  ICMP_BURST="${ICMP_BURST:-4}"
SCAN_RATE="${SCAN_RATE:-1/s}";  SCAN_BURST="${SCAN_BURST:-2}"

SSH_PORT="${SSH_PORT:-}"                          # empty = auto-detect (or force with --ssh-port)
WHITELIST_SET="antiddos_whitelist"                # hash:net ipset -> O(1) lookups
BLACKLIST_SET="antiddos_blacklist"
SYSCTL_CONF="/etc/sysctl.d/99-antiddos.conf"
SCAN_FLAG="/var/lib/antiddos/scan.done"           # first-run scan marker

#------------------------------------------------------------------------------
# Colors
#------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Symbols
CHECK="✅"
CROSS="❌"
INFO="ℹ️"
WARN="⚠️"
FIRE="🔥"
SCANY="🔍"
GEAR="⚙️"

# Paths
IPT=$(command -v iptables 2>/dev/null || echo "iptables")
IPS=$(command -v iptables-save 2>/dev/null || echo "iptables-save")

function command_exists() { command -v "$1" >/dev/null 2>&1; }

function die() {
    echo -e "${RED}${CROSS} $1${NC}"
    exit "${2:-1}"
}

#------------------------------------------------------------------------------
# Validate an IPv4 address or CIDR block (e.g. 1.2.3.4 or 10.0.0.0/24)
#------------------------------------------------------------------------------
function is_valid_target() {
    local t="$1" ip o parts
    local re='^([0-9]{1,3}\.){3}[0-9]{1,3}(/([0-9]|[12][0-9]|3[0-2]))?$'
    [[ "$t" =~ $re ]] || return 1
    ip="${t%%/*}"
    IFS='.' read -ra parts <<< "$ip"
    for o in "${parts[@]}"; do
        (( 10#$o <= 255 )) || return 1
    done
    return 0
}

function show_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "    ___         __  _     ____  ____       "
    echo "   /   |  ____ / /_(_)   / __ \/ __ \____  "
    echo "  / /| | / __ \ __/ /   / / / / / / / __ \ "
    echo " / ___ |/ / / / /_/ /   / /_/ / /_/ / /_/ /"
    echo "/_/  |_/_/ /_/\__/_/___/_____/_____/\____/ "
    echo "                  /___/                    "
    echo -e "${NC}"
    echo -e "${BLUE}    Linux Server Anti-DDoS Firewall Management Tool${NC}"
    echo -e "${BLUE}    Version: ${VERSION} | Developer: ${DEV}${NC}"
    echo ""
}

#------------------------------------------------------------------------------
# Built-in usage guide (command #7)
#------------------------------------------------------------------------------
function show_guide() {
    echo -e "${BOLD}  Run with root privileges:${NC}   ${CYAN}sudo ./antiddos.sh <command>${NC}"
    echo ""
    echo -e "${BLUE}${BOLD}  COMMAND                                          DESCRIPTION${NC}"
    printf "  ${CYAN}%-48s${NC} %s\n" "sudo ./antiddos.sh start"        "Apply all Anti-DDoS protection rules"
    printf "  ${CYAN}%-48s${NC} %s\n" "sudo ./antiddos.sh stop"         "Remove all rules and revert to defaults"
    printf "  ${CYAN}%-48s${NC} %s\n" "sudo ./antiddos.sh status"       "View current protection and rule status"
    printf "  ${CYAN}%-48s${NC} %s\n" "sudo ./antiddos.sh monitor"      "Launch real-time monitoring dashboard"
    printf "  ${CYAN}%-48s${NC} %s\n" "sudo ./antiddos.sh whitelist <IP>"  "Add an IP address to the whitelist"
    printf "  ${CYAN}%-48s${NC} %s\n" "sudo ./antiddos.sh blacklist <IP>"  "Block a specific IP address"
    printf "  ${CYAN}%-48s${NC} %s\n" "sudo ./antiddos.sh save"         "Make current rules persistent across reboots"
    printf "  ${CYAN}%-48s${NC} %s\n" "sudo ./antiddos.sh clear"        "Flush all iptables rules"
    echo ""
    echo -e "${BLUE}${BOLD}  EXTRA COMMANDS${NC}"
    printf "  ${CYAN}%-48s${NC} %s\n" "sudo ./antiddos.sh restart"      "Restart protection (stop + start)"
    printf "  ${CYAN}%-48s${NC} %s\n" "sudo ./antiddos.sh scan"         "Re-run system/dependency scan"
    printf "  ${CYAN}%-48s${NC} %s\n" "sudo ./antiddos.sh tune"         "Re-apply sysctl kernel hardening"
    printf "  ${CYAN}%-48s${NC} %s\n" "sudo ./antiddos.sh whitelist list"      "Show whitelisted IPs"
    printf "  ${CYAN}%-48s${NC} %s\n" "sudo ./antiddos.sh whitelist del <IP>"  "Remove an IP from the whitelist"
    printf "  ${CYAN}%-48s${NC} %s\n" "sudo ./antiddos.sh blacklist list"      "Show blacklisted IPs"
    printf "  ${CYAN}%-48s${NC} %s\n" "sudo ./antiddos.sh blacklist del <IP>"  "Remove an IP from the blacklist"
    echo ""
    echo -e "${BLUE}${BOLD}  OPTIONS & ENVIRONMENT${NC}"
    printf "  ${CYAN}%-48s${NC} %s\n" "--ssh-port <PORT>"              "Force SSH port (skips auto-detection)"
    printf "  ${CYAN}%-48s${NC} %s\n" "UDP_GAME_PORTS=\"27015 7777\""   "UDP ports guarded against flood (* = all)"
    printf "  ${CYAN}%-48s${NC} %s\n" "CONN_LIMIT=<n>"                 "Max concurrent connections per source IP"
    echo ""
}

#------------------------------------------------------------------------------
# System scan / dependency check (command #8 - runs automatically on 1st run)
#------------------------------------------------------------------------------
function pkg_detect() {
    if   command_exists apt-get; then PKG_MGR="apt"
    elif command_exists dnf;     then PKG_MGR="dnf"
    elif command_exists yum;     then PKG_MGR="yum"
    elif command_exists pacman;  then PKG_MGR="pacman"
    elif command_exists zypper;  then PKG_MGR="zypper"
    elif command_exists apk;     then PKG_MGR="apk"
    else PKG_MGR=""
    fi
}

function pkg_install() {
    local pkg="$1"
    case "$PKG_MGR" in
        apt)    DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >/dev/null 2>&1 ;;
        dnf)    dnf install -y "$pkg" >/dev/null 2>&1 ;;
        yum)    yum install -y "$pkg" >/dev/null 2>&1 ;;
        pacman) pacman -S --noconfirm "$pkg" >/dev/null 2>&1 ;;
        zypper) zypper --non-interactive install "$pkg" >/dev/null 2>&1 ;;
        apk)    apk add "$pkg" >/dev/null 2>&1 ;;
        *)      return 1 ;;
    esac
}

function check_dep() {
    # $1 = binary, $2 = space separated package candidates, $3 = description
    local bin="$1" pkgs="$2" desc="$3" pkg
    if command_exists "$bin"; then
        echo -e "  ${GREEN}${CHECK} ${BOLD}$bin${NC}${GREEN} — already supported (${desc})${NC}"
        return 0
    fi
    echo -e "  ${YELLOW}${WARN} ${BOLD}$bin${NC}${YELLOW} not found (${desc}) — trying automatic install...${NC}"
    if [[ -z "$PKG_MGR" ]]; then
        echo -e "  ${RED}${CROSS} No supported package manager found. Install manually: ${pkgs}${NC}"
        return 1
    fi
    for pkg in $pkgs; do
        if pkg_install "$pkg" && command_exists "$bin"; then
            echo -e "  ${GREEN}${CHECK} ${BOLD}$bin${NC}${GREEN} installed automatically ($pkg).${NC}"
            return 0
        fi
    done
    echo -e "  ${RED}${CROSS} Could not install ${BOLD}$bin${NC}${RED} automatically. Install manually: ${pkgs}${NC}"
    return 1
}

function scan_system() {
    local force="$1" os_pretty="" need_install=0 failed=0 b
    show_banner
    echo -e "${PURPLE}${BOLD}--- SYSTEM SCAN ${SCANY} ${force:+(forced)}---${NC}"

    if [[ -r /etc/os-release ]]; then
        os_pretty=$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-}")
    fi
    pkg_detect
    echo -e "  ${BLUE}OS detected      : ${os_pretty:-unknown}${NC}"
    echo -e "  ${BLUE}Package manager  : ${PKG_MGR:-none found}${NC}"
    echo ""

    # refresh apt index only if something is actually missing
    for b in iptables ipset ss sysctl iptables-save; do
        command_exists "$b" || need_install=1
    done
    if (( need_install )) && [[ "$PKG_MGR" == "apt" ]] && command_exists timeout; then
        echo -e "  ${YELLOW}${INFO} Updating package index (apt-get update)...${NC}"
        timeout 120 apt-get update -qq >/dev/null 2>&1
    fi

    echo -e "${BLUE}${BOLD}  Dependencies:${NC}"
    check_dep iptables      "iptables"          "netfilter firewall engine" || failed=1
    check_dep iptables-save "iptables"          "rule persistence (save/restore)" || failed=1
    check_dep ipset         "ipset"             "O(1) hash-based IP sets for whitelist/blacklist" || failed=1
    check_dep ss            "iproute2 iproute"  "socket inspection + SSH port auto-detection" || failed=1
    check_dep sysctl        "procps procps-ng"  "kernel (sysctl) tuning" || failed=1
    check_dep modprobe      "kmod"              "kernel module loader (conntrack)" || failed=1

    echo ""
    echo -e "${BLUE}${BOLD}  Kernel / persistence support:${NC}"

    # conntrack state tracking support
    command_exists modprobe && modprobe nf_conntrack 2>/dev/null
    if [[ -e /proc/net/nf_conntrack || -e /proc/sys/net/netfilter/nf_conntrack_max ]]; then
        echo -e "  ${GREEN}${CHECK} conntrack — already supported (connection state tracking)${NC}"
    else
        echo -e "  ${YELLOW}${WARN} conntrack support not detected — state rules may fail (usually safe to ignore)${NC}"
    fi

    # persistence helpers
    if [[ -d /etc/iptables ]] || command_exists netfilter-persistent; then
        echo -e "  ${GREEN}${CHECK} iptables-persistent — already supported (boot-time rule restore)${NC}"
    else
        echo -e "  ${YELLOW}${INFO} iptables-persistent not installed (optional — only needed for 'save')${NC}"
        echo -e "  ${YELLOW}    Debian/Ubuntu: apt-get install iptables-persistent ipset-persistent${NC}"
        echo -e "  ${YELLOW}    RHEL/Fedora  : dnf install iptables-services${NC}"
    fi

    echo ""
    if (( failed )); then
        echo -e "  ${RED}${CROSS} Scan finished: some dependencies are MISSING. Fix them before running 'start'.${NC}"
    else
        echo -e "  ${GREEN}${CHECK} Scan finished: system is READY — all required tools are supported.${NC}"
    fi

    mkdir -p "$(dirname "$SCAN_FLAG")" 2>/dev/null
    touch "$SCAN_FLAG" 2>/dev/null
    echo ""
}

#------------------------------------------------------------------------------
# SSH port detection (command #6)
#------------------------------------------------------------------------------
function detect_ssh_port() {
    # explicit --ssh-port always wins
    if [[ -n "$SSH_PORT" ]]; then
        echo "$SSH_PORT"
        return
    fi
    local p=""
    if command_exists ss; then
        p=$(ss -tlpn 2>/dev/null | awk '/sshd/ {n=split($4,a,":"); print a[n]; exit}')
    fi
    if [[ -z "$p" ]] && command_exists netstat; then
        p=$(netstat -tlpn 2>/dev/null | awk '/sshd/ {n=split($4,a,":"); print a[n]; exit}')
    fi
    if [[ -z "$p" && -r /etc/ssh/sshd_config ]]; then
        p=$(awk 'tolower($1)=="port" {print $2; exit}' /etc/ssh/sshd_config)
    fi
    echo "${p:-22}"
}

#------------------------------------------------------------------------------
# sysctl kernel tuning (command #5)
#------------------------------------------------------------------------------
TUNE_QUIET=0
function tune_sysctl() {
    local -a settings=(
        "net.ipv4.tcp_syncookies=1"
        "net.ipv4.conf.all.accept_source_route=0"
        "net.ipv4.conf.default.accept_source_route=0"
        "net.ipv4.conf.all.accept_redirects=0"
        "net.ipv4.conf.default.accept_redirects=0"
        "net.ipv4.conf.all.send_redirects=0"
        "net.ipv4.conf.default.send_redirects=0"
        "net.ipv4.conf.all.rp_filter=1"
        "net.ipv4.conf.default.rp_filter=1"
        "net.ipv4.icmp_echo_ignore_broadcasts=1"
        "net.ipv4.icmp_ignore_bogus_error_responses=1"
        "net.ipv4.conf.all.log_martians=1"
        "net.ipv4.tcp_max_syn_backlog=4096"
        "net.core.netdev_max_backlog=16384"
        "net.ipv4.tcp_fin_timeout=15"
        "net.ipv4.tcp_keepalive_time=300"
        "net.ipv4.tcp_rfc1337=1"
    )
    local s key val applied=0 skipped=0

    (( TUNE_QUIET )) || echo -e "${PURPLE}${BOLD}--- KERNEL (sysctl) TUNING ${GEAR} ---${NC}"

    for s in "${settings[@]}"; do
        key="${s%%=*}"; val="${s##*=}"
        if sysctl -w "$key=$val" >/dev/null 2>&1; then
            (( TUNE_QUIET )) || echo -e "  ${GREEN}${CHECK} $key = $val${NC}"
            applied=$((applied + 1))
        else
            (( TUNE_QUIET )) || echo -e "  ${YELLOW}${WARN} $key = $val (skipped — not permitted here)${NC}"
            skipped=$((skipped + 1))
        fi
    done

    # persist so hardening survives reboots
    if [[ -d /etc/sysctl.d && -w /etc/sysctl.d ]]; then
        {
            echo "# antiddos v${VERSION} by ${DEV} — generated by tune_sysctl"
            printf '%s\n' "${settings[@]}"
        } > "$SYSCTL_CONF"
        (( TUNE_QUIET )) || echo -e "  ${GREEN}${CHECK} Settings persisted to ${SYSCTL_CONF}${NC}"
    else
        (( TUNE_QUIET )) || echo -e "  ${YELLOW}${WARN} Could not persist to ${SYSCTL_CONF} (directory not writable)${NC}"
    fi

    if (( TUNE_QUIET )); then
        echo -e "${CYAN}   - Kernel tuning: ${applied} applied, ${skipped} skipped${NC}"
    else
        echo -e "${GREEN}${CHECK} sysctl tuning complete (${applied} applied, ${skipped} skipped).${NC}"
    fi
}

#------------------------------------------------------------------------------
# ipset management (command #4)
#------------------------------------------------------------------------------
function ensure_ipsets() {
    command_exists ipset || return 1
    ipset create "$WHITELIST_SET" hash:net -exist 2>/dev/null
    ipset create "$BLACKLIST_SET" hash:net -exist 2>/dev/null
    return 0
}

# Insert the set-matching rules into INPUT if they are not there yet
# (used when whitelist/blacklist is run while protection was never started)
function ensure_ipset_hooks() {
    ensure_ipsets || return 1
    if ! $IPT -C INPUT -m set --match-set "$WHITELIST_SET" src -j ACCEPT 2>/dev/null; then
        $IPT -I INPUT 1 -m set --match-set "$WHITELIST_SET" src -j ACCEPT
    fi
    if ! $IPT -C INPUT -m set --match-set "$BLACKLIST_SET" src -j DROP 2>/dev/null; then
        # keep whitelist priority: insert directly AFTER the whitelist rule
        local wl_line
        wl_line=$($IPT -nL INPUT --line-numbers 2>/dev/null | awk '/antiddos_whitelist/ {print $1; exit}')
        if [[ -n "$wl_line" ]]; then
            $IPT -I INPUT $((wl_line + 1)) -m set --match-set "$BLACKLIST_SET" src -j DROP
        else
            $IPT -I INPUT 2 -m set --match-set "$BLACKLIST_SET" src -j DROP
        fi
    fi
}

function show_set() {
    local setname="$1"
    if ! command_exists ipset; then
        echo -e "${RED}${CROSS} ipset is not installed.${NC}"
        return 1
    fi
    local members
    members=$(ipset list "$setname" 2>/dev/null | sed -n '/^Members/,$p' | tail -n +2 | sed '/^$/d')
    if [[ -z "$members" ]]; then
        echo -e "${YELLOW}${INFO} Set '$setname' is empty.${NC}"
    else
        echo -e "${BLUE}${BOLD} Members of '$setname':${NC}"
        echo "$members" | sed 's/^/   /'
    fi
}

#------------------------------------------------------------------------------
# Core rule management
#------------------------------------------------------------------------------
function clear_rules() {
    echo -e "${YELLOW}${INFO} Clearing all iptables rules...${NC}"
    $IPT -P INPUT ACCEPT
    $IPT -P FORWARD ACCEPT
    $IPT -P OUTPUT ACCEPT
    $IPT -t nat -F 2>/dev/null
    $IPT -t mangle -F 2>/dev/null
    $IPT -F
    $IPT -X
    echo -e "${GREEN}${CHECK} Rules cleared successfully.${NC}"
}

function stop_antiddos() {
    clear_rules
    if command_exists ipset; then
        ipset destroy "$WHITELIST_SET" 2>/dev/null
        ipset destroy "$BLACKLIST_SET" 2>/dev/null
        echo -e "${GREEN}${CHECK} ipset whitelist/blacklist sets removed.${NC}"
    fi
    echo -e "${YELLOW}${INFO} Note: sysctl hardening stays active. Run 'sudo $0 tune' to re-apply, or delete ${SYSCTL_CONF} and reboot to fully revert.${NC}"
}

function status_antiddos() {
    show_banner
    echo -e "${PURPLE}${BOLD}--- PROTECTION STATUS ---${NC}"

    if $IPT -nL SYN_FLOOD >/dev/null 2>&1; then
        echo -e "  ${GREEN}${CHECK} Anti-DDoS rules are ${BOLD}ACTIVE${NC}"
    else
        echo -e "  ${RED}${CROSS} Anti-DDoS rules are ${BOLD}INACTIVE${NC}"
        echo ""
        echo -e "  ${YELLOW}${INFO} Tip: run 'sudo $0 start' to activate protection.${NC}"
        return 0
    fi

    echo ""
    echo -e "${BLUE}${BOLD}  Chains:${NC}"
    local c
    for c in SYN_FLOOD UDP_FLOOD ICMP_FLOOD PORT_SCAN; do
        if $IPT -nL "$c" >/dev/null 2>&1; then
            echo -e "    ${GREEN}${CHECK} $c${NC}"
        else
            echo -e "    ${YELLOW}${WARN} $c (missing)${NC}"
        fi
    done

    echo ""
    echo -e "${BLUE}${BOLD}  Configuration:${NC}"
    echo -e "    SSH port (auto-detected) : $(detect_ssh_port)"
    echo -e "    Conn. limit per IP       : ${CONN_LIMIT}"
    echo -e "    UDP guarded ports        : ${UDP_GAME_PORTS:-none}"

    if command_exists ipset; then
        local wl bl
        wl=$(ipset list "$WHITELIST_SET" 2>/dev/null | sed -n '/^Members/,$p' | tail -n +2 | grep -c . || true)
        bl=$(ipset list "$BLACKLIST_SET" 2>/dev/null | sed -n '/^Members/,$p' | tail -n +2 | grep -c . || true)
        echo -e "    Whitelist entries        : ${wl:-0}"
        echo -e "    Blacklist entries        : ${bl:-0}"
    else
        echo -e "    ${YELLOW}${WARN} ipset not installed — whitelist/blacklist running in fallback mode${NC}"
    fi

    echo ""
    echo -e "${BLUE}${BOLD}  Kernel (sysctl) highlights:${NC}"
    echo -e "    tcp_syncookies           : $(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo '?')"
    echo -e "    tcp_max_syn_backlog      : $(sysctl -n net.ipv4.tcp_max_syn_backlog 2>/dev/null || echo '?')"
    echo -e "    rp_filter (all)          : $(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo '?')"

    echo ""
    echo -e "${BLUE}${BOLD}  Active Rule Sets:${NC}"
    $IPT -nL --line-numbers 2>/dev/null | grep -E "SYN_FLOOD|UDP_FLOOD|ICMP_FLOOD|PORT_SCAN|connlimit|antiddos_" \
        || echo -e "    ${YELLOW}no matching rules found${NC}"
}

function start_antiddos() {
    show_banner
    echo -e "${YELLOW}${INFO} Applying Anti-DDoS rules...${NC}"

    # make sure the tools exist (first-run scan should have installed them)
    if ! command_exists iptables; then
        scan_system
        command_exists iptables || die "iptables is still missing — install it manually, then retry."
    fi

    # Flush existing rules to avoid duplicates if restarting
    $IPT -F
    $IPT -X

    local ssh_port
    ssh_port=$(detect_ssh_port)

    # 0. Kernel-level hardening
    echo -e "${CYAN}   - Tuning kernel (sysctl) settings...${NC}"
    TUNE_QUIET=1
    tune_sysctl
    TUNE_QUIET=0

    # 1. Loopback permission — must be first (command #1)
    echo -e "${CYAN}   - Allowing loopback (127.0.0.1) traffic...${NC}"
    $IPT -A INPUT  -i lo -j ACCEPT
    $IPT -A OUTPUT -o lo -j ACCEPT

    # 2. State tracking — ESTABLISHED/RELATED flows bypass every flood check (command #2)
    echo -e "${CYAN}   - Enabling state tracking (ESTABLISHED,RELATED pass through)...${NC}"
    $IPT -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # 3. ipset whitelist/blacklist — O(1) hash lookups (command #4)
    if ensure_ipsets; then
        echo -e "${CYAN}   - Hooking ipset whitelist/blacklist (${WHITELIST_SET} / ${BLACKLIST_SET})...${NC}"
        $IPT -A INPUT -m set --match-set "$WHITELIST_SET" src -j ACCEPT
        $IPT -A INPUT -m set --match-set "$BLACKLIST_SET" src -j DROP
    else
        echo -e "${YELLOW}   ${WARN} ipset unavailable — skipping O(1) whitelist/blacklist hooks${NC}"
    fi

    # 4. Drop invalid packets
    echo -e "${CYAN}   - Setting up Invalid packet filtering...${NC}"
    $IPT -A INPUT -m state --state INVALID -j DROP

    # 5. Drop packets with problematic TCP flags
    echo -e "${CYAN}   - Setting up TCP flag filtering...${NC}"
    $IPT -A INPUT -p tcp --tcp-flags ALL ACK,RST,SYN,FIN -j DROP
    $IPT -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
    $IPT -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
    $IPT -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
    $IPT -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
    $IPT -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
    $IPT -A INPUT -p tcp --tcp-flags ALL SYN,FIN,PSH,URG -j DROP
    $IPT -A INPUT -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP

    # 6. Drop fragmented packets
    echo -e "${CYAN}   - Setting up Fragment packet filtering...${NC}"
    $IPT -A INPUT -f -j DROP

    # 7. SSH allow — BEFORE any rate limits so you never lock yourself out (command #6)
    echo -e "${CYAN}   - Allowing SSH on port ${ssh_port} (before connection limits)...${NC}"
    $IPT -A INPUT -p tcp --dport "$ssh_port" -m conntrack --ctstate NEW -j ACCEPT
    if [[ -z "$SSH_PORT" ]]; then
        echo -e "${YELLOW}   ${INFO} SSH port auto-detected as ${BOLD}${ssh_port}${NC}${YELLOW}. Wrong? Re-run with: --ssh-port <PORT>${NC}"
    fi

    # 8. Limit connections per IP
    echo -e "${CYAN}   - Setting up TCP connection limit (${CONN_LIMIT}/IP)...${NC}"
    $IPT -A INPUT -p tcp --syn -m connlimit --connlimit-above "$CONN_LIMIT" -j DROP

    # 9. SYN Flood Protection
    echo -e "${CYAN}   - Setting up SYN Flood protection...${NC}"
    $IPT -N SYN_FLOOD
    $IPT -A INPUT -p tcp --syn -j SYN_FLOOD
    $IPT -A SYN_FLOOD -m limit --limit "$SYN_RATE" --limit-burst "$SYN_BURST" -j RETURN
    $IPT -A SYN_FLOOD -j DROP

    # 10. UDP Flood Protection — scoped to application/game ports only (command #3)
    if [[ -n "$UDP_GAME_PORTS" ]]; then
        echo -e "${CYAN}   - Setting up UDP Flood protection (ports: ${UDP_GAME_PORTS})...${NC}"
        $IPT -N UDP_FLOOD
        if [[ "$UDP_GAME_PORTS" == "*" ]]; then
            $IPT -A INPUT -p udp -j UDP_FLOOD
        else
            local up
            for up in $UDP_GAME_PORTS; do
                $IPT -A INPUT -p udp --dport "$up" -j UDP_FLOOD
            done
        fi
        $IPT -A UDP_FLOOD -m limit --limit "$UDP_RATE" --limit-burst "$UDP_BURST" -j RETURN
        $IPT -A UDP_FLOOD -j DROP
    else
        echo -e "${YELLOW}   ${INFO} UDP_GAME_PORTS is empty — skipping UDP flood chain${NC}"
    fi

    # 11. ICMP (Ping) Flood Protection
    echo -e "${CYAN}   - Setting up ICMP Flood protection...${NC}"
    $IPT -N ICMP_FLOOD
    $IPT -A INPUT -p icmp -j ICMP_FLOOD
    $IPT -A ICMP_FLOOD -m limit --limit "$ICMP_RATE" --limit-burst "$ICMP_BURST" -j RETURN
    $IPT -A ICMP_FLOOD -j DROP

    # 12. Port scan protection (proper chain so RETURN works)
    echo -e "${CYAN}   - Setting up Port Scan protection...${NC}"
    $IPT -N PORT_SCAN
    $IPT -A INPUT -p tcp --tcp-flags SYN,ACK,FIN,RST RST -j PORT_SCAN
    $IPT -A PORT_SCAN -m limit --limit "$SCAN_RATE" --limit-burst "$SCAN_BURST" -j RETURN
    $IPT -A PORT_SCAN -j DROP

    echo ""
    echo -e "${GREEN}${CHECK}${BOLD} Anti-DDoS rules applied successfully!${NC}"
    echo -e "${BLUE}   SSH     : allowed on port ${ssh_port}${NC}"
    echo -e "${BLUE}   UDP     : flood-guarded on ports ${UDP_GAME_PORTS:-none}${NC}"
    echo -e "${BLUE}   Monitor : sudo $0 monitor${NC}"
}

#------------------------------------------------------------------------------
# Whitelist / blacklist via ipset (command #4) with plain-iptables fallback
#------------------------------------------------------------------------------
function whitelist_cmd() {
    local sub="${1:-}"
    if [[ -z "$sub" ]]; then
        echo -e "${YELLOW}Usage: sudo $0 whitelist <IP|CIDR> | whitelist list | whitelist del <IP|CIDR>${NC}"
        return 1
    fi
    if [[ "$sub" == "list" ]]; then show_set "$WHITELIST_SET"; return 0; fi

    local op="add" target="$sub"
    if [[ "$sub" == "del" || "$sub" == "remove" ]]; then op="del"; target="${2:-}"; fi
    [[ -z "$target" ]] && { echo -e "${RED}${CROSS} Error: IP address is required.${NC}"; return 1; }
    is_valid_target "$target" || { echo -e "${RED}${CROSS} Error: '$target' is not a valid IPv4/CIDR.${NC}"; return 1; }

    if command_exists ipset; then
        ensure_ipset_hooks
        if [[ "$op" == "add" ]]; then
            ipset add "$WHITELIST_SET" "$target" -exist \
                && echo -e "${GREEN}${CHECK} Whitelisting IP: $target (ipset, O(1))${NC}"
        else
            ipset del "$WHITELIST_SET" "$target" -exist \
                && echo -e "${GREEN}${CHECK} Removed from whitelist: $target${NC}"
        fi
    else
        echo -e "${YELLOW}${WARN} ipset missing — using fallback linear iptables rule${NC}"
        if [[ "$op" == "add" ]]; then
            $IPT -C INPUT -s "$target" -j ACCEPT 2>/dev/null || $IPT -I INPUT 1 -s "$target" -j ACCEPT
            echo -e "${GREEN}${CHECK} Whitelisting IP: $target${NC}"
        else
            $IPT -D INPUT -s "$target" -j ACCEPT 2>/dev/null
            echo -e "${GREEN}${CHECK} Removed from whitelist: $target${NC}"
        fi
    fi
}

function blacklist_cmd() {
    local sub="${1:-}"
    if [[ -z "$sub" ]]; then
        echo -e "${YELLOW}Usage: sudo $0 blacklist <IP|CIDR> | blacklist list | blacklist del <IP|CIDR>${NC}"
        return 1
    fi
    if [[ "$sub" == "list" ]]; then show_set "$BLACKLIST_SET"; return 0; fi

    local op="add" target="$sub"
    if [[ "$sub" == "del" || "$sub" == "remove" ]]; then op="del"; target="${2:-}"; fi
    [[ -z "$target" ]] && { echo -e "${RED}${CROSS} Error: IP address is required.${NC}"; return 1; }
    is_valid_target "$target" || { echo -e "${RED}${CROSS} Error: '$target' is not a valid IPv4/CIDR.${NC}"; return 1; }

    if command_exists ipset; then
        ensure_ipset_hooks
        if [[ "$op" == "add" ]]; then
            ipset add "$BLACKLIST_SET" "$target" -exist \
                && echo -e "${RED}${WARN} Blacklisting IP: $target (ipset, O(1))${NC}"
        else
            ipset del "$BLACKLIST_SET" "$target" -exist \
                && echo -e "${GREEN}${CHECK} Removed from blacklist: $target${NC}"
        fi
    else
        echo -e "${YELLOW}${WARN} ipset missing — using fallback linear iptables rule${NC}"
        if [[ "$op" == "add" ]]; then
            $IPT -C INPUT -s "$target" -j DROP 2>/dev/null || $IPT -I INPUT 1 -s "$target" -j DROP
            echo -e "${RED}${WARN} Blacklisting IP: $target${NC}"
        else
            $IPT -D INPUT -s "$target" -j DROP 2>/dev/null
            echo -e "${GREEN}${CHECK} Removed from blacklist: $target${NC}"
        fi
    fi
}

#------------------------------------------------------------------------------
# Real-time monitoring
#------------------------------------------------------------------------------
function monitor_traffic() {
    show_banner
    echo -e "${BOLD}${FIRE} Entering real-time monitoring mode (Press Ctrl+C to exit)...${NC}"
    echo ""
    trap 'echo ""; echo -e "${INFO} Monitoring stopped."; exit 0' INT
    local drops
    while true; do
        clear
        show_banner
        echo -e "${BOLD}${BLUE}--- REAL-TIME DROPPED PACKETS ---${NC}"
        drops=$($IPT -L -n -v 2>/dev/null | grep -E "DROP|REJECT" | grep -v "0     0")
        if [[ -n "$drops" ]]; then echo "$drops"; else echo "  (no packets dropped yet)"; fi

        echo ""
        echo -e "${BOLD}${BLUE}--- TOP TALKERS (established connections) ---${NC}"
        if command_exists ss; then
            ss -H -tn state established 2>/dev/null | \
                awk '{n=split($4,p,":"); gsub(/\[/,"",p[1]); print p[1]}' | \
                sort | uniq -c | sort -rn | head -10 || echo "  (none)"
        fi

        echo ""
        echo -e "${BOLD}${BLUE}--- CURRENT CONNECTIONS SUMMARY ---${NC}"
        if command_exists ss; then
            ss -s
        else
            netstat -ant 2>/dev/null | awk '{print $6}' | sort | uniq -c | sort -n
        fi
        sleep 2
    done
}

#------------------------------------------------------------------------------
# Persistence (rules + ipsets + sysctl survive reboot)
#------------------------------------------------------------------------------
function save_persistence() {
    echo -e "${YELLOW}${INFO} Saving current rules for persistence...${NC}"
    mkdir -p /etc/iptables 2>/dev/null
    if $IPS > /etc/iptables/rules.v4 2>/dev/null; then
        echo -e "${GREEN}${CHECK} Rules saved to /etc/iptables/rules.v4${NC}"
    else
        echo -e "${RED}${CROSS} Failed to save iptables rules (is iptables-save available?).${NC}"
    fi

    if command_exists ipset; then
        if ipset save > /etc/ipset.conf 2>/dev/null; then
            echo -e "${GREEN}${CHECK} IP sets saved to /etc/ipset.conf${NC}"
        else
            echo -e "${YELLOW}${WARN} Could not save ipset sets.${NC}"
        fi
    fi

    if [[ -f "$SYSCTL_CONF" ]]; then
        echo -e "${GREEN}${CHECK} sysctl settings already persisted at ${SYSCTL_CONF}${NC}"
    else
        echo -e "${YELLOW}${INFO} Run 'sudo $0 start' (or 'tune') once to generate ${SYSCTL_CONF}${NC}"
    fi

    if command_exists systemctl && systemctl list-unit-files 2>/dev/null | grep -q netfilter-persistent; then
        systemctl enable netfilter-persistent >/dev/null 2>&1 \
            && echo -e "${GREEN}${CHECK} netfilter-persistent enabled at boot${NC}"
    else
        echo -e "${YELLOW}${INFO} For automatic boot restore, install: iptables-persistent (+ ipset-persistent on Debian/Ubuntu)${NC}"
    fi
}

#------------------------------------------------------------------------------
# Argument parsing: global options + command dispatch
#------------------------------------------------------------------------------
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh-port)   SSH_PORT="$2"; shift 2 ;;
        --ssh-port=*) SSH_PORT="${1#*=}"; shift ;;
        -h|--help|help|guide)
            show_banner
            show_guide
            exit 0 ;;
        *) ARGS+=("$1"); shift ;;
    esac
done

CMD="${ARGS[0]:-}"

# No command -> show the built-in guide
if [[ -z "$CMD" ]]; then
    show_banner
    show_guide
    exit 1
fi

# Root check for everything that touches the firewall
if [[ $EUID -ne 0 ]]; then
    show_banner
    echo -e "${RED}${CROSS} Error: This script must be run as root (try: sudo $0 ${CMD}).${NC}"
    exit 1
fi

# Command #8: automatic first-run system scan
if [[ ! -f "$SCAN_FLAG" ]]; then
    scan_system
fi

case "$CMD" in
    start)     start_antiddos ;;
    stop)      stop_antiddos ;;
    restart)   stop_antiddos; echo ""; start_antiddos ;;
    status)    status_antiddos ;;
    clear)     clear_rules ;;
    whitelist) whitelist_cmd "${ARGS[@]:1}" ;;
    blacklist) blacklist_cmd "${ARGS[@]:1}" ;;
    monitor)   monitor_traffic ;;
    save)      save_persistence ;;
    scan)      scan_system force ;;
    tune|sysctl) tune_sysctl ;;
    guide|help) show_banner; show_guide ;;
    *)
        show_banner
        show_guide
        echo -e "${RED}Unknown command: ${CMD}${NC}"
        exit 1
        ;;
esac

exit 0
