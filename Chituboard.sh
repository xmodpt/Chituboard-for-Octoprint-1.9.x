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

Created By Vikram Sarkhel AKA: rudetrooper
    https://github.com/rudetrooper/Octoprint-Chituboard                                                                                       
EOF

# Exit on error
set -euo pipefail

# filename: Chituboard.sh
# modified version of Kenzillla's Mariner+Samba Auto-Installer
# Changed by CrAzY RaBbit 2024
# Updated with custom size option

function info { echo -e "\e[32m[info] $*\e[39m"; }
function warn  { echo -e "\e[33m[warn] $*\e[39m"; }
function error { echo -e "\e[31m[error] $*\e[39m"; exit 1; }

# Function to validate size input
validate_size() {
    local size=$1
    # Check if it's a number
    if ! [[ "$size" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    # Check minimum size (100MB)
    if [ "$size" -lt 100 ]; then
        warn "Size must be at least 100 MB"
        return 1
    fi
    # Check maximum size (64GB = 65536MB)
    if [ "$size" -gt 65536 ]; then
        warn "Size must be no more than 64 GB (65536 MB)"
        return 1
    fi
    return 0
}

# Function to check available disk space
check_disk_space() {
    local required_size=$1
    local available_space
    available_space=$(df /home | awk 'NR==2 {print int($4/1024)}') # Convert to MB
    
    info "Required space: ${required_size} MB"
    info "Available space: ${available_space} MB"
    
    if [ "$required_size" -gt "$available_space" ]; then
        error "Not enough disk space! Required: ${required_size}MB, Available: ${available_space}MB"
    fi
}

if ! [ "$(id -u)" = 0 ]; then
    warn "This script needs to be run as root." >&2
    exit 1
fi

info
info "Welcome to Octoprint+Samba Auto-Installer!"
sleep .1
info "..."

sleep 1

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

info
info "Setting up Chituboard prerequisites"
echo "dtoverlay=dwc2,dr_mode=peripheral" >> /boot/config.txt
echo "enable_uart=1" >> /boot/config.txt
sudo sed -i 's/console=serial0,115200 //g' /boot/cmdline.txt
echo -n " modules-load=dwc2" >> /boot/cmdline.txt

# Setup container file for storing uploaded files
info
info "Setting up Pi-USB; this could take several minutes"

# Present a menu for the user to select the size
info "Select the size of the storage:"
info "NOTE: The bigger your choice... the longer it will take"
info ""
options=("4GB (4096 MB)" "8GB (8192 MB)" "16GB (16384 MB)" "Custom Size")
PS3="Enter your choice (1-4): "
select opt in "${options[@]}"
do
    case $opt in
        "4GB (4096 MB)")
            SIZE=4096
            SIZE_LABEL="4GB"
            break
            ;;
        "8GB (8192 MB)")
            SIZE=8192
            SIZE_LABEL="8GB"
            break
            ;;
        "16GB (16384 MB)")
            SIZE=16384
            SIZE_LABEL="16GB"
            break
            ;;
        "Custom Size")
            info ""
            info "Custom Size Selection"
            info "===================="
            info "Enter size in MB (megabytes)"
            info "Minimum: 100 MB"
            info "Maximum: 65536 MB (64 GB)"
            info ""
            info "Common sizes for reference:"
            info "  1 GB = 1024 MB"
            info "  2 GB = 2048 MB"
            info "  4 GB = 4096 MB"
            info "  8 GB = 8192 MB"
            info "  16 GB = 16384 MB"
            info "  32 GB = 32768 MB"
            info "  64 GB = 65536 MB"
            info ""
            
            while true; do
                read -r -p "Enter custom size in MB: " custom_size
                if validate_size "$custom_size"; then
                    SIZE="$custom_size"
                    SIZE_LABEL="${custom_size}MB"
                    break
                else
                    warn "Invalid size. Please enter a number between 100 and 65536."
                fi
            done
            break
            ;;
        *)
            warn "Invalid option. Please try again."
            ;;
    esac
done

info "You have selected $SIZE_LABEL size. Creating a $SIZE MB container file."

