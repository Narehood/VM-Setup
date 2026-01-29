#!/bin/bash
set -euo pipefail

# REQUIRES_ROOT: true
# DESCRIPTION: Configure MOTD and SSH login banners

# VISUAL STYLING
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

UI_WIDTH=86

# File paths
MOTD_FILE="/etc/motd"
MOTD_DIR="/etc/update-motd.d"
PROFILE_MOTD="/etc/profile.d/motd.sh"
SSH_CONFIG="/etc/ssh/sshd_config"
SSH_BANNER="/etc/ssh/banner"
BACKUP_DIR="/etc/motd-backup"

# print_centered centers the given text within UI_WIDTH.
print_centered() {
    local text="$1"
    local color="${2:-$NC}"
    local padding=$(( (UI_WIDTH - ${#text}) / 2 ))
    if [ "$padding" -lt 0 ]; then padding=0; fi
    printf "${color}%${padding}s%s${NC}\n" "" "$text"
}

# print_line draws a horizontal line of length UI_WIDTH.
print_line() {
    local char="${1:-=}"
    local color="${2:-$BLUE}"
    printf "${color}%${UI_WIDTH}s${NC}\n" "" | sed "s/ /${char}/g"
}

print_status() { echo -e "${CYAN}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

pause() {
    echo ""
    read -rp "Press [Enter] to continue..."
}

# check_root ensures the script is run as root.
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root."
        exit 1
    fi
}

# create_backup backs up existing MOTD configuration.
create_backup() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/$timestamp"

    mkdir -p "$backup_path"

    [ -f "$MOTD_FILE" ] && cp "$MOTD_FILE" "$backup_path/" 2>/dev/null || true
    [ -f "$PROFILE_MOTD" ] && cp "$PROFILE_MOTD" "$backup_path/" 2>/dev/null || true
    [ -f "$SSH_BANNER" ] && cp "$SSH_BANNER" "$backup_path/" 2>/dev/null || true
    [ -d "$MOTD_DIR" ] && cp -r "$MOTD_DIR" "$backup_path/" 2>/dev/null || true

    print_success "Backup created: $backup_path"
}

# detect_distro returns the distribution family.
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|pop|linuxmint|kali)
                echo "debian"
                ;;
            fedora|rhel|centos|rocky|almalinux)
                echo "rhel"
                ;;
            arch|endeavouros|manjaro)
                echo "arch"
                ;;
            alpine)
                echo "alpine"
                ;;
            opensuse*|sles)
                echo "suse"
                ;;
            *)
                echo "unknown"
                ;;
        esac
    else
        echo "unknown"
    fi
}

# view_current_motd displays the current MOTD configuration.
view_current_motd() {
    clear
    print_line "=" "$BLUE"
    print_centered "CURRENT MOTD CONFIGURATION" "$WHITE"
    print_line "=" "$BLUE"
    echo ""

    echo -e "${WHITE}Static MOTD (/etc/motd):${NC}"
    print_line "-" "$BLUE"
    if [ -f "$MOTD_FILE" ] && [ -s "$MOTD_FILE" ]; then
        cat "$MOTD_FILE"
    else
        echo -e "${YELLOW}  (empty or not configured)${NC}"
    fi
    echo ""

    if [ -d "$MOTD_DIR" ]; then
        echo -e "${WHITE}Dynamic MOTD Scripts (/etc/update-motd.d/):${NC}"
        print_line "-" "$BLUE"
        local scripts
        scripts=$(ls -1 "$MOTD_DIR" 2>/dev/null || true)
        if [ -n "$scripts" ]; then
            for script in $scripts; do
                local status="${RED}disabled${NC}"
                [ -x "$MOTD_DIR/$script" ] && status="${GREEN}enabled${NC}"
                printf "  %-40s [%b]\n" "$script" "$status"
            done
        else
            echo -e "${YELLOW}  (no scripts found)${NC}"
        fi
        echo ""
    fi

    if [ -f "$PROFILE_MOTD" ]; then
        echo -e "${WHITE}Profile MOTD (/etc/profile.d/motd.sh):${NC}"
        print_line "-" "$BLUE"
        echo -e "${GREEN}  Installed and active${NC}"
        echo ""
    fi

    echo -e "${WHITE}SSH Banner:${NC}"
    print_line "-" "$BLUE"
    local banner_config
    banner_config=$(grep -E "^Banner " "$SSH_CONFIG" 2>/dev/null || true)
    if [ -n "$banner_config" ]; then
        local banner_file="${banner_config#Banner }"
        echo -e "  Configured: ${CYAN}$banner_file${NC}"
        if [ -f "$banner_file" ]; then
            echo ""
            cat "$banner_file"
        fi
    else
        echo -e "${YELLOW}  (not configured)${NC}"
    fi

    print_line "=" "$BLUE"
    pause
}

