# Delling Installation Order

This document defines the installation sequence and dependencies.

---

## Dependency Graph

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              PHASE 1: Base System                            │
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                   │
│  │ Update apt   │    │ Create dirs  │    │ Install deps │                   │
│  │ & upgrade    │───▶│ /opt/delling │───▶│ git, python  │                   │
│  └──────────────┘    └──────────────┘    └──────────────┘                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              PHASE 2: Network                                │
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                   │
│  │  WiFi AP     │───▶│  dnsmasq     │───▶│  nftables    │                   │
│  │  (nmcli)     │    │  DNS redirect│    │  HTTP redir  │                   │
│  └──────────────┘    └──────────────┘    └──────────────┘                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              PHASE 3: Dashboard                              │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                         OliveTin                                      │   │
│  │                    (download + config)                                │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PHASE 4: Always-On Services                        │
│                                                                              │
│  ┌──────────────────────┐         ┌──────────────────────┐                  │
│  │      Tinymedia       │         │        Kiwix         │                  │
│  │   (git + install)    │         │  (apt + service)     │                  │
│  └──────────────────────┘         └──────────────────────┘                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PHASE 5: SDR Foundation                            │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    RTL-SDR Base Setup                                 │   │
│  │              (blacklist driver, apt install, udev rules)              │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PHASE 6: SDR Applications                          │
│                          (order doesn't matter)                              │
│                                                                              │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │rtl_fm_web  │  │ welle-cli  │  │ OpenWebRX+ │  │ dump1090   │            │
│  └────────────┘  └────────────┘  └────────────┘  └────────────┘            │
│                                                                              │
│  ┌────────────┐                                                             │
│  │AIS-catcher │                                                             │
│  └────────────┘                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PHASE 7: Finalize                                  │
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                   │
│  │ Disable IP   │    │ Enable auto- │    │   Reboot     │                   │
│  │ forwarding   │    │ start svcs   │    │   & test     │                   │
│  └──────────────┘    └──────────────┘    └──────────────┘                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Detailed Steps

### Phase 1: Base System

```bash
# 1.1 Update system
sudo apt update && sudo apt upgrade -y

# 1.2 Create Delling directories
sudo mkdir -p /opt/delling/scripts
sudo chown -R $USER:$USER /opt/delling

# 1.3 Install common dependencies
sudo apt install -y \
    git \
    python3 \
    python3-pip \
    python3-flask \
    curl \
    wget
```

### Phase 2: Network

```bash
# 2.1 WiFi Access Point
sudo nmcli con add type wifi ifname wlan0 mode ap con-name DellingAP ssid "Delling" \
    wifi.band bg \
    wifi.channel 6 \
    ipv4.method shared \
    ipv4.addresses 192.168.4.1/24 \
    ipv6.method disabled
sudo nmcli con up DellingAP
sudo nmcli con modify DellingAP connection.autoconnect yes

# 2.2 DNS redirect (captive portal)
sudo apt install -y dnsmasq
echo 'address=/#/192.168.4.1' | sudo tee /etc/NetworkManager/dnsmasq-shared.d/captive.conf
sudo systemctl restart NetworkManager

# 2.3 HTTP redirect to dashboard
sudo apt install -y nftables
sudo nft add table ip captive
sudo nft add chain ip captive prerouting { type nat hook prerouting priority -100 \; }
sudo nft add rule ip captive prerouting iifname "wlan0" tcp dport 80 redirect to :1337
sudo nft list ruleset | sudo tee /etc/nftables.conf
sudo systemctl enable nftables

# 2.4 Disable IP forwarding
echo 'net.ipv4.ip_forward = 0' | sudo tee /etc/sysctl.d/99-no-forward.conf
sudo sysctl -p /etc/sysctl.d/99-no-forward.conf
```

### Phase 3: Dashboard (OliveTin)

```bash
# 3.1 Download and install OliveTin
ARCH=$(dpkg --print-architecture)
wget -O /tmp/OliveTin.deb \
    "https://github.com/OliveTin/OliveTin/releases/latest/download/OliveTin_linux_${ARCH}.deb"
sudo dpkg -i /tmp/OliveTin.deb

# 3.2 Copy config (created separately)
sudo cp /opt/delling/config/olivetin-config.yaml /etc/OliveTin/config.yaml

# 3.3 Enable and start
sudo systemctl enable --now OliveTin
```

### Phase 4: Always-On Services

```bash
# 4.1 Tinymedia
git clone https://github.com/tronba/Tinymedia /opt/tinymedia
cd /opt/tinymedia
./install_arm_no_venv.sh
# (Script creates service and enables it)

# 4.2 Kiwix
sudo apt install -y kiwix-tools

# Create startup script
cat << 'EOF' | sudo tee /opt/delling/scripts/start-kiwix.sh
#!/bin/bash
MOUNT_POINT="/media/usb"
KIWIX_FOLDER="kiwix"
PORT=8000
KIWIX_PATH="$MOUNT_POINT/$KIWIX_FOLDER"

if ! mountpoint -q "$MOUNT_POINT"; then
    echo "No USB drive mounted at $MOUNT_POINT"
    exit 1
fi

if [ ! -d "$KIWIX_PATH" ]; then
    echo "No kiwix folder found on USB drive"
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
EOF
sudo chmod +x /opt/delling/scripts/start-kiwix.sh

# Create systemd service
cat << 'EOF' | sudo tee /etc/systemd/system/kiwix.service
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

sudo systemctl daemon-reload
sudo systemctl enable kiwix
```

### Phase 5: SDR Foundation

```bash
# 5.1 Blacklist default RTL driver
echo 'blacklist dvb_usb_rtl28xxu' | sudo tee /etc/modprobe.d/blacklist-rtlsdr.conf

# 5.2 Install RTL-SDR tools
sudo apt install -y rtl-sdr librtlsdr-dev

# 5.3 udev rules for non-root access
sudo tee /etc/udev/rules.d/20-rtlsdr.rules << 'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2832", MODE="0666"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### Phase 6: SDR Applications

```bash
# 6.1 rtl_fm_python_webgui (FM/VHF Radio)
sudo apt install -y ffmpeg gcc
git clone https://github.com/tronba/rtl_fm_python_webgui /opt/rtl_fm_webgui
cd /opt/rtl_fm_webgui
./build.sh
./radio-control.sh install
sudo systemctl disable rtl-fm-radio

# 6.2 welle-cli (DAB+ Radio)
sudo apt install -y welle.io
git clone https://github.com/tronba/simple-webgui-welle-cli /tmp/welle-ui
sudo cp /tmp/welle-ui/index.html /usr/share/welle-io/html/
sudo cp /tmp/welle-ui/player.js /usr/share/welle-io/html/

cat << 'EOF' | sudo tee /etc/systemd/system/welle-cli.service
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
sudo systemctl daemon-reload
# Don't enable - started via OliveTin

# 6.3 OpenWebRX+
curl -s https://luarvique.github.io/ppa/openwebrx-plus.gpg | \
    sudo gpg --yes --dearmor -o /etc/apt/trusted.gpg.d/openwebrx-plus.gpg
echo "deb [signed-by=/etc/apt/trusted.gpg.d/openwebrx-plus.gpg] https://luarvique.github.io/ppa/bookworm ./" | \
    sudo tee /etc/apt/sources.list.d/openwebrx-plus.list
sudo apt update
sudo apt install -y openwebrx
echo "Set OpenWebRX admin password:"
sudo openwebrx admin adduser admin
sudo systemctl disable openwebrx

# 6.4 dump1090-fa (ADS-B)
sudo bash -c "$(wget -O - https://raw.githubusercontent.com/abcd567a/piaware-ubuntu-debian-amd64/master/install-dump1090-fa.sh)"
sudo systemctl disable dump1090-fa

# 6.5 AIS-catcher (Ship tracking)
sudo bash -c "$(wget -O - https://raw.githubusercontent.com/abcd567a/install-aiscatcher/master/install-aiscatcher.sh)"
sudo systemctl disable aiscatcher
sudo sed -i 's/^-d [0-9]\+/#-d 0/' /usr/share/aiscatcher/aiscatcher.conf
```

### Phase 7: Finalize

```bash
# 7.1 Create SDR stop script
cat << 'EOF' | sudo tee /opt/delling/scripts/stop-all-sdr.sh
#!/bin/bash
sudo systemctl stop openwebrx dump1090-fa aiscatcher rtl-fm-radio welle-cli 2>/dev/null
sleep 1
EOF
sudo chmod +x /opt/delling/scripts/stop-all-sdr.sh

# 7.2 Verify auto-start services
sudo systemctl enable OliveTin
sudo systemctl enable tinymedia
sudo systemctl enable kiwix
sudo systemctl enable nftables

# 7.3 Reboot
echo "Installation complete! Rebooting..."
sudo reboot
```

---

## Post-Install Checklist

After reboot, verify:

1. [ ] Connect to "Delling" WiFi (no password)
2. [ ] Open any webpage → redirects to OliveTin dashboard
3. [ ] Tinymedia accessible at `http://192.168.4.1:5000`
4. [ ] Kiwix accessible at `http://192.168.4.1:8000` (if USB with ZIM files connected)
5. [ ] Test one SDR app via dashboard
6. [ ] Configure Heltec V3 with static IP `192.168.4.10`
7. [ ] Verify Meshtastic at `http://192.168.4.10`

---

## Optional: Component Selection

The install script can be made modular. User chooses which SDR apps to install:

```
[x] rtl_fm_python_webgui (FM/VHF Radio)
[x] welle-cli (DAB+ Radio) 
[x] OpenWebRX+ (Wideband SDR)
[x] dump1090-fa (ADS-B Aircraft)
[x] AIS-catcher (Ship Tracking)
```

This saves disk space and install time for users who don't need everything.