# Check available disk space before proceeding
check_disk_space "$SIZE"

info "NOTE: THIS PROCESS WILL TAKE A LONG TIME... DEPENDING ON YOUR CHOICE"
info "Estimated time for $SIZE_LABEL:"
if [ "$SIZE" -le 1024 ]; then
    info "  Expected time: 1-3 minutes"
elif [ "$SIZE" -le 4096 ]; then
    info "  Expected time: 3-10 minutes"
elif [ "$SIZE" -le 8192 ]; then
    info "  Expected time: 10-20 minutes"
elif [ "$SIZE" -le 16384 ]; then
    info "  Expected time: 20-40 minutes"
else
    info "  Expected time: 40+ minutes (large custom size)"
fi

info ""
info "######    Please wait - Creating ${SIZE_LABEL} storage file ##########"

# Create the container file with the selected size
if ! sudo dd bs=1M if=/dev/zero of=/piusb.bin count="$SIZE" status=progress; then
    error "Failed to create storage file. Check disk space and permissions."
fi

info "Storage file created successfully. Formatting..."

if ! sudo mkdosfs /piusb.bin -F 32 -I; then
    error "Failed to format storage file."
fi

info "Storage file formatted successfully."

# Create the mount point for the container file
sudo mkdir -p /home/"${USER}"/.octoprint/uploads/resin

# Add to fstab if not already present
FSTAB_LINE="/piusb.bin            /home/${USER}/.octoprint/uploads/resin  vfat    users,uid=${USER},gid=${USER},umask=000   0       2"
if ! grep -q "/piusb.bin" /etc/fstab; then
    echo "$FSTAB_LINE" >> /etc/fstab
    info "Added storage mount to /etc/fstab"
else
    warn "Storage mount already exists in /etc/fstab"
fi

if ! sudo mount -a; then
    error "Failed to mount storage. Check /etc/fstab configuration."
fi

info "Storage mounted successfully at /home/${USER}/.octoprint/uploads/resin"

# Update rc.local for USB gadget mode
sudo sed -i 's/exit 0//g' /etc/rc.local

RC_LOCAL_CONTENT='/bin/sleep 5 
modprobe g_mass_storage file=/piusb.bin removable=1 ro=0 stall=0
exit 0'

if ! grep -q "g_mass_storage" /etc/rc.local; then
    echo "$RC_LOCAL_CONTENT" >> /etc/rc.local
    info "Added USB mass storage configuration to /etc/rc.local"
else
    warn "USB mass storage configuration already exists in /etc/rc.local"
fi

# Disable serial console
sudo systemctl stop serial-getty@ttyS0
sudo systemctl disable serial-getty@ttyS0

info ""
info "Setting up Samba share; this could take a long time"
if ! sudo apt-get update; then
    warn "Failed to update package list, continuing anyway..."
fi

if ! sudo apt-get install samba winbind -y; then
    error "Failed to install Samba. Check your internet connection."
fi

read -r -p "Enter a short description of your printer, like the model: " model

SAMBA_CONFIG="[USB_Share]
comment = $model
path = /home/${USER}/.octoprint/uploads/resin/
browseable = Yes
writeable = Yes
only guest = no
create mask = 0777
directory mask = 0777
public = yes
read only = no
force user = root
force group = root"

if ! grep -q "\[USB_Share\]" /etc/samba/smb.conf; then
    echo "$SAMBA_CONFIG" >> /etc/samba/smb.conf
    info "Added Samba share configuration"
else
    warn "Samba share configuration already exists"
fi

info ""
info "Installation Summary:"
info "===================="
info "✓ USB Storage Size: $SIZE_LABEL"
info "✓ Mount Point: /home/${USER}/.octoprint/uploads/resin"
info "✓ Samba Share: Configured for '$model'"
info "✓ USB Gadget Mode: Enabled"
info "✓ Serial Console: Disabled"
info ""

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
            info "Reboot skipped. You will need to reboot manually for changes to take effect."
            break
            ;;
        *)
            warn "Invalid input... Please enter Y or N"
            ;;
    esac
done