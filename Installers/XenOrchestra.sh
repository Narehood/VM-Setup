#!/usr/bin/env bash
# REQUIRES_ROOT: true
# DESCRIPTION: Runs the verified Xen Orchestra installer (upstream distro requirements apply)
set -euo pipefail
readonly REPO_URL="https://github.com/Narehood/XenOrchestraInstallerUpdater.git"
readonly REPO_REVISION="3c2a24b50c6b247b9d330ee151fcdbb42d305083"

main() {
    command -v git >/dev/null || { echo 'Install git first.' >&2; return 1; }
    ((EUID == 0)) || { echo 'Run as root.' >&2; return 1; }
    XO_WORK_DIR=$(mktemp -d /var/tmp/vm-xo.XXXXXXXX)
    trap 'rm -rf -- "$XO_WORK_DIR"' EXIT
    git init -q "$XO_WORK_DIR"
    git -C "$XO_WORK_DIR" remote add origin "$REPO_URL"
    git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 -C "$XO_WORK_DIR" fetch --depth 1 origin "$REPO_REVISION"
    git -C "$XO_WORK_DIR" checkout --detach -q FETCH_HEAD
    [[ "$(git -C "$XO_WORK_DIR" rev-parse HEAD)" == "$REPO_REVISION" ]]
    [[ -f "$XO_WORK_DIR/xo-install.sh" && ! -L "$XO_WORK_DIR/xo-install.sh" ]]
    local config="${XO_CONFIG_FILE:-/etc/vm-setup/xo-install.cfg}"
    if [[ ! -e "$config" ]]; then
        install -d -m 700 "$(dirname "$config")"
        (umask 077; set -o noclobber; cat "$XO_WORK_DIR/sample.xo-install.cfg" > "$config")
    fi
    [[ -f "$config" && ! -L "$config" ]]
    cp "$config" "$XO_WORK_DIR/xo-install.cfg"
    install -d -m 700 /var/log/vm-setup-xo
    # The upstream config is sourced before defaults; enforce pinning after it.
    printf '\nSELFUPGRADE=false\nLOGPATH=/var/log/vm-setup-xo\n' >> "$XO_WORK_DIR/xo-install.cfg"
    echo "Xen Orchestra installer: $REPO_REVISION; configuration: $config"
    bash "$XO_WORK_DIR/xo-install.sh" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
