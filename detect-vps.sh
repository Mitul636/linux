#!/usr/bin/env bash

# ==========================================================
# Advanced Server Detection v3.2
# No external packages required (uses native tools/sysfs)
# Supports:
# - Dual-Stack Network Layer (True IPv4/IPv6 verification)
# - Byte-Accurate Hardware Matrix (RAM/Disk down to the byte)
# - Deep CPU Topology Tracing (Sockets, Cores, Threads, Caches)
# - Advanced Virtualization & Cloud Provider Identification
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

clear

banner() {
echo -e "${CYAN}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "        ADVANCED SERVER, HARDWARE & NETWORK DETECTOR v3.2"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${NC}"
}

banner

HOSTNAME=$(hostname 2>/dev/null)
OS=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d'"' -f2)
[ -z "$OS" ] && OS=$(uname -o)
KERNEL=$(uname -r)

# ==========================================================
# Deep CPU Topology Architecture Tracing
# ==========================================================
CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//')
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(uname -p)

CPU_ARCH=$(uname -m)
CPU_TOTAL_THREADS=$(nproc 2>/dev/null)
[ -z "$CPU_TOTAL_THREADS" ] && CPU_TOTAL_THREADS=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null)

# Sockets, physical cores, and hyper-threading breakdown via sysfs/procinfo
CPU_SOCKETS=$(grep "physical id" /proc/cpuinfo 2>/dev/null | sort -u | wc -l)
[ "$CPU_SOCKETS" -eq 0 ] && CPU_SOCKETS=1

CORES_PER_SOCKET=$(grep "cpu cores" /proc/cpuinfo 2>/dev/null | uniq | awk '{print $4}')
[ -z "$CORES_PER_SOCKET" ] && CORES_PER_SOCKET=$((CPU_TOTAL_THREADS / CPU_SOCKETS))

TOTAL_PHYSICAL_CORES=$((CPU_SOCKETS * CORES_PER_SOCKET))

if [ "$CPU_TOTAL_THREADS" -gt "$TOTAL_PHYSICAL_CORES" ]; then
    SMT_STATUS="Enabled (Hyper-Threading / SMT Active)"
else
    SMT_STATUS="Disabled / Not Supported"
fi

# Extracting Level 1, 2, and 3 Processor Caches via sysfs
L1D_CACHE=$(cat /sys/devices/system/cpu/cpu0/cache/index0/size 2>/dev/null)
L1I_CACHE=$(cat /sys/devices/system/cpu/cpu0/cache/index1/size 2>/dev/null)
L2_CACHE=$(cat /sys/devices/system/cpu/cpu0/cache/index2/size 2>/dev/null)
L3_CACHE=$(cat /sys/devices/system/cpu/cpu0/cache/index3/size 2>/dev/null)

# ==========================================================
# Byte-Accurate RAM & Disk Metrics
# ==========================================================
# Parsing meminfo cleanly to bypass free formatting fluctuations
RAM_TOTAL_KIB=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null)
RAM_TOTAL_BYTES=$((RAM_TOTAL_KIB * 1024))
RAM_HUMAN=$(free -h | awk '/^Mem:/ {print $2}')

# Disk Byte verification using explicitly defined block metrics
DISK_TOTAL_BYTES=$(df -B1 / 2>/dev/null | awk 'NR==2 {print $2}')
DISK_FREE_BYTES=$(df -B1 / 2>/dev/null | awk 'NR==2 {print $4}')
DISK_HUMAN=$(df -h / | awk 'NR==2 {print $2}')

PRODUCT_NAME=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
SYS_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
BOARD_NAME=$(cat /sys/class/dmi/id/board_name 2>/dev/null)
DMI_INFO="$(echo "$PRODUCT_NAME $SYS_VENDOR $BOARD_NAME" | tr '[:upper:]' '[:lower:]')"

SCORE=0

# ==========================================================
# Virtualization Detection
# ==========================================================
VIRT="none"
if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT=$(systemd-detect-virt 2>/dev/null)
fi
[ -f /.dockerenv ] && VIRT="docker"
grep -qa container=lxc /proc/1/environ 2>/dev/null && VIRT="lxc"
[ -d /proc/vz ] && [ ! -d /proc/bc ] && VIRT="openvz"

