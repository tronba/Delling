# Delling Components

Detailed specifications for each component in the Delling hub.

---

## Core Infrastructure

### 1. WiFi Access Point (NetworkManager)

**Purpose:** Creates the "Delling" WiFi network that users connect to.

| Property | Value |
|----------|-------|
| Package | `network-manager` (pre-installed on Raspberry Pi OS) |
| Interface | wlan0 |
| SSID | Delling |
| IP | 192.168.4.1/24 |
| DHCP Range | 192.168.4.100 - 192.168.4.200 (NetworkManager default) |
| Band | 2.4 GHz (bg) |

**Config commands:**
```bash
sudo nmcli con add type wifi ifname wlan0 mode ap con-name DellingAP ssid "Delling" \
  wifi.band bg wifi.channel 6 \
  ipv4.method shared ipv4.addresses 192.168.4.1/24 \
  ipv6.method disabled
sudo nmcli con modify DellingAP connection.autoconnect yes
```

**Dependencies:** None

---

### 2. Captive Portal (dnsmasq + nftables)

**Purpose:** Redirects users to the dashboard when they open any webpage.

| Property | Value |
|----------|-------|
| DNS Package | `dnsmasq` |
| Firewall | `nftables` |
| Target | 192.168.4.1:1337 (OliveTin) |

**DNS redirect:**
```
# /etc/NetworkManager/dnsmasq-shared.d/captive.conf
address=/#/192.168.4.1
```

**HTTP redirect (nftables):**
```bash
sudo nft add table ip captive
sudo nft add chain ip captive prerouting { type nat hook prerouting priority -100 \; }
sudo nft add rule ip captive prerouting iifname "wlan0" tcp dport 80 redirect to :1337
```

**Dependencies:** NetworkManager AP must be configured first

---

### 3. OliveTin (Dashboard)

**Purpose:** Main control panel. Start/stop services, links to apps.

| Property | Value |
|----------|-------|
| Install | Download `.deb` from GitHub releases |
| Port | 1337 |
| Config | `/etc/OliveTin/config.yaml` |
| Service | `OliveTin.service` |
| Auto-start | ✅ Yes |

**Install:**
```bash
wget https://github.com/OliveTin/OliveTin/releases/latest/download/OliveTin_linux_arm64.deb
sudo dpkg -i OliveTin_linux_arm64.deb
sudo systemctl enable --now OliveTin
```

**Dependencies:** None (first thing to install after base system)

---

## Always-On Services

### 4. Tinymedia (Media Server)

**Purpose:** Browse and stream video/audio from USB storage.

| Property | Value |
|----------|-------|
| Repository | `https://github.com/tronba/Tinymedia` |
| Port | 5000 |
| Service | `tinymedia.service` |
| Auto-start | ✅ Yes |
| MEDIA_ROOT | Auto-detected exFAT USB or `/media/usb` |

**Install:**
```bash
git clone https://github.com/tronba/Tinymedia /opt/tinymedia
cd /opt/tinymedia
./install_arm_no_venv.sh
```

**Dependencies:** 
- Python 3
- Flask, gunicorn (installed by script)
- USB drive mounted

**Notes:**
- Install script auto-detects exFAT USB drives
- Creates systemd service automatically
- Runs as current user

---

### 5. Kiwix (Offline Knowledge)

**Purpose:** Serve Wikipedia and other ZIM archives offline.

| Property | Value |
|----------|-------|
| Package | `kiwix-tools` |
| Port | 8000 |
| Service | `kiwix.service` (custom) |
| Auto-start | ✅ Yes |
| Content | `/media/usb/kiwix/*.zim` |

**Install:**
```bash
sudo apt install kiwix-tools
```

**Startup script:** `/opt/delling/scripts/start-kiwix.sh`
```bash
#!/bin/bash
MOUNT_POINT="/media/usb"
KIWIX_FOLDER="kiwix"
PORT=8000
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

# Find all .zim files
ZIM_FILES=$(find "$KIWIX_PATH" -maxdepth 1 -type f -name "*.zim" 2>/dev/null)

if [ -z "$ZIM_FILES" ]; then
    echo "No .zim files found in $KIWIX_PATH"
    exit 1
fi

FILE_COUNT=$(echo "$ZIM_FILES" | wc -l)
echo "Found $FILE_COUNT .zim file(s), starting kiwix-serve..."

exec kiwix-serve --port="$PORT" $ZIM_FILES
```

**Service file:** `/etc/systemd/system/kiwix.service`
```ini
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
```

**Dependencies:**
- USB drive mounted with ZIM files in `/media/usb/kiwix/`

---

### 6. Delling Maps (Offline Map Viewer + AIS Overlay)

