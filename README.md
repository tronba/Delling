# Delling

**A portable emergency information hub for offline communication, media, and radio.**

Delling – named after the Norse god of dawn – is a self-contained hub that runs on Orange Pi or Raspberry Pi. Connect via WiFi, control everything from your browser. Built for power outages, emergencies, cabins, and community resilience.

---

## Features

- **Software-defined radio** – Multiple SDR applications (one at a time):
  - FM Radio (AM/FM, Marine VHF, Aviation, PMR446)
  - DAB+ Radio (digital radio)
  - ADS-B aircraft tracking
  - AIS ship tracking
  - OpenWebRX (wideband radio receiver)
- **Local communication** – Mesh messaging via Meshtastic and Heltec V3
- **Media server** – Stream and share files from USB storage
- **Offline knowledge** – Kiwix server with Wikipedia and other archives

---

## Hardware Requirements

| Component | Purpose |
|-----------|---------|
| Orange Pi 3 (2GB+) or Raspberry Pi 4/5 | Main computer |
| SD card (16GB minimum recommended) | Operating system |
| RTL-SDR dongle | Radio reception |
| USB storage (exFAT formatted) | Media and offline content |
| Heltec V3 (optional) | Meshtastic mesh node |

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
└── kiwix/
    └── .zim files...
```

### Video Format

For maximum phone/tablet compatibility, encode video as:
- **Video codec:** H.264
- **Audio codec:** AAC
- **Container:** MP4

This allows direct playback in mobile browsers without transcoding.

---

## Installation

### Prerequisites
- Fresh Raspberry Pi OS (Bookworm) or Armbian install
- Internet connection via Ethernet (for initial setup)
- Basic Linux command line knowledge

### Quick Install

1. **Set WiFi country** (Raspberry Pi only):
   ```bash
   sudo raspi-config
   # Navigate to: Localisation Options → WLAN Country → Select your country
   ```

2. **Update system and install Git**:
   ```bash
   sudo apt update
   sudo apt upgrade
   sudo apt install git
   ```

3. **Clone and run installer**:
   ```bash
   git clone https://github.com/tronba/Delling
   cd Delling
   chmod +x install.sh
   ./install.sh
   ```

4. **Follow the prompts**:
   - WiFi network name (default: Delling)
   - WiFi channel (default: 6)
   - USB mount point (default: /media/usb)
   - OpenWebRX admin password

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
- **Media Server** - Browse and stream media from USB
- **Kiwix** - Offline Wikipedia and educational content
- **Aircraft Tracking** - Live ADS-B flight tracking
- **Ship Tracking** - Live AIS marine tracking
- **Meshtastic** - Mesh messaging (requires Heltec V3)
- **OpenWebRX** - Advanced wideband SDR receiver

**Note:** Only one SDR service (FM/DAB/ADS-B/AIS/OpenWebRX) can run at a time. The system automatically stops other SDR services when you start a new one.

---

## Service Ports

| Service | Port |
|---------|------|
| Delling Dashboard | 1337 |
| FM Radio | 10100 |
| DAB+ Radio | 7979 |
| Tinymedia (media server) | 5000 |
| Kiwix | 8000 |
| OpenWebRX | 8073 |
| Aircraft Tracking (dump1090) | 8080 |
| Ship Tracking (AIS-catcher) | 8100 |
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
sudo systemctl stop rtl-fm-radio welle-cli openwebrx dump1090-fa aiscatcher

# Start a specific service
sudo systemctl start rtl-fm-radio

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
- [OpenWebRX+](https://github.com/luarvique/openwebrx) - SDR web receiver
- [dump1090-fa](https://github.com/flightaware/dump1090) - ADS-B decoder
- [AIS-catcher](https://github.com/jvde-github/AIS-catcher) - AIS receiver
- [Kiwix](https://www.kiwix.org/) - Offline content server
- [Meshtastic](https://meshtastic.org/) - Mesh networking
- [welle.io](https://github.com/AlbrechtL/welle.io) - DAB/DAB+ receiver
- [rtl_fm_python_webgui](https://github.com/tronba/rtl_fm_python_webgui) - FM radio interface
- [Tinymedia](https://github.com/tronba/Tinymedia) - Lightweight media server

---

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.