# set_simple_motd sets a static text MOTD.
set_simple_motd() {
    clear
    print_line "=" "$BLUE"
    print_centered "SET SIMPLE TEXT MOTD" "$WHITE"
    print_line "=" "$BLUE"
    echo ""

    echo -e "${WHITE}Choose a template or enter custom text:${NC}"
    echo ""
    echo -e "  ${CYAN}1.${NC} Hostname banner (ASCII art if figlet available)"
    echo -e "  ${CYAN}2.${NC} Simple welcome message"
    echo -e "  ${CYAN}3.${NC} Server info template"
    echo -e "  ${CYAN}4.${NC} Minimal hostname only"
    echo -e "  ${CYAN}5.${NC} Enter custom text"
    echo -e "  ${CYAN}6.${NC} Clear MOTD (empty)"
    echo -e "  ${CYAN}0.${NC} Cancel"
    echo ""
    print_line "-" "$BLUE"

    read -rp "  Select option [0-6]: " choice

    local content=""
    local hostname_str
    hostname_str=$(hostname)

    case "$choice" in
        1)
            if command -v figlet >/dev/null 2>&1; then
                content=$(figlet -w 80 "$hostname_str" 2>/dev/null || echo "$hostname_str")
            elif command -v toilet >/dev/null 2>&1; then
                content=$(toilet -w 80 "$hostname_str" 2>/dev/null || echo "$hostname_str")
            else
                print_warn "figlet/toilet not installed. Using simple text."
                echo ""
                read -rp "  Install figlet? (y/N): " install_figlet
                if [[ "$install_figlet" =~ ^[Yy]$ ]]; then
                    local distro
                    distro=$(detect_distro)
                    case "$distro" in
                        debian) apt-get update && apt-get install -y figlet ;;
                        rhel) dnf install -y figlet 2>/dev/null || yum install -y figlet ;;
                        arch) pacman -S --noconfirm figlet ;;
                        alpine) apk add figlet ;;
                        suse) zypper install -y figlet ;;
                    esac
                    if command -v figlet >/dev/null 2>&1; then
                        content=$(figlet -w 80 "$hostname_str")
                    else
                        content="=== $hostname_str ==="
                    fi
                else
                    content="
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║   $hostname_str
║                                                                ║
╚════════════════════════════════════════════════════════════════╝"
                fi
            fi
            ;;
        2)
            content="
================================================================================
  Welcome to $hostname_str
  $(date +"%Y-%m-%d")
================================================================================
"
            ;;
        3)
            local ip_addr="N/A"
            if command -v ip >/dev/null 2>&1; then
                ip_addr=$(ip -4 addr show scope global 2>/dev/null | awk '/inet / {print $2; exit}' | cut -d/ -f1)
            fi
            content="
================================================================================
  Server:   $hostname_str
  IP:       ${ip_addr:-N/A}
  OS:       $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || uname -s)
  Kernel:   $(uname -r)