# ==========================================================
# Network & IP Capabilities Layer (Dual-Stack Verification)
# ==========================================================
LOCAL_IPV4=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
LOCAL_IPV6=$(ip route get 2606:4700:4700::1111 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
[ -z "$LOCAL_IPV4" ] && LOCAL_IPV4=$(hostname -I 2>/dev/null | awk '{print $1}')

# Multi-endpoint fallbacks for resilient WAN checking
fetch_net() {
    if command -v curl >/dev/null 2>&1; then
        curl -s --max-time 3 "$@"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout=3 "$@"
    fi
}

# Real-time Dual-Stack Validation
PUBLIC_IPV4=$(fetch_net -4 https://v4.ident.me 2>/dev/null)
[ -z "$PUBLIC_IPV4" ] && PUBLIC_IPV4=$(fetch_net -4 https://api.ipify.org 2>/dev/null)
[ -z "$PUBLIC_IPV4" ] && PUBLIC_IPV4="Not Routed/Protected"

PUBLIC_IPV6=$(fetch_net -6 https://v6.ident.me 2>/dev/null)
[ -z "$PUBLIC_IPV6" ] && PUBLIC_IPV6=$(fetch_net -6 https://api6.ipify.org 2>/dev/null)
[ -z "$PUBLIC_IPV6" ] && PUBLIC_IPV6="Not Routed/None"

# Master JSON Payload pull for Geolocation/ISP data mapping
IP_DATA=$(fetch_net https://ipinfo.io/json 2>/dev/null)
ISP="Unknown / Offline"
LOCATION="Unknown"

if [ -n "$IP_DATA" ]; then
    ISP=$(echo "$IP_DATA" | awk -F'"' '/"org"/ {print $4}')
    CITY=$(echo "$IP_DATA" | awk -F'"' '/"city"/ {print $4}')
    COUNTRY=$(echo "$IP_DATA" | awk -F'"' '/"country"/ {print $4}')
    [ -n "$CITY" ] && LOCATION="$CITY, $COUNTRY"
fi

# ==========================================================
# Server Type & Cloud Provider Translation Matrix
# ==========================================================
SERVER_TYPE="Unknown"
case "$VIRT" in
    docker)   SERVER_TYPE="Docker Container" ;;
    lxc)      SERVER_TYPE="LXC Container" ;;
    podman)   SERVER_TYPE="Podman Container" ;;
    openvz)   SERVER_TYPE="OpenVZ Container" ;;
    kvm)      SERVER_TYPE="KVM VPS" ;;
    qemu)     SERVER_TYPE="QEMU VPS" ;;
    vmware)   SERVER_TYPE="VMware VM" ;;
    xen)      SERVER_TYPE="Xen VPS" ;;
    oracle)   SERVER_TYPE="VirtualBox VM" ;;
    microsoft)SERVER_TYPE="Hyper-V VPS" ;;
    amazon)   SERVER_TYPE="Amazon EC2 Instance" ;;
    google)   SERVER_TYPE="Google Cloud VM" ;;
    none)     SERVER_TYPE="Bare Metal Server" ;;
    *)        SERVER_TYPE="$VIRT" ;;
esac

# ASN / Network Org checking as a deep signature fallback
if [ "$SERVER_TYPE" = "KVM VPS" ] || [ "$SERVER_TYPE" = "QEMU VPS" ] || [ "$SERVER_TYPE" = "Unknown" ]; then
    if echo "$ISP" | grep -qi "amazon"; then SERVER_TYPE="Amazon EC2 Instance"; fi
    if echo "$ISP" | grep -qi "google"; then SERVER_TYPE="Google Cloud VM"; fi
    if echo "$ISP" | grep -qi "digitalocean"; then SERVER_TYPE="DigitalOcean Droplet"; fi
    if echo "$ISP" | grep -qi "linode"; then SERVER_TYPE="Linode Instance"; fi
    if echo "$ISP" | grep -qi "hetzner"; then SERVER_TYPE="Hetzner Cloud VPS"; fi
    if echo "$ISP" | grep -qi "vultr"; then SERVER_TYPE="Vultr VPS"; fi
    if echo "$ISP" | grep -qi "microsoft"; then SERVER_TYPE="Microsoft Azure VM"; fi
fi

MACHINE_TYPE="Unknown"
case "$DMI_INFO" in
    *q35*)          MACHINE_TYPE="Q35 (QEMU)" ;;
    *i440fx*)       MACHINE_TYPE="i440FX (QEMU)" ;;
    *kvm*)          MACHINE_TYPE="KVM" ;;
    *qemu*)         MACHINE_TYPE="QEMU" ;;
    *vmware*)       MACHINE_TYPE="VMware" ;;
    *virtualbox*)   MACHINE_TYPE="VirtualBox" ;;
    *xen*)          MACHINE_TYPE="Xen" ;;
    *hyper-v*|*microsoft*) MACHINE_TYPE="Hyper-V" ;;
    *proxmox*)      MACHINE_TYPE="Proxmox" ;;
    *openstack*)    MACHINE_TYPE="OpenStack" ;;
    *amazon*)       MACHINE_TYPE="Amazon Web Services" ;;
    *google*)       MACHINE_TYPE="Google Cloud Platform" ;;
    *azure*)        MACHINE_TYPE="Microsoft Azure" ;;
    *)
        if echo "$ISP" | grep -qi "amazon"; then MACHINE_TYPE="AWS (via ASN)";
        elif echo "$ISP" | grep -qi "google"; then MACHINE_TYPE="GCP (via ASN)";
        elif echo "$ISP" | grep -qi "digitalocean"; then MACHINE_TYPE="DigitalOcean (via ASN)";
        elif echo "$ISP" | grep -qi "linode"; then MACHINE_TYPE="Linode (via ASN)";
        elif echo "$ISP" | grep -qi "hetzner"; then MACHINE_TYPE="Hetzner (via ASN)";
        elif echo "$ISP" | grep -qi "microsoft"; then MACHINE_TYPE="Azure (via ASN)";
        elif [ "$VIRT" != "none" ]; then MACHINE_TYPE=$(echo "$VIRT" | tr '[:lower:]' '[:upper:]'); fi
        ;;
