#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Update OliveTin Configuration Script
# Updates only the OliveTin config without full reinstall
# ═══════════════════════════════════════════════════════════════════════════

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}[✓]${NC} Updating OliveTin configuration..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if config file exists
if [ ! -f "$SCRIPT_DIR/config/olivetin-config.yaml" ]; then
    echo -e "${RED}[✗]${NC} Config file not found: $SCRIPT_DIR/config/olivetin-config.yaml"
    exit 1
fi

# Backup existing config
if [ -f /etc/OliveTin/config.yaml ]; then
    echo -e "${YELLOW}[i]${NC} Backing up existing config..."
    sudo cp /etc/OliveTin/config.yaml /etc/OliveTin/config.yaml.backup.$(date +%Y%m%d_%H%M%S)
fi

# Copy new config
echo -e "${GREEN}[✓]${NC} Installing new config..."
sudo cp "$SCRIPT_DIR/config/olivetin-config.yaml" /etc/OliveTin/config.yaml

# Restart OliveTin
echo -e "${GREEN}[✓]${NC} Restarting OliveTin..."
sudo systemctl restart OliveTin

echo ""
echo -e "${GREEN}[✓]${NC} OliveTin configuration updated successfully!"
echo -e "${YELLOW}[i]${NC} Dashboard: http://192.168.4.1:1337"
