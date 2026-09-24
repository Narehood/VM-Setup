#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck source=Installers/mtu-fix.sh
source "$repo_root/Installers/mtu-fix.sh"
NETWORK_ROOT=$fixture
mkdir -p "$fixture/etc/network/interfaces.d" "$fixture/etc/sysconfig/network" "$fixture/etc/netplan"

# NetworkManager connection names may contain colons; UUIDs avoid name parsing.
nmcli() {
    case "$*" in
        '-g GENERAL.CON-UUID device show eth0') echo 11111111-2222-3333-4444-555555555555 ;;
        '-g connection.type connection show uuid '*) echo 802-3-ethernet ;;
        '-g 802-3-ethernet.mtu connection show uuid '*) echo 1500 ;;
        'connection modify uuid '*) printf '%s\n' "$*" > "$fixture/nm-command" ;;
        *) return 1 ;;
    esac
}
apply_mtu_persistent eth0 1400
grep -Fxq 'connection modify uuid 11111111-2222-3333-4444-555555555555 802-3-ethernet.mtu 1400' "$fixture/nm-command"
nmcli() { return 1; }

printf 'BOOTPROTO=static\nIPADDR=192.0.2.10\nMTU=1500\n' > "$fixture/etc/sysconfig/network/ifcfg-eth0"
apply_mtu_persistent eth0 1350
grep -q '^IPADDR=192.0.2.10$' "$fixture/etc/sysconfig/network/ifcfg-eth0"
grep -q '^MTU=1350$' "$fixture/etc/sysconfig/network/ifcfg-eth0"

printf '[Match]\nName=eth1\n[Network]\nAddress=192.0.2.20/24\n' > "$fixture/existing.network"
networkctl() { printf '  Network File: %s/existing.network\n' "$fixture"; }
apply_mtu_persistent eth1 1400
grep -q '^MTUBytes=1400$' "$fixture/etc/systemd/network/existing.network.d/90-vm-setup-mtu.conf"
grep -q '^Address=192.0.2.20/24$' "$fixture/existing.network"

# Netplan itself is mocked; the production YAML matching code runs when PyYAML
# is available (required on the Debian/Ubuntu CI images that use this backend).
if command -v python3 >/dev/null && python3 -c 'import yaml' 2>/dev/null; then
    cat > "$fixture/etc/netplan/50-static.yaml" <<'EOF'
network:
  version: 2
  ethernets:
    uplink:
      match:
        name: eth0
      addresses: [192.0.2.10/24]
EOF
    cp "$fixture/etc/netplan/50-static.yaml" "$fixture/netplan-before"
    netplan() {
        case "$1" in
            get) cat "$fixture/etc/netplan/50-static.yaml" ;;
            set)
                [[ "$6" == network.ethernets.uplink.mtu=1400 ]]
                printf 'network:\n  ethernets:\n    uplink:\n      mtu: 1400\n' > "$3/etc/netplan/99-vm-setup-mtu.yaml" ;;
            generate) [[ -f "$3/etc/netplan/50-static.yaml" ]] ;;
            *) return 1 ;;
        esac
    }
    apply_mtu_persistent eth0 1400
    cmp "$fixture/netplan-before" "$fixture/etc/netplan/50-static.yaml"
    grep -q 'mtu: 1400' "$fixture/etc/netplan/99-vm-setup-mtu.yaml"
    cp "$fixture/etc/netplan/99-vm-setup-mtu.yaml" "$fixture/override-before"
    if apply_mtu_persistent missing0 1400; then exit 1; fi
    cmp "$fixture/override-before" "$fixture/etc/netplan/99-vm-setup-mtu.yaml"
else
    echo 'Netplan YAML matching check skipped: install python3 + PyYAML to include it.'
fi
echo 'NetworkManager, sysconfig and networkd configuration preservation: passed.'