esac

# Hardware Validation Scoring System
ASSESSMENT="Unknown"
case "$VIRT" in
    docker|lxc|podman|openvz) ASSESSMENT="Container" ;;
    none)                     ASSESSMENT="Bare Metal" ;;
    *)
        if echo "$CPU_MODEL" | grep -qi -E "epyc|xeon"; then SCORE=$((SCORE+2)); fi
        if [ "$CPU_TOTAL_THREADS" -e 8 ]; then SCORE=$((SCORE+1)); fi
        if grep -qi hypervisor /proc/cpuinfo; then SCORE=$((SCORE+2)); fi

        if [ "$SCORE" -ge 4 ]; then ASSESSMENT="VDS"; else ASSESSMENT="VPS"; fi
        ;;
esac

# ==========================================================
# Output Engine Visual Render
# ==========================================================
echo -e "${WHITE}Hostname       :${NC} $HOSTNAME"
echo -e "${WHITE}Operating Sys  :${NC} $OS"
echo -e "${WHITE}Kernel Version :${NC} $KERNEL"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}[ Dual-Stack Network Layer ]${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${WHITE}Public IPv4    :${NC} $PUBLIC_IPV4"
echo -e "${WHITE}Public IPv6    :${NC} $PUBLIC_IPV6"
echo -e "${WHITE}Local Network  :${NC} IPv4: [${LOCAL_IPV4:-None}] | IPv6: [${LOCAL_IPV6:-None}]"
echo -e "${WHITE}Network ISP    :${NC} $ISP"
echo -e "${WHITE}Geo Location   :${NC} $LOCATION"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}[ CPU Topology & Architecture Tracing ]${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${WHITE}Processor Model:${NC} $CPU_MODEL"
echo -e "${WHITE}Architecture   :${NC} $CPU_ARCH"
echo -e "${WHITE}Physical Layout:${NC} Sockets: $CPU_SOCKETS | Cores/Socket: $CORES_PER_SOCKET"
echo -e "${WHITE}Processors     :${NC} Total Processing Threads: $CPU_TOTAL_THREADS"
echo -e "${WHITE}SMT / HT Info  :${NC} $SMT_STATUS"
echo -e "${WHITE}Hardware Cache :${NC} L1d: ${L1D_CACHE:-N/A} | L1i: ${L1I_CACHE:-N/A} | L2: ${L2_CACHE:-N/A} | L3: ${L3_CACHE:-N/A}"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}[ Byte-Accurate Memory & Storage Matrix ]${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${WHITE}Total Memory   :${NC} $RAM_HUMAN ($RAM_TOTAL_BYTES Bytes)"
echo -e "${WHITE}Root Disk Cap  :${NC} $DISK_HUMAN ($DISK_TOTAL_BYTES Bytes)"
echo -e "${WHITE}Root Disk Free :${NC} $DISK_FREE_BYTES Bytes"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}[ Virtualization & Hypervisor Footprint ]${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${WHITE}Server Type    :${NC} $SERVER_TYPE"
echo -e "${WHITE}Virtual Driver :${NC} $VIRT"
echo -e "${WHITE}Machine Engine :${NC} $MACHINE_TYPE"
echo -e "${WHITE}DMI Platform   :${NC} ${PRODUCT_NAME:-Unknown}"
echo -e "${WHITE}System Vendor  :${NC} ${SYS_VENDOR:-Unknown}"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

case "$ASSESSMENT" in
    Container)   echo -e "${BLUE}Environment    : Containerized Context${NC}" ;;
    Bare\ Metal) echo -e "${GREEN}Environment    : Native Bare Metal Configuration${NC}" ;;
    VDS)         echo -e "${GREEN}Environment    : High-Resource Dedicated Virtual Server (VDS)${NC}" ;;
    VPS)         echo -e "${YELLOW}Environment    : Multi-Tenant Shared Resource Instance (VPS)${NC}" ;;
    *)           echo -e "${WHITE}Environment    : Unclassified/Dynamic${NC}" ;;
esac

echo -e "${WHITE}Confidence Score:${NC} $SCORE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$ASSESSMENT" = "Bare Metal" ]; then
    echo -e "${GREEN}FINAL VERDICT  : Bare Metal Infrastructure${NC}"
elif [ "$ASSESSMENT" = "Container" ]; then
    echo -e "${BLUE}FINAL VERDICT  : Micro-Engine/Container Namespace${NC}"
else
    echo -e "${CYAN}FINAL VERDICT  : $ASSESSMENT ($SERVER_TYPE)${NC}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
