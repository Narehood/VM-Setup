#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/remote/Installers"
cp "$repo_root/install.sh" "$fixture/remote/"
cp "$repo_root/Installers/"{Docker-Prep,linutil}.sh "$fixture/remote/Installers/"
printf '.update-state\nsettings.local.conf\n' > "$fixture/remote/.gitignore"
git init -q -b main "$fixture/remote"
git -C "$fixture/remote" config user.name Test
git -C "$fixture/remote" config user.email test@example.invalid
git -C "$fixture/remote" -c core.autocrlf=false add .
git -C "$fixture/remote" -c commit.gpgsign=false commit -qm initial
git -c core.autocrlf=false clone -q "$fixture/remote" "$fixture/behind"
git -c core.autocrlf=false clone -q "$fixture/remote" "$fixture/ahead"
(
    cd "$fixture/behind"
    # shellcheck source=install.sh
    source ./install.sh
    prepare_update_check
    [[ "$UPDATE_RELATION" == equal ]]
)
git -C "$fixture/ahead" -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m local
(
    cd "$fixture/ahead"
    # shellcheck source=install.sh
    source ./install.sh
    exec() { echo restarted > "$fixture/unexpected-restart"; }
    prepare_update_check
    [[ "$UPDATE_RELATION" == ahead ]]
    if apply_repository_update auto; then exit 1; fi
    [[ ! -e "$fixture/unexpected-restart" ]]
)
git -C "$fixture/remote" -c commit.gpgsign=false commit -q --allow-empty -m upstream
new_commit=$(git -C "$fixture/remote" rev-parse HEAD)
(
    cd "$fixture/ahead"
    # shellcheck source=install.sh
    source ./install.sh
    prepare_update_check
    [[ "$UPDATE_RELATION" == diverged ]]
    if apply_repository_update auto; then exit 1; fi
)
(
    cd "$fixture/behind"
    # shellcheck source=install.sh
    source ./install.sh
    exec() { echo restarted >> "$fixture/restarts"; }
    sleep() { :; }
    prepare_update_check
    [[ "$UPDATE_RELATION" == behind ]]
    echo dirty > untracked
    if apply_repository_update auto; then exit 1; fi
    rm untracked
    apply_repository_update auto
    [[ "$(git rev-parse HEAD)" == "$new_commit" ]]
    grep -Fq "new_commit=$new_commit" .update-state
    [[ "$(wc -l < "$fixture/restarts")" -eq 1 ]]
    prepare_update_check
    [[ "$UPDATE_RELATION" == equal ]]
    if apply_repository_update auto; then exit 1; fi
    [[ "$(wc -l < "$fixture/restarts")" -eq 1 ]]
)
echo 'Real Git equal/ahead/behind/diverged, dirty-tree protection and single restart: passed.'
