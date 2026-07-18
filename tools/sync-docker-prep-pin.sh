#!/usr/bin/env bash
set -euo pipefail

# Updates Installers/Docker-Prep.sh to a Docker-Prep release commit and regenerates
# the trusted checksum manifest. Intended for CI and release maintenance.

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
launcher="$repo_root/Installers/Docker-Prep.sh"
docker_prep_repo="${DOCKER_PREP_REPO:-Narehood/Docker-Prep}"
requested_ref="${1:-}"

if [[ ! -f "$launcher" ]]; then
    echo "Docker-Prep launcher not found: $launcher" >&2
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "gh is required to resolve Docker-Prep releases." >&2
    exit 1
fi

if [[ -z "$requested_ref" ]]; then
    requested_ref=$(gh api "repos/${docker_prep_repo}/releases/latest" --jq '.tag_name')
fi

if [[ -z "$requested_ref" || "$requested_ref" == "null" ]]; then
    echo "Unable to resolve a Docker-Prep release tag." >&2
    exit 1
fi

release_json=$(gh api "repos/${docker_prep_repo}/releases/tags/${requested_ref}")
release_name=$(printf '%s' "$release_json" | jq -r '.name // .tag_name')
release_url=$(printf '%s' "$release_json" | jq -r '.html_url')
release_notes=$(printf '%s' "$release_json" | jq -r '.body // ""')

tag_ref_json=$(gh api "repos/${docker_prep_repo}/git/ref/tags/${requested_ref}")
target_sha=$(printf '%s' "$tag_ref_json" | jq -r '.object.sha')
object_type=$(printf '%s' "$tag_ref_json" | jq -r '.object.type')
if [[ "$object_type" == "tag" ]]; then
    target_sha=$(gh api "repos/${docker_prep_repo}/git/tags/${target_sha}" --jq '.object.sha')
fi

if [[ ! "$target_sha" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Unable to resolve a 40-character commit for ${requested_ref}." >&2
    exit 1
fi

current_sha=$(awk -F= '/^readonly REPO_REVISION=/{ gsub(/"/, "", $2); print $2 }' "$launcher")
current_version=$(awk -F= '/^readonly REPO_VERSION=/{ gsub(/"/, "", $2); print $2 }' "$launcher")

if [[ "$current_sha" == "$target_sha" && "$current_version" == "$requested_ref" ]]; then
    echo "Docker-Prep pin already matches ${requested_ref} (${target_sha})."
    exit 0
fi

temporary=$(mktemp)
trap 'rm -f -- "$temporary"' EXIT

awk -v sha="$target_sha" -v version="$requested_ref" '
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
        if (!updated_revision) {
            exit 2
        }
        if (!updated_version) {
            exit 3
        }
    }
' "$launcher" > "$temporary"

mv -- "$temporary" "$launcher"
trap - EXIT

bash "$repo_root/tools/generate-checksums.sh"

cat > "$repo_root/.docker-prep-pin-update.md" <<EOF
## Docker-Prep pin update

| Field | Value |
| :--- | :--- |
| Previous pin | \`${current_sha:0:12}\` (${current_version:-unknown}) |
| New pin | \`${target_sha:0:12}\` (${requested_ref}) |
| Release | [${release_name}](${release_url}) |

### Release notes

${release_notes:-_No release notes provided._}
EOF

echo "Updated Docker-Prep pin to ${requested_ref} (${target_sha})"
echo "Summary written to .docker-prep-pin-update.md"
