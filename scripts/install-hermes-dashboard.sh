#!/bin/bash
set -e

# --- Config: adjust these if needed ---
HERMES_BIN="$(which hermes || echo /usr/local/bin/hermes)"
RUN_USER="${SUDO_USER:-$USER}"
SERVICE_NAME="hermes-dashboard"

# --- Create systemd unit ---
sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=Hermes Dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
ExecStart=${HERMES_BIN} dashboard --host 0.0.0.0
Restart=always
RestartSec=5
Environment=PATH=/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
EOF

# --- Enable and start ---
sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}.service
sudo systemctl restart ${SERVICE_NAME}.service

echo ""
echo "Done. Status:"
sudo systemctl status ${SERVICE_NAME}.service --no-pager