================================================================================
"
            ;;
        4)
            content="$hostname_str"
            ;;
        5)
            echo ""
            echo -e "${WHITE}Enter your custom MOTD (press Ctrl+D when done):${NC}"
            print_line "-" "$BLUE"
            content=$(cat)
            ;;
        6)
            content=""
            ;;
        0|"")
            print_status "Cancelled."
            sleep 1
            return 0
            ;;
        *)
            print_error "Invalid option."
            sleep 1
            return 1
            ;;
    esac

    create_backup
    echo "$content" > "$MOTD_FILE"
    print_success "Static MOTD updated."
    pause
}

# install_dynamic_motd installs a dynamic MOTD script.
install_dynamic_motd() {
    clear
    print_line "=" "$BLUE"
    print_centered "INSTALL DYNAMIC MOTD" "$WHITE"
    print_line "=" "$BLUE"
    echo ""

    echo -e "${WHITE}Dynamic MOTD displays live system stats on login.${NC}"
    echo ""
    echo -e "  ${CYAN}1.${NC} Full system dashboard (recommended)"
    echo -e "  ${CYAN}2.${NC} Minimal stats (load, memory, disk)"
    echo -e "  ${CYAN}3.${NC} Custom color scheme"
    echo -e "  ${CYAN}0.${NC} Cancel"
    echo ""
    print_line "-" "$BLUE"

    read -rp "  Select option [0-3]: " choice

    local color_primary="\033[0;36m"
    local color_label="\033[1;33m"
    local color_reset="\033[0m"

    if [ "$choice" = "3" ]; then
        echo ""
        echo -e "  ${WHITE}Select primary color:${NC}"
        echo -e "    ${CYAN}1.${NC} Cyan (default)"
        echo -e "    ${GREEN}2.${NC} Green"
        echo -e "    ${BLUE}3.${NC} Blue"
        echo -e "    ${RED}4.${NC} Red"
        echo -e "    ${YELLOW}5.${NC} Yellow"
        echo ""
        read -rp "  Select color [1-5]: " color_choice
        case "$color_choice" in
            2) color_primary="\033[0;32m" ;;
            3) color_primary="\033[0;34m" ;;
            4) color_primary="\033[0;31m" ;;
            5) color_primary="\033[1;33m" ;;
        esac
        choice="1"
    fi

    case "$choice" in
        1)
            create_backup

            cat > "$PROFILE_MOTD" << 'SCRIPT_EOF'
#!/bin/bash
# Dynamic MOTD - System Dashboard

# Colors
PRIMARY="COLOR_PRIMARY_PLACEHOLDER"
LABEL="COLOR_LABEL_PLACEHOLDER"
NC="COLOR_RESET_PLACEHOLDER"

# Only show for interactive shells
[[ $- != *i* ]] && return
[ -z "$PS1" ] && return

# Gather system info
HOSTNAME=$(hostname)
KERNEL=$(uname -r)
UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "N/A")

# OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS="${PRETTY_NAME:-$ID}"
else
    OS=$(uname -s)
fi

# IP Address
IP="N/A"
if command -v ip >/dev/null 2>&1; then
    IP=$(ip -4 addr show scope global 2>/dev/null | awk '/inet / {print $2; exit}' | cut -d/ -f1)
fi
[ -z "$IP" ] && IP="N/A"

# Load average
LOAD="N/A"
[ -f /proc/loadavg ] && LOAD=$(awk '{print $1, $2, $3}' /proc/loadavg)

# Memory
MEM="N/A"
if [ -f /proc/meminfo ]; then
    MEM_TOTAL=$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)
    MEM_AVAIL=$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo)
    if [ -n "$MEM_TOTAL" ] && [ -n "$MEM_AVAIL" ] && [ "$MEM_TOTAL" -gt 0 ]; then
        MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
        MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
        MEM="${MEM_USED}/${MEM_TOTAL}MB (${MEM_PCT}%)"
    fi
fi

# Disk
DISK="N/A"
if command -v df >/dev/null 2>&1; then
    DISK_INFO=$(df -P / 2>/dev/null | awk 'NR==2 {printf "%d/%dGB (%s)", $3/1048576, $2/1048576, $5}')
    [ -n "$DISK_INFO" ] && DISK="$DISK_INFO"
fi

