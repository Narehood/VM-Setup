#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

(
    # shellcheck source=Installers/WordPress.sh
    source "$repo_root/Installers/WordPress.sh"
    INSTALL_DIR="$fixture/existing-site" CREDS_FILE="$fixture/credentials"
    mkdir "$INSTALL_DIR"
    echo precious > "$INSTALL_DIR/wp-config.php"
    echo existing > "$CREDS_FILE"
    if check_existing_wordpress; then exit 1; fi
    run_mysql_sql() { echo "$1" >> "$fixture/sql"; }
    cleanup
    [[ "$(cat "$INSTALL_DIR/wp-config.php")" == precious ]]
    [[ "$(cat "$CREDS_FILE")" == existing && ! -f "$fixture/sql" ]]
    INSTALL_DIR="$fixture/new-site"; mkdir "$INSTALL_DIR"
    SITE_CREATED=true DB_CREATED=true DB_USER_CREATED=false DB_NAME=wp_test
    cleanup
    [[ ! -e "$INSTALL_DIR" ]]
    grep -Fq 'DROP DATABASE `wp_test`;' "$fixture/sql"
    if grep -q 'DROP USER' "$fixture/sql"; then exit 1; fi
    OS=arch
    pacman() { return 17; }
    if install_pkg php; then echo 'Package failure swallowed' >&2; exit 1; fi
    WORK_DIR="$fixture/download"; mkdir -p "$WORK_DIR" "$fixture/archive/wordpress"
    touch "$fixture/archive/wordpress/"{wp-settings.php,wp-config-sample.php}
    tar -czf "$fixture/source.tar.gz" -C "$fixture/archive" wordpress
    curl() { [[ "${*: -2:1}" == -o ]]; cp "$fixture/source.tar.gz" "${*: -1}"; }
    download_wordpress
    [[ -f "$WORK_DIR/site/wp-settings.php" ]]
)

(
    # shellcheck source=Installers/mtu-fix.sh
    source "$repo_root/Installers/mtu-fix.sh"
    test_mtu_size() { (( $1 <= 1400 )); }
    prompt_yes_no() { return 0; }
    [[ "$(test_mtu_values)" == 1400 ]]
    test_mtu_size() { return 0; }
    [[ "$(test_mtu_values)" == 1500 ]]
    prompt_yes_no() { return 1; }
    if test_mtu_values > "$fixture/probe-output"; then exit 1; fi
    [[ ! -s "$fixture/probe-output" ]]
    config="$fixture/daemon.json"
    printf '{"log-driver":"local","dns":["1.1.1.1"],"mtu":1500}\n' > "$config"
    update_docker_json "$config" 1400
    jq -e '.mtu==1400 and ."log-driver"=="local" and .dns==["1.1.1.1"]' "$config" >/dev/null
    update_docker_json "$config" reset
    jq -e '(has("mtu")|not) and ."log-driver"=="local"' "$config" >/dev/null
    printf '{invalid json' > "$config"
    cp "$config" "$fixture/invalid-original"
    if update_docker_json "$config" 1400; then exit 1; fi
    cmp "$config" "$fixture/invalid-original"
    command() {
        if [[ "$*" == '-v jq' ]]; then return 1; fi
        builtin command "$@"
    }
    if update_docker_json "$config" 1400; then exit 1; fi
    cmp "$config" "$fixture/invalid-original"
    unset -f command
    cat > "$fixture/interfaces" <<'EOF'
auto eth0
iface eth0 inet static
    address 192.0.2.10/24
    gateway 192.0.2.1
iface eth1 inet dhcp
    mtu 1500
EOF
    apply_ifupdown_mtu "$fixture/interfaces" eth0 1400
    grep -Fq 'address 192.0.2.10/24' "$fixture/interfaces"
    grep -Fq 'gateway 192.0.2.1' "$fixture/interfaces"
    [[ "$(grep -c 'mtu 1400' "$fixture/interfaces")" -eq 1 ]]
    apply_ifupdown_mtu "$fixture/interfaces" eth0 1350
    [[ "$(grep -c 'mtu ' "$fixture/interfaces")" -eq 2 ]]
    cp "$fixture/interfaces" "$fixture/interfaces-before"
    if apply_ifupdown_mtu "$fixture/interfaces" missing0 1400; then exit 1; fi
    cmp "$fixture/interfaces" "$fixture/interfaces-before"
)

