#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

for script in install.sh Installers/*.sh tests/*.sh tools/*.sh; do
    bash -n "$script"
done

bash tests/update-flow.sh
bash tests/alpine-upgrade.sh
bash tests/server-setup-alpine.sh
bash tests/docker-prep-update.sh

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

if ! awk '
    /^load_settings\(\)/ { in_fn=1 }
    in_fn && /^[[:space:]]*AUTO_UPDATE_CHECK="false"[[:space:]]*$/ { update_default=1 }
    in_fn && /^[[:space:]]*AUTO_APPLY_UPDATES="false"[[:space:]]*$/ { apply_default=1 }
    in_fn && /^}/ { exit }
    END { exit !(update_default && apply_default) }
' install.sh; then
    echo "install.sh must default AUTO_UPDATE_CHECK and AUTO_APPLY_UPDATES to false." >&2
    exit 1
fi

if ! grep -q '^readonly REPO_VERSION=' Installers/Docker-Prep.sh; then
    echo "Docker-Prep launcher must expose REPO_VERSION for update summaries." >&2
    exit 1
fi

if rg -n 'git clean[[:space:]]+-[^[:space:]]*f' install.sh; then
    echo "Broad destructive git clean is forbidden." >&2
    exit 1
fi

echo "Security checks passed."
