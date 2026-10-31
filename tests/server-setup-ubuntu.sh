#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

# Run the real guest-tools dispatch in a fresh shell so errexit stays enabled.
# Ubuntu 24.04's xe-guest-utilities package ships xe-daemon.service.
run_guest_setup() {
    bash -s -- "$repo_root" "$fixture" "$@" <<'EOF'
set -euo pipefail
# shellcheck source=Installers/serverSetup.sh
source "$1/Installers/serverSetup.sh"
commands="$2/commands"
OS=$3
package_status=$4
service_status=$5
prompt_yes_no() { return 0; }
apt-get() {
    printf 'apt-get %s\n' "$*" >> "$commands"
    if [[ "$1" == install ]]; then return "$package_status"; fi
}
systemctl() {
    printf 'systemctl %s\n' "$*" >> "$commands"
    if [[ "$*" != 'enable --now xe-daemon.service' ]]; then
        echo "Failed to enable unit: Unit file ${*: -1} does not exist." >&2
        return 1
    fi
    return "$service_status"
}
eval "$(sed -n '/^# XCP-NG Tools Installation$/,/^# Install Standard Server Tools$/p' "$1/Installers/serverSetup.sh")"
EOF
}

for distro in ubuntu pop linuxmint; do
    : > "$fixture/commands"
    run_guest_setup "$distro" 0 0 > "$fixture/output"
    grep -Fxq 'apt-get install -y -qq xe-guest-utilities' "$fixture/commands"
    grep -Fxq 'systemctl enable --now xe-daemon.service' "$fixture/commands"
    grep -q 'XCP-NG tools installed.' "$fixture/output"
done

for failure in package service; do
    : > "$fixture/commands"
    package_status=0 service_status=0
    if [[ "$failure" == package ]]; then package_status=17; else service_status=18; fi
    if run_guest_setup ubuntu "$package_status" "$service_status" > "$fixture/output"; then
        echo "Guest tools setup ignored a $failure failure." >&2
        exit 1
    fi
    if grep -q 'XCP-NG tools installed.' "$fixture/output"; then exit 1; fi
    if [[ "$failure" == package ]] && grep -q '^systemctl ' "$fixture/commands"; then exit 1; fi
done

echo 'Ubuntu guest-tools service selection and failure propagation: passed.'
