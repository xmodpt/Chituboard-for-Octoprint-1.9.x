#!/usr/bin/env bash

# ASCII Art Banner
cat << "EOF"



   _____ _     _ _         _                         _ 
  / ____| |   (_) |       | |                       | |
 | |    | |__  _| |_ _   _| |__   ___   __ _ _ __ __| |
 | |    | '_ \| | __| | | | '_ \ / _ \ / _` | '__/ _` |
 | |____| | | | | |_| |_| | |_) | (_) | (_| | | | (_| |
  \_____|_| |_|_|\__|\__,_|_.__/ \___/ \__,_|_|  \__,_|
         ┬ ┌┐┌┌─┐┌┬┐┌─┐┬  ┬    ┌─┐┌─┐┬─┐┬┌─┐┌┬┐
         │ │││└─┐ │ ├─┤│  │    └─┐│  ├┬┘│├─┘ │ 
         ┴ ┘└┘└─┘ ┴ ┴ ┴┴─┘┴─┘  └─┘└─┘┴└─┴┴   ┴ 
             Ver. 2.1    by CrAzZyRaBbIt           
              (Raspbian Bookworm Compatible)

Created By Vikram Sarkhel AKA: rudetrooper
    https://github.com/rudetrooper/Octoprint-Chituboard                                                                                       
EOF

# Exit on error
set -euo pipefail

# filename: Chituboard.sh
# modified version of Kenzillla's Mariner+Samba Auto-Installer
# Changed by CrAzY RaBbit 2024
# Adapted for Raspbian Bookworm (Debian 12) compatibility

# Exit on error
set -euo pipefail

function info { echo -e "\e[32m[info] $*\e[39m"; }
function warn  { echo -e "\e[33m[warn] $*\e[39m"; }
function error { echo -e "\e[31m[error] $*\e[39m"; exit 1; }

if ! [ "$(id -u)" = 0 ]; then
    warn "This script needs to be run as root." >&2
    exit 1
fi

info
info "Welcome to Octoprint+Samba Auto-Installer for Raspbian Bookworm!"
sleep .1
info "..."

sleep 1

# Detect boot configuration path (Bookworm uses /boot/firmware/)
if [ -d "/boot/firmware" ]; then
    BOOT_PATH="/boot/firmware"
    CONFIG_FILE="/boot/firmware/config.txt"
    CMDLINE_FILE="/boot/firmware/cmdline.txt"
    info "Detected Raspbian Bookworm - using /boot/firmware/"
elif [ -d "/boot" ]; then
    BOOT_PATH="/boot"
    CONFIG_FILE="/boot/config.txt"
    CMDLINE_FILE="/boot/cmdline.txt"
    info "Using legacy boot path /boot/"
else
    error "Cannot find boot configuration directory"
fi

# Checks the base of the dir this script is being run in such as /home/username/Chituboard.sh 
# This sets the var to the last directory in the file path.
ASSUMED_USER=$(basename "$(pwd)") 
DEFAULT_USER="pi"

info "File is being run in $(pwd)"
info "Which user account should the be installed in that contains your octoprint config?  The user may be ${ASSUMED_USER}."
info "Please confirm this below or choose another user."
info ""
info "Please TYPE the username you have created in Raspberry imager for the SSH connection"
read -r user_input
USER="${user_input:-${DEFAULT_USER}}"

info "User is: ${USER}"

# Verify user exists
if ! id "${USER}" &>/dev/null; then
    error "User '${USER}' does not exist on this system"
fi

info
info "Setting up Chituboard prerequisites"

# Check if config entries already exist to avoid duplicates
if ! grep -q "dtoverlay=dwc2,dr_mode=peripheral" "${CONFIG_FILE}"; then
    echo "dtoverlay=dwc2,dr_mode=peripheral" >> "${CONFIG_FILE}"
    info "Added dwc2 overlay to ${CONFIG_FILE}"
else
    info "dwc2 overlay already exists in ${CONFIG_FILE}"
fi

if ! grep -q "enable_uart=1" "${CONFIG_FILE}"; then
    echo "enable_uart=1" >> "${CONFIG_FILE}"
    info "Added enable_uart to ${CONFIG_FILE}"
else
    info "enable_uart already exists in ${CONFIG_FILE}"
fi

# Handle cmdline.txt modifications more carefully
if [ -f "${CMDLINE_FILE}" ]; then
    # Remove console=serial0,115200 if it exists
    sudo sed -i 's/console=serial0,115200 //g' "${CMDLINE_FILE}"
    
    # Add modules-load=dwc2 if it doesn't exist
    if ! grep -q "modules-load=dwc2" "${CMDLINE_FILE}"; then
        sed -i '$ s/$/ modules-load=dwc2/' "${CMDLINE_FILE}"
        info "Added modules-load=dwc2 to ${CMDLINE_FILE}"
    else
        info "modules-load=dwc2 already exists in ${CMDLINE_FILE}"
    fi
else
    warn "Warning: ${CMDLINE_FILE} not found"
fi

# Setup container file for storing uploaded files
info
info "Setting up Pi-USB; this could take several minutes"

# Present a menu for the user to select the size
info "Select the size of the storage:"
info "NOTE: The bigger your choice... the longer it will take"
options=("4GB" "8GB" "16GB")
PS3="Enter your choice (1-3): "
select opt in "${options[@]}"
do
    case $opt in
        "4GB")
            SIZE=4096
            break
            ;;
        "8GB")
            SIZE=8192
            break
            ;;
        "16GB")
            SIZE=16384
            break
            ;;
        *)
            warn "Invalid option. Please try again."
            ;;
    esac
