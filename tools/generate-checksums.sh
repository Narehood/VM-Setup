#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
installers_dir="$repo_root/Installers"
manifest="$installers_dir/.checksums.sha256"
temporary=$(mktemp "$installers_dir/.checksums.sha256.XXXXXXXX")

cleanup() {
    rm -f -- "$temporary"
}
trap cleanup EXIT

for script in "$installers_dir"/*.sh; do
    sha256sum "$script" | awk -v name="$(basename "$script")" '{ print $1, name }'
done | sort -k2 > "$temporary"

if [[ ! -s "$temporary" ]]; then
    echo "No installer scripts found; manifest was not changed." >&2
    exit 1
fi

mv -- "$temporary" "$manifest"
trap - EXIT
echo "Updated $manifest"