# Users logged in
USERS=$(who 2>/dev/null | wc -l)

# Last login
LAST_LOGIN=$(last -1 -R "$USER" 2>/dev/null | head -1 | awk '{print $3, $4, $5, $6}' || echo "N/A")

# Print dashboard
echo ""
echo -e "${PRIMARY}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PRIMARY}║${NC}                                                                              ${PRIMARY}║${NC}"
printf "${PRIMARY}║${NC}   ${LABEL}%-12s${NC} %-62s ${PRIMARY}║${NC}\n" "Hostname:" "$HOSTNAME"
printf "${PRIMARY}║${NC}   ${LABEL}%-12s${NC} %-62s ${PRIMARY}║${NC}\n" "OS:" "$OS"
printf "${PRIMARY}║${NC}   ${LABEL}%-12s${NC} %-62s ${PRIMARY}║${NC}\n" "Kernel:" "$KERNEL"
printf "${PRIMARY}║${NC}   ${LABEL}%-12s${NC} %-62s ${PRIMARY}║${NC}\n" "IP Address:" "$IP"
echo -e "${PRIMARY}║${NC}                                                                              ${PRIMARY}║${NC}"
echo -e "${PRIMARY}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${PRIMARY}║${NC}                                                                              ${PRIMARY}║${NC}"
printf "${PRIMARY}║${NC}   ${LABEL}%-12s${NC} %-62s ${PRIMARY}║${NC}\n" "Uptime:" "$UPTIME"
printf "${PRIMARY}║${NC}   ${LABEL}%-12s${NC} %-62s ${PRIMARY}║${NC}\n" "Load:" "$LOAD"
printf "${PRIMARY}║${NC}   ${LABEL}%-12s${NC} %-62s ${PRIMARY}║${NC}\n" "Memory:" "$MEM"
printf "${PRIMARY}║${NC}   ${LABEL}%-12s${NC} %-62s ${PRIMARY}║${NC}\n" "Disk (/):" "$DISK"
echo -e "${PRIMARY}║${NC}                                                                              ${PRIMARY}║${NC}"
echo -e "${PRIMARY}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${PRIMARY}║${NC}                                                                              ${PRIMARY}║${NC}"
printf "${PRIMARY}║${NC}   ${LABEL}%-12s${NC} %-62s ${PRIMARY}║${NC}\n" "Users:" "$USERS logged in"
printf "${PRIMARY}║${NC}   ${LABEL}%-12s${NC} %-62s ${PRIMARY}║${NC}\n" "Last Login:" "$LAST_LOGIN"
echo -e "${PRIMARY}║${NC}                                                                              ${PRIMARY}║${NC}"
echo -e "${PRIMARY}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
SCRIPT_EOF

            sed -i "s|COLOR_PRIMARY_PLACEHOLDER|$color_primary|g" "$PROFILE_MOTD"
            sed -i "s|COLOR_LABEL_PLACEHOLDER|$color_label|g" "$PROFILE_MOTD"
            sed -i "s|COLOR_RESET_PLACEHOLDER|$color_reset|g" "$PROFILE_MOTD"
            chmod +x "$PROFILE_MOTD"

            echo "" > "$MOTD_FILE"

            print_success "Dynamic MOTD installed (full dashboard)."
            ;;
        2)
            create_backup

            cat > "$PROFILE_MOTD" << 'SCRIPT_EOF'
#!/bin/bash
# Dynamic MOTD - Minimal Stats

[[ $- != *i* ]] && return
[ -z "$PS1" ] && return

LOAD=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "N/A")

MEM="N/A"
if [ -f /proc/meminfo ]; then
    MEM_TOTAL=$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)
    MEM_AVAIL=$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo)
    [ "$MEM_TOTAL" -gt 0 ] && MEM="$((100 - (MEM_AVAIL * 100 / MEM_TOTAL)))%"
fi

DISK=$(df -P / 2>/dev/null | awk 'NR==2 {print $5}' || echo "N/A")