**Purpose:** Serve offline map tiles from MBTiles files and display them in a Leaflet-based map viewer. Automatically overlays AIS ship positions when AIS-catcher is running.

| Property | Value |
|----------|-------|
| Source | Built-in (`ais-map/` directory) |
| Port | 8082 |
| Service | `delling-maps.service` |
| Auto-start | ✅ Yes |
| Content | `/media/usb/maps/*.mbtiles` |
| Dependencies | Flask, Leaflet (downloaded during install) |

**Features:**
- Serves raster map tiles directly from MBTiles (SQLite) — no external tile server binary needed
- Auto-discovers `.mbtiles` files on USB (case-insensitive `maps` folder)
- AIS ship overlay with SVG markers showing heading and speed
- Layer switcher when multiple tilesets are available
- Fully offline — Leaflet JS/CSS bundled locally
- CORS-enabled tile endpoints (other apps can use the tile server)

**How it works:**
1. Python Flask app reads tiles from MBTiles (SQLite) files
2. Leaflet map viewer loads tiles from `http://192.168.4.1:8082/tiles/{name}/{z}/{x}/{y}`
3. Ship overlay polls `http://192.168.4.1:8082/api/ships` (proxied from AIS-catcher on port 8100)

**AIS Integration:**
- The map app proxies ship data from AIS-catcher's REST API
- When AIS-catcher is running (started via dashboard), ship positions appear automatically
- When AIS-catcher is stopped, the map works normally without ships
- No modification to AIS-catcher needed — the integration is non-invasive

**USB folder structure:**
```
/media/usb/maps/         (case-insensitive: maps, Maps, MAPS)
├── region.mbtiles       (e.g., norway.mbtiles)
└── nautical.mbtiles     (optional: additional layers)
```

**Tile API (can be used by other services):**
- `GET /api/tilesets` — list available tilesets with metadata
- `GET /tiles/{name}/{z}/{x}/{y}` — XYZ tile endpoint
- `GET /api/ships` — proxied AIS ship data

**Service file:** `/etc/systemd/system/delling-maps.service`

**Dependencies:**
- USB drive mounted with `.mbtiles` files in `/media/usb/maps/`
- Leaflet JS/CSS (downloaded during install)
- AIS-catcher (optional, for ship overlay)

---

## SDR Applications (Mutually Exclusive)

> ⚠️ Only ONE of these can run at a time. OliveTin manages switching.

### 6. RTL-SDR Base Setup

**Purpose:** Blacklist default driver, install base tools.

| Property | Value |
|----------|-------|
| Package | `rtl-sdr` |
| Blacklist | `/etc/modprobe.d/blacklist-rtlsdr.conf` |
| udev rules | `/etc/udev/rules.d/20-rtlsdr.rules` |

**Install:**
```bash
echo 'blacklist dvb_usb_rtl28xxu' | sudo tee /etc/modprobe.d/blacklist-rtlsdr.conf
sudo apt install rtl-sdr
# udev rules for non-root access
sudo tee /etc/udev/rules.d/20-rtlsdr.rules << 'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2832", MODE="0666"
EOF
sudo udevadm control --reload-rules
```

**Dependencies:** None (install before any SDR app)

---

### 7. rtl_fm_python_webgui (FM/VHF Radio)

**Purpose:** FM broadcast, Marine VHF, Aviation, PMR446, Hunter radio.

| Property | Value |
|----------|-------|
| Repository | `https://github.com/tronba/rtl_fm_python_webgui` |
| Port | 10100 |
| Service | `rtl-fm-radio.service` |
| Auto-start | ❌ No |

**Install:**
```bash
sudo apt install librtlsdr-dev ffmpeg python3-flask
git clone https://github.com/tronba/rtl_fm_python_webgui /opt/rtl_fm_webgui
cd /opt/rtl_fm_webgui
./build.sh  # Compiles C library
./radio-control.sh install
sudo systemctl disable rtl-fm-radio  # Don't auto-start
```

**Dependencies:**
- RTL-SDR base setup
- librtlsdr-dev, ffmpeg, gcc

**Web UI pages:**
- `/static/index.html` — FM sweep scanner
- `/static/marine.html` — Marine VHF
- `/static/air.html` — Aviation
- (others as configured)

---

### 8. welle-cli (DAB+ Radio)

**Purpose:** Digital Audio Broadcasting (European digital radio).

| Property | Value |
|----------|-------|
| Package | `welle.io` (includes welle-cli) |
| Port | 7979 |
| Service | `welle-cli.service` (custom) |
| Auto-start | ❌ No |
| Web UI | Custom from `tronba/simple-webgui-welle-cli` |
| Command | `welle-cli -c 12A -C 1 -w 7979` |

**Command flags:**
- `-c 12A` — DAB channel (user may need to change for their region)
- `-C 1` — Device index
- `-w 7979` — Web server port

