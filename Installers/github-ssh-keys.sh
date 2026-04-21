#!/bin/bash
set -euo pipefail

# DESCRIPTION: Import a GitHub user's public SSH keys into the current user's authorized_keys

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

UI_WIDTH=86
EXIT_APP_CODE=42

trap 'echo -e "\n${GREEN}Goodbye!${NC}"; exit $EXIT_APP_CODE' INT

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
    printf "${color}%${UI_WIDTH}s${NC}\n" "" | sed "s/ /${char}/g"
}

print_status() { echo -e "${CYAN}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s\n' "$value"
}

show_header() {
    clear
    print_line "=" "$BLUE"
    print_centered "GITHUB SSH KEY IMPORT" "$WHITE"
    print_line "=" "$BLUE"
    echo ""
}

resolve_target_user() {
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        printf '%s\n' "$SUDO_USER"
    else
        id -un
    fi
}

resolve_target_home() {
    local user="$1"
    local home_dir=""

    if command -v getent >/dev/null 2>&1; then
        home_dir=$(getent passwd "$user" | awk -F: '{print $6}')
    fi

    if [[ -z "$home_dir" && -f /etc/passwd ]]; then
        home_dir=$(awk -F: -v user="$user" '$1 == user {print $6}' /etc/passwd)
    fi

    printf '%s\n' "$home_dir"
}

fetch_keys() {
    local github_user="$1"
    local output_file="$2"
    local url="https://github.com/${github_user}.keys"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output_file"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$output_file" "$url"
    else
        print_error "Neither curl nor wget is installed. Please install one and try again."
        return 1
    fi
}

is_valid_ssh_public_key() {
    local key_line="$1"
    [[ "$key_line" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]]
}

validate_key_file() {
    local key_file="$1"
    local valid_count=0
    local line=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue

        if ! is_valid_ssh_public_key "$line"; then
            print_error "Received non-SSH-key output. Aborting without making changes."
            return 1
        fi

        valid_count=$((valid_count + 1))
    done < "$key_file"

    if [[ "$valid_count" -eq 0 ]]; then
        print_error "No public SSH keys were found for that GitHub user."
        return 1
    fi

    return 0
}

ensure_ssh_paths() {
    local ssh_dir="$1"
    local auth_keys="$2"

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    if [[ ! -f "$auth_keys" ]]; then
        : > "$auth_keys"
    fi
    chmod 600 "$auth_keys"
}

create_backup() {
    local auth_keys="$1"
    local backup_file="$2"

    cp "$auth_keys" "$backup_file"
    print_status "Backup created: $backup_file"
}

set_target_ownership() {
    local target_user="$1"
    local ssh_dir="$2"
    local auth_keys="$3"

    if [[ "$EUID" -eq 0 ]]; then
        chown "$target_user":"$target_user" "$ssh_dir" "$auth_keys" 2>/dev/null || \
            chown "$target_user" "$ssh_dir" "$auth_keys" 2>/dev/null || \
            print_warn "Could not update ownership for ${ssh_dir} and ${auth_keys}."
    fi
}

main() {
    local target_user=""
    local target_home=""
    local ssh_dir=""
    local auth_keys=""
    local backup_file=""
    local github_user=""
    local fetched_file=""
    local merged_file=""
    local line=""
    local fetched_count=0
    local added_count=0
    local skipped_count=0
    local had_existing_auth_keys="false"

    show_header

    target_user=$(resolve_target_user)
    target_home=$(resolve_target_home "$target_user")

    if [[ -z "$target_home" || ! -d "$target_home" ]]; then
        print_error "Could not resolve a valid home directory for user '$target_user'."
        exit 1
    fi

    ssh_dir="${target_home}/.ssh"
    auth_keys="${ssh_dir}/authorized_keys"

    print_status "Target user: ${target_user}"
    print_status "Target SSH directory: ${ssh_dir}"
    echo ""

    read -rp "Enter GitHub username: " github_user
    github_user=$(trim_whitespace "$github_user")

    if [[ -z "$github_user" ]]; then
        print_error "GitHub username is required."
        exit 1
    fi

    if [[ ! "$github_user" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}$ ]]; then
        print_error "GitHub username contains unsupported characters."
        exit 1
    fi

    fetched_file=$(mktemp)
    merged_file=$(mktemp)
    trap 'rm -f "${fetched_file:-}" "${merged_file:-}"' EXIT

    print_status "Fetching public keys from GitHub..."
    if ! fetch_keys "$github_user" "$fetched_file"; then
        print_error "Failed to fetch public keys for GitHub user '${github_user}'."
        exit 1
    fi

    if ! validate_key_file "$fetched_file"; then
        exit 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        fetched_count=$((fetched_count + 1))
    done < "$fetched_file"

    if [[ -f "$auth_keys" ]]; then
        had_existing_auth_keys="true"
    fi

    ensure_ssh_paths "$ssh_dir" "$auth_keys"
    cat "$auth_keys" > "$merged_file"

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue

        if grep -Fqx "$line" "$merged_file"; then
            skipped_count=$((skipped_count + 1))
            continue
        fi

        printf '%s\n' "$line" >> "$merged_file"
        added_count=$((added_count + 1))
    done < "$fetched_file"

    if [[ "$added_count" -eq 0 ]]; then
        print_warn "All fetched keys are already present in ${auth_keys}."
        set_target_ownership "$target_user" "$ssh_dir" "$auth_keys"
        chmod 700 "$ssh_dir"
        chmod 600 "$auth_keys"
        echo ""
        print_line "-" "$BLUE"
        print_success "Summary"
        printf "  ${YELLOW}%-14s${NC} : %s\n" "Target User" "$target_user"
        printf "  ${YELLOW}%-14s${NC} : %s\n" "Target File" "$auth_keys"
        printf "  ${YELLOW}%-14s${NC} : %s\n" "Fetched Keys" "$fetched_count"
        printf "  ${YELLOW}%-14s${NC} : %s\n" "Added Keys" "$added_count"
        printf "  ${YELLOW}%-14s${NC} : %s\n" "Duplicates" "$skipped_count"
        print_line "-" "$BLUE"
        return 0
    fi

    if [[ "$had_existing_auth_keys" == "true" ]]; then
        backup_file="${auth_keys}.bak.$(date +%Y%m%d_%H%M%S)"
        create_backup "$auth_keys" "$backup_file"
    fi

    cat "$merged_file" > "$auth_keys"
    chmod 600 "$auth_keys"
    chmod 700 "$ssh_dir"
    set_target_ownership "$target_user" "$ssh_dir" "$auth_keys"

    echo ""
    print_line "-" "$BLUE"
    print_success "Imported GitHub public keys successfully."
    printf "  ${YELLOW}%-14s${NC} : %s\n" "Target User" "$target_user"
    printf "  ${YELLOW}%-14s${NC} : %s\n" "Target File" "$auth_keys"
    printf "  ${YELLOW}%-14s${NC} : %s\n" "Fetched Keys" "$fetched_count"
    printf "  ${YELLOW}%-14s${NC} : %s\n" "Added Keys" "$added_count"
    printf "  ${YELLOW}%-14s${NC} : %s\n" "Duplicates" "$skipped_count"
    if [[ -n "$backup_file" ]]; then
        printf "  ${YELLOW}%-14s${NC} : %s\n" "Backup File" "$backup_file"
    fi
    print_line "-" "$BLUE"
}

main "$@"
