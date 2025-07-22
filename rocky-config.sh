#!/bin/bash
# bash rocky-config.sh

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "=============================================="
    echo "WARNING: This script is running as root!"
    echo "=============================================="
    echo ""
    echo "This script should be run as your user."
    echo ""
    echo "If you are root please continue, if you are using sudo,"
    echo "cancel and run it again as your user."
    echo ""
    echo "Options:"
    echo "1) Continue anyway"
    echo "2) Cancel and exit"
    echo ""
    read -p "Enter your choice (1 or 2): " choice
    
    case $choice in
        1)
            echo "Continuing as root..."
            echo ""
            ;;
        2)
            echo "Exiting script. Please run as your user without sudo."
            exit 1
            ;;
        *)
            echo "Invalid choice. Exiting for safety."
            exit 1
            ;;
    esac
fi

# Ensure dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "Installing dialog..."
    sudo dnf install -y dialog
fi

# Welcome message
dialog --title "Rocky Linux Configuration" --msgbox "Welcome to the Rocky Linux Configuration Script!\n\nThis script will help you configure your Rocky Linux system.\n\nPress OK to continue." 10 60

# Configuration selection menu
exec 3>&1
SELECTED_OPTIONS=$(dialog --title "Configuration Options" \
    --checklist "Select the configuration tasks you want to perform:\n(Use SPACE to select/deselect, ENTER to confirm)" 15 70 4 \
    "hostname" "Change system hostname" off \
    "partition" "Resize/expand a partition" off \
    "bash" "Add bash aliases and functions" off \
    "update" "Update system packages" on \
    2>&1 1>&3)
exec 3>&-

# Check if user cancelled
if [ $? -ne 0 ]; then
    dialog --title "Cancelled" --msgbox "Configuration cancelled by user." 6 40
    clear
    exit 0
fi

# Set flags based on selections
CHANGE_HOSTNAME=1
RESIZE_PARTITION=1
CONFIGURE_BASH=1
UPDATE_SYSTEM=1

if [[ $SELECTED_OPTIONS == *"hostname"* ]]; then
    CHANGE_HOSTNAME=0
fi

if [[ $SELECTED_OPTIONS == *"partition"* ]]; then
    RESIZE_PARTITION=0
fi

if [[ $SELECTED_OPTIONS == *"bash"* ]]; then
    CONFIGURE_BASH=0
fi

if [[ $SELECTED_OPTIONS == *"update"* ]]; then
    UPDATE_SYSTEM=0
fi

# Initialize summary variables
SUMMARY_MESSAGES=""
HOSTNAME_STATUS="Skipped"
PARTITION_STATUS="Skipped"
BASH_STATUS="Skipped"
UPDATE_STATUS="Skipped"

