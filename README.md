# Delling

**A portable emergency information hub for offline communication, media, and radio.**

Delling – named after the Norse god of dawn, is a self-contained hub that runs on Orange Pi or Raspberry Pi. Connect to it from a cellphone via WiFi, all normal features are available from the browser. Built for power outages, emergencies, cabins, and community resilience.

---

## Features

- **Software-defined radio** – Multiple SDR applications (one at a time):
  - FM Radio (AM/FM, Marine VHF, Aviation, PMR446)
  - DAB+ Radio (digital radio)
  - AIS ship tracking
  - ADS-B aircraft tracking (readsb + tar1090)
- **Offline maps** – Leaflet map viewer with MBTiles tile server, AIS ship overlay
- **Local communication** – Mesh messaging via Meshtastic and Heltec V3
- **Media server** – Stream and share files from USB storage
- **Offline knowledge** – Kiwix server with Wikipedia and other archives

---

## Hardware Requirements

| Component | Purpose |
|-----------|---------|
| Orange Pi 3 (1.5GB+) or Raspberry Pi 4/5 | Main computer |
| SD card (8GB minimum recommended) | Operating system |
| RTL-SDR dongle | Radio reception |
| USB storage (exFAT formatted) 64gb+ recommended | Media and offline content |
| Heltec V3 | Meshtastic mesh node |

**Networking:** Delling creates its own WiFi access point. Devices connect directly to it. The Ethernet port can be used for initial setup (internet access) or to connect Delling to an existing network.

---

## USB Storage Setup

The USB drive must be formatted as **exFAT** for cross-platform compatibility.

### Folder Structure

```
/media/usb/
├── Media/
│   ├── Video/
│   │   ├── Series Name/
│   │   │   └── episodes...
│   │   └── movies...
│   └── Audio/
│       └── music...
├── kiwix/
│   └── .zim files...
└── maps/
    └── .mbtiles files...
```

> **Important:** Kiwix `.zim` filenames must not contain spaces. Rename files like `wikipedia_en_all 2026.zim` to `wikipedia_en_all_2026.zim` before use. The folder names `kiwix` and `maps` are case-insensitive (`Kiwix`, `KIWIX`, `Maps`, `MAPS`, etc. all work).

