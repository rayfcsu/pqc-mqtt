#!/bin/bash

set -e

echo "-----------------------------------------"
echo "Cleaning up PQC/MQTT installation..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# remove main directories
echo "Removing installation directories..."
rm -rf /opt/oqs-provider /opt/liboqs /opt/openssl /opt/oqssa /opt/mosquitto 2>/dev/null || true

# remove test directory
rm -rf /pqc-mqtt 2>/dev/null || true

# remove Mosquitto from /usr/local
echo "Removing Mosquitto..."
rm -f /usr/local/bin/mosquitto* 2>/dev/null || true
rm -rf /usr/local/lib/libmosquitto* 2>/dev/null || true

# clean up symlinks
echo "Cleaning up symlinks..."
rm -f /usr/lib/libmosquitto.so.1 2>/dev/null || true

echo "Cleanup completed."
echo "-----------------------------------------"