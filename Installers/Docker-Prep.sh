#!/bin/bash
set -euo pipefail

# DESCRIPTION: Downloads and runs a pinned revision of the Docker-Prep installer
# REQUIRES_ROOT: false

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

readonly REPO_URL="https://github.com/Narehood/Docker-Prep.git"
readonly REPO_REVISION="d50a3bddfd32419791dea74ca26b898275781778"
readonly REPO_VERSION="unreleased"

# Runtime pin used for this launch (may be updated before fetch).
EFFECTIVE_REVISION="$REPO_REVISION"
EFFECTIVE_VERSION="$REPO_VERSION"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${CYAN}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# resolve_latest_docker_prep sets LATEST_SHA and LATEST_VERSION from remote tags or main.
# Prefers the newest v* tag when present; otherwise uses refs/heads/main.
resolve_latest_docker_prep() {
    LATEST_SHA=""
    LATEST_VERSION=""

    local tags_out latest_tag main_sha
    tags_out=$(git ls-remote --tags --refs "$REPO_URL" 'refs/tags/v*' 2>/dev/null || true)
    if [[ -n "$tags_out" ]]; then
        latest_tag=$(printf '%s\n' "$tags_out" | awk '{print $2}' | sed 's#refs/tags/##' | sort -V | tail -n1)
        if [[ -n "$latest_tag" ]]; then
            LATEST_SHA=$(printf '%s\n' "$tags_out" | awk -v tag="refs/tags/${latest_tag}" '$2 == tag { print $1; exit }')
            LATEST_VERSION="$latest_tag"
        fi
    fi

    if [[ "$LATEST_SHA" =~ ^[0-9a-f]{40}$ ]]; then
        return 0
    fi

    main_sha=$(git ls-remote "$REPO_URL" refs/heads/main 2>/dev/null | awk '{print $1; exit}' || true)
    if [[ "$main_sha" =~ ^[0-9a-f]{40}$ ]]; then
        LATEST_SHA="$main_sha"
        LATEST_VERSION="main"
        return 0
    fi

    return 1
}

# write_launcher_pin updates readonly REPO_REVISION / REPO_VERSION in this launcher script.
write_launcher_pin() {
    local sha="$1"
    local version="$2"
    local temporary

    temporary=$(mktemp)
    if ! awk -v sha="$sha" -v version="$version" '
        BEGIN { updated_revision=0; updated_version=0 }
        /^readonly REPO_REVISION=/ {
            print "readonly REPO_REVISION=\"" sha "\""
            updated_revision=1
            next
        }
        /^readonly REPO_VERSION=/ {
            print "readonly REPO_VERSION=\"" version "\""
            updated_version=1
            next
        }
        { print }
        END {
            if (!updated_revision || !updated_version) {
                exit 2
            }
        }
    ' "$SCRIPT_PATH" > "$temporary"; then
        rm -f -- "$temporary"
        return 1
    fi

    cat "$temporary" > "$SCRIPT_PATH"
    rm -f -- "$temporary"
    return 0
}

# refresh_checksum_manifest regenerates Installers/.checksums.sha256 when the helper exists.
refresh_checksum_manifest() {
    if [[ -f "$REPO_ROOT/tools/generate-checksums.sh" ]]; then
        bash "$REPO_ROOT/tools/generate-checksums.sh" >/dev/null
        return $?
    fi
    return 1
}

# check_docker_prep_update compares the local pin to the latest remote revision and offers to update.
check_docker_prep_update() {
    print_status "Checking for Docker-Prep updates..."

    if ! resolve_latest_docker_prep; then
        print_warn "Could not determine the latest Docker-Prep revision; continuing with the current pin."
        return 0
    fi

    if [[ "$LATEST_SHA" == "$EFFECTIVE_REVISION" ]]; then
        print_success "Docker-Prep pin is up to date (${EFFECTIVE_VERSION} / ${EFFECTIVE_REVISION:0:12})."
        return 0
    fi

    print_warn "A newer Docker-Prep revision is available."
    print_status "Current pin: ${EFFECTIVE_VERSION} (${EFFECTIVE_REVISION:0:12})"
    print_status "Latest:      ${LATEST_VERSION} (${LATEST_SHA:0:12})"
    echo ""

    local answer="n"
    if [[ -t 0 ]]; then
        read -rp "Update the VM-Setup pin and run the latest revision? (y/N): " answer || answer="n"
    else
        print_status "Non-interactive session; keeping the current pin."
        return 0
    fi
    answer=${answer:-n}

    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        print_status "Continuing with the current pin."
        return 0
    fi

    if ! write_launcher_pin "$LATEST_SHA" "$LATEST_VERSION"; then
        print_error "Failed to update the Docker-Prep pin in $SCRIPT_PATH."
        print_status "Continuing with the current pin."
        return 0
    fi

    EFFECTIVE_REVISION="$LATEST_SHA"
    EFFECTIVE_VERSION="$LATEST_VERSION"

    if refresh_checksum_manifest; then
        print_success "Updated pin and refreshed installer checksums."
    else
        print_warn "Pin updated, but checksum refresh failed. Re-run: bash tools/generate-checksums.sh"
    fi
}

# --- MAIN ---
# When sourced (e.g. by tests), expose helpers only and skip execution.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
fi

if ! command -v git &>/dev/null; then
    print_error "git is required to securely fetch Docker-Prep."
    exit 1
fi

check_docker_prep_update

print_status "Docker-Prep is pinned to ${EFFECTIVE_VERSION} (${EFFECTIVE_REVISION})"
read -rp "Press [Enter] to download and run it, or Ctrl+C to cancel..."

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/docker-prep.XXXXXXXX")
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

git -C "$work_dir" init -q
git -C "$work_dir" remote add origin "$REPO_URL"
if ! git -C "$work_dir" fetch -q --depth 1 origin "$EFFECTIVE_REVISION"; then
    print_error "Failed to fetch Docker-Prep revision ${EFFECTIVE_REVISION}."
    exit 1
fi
git -C "$work_dir" checkout -q --detach FETCH_HEAD

actual_revision=$(git -C "$work_dir" rev-parse HEAD)
if [[ "$actual_revision" != "$EFFECTIVE_REVISION" ]]; then
    print_error "Docker-Prep revision verification failed."
    exit 1
fi
if [[ ! -f "$work_dir/install.sh" ]]; then
    print_error "Pinned Docker-Prep entrypoint was not found."
    exit 1
fi

print_success "Verified Docker-Prep revision. Starting installer..."
(
    cd "$work_dir"
    DOCKER_PREP_EPHEMERAL=1 \
        DOCKER_PREP_REVISION="$EFFECTIVE_REVISION" \
        bash ./install.sh
)