> **Map tiles:** Download global or regional `.mbtiles` files from [OpenAndroMaps](https://www.openandromaps.org/en/downloads/general-maps) before running the installer. Place them in the `maps/` folder on your USB drive.

### Video Format

For maximum phone/tablet compatibility, encode video as:
- **Video codec:** H.264
- **Audio codec:** AAC
- **Container:** MP4

This allows direct playback in mobile browsers without transcoding.

---

## Installation

### Prerequisites
- Fresh Raspberry Pi OS (Trixie) or Armbian install
- **Ethernet connection required** (WiFi will be reconfigured during install)
- Basic Linux command line knowledge

#### USB Drive Setup (before installing)

The installer expects an exFAT-formatted USB drive connected and mounted at `/media/usb`. Prepare the following folders and files on the drive before running `install.sh`:

| Folder | Contents | Used by |
|--------|----------|---------|
| `Media/` | Video and audio files (see [Video Format](#video-format)) | Tinymedia |
| `maps/` | `.mbtiles` map tile files | Offline Maps, AIS ship overlay, ADS-B tracking |
| `kiwix/` | `.zim` offline knowledge files | Kiwix |

All three folders are optional — the installer will skip or gracefully handle missing ones — but the services that depend on them won't work without the files. Folder names are case-insensitive (`maps`, `Maps`, `MAPS` all work).

> **Note:** If the USB drive is not connected during install, Tinymedia setup will be skipped. You can run it manually later.

> **Warning:** Do NOT run the installer over WiFi SSH. The script reconfigures WiFi as an access point, which will disconnect you. Always use Ethernet.

### Quick Install

1. **Set WiFi country** (Raspberry Pi only — required for WiFi AP to work):
   ```bash
   sudo raspi-config
   ```
   Navigate to: `Localisation Options` → `WLAN Country` → Select your country, then reboot if prompted.

2. **Update system and install Git**:
   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo apt install -y git
   ```

3. **Clone and run installer**:
   ```bash
   git clone https://github.com/tronba/Delling ~/Delling
   cd ~/Delling
   chmod +x install.sh
   ./install.sh
   ```

4. **Follow the prompts**:
   - WiFi network name (default: Delling)
   - WiFi channel (default: 6)

The installation takes 15-30 minutes depending on your hardware and internet speed.

### Post-Installation

After installation completes:
```bash
sudo reboot
```

Once rebooted, Delling will be ready:
- WiFi network "Delling" (or your chosen name) will be active
- Connect any device to this network
- Open a web browser - you'll be redirected to the control panel

---

## Usage

1. **Power on** Delling
2. **Connect** to WiFi network "Delling" (open network, no password)
3. **Open browser** - automatically redirects to control panel
4. **Click service** you want to use - browser opens automatically

### Services

- **FM Radio** - AM/FM radio streaming with web interface
- **DAB+ Radio** - Digital radio receiver
- **Maps** - Offline map viewer with live AIS ship overlay
- **Media Server** - Browse and stream media from USB
- **Kiwix** - Offline Wikipedia and educational content
- **Ship Tracking** - Live AIS marine tracking
- **Aircraft Tracking** - ADS-B aircraft tracking with tar1090 map interface
- **Meshtastic** - Mesh messaging (requires Heltec V3)

**Note:** Only one SDR service (FM/DAB/AIS/ADS-B) can run at a time. The system automatically stops other SDR services when you start a new one.

---

## Service Ports

| Service | Port |
|---------|------|
| Delling Dashboard | 8080 |
| FM Radio | 10100 |
| DAB+ Radio | 7979 |
| Maps (tile server + viewer) | 8082 |
| Tinymedia (media server) | 5000 |
| Kiwix | 8000 |
| Ship Tracking (AIS-catcher) | 8100 |
| Aircraft Tracking (tar1090) | 8090 |
| Meshtastic | 192.168.4.10 |

---

## Troubleshooting

### No WiFi network appearing
- Check that wlan0 interface exists: `nmcli device status`
- Verify WiFi country is set (Raspberry Pi): `sudo raspi-config`
- Restart network: `sudo systemctl restart NetworkManager`

### Services not starting
- Check service status: `sudo systemctl status <service-name>`
- View logs: `sudo journalctl -u <service-name> -n 50`
- Restart dashboard: `sudo systemctl restart delling-dashboard`

### SDR not detected
- Check USB connection: `lsusb | grep Realtek`
- Test SDR: `rtl_test -t`
- Verify udev rules: `ls -l /etc/udev/rules.d/20-rtlsdr.rules`

### USB drive not mounting
- Check format is exFAT: `sudo blkid`
- Manual mount: `sudo mount /dev/sda1 /media/usb`
- Add to fstab for auto-mount

---

## Manual Service Control

All services are managed via systemd. You can control them manually if needed:

```bash
# Stop all SDR services
sudo systemctl stop rtl-fm-radio welle-cli aiscatcher readsb tar1090 lighttpd

# Start a specific service
sudo systemctl start rtl-fm-radio

# Start ADS-B (requires all three services)
sudo systemctl start readsb && sudo systemctl start tar1090 && sudo systemctl start lighttpd

# Set ADS-B receiver location (improves range display)
sudo readsb-set-location 59.9139 10.7522

# Adjust ADS-B gain
sudo readsb-gain -10

# Check service status
sudo systemctl status rtl-fm-radio

# View service logs
sudo journalctl -u rtl-fm-radio -f
```

---

## License

MIT License - See LICENSE file for details

---

## Credits

Built with open-source software:

- [Flask](https://flask.palletsprojects.com/) - Python web framework
- [AIS-catcher](https://github.com/jvde-github/AIS-catcher) - AIS receiver
- [readsb](https://github.com/wiedehopf/readsb) - ADS-B decoder (by wiedehopf)
- [tar1090](https://github.com/wiedehopf/tar1090) - ADS-B web interface (by wiedehopf)
- [Kiwix](https://www.kiwix.org/) - Offline content server
- [Meshtastic](https://meshtastic.org/) - Mesh networking
- [welle.io](https://github.com/AlbrechtL/welle.io) - DAB/DAB+ receiver
- [rtl_fm_python_webgui](https://github.com/tronba/rtl_fm_python_webgui) - FM radio interface
- [Tinymedia](https://github.com/tronba/Tinymedia) - Lightweight media server
- [Leaflet](https://leafletjs.com/) - Interactive map library

---

## Acknowledgements

The ADS-B aircraft tracking installation (readsb + tar1090) is adapted from the [automatic installation script by wiedehopf](https://github.com/wiedehopf/adsb-scripts/wiki/Automatic-installation-for-readsb). The upstream script handles a wide range of configurations and feeder setups; Delling's version is streamlined for offline/emergency use with on-demand SDR switching.

Thanks to Christian and Tobias for running the [OpenAndroMaps](https://www.openandromaps.org/) project, providing freely available offline map data.

---

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.
