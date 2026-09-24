#!/bin/bash
set -euo pipefail

# DESCRIPTION: Downloads and launches a pinned, SHA-256 verified LinUtil release
# REQUIRES_ROOT: false

readonly LINUTIL_REVISION="7ed1ddb5e9c2733c4f1bb359c7af5dbd08c2261c"
readonly LINUTIL_VERSION="2026.07.17"
readonly LINUTIL_SHA256_X86_64="3e7dd8da45b644e7af3ff29bfba391ebd13772865eeefb55ea88a48c74f7d1ff"
readonly LINUTIL_SHA256_AARCH64="0504580240adc8977c831d18030469dd3c3848ce8fed3b310d94374899a8b708"

select_linutil_asset() {
    case "$1" in
        x86_64|amd64) LINUTIL_ASSET=linutil; LINUTIL_SHA256="$LINUTIL_SHA256_X86_64" ;;
        aarch64|arm64) LINUTIL_ASSET=linutil-aarch64; LINUTIL_SHA256="$LINUTIL_SHA256_AARCH64" ;;
        *) printf 'LinUtil has no pinned binary for architecture %s.\n' "$1" >&2; return 1 ;;
    esac
}

verify_linutil_asset() {
    local actual
    actual=$(sha256sum "$1") || return 1
    [[ "${actual%% *}" == "$LINUTIL_SHA256" ]]
}

main() {
    local requirement
    for requirement in curl sha256sum; do
        command -v "$requirement" >/dev/null 2>&1 || { printf '%s is required.\n' "$requirement" >&2; return 1; }
    done
    select_linutil_asset "$(uname -m)"
    printf 'LinUtil release %s (%s)\n' "$LINUTIL_VERSION" "$LINUTIL_REVISION"
    read -rp "Press [Enter] to launch this third-party utility, or Ctrl+C to cancel..." || return 1
    work_dir=$(mktemp -d "${TMPDIR:-/tmp}/linutil.XXXXXXXX")
    trap 'rm -rf -- "$work_dir"' EXIT
    curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fSL --connect-timeout 15 --max-time 180 --retry 2 \
        "https://github.com/ChrisTitusTech/linutil/releases/download/$LINUTIL_VERSION/$LINUTIL_ASSET" \
        -o "$work_dir/linutil"
    if ! verify_linutil_asset "$work_dir/linutil"; then
        printf 'LinUtil checksum verification failed.\n' >&2
        return 1
    fi
    chmod 700 "$work_dir/linutil"
    "$work_dir/linutil" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
