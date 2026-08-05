#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

script="Installers/alpineUpgrade.sh"

[[ -f "$script" ]] || {
    echo "Missing $script" >&2
    exit 1
}

bash -n "$script"

for required in \
    'Upgrade Alpine Linux to a newer release branch' \
    'apk upgrade --available' \
    'normalize_branch' \
    'build_upgrade_path' \
    'update_repos_to_branch' \
    'latest-releases.yaml' \
    '--target RELEASE' \
    'REPOS_BACKUP' \
    'on_upgrade_error' \
    'set -o noclobber'
do
    if ! grep -Fq -- "$required" "$script"; then
        echo "alpineUpgrade.sh is missing expected content: $required" >&2
        exit 1
    fi
done

if ! grep -Fq 'alpineUpgrade.sh:Alpine Release Upgrade' Installers/serverConfig.sh; then
    echo "Server Config menu must expose Alpine Release Upgrade." >&2
    exit 1
fi

# Source installer helpers (source guard skips main execution).
# shellcheck disable=SC1091
source "$script"
LOG_ENABLED="false"

got=$(normalize_branch "3.23.5")
[[ "$got" == "3.23" ]] || {
    echo "normalize_branch failed for 3.23.5 -> got $got" >&2
    exit 1
}

got=$(normalize_branch "v3.24")
[[ "$got" == "3.24" ]] || {
    echo "normalize_branch failed for v3.24 -> got $got" >&2
    exit 1
}

status=0
compare_branches "3.23" "3.24" || status=$?
[[ "$status" -eq 0 ]] || {
    echo "compare_branches should treat 3.23 < 3.24" >&2
    exit 1
}

status=0
compare_branches "3.24" "3.24" || status=$?
[[ "$status" -eq 1 ]] || {
    echo "compare_branches should treat equal branches as equal" >&2
    exit 1
}

status=0
compare_branches "3.24" "3.23" || status=$?
[[ "$status" -eq 2 ]] || {
    echo "compare_branches should treat 3.24 > 3.23" >&2
    exit 1
}

path=$(build_upgrade_path "3.22" "3.24" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
[[ "$path" == "3.23 3.24" ]] || {
    echo "Unexpected upgrade path for 3.22 -> 3.24: '$path'" >&2
    exit 1
}

path=$(build_upgrade_path "3.23" "3.24" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
[[ "$path" == "3.24" ]] || {
    echo "Unexpected upgrade path for 3.23 -> 3.24: '$path'" >&2
    exit 1
}

# Cross-major targets must be rejected by the installer implementation.
if major_err=$(build_upgrade_path "3.24" "4.0" 2>&1); then
    echo "build_upgrade_path should reject cross-major upgrades" >&2
    exit 1
fi
printf '%s\n' "$major_err" | grep -Fq 'across major series' || {
    echo "Cross-major rejection message missing: $major_err" >&2
    exit 1
}

# awk version extraction must handle list-style "- version:" records.
parsed=$(printf '%s\n' '- version: "3.24.1"' | awk '
    /^[[:space:]]*-?[[:space:]]*version:[[:space:]]*/ {
        sub(/^[[:space:]]*-?[[:space:]]*version:[[:space:]]*/, "")
        gsub(/["'\'']/, "")
        print
        exit
    }
')
[[ "$parsed" == "3.24.1" ]] || {
    echo "List-style version parse failed: '$parsed'" >&2
    exit 1
}

echo "Alpine upgrade checks passed."
