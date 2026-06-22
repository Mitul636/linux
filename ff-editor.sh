#!/bin/bash

# ==========================================
# Fastfetch Interactive Menu Configurator
# ==========================================

CONFIG_DIR="$HOME/.config/fastfetch"
CONFIG_FILE="$CONFIG_DIR/config.jsonc"
BACKUP_FILE="$CONFIG_DIR/config.jsonc.bak"

# Initialize default variables
LOGO="auto"
LOGO_COLOR=""
KEY_COLOR=""

# Ensure the fastfetch config directory exists
mkdir -p "$CONFIG_DIR"

# Function to show the main menu
show_menu() {
    clear
    echo "========================================="
    echo "   Fastfetch Interactive Configurator    "
    echo "========================================="
    echo "1) Choose Logo         (Current: $LOGO)"
    echo "2) Set Logo Color      (Current: ${LOGO_COLOR:-Default})"
    echo "3) Set Key/Text Color  (Current: ${KEY_COLOR:-Default})"
    echo "4) Apply & Save Config"
    echo "5) Exit"
    echo "========================================="
    read -p "Choose an option [1-5]: " choice
}

# Function to choose a logo
choose_logo() {
    echo ""
    echo "Available Logos: arch, ubuntu, debian, fedora, mint, manjaro, windows, apple, none, auto"
    read -p "Enter logo name: " LOGO_INPUT
    if [ -n "$LOGO_INPUT" ]; then
        LOGO=$LOGO_INPUT
    fi
}

# Function to choose a color
choose_color() {
    echo ""
    echo "Available Colors: black, red, green, yellow, blue, magenta, cyan, white, default"
    read -p "Enter color name: " COLOR_INPUT
    echo "$COLOR_INPUT"
}

# Function to generate the JSONC config
generate_config() {
    # Backup existing config if it exists
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        echo "[*] Existing config backed up to config.jsonc.bak"
    fi

    # Format the Logo Block
    if [ -n "$LOGO_COLOR" ] && [ "$LOGO_COLOR" != "default" ]; then
        LOGO_BLOCK="\"logo\": { \"source\": \"$LOGO\", \"color\": {\"1\": \"$LOGO_COLOR\"} },"
    else
        LOGO_BLOCK="\"logo\": { \"source\": \"$LOGO\" },"
    fi

    # Format the Display (Key Color) Block
    if [ -n "$KEY_COLOR" ] && [ "$KEY_COLOR" != "default" ]; then
        DISPLAY_BLOCK="\"display\": { \"color\": \"$KEY_COLOR\" },"
    else
        DISPLAY_BLOCK="\"display\": {},"
    fi

    # Write the new config file
    cat > "$CONFIG_FILE" << EOF
{
  "\$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  $LOGO_BLOCK
  $DISPLAY_BLOCK
  "modules": [
    "title",
    "separator",
    "os",
    "host",
    "kernel",
    "uptime",
    "packages",
    "shell",
    "display",
    "de",
    "wm",
    "theme",
    "icons",
    "font",
    "cursor",
    "terminal",
    "cpu",
    "gpu",
    "memory",
    "swap",
    "disk",
    "localip",
    "battery",
    "poweradapter",
    "break",
    "colors"
  ]
}
EOF
    echo "[*] New fastfetch configuration generated and saved!"
    echo "[*] Running fastfetch to preview..."
    echo ""
    fastfetch
    echo ""
    read -p "Press [Enter] to return to the menu..."
}

# Main script loop
while true; do
    show_menu
    case $choice in
        1)
            choose_logo
            ;;
        2)
            LOGO_COLOR=$(choose_color)
            ;;
        3)
            KEY_COLOR=$(choose_color)
            ;;
        4)
            generate_config
            ;;
        5)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option. Please try again."
            sleep 1
            ;;
    esac
done
