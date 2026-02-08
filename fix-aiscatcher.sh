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
CMD=("/usr/bin/AIS-catcher")

# Add config file if it exists
if [ -f "$CONF_FILE" ]; then
    CMD+=("-C" "$CONF_FILE")
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
EOF

sudo mv /tmp/start-aiscatcher.sh /opt/delling/scripts/start-aiscatcher.sh
sudo chmod +x /opt/delling/scripts/start-aiscatcher.sh

echo "Restarting AIS-catcher service..."
sudo systemctl daemon-reload
sudo systemctl restart aiscatcher

echo "Done! Check status with: sudo systemctl status aiscatcher"
