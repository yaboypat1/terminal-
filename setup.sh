#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error.
set -u
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# --- Configuration ---
TARGET_USER=$(whoami)
DEFAULT_LANG="cn"
SSH_PORT="10022"
VNC_PORT="5901"

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Language and Messaging ---
declare -A messages
messages=(
   # General
   ["press_enter_cn"]="按回车键继续..."
   ["press_enter_en"]="Press Enter to continue..."
   ["install_success_cn"]="成功安装 %s"
   ["install_success_en"]="Successfully installed %s"
   ["install_fail_cn"]="安装 %s 失败"
   ["install_fail_en"]="Failed to install %s"
   ["update_fail_cn"]="更新软件包列表失败"
   ["update_fail_en"]="Failed to update package lists"
   ["config_fail_cn"]="配置 %s 失败"
   ["config_fail_en"]="Failed to configure %s"
   ["final_instructions_cn"]="所有配置已完成！为了使所有更改（如桌面环境和输入法）完全生效，请重新启动计算机。"
   ["final_instructions_en"]="All configurations completed! Please reboot your computer for all changes (like the desktop environment and input method) to take full effect."

   # Function specific
   ["set_password_prompt_cn"]="是否为用户 '%s' 设置/更改密码？(y/n): "
   ["set_password_prompt_en"]="Set/change the password for user '%s'? (y/n): "
   ["update_pkg_cn"]="正在更新软件包列表..."
   ["update_pkg_en"]="Updating package list..."
   ["modify_ssh_cn"]="正在修改 SSH 配置 (端口: ${SSH_PORT})..."
   ["modify_ssh_en"]="Modifying SSH configuration (Port: ${SSH_PORT})..."
   ["locale_check_cn"]="正在检查语言环境设置..."
   ["locale_check_en"]="Checking locale settings..."
   ["locale_is_utf8_cn"]="检测到 UTF-8 语言环境，跳过设置。"
   ["locale_is_utf8_en"]="UTF-8 locale detected, skipping setup."
   ["locale_set_utf8_cn"]="未检测到 UTF-8 语言环境。正在安装并设置为 en_US.UTF-8..."
   ["locale_set_utf8_en"]="No UTF-8 locale detected. Installing and setting to en_US.UTF-8..."
   ["install_desktop_cn"]="正在安装 KDE Plasma 桌面环境..."
   ["install_desktop_en"]="Installing KDE Plasma desktop environment..."
   ["config_vnc_cn"]="正在配置 VNC 服务器 (端口: ${VNC_PORT})..."
   ["config_vnc_en"]="Configuring VNC server (Port: ${VNC_PORT})..."
   ["vnc_pass_prompt_cn"]="需要为 VNC 设置密码。"
   ["vnc_pass_prompt_en"]="A password is required for VNC."
   ["vnc_pass_exists_cn"]="已找到 VNC 密码文件，跳过设置。"
   ["vnc_pass_exists_en"]="VNC password file already exists, skipping setup."
   ["install_ime_cn"]="正在安装中文输入法 (IBus Pinyin)..."
   ["install_ime_en"]="Installing Chinese Pinyin input method (IBus Pinyin)..."

   # New Features
   ["config_firewall_cn"]="正在配置防火墙 (UFW)..."
   ["config_firewall_en"]="Configuring firewall (UFW)..."
   ["install_utils_prompt_cn"]="是否安装常用的命令行工具 (git, curl, htop, etc.)？ (y/n): "
   ["install_utils_prompt_en"]="Install common command-line utilities (git, curl, htop, etc.)? (y/n): "
   ["installing_utils_cn"]="正在安装常用工具..."
   ["installing_utils_en"]="Installing common utilities..."
   ["install_docker_prompt_cn"]="是否安装 Docker 和 Docker Compose？ (y/n): "
   ["install_docker_prompt_en"]="Install Docker and Docker Compose? (y/n): "
   ["installing_docker_cn"]="正在安装 Docker..."
   ["installing_docker_en"]="Installing Docker..."
   ["summary_header_cn"]="===== 系统设置摘要 ====="
   ["summary_header_en"]="===== System Setup Summary ====="
   ["summary_ip_cn"]="         本地IP地址: %s"
   ["summary_ip_en"]="      Local IP Address: %s"
   ["summary_user_cn"]="                 用户: %s"
   ["summary_user_en"]="                 User: %s"
   ["summary_ssh_cn"]="            SSH 端口: %s (已在防火墙中允许)"
   ["summary_ssh_en"]="            SSH Port: %s (Allowed in firewall)"
   ["summary_vnc_cn"]="            VNC 端口: %s (已在防火墙中允许)"
   ["summary_vnc_en"]="            VNC Port: %s (Allowed in firewall)"
)

# --- Helper Functions ---

function lang() {
   local key="${1}_${LANG}"
   [[ -z "${messages[$key]}" ]] && key="${1}_en"
   printf "%s" "${messages[$key]}"
}

