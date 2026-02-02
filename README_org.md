# Delling

**A portable hub for offline information, media, and local communication.**

Delling – named after the Norse god of dawn – is a self-contained hub that runs on Orange Pi or Raspberry Pi. Connect via WiFi, control everything from your browser. Built for power outages, cabins, and community resilience.

---

## Features

- **Software-defined radio** – Multiple SDR applications (one at a time):
  - DAB+ radio (welle-cli with mobile web interface)
  - RTL_FM Web GUI (AM/FM radio streaming)
    - FM Radio
    - Marine VHF
    - Aviation
    - PMR446 walkie-talkie
    - Hunter/Gather Radio 
  - ADS-B aircraft tracking (dump1090-fa)
  - AIS ship tracking (AIS-catcher)
  - OpenWebRX+ (wideband radio receiver)
- **Local communication** – Mesh messaging via Meshtastic and Heltec V3
- **Media server** – Stream and share files from USB storage
- **Offline knowledge** – Kiwix server with Wikipedia and other archives

---

## Hardware

| Component | Purpose |
|-----------|---------|
| Orange Pi 3 (2GB+) or Raspberry Pi | Main computer |
| SD card (8GB minimum) | Operating system |
| RTL-SDR dongle | Radio reception |
| USB storage (exFAT formatted) | Media and offline content |
| Heltec V3 | Meshtastic mesh node |

Networking: Delling runs as a WiFi access point with DHCP – phones and laptops connect directly to it. The Ethernet port is used as a client for initial setup (internet access) or to connect Delling to an existing wired network. Note: when connected via Ethernet to another network, the Meshtastic web interface wil not be accessible from devices on that network.

---

## USB Storage Setup

The USB drive must be formatted as **exFAT** for cross-platform compatibility.

### USB Folder structure

```
/media/usb/
├── Media/
│   ├── Video/
│   │   ├── Series Name/
│   │   │   └── episodes...
│   │   └── movies...
│   └── Audio/
│       └── music...
├── Install files/
│   ├── Android/
│   └── Windows/
└── kiwix/
    └── .zim files...
```

### USB stored media file format

For maximum phone compatibility, encode video files as:
- **Video codec:** H.264
- **Audio codec:** AAC
- **Container:** MP4

Most phones can play this natively in the browser without transcoding.

---

## Installation

### Prerequisites
- Fresh Raspberry Pi OS or Armbian install
- Internet connection (for initial setup)

### 1. System setup

```bash
# Set WLAN country
sudo raspi-config
# Localisation Options → WLAN Country → Select your country
sudo reboot
```

### 2. WiFi access point

```bash
# Verify wlan0 is available
nmcli device status

# Create access point
sudo nmcli con add type wifi ifname wlan0 mode ap con-name DellingAP ssid "Delling" \
  wifi.band bg \
  wifi.channel 6 \
  ipv4.method shared \
  ipv4.addresses 192.168.4.1/24 \
  ipv6.method disabled

# Enable and start
sudo nmcli con up DellingAP
sudo nmcli con modify DellingAP connection.autoconnect yes

# Disable IP forwarding (no routing to ethernet)
echo 'net.ipv4.ip_forward = 0' | sudo tee /etc/sysctl.d/99-no-forward.conf
sudo sysctl -p /etc/sysctl.d/99-no-forward.conf
```

### 3. Captive portal

```bash
sudo apt install dnsmasq

# DNS redirect
sudo nano /etc/NetworkManager/dnsmasq-shared.d/captive.conf
# Add: address=/#/192.168.4.1

# HTTP redirect
sudo nft add table ip captive
sudo nft add chain ip captive prerouting { type nat hook prerouting priority -100 \; }
sudo nft add rule ip captive prerouting iifname "wlan0" tcp dport 80 redirect to :1337
sudo nft list ruleset | sudo tee /etc/nftables.conf
sudo systemctl enable nftables
```

### 4. OliveTin (Main dashboard)

```bash
wget https://github.com/OliveTin/OliveTin/releases/latest/download/OliveTin_linux_arm64.deb
sudo dpkg -i OliveTin_linux_arm64.deb

# Configure
sudo nano /etc/OliveTin/config.yaml

sudo systemctl enable --now OliveTin
```

### 5. SDR setup

```bash
# Blacklist default driver
echo 'blacklist dvb_usb_rtl28xxu' | sudo tee /etc/modprobe.d/blacklist-rtlsdr.conf

sudo apt install rtl-sdr

# udev rules for permissions
sudo tee /etc/udev/rules.d/20-rtlsdr.rules << 'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2832", MODE="0666"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger
```

