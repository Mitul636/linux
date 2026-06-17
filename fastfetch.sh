#!/bin/bash

clear

# ==============================
#   FASTFETCH AUTO INSTALLER (UPDATED)
#   Made by HopingBoyz
#   Improved And Updated by Mitul Playz
# ==============================

# Fancy ASCII Art
cat << "EOF"
 ______                 _____   _______   ______   ______   _______     _____   _    _ 
|  ____|       /\      / ____| |__   __| |  ____| |  ____| |__   __|   / ____| | |  | |
| |__         /  \    | (___      | |    | |__    | |__       | |     | |      | |__| |
|  __|       / /\ \    \___ \     | |    |  __|   |  __|      | |     | |      |  __  |
| |         / ____ \   ____) |    | |    | |      | |____     | |     | |____  | |  | |
|_|        /_/    \_\ |_____/     |_|    |_|      |______|    |_|      \_____| |_|  |_|
                                                                                       

                             Fastfetch Auto Installer
                                Made by Hopingboyz
EOF

echo ""
echo ">>> Detecting system architecture..."
ARCH=$(dpkg --print-architecture)

echo ">>> Architecture detected: $ARCH"
echo ""

# Select correct download URL based on architecture
case $ARCH in
    amd64)
        URL="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb"
        ;;
    arm64)
        URL="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-arm64.deb"
        ;;
    *)
        echo "❌ Unsupported architecture: $ARCH"
        echo "Supported: amd64, arm64"
        exit 1
        ;;
esac

echo ">>> Installing dependencies..."
sudo apt update -y

echo ""
echo ">>> Downloading Fastfetch package..."
cd /tmp || exit
wget -q "$URL" -O fastfetch.deb

if [ ! -f "fastfetch.deb" ]; then
    echo "❌ Download failed!"
    exit 1
fi

echo ">>> Installing Fastfetch..."
sudo apt install ./fastfetch.deb -y

if ! command -v fastfetch >/dev/null 2>&1; then
    echo "❌ Installation failed!"
    exit 1
fi

echo ""
echo "==========================================="
echo "   ✅ Fastfetch Installed Successfully!"
echo "   🎉 Enjoy the clean system info tool!"
echo "   🔥 Script Made by Hopingboyz"
echo "==========================================="
echo ""
fastfetch
