#!/usr/bin/env bash
set -e

# -------------------------------------------
# FRC Log Puller First-Run Setup Script
# Hosts: Orange Pi Zero 3 (Armbian CLI)
# Usage: curl -sSL <URL-to-this-script> | sudo bash
# -------------------------------------------

# 0. Ensure script runs as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: this script must be run as root."
  echo "Usage: curl -sSL <URL> | sudo bash"
  exit 1
fi

# 1. Install and start NetworkManager if missing
if ! command -v nmcli > /dev/null; then
  echo "Installing NetworkManager..."
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y network-manager
fi
systemctl enable NetworkManager
systemctl start NetworkManager

# 2. Prompt for team number and validate
read -p "Enter your FRC team number (e.g. 6328): " TEAM </dev/tty
if ! [[ "$TEAM" =~ ^[0-9]+$ ]]; then
  echo "Error: team number must be numeric."
  exit 1
fi

# 3. Compute IP addressing
TE=$(( TEAM / 100 ))
AM=$(( TEAM % 100 ))
IP="10.${TE}.${AM}.88"
GATEWAY="10.${TE}.${AM}.1"
NETMASK="24"

echo
printf "Assigning static IP %s/%s with gateway %s on eth0\n" "$IP" "$NETMASK" "$GATEWAY"

# 4. Create/replace connection profiles
# Remove old profiles if exist
nmcli connection delete frc-static &>/dev/null || true
nmcli connection delete frc-dhcp-fallback &>/dev/null || true

# Create fallback DHCP profile
nmcli connection add type ethernet con-name frc-dhcp-fallback ifname eth0 \
  ipv4.method auto \
  connection.autoconnect yes

# Create static profile
nmcli connection add type ethernet con-name frc-static ifname eth0 \
  ipv4.method manual \
  ipv4.addresses "${IP}/${NETMASK}" \
  ipv4.gateway "$GATEWAY" \
  ipv4.dns "8.8.8.8" \
  connection.autoconnect yes

# 5. Bring up static profile
nmcli connection up frc-static

echo "Static IP set; fallback DHCP profile 'frc-dhcp-fallback' enabled."

# 6. Install system dependencies

echo
printf "Installing git, python3, python3-pip...\n"
apt update
DEBIAN_FRONTEND=noninteractive apt install -y git python3 python3-pip

# 7. Clone or update the log-puller repo
REPO_URL="https://github.com/your-org/frc-log-puller.git"
TARGET_DIR="frc-log-puller"
if [ ! -d "$TARGET_DIR" ]; then
  echo "Cloning log-puller repository..."
  git clone "$REPO_URL" "$TARGET_DIR"
else
  echo "Updating existing repository..."
  cd "$TARGET_DIR"
  git pull --ff-only
  cd ..
fi

# 8. Create systemd service
SERVICE_NAME="frc-log-puller"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
WORK_DIR="$(pwd)/${TARGET_DIR}"

echo "Creating systemd service '${SERVICE_NAME}'..."
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

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# 9. Completion message

echo
printf "Setup complete!\n" \
  "Static IP: %s\n" "$IP" \
  "Repo path: %s\n" "$WORK_DIR" \
  "Service: %s (active)\n" "$SERVICE_NAME"
