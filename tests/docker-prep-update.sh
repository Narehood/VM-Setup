#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
git init -q -b main "$fixture/remote"
git -C "$fixture/remote" config user.email test@example.invalid
git -C "$fixture/remote" config user.name Test
git -C "$fixture/remote" -c commit.gpgsign=false commit -q --allow-empty -m initial
revision=$(git -C "$fixture/remote" rev-parse HEAD)
git -C "$fixture/remote" tag v1.9.0
git -C "$fixture/remote" -c tag.gpgsign=false tag -a v1.10.0 -m annotated
git -C "$fixture/remote" tag v99.0.0-rc1
# shellcheck source=Installers/Docker-Prep.sh
source "$repo_root/Installers/Docker-Prep.sh"
remote_git() { git ls-remote "$fixture/remote" 'refs/tags/v*' refs/heads/main; }
resolve_latest_docker_prep
[[ "$LATEST_VERSION" == v1.10.0 && "$LATEST_SHA" == "$revision" ]]
[[ "$LATEST_SHA" != "$(git -C "$fixture/remote" rev-parse v1.10.0)" ]]
before=$(sha256sum "$repo_root/Installers/Docker-Prep.sh" "$repo_root/Installers/.checksums.sha256")
check_docker_prep_update </dev/null
[[ "$EFFECTIVE_REVISION" == "$REPO_REVISION" ]]
[[ "$before" == "$(sha256sum "$repo_root/Installers/Docker-Prep.sh" "$repo_root/Installers/.checksums.sha256")" ]]
git -C "$fixture/remote" tag -d v1.9.0 v1.10.0 v99.0.0-rc1 >/dev/null
resolve_latest_docker_prep
[[ "$LATEST_VERSION" == main && "$LATEST_SHA" == "$revision" ]]
remote_git() { printf 'not-a-commit refs/heads/main\n'; }
if resolve_latest_docker_prep; then echo 'Malformed revision accepted' >&2; exit 1; fi
remote_git() { return 1; }
check_docker_prep_update
[[ "$EFFECTIVE_REVISION" == "$REPO_REVISION" ]]
echo 'Docker-Prep stable/annotated tags, main fallback, offline pin and immutable manifest: passed.'
