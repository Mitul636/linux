#!/bin/bash

clear

# ==============================
#   FASTFETCH AUTO INSTALLER (PROOT VERSION)
#   Made by Mitul Playz
# ==============================

# Fancy ASCII Art
cat << "EOF"
 ______          _____   _______   ______   ______   _______     _____   _    _ 
|  ____|        /\      / ____| |__   __| |  ____| |  ____| |__   __|   / ____| | |  | |
| |__          /  \    | (___      | |    | |__    | |__       | |     | |      | |__| |
|  __|        / /\ \    \___ \     | |    |  __|   |  __|      | |     | |      |  __  |
| |          / ____ \   ____) |    | |    | |      | |____     | |     | |____  | |  | |
|_|         /_/    \_\ |_____/     |_|    |_|      |______|    |_|      \_____| |_|  |_|
                                                                                        

                           Fastfetch Auto Installer
                             Made by Mitul Playz
EOF

echo ""
echo ">>> Detecting system architecture..."
# Using uname -m is safer in proot than dpkg, as dpkg might be restricted
ARCH=$(uname -m)

# Select correct download architecture
case $ARCH in
    x86_64)
        FF_ARCH="amd64"
        ;;
    aarch64|arm64)
        FF_ARCH="aarch64"
        ;;
    *)
        echo "❌ Unsupported architecture: $ARCH"
        echo "Supported: x86_64 (amd64), aarch64 (arm64)"
        exit 1
        ;;
esac

echo ">>> Architecture detected: $FF_ARCH"
echo ""

URL="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${FF_ARCH}.tar.gz"

echo ">>> Setting up local directories..."
# We install to ~/.local to avoid needing root/sudo permissions
INSTALL_DIR="$HOME/.local"
BIN_DIR="$INSTALL_DIR/bin"
mkdir -p "$BIN_DIR"

echo ">>> Downloading Fastfetch package..."
cd /tmp || exit
# Clean up any previous attempts
rm -rf fastfetch.tar.gz fastfetch-linux-*
wget -q "$URL" -O fastfetch.tar.gz

if [ ! -f "fastfetch.tar.gz" ]; then
    echo "❌ Download failed!"
    exit 1
fi

echo ">>> Extracting and installing Fastfetch..."
tar -xzf fastfetch.tar.gz

# Copy the extracted binaries and assets to the local user directory
cp -r fastfetch-linux-*/usr/* "$INSTALL_DIR/"
chmod +x "$BIN_DIR/fastfetch"

# Clean up temp files
rm -rf fastfetch.tar.gz fastfetch-linux-*

# Add ~/.local/bin to PATH if it isn't already there
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ">>> Adding $BIN_DIR to PATH in ~/.bashrc..."
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"
fi

if ! command -v fastfetch >/dev/null 2>&1; then
    # Fallback check just in case PATH hasn't refreshed in the current session
    if [ -x "$BIN_DIR/fastfetch" ]; then
        echo ""
        echo "⚠️  Fastfetch installed, but you may need to run 'source ~/.bashrc' or restart your terminal."
        echo ""
        "$BIN_DIR/fastfetch"
    else
        echo "❌ Installation failed!"
        exit 1
    fi
else
    echo ""
    echo "==========================================="
    echo "   ✅ Fastfetch Installed Successfully!"
    echo "   🎉 Enjoy the clean system info tool!"
    echo "   🔥 Script Made by Mitul Playz"
    echo "==========================================="
    echo ""
    fastfetch
fi
