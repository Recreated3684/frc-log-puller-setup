#!/usr/bin/env bash
set -e

# -------------------------------------------
# FRC Log Puller First-Run Setup Script
# Hosts: Orange Pi Zero 3 (Armbian CLI)
# Usage: curl -sSL <URL-to-this-script> | bash
# -------------------------------------------

#--- 1. Ask for team number and compute IPs ---
read -p "Enter your FRC team number (e.g. 6328): " TEAM
TE=$(( TEAM / 100 ))
AM=$(( TEAM % 100 ))
IP="10.${TE}.${AM}.88"
GATEWAY="10.${TE}.${AM}.1"
NETMASK="24"

echo
echo "Configuring Ethernet static IP to ${IP}/${NETMASK} with gateway ${GATEWAY}"

#--- 2. Identify active Ethernet connection profile ---
CONN=$(nmcli -t -f NAME,TYPE connection show --active | grep ":ethernet" | cut -d: -f1 | head -n1)
if [ -z "$CONN" ]; then
  echo "Error: no active Ethernet connection detected."
  echo "Please connect Ethernet and try again."
  exit 1
fi

#--- 3. Apply static IP via NetworkManager ---
nmcli connection modify "$CONN" \
  ipv4.method manual \
  ipv4.addresses "${IP}/${NETMASK}" \
  ipv4.gateway "$GATEWAY" \
  ipv4.dns "8.8.8.8" \
  connection.autoconnect yes

nmcli connection down "$CONN" && nmcli connection up "$CONN"

echo "Static IP set and connection restarted."

#--- 4. Install system dependencies ---
echo
echo "Updating package lists and installing dependencies..."
apt update
apt install -y git python3 python3-pip

#--- 5. Clone or update the log-puller repo ---
REPO_URL="https://github.com/your-org/frc-log-puller.git"
TARGET_DIR="frc-log-puller"
if [ ! -d "$TARGET_DIR" ]; then
  echo "Cloning log-puller repository..."
  git clone "$REPO_URL" "$TARGET_DIR"
else
  echo "Repository exists; pulling latest changes..."
  cd "$TARGET_DIR"
  git pull
  cd ..
fi

#--- 6. Create systemd service for auto-start ---
SERVICE_NAME="frc-log-puller"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
WORK_DIR="$(pwd)/${TARGET_DIR}"

echo "Creating systemd service: ${SERVICE_NAME}" 
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=FRC Log Puller Service
After=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${WORK_DIR}
ExecStart=/usr/bin/python3 ${WORK_DIR}/pull_logs.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload, enable, and start service
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

echo
echo "Setup complete!"
echo "- Static IP: ${IP}" 
echo "- Log puller repo: ${WORK_DIR}" 
echo "- Service: ${SERVICE_NAME} running"