# Step 1: Update and upgrade the system
if [ $UPDATE_SYSTEM -eq 0 ]; then
    # Create a function to show progress during updates
    show_update_progress() {
        local operation="$1"
        local log_file="$2"
        local title="$3"
        
        # Start the operation in background
        sudo dnf -y $operation > "$log_file" 2>&1 &
        local dnf_pid=$!
        
        # Show progress bar
        (
            echo "0"
            while kill -0 $dnf_pid 2>/dev/null; do
                # Check log file for progress indicators
                if [[ -f "$log_file" ]]; then
                    # Count completed vs total operations based on log content
                    local total_packages=$(grep -c "Installing\|Upgrading\|Removing" "$log_file" 2>/dev/null || echo "0")
                    local completed_packages=$(grep -c "Installed\|Upgraded\|Removed" "$log_file" 2>/dev/null || echo "0")
                    
                    if [[ $total_packages -gt 0 ]]; then
                        local progress=$((completed_packages * 100 / total_packages))
                        if [[ $progress -gt 100 ]]; then
                            progress=100
                        fi
                        echo "$progress"
                    else
                        # If no package info yet, show pulsing progress
                        for i in {10..90..10}; do
                            echo "$i"
                            sleep 0.5
                            kill -0 $dnf_pid 2>/dev/null || break
                        done
                    fi
                fi
                sleep 1
            done
            echo "100"
        ) | dialog --title "$title" --gauge "Processing packages...\nPlease wait while the operation completes." 8 60 0
        
        # Wait for the process to complete and get exit status
        wait $dnf_pid
        return $?
    }
    
    # Create temporary log files
    UPDATE_LOG=$(mktemp)
    UPGRADE_LOG=$(mktemp)
    
    # Perform update with progress bar
    show_update_progress "update" "$UPDATE_LOG" "System Update - Downloading and Installing Updates"
    UPDATE_EXIT_CODE=$?
    
    # Perform upgrade with progress bar
    if [[ $UPDATE_EXIT_CODE -eq 0 ]]; then
        show_update_progress "upgrade" "$UPGRADE_LOG" "System Upgrade - Installing Additional Updates"
        UPGRADE_EXIT_CODE=$?
    else
        UPGRADE_EXIT_CODE=1
    fi
    
    # Determine final status
    if [[ $UPDATE_EXIT_CODE -eq 0 && $UPGRADE_EXIT_CODE -eq 0 ]]; then
        # Count updated packages for summary
        UPDATED_COUNT=$(grep -c "Upgraded\|Installed" "$UPDATE_LOG" "$UPGRADE_LOG" 2>/dev/null || echo "0")
        if [[ $UPDATED_COUNT -gt 0 ]]; then
            UPDATE_STATUS="Completed successfully ($UPDATED_COUNT packages updated)"
        else
            UPDATE_STATUS="Completed successfully (system already up to date)"
        fi
    else
        UPDATE_STATUS="Failed - check system logs"
        # Show error details if available
        if [[ -s "$UPDATE_LOG" ]]; then
            ERROR_MSG=$(tail -5 "$UPDATE_LOG" | head -3)
            UPDATE_STATUS="Failed - $ERROR_MSG"
        fi
    fi
    
    # Clean up temporary files
    rm -f "$UPDATE_LOG" "$UPGRADE_LOG"
else
    UPDATE_STATUS="Skipped by user"
fi

# Step 2: Configure hostname if requested
if [ $CHANGE_HOSTNAME -eq 0 ]; then
    # Prompt for hostname and domain using a single form
    exec 3>&1
    form_data=$(dialog --title "Network Configuration" --form "Enter your hostname and domain:" 15 80 0 \
        "Hostname:" 1 1 "" 1 12 40 0 \
        "Domain:" 2 1 "" 2 12 40 0 \
        2>&1 1>&3)
    exec 3>&-

    # Check if user cancelled
    if [ $? -ne 0 ]; then
        HOSTNAME_STATUS="Cancelled by user"
    else
        new_hostname=$(echo "$form_data" | sed -n 1p)
        domain=$(echo "$form_data" | sed -n 2p)

        # Validate input
        if [[ -z "$new_hostname" ]]; then
            HOSTNAME_STATUS="Failed - hostname cannot be empty"
        elif [[ -z "$domain" ]]; then
            HOSTNAME_STATUS="Failed - domain cannot be empty"
        else
            # Combine hostname and domain
            FQDN="${new_hostname}.${domain}"

            # Confirm configuration
            dialog --title "Confirm Configuration" --yesno "Hostname: $new_hostname\nDomain: $domain\nFQDN: $FQDN\n\nProceed with this configuration?" 10 50

            if [ $? -eq 0 ]; then
                # Update /etc/hosts
                dialog --title "Network Configuration" --infobox "Updating /etc/hosts and hostname..." 5 40

                # Backup original hosts file
                sudo cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)

                # Remove any existing entries for this hostname/FQDN
                sudo sed -i "/\s$new_hostname\s*$/d" /etc/hosts
                sudo sed -i "/\s$FQDN\s*$/d" /etc/hosts

                # Add new entry
                echo "127.0.0.1   $FQDN $new_hostname" | sudo tee -a /etc/hosts > /dev/null

                # Set hostname
                if sudo hostnamectl set-hostname "$new_hostname"; then
                    HOSTNAME_STATUS="Changed to $new_hostname (FQDN: $FQDN)"
                else
                    HOSTNAME_STATUS="Failed to set hostname"
                fi
            else
                HOSTNAME_STATUS="Cancelled by user"
            fi
        fi
    fi
