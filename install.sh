#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Delling Installation Script
# A portable emergency hub for Raspberry Pi / Orange Pi
# ═══════════════════════════════════════════════════════════════════════════
#
# This script installs and configures:
#   • WiFi Access Point with captive portal
#   • Delling Dashboard (service control panel)
#   • Multi-mode Radio (rtl_fm_python_webgui)
#   • DAB+ Radio (welle-cli + custom web UI)
#   • AIS Ship Tracking (AIS-catcher)
#   • Offline Maps (Leaflet + MBTiles tile server)
#   • Tinymedia (media server)
#   • Kiwix (offline Wikipedia)
#
# Usage:
#   git clone https://github.com/tronba/Delling ~/Delling
#   cd ~/Delling
#   chmod +x install.sh
#   ./install.sh
#
# ═══════════════════════════════════════════════════════════════════════════

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure /usr/sbin is in PATH (needed on some Armbian installs for rfkill, iw, etc.)
export PATH="/usr/sbin:/usr/local/sbin:$PATH"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track failures for end-of-install report
declare -a FAILURES=()

# Track which port-redirect method was configured (nftables or iptables)
REDIRECT_METHOD="nftables"

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

record_failure() {
    FAILURES+=("$1")
    print_error "$1"
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

check_dependencies() {
    local missing=()
    for cmd in nmcli iw rfkill; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        print_info "Missing commands: ${missing[*]}"
        print_info "These will be installed during Phase 1."
    fi
}

detect_network_stack() {
    if command -v nmcli &>/dev/null && systemctl is-active NetworkManager &>/dev/null; then
        echo "networkmanager"
    elif systemctl is-active systemd-networkd &>/dev/null; then
        echo "networkd"
    else
        echo "unknown"
    fi
}

detect_wifi_interface() {
    # Find the first wireless interface
    local iface
    iface=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | head -n1)
    if [ -z "$iface" ]; then
        # Fallback: check /sys/class/net for wireless devices
        for dev in /sys/class/net/*; do
            if [ -d "$dev/wireless" ] || [ -d "$dev/phy80211" ]; then
                iface=$(basename "$dev")
                break
            fi
        done
    fi
    if [ -z "$iface" ]; then
        iface="wlan0"  # Last resort default
    fi
    echo "$iface"
}

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION (Asked upfront)
# ═══════════════════════════════════════════════════════════════════════════

ask_questions() {
    print_header "Delling Installation"

    echo "Welcome to Delling – your emergency information hub!"
    echo ""
    echo "This script will install and configure:"
    echo "  • WiFi Access Point (captive portal)"
    echo "  • Delling Dashboard (service control panel)"
    echo "  • Multi-mode Radio, DAB+ Radio"
    echo "  • AIS Ship Tracking"
    echo "  • Offline Maps (Leaflet + AIS overlay)"
    echo "  • Tinymedia (media server)"
    echo "  • Kiwix (offline Wikipedia)"
    echo ""
    echo "Please answer a few questions before we begin."
    echo ""

    # Username
    DELLING_USER=$(whoami)

    # WiFi SSID
    read -p "WiFi network name [Delling]: " INPUT_SSID
    WIFI_SSID=${INPUT_SSID:-Delling}

    # WiFi Channel
    read -p "WiFi channel (1-11) [6]: " INPUT_CHANNEL
    WIFI_CHANNEL=${INPUT_CHANNEL:-6}

    # USB mount point (fixed to /media/usb)
    USB_MOUNT="/media/usb"

    # Confirm
    echo ""
    print_header "Configuration Summary"
    echo "  User:           $DELLING_USER"
    echo "  WiFi SSID:      $WIFI_SSID"
    echo "  WiFi Channel:   $WIFI_CHANNEL"
    echo "  USB Mount:      $USB_MOUNT"
    echo "  Install Dir:    $SCRIPT_DIR"
    echo ""
    echo "  Services to install:"
    echo "    Dashboard ........... port 8080"
    echo "    Multi-mode Radio .... port 10100"
    echo "    DAB+ Radio .......... port 7979"
    echo "    Tinymedia ........... port 5000"
    echo "    Kiwix ............... port 8000"
    echo "    AIS Ship Tracking ... port 8100"
    echo "    Offline Maps ........ port 8082"
    echo ""

    read -p "Proceed with installation? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi

    # Early warning about USB drive requirement
    echo ""
    print_info "NOTE: Tinymedia requires a USB drive (exFAT) to be connected."
    print_info "If no USB drive is present, Tinymedia install will be skipped."
    print_info "You can run it manually later."
    echo ""
    read -p "Press Enter to continue..." -r
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

    # --- Core dependencies (must succeed) ---
    print_step "Installing core dependencies..."
    sudo apt install -y \
        git \
        python3 \
        python3-pip \
        python3-flask \
        curl \
        wget \
        ffmpeg \
        gcc \
        build-essential \
        libusb-1.0-0-dev \
        rtl-sdr \
        librtlsdr-dev \
        libsqlite3-dev \
        sqlite3 \
        network-manager \
        dnsmasq \
        nftables \
        iw \
        wireless-tools \
        exfatprogs

    # --- Optional packages (may not be in all repos) ---
    print_step "Installing optional packages..."
    for pkg in kiwix-tools welle.io; do
        if sudo apt install -y "$pkg" 2>/dev/null; then
            print_step "Installed $pkg"
        else
            record_failure "Package '$pkg' not available in repos (may need manual install)"
        fi
    done

    # --- Ensure user can access USB SDR devices ---
    if ! groups "$DELLING_USER" | grep -q plugdev; then
        print_step "Adding $DELLING_USER to plugdev group (SDR access)..."
        sudo usermod -aG plugdev "$DELLING_USER"
    fi

    print_step "Phase 1 complete!"
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 2: NETWORK
# ═══════════════════════════════════════════════════════════════════════════

phase2_network() {
    print_header "Phase 2: Network Configuration"

    # --- Detect WiFi interface ---
    WIFI_IFACE=$(detect_wifi_interface)
    print_info "Detected WiFi interface: $WIFI_IFACE"

    # --- Detect networking stack and prepare NetworkManager ---
    local net_stack
    net_stack=$(detect_network_stack)
    print_info "Detected networking stack: $net_stack"

    if [ "$net_stack" = "networkd" ]; then
        print_info "System uses systemd-networkd (typical for Armbian/Orange Pi)"
        print_step "Configuring NetworkManager to coexist with systemd-networkd..."

        # Tell systemd-networkd to leave WiFi interface alone
        sudo tee /etc/systemd/network/10-ignore-wlan.network > /dev/null << NETEOF
[Match]
Name=$WIFI_IFACE

[Link]
Unmanaged=yes
NETEOF
        sudo systemctl restart systemd-networkd

        # Enable and start NetworkManager
        sudo systemctl enable NetworkManager
        sudo systemctl start NetworkManager
        sleep 3
    fi

    # Verify nmcli is available
    if ! command -v nmcli &>/dev/null; then
        record_failure "Network: nmcli not found. NetworkManager installation may have failed."
        return 1
    fi

    # Ensure NetworkManager is running
    if ! systemctl is-active NetworkManager &>/dev/null; then
        print_step "Starting NetworkManager..."
        sudo systemctl enable NetworkManager
        sudo systemctl start NetworkManager
        sleep 3
    fi

    # --- Disable standalone dnsmasq (NM's shared mode runs its own) ---
    print_step "Disabling standalone dnsmasq (NetworkManager handles DHCP/DNS)..."
    sudo systemctl disable --now dnsmasq 2>/dev/null || true

    # --- Disable WiFi power saving for stability (especially Unisoc chips) ---
    if command -v iw &>/dev/null; then
        sudo iw dev "$WIFI_IFACE" set power_save off 2>/dev/null || true
    fi

    # --- WiFi Access Point ---
    if nmcli con show DellingAP &>/dev/null; then
        print_info "WiFi AP 'DellingAP' already exists, removing..."
        sudo nmcli con delete DellingAP
    fi

    print_step "Creating WiFi Access Point '$WIFI_SSID' on $WIFI_IFACE..."
    sudo nmcli con add type wifi ifname "$WIFI_IFACE" mode ap con-name DellingAP ssid "$WIFI_SSID" \
        wifi.band bg \
        wifi.channel "$WIFI_CHANNEL" \
        ipv4.method shared \
        ipv4.addresses 192.168.4.1/24 \
        ipv6.method disabled

    print_step "Enabling WiFi AP..."
    sudo nmcli con up DellingAP
    sudo nmcli con modify DellingAP connection.autoconnect yes

    # --- Verify AP is actually running ---
    sleep 5
    if nmcli -t -f GENERAL.STATE con show DellingAP 2>/dev/null | grep -q activated; then
        print_step "WiFi AP is active and broadcasting '$WIFI_SSID'"
    else
        record_failure "Network: WiFi AP 'DellingAP' failed to activate"
        print_info "Debug: sudo nmcli con up DellingAP"
        print_info "Logs:  sudo journalctl -u NetworkManager -n 50"
    fi

    # --- Captive Portal: DNS redirect ---
    print_step "Configuring DNS redirect (all domains → 192.168.4.1)..."
    sudo mkdir -p /etc/NetworkManager/dnsmasq-shared.d
    echo 'address=/#/192.168.4.1' | sudo tee /etc/NetworkManager/dnsmasq-shared.d/captive.conf > /dev/null

    # --- Captive Portal: HTTP redirect (port 80 → 8080 dashboard) ---
    print_step "Configuring HTTP redirect (port 80 → 8080)..."

    # Try loading nftables kernel modules (needed on some ARM SBCs)
    for mod in nf_tables nft_chain_nat nft_compat; do
        sudo modprobe "$mod" 2>/dev/null || true
    done

    # Attempt nftables first, fall back to iptables if kernel lacks support
    NFT_OK=false
    if sudo nft add table ip captive 2>/dev/null; then
        sudo nft flush table ip captive 2>/dev/null || true
        if sudo nft add chain ip captive prerouting '{ type nat hook prerouting priority -100 ; }' 2>/dev/null && \
           sudo nft add rule ip captive prerouting iifname "$WIFI_IFACE" tcp dport 80 redirect to :8080 2>/dev/null; then
            NFT_OK=true
            print_info "Using nftables for port redirect"
            sudo nft list ruleset | sudo tee /etc/nftables.conf > /dev/null
            sudo systemctl enable nftables
            REDIRECT_METHOD="nftables"
        else
            print_info "nftables commands failed, cleaning up..."
            sudo nft delete table ip captive 2>/dev/null || true
        fi
    fi

    if [ "$NFT_OK" = false ]; then
        print_info "nftables not available, falling back to iptables"
        sudo apt install -y iptables 2>/dev/null || true
        # Remove any stale nftables rules
        sudo nft delete table ip captive 2>/dev/null || true
        # Flush old iptables redirect rules
        sudo iptables -t nat -D PREROUTING -i "$WIFI_IFACE" -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null || true
        # Add iptables redirect
        sudo iptables -t nat -A PREROUTING -i "$WIFI_IFACE" -p tcp --dport 80 -j REDIRECT --to-port 8080
        # Persist iptables rules across reboots
        sudo sh -c 'iptables-save > /etc/iptables.rules'
        # Create systemd service to restore rules on boot
        cat <<'IPTEOF' | sudo tee /etc/systemd/system/iptables-restore.service > /dev/null
[Unit]
Description=Restore iptables rules
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'iptables-restore < /etc/iptables.rules'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
IPTEOF
        sudo systemctl daemon-reload
        sudo systemctl enable iptables-restore
        REDIRECT_METHOD="iptables"
    fi

    # Verify the redirect is active
    print_step "Verifying port 80 → 8080 redirect..."
    if [ "$REDIRECT_METHOD" = "nftables" ]; then
        if sudo nft list table ip captive 2>/dev/null | grep -q 'redirect to :8080'; then
            print_step "nftables redirect verified!"
        else
            record_failure "Network: nftables redirect rule not active"
        fi
    else
        if sudo iptables -t nat -L PREROUTING -n 2>/dev/null | grep -q 'redir ports 8080'; then
            print_step "iptables redirect verified!"
        else
            record_failure "Network: iptables redirect rule not active"
        fi
    fi

    # --- Disable IP forwarding (no internet sharing) ---
    print_step "Disabling IP forwarding..."
    echo 'net.ipv4.ip_forward = 0' | sudo tee /etc/sysctl.d/99-no-forward.conf > /dev/null
    sudo sysctl -p /etc/sysctl.d/99-no-forward.conf 2>/dev/null || true

    # --- Restart NetworkManager to apply DNS config ---
    print_step "Restarting NetworkManager..."
    sudo systemctl restart NetworkManager

    print_step "Phase 2 complete!"
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 3: DASHBOARD
# ═══════════════════════════════════════════════════════════════════════════

phase3_dashboard() {
    print_header "Phase 3: Delling Dashboard"

    # --- Sudoers: allow dashboard user to start/stop services without password ---
    print_step "Configuring sudoers for service control..."
    sudo tee /etc/sudoers.d/delling > /dev/null << EOF
# Delling Dashboard - allow service control without password
$DELLING_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl start rtl-fm-radio, /usr/bin/systemctl stop rtl-fm-radio
$DELLING_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl start welle-cli, /usr/bin/systemctl stop welle-cli
$DELLING_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl start aiscatcher, /usr/bin/systemctl stop aiscatcher
$DELLING_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl start tinymedia, /usr/bin/systemctl stop tinymedia
$DELLING_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl start kiwix, /usr/bin/systemctl stop kiwix
$DELLING_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl start delling-maps, /usr/bin/systemctl stop delling-maps
$DELLING_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl start delling-dashboard, /usr/bin/systemctl stop delling-dashboard
EOF
    sudo chmod 0440 /etc/sudoers.d/delling
    # Validate the sudoers file (remove if invalid to avoid lockout)
    if ! sudo visudo -cf /etc/sudoers.d/delling; then
        record_failure "Sudoers: /etc/sudoers.d/delling has syntax errors, removing"
        sudo rm -f /etc/sudoers.d/delling
    fi

    print_step "Creating dashboard service..."
    sudo tee /etc/systemd/system/delling-dashboard.service > /dev/null << EOF
[Unit]
Description=Delling Dashboard
After=network.target

[Service]
Type=simple
User=$DELLING_USER
WorkingDirectory=$SCRIPT_DIR/dashboard
ExecStart=/usr/bin/python3 $SCRIPT_DIR/dashboard/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    print_step "Enabling dashboard service..."
    sudo systemctl daemon-reload
    sudo systemctl enable delling-dashboard

    print_step "Phase 3 complete!"
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 4: ALWAYS-ON SERVICES (Tinymedia + Kiwix + Maps)
# ═══════════════════════════════════════════════════════════════════════════

phase4_always_on() {
    print_header "Phase 4: Always-On Services"

    # ─── Tinymedia ───
    print_step "Cloning Tinymedia..."
    if [ -d "$SCRIPT_DIR/Tinymedia" ]; then
        print_info "Tinymedia directory exists, updating..."
        pushd "$SCRIPT_DIR/Tinymedia" > /dev/null && git pull && popd > /dev/null
    else
        git clone https://github.com/tronba/Tinymedia "$SCRIPT_DIR/Tinymedia"
    fi

    print_step "Running Tinymedia installer (AUTO_YES=1)..."
    print_info "This requires a USB drive to be connected."
    pushd "$SCRIPT_DIR/Tinymedia" > /dev/null
    if AUTO_YES=1 bash install_arm_no_venv.sh; then
        print_step "Tinymedia installed successfully!"
    else
        record_failure "Tinymedia: Auto-install failed (USB drive may be missing)"
        print_info "You can run it manually later:"
        print_info "  cd $SCRIPT_DIR/Tinymedia && bash install_arm_no_venv.sh"
    fi
    popd > /dev/null

    # ─── Kiwix ───
    print_step "Creating Kiwix startup script..."
    sudo mkdir -p /opt/delling/scripts
    sudo chown -R "$DELLING_USER:$DELLING_USER" /opt/delling

    cat > /opt/delling/scripts/start-kiwix.sh << 'KIWIXEOF'
#!/bin/bash
PORT=8000

# Try both common USB mount points
MOUNT_POINT=""
for candidate in "/media/usb" "/media/$USER/usb"; do
    if mountpoint -q "$candidate" 2>/dev/null || [ -d "$candidate" ]; then
        MOUNT_POINT="$candidate"
        break
    fi
done

if [ -z "$MOUNT_POINT" ]; then
    echo "No USB drive mounted at /media/usb or /media/$USER/usb"
    exit 1
fi

# Find kiwix folder (case-insensitive)
KIWIX_PATH=$(find "$MOUNT_POINT" -maxdepth 1 -type d -iname "kiwix" 2>/dev/null | head -n 1)

if [ -z "$KIWIX_PATH" ] || [ ! -d "$KIWIX_PATH" ]; then
    echo "No kiwix folder found on USB drive (tried: kiwix, Kiwix, KIWIX)"
    exit 1
fi

ZIM_FILES=$(find "$KIWIX_PATH" -maxdepth 1 -type f -name "*.zim" 2>/dev/null)

if [ -z "$ZIM_FILES" ]; then
    echo "No .zim files found in $KIWIX_PATH"
    exit 1
fi

FILE_COUNT=$(echo "$ZIM_FILES" | wc -l)
echo "Found $FILE_COUNT .zim file(s), starting kiwix-serve..."

exec kiwix-serve --port="$PORT" $ZIM_FILES
KIWIXEOF
    chmod +x /opt/delling/scripts/start-kiwix.sh

    print_step "Creating Kiwix service..."
    sudo tee /etc/systemd/system/kiwix.service > /dev/null << EOF
[Unit]
Description=Kiwix Offline Knowledge Server
After=network.target local-fs.target

[Service]
Type=simple
User=$DELLING_USER
ExecStart=/opt/delling/scripts/start-kiwix.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable kiwix

    # ─── Offline Maps (Leaflet + MBTiles tile server) ───
    print_step "Setting up offline map viewer..."

    # Download Leaflet for offline use
    LEAFLET_VERSION="1.9.4"
    mkdir -p "$SCRIPT_DIR/ais-map/static/leaflet/images"

    print_step "Downloading Leaflet ${LEAFLET_VERSION} for offline use..."
    if wget -q -O "$SCRIPT_DIR/ais-map/static/leaflet/leaflet.js" \
        "https://unpkg.com/leaflet@${LEAFLET_VERSION}/dist/leaflet.js" && \
       wget -q -O "$SCRIPT_DIR/ais-map/static/leaflet/leaflet.css" \
        "https://unpkg.com/leaflet@${LEAFLET_VERSION}/dist/leaflet.css"; then
        # Leaflet marker images
        for img in marker-icon.png marker-icon-2x.png marker-shadow.png; do
            wget -q -O "$SCRIPT_DIR/ais-map/static/leaflet/images/$img" \
                "https://unpkg.com/leaflet@${LEAFLET_VERSION}/dist/images/$img"
        done
        print_step "Leaflet downloaded successfully!"
    else
        record_failure "Maps: Failed to download Leaflet (no internet?)"
    fi

    print_step "Creating map viewer service..."
    sudo tee /etc/systemd/system/delling-maps.service > /dev/null << EOF
[Unit]
Description=Delling Maps (Offline Map Viewer + Tile Server)
After=network.target local-fs.target

[Service]
Type=simple
User=$DELLING_USER
WorkingDirectory=$SCRIPT_DIR/ais-map
ExecStart=/usr/bin/python3 $SCRIPT_DIR/ais-map/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable delling-maps

    print_step "Phase 4 complete!"
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 5: SDR FOUNDATION
# ═══════════════════════════════════════════════════════════════════════════

phase5_sdr_foundation() {
    print_header "Phase 5: SDR Foundation"

    print_step "Blacklisting default RTL-SDR driver..."
    echo 'blacklist dvb_usb_rtl28xxu' | sudo tee /etc/modprobe.d/blacklist-rtlsdr.conf > /dev/null

    print_step "Creating udev rules for non-root SDR access..."
    sudo tee /etc/udev/rules.d/20-rtlsdr.rules > /dev/null << 'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2832", MODE="0666"
EOF
    sudo udevadm control --reload-rules
    sudo udevadm trigger

    print_step "Creating SDR stop-all script..."
    cat > /opt/delling/scripts/stop-all-sdr.sh << 'EOF'
#!/bin/bash
sudo systemctl stop rtl-fm-radio welle-cli aiscatcher 2>/dev/null
sleep 1
EOF
    chmod +x /opt/delling/scripts/stop-all-sdr.sh

    print_step "Phase 5 complete!"
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 6: SDR APPLICATIONS
# ═══════════════════════════════════════════════════════════════════════════

phase6_sdr_apps() {
    print_header "Phase 6: SDR Applications"

    # ─── rtl_fm_python_webgui (Multi-mode Radio) ───
    print_step "Cloning Multi-mode Radio (rtl_fm_python_webgui)..."
    if [ -d "$SCRIPT_DIR/rtl_fm_webgui" ]; then
        print_info "rtl_fm_webgui directory exists, updating..."
        pushd "$SCRIPT_DIR/rtl_fm_webgui" > /dev/null && git pull && popd > /dev/null
    else
        git clone https://github.com/tronba/rtl_fm_python_webgui "$SCRIPT_DIR/rtl_fm_webgui"
    fi

    print_step "Building rtl_fm C library..."
    pushd "$SCRIPT_DIR/rtl_fm_webgui" > /dev/null
    if bash build.sh; then
        print_step "Build successful!"
    else
        record_failure "Multi-mode Radio: build.sh failed (missing dependencies?)"
        print_info "You can try manually: cd $SCRIPT_DIR/rtl_fm_webgui && ./build.sh"
    fi

    # Create the service file (README says: "Edit rtl-fm-radio.service to match your setup")
    print_step "Creating rtl-fm-radio service file..."
    cat > "$SCRIPT_DIR/rtl_fm_webgui/rtl-fm-radio.service" << EOF
[Unit]
Description=RTL-SDR Web Radio
After=network.target

[Service]
Type=simple
User=$DELLING_USER
WorkingDirectory=$SCRIPT_DIR/rtl_fm_webgui
ExecStart=/usr/bin/python3 $SCRIPT_DIR/rtl_fm_webgui/rtl_fm_python_web.py -M wbfm -f 101.1M -
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Use the upstream install mechanism
    print_step "Installing Multi-mode Radio service (radio-control.sh install)..."
    chmod +x radio-control.sh
    bash radio-control.sh install
    sudo systemctl disable rtl-fm-radio 2>/dev/null || true
    popd > /dev/null

    # ─── welle-cli (DAB+ Radio) ───
    # welle.io was already installed in Phase 1 via apt
    print_step "Cloning custom welle-cli web UI..."
    if [ -d "$SCRIPT_DIR/simple-webgui-welle-cli" ]; then
        print_info "welle-cli web UI directory exists, updating..."
        pushd "$SCRIPT_DIR/simple-webgui-welle-cli" > /dev/null && git pull && popd > /dev/null
    else
        git clone https://github.com/tronba/simple-webgui-welle-cli "$SCRIPT_DIR/simple-webgui-welle-cli"
    fi

    print_step "Installing custom welle-cli web UI..."
    # Try the standard path first, then the alternate
    if [ -d /usr/share/welle-io/html ]; then
        WELLE_HTML="/usr/share/welle-io/html"
    elif [ -d /usr/local/share/welle-io/html ]; then
        WELLE_HTML="/usr/local/share/welle-io/html"
    else
        # Create it if neither exists (some installs put it elsewhere)
        WELLE_HTML="/usr/share/welle-io/html"
        sudo mkdir -p "$WELLE_HTML"
    fi
    sudo cp "$SCRIPT_DIR/simple-webgui-welle-cli/index.html" "$WELLE_HTML/"
    sudo cp "$SCRIPT_DIR/simple-webgui-welle-cli/player.js" "$WELLE_HTML/"
    print_step "Web UI installed to $WELLE_HTML"

    print_step "Creating welle-cli service..."
    sudo tee /etc/systemd/system/welle-cli.service > /dev/null << 'EOF'
[Unit]
Description=Welle-cli DAB+ Radio
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/welle-cli -c 12A -C 1 -w 7979
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    # Don't enable — started on demand via dashboard

    # ─── AIS-catcher (Ship Tracking) ───
    print_step "Installing AIS-catcher (ship tracking)..."
    print_info "Running upstream install script from GitHub..."
    if sudo bash -c "$(wget -q -O - https://raw.githubusercontent.com/abcd567a/install-aiscatcher/master/install-aiscatcher.sh)"; then
        print_step "AIS-catcher installed!"
    else
        record_failure "AIS-catcher: Upstream install script failed"
    fi
    sudo systemctl disable aiscatcher 2>/dev/null || true

    # ─── AIS-catcher Offline Web Assets ───
    print_step "Cloning AIS-catcher web assets for offline use..."
    if [ -d /opt/delling/webassets ]; then
        print_info "webassets directory exists, updating..."
        pushd /opt/delling/webassets > /dev/null && git pull && popd > /dev/null
    else
        git clone https://github.com/jvde-github/webassets.git /opt/delling/webassets
    fi

    # ─── AIS-catcher Startup Script (offline CDN + MBTiles) ───
    print_step "Creating AIS-catcher startup script with offline map support..."
    cat > /opt/delling/scripts/start-aiscatcher.sh << 'AISCATCHEREOF'
#!/bin/bash
# Start AIS-catcher with offline web assets and MBTiles map tiles

CDN_PATH="/opt/delling/webassets"
CONF_FILE="/usr/share/aiscatcher/aiscatcher.conf"

# Build command as array for proper argument handling
CMD=("/usr/local/bin/AIS-catcher")

# Extract SDR/radio settings from upstream config file
# Strip comments (#), blank lines, and network/server config (we provide our own)
# This avoids using -C which tries to parse the file as JSON and chokes on # comments
if [ -f "$CONF_FILE" ]; then
    SDR_ARGS=$(sed 's/#.*//; /^\s*$/d; /^\s*-N/d; /^\s*-S/d; /^\s*LAT/d; /^\s*-u/d; /^\s*-P/d' "$CONF_FILE" | tr '\n' ' ')
    if [ -n "$SDR_ARGS" ]; then
        read -ra EXTRA_ARGS <<< "$SDR_ARGS"
        CMD+=("${EXTRA_ARGS[@]}")
        echo "SDR settings from config: $SDR_ARGS"
    fi
fi

# Add web server with offline CDN if available
CMD+=("-N" "8100")
if [ -d "$CDN_PATH" ]; then
    CMD+=("CDN" "$CDN_PATH")
fi

# Try both common USB mount points
MOUNT_POINT=""
for candidate in "/media/usb" "/media/$USER/usb"; do
    if mountpoint -q "$candidate" 2>/dev/null || [ -d "$candidate" ]; then
        MOUNT_POINT="$candidate"
        break
    fi
done

# Find maps folder and first .mbtiles file
if [ -n "$MOUNT_POINT" ]; then
    MAPS_DIR=$(find "$MOUNT_POINT" -maxdepth 1 -type d -iname "maps" 2>/dev/null | head -n 1)
    if [ -n "$MAPS_DIR" ]; then
        MBTILES_FILE=$(find "$MAPS_DIR" -maxdepth 1 -type f -name "*.mbtiles" 2>/dev/null | head -n 1)
        if [ -n "$MBTILES_FILE" ]; then
            echo "Using offline map: $MBTILES_FILE"
            CMD+=("MBTILES" "$MBTILES_FILE")
        fi
    fi
fi

echo "Starting: ${CMD[*]}"
exec "${CMD[@]}"
AISCATCHEREOF
    chmod +x /opt/delling/scripts/start-aiscatcher.sh

    print_step "Creating AIS-catcher service override..."
    sudo tee /etc/systemd/system/aiscatcher.service > /dev/null << EOF
[Unit]
Description=AIS-catcher Ship Tracking (Offline)
After=network.target local-fs.target

[Service]
Type=simple
User=$DELLING_USER
ExecStart=/opt/delling/scripts/start-aiscatcher.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload

    print_step "Phase 6 complete!"
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 7: FINALIZE
# ═══════════════════════════════════════════════════════════════════════════

phase7_finalize() {
    print_header "Phase 7: Finalize"

    print_step "Reloading systemd..."
    sudo systemctl daemon-reload

    print_step "Enabling auto-start services..."
    sudo systemctl enable delling-dashboard
    sudo systemctl enable kiwix
    sudo systemctl enable delling-maps
    # Enable whichever redirect method was configured in phase 2
    if [ "$REDIRECT_METHOD" = "iptables" ]; then
        sudo systemctl enable iptables-restore
    else
        sudo systemctl enable nftables
    fi
    # tinymedia is enabled by its own installer (if it ran successfully)

    print_step "Starting dashboard..."
    sudo systemctl start delling-dashboard

    print_step "Starting map server..."
    sudo systemctl start delling-maps

    print_step "Phase 7 complete!"
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════

main() {
    check_root
    check_arch
    check_dependencies
    ask_questions

    phase1_base_system
    phase2_network
    phase3_dashboard
    phase4_always_on
    phase5_sdr_foundation
    phase6_sdr_apps
    phase7_finalize

    print_header "Installation Complete!"

    # Report any failures
    if [ ${#FAILURES[@]} -gt 0 ]; then
        echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  ISSUES DETECTED (${#FAILURES[@]})                                           ${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        for failure in "${FAILURES[@]}"; do
            echo -e "  ${RED}•${NC} $failure"
        done
        echo ""
        echo -e "${YELLOW}Review the issues above. Some services may need manual setup.${NC}"
        echo ""
    fi

    echo -e "${GREEN}Delling has been installed successfully!${NC}"
    echo ""
    echo "Services installed:"
    echo "  ✓ Dashboard ............ port 8080  (auto-start)"
    echo "  ✓ Tinymedia ............ port 5000  (auto-start)"
    echo "  ✓ Kiwix ................ port 8000  (auto-start, needs USB)"
    echo "  ✓ Maps ................. port 8082  (auto-start, needs USB)"
    echo "  ✓ Multi-mode Radio ..... port 10100 (on-demand via dashboard)"
    echo "  ✓ DAB+ Radio ........... port 7979  (on-demand via dashboard)"
    echo "  ✓ AIS Ship Tracking .... port 8100  (on-demand via dashboard)"
    echo ""
    echo "  Map viewer shows AIS ships automatically when AIS is running."
    echo ""
    if ! systemctl is-active tinymedia &>/dev/null; then
        echo -e "${YELLOW}NOTE: Tinymedia may need manual setup:${NC}"
        echo "  1. Connect your USB drive (exFAT formatted)"
        echo "  2. Run: cd $SCRIPT_DIR/Tinymedia && bash install_arm_no_venv.sh"
        echo ""
    fi
    echo "Meshtastic setup (manual - external device):"
    echo "  Configure Heltec V3 with:"
    echo "    WiFi SSID: $WIFI_SSID"
    echo "    Static IP: 192.168.4.10"
    echo "  Then access: http://192.168.4.10"
    echo ""
    echo "Next steps:"
    echo "  1. Reboot: sudo reboot"
    echo "  2. Connect to WiFi network '$WIFI_SSID'"
    echo "  3. Open any webpage → dashboard at http://192.168.4.1:8080"
    echo ""
    read -p "Reboot now? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        sudo reboot
    fi
}

# Run
main "$@"
