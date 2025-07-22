#!/bin/bash

# Ensure dialog is installed
sudo dnf install -y dialog

# Step 1: Update and upgrade the system
dialog --infobox "Updating system..." 5 40
sudo dnf -y update &>/dev/null
sudo dnf -y upgrade &>/dev/null

# Step 2: Prompt for hostname and domain using a single form
exec 3>&1
form_data=$(dialog --form "Enter your hostname and domain:" 15 50 0     "Hostname:" 1 1 "" 1 10 30 0     "Domain:" 2 1 "" 2 10 30 0 2>&1 1>&3)
exec 3>&-

new_hostname=$(echo "$form_data" | sed -n 1p)
domain=$(echo "$form_data" | sed -n 2p)

# Step 3: Define packages and descriptions
declare -A package_descriptions=(
    [wget]="Command-line file downloader"
    [vim]="Text editor"
    [git]="Version control system"
    [htop]="Interactive process viewer"
    [epel-release]="Extra Packages for Enterprise Linux repository"
    [tmux]="Terminal multiplexer"
    [net-tools]="Legacy networking tools"
    [curl]="Data transfer tool"
    [bat]="Cat clone with syntax highlighting"
    [fd-find]="Fast alternative to 'find'"
    [ncdu]="Disk usage analyzer"
    [pv]="Monitor data through a pipe"
    [tldr]="Simplified man pages"
    [parted]="Partition manipulation tool"
    [lvm2]="Logical Volume Manager utilities"
    [gdisk]="GPT partitioning tool"
    [tree]="Recursively list the content of a directory"
)

# Step 4: Build checklist options
checklist_items=()
for pkg in "${!package_descriptions[@]}"; do
    checklist_items+=("$pkg" "${package_descriptions[$pkg]}" "on")
done

# Step 5: Show checklist
exec 3>&1
selected=$(dialog --checklist "Select packages to install:" 20 70 15 "${checklist_items[@]}" 2>&1 1>&3)
exec 3>&-

# Step 6: Install selected packages with progress bar
packages=($selected)
total_packages=${#packages[@]}
(
for i in "${!packages[@]}"; do
    echo "$((i * 100 / total_packages))"
    sudo dnf install -y "${packages[$i]}" &>/dev/null
done
echo "100"
) | dialog --gauge "Installing selected packages..." 10 70 0

# Step 7: Set hostname
sudo hostnamectl set-hostname "$new_hostname"

# Step 8: Update /etc/hosts
sudo sed -i "s/127.0.0.1.*/127.0.0.1   $new_hostname.$domain $new_hostname localhost localhost.localdomain localhost4 localhost4.localdomain4/" /etc/hosts
sudo sed -i "s/::1.*/::1         $new_hostname.$domain $new_hostname localhost localhost.localdomain localhost6 localhost6.localdomain6/" /etc/hosts

# Add server's actual IP to /etc/hosts
ip_address=$(hostname -I | awk '{print $1}')
if ! grep -q "$ip_address" /etc/hosts; then
    echo "$ip_address   $new_hostname.$domain $new_hostname" | sudo tee -a /etc/hosts > /dev/null
fi

# Step 9: Check disk and partition size, then resize if requested
DISK="/dev/sda"
PARTITION="3"
PARTITION_PATH="${DISK}${PARTITION}"

# Get disk and partition information
DISK_SIZE=$(sudo fdisk -l $DISK | grep "Disk $DISK" | awk '{print $3 " " $4}' | tr -d ',')
PARTITION_SIZE=$(sudo fdisk -l $DISK | grep "$PARTITION_PATH" | awk '{print $5 " " $6}')
LVM_FREE=$(sudo vgs --noheadings --units g -o vg_free | tr -d ' ' | tr -d 'g')

# Show disk information and ask for confirmation
exec 3>&1
RESIZE_CONFIRM=$(dialog --title "Disk Resize Confirmation" --yesno "Current disk size: $DISK_SIZE\nCurrent partition size: $PARTITION_SIZE\nLVM free space: ${LVM_FREE}G\n\nWould you like to expand the partition to use all available space?" 12 60 2>&1 1>&3)
RESIZE_STATUS=$?
exec 3>&-

# Only resize if user confirmed (status 0 means "yes")
if [ $RESIZE_STATUS -eq 0 ]; then
    (
    echo "10"
    sudo gdisk $DISK <<EOF
d
$PARTITION
n
$PARTITION


8E00
w
Y
EOF

    sleep 10
    echo "50"
    sudo partprobe $DISK
    sudo pvresize $PARTITION_PATH
    echo "70"
    sudo lvextend -l +100%FREE /dev/rl/root
    echo "90"
    sudo xfs_growfs /
    echo "100"
    ) | dialog --gauge "Resizing disk and extending filesystem..." 10 70 0
    # Set flag to indicate resize was performed
    RESIZE_PERFORMED=true
else
    dialog --msgbox "Disk resize operation skipped." 5 40
    # Set flag to indicate resize was not performed
    RESIZE_PERFORMED=false
fi

# Step 10: Add aliases
grep -qxF "alias ll='ls -lah'" ~/.bashrc || echo -e "
# better than just ls
alias ll='ls -lah'" >> ~/.bashrc
grep -qxF "alias mkenv='python -m venv venv && source venv/bin/activate && python -m pip install --upgrade pip'" ~/.bashrc || echo -e "
# Creates a python venv and upgrades pip
alias mkenv='python -m venv venv && source venv/bin/activate && python -m pip install --upgrade pip'" >> ~/.bashrc
source ~/.bashrc

# Step 11: Display summary
fqdn=$(hostname --fqdn)
ip_address=$(hostname -I | awk '{print $1}')
# Capture disk usage information
disk_usage=$(df -h /)
summary="System updated and upgraded.
Hostname: $fqdn
IP Address: $ip_address

Installed packages:
"

for pkg in "${packages[@]}"; do
    summary+="$pkg - ${package_descriptions[$pkg]}
"
done

# Add disk resize information to summary based on whether it was performed
if [ "$RESIZE_PERFORMED" = true ]; then
    summary+="
Disk resized and filesystem extended."
else
    summary+="
Disk resize operation was skipped."
fi

summary+="
Aliases added:
  ll    - Outputs the result of 'ls -lah'
  mkenv - Creates a Python venv, updates pip, and activates the venv

Disk Usage:
$disk_usage"

dialog --msgbox "$summary" 25 80
clear
