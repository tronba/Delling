#!/bin/bash
set -e

WIFI_IFACE="wlan0"
IPTABLES_CMD="iptables-legacy"

echo "[1/5] Loading iptable_nat kernel module..."
sudo modprobe iptable_nat

echo "[2/5] Adding port 80 -> 8080 redirect rule..."
sudo $IPTABLES_CMD -t nat -C PREROUTING -i $WIFI_IFACE -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null \
    || sudo $IPTABLES_CMD -t nat -A PREROUTING -i $WIFI_IFACE -p tcp --dport 80 -j REDIRECT --to-port 8080

echo "[3/5] Adding port 443 -> 8443 redirect rule..."
sudo $IPTABLES_CMD -t nat -C PREROUTING -i $WIFI_IFACE -p tcp --dport 443 -j REDIRECT --to-port 8443 2>/dev/null \
    || sudo $IPTABLES_CMD -t nat -A PREROUTING -i $WIFI_IFACE -p tcp --dport 443 -j REDIRECT --to-port 8443

echo "[4/5] Rewriting iptables-restore.service..."
sudo tee /etc/systemd/system/iptables-restore.service > /dev/null << EOF
[Unit]
Description=Restore iptables rules for Delling captive portal
After=NetworkManager.service network-online.target
Wants=NetworkManager.service network-online.target

[Service]
Type=oneshot
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStartPre=/bin/sleep 5
ExecStartPre=/sbin/modprobe iptable_nat
ExecStart=/bin/sh -c "$IPTABLES_CMD -t nat -C PREROUTING -i $WIFI_IFACE -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null || $IPTABLES_CMD -t nat -A PREROUTING -i $WIFI_IFACE -p tcp --dport 80 -j REDIRECT --to-port 8080"
ExecStart=/bin/sh -c "$IPTABLES_CMD -t nat -C PREROUTING -i $WIFI_IFACE -p tcp --dport 443 -j REDIRECT --to-port 8443 2>/dev/null || $IPTABLES_CMD -t nat -A PREROUTING -i $WIFI_IFACE -p tcp --dport 443 -j REDIRECT --to-port 8443"
RemainAfterExit=yes
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "[5/5] Reloading systemd and enabling service..."
sudo systemctl daemon-reload
sudo systemctl enable iptables-restore

echo ""
echo "Current PREROUTING rules:"
sudo $IPTABLES_CMD -t nat -L PREROUTING -n -v --line-numbers

echo ""
echo "Done. http://192.168.4.1 should now work without :8080"
echo "Run: sudo reboot   to confirm it survives a restart"