echo ""
echo "  Load: $LOAD | Memory: $MEM | Disk: $DISK"
echo ""
SCRIPT_EOF

            chmod +x "$PROFILE_MOTD"
            echo "" > "$MOTD_FILE"

            print_success "Dynamic MOTD installed (minimal)."
            ;;
        0|"")
            print_status "Cancelled."
            sleep 1
            return 0
            ;;
        *)
            print_error "Invalid option."
            sleep 1
            return 1
            ;;
    esac

    pause
}

# set_ssh_banner configures the pre-login SSH banner.
set_ssh_banner() {
    clear
    print_line "=" "$BLUE"
    print_centered "SET SSH PRE-LOGIN BANNER" "$WHITE"
    print_line "=" "$BLUE"
    echo ""

    echo -e "${WHITE}The SSH banner is shown BEFORE login (for legal notices).${NC}"
    echo ""
    echo -e "  ${CYAN}1.${NC} Standard authorized users warning"
    echo -e "  ${CYAN}2.${NC} Detailed legal notice"
    echo -e "  ${CYAN}3.${NC} Simple warning"
    echo -e "  ${CYAN}4.${NC} Enter custom banner"
    echo -e "  ${CYAN}5.${NC} Disable SSH banner"
    echo -e "  ${CYAN}0.${NC} Cancel"
    echo ""
    print_line "-" "$BLUE"

    read -rp "  Select option [0-5]: " choice

    local content=""
    local hostname_str
    hostname_str=$(hostname)

    case "$choice" in
        1)
            content="
================================================================================
                           AUTHORIZED ACCESS ONLY

  This system is for authorized users only. All activity may be monitored
  and recorded. Unauthorized access is prohibited and may be subject to
  criminal prosecution.

  Server: $hostname_str
================================================================================
"
            ;;
        2)
            content="
********************************************************************************
*                                                                              *
*                              W A R N I N G                                   *
*                                                                              *
*  This computer system is the property of its owner. It is for authorized    *
*  use only. By using this system, all users acknowledge notice of, and       *
*  agree to comply with, the Acceptable Use Policy.                           *
*                                                                              *
*  Users have no expectation of privacy. All activities may be monitored      *
*  and/or recorded. Evidence of unauthorized use may be provided to           *
*  appropriate authorities.                                                    *
*                                                                              *
*  Unauthorized or improper use of this system may result in administrative   *
*  disciplinary action, civil and/or criminal penalties.                      *
*                                                                              *
*  By continuing to use this system you indicate your awareness of and        *
*  consent to these terms and conditions of use.                              *
*                                                                              *
*  LOG OFF IMMEDIATELY if you do not agree to the conditions stated above.    *
*                                                                              *
********************************************************************************
"
            ;;
        3)
            content="
** AUTHORIZED USERS ONLY **
Disconnect immediately if you are not authorized.

"
            ;;
        4)
            echo ""
            echo -e "${WHITE}Enter your custom banner (press Ctrl+D when done):${NC}"
            print_line "-" "$BLUE"
            content=$(cat)
            ;;
        5)
            create_backup
            if grep -qE "^Banner " "$SSH_CONFIG" 2>/dev/null; then
                sed -i '/^Banner /d' "$SSH_CONFIG"
                print_success "SSH banner disabled."
                
                if systemctl is-active --quiet sshd 2>/dev/null; then
                    systemctl reload sshd
                    print_success "SSH service reloaded."
                elif systemctl is-active --quiet ssh 2>/dev/null; then
                    systemctl reload ssh
                    print_success "SSH service reloaded."
                fi
            else
                print_status "SSH banner was not configured."
            fi
            pause
            return 0
            ;;
        0|"")
            print_status "Cancelled."
            sleep 1
            return 0
            ;;
        *)
            print_error "Invalid option."
            sleep 1
            return 1
            ;;
    esac

    create_backup

    echo "$content" > "$SSH_BANNER"
    chmod 644 "$SSH_BANNER"

    if grep -qE "^Banner " "$SSH_CONFIG" 2>/dev/null; then
        sed -i "s|^Banner .*|Banner $SSH_BANNER|" "$SSH_CONFIG"
    else
        echo "Banner $SSH_BANNER" >> "$SSH_CONFIG"
    fi

    print_success "SSH banner configured."

    if systemctl is-active --quiet sshd 2>/dev/null; then
        systemctl reload sshd
        print_success "SSH service reloaded."
    elif systemctl is-active --quiet ssh 2>/dev/null; then
        systemctl reload ssh
        print_success "SSH service reloaded."
    else
        print_warn "Could not reload SSH. You may need to restart manually."
    fi

    pause
}

