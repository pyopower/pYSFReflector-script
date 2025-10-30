#!/bin/bash

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# Get the directory where the script is located
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# Check for required files to ensure the script is run correctly
REQUIRED_FILES=(
    "$SCRIPT_DIR/YSFReflector"
    "$SCRIPT_DIR/requirements.txt"
    "$SCRIPT_DIR/YSFReflector.ini"
    "$SCRIPT_DIR/systemd/YSFReflector.service"
    "$SCRIPT_DIR/logrotate.d/YSFReflector"
)

for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$f" ] && [ ! -d "$f" ]; then
        echo "Error: Required file or directory not found: $f"
        echo "Please ensure you are running this script from the root of the pYSFReflector repository."
        echo "Alternatively, the script may have been run in a way that prevents it from finding its files (e.g., by piping it to bash)."
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
if ! python3 -m pip install --break-system-packages -r "$SCRIPT_DIR/requirements.txt"; then
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
cp "$SCRIPT_DIR/YSFReflector" /opt/YSFReflector/
cp "$SCRIPT_DIR/deny.db" /opt/YSFReflector/
cp "$SCRIPT_DIR/YSFReflector.ini" /etc/ysfreflector/

# Set permissions
chown -R ysfreflector:ysfreflector /opt/YSFReflector
chown -R ysfreflector:ysfreflector /var/log/ysfreflector
chown -R ysfreflector:ysfreflector /etc/ysfreflector

echo "Starting interactive configuration..."
read -p "Enter reflector name: " reflector_name
read -p "Enter reflector description: " reflector_description
read -p "Enter reflector port [42395]: " reflector_port
reflector_port=${reflector_port:-42395}

# Update configuration file
sed -i "s/^Name = .*/Name = $reflector_name/" /etc/ysfreflector/YSFReflector.ini
sed -i "s/^Description = .*/Description = $reflector_description/" /etc/ysfreflector/YSFReflector.ini
sed -i "s/^Port = .*/Port = $reflector_port/" /etc/ysfreflector/YSFReflector.ini

# Copy service and logrotate files
cp "$SCRIPT_DIR/systemd/YSFReflector.service" /etc/systemd/system/
cp "$SCRIPT_DIR/logrotate.d/YSFReflector" /etc/logrotate.d/

# Reload systemd, enable and start the service
systemctl daemon-reload
systemctl enable YSFReflector.service
systemctl start YSFReflector.service

echo "Installation, configuration, and service setup complete."
