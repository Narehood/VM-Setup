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
    '--target RELEASE'
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

# Pure bash helpers mirrored from the installer for unit-style checks.
normalize_branch() {
    local raw="$1"
    raw="${raw#v}"
    if [[ "$raw" =~ ^([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]]; then
        echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

compare_branches() {
    local a_major a_minor b_major b_minor
    IFS=. read -r a_major a_minor <<< "$1"
    IFS=. read -r b_major b_minor <<< "$2"

    if ((a_major < b_major)); then
        return 0
    elif ((a_major > b_major)); then
        return 2
    elif ((a_minor < b_minor)); then
        return 0
    elif ((a_minor > b_minor)); then
        return 2
    fi
    return 1
}

next_branch() {
    local major minor
    IFS=. read -r major minor <<< "$1"
    echo "${major}.$((minor + 1))"
}

build_upgrade_path() {
    local start="$1"
    local end="$2"
    local cursor path=() cmp=0

    compare_branches "$start" "$end" || cmp=$?
    case $cmp in
        1) return 0 ;;
        2) return 2 ;;
    esac

    cursor="$start"
    while true; do
        cursor=$(next_branch "$cursor")
        path+=("$cursor")
        cmp=0
        compare_branches "$cursor" "$end" || cmp=$?
        case $cmp in
            1) break ;;
            2) return 2 ;;
        esac
    done

    printf '%s\n' "${path[@]}"
}

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

echo "Alpine upgrade checks passed."
