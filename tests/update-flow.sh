#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

# shellcheck disable=SC1091
source /dev/null

read_launcher_constant() {
    local file_path="$1"
    local constant_name="$2"
    awk -F= -v name="$constant_name" '
        $0 ~ "^readonly[[:space:]]+" name "=" {
            value=$2
            gsub(/"/, "", value)
            print value
            exit
        }
    ' "$file_path"
}

docker_rev=$(read_launcher_constant Installers/Docker-Prep.sh REPO_REVISION)
docker_ver=$(read_launcher_constant Installers/Docker-Prep.sh REPO_VERSION)
linutil_rev=$(read_launcher_constant Installers/linutil.sh LINUTIL_REVISION)

[[ "$docker_rev" =~ ^[0-9a-f]{40}$ ]] || {
    echo "Unexpected Docker-Prep revision: $docker_rev" >&2
    exit 1
}
[[ -n "$docker_ver" ]] || {
    echo "Docker-Prep version pin is empty." >&2
    exit 1
}
[[ "$linutil_rev" =~ ^[0-9a-f]{40}$ ]] || {
    echo "Unexpected LinUtil revision: $linutil_rev" >&2
    exit 1
}

state_file=$(mktemp)
trap 'rm -f -- "$state_file"' EXIT
cat > "$state_file" <<EOF
mode=auto
previous_commit=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
previous_version=3.7.2
previous_docker_prep_revision=d50a3bddfd32419791dea74ca26b898275781778
previous_docker_prep_version=unreleased
previous_linutil_revision=41fc99189a588bfa82190fe49a1baf23fd65e97f
new_commit=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
new_version=3.8.0
new_docker_prep_revision=cccccccccccccccccccccccccccccccccccccccc
new_docker_prep_version=v1.2.0
new_linutil_revision=41fc99189a588bfa82190fe49a1baf23fd65e97f
release_url=https://github.com/Narehood/VM-Setup/compare/aaaaaaaaaaaa...bbbbbbbbbbbb
EOF

mode=$(sed -n 's/^mode=//p' "$state_file")
new_version=$(sed -n 's/^new_version=//p' "$state_file")
release_url=$(sed -n 's/^release_url=//p' "$state_file")

[[ "$mode" == "auto" ]] || exit 1
[[ "$new_version" == "3.8.0" ]] || exit 1
[[ "$release_url" == "https://github.com/Narehood/VM-Setup/compare/aaaaaaaaaaaa...bbbbbbbbbbbb" ]] || exit 1

if ! grep -q 'check_for_updates_automatic' install.sh; then
    echo "Automatic update path is missing from install.sh" >&2
    exit 1
fi

if ! grep -q 'show_pending_update_summary' install.sh; then
    echo "Update summary display is missing from install.sh" >&2
    exit 1
fi

# Scheduled Docker-Prep pin sync must no-op when releases/latest 404s.
if ! grep -q "steps.release.outputs.skip != 'true'" .github/workflows/sync-docker-prep-pin.yml; then
    echo "Sync Docker-Prep pin workflow must skip remaining steps when no release exists." >&2
    exit 1
fi
if ! grep -q 'Scheduled sync has nothing to do until the first release exists.' .github/workflows/sync-docker-prep-pin.yml; then
    echo "Sync Docker-Prep pin workflow must explain schedule no-op when releases are missing." >&2
    exit 1
fi
if ! grep -q 'No GitHub Releases found in' tools/sync-docker-prep-pin.sh; then
    echo "sync-docker-prep-pin.sh must report a clear error when releases/latest is missing." >&2
    exit 1
fi

if ! grep -q 'Choose an option to update anyway' install.sh; then
    echo "Automatic update path must offer an update-anyway prompt for local changes." >&2
    exit 1
fi
if ! grep -q 'Stash changes and continue' install.sh; then
    echo "Uncommitted-change handler must offer stash-and-continue." >&2
    exit 1
fi

echo "Update flow checks passed."
