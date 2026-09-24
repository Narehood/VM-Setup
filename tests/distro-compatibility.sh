#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

# Exercise production dispatch with commands captured, never host package changes.
for distro in debian ubuntu alpine arch manjaro endeavouros rhel redhat rocky almalinux centos fedora opensuse-leap opensuse-tumbleweed sles; do
    (
        # shellcheck source=Installers/WordPress.sh
        source "$repo_root/Installers/WordPress.sh"
        OS=$distro
        record() { printf '%s\n' "$*" >> "$fixture/$distro"; }
        apt-get() { record apt-get "$@"; }
        dnf() { record dnf "$@"; }
        pacman() { record pacman "$@"; }
        zypper() { record zypper "$@"; }
        apk() { if [[ "$1" == search ]]; then printf 'php84\nphp85\n'; else record apk "$@"; fi; }
        rc-update() { record rc-update "$@"; }
        rc-service() { record rc-service "$@"; }
        systemctl() { record systemctl "$@"; }
        update_repos
        select_packages
        ((${#PHP_PACKAGES[@]} >= 4))
        install_pkg "${BASE_PACKAGES[@]}" "${PHP_PACKAGES[@]}"
        service_start "$WEB_SERVICE"
        case "$distro" in
            debian|ubuntu) grep -q 'apt-get install.*php-mysql' "$fixture/$distro" ;;
            alpine) grep -q 'apk add.*php85-mysqli' "$fixture/$distro"; grep -q 'rc-service apache2 start' "$fixture/$distro" ;;
            arch|manjaro|endeavouros)
                grep -q 'pacman -S.*php-apache' "$fixture/$distro"
                if grep -q 'pacman -Sy' "$fixture/$distro"; then exit 1; fi ;;
            opensuse*|sles) grep -q 'zypper.*install.*php8-mysql' "$fixture/$distro" ;;
            *) grep -q 'dnf install.*php-mysqlnd' "$fixture/$distro" ;;
        esac
    )
    (
        # shellcheck source=Installers/systemUpdate.sh
        source "$repo_root/Installers/systemUpdate.sh"
        OS=$distro QUIET=true LOG_ENABLED=false DRY_RUN=false
        detect_os() { :; }
        record() { printf '%s\n' "$*" >> "$fixture/update-$distro"; }
        apt-get() { record apt-get "$@"; }
        dnf() { record dnf "$@"; }
        pacman() { record pacman "$@"; }
        paccache() { record paccache "$@"; }
        zypper() { record zypper "$@"; }
        apk() { record apk "$@"; }
        update_system
        case "$distro" in
            arch|manjaro|endeavouros) grep -q 'pacman -Syu' "$fixture/update-$distro" ;;
            opensuse-tumbleweed) grep -q 'zypper --non-interactive dup' "$fixture/update-$distro" ;;
            alpine) grep -q 'apk upgrade' "$fixture/update-$distro" ;;
        esac
    )
done

(
    # shellcheck source=Installers/Automated-Security-Patches.sh
    source "$repo_root/Installers/Automated-Security-Patches.sh"
    run_as_root() {
        printf '%s\n' "$*" >> "$fixture/maintenance-commands"
        if [[ "$1" == tee ]]; then cat > "$fixture/$(basename "$2")"; fi
    }
    pacman() { return 0; }
    enable_arch_updates
    grep -q 'ExecStart=/usr/bin/checkupdates' "$fixture/pacman-refresh.service"
    if grep -q 'pacman -S[yY]' "$fixture/pacman-refresh.service"; then exit 1; fi
    enable_alpine_updates
    grep -q 'rc-service crond status' "$fixture/maintenance-commands"
    OS=sles; enable_suse_updates
    grep -q 'patch --category security' "$fixture/suse-update"
    OS=opensuse-tumbleweed; enable_suse_updates
    grep -q 'list-updates' "$fixture/suse-update"
)

(
    # shellcheck source=Installers/CloudFlare-Tunnels.sh
    source "$repo_root/Installers/CloudFlare-Tunnels.sh"
    for arch in x86_64 aarch64 armv7l; do select_cloudflared_asset "$arch"; [[ "$CF_SHA" =~ ^[a-f0-9]{64}$ ]]; done
    write_openrc_service > "$fixture/cloudflared-openrc"
    write_systemd_service > "$fixture/cloudflared-systemd"
    bash -n "$fixture/cloudflared-openrc"
    grep -q -- '--token-file' "$fixture/cloudflared-openrc"
    grep -q -- '--token-file' "$fixture/cloudflared-systemd"
)
echo 'Package/service dispatch across 15 distro IDs, rolling updates and OpenRC/systemd: passed.'
