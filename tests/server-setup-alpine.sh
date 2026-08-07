#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

script="Installers/serverSetup.sh"
[[ -f "$script" ]] || {
    echo "Missing $script" >&2
    exit 1
}

bash -n "$script"

for required in \
    'ensure_alpine_guest_tool_repos' \
    'install_alpine_xe_guest_utilities' \
    'setup-apkrepos -c' \
    '@edge' \
    '/community'
do
    if ! grep -Fq -- "$required" "$script"; then
        echo "serverSetup.sh is missing expected content: $required" >&2
        exit 1
    fi
done

# shellcheck disable=SC1091
source "$script"
QUIET="true"
OS="alpine"
OS_VERSION="3.24.1"
PKG_MANAGER_UPDATED="false"

repos_tmp=$(mktemp)
trap 'rm -f -- "$repos_tmp"' EXIT
cat > "$repos_tmp" <<'EOF'
https://dl-cdn.alpinelinux.org/alpine/v3.24/main
#https://dl-cdn.alpinelinux.org/alpine/v3.24/community
EOF
ALPINE_REPOS_FILE="$repos_tmp"

# Avoid calling real setup-apkrepos in the test environment.
setup-apkrepos() { return 1; }

ensure_alpine_guest_tool_repos

grep -Eq '^https://dl-cdn.alpinelinux.org/alpine/v3.24/community$' "$repos_tmp" || {
    echo "Expected uncommented/added v3.24/community line" >&2
    cat "$repos_tmp" >&2
    exit 1
}
grep -Eq '^@edge https://dl-cdn.alpinelinux.org/alpine/edge/community$' "$repos_tmp" || {
    echo "Expected tagged @edge community overlay" >&2
    cat "$repos_tmp" >&2
    exit 1
}

# Idempotent on second run.
ensure_alpine_guest_tool_repos
community_count=$(grep -c '/alpine/v3.24/community' "$repos_tmp" || true)
edge_count=$(grep -c '^@edge .*/alpine/edge/community' "$repos_tmp" || true)
[[ "$community_count" -eq 1 ]] || {
    echo "Community line should remain unique, got $community_count" >&2
    cat "$repos_tmp" >&2
    exit 1
}
[[ "$edge_count" -eq 1 ]] || {
    echo "Edge overlay should remain unique, got $edge_count" >&2
    cat "$repos_tmp" >&2
    exit 1
}

echo "Server setup Alpine repo checks passed."
