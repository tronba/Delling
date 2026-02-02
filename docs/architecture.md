# Delling Architecture

## Overview

Delling is a self-contained emergency information hub running on ARM SBCs (Orange Pi / Raspberry Pi). It creates a WiFi access point that users connect to with phones or laptops, accessing all services through a web browser.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         DELLING HUB                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │   OliveTin  │  │  SDR Apps   │  │  Tinymedia  │  │   Kiwix     │ │
│  │  Dashboard  │  │ (1 at time) │  │   Server    │  │   Server    │ │
│  │   :1337     │  │ (various)   │  │   :5000     │  │   :8000     │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘ │
│         ▲                ▲                ▲                ▲        │
│         └────────────────┴────────────────┴────────────────┘        │
│                              wlan0 (AP)                             │
│                           192.168.4.1/24                            │
└─────────────────────────────────────────────────────────────────────┘
          │                      │
          ▼                      ▼
    ┌──────────┐           ┌──────────┐
    │  Phone   │           │  Laptop  │
    │  WiFi    │           │  WiFi    │
    └──────────┘           └──────────┘
```

---

## Network Architecture

### WiFi Access Point
- **Interface:** wlan0
- **Mode:** Access Point (NetworkManager `nmcli`)
- **SSID:** "Delling" (configurable)
- **Password:** None (open network for emergency access)
- **IP:** 192.168.4.1/24
- **DHCP:** Provided by NetworkManager's shared mode
- **Band:** 2.4 GHz (bg) for maximum device compatibility

### Captive Portal
When users connect and open any webpage:
1. **DNS redirect:** dnsmasq returns 192.168.4.1 for all queries
2. **HTTP redirect:** nftables redirects port 80 → 1337 (OliveTin)
3. User lands on the OliveTin dashboard

### Ethernet (Optional)
- Used as **client** for initial setup (internet for package installation)
- Can connect Delling to existing network for wired access
- **Note:** Meshtastic web UI won't work from devices on the wired network

### IP Forwarding
- **Disabled** (`net.ipv4.ip_forward = 0`)
- WiFi clients cannot reach the internet through Ethernet
- Intentional isolation for offline operation

---

## Port Allocation

| Port | Service | Description |
|------|---------|-------------|
| 1337 | OliveTin | Main dashboard (captive portal target) |
| 5000 | Tinymedia | Media file browser/streamer |
| 8000 | Kiwix | Offline Wikipedia/ZIM viewer |
| 7979 | welle-cli | DAB+ radio |
| 8073 | OpenWebRX+ | Wideband SDR receiver |
| 8080 | dump1090-fa | ADS-B aircraft tracking |
| 8100 | AIS-catcher | Ship tracking |
| 10100 | rtl_fm_webgui | FM/AM/VHF radio |

> **TODO:** Confirm welle-cli port. The README mentions files go to `/usr/share/welle-io/html` but doesn't specify the port.

---

## Component Overview

### Core Infrastructure
| Component | Purpose | Install Method | Service Name |
|-----------|---------|----------------|--------------|
| NetworkManager | WiFi AP + DHCP | apt (pre-installed) | NetworkManager |
| dnsmasq | DNS redirect for captive portal | apt | (via NM) |
| nftables | HTTP → dashboard redirect | apt | nftables |
| OliveTin | Dashboard / service control | .deb download | OliveTin |

### SDR Applications (Mutually Exclusive)
Only one SDR app can run at a time (single RTL-SDR dongle).

| Component | Purpose | Install Method | Service Name |
|-----------|---------|----------------|--------------|
| OpenWebRX+ | Wideband SDR | apt (custom repo) | openwebrx |
| dump1090-fa | ADS-B tracking | install script | dump1090-fa |
| AIS-catcher | Ship tracking | install script | aiscatcher |
| rtl_fm_webgui | FM/VHF radio | git clone + build | rtl-fm-radio |
| welle-cli | DAB+ radio | apt (welle.io) | ? |

### Media & Knowledge
| Component | Purpose | Install Method | Service Name |
|-----------|---------|----------------|--------------|
| Tinymedia | File browser/streamer | git clone | tinymedia |
| Kiwix | Offline wiki/ZIM | script (see README) | kiwix (custom) |

### Communication
| Component | Purpose | Install Method | Notes |
|-----------|---------|----------------|-------|
| Meshtastic | Mesh messaging | Heltec V3 firmware | Hardware-based, USB serial |

---

## USB Storage

### Mount Point
```
/media/usb/
```

### Expected Structure
```
/media/usb/
├── Media/
│   ├── Video/
│   └── Audio/
├── Install files/
│   ├── Android/
│   └── Windows/
└── kiwix/
    └── *.zim files