**Install:**
```bash
sudo apt install welle.io
# Install custom mobile-friendly web UI
git clone https://github.com/tronba/simple-webgui-welle-cli /tmp/welle-ui
sudo cp /tmp/welle-ui/index.html /usr/share/welle-io/html/
sudo cp /tmp/welle-ui/player.js /usr/share/welle-io/html/
```

**Service file:** `/etc/systemd/system/welle-cli.service`
```ini
[Unit]
Description=Welle-cli DAB+ Radio
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/welle-cli -c 12A -C 1 -w 7979
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

**Dependencies:**
- RTL-SDR base setup

---

### 9. OpenWebRX+ (Wideband SDR)

**Purpose:** General-purpose SDR receiver with waterfall display.

| Property | Value |
|----------|-------|
| Repository | Custom APT repo |
| Port | 8073 |
| Service | `openwebrx.service` |
| Auto-start | ❌ No |

**Install:**
```bash
curl -s https://luarvique.github.io/ppa/openwebrx-plus.gpg | \
  sudo gpg --yes --dearmor -o /etc/apt/trusted.gpg.d/openwebrx-plus.gpg
echo "deb [signed-by=/etc/apt/trusted.gpg.d/openwebrx-plus.gpg] \
  https://luarvique.github.io/ppa/bookworm ./" | \
  sudo tee /etc/apt/sources.list.d/openwebrx-plus.list
sudo apt update && sudo apt install openwebrx
sudo openwebrx admin adduser admin  # Set password
sudo systemctl disable openwebrx  # Don't auto-start
```

**Dependencies:**
- RTL-SDR base setup

---

### 10. dump1090-fa (ADS-B Aircraft Tracking)

**Purpose:** Receive aircraft transponder signals, show on map.

| Property | Value |
|----------|-------|
| Install | Script from GitHub |
| Port | 8080 |
| Service | `dump1090-fa.service` |
| Auto-start | ❌ No |

**Install:**
```bash
sudo bash -c "$(wget -O - https://raw.githubusercontent.com/abcd567a/piaware-ubuntu-debian-amd64/master/install-dump1090-fa.sh)"
sudo systemctl disable dump1090-fa
```

**Dependencies:**
- RTL-SDR base setup

---

### 11. AIS-catcher (Ship Tracking)

**Purpose:** Receive AIS signals from ships.

| Property | Value |
|----------|-------|
| Install | Script from GitHub |
| Port | 8100 |
| Service | `aiscatcher.service` |
| Auto-start | ❌ No |

**Install:**
```bash
sudo bash -c "$(wget -O - https://raw.githubusercontent.com/abcd567a/install-aiscatcher/master/install-aiscatcher.sh)"
sudo systemctl disable aiscatcher
# Fix config to use first available SDR
sudo sed -i 's/^-d [0-9]\+/#-d 0/' /usr/share/aiscatcher/aiscatcher.conf
```

**Dependencies:**
- RTL-SDR base setup

---

## External Hardware

### 12. Heltec V3 (Meshtastic)

**Purpose:** Off-grid mesh messaging via LoRa.

| Property | Value |
|----------|-------|
| Connection | WiFi (connects to Delling AP) |
| IP | 192.168.4.10 (static, configured on device) |
| Port | 80 |
| Setup | Manual by user via Meshtastic app |

**User setup instructions (for README):**
1. Flash Meshtastic firmware to Heltec V3
2. Use Meshtastic app to configure:
   - WiFi SSID: `Delling`
   - WiFi Password: (if any)
   - Static IP: `192.168.4.10`
3. Connect Heltec to power
4. Access web UI at `http://192.168.4.10`

**Dependencies:** None (external device)

---

## SDR Stop Script

Needed by OliveTin to ensure clean switching:

```bash
#!/bin/bash
# /opt/delling/scripts/stop-all-sdr.sh
sudo systemctl stop openwebrx dump1090-fa aiscatcher rtl-fm-radio welle-cli 2>/dev/null
sleep 1
```

---

## Summary Table

| Component | Port | Auto-start | Install Method |
|-----------|------|------------|----------------|
| OliveTin | 1337 | ✅ | .deb |
| Tinymedia | 5000 | ✅ | git clone + script |
| Kiwix | 8000 | ✅ | apt + custom service |
| Delling Maps | 8082 | ✅ | built-in (ais-map/) |
| rtl_fm_webgui | 10100 | ❌ | git clone + build |
| welle-cli | 7979 | ❌ | apt + custom service |
| OpenWebRX+ | 8073 | ❌ | apt (custom repo) |
| dump1090-fa | 8080 | ❌ | install script |
| AIS-catcher | 8100 | ❌ | install script |
| Meshtastic | 80 | N/A | External device |