done

info "You have selected $opt size. Creating a $SIZE MB container file."
info "NOTE: THIS PROCESS WILL TAKE A LONG TIME... DEPENDING ON YOUR CHOICE"
info "######    Please wait ##########"

# Create the container file with the selected size
if [ ! -f "/piusb.bin" ]; then
    sudo dd bs=1M if=/dev/zero of=/piusb.bin count=$SIZE status=progress
    sudo mkdosfs /piusb.bin -F 32 -I
    info "Created USB container file"
else
    info "USB container file already exists"
fi

# Create the mount point for the container file
MOUNT_POINT="/home/${USER}/.octoprint/uploads/resin"
if [ ! -d "${MOUNT_POINT}" ]; then
    sudo mkdir -p "${MOUNT_POINT}"
    info "Created mount point: ${MOUNT_POINT}"
fi

# Check if fstab entry already exists
if ! grep -q "/piusb.bin" /etc/fstab; then
    echo "/piusb.bin            ${MOUNT_POINT}  vfat    users,uid=${USER},gid=${USER},umask=000   0       2 " >> /etc/fstab
    info "Added fstab entry"
else
    info "fstab entry already exists"
fi

# Set proper ownership
sudo chown "${USER}:${USER}" "${MOUNT_POINT}"

# Mount the filesystem
sudo mount -a

# Handle rc.local for Bookworm (systemd-based)
if [ -f "/etc/rc.local" ]; then
    # Remove existing exit 0
    sudo sed -i '/^exit 0$/d' /etc/rc.local
    
    # Add our commands if not already present
    if ! grep -q "g_mass_storage" /etc/rc.local; then
        echo '/bin/sleep 5 
modprobe g_mass_storage file=/piusb.bin removable=1 ro=0 stall=0
exit 0' >> /etc/rc.local
        info "Added mass storage module loading to rc.local"
    else
        info "Mass storage module already configured in rc.local"
    fi
else
    # Create rc.local if it doesn't exist
    cat > /etc/rc.local << 'EOF'
#!/bin/bash
/bin/sleep 5 
modprobe g_mass_storage file=/piusb.bin removable=1 ro=0 stall=0
exit 0
EOF
    chmod +x /etc/rc.local
    info "Created rc.local file"
fi

# Handle serial getty service (might not exist in newer versions)
if systemctl is-enabled serial-getty@ttyS0 &>/dev/null; then
    sudo systemctl stop serial-getty@ttyS0
    sudo systemctl disable serial-getty@ttyS0
    info "Disabled serial getty service"
else
    info "Serial getty service not found or already disabled"
fi

# Also disable serial-getty@ttyAMA0 if it exists (common on newer Pi OS)
if systemctl is-enabled serial-getty@ttyAMA0 &>/dev/null; then
    sudo systemctl stop serial-getty@ttyAMA0
    sudo systemctl disable serial-getty@ttyAMA0
    info "Disabled serial getty AMA0 service"
fi

info ""
info "Setting up Sambashare; this could take a long time"

# Update package list first
sudo apt-get update

# Install samba and winbind
sudo apt-get install samba winbind -y

read -r -p "Enter a short description of your printer, like the model: "  model

# Check if samba share already exists
if ! grep -q "\[USB_Share\]" /etc/samba/smb.conf; then
    echo "
[USB_Share]
comment = $model
path = ${MOUNT_POINT}/
browseable = Yes
writeable = Yes
only guest = no
create mask = 0777
directory mask = 0777
public = yes
read only = no
force user = root
force group = root" >> /etc/samba/smb.conf
    info "Added Samba share configuration"
else
    info "Samba share already configured"
fi

# Restart samba service
sudo systemctl restart smbd
sudo systemctl enable smbd

info ""
info "Installation completed successfully!"
info "Your Chituboard setup is now ready for Raspbian Bookworm"

while true
do
    warn "Confirm your disk setup looks correct before rebooting"
    df -h
    
    read -r -p "Reboot now? [Y/n] " input

    case $input in
        [yY][eE][sS]|[yY])
    warn "Rebooting in 5 seconds"
    sleep 5
    sudo reboot
    break
    ;;
        [nN][oO]|[nN])
    break
            ;;
        *)
    warn "Invalid input..."
    esac
done
