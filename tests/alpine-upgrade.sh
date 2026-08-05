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
    'set -o noclobber' \
    'parse_latest_release_version'
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

# Production metadata parser must handle list-style "- version:" records.
parsed=$(printf '%s\n' '- version: "3.24.1"' | parse_latest_release_version)
[[ "$parsed" == "3.24.1" ]] || {
    echo "List-style version parse failed: '$parsed'" >&2
    exit 1
}

# Versioned main/community plus tagged edge/testing must classify as versioned.
repos_tmp=$(mktemp)
trap 'rm -f -- "$repos_tmp"' EXIT
cat > "$repos_tmp" <<'EOF'
https://dl-cdn.alpinelinux.org/alpine/v3.23/main
https://dl-cdn.alpinelinux.org/alpine/v3.23/community
@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing
#https://dl-cdn.alpinelinux.org/alpine/edge/main
EOF
REPOS_FILE="$repos_tmp"
detect_repo_style
[[ "$REPO_STYLE" == "versioned" ]] || {
    echo "Expected versioned style with tagged edge overlay, got: $REPO_STYLE" >&2
    exit 1
}
[[ "$REPO_BRANCH" == "3.23" ]] || {
    echo "Expected REPO_BRANCH 3.23, got: $REPO_BRANCH" >&2
    exit 1
}
[[ "$REPO_EDGE_TAGGED" == "true" ]] || {
    echo "Expected REPO_EDGE_TAGGED=true for @testing overlay" >&2
    exit 1
}

# Untagged edge mixed with versioned repos must remain mixed.
cat > "$repos_tmp" <<'EOF'
https://dl-cdn.alpinelinux.org/alpine/v3.23/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
EOF
detect_repo_style
[[ "$REPO_STYLE" == "mixed" ]] || {
    echo "Expected mixed style for untagged edge + versioned, got: $REPO_STYLE" >&2
    exit 1
}
[[ "$REPO_BRANCH" == "3.23" ]] || {
    echo "Expected REPO_BRANCH 3.23 for mixed untagged edge case, got: $REPO_BRANCH" >&2
    exit 1
}

# Tagging untagged edge overlays should yield a versioned layout.
tag_untagged_edge_repos
detect_repo_style
[[ "$REPO_STYLE" == "versioned" ]] || {
    echo "Expected versioned after tagging edge overlays, got: $REPO_STYLE" >&2
    exit 1
}
grep -Fq '@edge https://dl-cdn.alpinelinux.org/alpine/edge/community' "$repos_tmp" || {
    echo "Expected @edge prefix on previously untagged edge community repo" >&2
    exit 1
}

if ! grep -Fq -- 'prompt_mixed_repos_continue' "$script"; then
    echo "Mixed-repo update-anyway prompt is missing." >&2
    exit 1
fi
if ! grep -Fq -- '--allow-mixed' "$script"; then
    echo "--allow-mixed flag is missing." >&2
    exit 1
fi

echo "Alpine upgrade checks passed."