else
    HOSTNAME_STATUS="Skipped by user"
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
        PARTITION_STATUS="Failed - no partitions found"
    else
        # Show partition selection menu
        exec 3>&1
        SELECTED_PARTITION=$(dialog --title "Select Partition to Expand" \
            --menu "Choose the partition you want to expand:" 15 100 8 \
            $PARTITION_LIST \
            2>&1 1>&3)
        exec 3>&-
        
        if [ $? -eq 0 ] && [[ -n "$SELECTED_PARTITION" ]]; then
            # Confirm selection
            PARTITION_INFO=$(df -h "$SELECTED_PARTITION" | tail -1)
            dialog --title "Confirm Partition Expansion" --yesno "You selected: $SELECTED_PARTITION\n\nCurrent info:\n$PARTITION_INFO\n\nProceed with expansion?" 12 70
            
            if [ $? -eq 0 ]; then
                dialog --title "Disk Management" --infobox "Analyzing and expanding partition: $SELECTED_PARTITION..." 5 80
                
                # Get device information for selected partition
                DISK_DEV=$(lsblk -no pkname "$SELECTED_PARTITION" 2>/dev/null)
                PART_NUM=$(echo "$SELECTED_PARTITION" | grep -o '[0-9]*$')
                
                if [[ -z "$DISK_DEV" ]] || [[ -z "$PART_NUM" ]]; then
                    PARTITION_STATUS="Failed - could not determine disk/partition info for $SELECTED_PARTITION"
                else
                    # Check if growpart is available
                    if ! command -v growpart &> /dev/null; then
                        sudo dnf install -y cloud-utils-growpart &>/dev/null
                    fi
                    
                    # Grow the partition
                    if sudo growpart "/dev/$DISK_DEV" "$PART_NUM" 2>/dev/null; then
                        # Resize the filesystem
                        FS_TYPE=$(df -T "$SELECTED_PARTITION" | tail -1 | awk '{print $2}')
                        case "$FS_TYPE" in
                            "xfs")
                                MOUNT_POINT=$(df "$SELECTED_PARTITION" | tail -1 | awk '{print $6}')
                                if sudo xfs_growfs "$MOUNT_POINT" 2>/dev/null; then
                                    PARTITION_STATUS="Successfully expanded $SELECTED_PARTITION (XFS)"
                                else
                                    PARTITION_STATUS="Partition expanded but filesystem resize failed (XFS)"
                                fi
                                ;;
                            "ext4")
                                if sudo resize2fs "$SELECTED_PARTITION" 2>/dev/null; then
                                    PARTITION_STATUS="Successfully expanded $SELECTED_PARTITION (EXT4)"
                                else
                                    PARTITION_STATUS="Partition expanded but filesystem resize failed (EXT4)"
                                fi
                                ;;
                            *)
                                PARTITION_STATUS="Partition expanded but unsupported filesystem ($FS_TYPE)"
                                ;;
                        esac
                    else
                        PARTITION_STATUS="Already at maximum size or expansion failed"
                    fi
                fi
            else
                PARTITION_STATUS="Cancelled by user"
            fi
        else
            PARTITION_STATUS="Cancelled - no partition selected"
        fi
    fi
else
    PARTITION_STATUS="Skipped by user"
fi

# Step 4: Configure bash aliases and functions if requested
if [ $CONFIGURE_BASH -eq 0 ]; then
    dialog --title "Bash Configuration" --infobox "Configuring bash aliases and functions..." 5 50
    
    # Define the bash configuration content
    BASH_CONFIG='
# Aliases
alias ll='\''ls -lah'\''
alias so='\''source venv/bin/activate'\''

