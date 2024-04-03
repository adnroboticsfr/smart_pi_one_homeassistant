#!/bin/bash

# Check for sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "\e[1;31mPlease run this script with sudo: sudo $0\e[0m"
    exit 1
fi

# Check if Home Assistant Supervised is already installed
if [ -d "/usr/share/hassio" ]; then
    echo -e "\e[1;31mHome Assistant Supervised is already installed. Exiting script.\e[0m"
    exit 0
fi

#Install Docker-CE with the following command:
curl -fsSL get.docker.com | sh

# Determine system architecture
ARCHITECTURE=$(dpkg --print-architecture)

# Convert "amd64" to "x86_64" | "armhf" to "armv7" | "arm64" to "aarch64"
case $ARCHITECTURE in
    amd64) ARCHITECTURE="x86_64" ;;
    armhf) ARCHITECTURE="armv7" ;;
    arm64) ARCHITECTURE="aarch64" ;;
    *) echo "Unsupported architecture: $ARCHITECTURE" ; exit 1 ;;
esac

# Get the latest release URL
RELEASES_URL="https://api.github.com/repos/home-assistant/os-agent/releases/latest"
LATEST_RELEASE=$(curl -s "$RELEASES_URL" | jq -r '.assets[] | select(.name | endswith("'"_$ARCHITECTURE.deb"'")) | .browser_download_url')

if [ -z "$LATEST_RELEASE" ]; then
    echo "Failed to fetch the latest release URL for os-agent_$ARCHITECTURE.deb"
    exit 1
fi

# Extract package name from URL
PACKAGE_NAME=$(basename "$LATEST_RELEASE")

# Print package name
echo -e "\e[1;32mPackage Name: $PACKAGE_NAME\e[0m"

# Download the latest Home Assistant OS Agent
echo -e "\e[1;32mDownloading the latest Home Assistant OS Agent...\e[0m"
wget -O "$PACKAGE_NAME" "$LATEST_RELEASE"

# Install Home Assistant OS Agent
echo -e "\e[1;32mInstalling Home Assistant OS Agent...\e[0m"
sudo dpkg -i $PACKAGE_NAME

# Download Home Assistant Supervised
echo -e "\e[1;32mDownloading Home Assistant Supervised...\e[0m"
wget -O homeassistant-supervised.deb https://github.com/home-assistant/supervised-installer/releases/latest/download/homeassistant-supervised.deb

# Extract control.tar.xz
echo -e "\e[1;32mExtract control.tar.xz...\e[0m"
sudo ar x homeassistant-supervised.deb
sudo tar xf control.tar.xz

# Edit control file to remove systemd-resolved dependency
echo -e "\e[1;32mEdit control file to remove systemd-resolved dependency...\e[0m"
sed -i '/Depends:.*systemd-resolved/d' control

# Recreate control.tar.xz
echo -e "\e[1;32mRecreate control.tar.xz...\e[0m"
sudo tar cfJ control.tar.xz postrm postinst preinst control templates

# Recreate the .deb package
echo -e "\e[1;32mRecreate the .deb package...\e[0m"
sudo ar rcs homeassistant-supervised.deb debian-binary control.tar.xz data.tar.xz

# Install Home Assistant Supervised
echo -e "\e[1;32mInstalling Home Assistant Supervised...\e[0m"
sudo BYPASS_OS_CHECK=true dpkg -i ./homeassistant-supervised.deb

# Set the initial delay time
initial_delay=600  # 5 minutes in seconds

# Countdown loop with parallel execution of docker check
while [ $initial_delay -gt 0 ]; do
    minutes=$(($initial_delay / 60))
    seconds=$(($initial_delay % 60))
    
    echo -ne "\e[1;33mWaiting for $minutes:$seconds minutes to check the installation of Home Assistant...\e[0m\r"
    
    # Check if any container with "hassio" in the name is running
    if sudo docker ps --format '{{.Names}}' | grep -q "hassio"; then
        echo -e "\e[1;32mA Hassio-related container is running.\e[0m"
        break
    fi
    
    sleep 1
    ((initial_delay--))
done

gdbus introspect --system --dest io.hass.os --object-path /io/hass/os


DATA_SHARE=/my/own/homeassistant dpkg --force-confdef --force-confold -i homeassistant-supervised.deb

# If no Hassio-related container is running, perform system reboot
if [ $initial_delay -eq 0 ]; then
    echo -e "\e[1;31mNo Hassio-related container is running. Performing system reboot...\e[0m"
    sudo reboot
fi

# Check if the directory exists and recreate it if needed
if [ -d "/usr/share/hassio/tmp/homeassistant_pulse" ]; then
    echo -e "\e[1;32mDirectory /usr/share/hassio/tmp/homeassistant_pulse already exists.\e[0m"
else
    echo -e "\e[1;31mDirectory /usr/share/hassio/tmp/homeassistant_pulse does not exist. Recreating...\e[0m"
    sudo mkdir -p /usr/share/hassio/tmp/homeassistant_pulse
fi

# Clean up downloaded files
echo "Cleaning up downloaded files..."
rm -f "$PACKAGE_NAME" "./homeassistant-supervised.deb" "control" "data.tar.xz" "control.tar.xz"


echo -e "\e[1;33mHome Assistant installation completed successfully!\e[0m\n"
echo -e "\e[1;34mA system reboot will be performed to apply the changes.\e[0m\n"
echo -e "\e[1;32mAfter of Reboot Open the link: \e[0m\e[1;92mhttp://$(hostname -I | cut -d' ' -f1):8123\e[0m\n"
echo -e "\e[1;31mIf you see 'This site can�t be reached,' please check again after 10 minutes.\e[0m\n"

# Reboot System
sudo reboot
