# Rocky Linux Configuration Scripts

A collection of interactive bash scripts designed to streamline the setup and configuration of Rocky Linux systems. These scripts provide user-friendly dialog-based interfaces for common system administration tasks.

## Scripts Overview

### 🔧 rocky-config.sh
**Interactive System Configuration Tool**

A comprehensive system configuration script that provides a dialog-based interface for essential Rocky Linux setup tasks.

**Features:**
- System package updates and upgrades
- Hostname and FQDN configuration with `/etc/hosts` management
- Interactive partition expansion with filesystem resizing
- Support for XFS and EXT4 filesystems
- Automatic backup of configuration files
- Optional system reboot after configuration

**Usage:**
```bash
sudo bash rocky-config.sh
```

**Requirements:**
- Must be run as root (uses sudo)
- Automatically installs `dialog` if not present
- Requires `cloud-utils-growpart` for partition expansion (auto-installed)

---

### 🎨 rocky-motd.sh
**Custom Message of the Day (MOTD)**

A colorful and informative MOTD script that displays system information upon login.

**Features:**
- Displays hostname, FQDN, and IP address
- Shows OS version and Python version
- Lists Cockpit web interface URLs
- Shows user-installed packages in a formatted table
- Colorized output with emojis for better readability

**Installation:**
```bash
sudo cp rocky-motd.sh /etc/profile.d/motd.sh
sudo chmod +x /etc/profile.d/motd.sh
```

**What it displays:**
- System hostname and network information
- Cockpit web interface access URLs
- Python version information
- User-installed packages (formatted in columns)
- Fun footer message

---

### 🚀 rocky-setup.sh
**Automated System Setup and Package Installation**

A streamlined setup script for new Rocky Linux installations with package selection and system configuration.

**Features:**
- System updates and upgrades
- Interactive hostname and domain configuration
- Package selection via checkbox interface
- Automatic partition expansion (optional)
- Useful bash aliases setup
- Comprehensive setup summary

**Usage:**
```bash
bash rocky-setup.sh
```

**Included Packages (selectable):**
- **System Tools:** `wget`, `curl`, `net-tools`, `tree`
- **Development:** `git`, `vim`
- **Monitoring:** `htop`, `ncdu`, `pv`
- **Enhanced Tools:** `bat`, `fd-find`, `tldr`
- **Storage Management:** `parted`, `lvm2`, `gdisk`
- **Terminal:** `tmux`
- **Repositories:** `epel-release`

**Added Aliases:**
- `ll` - Enhanced directory listing (`ls -lah`)
- `mkenv` - Python virtual environment creator with pip upgrade

## System Requirements

- **OS:** Rocky Linux (tested on Rocky Linux 8/9)
- **Privileges:** Root access required for most operations
- **Dependencies:** 
  - `dialog` (auto-installed)
  - `cloud-utils-growpart` (auto-installed when needed)

## Installation and Usage

1. **Clone or download the scripts:**
   ```bash
   git clone https://github.com/ThisIsCJ/rocky-scripts.git
   cd rocky-config
   ```

2. **Make scripts executable:**
   ```bash
   chmod +x *.sh
   ```

3. **Run the desired script:**
   ```bash
   # For comprehensive system configuration
   sudo bash rocky-config.sh
   
   # For initial system setup with package installation
   bash rocky-setup.sh
   
   # For MOTD installation
   sudo cp rocky-motd.sh /etc/profile.d/motd.sh
   sudo chmod +x /etc/profile.d/motd.sh
   ```

## Script Workflow

### rocky-config.sh Workflow
1. **Verification:** Checks for root privileges and installs dialog
2. **Updates:** Performs system package updates
3. **Hostname:** Optional hostname and domain configuration
4. **Partitions:** Optional partition expansion with filesystem resize
5. **Summary:** Displays final system configuration
6. **Reboot:** Optional system reboot

### rocky-setup.sh Workflow
1. **Updates:** System package updates and upgrades
2. **Network:** Hostname and domain configuration
3. **Packages:** Interactive package selection and installation
4. **Storage:** Optional disk partition expansion
5. **Aliases:** Adds useful bash aliases
6. **Summary:** Comprehensive setup report

## Safety Features

- **Backups:** Automatic backup of `/etc/hosts` before modifications
- **Validation:** Input validation for hostnames and domains
- **Confirmation:** User confirmation for destructive operations
- **Error Handling:** Graceful error handling with informative messages
- **Cancellation:** Ability to cancel operations at any point

## Disk Management

Both `rocky-config.sh` and `rocky-setup.sh` include intelligent disk management:

- **Partition Detection:** Automatic detection of available partitions
- **Filesystem Support:** XFS and EXT4 filesystem expansion
- **LVM Support:** Logical Volume Manager integration
- **Safety Checks:** Validation before performing resize operations

## Troubleshooting

### Common Issues

1. **Permission Denied:**
   ```bash
   # Ensure scripts are executable
   chmod +x *.sh
   ```

2. **Dialog Not Found:**
   ```bash
   # Install dialog manually if auto-install fails
   sudo dnf install -y dialog
   ```

3. **Partition Resize Fails:**
   - Ensure the partition is not at maximum size
   - Check for sufficient free space on the disk
   - Verify LVM configuration if using logical volumes

### Log Files

- System logs: `/var/log/messages`
- DNF logs: `/var/log/dnf.log`
- Backup files: `/etc/hosts.backup.YYYYMMDD_HHMMSS`

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve these scripts.

## License

These scripts are provided as-is for educational and administrative purposes. Use at your own risk and always test in a non-production environment first.

---

**Note:** Always backup your system before running configuration scripts, especially those that modify partitions or system files.
