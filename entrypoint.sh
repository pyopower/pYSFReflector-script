#!/bin/sh

# Exit immediately if a command exits with a non-zero status.
set -e

# Substitute environment variables in the config file
sed -i "s|<reflector name>|${YSF_NAME}|g" /etc/ysfreflector/YSFReflector.ini
sed -i "s|<reflector description>|${YSF_DESCRIPTION}|g" /etc/ysfreflector/YSFReflector.ini
sed -i "s|Port=42395|Port=${YSF_PORT}|g" /etc/ysfreflector/YSFReflector.ini
sed -i "s|File=/usr/local/etc/deny.db|File=/etc/ysfreflector/deny.db|g" /etc/ysfreflector/YSFReflector.ini
sed -i "s|FilePath=/var/log|FilePath=/var/log/ysfreflector|g" /etc/ysfreflector/YSFReflector.ini

# Execute the main process
exec "$@"
