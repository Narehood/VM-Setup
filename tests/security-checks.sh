#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

for script in install.sh Installers/*.sh tests/*.sh; do
    bash -n "$script"
done

(
    cd Installers
    sha256sum --check --strict .checksums.sha256
)

if rg -n 'curl[^|]*\|[[:space:]]*(ba)?sh' --glob '*.sh' --glob '!Installers/UniFi-Controller.sh' .; then
    echo "Direct curl-to-shell execution is forbidden." >&2
    exit 1
fi

if rg -n '(Pangolin|Newt)' README.md install.sh Installers/installer.sh; then
    echo "Removed Pangolin/Newt integrations are still referenced." >&2
    exit 1
fi

if ! grep -q '^AUTO_UPDATE_CHECK="false"$' settings.conf; then
    echo "Automatic update checks must remain disabled by default." >&2
    exit 1
fi

if rg -n 'git clean[[:space:]]+-[^[:space:]]*f' install.sh; then
    echo "Broad destructive git clean is forbidden." >&2
    exit 1
fi

echo "Security checks passed."
