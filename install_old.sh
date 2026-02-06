#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Delling Installation Script
# Emergency Hub for Raspberry Pi
# ═══════════════════════════════════════════════════════════════════════════

set -e  # Exit on error

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ═══════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[i]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

check_root() {
    if [ "$EUID" -eq 0 ]; then
        print_error "Do NOT run this script as root."
        print_info "Run as the user that will own the Delling services."
        exit 1
    fi
}

check_arch() {
    ARCH=$(uname -m)
    if [[ "$ARCH" != "aarch64" && "$ARCH" != "armv7l" && "$ARCH" != arm* ]]; then
        print_info "Warning: Detected architecture $ARCH"
        print_info "This script is designed for ARM (Raspberry Pi / Orange Pi)"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION QUESTIONS (Asked upfront)
# ═══════════════════════════════════════════════════════════════════════════

ask_questions() {
    print_header "Delling Installation"
    
    echo "Welcome to Delling - your emergency information hub!"
    echo ""
    echo "This script will install and configure:"
    echo "  • WiFi Access Point (open network 'Delling')"
    echo "  • Delling Dashboard"
    echo "  • Tinymedia (media server)"
    echo "  • Kiwix (offline Wikipedia)"
    echo "  • FM/VHF Radio, DAB+ Radio, OpenWebRX"
    echo "  • ADS-B aircraft tracking, AIS ship tracking"
    echo ""
    echo "Please answer a few questions before we begin."
    echo ""

    # Username
    CURRENT_USER=$(whoami)
    read -p "Run services as user [$CURRENT_USER]: " INPUT_USER
    DELLING_USER=${INPUT_USER:-$CURRENT_USER}
    
    # WiFi SSID
    read -p "WiFi network name [Delling]: " INPUT_SSID
    WIFI_SSID=${INPUT_SSID:-Delling}
    
    # WiFi Channel
    read -p "WiFi channel (1-11) [6]: " INPUT_CHANNEL
    WIFI_CHANNEL=${INPUT_CHANNEL:-6}
    
    # USB mount point
    read -p "USB mount point [/media/usb]: " INPUT_USB
    USB_MOUNT=${INPUT_USB:-/media/usb}
    
    # OpenWebRX admin password
    echo ""
    print_info "OpenWebRX requires an admin password for its web interface."
    read -s -p "OpenWebRX admin password: " OPENWEBRX_PASS
    echo ""
    
    # Confirm
    echo ""
    print_header "Configuration Summary"
    echo "  User:           $DELLING_USER"
    echo "  WiFi SSID:      $WIFI_SSID"
    echo "  WiFi Channel:   $WIFI_CHANNEL"
    echo "  USB Mount:      $USB_MOUNT"
    echo "  OpenWebRX Pass: ********"
    echo ""
    
    read -p "Proceed with installation? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 1: BASE SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

phase1_base_system() {
    print_header "Phase 1: Base System"
    
    print_step "Updating package lists..."
    sudo apt update
    
    print_step "Upgrading system packages..."
    sudo apt upgrade -y
    
    print_step "Creating Delling directories..."
    sudo mkdir -p /opt/delling/scripts
    sudo mkdir -p /opt/delling/config
    sudo chown -R "$DELLING_USER:$DELLING_USER" /opt/delling
    
    print_step "Installing common dependencies..."
    sudo apt install -y \
        git \
        python3 \
        python3-pip \
        python3-flask \
        curl \
        wget \
        ffmpeg \
        gcc \
        build-essential
    
    print_step "Phase 1 complete!"
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 2: NETWORK
# ═══════════════════════════════════════════════════════════════════════════

phase2_network() {
    print_header "Phase 2: Network Configuration"
    
    # Check if AP already exists
    if nmcli con show DellingAP &>/dev/null; then
        print_info "WiFi AP 'DellingAP' already exists, removing..."
        sudo nmcli con delete DellingAP
    fi
    
    print_step "Creating WiFi Access Point '$WIFI_SSID'..."
    sudo nmcli con add type wifi ifname wlan0 mode ap con-name DellingAP ssid "$WIFI_SSID" \
        wifi.band bg \
        wifi.channel "$WIFI_CHANNEL" \
        ipv4.method shared \
        ipv4.addresses 192.168.4.1/24 \
        ipv6.method disabled
    
    print_step "Enabling WiFi AP..."
    sudo nmcli con up DellingAP
    sudo nmcli con modify DellingAP connection.autoconnect yes
    
    print_step "Installing dnsmasq for captive portal..."
    sudo apt install -y dnsmasq
    
    print_step "Configuring DNS redirect..."
    echo 'address=/#/192.168.4.1' | sudo tee /etc/NetworkManager/dnsmasq-shared.d/captive.conf
    
    print_step "Installing nftables..."
    sudo apt install -y nftables
    
    print_step "Configuring HTTP redirect to dashboard..."
    sudo nft add table ip captive 2>/dev/null || true
    sudo nft add chain ip captive prerouting { type nat hook prerouting priority -100 \; } 2>/dev/null || true
    sudo nft add rule ip captive prerouting iifname "wlan0" tcp dport 80 redirect to :1337 2>/dev/null || true
    sudo nft list ruleset | sudo tee /etc/nftables.conf > /dev/null
    sudo systemctl enable nftables
    
    print_step "Disabling IP forwarding..."
    echo 'net.ipv4.ip_forward = 0' | sudo tee /etc/sysctl.d/99-no-forward.conf
    sudo sysctl -p /etc/sysctl.d/99-no-forward.conf 2>/dev/null || true
    
    print_step "Restarting NetworkManager..."
    sudo systemctl restart NetworkManager
    
    print_step "Phase 2 complete!"
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 3: DASHBOARD
# ═══════════════════════════════════════════════════════════════════════════

phase3_dashboard() {
    print_header "Phase 3: Delling Dashboard"
    
    print_step "Installing dashboard..."
    sudo mkdir -p /opt/delling/dashboard
    sudo cp "$SCRIPT_DIR/dashboard/app.py" /opt/delling/dashboard/
    sudo chown -R $DELLING_USER:$DELLING_USER /opt/delling/dashboard
    
    print_step "Creating dashboard service..."
    cat << EOF | sudo tee /etc/systemd/system/delling-dashboard.service > /dev/null
[Unit]
Description=Delling Dashboard
After=network.target

[Service]
Type=simple
User=$DELLING_USER
WorkingDirectory=/opt/delling/dashboard
ExecStart=/usr/bin/python3 /opt/delling/dashboard/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    print_step "Enabling dashboard service..."
    sudo systemctl daemon-reload
    sudo systemctl enable --now delling-dashboard
    
    print_step "Phase 3 complete!"
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 4: ALWAYS-ON SERVICES
# ═══════════════════════════════════════════════════════════════════════════

phase4_always_on() {
    print_header "Phase 4: Always-On Services"
    
    # --- Tinymedia ---
    print_step "Downloading Tinymedia..."
    if [ -d /opt/tinymedia ]; then
        print_info "Tinymedia directory exists, updating..."
        cd /opt/tinymedia && sudo git pull
    else
        sudo git clone https://github.com/tronba/Tinymedia /opt/tinymedia
        sudo chown -R $DELLING_USER:$DELLING_USER /opt/tinymedia
    fi
    print_info "Tinymedia downloaded. You will need to run its installer manually."
    print_info "See instructions at the end of installation."

    # --- Kiwix ---
    print_step "Installing Kiwix..."
    sudo apt install -y kiwix-tools
    
    print_step "Creating Kiwix startup script..."
    cat << EOF | sudo tee /opt/delling/scripts/start-kiwix.sh > /dev/null
#!/bin/bash
MOUNT_POINT="$USB_MOUNT"
KIWIX_FOLDER="kiwix"
PORT=8000
KIWIX_PATH="\$MOUNT_POINT/\$KIWIX_FOLDER"

if ! mountpoint -q "\$MOUNT_POINT"; then
    echo "No USB drive mounted at \$MOUNT_POINT"
    exit 1
fi

if [ ! -d "\$KIWIX_PATH" ]; then
    echo "No kiwix folder found on USB drive"
    exit 1
fi

ZIM_FILES=\$(find "\$KIWIX_PATH" -maxdepth 1 -type f -name "*.zim" 2>/dev/null)

if [ -z "\$ZIM_FILES" ]; then
    echo "No .zim files found in \$KIWIX_PATH"
    exit 1
fi

FILE_COUNT=\$(echo "\$ZIM_FILES" | wc -l)
echo "Found \$FILE_COUNT .zim file(s), starting kiwix-serve..."

exec kiwix-serve --port="\$PORT" \$ZIM_FILES
EOF
    sudo chmod +x /opt/delling/scripts/start-kiwix.sh
    
    print_step "Creating Kiwix service..."
    cat << 'EOF' | sudo tee /etc/systemd/system/kiwix.service > /dev/null
[Unit]
Description=Kiwix Offline Knowledge Server
After=network.target local-fs.target

[Service]
Type=simple
ExecStart=/opt/delling/scripts/start-kiwix.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    print_step "Enabling always-on services..."
    sudo systemctl daemon-reload
    sudo systemctl enable tinymedia
    sudo systemctl enable kiwix
    
    print_step "Phase 4 complete!"
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 5: SDR FOUNDATION
# ═══════════════════════════════════════════════════════════════════════════

phase5_sdr_foundation() {
    print_header "Phase 5: SDR Foundation"
    
    print_step "Blacklisting default RTL driver..."
    echo 'blacklist dvb_usb_rtl28xxu' | sudo tee /etc/modprobe.d/blacklist-rtlsdr.conf
    
    print_step "Installing RTL-SDR tools..."
    sudo apt install -y rtl-sdr librtlsdr-dev
    
    print_step "Creating udev rules for non-root SDR access..."
    sudo tee /etc/udev/rules.d/20-rtlsdr.rules > /dev/null << 'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2832", MODE="0666"
EOF
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    
    print_step "Creating SDR stop script..."
    cat << 'EOF' | sudo tee /opt/delling/scripts/stop-all-sdr.sh > /dev/null
#!/bin/bash
sudo systemctl stop openwebrx dump1090-fa aiscatcher rtl-fm-radio welle-cli 2>/dev/null
sleep 1
EOF
    sudo chmod +x /opt/delling/scripts/stop-all-sdr.sh
    
    print_step "Phase 5 complete!"
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 6: SDR APPLICATIONS
# ═══════════════════════════════════════════════════════════════════════════

phase6_sdr_apps() {
    print_header "Phase 6: SDR Applications"
    
    # --- rtl_fm_python_webgui ---
    print_step "Installing FM/VHF Radio (rtl_fm_webgui)..."
    if [ -d /opt/rtl_fm_webgui ]; then
        print_info "rtl_fm_webgui exists, updating..."
        cd /opt/rtl_fm_webgui && sudo git pull
    else
        sudo git clone https://github.com/tronba/rtl_fm_python_webgui /opt/rtl_fm_webgui
        sudo chown -R $DELLING_USER:$DELLING_USER /opt/rtl_fm_webgui
    fi
    cd /opt/rtl_fm_webgui
    ./build.sh
    
    # Create service manually (don't run radio-control.sh install to avoid prompts)
    cat << EOF | sudo tee /etc/systemd/system/rtl-fm-radio.service > /dev/null
[Unit]
Description=RTL-SDR Web Radio
After=network.target

[Service]
Type=simple
User=$DELLING_USER
WorkingDirectory=/opt/rtl_fm_webgui
ExecStart=/usr/bin/python3 /opt/rtl_fm_webgui/rtl_fm_python_web.py -M wbfm -f 101.1M -
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    
    # --- welle-cli ---
    print_step "Installing DAB+ Radio (welle-cli)..."
    sudo apt install -y welle.io
    
    print_step "Installing custom welle-cli web UI..."
    if [ -d /tmp/welle-ui ]; then
        rm -rf /tmp/welle-ui
    fi
    git clone https://github.com/tronba/simple-webgui-welle-cli /tmp/welle-ui
    sudo cp /tmp/welle-ui/index.html /usr/share/welle-io/html/ 2>/dev/null || \
        sudo cp /tmp/welle-ui/index.html /usr/local/share/welle-io/html/
    sudo cp /tmp/welle-ui/player.js /usr/share/welle-io/html/ 2>/dev/null || \
        sudo cp /tmp/welle-ui/player.js /usr/local/share/welle-io/html/
    rm -rf /tmp/welle-ui
    
    print_step "Creating welle-cli service..."
    cat << 'EOF' | sudo tee /etc/systemd/system/welle-cli.service > /dev/null
[Unit]
Description=Welle-cli DAB+ Radio
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/welle-cli -c 12A -C 1 -w 7979
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    # --- OpenWebRX+ ---
    print_step "Installing OpenWebRX+..."
    curl -s https://luarvique.github.io/ppa/openwebrx-plus.gpg | \
        sudo gpg --yes --dearmor -o /etc/apt/trusted.gpg.d/openwebrx-plus.gpg
    
    # Detect Debian version
    DEBIAN_CODENAME=$(lsb_release -cs 2>/dev/null || echo "bookworm")
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/openwebrx-plus.gpg] https://luarvique.github.io/ppa/${DEBIAN_CODENAME} ./" | \
        sudo tee /etc/apt/sources.list.d/openwebrx-plus.list
    
    sudo apt update
    sudo apt install -y openwebrx
    
    print_step "Setting OpenWebRX admin password..."
    printf "%s\n%s\n" "$OPENWEBRX_PASS" "$OPENWEBRX_PASS" | sudo openwebrx admin adduser admin 2>/dev/null || \
        print_info "OpenWebRX admin may already exist"
    
    sudo systemctl disable openwebrx
    
    # --- dump1090-fa ---
    print_step "Installing ADS-B tracking (dump1090-fa)..."
    sudo bash -c "$(wget -q -O - https://raw.githubusercontent.com/abcd567a/piaware-ubuntu-debian-amd64/master/install-dump1090-fa.sh)" || \
        print_info "dump1090-fa install script may have failed, continuing..."
    sudo systemctl disable dump1090-fa 2>/dev/null || true
    
    # --- AIS-catcher ---
    print_step "Installing AIS ship tracking..."
    sudo bash -c "$(wget -q -O - https://raw.githubusercontent.com/abcd567a/install-aiscatcher/master/install-aiscatcher.sh)" || \
        print_info "AIS-catcher install script may have failed, continuing..."
    sudo systemctl disable aiscatcher 2>/dev/null || true
    # Fix config
    sudo sed -i 's/^-d [0-9]\+/#-d 0/' /usr/share/aiscatcher/aiscatcher.conf 2>/dev/null || true
    
    print_step "Reloading systemd..."
    sudo systemctl daemon-reload
    
    print_step "Phase 6 complete!"
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 7: FINALIZE
# ═══════════════════════════════════════════════════════════════════════════

phase7_finalize() {
    print_header "Phase 7: Finalize"
    
    print_step "Ensuring all auto-start services are enabled..."
    sudo systemctl enable delling-dashboard
    sudo systemctl enable kiwix
    sudo systemctl enable nftables
    
    print_step "Starting always-on services..."
    sudo systemctl start delling-dashboard
    # Kiwix and Tinymedia will start on boot after manual setup
    
    print_step "Phase 7 complete!"
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════

main() {
    check_root
    check_arch
    ask_questions
    
    phase1_base_system
    phase2_network
    phase3_dashboard
    phase4_always_on
    phase5_sdr_foundation
    phase6_sdr_apps
    phase7_finalize
    
    print_header "Installation Complete!"
    
    echo -e "${GREEN}Delling has been installed successfully!${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT - Tinymedia Setup Required:${NC}"
    echo "  Tinymedia has been downloaded but NOT installed."
    echo "  To complete Tinymedia installation:"
    echo "    1. Connect your USB drive with media files"
    echo "    2. Run: cd /opt/tinymedia"
    echo "    3. Run: bash install_arm_no_venv.sh"
    echo "    4. Follow the prompts to select your USB drive"
    echo ""
    echo "Next steps:"
    echo "  1. Reboot: sudo reboot"
    echo "  2. Connect to WiFi network '$WIFI_SSID'"
    echo "  3. Open any webpage to access the dashboard"
    echo ""
    echo "Direct access URLs (after connecting to Delling WiFi):"
    echo "  Dashboard:    http://192.168.4.1:1337"
    echo "  Media Server: http://192.168.4.1:5000 (after Tinymedia setup)"
    echo "  Kiwix:        http://192.168.4.1:8000"
    echo ""
    echo "Meshtastic setup (manual):"
    echo "  Configure Heltec V3 with:"
    echo "    WiFi SSID: $WIFI_SSID"
    echo "    Static IP: 192.168.4.10"
    echo "  Then access: http://192.168.4.10"
    echo ""
    read -p "Reboot now? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        sudo reboot
    fi
}

# Run main
main "$@"
