#!/bin/bash
# sudo bash rocky-config.sh

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   dialog --title "Error" --msgbox "This script must be run as root. Try using sudo." 8 50
   exit 1
fi

# Ensure dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "Installing dialog..."
    sudo dnf install -y dialog
fi

# Welcome message
dialog --title "Rocky Linux Configuration" --msgbox "Welcome to the Rocky Linux Configuration Script!\n\nThis script will help you configure your Rocky Linux system.\n\nPress OK to continue." 10 60

# Ask if user wants to change hostname
dialog --title "Hostname Configuration" --yesno "Do you want to change the system hostname?\n\nCurrent hostname: $(hostname)" 8 50
CHANGE_HOSTNAME=$?

# Ask if user wants to resize partition
dialog --title "Partition Management" --yesno "Do you want to resize/expand a partition?" 7 50
RESIZE_PARTITION=$?

# Step 1: Update and upgrade the system
dialog --title "System Update" --infobox "Updating system packages...\nThis may take several minutes." 6 50
sudo dnf -y update &>/dev/null
sudo dnf -y upgrade &>/dev/null

dialog --title "System Update" --msgbox "System update completed successfully!" 6 50

# Step 2: Configure hostname if requested
if [ $CHANGE_HOSTNAME -eq 0 ]; then
    # Prompt for hostname and domain using a single form
    exec 3>&1
    form_data=$(dialog --title "Network Configuration" --form "Enter your hostname and domain:" 15 60 0 \
        "Hostname:" 1 1 "" 1 12 40 0 \
        "Domain:" 2 1 "" 2 12 40 0 \
        2>&1 1>&3)
    exec 3>&-

    # Check if user cancelled
    if [ $? -ne 0 ]; then
        dialog --title "Cancelled" --msgbox "Hostname configuration cancelled by user." 6 40
    else
        new_hostname=$(echo "$form_data" | sed -n 1p)
        domain=$(echo "$form_data" | sed -n 2p)

        # Validate input
        if [[ -z "$new_hostname" ]]; then
            dialog --title "Error" --msgbox "Hostname cannot be empty. Skipping hostname configuration." 6 50
        elif [[ -z "$domain" ]]; then
            dialog --title "Error" --msgbox "Domain cannot be empty. Skipping hostname configuration." 6 50
        else
            # Combine hostname and domain
            FQDN="${new_hostname}.${domain}"

            # Confirm configuration
            dialog --title "Confirm Configuration" --yesno "Hostname: $new_hostname\nDomain: $domain\nFQDN: $FQDN\n\nProceed with this configuration?" 10 50

            if [ $? -eq 0 ]; then
                # Update /etc/hosts
                dialog --title "Network Configuration" --infobox "Updating /etc/hosts file..." 5 40

                # Backup original hosts file
                cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)

                # Remove any existing entries for this hostname/FQDN
                sed -i "/\s$new_hostname\s*$/d" /etc/hosts
                sed -i "/\s$FQDN\s*$/d" /etc/hosts

                # Add new entry
                echo "127.0.0.1   $FQDN $new_hostname" >> /etc/hosts

                dialog --title "Network Configuration" --msgbox "/etc/hosts updated successfully!" 6 50

                # Set hostname
                hostnamectl set-hostname "$new_hostname"
            else
                dialog --title "Cancelled" --msgbox "Hostname configuration cancelled by user." 6 40
            fi
        fi
    fi
else
    dialog --title "Hostname" --msgbox "Keeping current hostname: $(hostname)" 6 50
fi