# My functions
# Make Python virtual environment and activate it and upgrade pip
mkenv() {
  python -m venv venv && \
  source venv/bin/activate && \
  pip install --upgrade pip
}'
    
    # Get all users with home directories (excluding system users)
    USER_LIST=""
    while IFS=: read -r username _ uid _ _ home _; do
        # Include users with UID >= 1000 (regular users) and root
        if [[ $uid -ge 1000 || $uid -eq 0 ]] && [[ -d "$home" ]]; then
            USER_LIST="$USER_LIST$username \"Home: $home\" "
        fi
    done < /etc/passwd
    
    if [[ -z "$USER_LIST" ]]; then
        BASH_STATUS="Failed - no user home directories found"
    else
        # Show user selection menu
        exec 3>&1
        SELECTED_USER=$(dialog --title "Select User for Bash Configuration" \
            --menu "Choose which user's .bashrc to configure:" 15 120 8 \
            $USER_LIST \
            2>&1 1>&3)
        exec 3>&-
        
        if [ $? -eq 0 ] && [[ -n "$SELECTED_USER" ]]; then
            # Get the user's home directory
            USER_HOME=$(getent passwd "$SELECTED_USER" | cut -d: -f6)
            BASHRC_FILE="$USER_HOME/.bashrc"
            
            # Confirm configuration
            dialog --title "Confirm Bash Configuration" --yesno "Configure .bashrc for user: $SELECTED_USER\nFile: $BASHRC_FILE\n\nThis will add aliases and functions to the .bashrc file.\n\nProceed?" 10 60
            
            if [ $? -eq 0 ]; then
                # Check if we can write to the target file/directory
                if [[ ! -w "$(dirname "$BASHRC_FILE")" ]] && [[ "$SELECTED_USER" != "$(whoami)" ]]; then
                    BASH_STATUS="Failed - insufficient permissions for $BASHRC_FILE"
                else
                    # Backup existing .bashrc if it exists
                    if [[ -f "$BASHRC_FILE" ]]; then
                        cp "$BASHRC_FILE" "$BASHRC_FILE.backup.$(date +%Y%m%d_%H%M%S)"
                    fi
                    
                    # Check if our configuration already exists
                    if grep -q "# Aliases" "$BASHRC_FILE" 2>/dev/null && grep -q "alias ll=" "$BASHRC_FILE" 2>/dev/null; then
                        BASH_STATUS="Already configured - skipped to avoid duplicates"
                    else
                        # Add our configuration to .bashrc
                        echo "$BASH_CONFIG" >> "$BASHRC_FILE"
                        
                        # Set proper ownership if we have permission (running as root or same user)
                        if [[ "$(whoami)" == "root" ]] || [[ "$SELECTED_USER" == "$(whoami)" ]]; then
                            if [[ "$(whoami)" == "root" ]]; then
                                chown "$SELECTED_USER:$SELECTED_USER" "$BASHRC_FILE"
                            fi
                            BASH_STATUS="Successfully configured for user $SELECTED_USER"
                        else
                            BASH_STATUS="Configured for $SELECTED_USER (ownership may need adjustment)"
                        fi
                    fi
                fi
            else
                BASH_STATUS="Cancelled by user"
            fi
        else
            BASH_STATUS="Cancelled - no user selected"
        fi
    fi
else
    BASH_STATUS="Skipped by user"
fi

# Get final system information
current_hostname=$(hostname)
current_fqdn=$(hostname -f 2>/dev/null || echo "Not set")
root_fs_info=$(df -h / | tail -1 | awk '{print $2 " total, " $3 " used, " $4 " available"}')

# Create comprehensive summary
SUMMARY_TEXT="ROCKY LINUX CONFIGURATION SUMMARY

SYSTEM INFORMATION:
• Hostname: $current_hostname
• FQDN: $current_fqdn
• Root filesystem: $root_fs_info

CONFIGURATION RESULTS:
• System Update: $UPDATE_STATUS
• Hostname Configuration: $HOSTNAME_STATUS
• Partition Management: $PARTITION_STATUS
• Bash Configuration: $BASH_STATUS

Configuration completed at: $(date)

Note: A system reboot is recommended to ensure 
all changes take effect properly."

# Display comprehensive summary
dialog --title "Configuration Summary" --msgbox "$SUMMARY_TEXT" 20 80

# Ask about reboot with updated options
dialog --title "Next Steps" --menu "Configuration is complete. What would you like to do next?" 12 60 3 \
    "reboot" "Reboot system now (recommended)" \
    "exit" "Exit without rebooting" \
    "summary" "View summary again" 2>/tmp/reboot_choice

REBOOT_CHOICE=$(cat /tmp/reboot_choice 2>/dev/null)
rm -f /tmp/reboot_choice

case "$REBOOT_CHOICE" in
    "reboot")
        dialog --title "Rebooting" --infobox "System will reboot in 3 seconds..." 5 40
        sleep 3
        sudo reboot
        ;;
    "summary")
        dialog --title "Configuration Summary" --msgbox "$SUMMARY_TEXT" 20 80
        dialog --title "Complete" --msgbox "Configuration complete. Please remember to reboot when convenient." 8 60
        ;;
    *)
        dialog --title "Complete" --msgbox "Configuration complete. Please remember to reboot when convenient." 8 60
        ;;
esac
clear
