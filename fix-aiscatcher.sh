#!/bin/bash
# Quick fix for AIS-catcher startup script
# Run this to update without reinstalling: chmod +x fix-aiscatcher.sh && ./fix-aiscatcher.sh

set -e

echo "Updating AIS-catcher startup script..."

sudo mkdir -p /opt/delling/scripts

cat > /tmp/start-aiscatcher.sh << 'EOF'
#!/bin/bash
# Start AIS-catcher with offline web assets and MBTiles map tiles

CDN_PATH="/opt/delling/webassets"
CONF_FILE="/usr/share/aiscatcher/aiscatcher.conf"

# Build command as array for proper argument handling
CMD=("/usr/local/bin/AIS-catcher")

# Extract generic SDR settings from upstream config file
# Strip comments (#), blank lines, network config (we provide our own),
# and dongle-specific calibration (-gr gain, -p ppm) which vary per dongle
if [ -f "$CONF_FILE" ]; then
    SDR_ARGS=$(sed 's/#.*//; /^\s*$/d; /^\s*-N/d; /^\s*-S/d; /^\s*LAT/d; /^\s*-u/d; /^\s*-P/d; /^\s*-gr/d; /^\s*-p/d' "$CONF_FILE" | tr '\n' ' ')
    if [ -n "$SDR_ARGS" ]; then
        read -ra EXTRA_ARGS <<< "$SDR_ARGS"
        CMD+=("${EXTRA_ARGS[@]}")
        echo "SDR settings from config: $SDR_ARGS"
    fi
fi

# Use safe defaults: autogain and auto ppm (each dongle differs)
CMD+=("-gr" "TUNER" "auto" "RTLAGC" "on")
CMD+=("-p" "0")

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
EOF

sudo mv /tmp/start-aiscatcher.sh /opt/delling/scripts/start-aiscatcher.sh
sudo chmod +x /opt/delling/scripts/start-aiscatcher.sh

echo "Restarting AIS-catcher service..."
sudo systemctl daemon-reload
sudo systemctl restart aiscatcher

echo "Done! Check status with: sudo systemctl status aiscatcher"