# Step 3: Handle partition resizing if requested
if [ $RESIZE_PARTITION -eq 0 ]; then
    dialog --title "Partition Management" --infobox "Scanning available partitions..." 5 40
    
    # Get list of all partitions with their information
    PARTITION_LIST=""
    while IFS= read -r line; do
        if [[ $line =~ ^/dev/ ]]; then
            DEVICE=$(echo "$line" | awk '{print $1}')
            SIZE=$(echo "$line" | awk '{print $2}')
            USED=$(echo "$line" | awk '{print $3}')
            AVAIL=$(echo "$line" | awk '{print $4}')
            MOUNT=$(echo "$line" | awk '{print $6}')
            
            # Skip if mount point is empty
            if [[ -n "$MOUNT" ]]; then
                PARTITION_LIST="$PARTITION_LIST$DEVICE \"Size:$SIZE Used:$USED Avail:$AVAIL Mount:$MOUNT\" "
            fi
        fi
    done < <(df -h | grep "^/dev/")
    
    if [[ -z "$PARTITION_LIST" ]]; then
        dialog --title "Error" --msgbox "No partitions found for resizing." 6 40
    else
        # Show partition selection menu
        exec 3>&1
        SELECTED_PARTITION=$(dialog --title "Select Partition to Expand" \
            --menu "Choose the partition you want to expand:" 15 80 8 \
            $PARTITION_LIST \
            2>&1 1>&3)
        exec 3>&-
        
        if [ $? -eq 0 ] && [[ -n "$SELECTED_PARTITION" ]]; then
            # Confirm selection
            PARTITION_INFO=$(df -h "$SELECTED_PARTITION" | tail -1)
            dialog --title "Confirm Partition Expansion" --yesno "You selected: $SELECTED_PARTITION\n\nCurrent info:\n$PARTITION_INFO\n\nProceed with expansion?" 12 70
            
            if [ $? -eq 0 ]; then
                dialog --title "Disk Management" --infobox "Analyzing partition: $SELECTED_PARTITION..." 5 50
                
                # Get device information for selected partition
                DISK_DEV=$(lsblk -no pkname "$SELECTED_PARTITION" 2>/dev/null)
                PART_NUM=$(echo "$SELECTED_PARTITION" | grep -o '[0-9]*$')
                
                if [[ -z "$DISK_DEV" ]] || [[ -z "$PART_NUM" ]]; then
                    dialog --title "Error" --msgbox "Could not determine disk or partition number for $SELECTED_PARTITION." 8 60
                else
                    dialog --title "Disk Management" --infobox "Device: $SELECTED_PARTITION\nDisk: /dev/$DISK_DEV\nPartition: $PART_NUM\n\nExpanding partition..." 8 50
                    
                    # Check if growpart is available
                    if ! command -v growpart &> /dev/null; then
                        dialog --title "Disk Management" --infobox "Installing cloud-utils-growpart..." 5 40
                        dnf install -y cloud-utils-growpart &>/dev/null
                    fi
                    
                    # Grow the partition
                    if growpart "/dev/$DISK_DEV" "$PART_NUM" 2>/dev/null; then
                        dialog --title "Disk Management" --infobox "Partition grown successfully.\nResizing filesystem..." 6 40
                        
                        # Resize the filesystem
                        FS_TYPE=$(df -T "$SELECTED_PARTITION" | tail -1 | awk '{print $2}')
                        case "$FS_TYPE" in
                            "xfs")
                                MOUNT_POINT=$(df "$SELECTED_PARTITION" | tail -1 | awk '{print $6}')
                                if xfs_growfs "$MOUNT_POINT" 2>/dev/null; then
                                    dialog --title "Disk Management" --msgbox "XFS filesystem resized successfully!" 6 50
                                else
                                    dialog --title "Error" --msgbox "Failed to resize XFS filesystem." 6 50
                                fi
                                ;;
                            "ext4")
                                if resize2fs "$SELECTED_PARTITION" 2>/dev/null; then
                                    dialog --title "Disk Management" --msgbox "EXT4 filesystem resized successfully!" 6 50
                                else
                                    dialog --title "Error" --msgbox "Failed to resize EXT4 filesystem." 6 50
                                fi
                                ;;
                            *)
                                dialog --title "Warning" --msgbox "Unsupported filesystem type: $FS_TYPE\nManual resize may be required." 8 50
                                ;;
                        esac
                    else
                        dialog --title "Info" --msgbox "Partition is already at maximum size or expansion failed." 8 50
                    fi
                fi
            else
                dialog --title "Cancelled" --msgbox "Partition expansion cancelled." 6 40
            fi
        else
            dialog --title "Cancelled" --msgbox "No partition selected for expansion." 6 40
        fi
    fi
else
    dialog --title "Partition Management" --msgbox "Skipping partition resizing as requested." 6 50
fi

# Get final system information
current_hostname=$(hostname)
current_fqdn=$(hostname -f 2>/dev/null || echo "Not set")
root_fs_info=$(df -h / | tail -1 | awk '{print $2 " total, " $3 " used, " $4 " available"}')

# Final status
dialog --title "Configuration Complete" --msgbox "Rocky Linux Configuration Complete!\n\nHostname: $current_hostname\nFQDN: $current_fqdn\nRoot filesystem: $root_fs_info\n\nSystem configuration completed successfully!" 14 70

# Ask about reboot
dialog --title "Reboot Required" --yesno "Configuration is complete. It's recommended to reboot the system to ensure all changes take effect.\n\nWould you like to reboot now?" 10 60

if [ $? -eq 0 ]; then
    dialog --title "Rebooting" --infobox "System will reboot in 3 seconds..." 5 40
    sleep 3
    reboot
else
    dialog --title "Complete" --msgbox "Configuration complete. Please remember to reboot when convenient." 8 50
fi
clear