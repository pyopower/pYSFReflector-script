#!/bin/bash

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# --- Staging Area ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
STAGING_DIR="/tmp/pYSFReflector-install"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -r "$SCRIPT_DIR"/* "$STAGING_DIR"/
cd "$STAGING_DIR"

# --- Management Functions ---
show_menu() {
    echo "YSFReflector Management Menu"
    echo "--------------------------"
    echo "1. View Reflector Status"
    echo "2. Stop Reflector"
    echo "3. Restart Reflector"
    echo "4. Uninstall Reflector"
    echo "5. Exit"
    echo "--------------------------"
}

uninstall_reflector() {
    echo "This will permanently remove YSFReflector and all associated files."
    read -p "Are you sure you want to continue? (y/n): " confirm1
    if [ "$confirm1" != "y" ]; then
        echo "Uninstall cancelled."
        return
    fi

    read -p "This action cannot be undone. Please confirm one last time. (y/n): " confirm2
    if [ "$confirm2" != "y" ]; then
        echo "Uninstall cancelled."
        return
    fi

    echo "Stopping and disabling services..."
    systemctl stop YSFReflector.service || true
    systemctl disable YSFReflector.service || true
    systemctl stop logtailer.service || true
    systemctl disable logtailer.service || true
    systemctl stop wysf-dashboard.service || true
    systemctl disable wysf-dashboard.service || true

    echo "Removing application files and directories..."
    rm -f /etc/systemd/system/YSFReflector.service
    rm -f /etc/systemd/system/logtailer.service
    rm -f /etc/systemd/system/wysf-dashboard.service
    rm -f /etc/logrotate.d/YSFReflector
    rm -rf /opt/YSFReflector
    rm -rf /etc/ysfreflector
    rm -rf /var/log/ysfreflector
    rm -rf /opt/WSYSFDash

    echo "Reloading systemd daemon..."
    systemctl daemon-reload

    echo "Removing the ysfreflector user..."
    userdel -r ysfreflector || true

    echo "YSFReflector and all associated components have been successfully uninstalled."
}

# --- Dashboard Installation ---
install_dashboard() {
    set -e # Exit immediately if a command fails

    echo "Installing WSYSFDash..."

    # Get dashboard ports from the user
    read -p "Enter the dashboard web service port [8080]: " web_port
    web_port=${web_port:-8080}
    read -p "Enter the dashboard websocket port [5678]: " ws_port
    ws_port=${ws_port:-5678}

    # Install dependencies
    apt-get update
    apt-get install -y python3-websockets python3-psutil git
    pip install --break-system-packages ansi2html

    # Clone the repository
    rm -rf /tmp/WSYSFDash
    git clone --recurse-submodules -j8 https://github.com/dg9vh/WSYSFDash /tmp/WSYSFDash

    # Create directories and copy files
    mkdir -p /opt/WSYSFDash
    cp -r /tmp/WSYSFDash/* /opt/WSYSFDash/
    chown -R ysfreflector:ysfreflector /opt/WSYSFDash

    # Configure the dashboard
    sed -i "s|^File = .*|File = /var/log/ysfreflector/YSFReflector.log|" /opt/WSYSFDash/logtailer.ini
    sed -i "s|^Port = .*|Port = $ws_port|" /opt/WSYSFDash/logtailer.ini
    sed -i "s|var WebsocketsPath.*|var WebsocketsPath        = \"/ysfreflector\";|" /opt/WSYSFDash/html/js/config.js
    sed -i "s|var WebsocketsPort.*|var WebsocketsPort      = $ws_port;|" /opt/WSYSFDash/html/js/config.js

    # Set up systemd services
    cat > /etc/systemd/system/logtailer.service << EOL
[Unit]
Description=Python3 logtailer for WSYSFDash
After=network.target

[Service]
Type=simple
User=ysfreflector
Group=ysfreflector
Restart=always
ExecStart=/usr/bin/python3 /opt/WSYSFDash/logtailer.py

[Install]
WantedBy=multi-user.target
EOL

    cat > /etc/systemd/system/wysf-dashboard.service << EOL
[Unit]
Description=Python3 HTTP Server for WSYSFDash
After=network.target

[Service]
Type=simple
User=ysfreflector
Group=ysfreflector
Restart=always
ExecStart=/usr/bin/python3 -m http.server $web_port --directory /opt/WSYSFDash/html

[Install]
WantedBy=multi-user.target
EOL

    # Enable and start services
    systemctl daemon-reload
    systemctl enable logtailer.service
    systemctl start logtailer.service
    systemctl enable wysf-dashboard.service
    systemctl start wysf-dashboard.service
}

# --- Main Script ---

# Check if the reflector is already installed
if [ -f "/opt/YSFReflector/YSFReflector" ]; then
  while true; do
    show_menu
    read -p "Enter your choice [1-5]: " choice
    case $choice in
      1)
        echo "Viewing status..."
        systemctl status YSFReflector.service
        ;;
      2)
        echo "Stopping reflector..."
        systemctl stop YSFReflector.service
        ;;
      3)
        echo "Restarting reflector..."
        systemctl restart YSFReflector.service
        ;;
      4)
        uninstall_reflector
        exit 0
        ;;
      5)
        break
        ;;
      *)
        echo "Invalid choice. Please enter a number between 1 and 5."
        ;;
    esac
    echo ""
  done
  exit 0
fi

# Check for required files to ensure the script is run correctly
REQUIRED_FILES=(
    "YSFReflector"
    "requirements.txt"
    "YSFReflector.ini"
    "systemd/YSFReflector.service"
    "logrotate.d/YSFReflector"
)

for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$f" ] && [ ! -d "$f" ]; then
        echo "Error: Required file or directory not found: $f"
        echo "Please ensure you are running this script from the root of the pYSFReflector repository."
        exit 1
    fi
done

# Check if pip is installed, and if not, install it
if ! command -v pip &> /dev/null; then
  echo "pip not found. Installing python3-pip..."
  apt-get update
  apt-get install -y python3-pip
fi

echo "Installing dependencies..."
if ! python3 -m pip install --break-system-packages -r "requirements.txt"; then
  echo "Failed to install dependencies." >&2
  exit 1
fi
echo "Dependencies installed successfully."

# Create a dedicated user for YSFReflector
if ! id "ysfreflector" &>/dev/null; then
  useradd -r -s /bin/false ysfreflector
fi

# Create necessary directories
mkdir -p /opt/YSFReflector
mkdir -p /var/log/ysfreflector
mkdir -p /etc/ysfreflector

# Copy files
cp "YSFReflector" /opt/YSFReflector/
cp "YSFReflector.ini" /etc/ysfreflector/

# Set permissions
chown -R ysfreflector:ysfreflector /opt/YSFReflector
chown -R ysfreflector:ysfreflector /var/log/ysfreflector
chown -R ysfreflector:ysfreflector /etc/ysfreflector

# Verify permissions
if [ ! -r "/opt/YSFReflector/YSFReflector" ]; then
    echo "Error: /opt/YSFReflector/YSFReflector is not readable."
    exit 1
fi


echo "Starting interactive configuration..."
read -p "Enter reflector name: " reflector_name
read -p "Enter reflector description: " reflector_description
read -p "Enter reflector port [42395]: " reflector_port
reflector_port=${reflector_port:-42395}

# Update configuration file
sed -i "s#Name=.*#Name=$reflector_name#" /etc/ysfreflector/YSFReflector.ini
sed -i "s#Description=.*#Description=$reflector_description#" /etc/ysfreflector/YSFReflector.ini
sed -i "s#Port=.*#Port=$reflector_port#" /etc/ysfreflector/YSFReflector.ini
sed -i "s#FileRotate=.*#FileRotate=0#" /etc/ysfreflector/YSFReflector.ini

# Copy service and logrotate files
cp "systemd/YSFReflector.service" /etc/systemd/system/
cp "logrotate.d/YSFReflector" /etc/logrotate.d/

# Reload systemd, enable and start the service
systemctl daemon-reload
systemctl enable YSFReflector.service
systemctl restart YSFReflector.service

echo "Installation, configuration, and service setup complete."

# Ask to install the dashboard
read -p "Do you want to install the WSYSFDash dashboard? (y/n): " install_dashboard_choice
if [ "$install_dashboard_choice" == "y" ]; then
  install_dashboard
fi