# disable_ubuntu_extras disables Ubuntu's default MOTD components.
disable_ubuntu_extras() {
    clear
    print_line "=" "$BLUE"
    print_centered "DISABLE UBUNTU MOTD EXTRAS" "$WHITE"
    print_line "=" "$BLUE"
    echo ""

    if [ ! -d "$MOTD_DIR" ]; then
        print_warn "This system doesn't use /etc/update-motd.d/"
        print_status "This option is primarily for Ubuntu/Debian systems."
        pause
        return 0
    fi

    echo -e "${WHITE}Ubuntu includes several MOTD scripts that can be disabled:${NC}"
    echo ""

    local scripts=(
        "10-help-text:Help text and documentation links"
        "50-motd-news:Canonical news/ads (fetches from internet)"
        "50-landscape-sysinfo:Landscape system info"
        "80-esm:Ubuntu Pro/ESM advertising"
        "80-livepatch:Livepatch notifications"
        "90-updates-available:Package update notifications"
        "91-release-upgrade:Release upgrade prompts"
        "95-hwe-eol:Hardware enablement EOL notices"
    )

    echo -e "  ${WHITE}Current status:${NC}"
    echo ""

    local found_any=false
    for entry in "${scripts[@]}"; do
        local script="${entry%%:*}"
        local desc="${entry#*:}"
        local script_path="$MOTD_DIR/$script"

        if [ -f "$script_path" ]; then
            found_any=true
            local status="${GREEN}enabled${NC}"
            [ ! -x "$script_path" ] && status="${RED}disabled${NC}"
            printf "    %-30s %-35s [%b]\n" "$script" "$desc" "$status"
        fi
    done

    if [ "$found_any" = false ]; then
        print_status "No common Ubuntu MOTD scripts found."
        pause
        return 0
    fi

    echo ""
    print_line "-" "$BLUE"
    echo ""
    echo -e "  ${CYAN}1.${NC} Disable all extras (recommended)"
    echo -e "  ${CYAN}2.${NC} Disable news/ads only"
    echo -e "  ${CYAN}3.${NC} Re-enable all"
    echo -e "  ${CYAN}4.${NC} Select individually"
    echo -e "  ${CYAN}0.${NC} Cancel"
    echo ""

    read -rp "  Select option [0-4]: " choice

    case "$choice" in
        1)
            create_backup
            for entry in "${scripts[@]}"; do
                local script="${entry%%:*}"
                local script_path="$MOTD_DIR/$script"
                [ -f "$script_path" ] && chmod -x "$script_path"
            done
            print_success "All MOTD extras disabled."
            ;;
        2)
            create_backup
            local news_scripts=("50-motd-news" "80-esm" "80-livepatch")
            for script in "${news_scripts[@]}"; do
                local script_path="$MOTD_DIR/$script"
                [ -f "$script_path" ] && chmod -x "$script_path"
            done
            print_success "News and advertising scripts disabled."
            ;;
        3)
            create_backup
            for entry in "${scripts[@]}"; do
                local script="${entry%%:*}"
                local script_path="$MOTD_DIR/$script"
                [ -f "$script_path" ] && chmod +x "$script_path"
            done
            print_success "All MOTD extras re-enabled."
            ;;
        4)
            echo ""
            for entry in "${scripts[@]}"; do
                local script="${entry%%:*}"
                local desc="${entry#*:}"
                local script_path="$MOTD_DIR/$script"

                if [ -f "$script_path" ]; then
                    local current="enabled"
                    [ ! -x "$script_path" ] && current="disabled"

                    read -rp "  $script ($current) - Toggle? (y/N): " toggle
                    if [[ "$toggle" =~ ^[Yy]$ ]]; then
                        if [ -x "$script_path" ]; then
                            chmod -x "$script_path"
                            print_success "Disabled: $script"
                        else
                            chmod +x "$script_path"
                            print_success "Enabled: $script"
                        fi
                    fi
                fi
            done
            ;;
        0|"")
            print_status "Cancelled."
            sleep 1
            return 0
            ;;
        *)
            print_error "Invalid option."
            sleep 1
            return 1
            ;;
    esac

    pause
}

