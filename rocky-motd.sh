#!/bin/bash
# sudo vim /etc/profile.d/motd.sh
# sudo chmod +x /etc/profile.d/motd.sh

# Colors
CYAN="\e[36m"
GREEN="\e[32m"
YELLOW="\e[33m"
MAGENTA="\e[35m"
RESET="\e[0m"
BOLD="\e[1m"

# System Info
HOSTNAME=$(hostname)
FQDN=$(hostname -f)
IP=$(hostname -I | awk '{print $1}')
OS=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
PYTHON_VERSION=$(python3 --version 2>/dev/null || echo "Python not found")
COCKPIT_VERSION=$(rpm -q cockpit 2>/dev/null | cut -d'-' -f2- | sed 's/.x86_64//')

# Header
echo -e "${BOLD}${CYAN}=============================================="
echo -e "   🚀 Welcome to ${GREEN}${HOSTNAME}${CYAN}"
echo -e "==============================================${RESET}"
echo -e "   ${YELLOW}🖥️ OS:${RESET} ${OS}"
echo -e "   ${YELLOW}📡 IP Address:${RESET}     ${IP}"
echo -e "   ${YELLOW}🌐 Hostname:${RESET} ${FQDN}"
echo -e "   ${YELLOW}🕹 Cockpit:${RESET}  http://${IP}:9090"
echo -e "             http://${FQDN}:9090"
echo -e "${CYAN}----------------------------------------------${RESET}"
echo -e ""
echo -e "🐍 Python Version:   ${PYTHON_VERSION}"
echo -e "🕹 Cockpit Version:  ${COCKPIT_VERSION:-Not installed}"
echo -e ""
echo -e "${MAGENTA}📦 User-Installed Packages:${RESET}"

# User-installed packages in 3 columns
dnf history userinstalled | awk 'NR>2 {print $1}' | \
xargs -r rpm -q --qf '%{NAME}\n' 2>/dev/null | \
sort | paste - - - | column -t

echo -e "${CYAN}==============================================${RESET}"
echo -e "${CYAN}====== This menu is brought to you by ========${RESET}"
echo -e "${CYAN}======       gummies and free time    ========${RESET}"
echo -e "${CYAN}==============================================${RESET}"