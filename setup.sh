#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error.
set -u
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# --- Configuration ---
TARGET_USER=$(whoami)
SSH_PORT="10022"
VNC_PORT="5901"

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions ---
function info() { echo -e "${GREEN}[INFO]${NC} $1"; }
function warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
function error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Main Logic Functions ---

function set_user_password() {
   local prompt_template="Set/change the password for user '%s'? (y/n): "
   local formatted_prompt
   printf -v formatted_prompt "$prompt_template" "$TARGET_USER"

   read -p "$formatted_prompt" set_pwd
   if [[ "$set_pwd" =~ ^[Yy]$ ]]; then
       sudo passwd "$TARGET_USER"
   fi
}

function update_packages() {
   info "Updating package list..."
   sudo apt-get update || { error "Failed to update package lists"; exit 1; }
}

function install_package() {
   info "$(printf "Successfully installed %s" "$1")"
   sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" || { 
       error "$(printf "Failed to install %s" "$*")"; exit 1;
   }
}

function configure_ssh() {
   info "Modifying SSH configuration (Port: ${SSH_PORT})..."
   install_package "openssh-server"
   sudo sed -i -e "s/^#\?Port .*/Port ${SSH_PORT}/" \
       -e 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' \
       /etc/ssh/sshd_config || { error "$(printf "Failed to configure %s" "SSH")"; exit 1; }
   sudo systemctl restart sshd
}

function configure_locale() {
   info "Checking locale settings..."
   if locale | grep -q "UTF-8"; then
       info "UTF-8 locale detected, skipping setup."; return
   fi
   warn "No UTF-8 locale detected. Installing and setting to en_US.UTF-8..."
   install_package "locales"
   sudo locale-gen en_US.UTF-8
   sudo localectl set-locale LANG=en_US.UTF-8
}

function install_desktop() {
   info "Installing KDE Plasma desktop environment..."
   install_package "tasksel"
   sudo DEBIAN_FRONTEND=noninteractive tasksel install kde-desktop || {
       error "$(printf "Failed to configure %s" "KDE Desktop")"; exit 1;
   }
}

function configure_vnc() {
   info "Configuring VNC server (Port: ${VNC_PORT})..."
   install_package "tigervnc-standalone-server" "tigervnc-common"
   [ ! -f "$HOME/.vnc/passwd" ] && { warn "A password is required for VNC."; vncpasswd; } || info "VNC password file already exists, skipping setup."
   mkdir -p "$HOME/.vnc"
   chmod 700 "$HOME/.vnc"
   cat > "$HOME/.vnc/xstartup" << 'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
/usr/bin/startplasma-x11 &
EOF
   chmod u+x "$HOME/.vnc/xstartup"
   echo "geometry=1920x1080" > "$HOME/.vnc/config"
   echo "localhost=no" >> "$HOME/.vnc/config"
   echo "alwaysshared" >> "$HOME/.vnc/config"
   sudo cp /lib/systemd/system/tigervncserver@.service /etc/systemd/system/tigervncserver@:1.service
   sudo sed -i "s/<USER>/${TARGET_USER}/" /etc/systemd/system/tigervncserver@:1.service
   sudo systemctl daemon-reload
   sudo systemctl enable --now tigervncserver@:1.service
}

function configure_firewall() {
   info "Configuring firewall (UFW)..."
   install_package "ufw"
   sudo ufw allow ${SSH_PORT}/tcp comment 'SSH'
   sudo ufw allow ${VNC_PORT}/tcp comment 'VNC'
   sudo ufw --force enable
   info "Firewall enabled. Status:"
   sudo ufw status verbose
}

function install_common_utils() {
   read -p "Install common command-line utilities (git, curl, htop, etc.)? (y/n): " choice
   if [[ "$choice" =~ ^[Yy]$ ]]; then
       info "Installing common utilities..."
       install_package git curl wget htop neofetch unzip ca-certificates
   fi
}

function install_docker() {
   read -p "Install Docker and Docker Compose? (y/n): " choice
   if [[ "$choice" =~ ^[Yy]$ ]]; then
       info "Installing Docker..."
       # Add Docker's official GPG key
       sudo install -m 0755 -d /etc/apt/keyrings
       curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
       sudo chmod a+r /etc/apt/keyrings/docker.gpg
       # Set up the repository
       echo \
         "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
         $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
         sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
       sudo apt-get update
       install_package docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
       # Add current user to docker group
       sudo usermod -aG docker ${TARGET_USER}
       warn "You need to log out and log back in for Docker group changes to take effect."
   fi
}

function display_summary() {
   local ip_address
   ip_address=$(hostname -I | awk '{print $1}')
   
   echo -e "\n\n${BLUE}-----------------------------------------------------${NC}"
   info "===== System Setup Summary ====="
   echo -e "${BLUE}-----------------------------------------------------${NC}"
   
   # Use neofetch if available for a nice visual summary
   if command -v neofetch &> /dev/null; then
       neofetch
   fi

   echo ""
   info "$(printf "      Local IP Address: %s" "${ip_address}")"
   info "$(printf "                 User: %s" "${TARGET_USER}")"
   info "$(printf "            SSH Port: %s (Allowed in firewall)" "${SSH_PORT}")"
   info "$(printf "            VNC Port: %s (Allowed in firewall)" "${VNC_PORT}")"
   echo -e "${BLUE}-----------------------------------------------------${NC}\n"
}

# --- Main Execution ---
function main() {
   if [[ $EUID -eq 0 ]]; then
      error "This script should not be run as root. Run it as a normal user with sudo privileges."
      exit 1
   fi
   
   # Core setup
   set_user_password
   update_packages
   configure_locale
   configure_ssh
   install_desktop
   configure_vnc
   
   # Optional additions
   install_common_utils
   install_docker

   # Final steps
   configure_firewall # Run firewall last to ensure all needed ports are known
   display_summary
   
   info "All configurations completed! Please reboot your computer for all changes to take full effect."
}

main "$@"