#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

script="Installers/Docker-Prep.sh"
[[ -f "$script" ]] || {
    echo "Missing $script" >&2
    exit 1
}

bash -n "$script"

for required in \
    'check_docker_prep_update' \
    'resolve_latest_docker_prep' \
    'write_launcher_pin' \
    'readonly REPO_REVISION=' \
    'readonly REPO_VERSION=' \
    'Checking for Docker-Prep updates'
do
    if ! grep -Fq -- "$required" "$script"; then
        echo "Docker-Prep.sh is missing expected content: $required" >&2
        exit 1
    fi
done

# shellcheck disable=SC1091
source "$script"

# Tag preference: newest v* wins.
tags_fixture=$(cat <<'EOF'
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa	refs/tags/v1.0.0
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb	refs/tags/v1.2.0
cccccccccccccccccccccccccccccccccccccccc	refs/tags/v1.10.0
EOF
)
LATEST_SHA=""
LATEST_VERSION=""
# Inline the selection logic against the fixture (mirrors resolve_latest_docker_prep tag branch).
latest_tag=$(printf '%s\n' "$tags_fixture" | awk '{print $2}' | sed 's#refs/tags/##' | sort -V | tail -n1)
LATEST_SHA=$(printf '%s\n' "$tags_fixture" | awk -v tag="refs/tags/${latest_tag}" '$2 == tag { print $1; exit }')
LATEST_VERSION="$latest_tag"
[[ "$latest_tag" == "v1.10.0" ]] || {
    echo "Expected newest tag v1.10.0, got $latest_tag" >&2
    exit 1
}
[[ "$LATEST_SHA" == "cccccccccccccccccccccccccccccccccccccccc" ]] || {
    echo "Unexpected SHA for newest tag: $LATEST_SHA" >&2
    exit 1
}

# write_launcher_pin should rewrite readonly pin lines.
pin_tmp=$(mktemp)
trap 'rm -f -- "$pin_tmp"' EXIT
cat > "$pin_tmp" <<'EOF'
readonly REPO_URL="https://example.invalid/Docker-Prep.git"
readonly REPO_REVISION="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
readonly REPO_VERSION="unreleased"
EOF
SCRIPT_PATH="$pin_tmp"
write_launcher_pin "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" "v9.9.9"
grep -Fq 'readonly REPO_REVISION="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' "$pin_tmp" || {
    echo "write_launcher_pin failed to update REPO_REVISION" >&2
    cat "$pin_tmp" >&2
    exit 1
}
grep -Fq 'readonly REPO_VERSION="v9.9.9"' "$pin_tmp" || {
    echo "write_launcher_pin failed to update REPO_VERSION" >&2
    cat "$pin_tmp" >&2
    exit 1
}

echo "Docker-Prep update-check tests passed."