(
    # shellcheck source=Installers/serverSetup.sh
    source "$repo_root/Installers/serverSetup.sh"
    umount() { printf '%s\n' "$*" >> "$fixture/unmounts"; }
    cleanup
    [[ ! -f "$fixture/unmounts" ]]
    GUEST_TOOLS_MOUNT="$fixture/owned-mount"; mkdir "$GUEST_TOOLS_MOUNT"
    GUEST_TOOLS_MOUNTED=true
    cleanup
    [[ "$(cat "$fixture/unmounts")" == "$fixture/owned-mount" ]]
    GUEST_TOOLS_MOUNT="$fixture/media"
    mkdir -p "$GUEST_TOOLS_MOUNT" "$fixture/guest-archive/usr/sbin" "$fixture/guest-archive/usr/bin"
    printf 'guest-agent-fixture\n' > "$fixture/guest-archive/usr/sbin/xe-daemon"
    printf 'distribution-fixture\n' > "$fixture/guest-archive/usr/sbin/xe-linux-distribution"
    printf 'xenstore-fixture\n' > "$fixture/guest-archive/usr/bin/xenstore"
    tar -czf "$GUEST_TOOLS_MOUNT/xe-guest-utilities_test_all.tgz" -C "$fixture/guest-archive" usr
    install() { printf '%s\n' "$*" >> "$fixture/guest-install-commands"; }
    ln() { printf '%s\n' "$*" >> "$fixture/guest-install-commands"; }
    systemctl() { printf '%s\n' "$*" >> "$fixture/guest-install-commands"; }
    install_guest_tools_archive
    grep -q 'enable --now xe-linux-distribution.service' "$fixture/guest-install-commands"
    [[ "$(cat "$GUEST_TOOLS_STAGE/xe-daemon")" == guest-agent-fixture ]]
    cleanup
)

(
    # shellcheck source=Installers/systemUpdate.sh
    source "$repo_root/Installers/systemUpdate.sh"
    OS=debian QUIET=true LOG_ENABLED=false NEEDS_REBOOT=false
    check_reboot_required
    print_status no-log
    print_success no-log
    LOCKFILE="$fixture/update.lock"
    echo 999999 > "$LOCKFILE"
    if acquire_lock; then exit 1; fi
    cleanup
    [[ "$(cat "$LOCKFILE")" == 999999 ]]
)

# Run a nested failure in a fresh Bash process; calling it in an if condition
# would disable errexit in the very function whose ERR handling is being tested.
set +e
bash -c 'source "$1/Installers/alpineUpgrade.sh"; REPOS_BACKUP="$2/backup"; REPOS_FILE="$2/repos"; LOG_ENABLED=false; touch "$REPOS_BACKUP"; trap on_upgrade_error ERR; nested() { false; }; nested' _ "$repo_root" "$fixture" > "$fixture/alpine-error" 2>&1
status=$?
set -e
[[ "$status" -ne 0 ]]
grep -Fq 'Repository-only recovery' "$fixture/alpine-error"

(
    # shellcheck source=Installers/github-ssh-keys.sh
    source "$repo_root/Installers/github-ssh-keys.sh"
    mkdir -p "$fixture/home/.ssh"
    printf 'restrict ssh-ed25519 AAAA old-comment' > "$fixture/home/.ssh/authorized_keys"
    show_header() { :; }
    resolve_target_user() { echo test; }
    resolve_target_home() { echo "$fixture/home"; }
    set_target_ownership() { :; }
    fetch_keys() { printf 'ssh-ed25519 BBBB new-key\nssh-ed25519 AAAA renamed\n' > "$2"; }
    main <<< 'example'
    [[ "$(wc -l < "$fixture/home/.ssh/authorized_keys")" -eq 2 ]]
    grep -Fxq 'restrict ssh-ed25519 AAAA old-comment' "$fixture/home/.ssh/authorized_keys"
    grep -Fxq 'ssh-ed25519 BBBB new-key' "$fixture/home/.ssh/authorized_keys"
)

(
    # shellcheck source=Installers/linutil.sh
    source "$repo_root/Installers/linutil.sh"
    select_linutil_asset x86_64
    [[ "$LINUTIL_ASSET" == linutil ]]
    select_linutil_asset aarch64
    [[ "$LINUTIL_ASSET" == linutil-aarch64 ]]
    if select_linutil_asset unknown; then exit 1; fi
    echo corrupt > "$fixture/binary"
    if verify_linutil_asset "$fixture/binary"; then exit 1; fi
)

(
    # shellcheck source=Installers/motd-config.sh
    source "$repo_root/Installers/motd-config.sh"
    SSH_CONFIG="$fixture/sshd_config"
    printf 'Port 22\nMatch User restricted\n    PasswordAuthentication no\n' > "$SSH_CONFIG"
    sshd() { grep -q '^Banner /etc/issue.net$' "$3"; }
    rc-service() { :; }
    apply_ssh_banner /etc/issue.net
    [[ "$(head -n1 "$SSH_CONFIG")" == 'Banner /etc/issue.net' ]]
    cp "$SSH_CONFIG" "$fixture/ssh-before"
    sshd() { return 1; }
    if apply_ssh_banner none; then exit 1; fi
    cmp "$SSH_CONFIG" "$fixture/ssh-before"
)

(
    # Extract only the patched helpers; never run the vendored installer in tests.
    # shellcheck disable=SC1090
    source <(sed -n '/^set_curl_arguments() {/,/^}/p; /^update_script() {/,/^}/p' "$repo_root/Installers/UniFi-Controller.sh")
    locate_http_proxy() { :; }
    curl_proxy_arg=()
    curl_argument=()
    set_curl_arguments
    [[ " ${curl_argument[*]} " != *' --insecure '* ]]
    [[ " ${curl_argument[*]} " == *" --proto =https "* ]]
    curl() { echo unexpected > "$fixture/unifi-update-request"; return 1; }
    update_script
    [[ ! -f "$fixture/unifi-update-request" ]]
)
echo 'Installer failure, cleanup, MTU, SSH, lock and download regressions: passed.'
