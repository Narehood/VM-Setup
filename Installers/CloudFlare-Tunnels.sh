#!/usr/bin/env bash
# REQUIRES_ROOT: true
# DESCRIPTION: Installs verified cloudflared for systemd or OpenRC
set -euo pipefail
readonly CLOUDFLARED_VERSION="2026.9.3"

select_cloudflared_asset() {
    case "$1" in
        x86_64|amd64) CF_ARCH=amd64; CF_SHA=77e26d8d900e0b8469f416239d14b5f296525fdf79fee6f511ef55609e3fbac2 ;;
        aarch64|arm64) CF_ARCH=arm64; CF_SHA=aaeb2d7d0da3614634c7e03ab13487a1522c2e79165ed2929cfe23d5e95b326d ;;
        armv7l|armv6l) CF_ARCH=arm; CF_SHA=967dc371a3fedbf09e881c13ee7ba317155ebc336cbd4afb756b46fc6785e5af ;;
        *) echo "Unsupported architecture: $1" >&2; return 1 ;;
    esac
}

write_systemd_service() {
    cat <<'EOF'
[Unit]
Description=Cloudflare Tunnel (VM-Setup)
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate run --token-file /etc/cloudflared/vm-setup-token
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
}

write_openrc_service() {
    cat <<'EOF'
#!/sbin/openrc-run
description="Cloudflare Tunnel (VM-Setup)"
command="/usr/local/bin/cloudflared"
command_args="tunnel --no-autoupdate run --token-file /etc/cloudflared/vm-setup-token"
command_background=true
pidfile="/run/cloudflared-vm-setup.pid"
depend() { need net; after firewall; }
EOF
}

main() {
    ((EUID == 0)) || { echo 'Run as root.' >&2; return 1; }
    local dependency token service_file
    for dependency in curl sha256sum install; do
        command -v "$dependency" >/dev/null || { echo "Install $dependency first." >&2; return 1; }
    done
    [[ "$(uname -s)" == Linux ]] || return 1
    select_cloudflared_asset "$(uname -m)"
    CF_WORK_DIR=$(mktemp -d /var/tmp/vm-cloudflared.XXXXXXXX)
    trap 'rm -rf -- "$CF_WORK_DIR"' EXIT
    curl --fail --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 20 --max-time 300 --retry 3 \
        "https://github.com/cloudflare/cloudflared/releases/download/$CLOUDFLARED_VERSION/cloudflared-linux-$CF_ARCH" -o "$CF_WORK_DIR/cloudflared"
    printf '%s  %s\n' "$CF_SHA" "$CF_WORK_DIR/cloudflared" | sha256sum -c -
    install -m 755 "$CF_WORK_DIR/cloudflared" /usr/local/bin/cloudflared
    /usr/local/bin/cloudflared --version
    echo 'Create or select a tunnel in Cloudflare and copy its connector token.'
    read -rsp 'Tunnel token (Enter skips service configuration): ' token
    echo
    [[ -n "$token" ]] || return 0
    [[ "$token" =~ ^[A-Za-z0-9_+/=-]+$ ]] || { echo 'Invalid token format.' >&2; return 1; }
    if command -v rc-service >/dev/null; then service_file=/etc/init.d/cloudflared-vm-setup
    elif command -v systemctl >/dev/null; then service_file=/etc/systemd/system/cloudflared-vm-setup.service
    else echo 'No supported service manager found.' >&2; return 1; fi
    # Keep any existing tunnel intact, including package-managed services.
    if [[ -e "$service_file" || -L "$service_file" || -e /etc/init.d/cloudflared || -e /etc/systemd/system/cloudflared.service || -e /etc/cloudflared/vm-setup-token ]]; then
        echo 'Existing tunnel configuration found. Binary updated; configure its existing service separately.' >&2
        return 1
    fi
    install -d -m 700 /etc/cloudflared
    (umask 077; set -o noclobber; printf '%s' "$token" > /etc/cloudflared/vm-setup-token)
    unset token
    if command -v rc-service >/dev/null; then
        write_openrc_service > "$CF_WORK_DIR/service"
        install -m 755 "$CF_WORK_DIR/service" "$service_file"
        rc-update add cloudflared-vm-setup default
        rc-service cloudflared-vm-setup start
        rc-service cloudflared-vm-setup status
    else
        write_systemd_service > "$CF_WORK_DIR/service"
        install -m 644 "$CF_WORK_DIR/service" "$service_file"
        systemctl daemon-reload
        systemctl enable --now cloudflared-vm-setup.service
        systemctl is-active --quiet cloudflared-vm-setup.service
    fi
    echo 'Tunnel service started. Token is stored in a root-only file.'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
