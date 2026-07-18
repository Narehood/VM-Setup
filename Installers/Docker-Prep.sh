#!/bin/bash
set -euo pipefail

# DESCRIPTION: Downloads and runs a pinned revision of the Docker-Prep installer

readonly REPO_URL="https://github.com/Narehood/Docker-Prep.git"
readonly REPO_REVISION="d50a3bddfd32419791dea74ca26b898275781778"
readonly REPO_VERSION="unreleased"

if ! command -v git &>/dev/null; then
    echo "ERROR: git is required to securely fetch Docker-Prep." >&2
    exit 1
fi

echo "Docker-Prep is pinned to ${REPO_VERSION} (${REPO_REVISION})"
read -rp "Press [Enter] to download and run it, or Ctrl+C to cancel..."

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/docker-prep.XXXXXXXX")
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

git -C "$work_dir" init -q
git -C "$work_dir" remote add origin "$REPO_URL"
git -C "$work_dir" fetch -q --depth 1 origin "$REPO_REVISION"
git -C "$work_dir" checkout -q --detach FETCH_HEAD

actual_revision=$(git -C "$work_dir" rev-parse HEAD)
if [[ "$actual_revision" != "$REPO_REVISION" ]]; then
    echo "ERROR: Docker-Prep revision verification failed." >&2
    exit 1
fi
if [[ ! -f "$work_dir/install.sh" ]]; then
    echo "ERROR: Pinned Docker-Prep entrypoint was not found." >&2
    exit 1
fi

echo "Verified Docker-Prep revision. Starting installer..."
(
    cd "$work_dir"
    DOCKER_PREP_EPHEMERAL=1 \
        DOCKER_PREP_REVISION="$REPO_REVISION" \
        bash ./install.sh
)
