#!/bin/bash
set -e

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# Check for Debian-based OS
if [ ! -f /etc/debian_version ]; then
    echo "This script is intended for Debian-based systems."
    exit 1
fi

# Function to detect the architecture
detect_arch() {
    case $(uname -m) in
        x86_64)
            echo "amd64"
            ;;
        aarch64)
            echo "aarch64"
            ;;
        *)
            echo "unsupported"
            ;;
    esac
}

# Function to install dependencies
install_dependencies() {
    echo "Updating package lists... (ignoring errors from misconfigured repositories)"
    apt-get update || echo "apt-get update failed, but continuing installation."

    echo "Installing dependencies..."
    apt-get install -y python3 python3-pip

    # Verify that dependencies are installed
    if ! command -v python3 &> /dev/null; then
        echo "ERROR: python3 could not be installed. Please check your system's package manager configuration."
        exit 1
    fi
    if ! command -v pip3 &> /dev/null; then
        echo "ERROR: pip3 could not be installed. Please check your system's package manager configuration."
        exit 1
    fi

    pip3 install -r requirements.txt
}

# Function to configure YSFReflector.ini
configure_ini() {
    echo "Starting interactive configuration..."
    read -p "Enter reflector name: " REFLECTOR_NAME
    read -p "Enter reflector description: " REFLECTOR_DESC
    read -p "Enter reflector port [42395]: " REFLECTOR_PORT
    REFLECTOR_PORT=${REFLECTOR_PORT:-42395}

    echo "Creating YSFReflector.ini..."
    cp YSFReflector.ini /etc/YSFReflector.ini
    sed -i "s|<reflector name>|$REFLECTOR_NAME|" /etc/YSFReflector.ini
    sed -i "s|<reflector description>|$REFLECTOR_DESC|" /etc/YSFReflector.ini
    sed -i "s|Port=42395|Port=$REFLECTOR_PORT|" /etc/YSFReflector.ini
    sed -i "s|FilePath=/var/log|FilePath=/var/log/ysfreflector|" /etc/YSFReflector.ini

    # Add a variable to store the port for the firewall warning
    export REFLECTOR_PORT
}

# Function to install the application
install_application() {
    echo "Creating dedicated user 'ysfreflector'..."
    useradd -r -s /bin/false ysfreflector || echo "User 'ysfreflector' already exists."

    echo "Copying application files..."
    cp YSFReflector /usr/local/bin/YSFReflector
    cp deny.db /usr/local/etc/deny.db

    echo "Creating log directory..."
    mkdir -p /var/log/ysfreflector
    chown ysfreflector:ysfreflector /var/log/ysfreflector
}

# Function to setup systemd and logrotate
setup_services() {
    echo "Configuring systemd service..."
    # Correct the user, group, and config file path in the service file
    sed -e 's/User=mmdvm/User=ysfreflector/' \
        -e 's/Group=mmdvm/Group=ysfreflector/' \
        -e 's|/etc/YSFReflector/YSFReflector.ini|/etc/YSFReflector.ini|' \
        systemd/YSFReflector.service > /tmp/YSFReflector.service.tmp

    echo "Copying systemd service file..."
    cp /tmp/YSFReflector.service.tmp /etc/systemd/system/YSFReflector.service

    echo "Copying logrotate config file..."
    cp logrotate.d/YSFReflector /etc/logrotate.d/YSFReflector

    echo "Reloading systemd daemon..."
    systemctl daemon-reload
    echo "Enabling YSFReflector service..."
    systemctl enable YSFReflector.service
    echo "Starting YSFReflector service..."
    systemctl restart YSFReflector.service
}

# Main script
ARCH=$(detect_arch)

if [ "$ARCH" == "unsupported" ]; then
    echo "Unsupported architecture."
    exit 1
fi

echo "Detected architecture: $ARCH"
install_dependencies

echo "Dependencies installed successfully."

install_application

configure_ini

setup_services

echo "Installation and configuration complete."
echo "Checking service status..."
systemctl status YSFReflector.service --no-pager

echo ""
echo "****************************************************************"
echo "FIREWALL WARNING"
echo "****************************************************************"
echo "Please remember to open port $REFLECTOR_PORT (UDP) in your firewall."
echo "****************************************************************"