### 6. OpenWebRX+ (wideband SDR)

```bash
curl -s https://luarvique.github.io/ppa/openwebrx-plus.gpg | sudo gpg --yes --dearmor -o /etc/apt/trusted.gpg.d/openwebrx-plus.gpg

sudo tee /etc/apt/sources.list.d/openwebrx-plus.list <<< "deb [signed-by=/etc/apt/trusted.gpg.d/openwebrx-plus.gpg] https://luarvique.github.io/ppa/trixie ./"

sudo apt update
sudo apt install openwebrx

sudo openwebrx admin adduser admin

sudo systemctl enable openwebrx
sudo systemctl start openwebrx
```

### 7. ADS-B aircraft tracking

```bash
sudo bash -c "$(wget -O - https://raw.githubusercontent.com/abcd567a/piaware-ubuntu-debian-amd64/master/install-dump1090-fa.sh)"
sudo reboot

# Disable autostart (controlled via OliveTin)
sudo systemctl disable dump1090-fa
```

### 8. AIS ship tracking

```bash
sudo bash -c "$(wget -O - https://raw.githubusercontent.com/abcd567a/install-aiscatcher/master/install-aiscatcher.sh)"

# Disable autostart
sudo systemctl disable aiscatcher

# Fix config to use first available SDR
sudo sed -i 's/^-d [0-9]\+/#-d 0/' /usr/share/aiscatcher/aiscatcher.conf
```

### 9. Additional components
sudo apt install welle.io

Clone from GitHub:

```bash
# FM radio web interface
git clone https://github.com/tronba/rtl_fm_python_webgui
# start_web_stream.sh 
#service.conf contains info needed for service setup

# Media server
git clone https://github.com/tronba/Tinymedia
# install_arm_no_venv.sh
# (the install_arm_no_venv.sh file also sets up the service)

# DAB+ radio interface
git clone https://github.com/tronba/simple-webgui-welle-cli
# index.html and player.js must be added to the /usr/share/welle-io/html (or /usr/local/share/welle-io/html). Welle.


```

### 10. Kiwix (offline knowledge)

```bash
#!/bin/bash

# Configuration
MOUNT_POINT="/media/usb"  # Adjust if your USB mounts elsewhere
KIWIX_FOLDER="kiwix"
PORT=8080

# Full path to the kiwix folder
KIWIX_PATH="$MOUNT_POINT/$KIWIX_FOLDER"

# Check if USB is mounted
if ! mountpoint -q "$MOUNT_POINT"; then
    echo "No USB drive mounted at $MOUNT_POINT"
    exit 1
fi

# Check if kiwix folder exists
if [ ! -d "$KIWIX_PATH" ]; then
    echo "No kiwix folder found on USB drive"
    exit 1
fi

# Find all .zim files (including .zim.aa split files, we only want the base .zim)
ZIM_FILES=$(find "$KIWIX_PATH" -maxdepth 1 -type f -name "*.zim" 2>/dev/null)

# Check if any zim files were found
if [ -z "$ZIM_FILES" ]; then
    echo "No .zim files found in $KIWIX_PATH"
    exit 1
fi

# Count files for logging
FILE_COUNT=$(echo "$ZIM_FILES" | wc -l)
echo "Found $FILE_COUNT .zim file(s), starting kiwix-serve..."

# Start kiwix-serve with all found zim files
exec kiwix-serve --port="$PORT" $ZIM_FILES
# TODO: Add Kiwix installation steps
# Content path: /media/usb/kiwix/
```

---

## Usage

1. Power on Delling
2. Connect to WiFi network "Delling"
3. Open any webpage – you'll be redirected to the control panel
4. Select what you want to run

---

## Service control

Only one SDR application runs at a time. Use OliveTin or:

```bash
# Stop all SDR services
sudo systemctl stop openwebrx dump1090-fa aiscatcher

# Start the one you need
sudo systemctl start openwebrx
```

---

## Ports

| Service | Port |
|---------|------|
| OliveTin (control panel) | 1337 |
| Tinymedia | 5000 |
| Kiwix | 8000 |
| OpenWebRX+ | 8073 |
| dump1090-fa | 8080 |
| AIS-catcher | 8100 |

---

## License

TODO

---

## Credits

- [OliveTin](https://github.com/OliveTin/OliveTin)
- [OpenWebRX+](https://github.com/luarvique/openwebrx)
- [dump1090-fa](https://github.com/flightaware/dump1090)
- [AIS-catcher](https://github.com/jvde-github/AIS-catcher)
- [Kiwix](https://www.kiwix.org/)
- [Meshtastic](https://meshtastic.org/)
