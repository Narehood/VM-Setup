#!/bin/bash
set -euo pipefail

# --- 1. CRITICAL SETUP & RESTART FIX ---
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
cd "$SCRIPT_DIR" || { echo "Failed to change directory to $SCRIPT_DIR"; exit 1; }

# --- 2. VISUAL STYLING ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

UI_WIDTH=66
VERSION="3.2.0"

# Handle Ctrl+C gracefully
trap 'echo -e "\n${GREEN}Goodbye!${NC}"; exit 0' SIGINT SIGTERM

print_centered() {
    local text="$1"
    local color="${2:-$NC}"
    local padding=$(( (UI_WIDTH - ${#text}) / 2 ))
    if [ "$padding" -lt 0 ]; then padding=0; fi
    printf "${color}%${padding}s%s${NC}\n" "" "$text"
}

print_line() {
    local char="${1:-=}"
    local color="${2:-$BLUE}"
    local line
    line=$(printf "%${UI_WIDTH}s" "" | sed "s/ /${char}/g")
    echo -e "${color}${line}${NC}"
}

print_status() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

pause() {
    echo ""
    read -rp "Press [Enter] to return to the menu..."
}

confirm_prompt() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    read -rp "$prompt" response
    response="${response:-$default}"
    [[ "$response" =~ ^[Yy]$ ]]
}

truncate_string() {
    local str="$1"
    local max_len="$2"
    if [ ${#str} -gt "$max_len" ]; then
        echo "${str:0:$((max_len - 2))}.."
    else
        echo "$str"
    fi
}

get_current_branch() {
    git branch --show-current 2>/dev/null || echo "unknown"
}

show_header() {
    clear
    echo -e "${BLUE}██╗   ██╗███╗   ███╗    ███████╗███████╗████████╗██╗   ██╗██████╗ ${NC}"
    echo -e "${BLUE}██║   ██║████╗ ████║    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗${NC}"
    echo -e "${BLUE}██║   ██║██╔████╔██║    ███████╗█████╗     ██║   ██║   ██║██████╔╝${NC}"
    echo -e "${BLUE}╚██╗ ██╔╝██║╚██╔╝██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ ${NC}"
    echo -e "${BLUE} ╚████╔╝ ██║ ╚═╝ ██║    ███████║███████╗   ██║   ╚██████╔╝██║     ${NC}"
    echo -e "${BLUE}  ╚═══╝  ╚═╝     ╚═╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     ${NC}"
    print_centered "VERSION $VERSION  |  BY: MICHAEL NAREHOOD" "$CYAN"
    print_line "=" "$BLUE"
}

show_stats() {
    # OS Detection
    local distro="Unknown"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" = "alpine" ]; then
            distro="Alpine ${VERSION_ID:-}"
        else
            distro="${PRETTY_NAME:-$ID}"
        fi
    fi
    distro=$(truncate_string "$distro" 22)

    # Kernel
    local kernel
    kernel=$(truncate_string "$(uname -r)" 22)

    # Uptime
    local uptime_str="N/A"
    if [ -f /proc/uptime ]; then
        local uptime_secs
        uptime_secs=$(cut -d. -f1 /proc/uptime)
        local days=$((uptime_secs / 86400))
        local hours=$(( (uptime_secs % 86400) / 3600 ))
        local mins=$(( (uptime_secs % 3600) / 60 ))
        if [ "$days" -gt 0 ]; then
            uptime_str="${days}d ${hours}h ${mins}m"
        elif [ "$hours" -gt 0 ]; then
            uptime_str="${hours}h ${mins}m"
        else
            uptime_str="${mins}m"
        fi
    fi

    # Load average
    local cpu_load="N/A"
    if [ -f /proc/loadavg ]; then
        cpu_load=$(LC_ALL=C awk '{printf "%.2f (1m)", $1}' /proc/loadavg)
    fi

    # Memory from /proc/meminfo
    local mem_usage="N/A"
    if [ -f /proc/meminfo ]; then
        local mem_total mem_avail mem_used mem_pct
        mem_total=$(LC_ALL=C awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)
        mem_avail=$(LC_ALL=C awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo)
        if [ -n "$mem_total" ] && [ -n "$mem_avail" ] && [ "$mem_total" -gt 0 ]; then
            mem_used=$((mem_total - mem_avail))
            mem_pct=$((mem_used * 100 / mem_total))
            mem_usage="${mem_used}/${mem_total}MB (${mem_pct}%)"
        fi
    fi

    # Disk usage
    local disk_usage="N/A"
    if command -v df >/dev/null 2>&1; then
        local disk_info
        disk_info=$(LC_ALL=C df -P / 2>/dev/null | awk 'NR==2 {print $3, $2, $5}')
        if [ -n "$disk_info" ]; then
            local used total pct
            read -r used total pct <<< "$disk_info"
            if [ -n "$used" ] && [ -n "$total" ] && [ -n "$pct" ]; then
                local used_h total_h
                if [ "$total" -ge 1048576 ]; then
                    used_h="$((used / 1048576))G"
                    total_h="$((total / 1048576))G"
                else
                    used_h="$((used / 1024))M"
                    total_h="$((total / 1024))M"
                fi
                disk_usage="${used_h}/${total_h} (${pct})"
            fi
        fi
    fi

    # Hostname
    local hostname_str
    hostname_str=$(truncate_string "$(hostname)" 20)

    # Network info
    local ip_addr="N/A"
    local subnet="N/A"
    local gateway="N/A"

    if command -v ip >/dev/null 2>&1; then
        local full_ip
        full_ip=$(LC_ALL=C ip -4 addr show scope global 2>/dev/null | awk '/inet / {print $2; exit}')
        if [ -n "$full_ip" ]; then
            ip_addr="${full_ip%%/*}"
            subnet="/${full_ip##*/}"
        fi
        gateway=$(LC_ALL=C ip route 2>/dev/null | awk '/default/ {print $3; exit}')
        gateway=$(truncate_string "${gateway:-N/A}" 15)
    fi

    # Current branch
    local current_branch
    current_branch=$(truncate_string "$(get_current_branch)" 20)

    # Display
    echo -e "${WHITE}SYSTEM INFORMATION${NC}"
    printf "  ${YELLOW}%-11s${NC} : %-20s ${YELLOW}%-11s${NC} : %s\n" "OS" "$distro" "IP Address" "$ip_addr"
    printf "  ${YELLOW}%-11s${NC} : %-20s ${YELLOW}%-11s${NC} : %s\n" "Kernel" "$kernel" "Subnet" "$subnet"
    printf "  ${YELLOW}%-11s${NC} : %-20s ${YELLOW}%-11s${NC} : %s\n" "Hostname" "$hostname_str" "Gateway" "$gateway"
    print_line "-" "$BLUE"
    printf "  ${YELLOW}%-11s${NC} : %-20s ${YELLOW}%-11s${NC} : %s\n" "Load Avg" "$cpu_load" "Memory" "$mem_usage"
    printf "  ${YELLOW}%-11s${NC} : %-20s ${YELLOW}%-11s${NC} : %s\n" "Disk Usage" "$disk_usage" "Uptime" "$uptime_str"
    print_line "-" "$BLUE"
    printf "  ${YELLOW}%-11s${NC} : %-20s\n" "Branch" "$current_branch"
    print_line "=" "$BLUE"
}

check_for_updates() {
    echo ""
    print_status "Checking for updates..."

    if ! command -v git >/dev/null 2>&1; then
        print_error "Git is not installed. Cannot check for updates."
        sleep 2
        return 1
    fi

    if [ ! -d "$SCRIPT_DIR/.git" ]; then
        print_warn "Not a git repository. Skipping update check."
        sleep 2
        return 1
    fi

    if ! git fetch --quiet 2>/dev/null; then
        print_error "Failed to fetch from remote. Check your network connection."
        sleep 2
        return 1
    fi

    local local_rev remote_rev
    local_rev=$(git rev-parse @ 2>/dev/null)

    if ! remote_rev=$(git rev-parse '@{u}' 2>/dev/null); then
        print_error "No upstream branch configured. Skipping update check."
        sleep 2
        return 1
    fi

    if [ "$local_rev" = "$remote_rev" ]; then
        print_success "Menu is up to date."
        sleep 1
    else
        print_warn "New version available."
        if confirm_prompt "Download and apply updates? (y/N): " "n"; then
            if git pull --quiet; then
                print_success "Updated successfully. Restarting..."
                sleep 1
                exec bash "$SCRIPT_PATH"
            else
                print_error "Update failed. Please try manually with 'git pull'."
                sleep 2
            fi
        else
            print_status "Update skipped."
            sleep 1
        fi
    fi
}

switch_branch() {
    clear
    print_line "=" "$BLUE"
    print_centered "SWITCH BRANCH" "$WHITE"
    print_line "=" "$BLUE"
    echo ""

    if ! command -v git >/dev/null 2>&1; then
        print_error "Git is not installed."
        pause
        return 1
    fi

    if [ ! -d "$SCRIPT_DIR/.git" ]; then
        print_error "Not a git repository."
        pause
        return 1
    fi

    print_status "Fetching branch information..."
    if ! git fetch --all --quiet 2>/dev/null; then
        print_warn "Could not fetch from remote. Showing local branches only."
    fi

    local current_branch
    current_branch=$(get_current_branch)

    if [ -z "$current_branch" ] || [ "$current_branch" = "unknown" ]; then
        print_warn "Currently in detached HEAD state."
        current_branch="(detached)"
    fi

    echo -e "  Current branch: ${GREEN}$current_branch${NC}"
    echo ""

    # Collect branches
    local branches=()
    local branch_display=()

    # Local branches
    while IFS= read -r branch; do
        branch="${branch#\* }"
        branch="${branch// /}"
        if [ -n "$branch" ]; then
            branches+=("$branch")
            if [ "$branch" = "$current_branch" ]; then
                branch_display+=("$branch (current)")
            else
                branch_display+=("$branch")
            fi
        fi
    done < <(git branch 2>/dev/null)

    # Remote branches (exclude HEAD and local duplicates)
    while IFS= read -r branch; do
        branch="${branch// /}"
        branch="${branch#origin/}"
        if [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
            local is_local="false"
            for local_branch in "${branches[@]}"; do
                if [ "$local_branch" = "$branch" ]; then
                    is_local="true"
                    break
                fi
            done
            if [ "$is_local" = "false" ]; then
                branches+=("$branch")
                branch_display+=("$branch (remote)")
            fi
        fi
    done < <(git branch -r 2>/dev/null | grep -v '\->')

    if [ ${#branches[@]} -eq 0 ]; then
        print_error "No branches found."
        pause
        return 1
    fi

    echo -e "  ${WHITE}Available Branches:${NC}"
    echo ""
    local i=1
    for display in "${branch_display[@]}"; do
        printf "    ${CYAN}%2d.${NC} %s\n" "$i" "$display"
        ((i++))
    done
    echo ""
    printf "    ${CYAN} 0.${NC} Cancel\n"
    echo ""
    print_line "-" "$BLUE"

    read -rp "  Select branch [0-$((${#branches[@]}))] : " selection

    if [ "$selection" = "0" ] || [ -z "$selection" ]; then
        print_status "Cancelled."
        sleep 1
        return 0
    fi

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#branches[@]} ]; then
        print_error "Invalid selection."
        sleep 1
        return 1
    fi

    local selected_branch="${branches[$((selection - 1))]}"

    if [ "$selected_branch" = "$current_branch" ]; then
        print_status "Already on branch '$selected_branch'."
        sleep 1
        return 0
    fi

    # Check for uncommitted changes
    local has_changes="false"
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        has_changes="true"
    fi

    if [ "$has_changes" = "true" ]; then
        print_warn "You have uncommitted changes."
        echo ""
        echo -e "  ${WHITE}Options:${NC}"
        echo -e "    ${CYAN}1.${NC} Stash changes (save for later)"
        echo -e "    ${CYAN}2.${NC} Discard changes (permanent)"
        echo -e "    ${CYAN}0.${NC} Cancel"
        echo ""
        read -rp "  Select option [0-2]: " change_option

        case "$change_option" in
            1)
                print_status "Stashing changes..."
                local stash_msg="Auto-stash before switching to $selected_branch"
                if ! git stash push -m "$stash_msg" 2>/dev/null; then
                    print_error "Failed to stash changes."
                    pause
                    return 1
                fi
                print_success "Changes stashed. Use 'git stash pop' to restore."
                ;;
            2)
                if ! confirm_prompt "  Are you sure? This cannot be undone. (y/N): " "n"; then
                    print_status "Cancelled."
                    sleep 1
                    return 0
                fi
                print_status "Discarding changes..."
                if ! git reset --hard HEAD >/dev/null 2>&1; then
                    print_error "Failed to reset working directory."
                    pause
                    return 1
                fi
                git clean -fd >/dev/null 2>&1 || true
                print_success "Changes discarded."
                ;;
            *)
                print_status "Cancelled."
                sleep 1
                return 0
                ;;
        esac
    fi

    echo ""
    print_status "Switching to branch '$selected_branch'..."

    # Check if branch exists locally or needs to be checked out from remote
    local checkout_output
    if git show-ref --verify --quiet "refs/heads/$selected_branch" 2>/dev/null; then
        checkout_output=$(git checkout "$selected_branch" 2>&1)
    else
        checkout_output=$(git checkout -b "$selected_branch" "origin/$selected_branch" 2>&1)
    fi

    local checkout_status=$?
    if [ $checkout_status -ne 0 ]; then
        print_error "Failed to switch branch."
        echo -e "  ${RED}Details:${NC} $checkout_output"
        pause
        return 1
    fi

    # Verify we're on the correct branch
    local new_branch
    new_branch=$(get_current_branch)
    if [ "$new_branch" != "$selected_branch" ]; then
        print_error "Branch switch verification failed."
        print_error "Expected: $selected_branch, Got: $new_branch"
        pause
        return 1
    fi

    # Pull latest if tracking remote
    if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
        print_status "Pulling latest changes..."
        if ! git pull --quiet 2>/dev/null; then
            print_warn "Could not pull latest changes. You may need to pull manually."
        fi
    else
        print_warn "No upstream configured for this branch."
    fi

    print_success "Switched to '$selected_branch'. Restarting menu..."
    sleep 1
    exec bash "$SCRIPT_PATH"
}

execute_script() {
    local script_name="$1"
    local full_path="$SCRIPT_DIR/Installers/$script_name"

    if [ ! -f "$full_path" ]; then
        print_error "Script not found: $full_path"
        pause
        return 1
    fi

    if [ ! -r "$full_path" ]; then
        print_error "Script not readable: $full_path"
        pause
        return 1
    fi

    echo -e "\n${GREEN}>>> Executing: $script_name${NC}"
    sleep 0.5

    bash "$full_path"
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        print_warn "Script exited with code: $exit_code"
    fi

    pause
}

show_help() {
    clear
    print_line "=" "$BLUE"
    print_centered "HELP & INFORMATION" "$WHITE"
    print_line "=" "$BLUE"
    echo ""
    echo -e "  ${WHITE}VM Setup Menu${NC} - Version $VERSION"
    echo -e "  A comprehensive tool for initial VM configuration."
    echo ""
    echo -e "  ${YELLOW}Menu Options:${NC}"
    echo -e "    ${CYAN}1${NC} - Run initial server configuration (hostname, tools, etc.)"
    echo -e "    ${CYAN}2${NC} - Browse and install common applications"
    echo -e "    ${CYAN}3${NC} - Prepare system for Docker installation"
    echo -e "    ${CYAN}4${NC} - Configure automatic security patch updates"
    echo -e "    ${CYAN}5${NC} - Run full system update"
    echo -e "    ${CYAN}6${NC} - Check for and apply menu updates"
    echo -e "    ${CYAN}7${NC} - Launch LinUtil utility"
    echo -e "    ${CYAN}8${NC} - Switch to a different branch (dev/testing)"
    echo -e "    ${CYAN}9${NC} - Display this help screen"
    echo -e "    ${CYAN}0${NC} - Exit the menu"
    echo ""
    echo -e "  ${YELLOW}Location:${NC} $SCRIPT_DIR"
    echo -e "  ${YELLOW}Branch:${NC}   $(get_current_branch)"
    echo ""
    print_line "=" "$BLUE"
    pause
}

# --- INITIAL UPDATE CHECK ---
clear
check_for_updates

# --- MAIN LOOP ---
while true; do
    show_header
    show_stats

    echo -e "${WHITE}MENU OPTIONS${NC}"
    printf "  ${CYAN}1.${NC} %-33s ${CYAN}5.${NC} %s\n" "Server Initial Config" "Run System Updates"
    printf "  ${CYAN}2.${NC} %-33s ${CYAN}6.${NC} %s\n" "Application Installers" "Update This Menu"
    printf "  ${CYAN}3.${NC} %-33s ${CYAN}7.${NC} %s\n" "Docker Host Preparation" "Launch LinUtil"
    printf "  ${CYAN}4.${NC} %-33s ${CYAN}8.${NC} %s\n" "Auto Security Patches" "Switch Branch"
    echo ""
    printf "  ${CYAN}9.${NC} %-33s ${CYAN}0.${NC} ${RED}%s${NC}\n" "Help / About" "Exit"
    echo ""
    print_line "-" "$BLUE"
    read -rp "  Enter selection [0-9]: " choice

    case "$choice" in
        1) execute_script "serverSetup.sh" ;;
        2) execute_script "installer.sh" ;;
        3) execute_script "Docker-Prep.sh" ;;
        4) execute_script "Automated-Security-Patches.sh" ;;
        5) execute_script "systemUpdate.sh" ;;
        6) check_for_updates ;;
        7) execute_script "linutil.sh" ;;
        8) switch_branch ;;
        9|h|help) show_help ;;
        0|q|exit) echo -e "\n${GREEN}Goodbye!${NC}"; exit 0 ;;
        "") ;;
        *) print_error "Invalid option: $choice"; sleep 1 ;;
    esac
done