```

### Filesystem
- **exFAT** for cross-platform compatibility (Windows/Mac/Linux)
- Tinymedia auto-detects and mounts removable USB on install

---

## Service Control Flow

OliveTin acts as the "switchboard":

```
┌──────────────────────────────────────────────────────────────────┐
│                         OliveTin                                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐            │
│  │ FM Radio │ │  DAB+    │ │  ADS-B   │ │   AIS    │ ...        │
│  │  Button  │ │  Button  │ │  Button  │ │  Button  │            │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘            │
│       │            │            │            │                   │
│       ▼            ▼            ▼            ▼                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  stop_all_sdr.sh  →  systemctl start <selected_service>     ││
│  └─────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────┘
```

### SDR Service Switching
1. User clicks SDR app button in OliveTin
2. OliveTin runs: `systemctl stop openwebrx dump1090-fa aiscatcher rtl-fm-radio ...`
3. OliveTin runs: `systemctl start <selected-service>`
4. User is redirected to the service's web UI

---

## Design Decisions (Resolved)

### Hardware
- **Primary target:** Raspberry Pi (Orange Pi 3 support planned later)
- **Design goal:** Affordable DIY kit — cheap enough to build for friends
- **Form factor:** 3D printed enclosure, USB stick mostly permanent
- **Heltec V3:** Connects via WiFi to the Pi's access point
  - Static IP: `192.168.4.10` (user configures manually on device)
  - Meshtastic web UI on port 80 (no conflict — different IP)
  - User pre-configures Heltec via Meshtastic app before deployment

### Port Conflict Resolution
Since only **one SDR app runs at a time**, port conflicts are not a runtime issue:
- dump1090-fa: 8080
- welle-cli: 8080 (same port, different service)
- Both can keep their default ports — OliveTin ensures mutual exclusion

### Service Behavior
| Service | Auto-start on boot | Always running |
|---------|-------------------|----------------|
| OliveTin (dashboard) | ✅ Yes | ✅ Yes |
| Tinymedia | ✅ Yes | ✅ Yes |
| Kiwix | ✅ Yes | ✅ Yes |
| SDR apps | ❌ No | ❌ One at a time |

### User Account
- **Not `pi`** — use current user (whoever installed OS) or create `delling` user
- Low-security local network device — simplicity over hardening

### OliveTin Dashboard Layout
Categories (in order):
1. 📻 **Radio** — FM, DAB+, OpenWebRX
2. 💬 **Coms** — Meshtastic (link to 192.168.4.10)
3. 📁 **Media** — Tinymedia, Kiwix (always-on, just links)
4. ✈️ **Tracking** — ADS-B, AIS

### SDR Service Switching Logic
```
User clicks SDR button → 
  1. Stop ALL SDR services (openwebrx, dump1090-fa, aiscatcher, rtl-fm-radio, welle-cli)
  2. Start selected service
  3. Show link to web UI
```

---

## Questions Still Open

### Minor Details
1. **OliveTin admin password:** Set during install, or leave default?

---

## Future Enhancements

### Country/Region Presets
Radio settings vary by country. Future versions could include:
- Country selection during install
- Pre-configured DAB channels per region (12A is default, common in Europe)
- FM band limits (87.5-108 MHz varies by country)
- Marine VHF channel presets for local coast guards
- Aviation frequencies for nearby airports

---

## Next Steps

1. ✅ Architecture decisions documented
2. Create `docs/components.md` with detailed per-component specs
3. Design OliveTin `config.yaml` structure  
4. Create `docs/install-order.md` with dependency graph
5. Build modular install scripts

