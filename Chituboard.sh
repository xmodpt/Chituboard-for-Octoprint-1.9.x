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
             Ver. 2      by CrAzZyRaBbIt           

Created By Vikram Sarkhel AKA: rudetrooper
    https://github.com/rudetrooper/Octoprint-Chituboard                                                                                       
EOF

# Exit on error
set -euo pipefail

# filename: Chituboard.sh
# modified version of Kenzillla's Mariner+Samba Auto-Installer
# Changed by CrAzY RaBbit 2024

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
info "NOTE: The bigger your choice... the longger it will take"
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
info "NOTE: THIS PROCESS WILL TAKE A LONG TIME... DEPENDING OF YOUR CHOICE"
info "######    Please wait ##########"


# Create the container file with the selected size
sudo dd bs=1M if=/dev/zero of=/piusb.bin count=$SIZE
sudo mkdosfs /piusb.bin -F 32 -I

# Create the mount point for the container file
sudo mkdir /home/"${USER}"/.octoprint/uploads/resin
echo "/piusb.bin            /home/${USER}/.octoprint/uploads/resin  vfat    users,uid=${USER},gid=${USER},umask=000   0       2 " >> /etc/fstab

sudo mount -a

sudo sed -i 's/exit 0//g' /etc/rc.local

echo '/bin/sleep 5 
modprobe g_mass_storage file=/piusb.bin removable=1 ro=0 stall=0
exit 0' >> /etc/rc.local

sudo systemctl stop serial-getty@ttyS0
sudo systemctl disable serial-getty@ttyS0

info ""
info "Setting up Sambashare; this could take a long time"
sudo apt-get install samba winbind -y

read -r -p "Enter a short description of your printer, like the model: "  model
echo "[USB_Share]
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
force group = root" >> /etc/samba/smb.conf

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
    break
            ;;
        *)
    warn "Invalid input..."
    esac
done