# restore_defaults restores MOTD to system defaults.
restore_defaults() {
    clear
    print_line "=" "$BLUE"
    print_centered "RESTORE DEFAULTS" "$WHITE"
    print_line "=" "$BLUE"
    echo ""

    echo -e "${YELLOW}This will:${NC}"
    echo "  - Clear /etc/motd"
    echo "  - Remove dynamic MOTD script (/etc/profile.d/motd.sh)"
    echo "  - Disable SSH banner"
    echo "  - Re-enable Ubuntu MOTD scripts (if applicable)"
    echo ""

    if [ -d "$BACKUP_DIR" ]; then
        echo -e "${WHITE}Available backups:${NC}"
        ls -1 "$BACKUP_DIR" 2>/dev/null | head -5
        echo ""
    fi

    read -rp "Continue with restore? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_status "Cancelled."
        sleep 1
        return 0
    fi

    create_backup

    echo "" > "$MOTD_FILE"
    print_success "Cleared /etc/motd"

    if [ -f "$PROFILE_MOTD" ]; then
        rm -f "$PROFILE_MOTD"
        print_success "Removed dynamic MOTD script"
    fi

    if grep -qE "^Banner " "$SSH_CONFIG" 2>/dev/null; then
        sed -i '/^Banner /d' "$SSH_CONFIG"
        print_success "Disabled SSH banner"

        if systemctl is-active --quiet sshd 2>/dev/null; then
            systemctl reload sshd
        elif systemctl is-active --quiet ssh 2>/dev/null; then
            systemctl reload ssh
        fi
    fi

    if [ -d "$MOTD_DIR" ]; then
        chmod +x "$MOTD_DIR"/* 2>/dev/null || true
        print_success "Re-enabled update-motd.d scripts"
    fi

    print_success "Defaults restored."
    pause
}

# show_menu displays the main menu.
show_menu() {
    clear
    print_line "=" "$BLUE"
    print_centered "MOTD & BANNER CONFIGURATION" "$WHITE"
    print_line "=" "$BLUE"
    echo ""

    echo -e "${WHITE}OPTIONS${NC}"
    echo -e "  ${CYAN}1.${NC} View current MOTD configuration"
    echo -e "  ${CYAN}2.${NC} Set simple text MOTD"
    echo -e "  ${CYAN}3.${NC} Install dynamic MOTD (system stats)"
    echo -e "  ${CYAN}4.${NC} Set SSH pre-login banner"
    echo -e "  ${CYAN}5.${NC} Disable Ubuntu MOTD extras"
    echo -e "  ${CYAN}6.${NC} Restore defaults"
    echo ""
    echo -e "  ${CYAN}0.${NC} ${RED}Exit${NC}"
    echo ""
    print_line "-" "$BLUE"
}

# MAIN
check_root

while true; do
    show_menu

    read -rp "  Enter selection [0-6]: " choice

    case "$choice" in
        1) view_current_motd ;;
        2) set_simple_motd ;;
        3) install_dynamic_motd ;;
        4) set_ssh_banner ;;
        5) disable_ubuntu_extras ;;
        6) restore_defaults ;;
        0|q|exit)
            echo -e "\n${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        "")
            ;;
        *)
            print_error "Invalid option: $choice"
            sleep 1
            ;;
    esac
done
