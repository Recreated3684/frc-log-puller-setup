#!/usr/bin/env bash
set -e

# -------------------------------------------
# FRC Log Puller First-Run Setup Script
# Hosts: Orange Pi Zero 3 (Armbian CLI)
# Usage: curl -sSL <URL-to-this-script> | bash
# -------------------------------------------

# If script is piped, reattach STDIN to /dev/tty for interactive prompts
if [ ! -t 0 ]; then
  exec < /dev/tty
fi

# Ensure NetworkManager is installed for nmcli
if ! command -v nmcli > /dev/null; then
  echo "Installing NetworkManager..."
  apt update
  apt install -y network-manager
fi

#--- 1. Ask for team number and compute IPs ---
read -p "Enter your FRC team number (e.g. 6328): " TEAM
TE=$(( TEAM / 100 ))
AM=$(( TEAM % 100 ))
IP="10.${TE}.${AM}.88"
GATEWAY="10.${TE}.${AM}.1"
NETMASK="24"

echo
printf "Configuring Ethernet static IP to %s/%s with gateway %s\n" "$IP" "$NETMASK" "$GATEWAY"

#--- 2. Identify active Ethernet connection profile ---
CONN=$(nmcli -t -f NAME,TYPE connection show --active | grep ":ethernet" | cut -d: -f1 | head -n1)
if [ -z "$CONN" ]; then
  echo "Error: no active Ethernet connection detected."
  echo "Please connect Ethernet and try again."
  exit 1
fi

#--- 3. Create DHCP fallback profile ---
BACKUP_CONN="${CONN}-dhcp-fallback"
if ! nmcli connection show "$BACKUP_CONN" &>/dev/null; then
  echo "Creating DHCP fallback profile: $BACKUP_CONN"
  nmcli connection clone "$CONN" "$BACKUP_CONN"
  nmcli connection modify "$BACKUP_CONN" ipv4.method auto connection.autoconnect yes
fi

#--- 4. Apply static IP on primary profile ---
nmcli connection modify "$CONN" \
  ipv4.method manual \
  ipv4.addresses "${IP}/${NETMASK}" \
  ipv4.gateway "$GATEWAY" \
  ipv4.dns "8.8.8.8" \
  connection.autoconnect yes

nmcli connection down "$CONN" && nmcli connection up "$CONN"

echo "Static IP set and connection restarted. Fallback DHCP profile remains enabled."

#--- 5. Install system dependencies ---
echo
printf "Updating package lists and installing dependencies...\n"
apt update
apt install -y git python3 python3-pip

#--- 6. Clone or update the log-puller repo ---
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

#--- 7. Create systemd service for auto-start ---
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
printf "Setup complete!\n- Static IP: %s\n- Log puller repo: %s\n- Service: %s running\n" "$IP" "$WORK_DIR" "$SERVICE_NAME"
