#!/bin/bash
set -euo pipefail

# DESCRIPTION: Downloads and runs a verified Docker-Prep revision
# REQUIRES_ROOT: false

readonly REPO_URL="https://github.com/Narehood/Docker-Prep.git"
readonly REPO_REVISION="9b0f944f334b2ba89ce7b5510ea2199d39f3f2b0"
readonly REPO_VERSION="2.4.0-main"
EFFECTIVE_REVISION="$REPO_REVISION"
EFFECTIVE_VERSION="$REPO_VERSION"

print_status() { printf '[INFO] %s\n' "$1"; }
print_success() { printf '[OK] %s\n' "$1"; }
print_warn() { printf '[WARN] %s\n' "$1"; }
print_error() { printf '[ERROR] %s\n' "$1" >&2; }

remote_git() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 120 git "$@"
    else
        git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 "$@"
    fi
}

# Resolve stable tags to commits, including peeled annotated tags. Until the
# upstream publishes releases, main remains an explicitly confirmed alternative.
resolve_latest_docker_prep() {
    LATEST_SHA=""
    LATEST_VERSION=""
    local refs latest_tag
    refs=$(remote_git ls-remote "$REPO_URL" 'refs/tags/v*' refs/heads/main) || return 1
    latest_tag=$(printf '%s\n' "$refs" | awk '$2 ~ /^refs\/tags\/v[0-9]+\.[0-9]+\.[0-9]+$/ {sub("refs/tags/", "", $2); print $2}' | sort -V | tail -n1)
    if [[ -n "$latest_tag" ]]; then
        LATEST_SHA=$(printf '%s\n' "$refs" | awk -v tag="refs/tags/$latest_tag" '
            $2 == tag { plain=$1 }
            $2 == tag "^{}" { peeled=$1 }
            END { print peeled != "" ? peeled : plain }
        ')
        LATEST_VERSION="$latest_tag"
    else
        LATEST_SHA=$(printf '%s\n' "$refs" | awk '$2 == "refs/heads/main" {print $1; exit}')
        LATEST_VERSION="main"
    fi
    [[ "$LATEST_SHA" =~ ^[0-9a-f]{40}$ ]]
}

check_docker_prep_update() {
    print_status "Checking for Docker-Prep updates..."
    if ! resolve_latest_docker_prep; then
        print_warn "Update check failed; keeping the bundled pin."
        return 0
    fi
    if [[ "$LATEST_SHA" == "$EFFECTIVE_REVISION" ]]; then
        print_success "Docker-Prep is current ($EFFECTIVE_REVISION)."
        return 0
    fi
    print_status "Bundled: $EFFECTIVE_VERSION ($EFFECTIVE_REVISION)"
    print_status "Available: $LATEST_VERSION ($LATEST_SHA)"
    print_status "Changes: https://github.com/Narehood/Docker-Prep/compare/$EFFECTIVE_REVISION...$LATEST_SHA"
    local answer=n
    if [[ -t 0 ]]; then
        read -rp "Use this revision for this launch only? (y/N): " answer || answer=n
    fi
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        EFFECTIVE_REVISION="$LATEST_SHA"
        EFFECTIVE_VERSION="$LATEST_VERSION"
    fi
    # Runtime choices must never rewrite a tracked launcher or its manifest.
    return 0
}

fetch_docker_prep() {
    local destination="$1"
    git -C "$destination" init -q || return 1
    git -C "$destination" remote add origin "$REPO_URL" || return 1
    remote_git -C "$destination" fetch -q --depth 1 origin "$EFFECTIVE_REVISION" || return 1
    git -C "$destination" checkout -q --detach FETCH_HEAD || return 1
    [[ "$(git -C "$destination" rev-parse HEAD)" == "$EFFECTIVE_REVISION" ]] || return 1
    [[ -f "$destination/install.sh" && ! -L "$destination/install.sh" ]]
}

main() {
    command -v git >/dev/null 2>&1 || { print_error "git is required."; return 1; }
    check_docker_prep_update
    print_status "Launching $EFFECTIVE_VERSION ($EFFECTIVE_REVISION)"
    read -rp "Press [Enter] to download and run it, or Ctrl+C to cancel..." || return 1
    work_dir=$(mktemp -d "${TMPDIR:-/tmp}/docker-prep.XXXXXXXX")
    trap 'rm -rf -- "$work_dir"' EXIT
    if ! fetch_docker_prep "$work_dir"; then
        print_error "Could not fetch and verify Docker-Prep."
        return 1
    fi
    (cd "$work_dir" && DOCKER_PREP_EPHEMERAL=1 DOCKER_PREP_REVISION="$EFFECTIVE_REVISION" bash ./install.sh)
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