function info() { echo -e "${GREEN}[INFO]${NC} $1"; }
function warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
function error() { echo -e "${RED}[ERROR]${NC} $1"; }
function prompt_continue() { read -r -p "$(echo -e ${YELLOW}"$1 $(lang press_enter)"${NC})"; }

# --- Main Logic Functions ---

function select_language() {
   echo "请选择语言 / Please select language:"
   echo "1. 中文 (默认 / Default)"
   echo "2. English"
   read -p "输入数字 / Enter number (1/2): " lang_choice
   [[ "$lang_choice" == "2" ]] && LANG="en" || LANG="cn"
   info "Language set to ${LANG}."
}

function set_user_password() {
   local prompt; prompt=$(printf "$(lang set_password_prompt_cn)" "$TARGET_USER")
   [[ "$LANG" == "en" ]] && prompt=$(printf "$(lang set_password_prompt_en)" "$TARGET_USER")
   read -p "$prompt" set_pwd
   [[ "$set_pwd" =~ ^[Yy]$ ]] && sudo passwd "$TARGET_USER"
}

function update_packages() {
   info "$(lang update_pkg)"
   sudo apt-get update || { error "$(lang update_fail)"; exit 1; }
}

function install_package() {
   info "$(printf "$(lang install_success)" "$1")"
   sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" || { 
       error "$(printf "$(lang install_fail)" "$*")"; exit 1;
   }
}

function configure_ssh() {
   info "$(lang modify_ssh)"
   install_package "openssh-server"
   sudo sed -i -e "s/^#\?Port .*/Port ${SSH_PORT}/" \
       -e 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' \
       /etc/ssh/sshd_config || { error "$(printf "$(lang config_fail)" "SSH")"; exit 1; }
   sudo systemctl restart sshd
}

function configure_locale() {
   info "$(lang locale_check)"
   if locale | grep -q "UTF-8"; then
       info "$(lang locale_is_utf8)"; return
   fi
   warn "$(lang locale_set_utf8)"
   install_package "locales"
   sudo locale-gen en_US.UTF-8
   sudo localectl set-locale LANG=en_US.UTF-8
}

function install_desktop() {
   info "$(lang install_desktop)"
   install_package "tasksel"
   sudo DEBIAN_FRONTEND=noninteractive tasksel install kde-desktop || {
       error "$(printf "$(lang config_fail)" "KDE Desktop")"; exit 1;
   }
}

function configure_vnc() {
   info "$(lang config_vnc)"
   install_package "tigervnc-standalone-server" "tigervnc-common"
   [ ! -f "$HOME/.vnc/passwd" ] && { warn "$(lang vnc_pass_prompt)"; vncpasswd; } || info "$(lang vnc_pass_exists)"
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

function install_input_method() {
   info "$(lang install_ime)"
   install_package "ibus" "ibus-pinyin" "im-config"
   im-config -n ibus
}

# --- NEW FEATURES ---

function configure_firewall() {
   info "$(lang config_firewall)"
   install_package "ufw"
   sudo ufw allow ${SSH_PORT}/tcp comment 'SSH'
   sudo ufw allow ${VNC_PORT}/tcp comment 'VNC'
   sudo ufw --force enable
   info "Firewall enabled. Status:"
   sudo ufw status verbose
}

function install_common_utils() {
   read -p "$(lang install_utils_prompt)" choice
   if [[ "$choice" =~ ^[Yy]$ ]]; then
       info "$(lang installing_utils)"
       install_package git curl wget htop neofetch unzip ca-certificates
   fi
}

function install_docker() {
   read -p "$(lang install_docker_prompt)" choice
   if [[ "$choice" =~ ^[Yy]$ ]]; then
       info "$(lang installing_docker)"
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
   info "$(lang summary_header)"
   echo -e "${BLUE}-----------------------------------------------------${NC}"
   
   # Use neofetch if available for a nice visual summary
   if command -v neofetch &> /dev/null; then
       neofetch
   fi

   echo ""
   info "$(printf "$(lang summary_ip)" "${ip_address}")"
   info "$(printf "$(lang summary_user)" "${TARGET_USER}")"
   info "$(printf "$(lang summary_ssh)" "${SSH_PORT}")"
   info "$(printf "$(lang summary_vnc)" "${VNC_PORT}")"
   echo -e "${BLUE}-----------------------------------------------------${NC}\n"
}


# --- Main Execution ---
function main() {
   if [[ $EUID -eq 0 ]]; then
      error "This script should not be run as root. Run it as a normal user with sudo privileges."
      exit 1
   fi

   LANG="$DEFAULT_LANG"
   select_language
   
   # Core setup
   set_user_password
   update_packages
   configure_locale
   configure_ssh
   install_desktop
   configure_vnc
   install_input_method
   
   # Optional additions
   install_common_utils
   install_docker

   # Final steps
   configure_firewall # Run firewall last to ensure all needed ports are known
   display_summary
   
   info "$(lang final_instructions)"
}

main "$@"