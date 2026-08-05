#!/bin/bash
set -euo pipefail

# REQUIRES_ROOT: true
# INTERPRETER: bash
# DESCRIPTION: Upgrade Alpine Linux to a newer release branch (e.g. 3.23 -> 3.24)
# Requires bash (BASH_REMATCH, mapfile, read -rp). Prefer: bash alpineUpgrade.sh

if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "alpineUpgrade.sh requires bash (found a non-bash interpreter)." >&2
    exit 1
fi

VERSION="1.0.1"
LOGFILE="/var/log/alpine-upgrade.log"
LOCKFILE="/var/run/alpine-upgrade.lock"
REPOS_FILE="/etc/apk/repositories"
LOG_ENABLED="true"
QUIET="false"
DRY_RUN="false"
ASSUME_YES="false"
SKIP_REBOOT_PROMPT="false"
TARGET_RELEASE=""
MIRROR_BASE="https://dl-cdn.alpinelinux.org/alpine"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m'

CURRENT_VERSION_ID=""
CURRENT_BRANCH=""
LATEST_VERSION_ID=""
LATEST_BRANCH=""
REPO_STYLE="" # versioned | latest-stable | edge | mixed | none
REPO_BRANCH=""
REPOS_BACKUP=""

# print_status outputs an informational message prefixed with a blue [INFO] tag.
print_status() {
    if [[ "$QUIET" == "true" ]]; then
        [[ "$LOG_ENABLED" == "true" ]] && echo -e "${BLUE}[INFO]${NC} $1" >> "$LOGFILE"
    elif [[ "$LOG_ENABLED" == "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOGFILE"
    else
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

# print_success prints a success message prefixed with a green "[SUCCESS]" tag.
print_success() {
    if [[ "$QUIET" == "true" ]]; then
        [[ "$LOG_ENABLED" == "true" ]] && echo -e "${GREEN}[SUCCESS]${NC} $1" >> "$LOGFILE"
    elif [[ "$LOG_ENABLED" == "true" ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOGFILE"
    else
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    fi
}

# print_warn prints a warning message prefixed with a yellow [WARN] tag.
print_warn() {
    if [[ "$QUIET" == "true" ]]; then
        [[ "$LOG_ENABLED" == "true" ]] && echo -e "${YELLOW}[WARN]${NC} $1" >> "$LOGFILE"
    elif [[ "$LOG_ENABLED" == "true" ]]; then
        echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOGFILE"
    else
        echo -e "${YELLOW}[WARN]${NC} $1"
    fi
}

# print_error prints MESSAGE prefixed with a red "[ERROR]" tag to stderr.
print_error() {
    if [[ "$LOG_ENABLED" == "true" ]]; then
        echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOGFILE" >&2
    else
        echo -e "${RED}[ERROR]${NC} $1" >&2
    fi
}

# show_help prints usage instructions and exits.
show_help() {
    cat << EOF
Alpine Release Upgrade v${VERSION}
Usage: $(basename "$0") [OPTIONS]

Upgrades Alpine Linux from the current release branch to a newer stable
branch by updating /etc/apk/repositories and running apk upgrade --available.
Example: 3.23.x -> 3.24.1 (repos use v3.24; packages land on the latest point release).

Options:
    -h, --help              Show this help message
    -v, --version           Show version
    -d, --dry-run           Show what would be done without making changes
    -q, --quiet             Suppress stdout output (errors still print to stderr)
    -y, --yes               Skip confirmation and reboot prompts
    -t, --target RELEASE    Target release branch (e.g. 3.24 or v3.24)
    -l, --log FILE          Log to specified file (default: $LOGFILE)

Notes:
    - Only Alpine Linux is supported.
    - Release branches are upgraded one minor step at a time (3.22 -> 3.23 -> 3.24).
    - Repositories already using latest-stable only need a normal package upgrade.
    - Edge is not upgraded automatically; switch repos manually if that is intended.
EOF
    exit 0
}

# cleanup removes the lockfile specified by LOCKFILE.
cleanup() {
    rm -f "$LOCKFILE"
}

# check_root verifies the script is running as root.
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script requires root privileges. Run with sudo."
        exit 1
    fi
}

# acquire_lock creates LOCKFILE containing the current PID to prevent concurrent runs.
# Uses noclobber so two processes cannot both create the lock after a stale-file check.
acquire_lock() {
    if [[ -f "$LOCKFILE" ]]; then
        local pid
        pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            print_error "Another instance is already running (PID: $pid)."
            exit 1
        fi
        print_warn "Stale lock file found, removing."
        rm -f "$LOCKFILE"
    fi

    if ! (
        set -o noclobber
        echo $$ > "$LOCKFILE"
    ) 2>/dev/null; then
        print_error "Failed to create lock file: $LOCKFILE"
        exit 1
    fi

    local written_pid
    written_pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")
    if [[ "$written_pid" != "$$" ]]; then
        print_error "Lock file verification failed."
        exit 1
    fi

    trap cleanup EXIT
}

# validate_log_path ensures the log directory exists, creating it if necessary.
validate_log_path() {
    local log_dir
    log_dir=$(dirname "$LOGFILE")

    if [[ ! -d "$log_dir" ]]; then
        if ! mkdir -p "$log_dir" 2>/dev/null; then
            LOG_ENABLED="false"
            echo -e "${YELLOW}[WARN]${NC} Cannot create log directory '$log_dir'. File logging disabled." >&2
            return 0
        fi
    fi

    if ! touch "$LOGFILE" 2>/dev/null; then
        LOG_ENABLED="false"
        echo -e "${YELLOW}[WARN]${NC} Cannot write to log file '$LOGFILE'. File logging disabled." >&2
    fi
}

# normalize_branch converts values like v3.24 or 3.24.1 into a release branch of the form 3.24.
normalize_branch() {
    local raw="$1"
    raw="${raw#v}"
    if [[ "$raw" =~ ^([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]]; then
        echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

# compare_branches returns 0 if $1 < $2, 1 if equal, 2 if $1 > $2 for X.Y branches.
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

# detect_alpine verifies Alpine Linux and records the installed VERSION_ID / branch.
detect_alpine() {
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot identify the Linux distribution (/etc/os-release missing)."
        exit 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != "alpine" ]]; then
        print_error "This script only supports Alpine Linux (detected: ${ID:-unknown})."
        exit 1
    fi

    CURRENT_VERSION_ID="${VERSION_ID:-unknown}"
    if ! CURRENT_BRANCH=$(normalize_branch "$CURRENT_VERSION_ID"); then
        print_error "Unable to parse Alpine VERSION_ID: $CURRENT_VERSION_ID"
        exit 1
    fi
}

# detect_repo_style inspects /etc/apk/repositories and sets REPO_STYLE / REPO_BRANCH.
detect_repo_style() {
    if [[ ! -f "$REPOS_FILE" ]]; then
        print_error "Repositories file not found: $REPOS_FILE"
        exit 1
    fi

    local has_versioned=0 has_latest=0 has_edge=0
    REPO_BRANCH=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" == *"/edge/"* ]]; then
            has_edge=1
        elif [[ "$line" == *"/latest-stable/"* ]]; then
            has_latest=1
        elif [[ "$line" =~ /v([0-9]+\.[0-9]+)/ ]]; then
            has_versioned=1
            if [[ -z "$REPO_BRANCH" ]]; then
                REPO_BRANCH="${BASH_REMATCH[1]}"
            fi
        fi
    done < "$REPOS_FILE"

    if ((has_edge)) && ((! has_versioned)) && ((! has_latest)); then
        REPO_STYLE="edge"
    elif ((has_latest)) && ((! has_versioned)) && ((! has_edge)); then
        REPO_STYLE="latest-stable"
    elif ((has_versioned)) && ((! has_latest)) && ((! has_edge)); then
        REPO_STYLE="versioned"
    elif ((! has_versioned)) && ((! has_latest)) && ((! has_edge)); then
        REPO_STYLE="none"
    else
        REPO_STYLE="mixed"
    fi
}

# arch_for_releases maps uname -m to Alpine release archive architecture names.
arch_for_releases() {
    local machine
    machine=$(uname -m)
    case "$machine" in
        x86_64|amd64) echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        armv7l|armv7) echo "armv7" ;;
        armv6l|armhf) echo "armhf" ;;
        i386|i686|x86) echo "x86" ;;
        ppc64le) echo "ppc64le" ;;
        s390x) echo "s390x" ;;
        riscv64) echo "riscv64" ;;
        loongarch64) echo "loongarch64" ;;
        *) echo "$machine" ;;
    esac
}

# fetch_url downloads URL contents to stdout using curl or wget.
fetch_url() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 20 "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout=20 "$url"
    else
        return 1
    fi
}

# parse_latest_release_version extracts a point-release version from Alpine CDN YAML on stdin.
parse_latest_release_version() {
    local yaml version
    yaml=$(cat)
    version=$(printf '%s\n' "$yaml" | awk '
        /^[[:space:]]*-?[[:space:]]*version:[[:space:]]*/ {
            sub(/^[[:space:]]*-?[[:space:]]*version:[[:space:]]*/, "")
            gsub(/["'\'']/, "")
            print
            exit
        }
    ')

    if [[ -z "$version" ]]; then
        version=$(printf '%s\n' "$yaml" | sed -n 's/.*version:[[:space:]]*"\?\([0-9]\+\.[0-9]\+\.[0-9]\+\)"\?.*/\1/p' | head -n1)
    fi

    [[ -n "$version" ]] || return 1
    printf '%s\n' "$version"
}

# detect_latest_release queries Alpine CDN for the latest-stable point release.
# When --target is set, CDN failures become warnings so the explicit target can proceed.
detect_latest_release() {
    local arch yaml version
    arch=$(arch_for_releases)
    yaml=$(fetch_url "${MIRROR_BASE}/latest-stable/releases/${arch}/latest-releases.yaml" 2>/dev/null || true)

    if [[ -z "$yaml" ]]; then
        # Fallback: some mirrors expose only APKINDEX; try a second common arch path.
        yaml=$(fetch_url "${MIRROR_BASE}/latest-stable/releases/x86_64/latest-releases.yaml" 2>/dev/null || true)
    fi

    if [[ -z "$yaml" ]]; then
        if [[ -n "$TARGET_RELEASE" ]]; then
            print_warn "Unable to determine the latest Alpine stable release from ${MIRROR_BASE}."
            print_warn "Continuing with explicit --target ${TARGET_RELEASE}."
            LATEST_VERSION_ID=""
            LATEST_BRANCH=""
            return 0
        fi
        print_error "Unable to determine the latest Alpine stable release from ${MIRROR_BASE}."
        print_error "Check network access or pass --target explicitly (e.g. --target 3.24)."
        exit 1
    fi

    version=$(printf '%s\n' "$yaml" | parse_latest_release_version || true)

    if [[ -z "$version" ]] || ! LATEST_BRANCH=$(normalize_branch "$version"); then
        if [[ -n "$TARGET_RELEASE" ]]; then
            print_warn "Failed to parse latest Alpine release version from CDN metadata."
            print_warn "Continuing with explicit --target ${TARGET_RELEASE}."
            LATEST_VERSION_ID=""
            LATEST_BRANCH=""
            return 0
        fi
        print_error "Failed to parse latest Alpine release version from CDN metadata."
        exit 1
    fi

    LATEST_VERSION_ID="$version"
}

# branch_exists_on_mirror returns 0 when the release branch exposes a main APKINDEX on the CDN.
branch_exists_on_mirror() {
    local branch="$1"
    local arch probe
    arch=$(arch_for_releases)
    if command -v curl >/dev/null 2>&1; then
        if curl -fsI --max-time 15 "${MIRROR_BASE}/v${branch}/main/${arch}/APKINDEX.tar.gz" >/dev/null 2>&1; then
            return 0
        fi
        curl -fsI --max-time 15 "${MIRROR_BASE}/v${branch}/main/x86_64/APKINDEX.tar.gz" >/dev/null 2>&1
        return $?
    fi
    probe=$(fetch_url "${MIRROR_BASE}/v${branch}/main/${arch}/APKINDEX.tar.gz" 2>/dev/null | head -c 16 || true)
    [[ -n "$probe" ]]
}

# next_branch echoes the next minor release branch after $1 within the same major.
next_branch() {
    local major minor
    IFS=. read -r major minor <<< "$1"
    echo "${major}.$((minor + 1))"
}

# build_upgrade_path echoes intermediate release branches from current (exclusive) to target (inclusive).
build_upgrade_path() {
    local start="$1"
    local end="$2"
    local cursor path=() cmp=0
    local start_major end_major

    start_major="${start%%.*}"
    end_major="${end%%.*}"
    if [[ "$start_major" != "$end_major" ]]; then
        print_error "Refusing to upgrade across major series (v${start} -> v${end})."
        print_error "This tool only steps within the same major version (e.g. 3.23 -> 3.24)."
        exit 1
    fi

    compare_branches "$start" "$end" || cmp=$?
    case $cmp in
        1)
            return 0
            ;;
        2)
            print_error "Target release v${end} is older than the current branch v${start}."
            exit 1
            ;;
    esac

    cursor="$start"
    while true; do
        cursor=$(next_branch "$cursor")
        path+=("$cursor")
        cmp=0
        compare_branches "$cursor" "$end" || cmp=$?
        case $cmp in
            1) break ;;
            2)
                print_error "Failed to compute upgrade path from v${start} to v${end}."
                exit 1
                ;;
        esac
        if ((${#path[@]} > 50)); then
            print_error "Upgrade path is unexpectedly long; aborting."
            exit 1
        fi
    done

    printf '%s\n' "${path[@]}"
}

# backup_repos creates a timestamped backup of the apk repositories file and records REPOS_BACKUP.
backup_repos() {
    REPOS_BACKUP="${REPOS_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY-RUN] Would back up $REPOS_FILE to $REPOS_BACKUP"
        return 0
    fi
    cp "$REPOS_FILE" "$REPOS_BACKUP"
    print_status "Backed up repositories to $REPOS_BACKUP"
}

# on_upgrade_error reports recovery steps using the retained repositories backup, then exits.
on_upgrade_error() {
    local exit_code=$?
    trap - ERR
    print_error "Alpine release upgrade failed (exit ${exit_code}) during package update."
    if [[ -n "${REPOS_BACKUP:-}" && -f "$REPOS_BACKUP" ]]; then
        print_error "Repositories backup retained at: $REPOS_BACKUP"
        print_error "To restore: cp '$REPOS_BACKUP' '$REPOS_FILE' && apk update"
    else
        print_error "No repositories backup path is available; inspect $REPOS_FILE manually."
    fi
    exit "$exit_code"
}

# update_repos_to_branch rewrites versioned repository URLs from from_branch to to_branch.
update_repos_to_branch() {
    local from_branch="$1"
    local to_branch="$2"
    local tmp from_escaped

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY-RUN] Would rewrite v${from_branch} -> v${to_branch} in $REPOS_FILE"
        return 0
    fi

    from_escaped=$(printf '%s\n' "$from_branch" | sed 's/\./\\./g')
    tmp=$(mktemp)
    sed -e "s|/v${from_escaped}/|/v${to_branch}/|g" "$REPOS_FILE" > "$tmp"
    if ! grep -Fq "/v${to_branch}/" "$tmp"; then
        rm -f "$tmp"
        print_error "Repository rewrite did not introduce v${to_branch} URLs. Check $REPOS_FILE."
        exit 1
    fi
    cat "$tmp" > "$REPOS_FILE"
    rm -f "$tmp"
    print_success "Repositories updated to v${to_branch}."
}

# run_apk_upgrade refreshes indexes and upgrades all packages to the new branch.
run_apk_upgrade() {
    local label="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY-RUN] Would run: apk update && apk upgrade --available ($label)"
        return 0
    fi

    print_status "Refreshing package index ($label)..."
    apk update

    # Upgrading apk-tools first is recommended by Alpine and is harmless on modern releases.
    if apk info -e apk-tools >/dev/null 2>&1; then
        print_status "Ensuring apk-tools is current..."
        apk add --upgrade apk-tools || print_warn "apk-tools upgrade skipped or failed; continuing."
    fi

    print_status "Upgrading all packages ($label)..."
    apk upgrade --available
    apk cache clean 2>/dev/null || true
}

# confirm_upgrade prompts for confirmation unless --yes was provided.
confirm_upgrade() {
    local summary="$1"

    if [[ "$ASSUME_YES" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    if [[ ! -t 0 ]]; then
        print_error "Non-interactive session detected. Re-run with --yes to proceed."
        exit 1
    fi

    echo ""
    print_warn "This will change Alpine release repositories and upgrade system packages."
    print_warn "Take a VM snapshot or backup before continuing on production hosts."
    echo ""
    echo -e "${CYAN}${summary}${NC}"
    echo ""
    local answer
    read -rp "Continue with Alpine release upgrade? (y/N): " answer || answer="n"
    answer=${answer:-n}
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        print_status "Upgrade cancelled."
        exit 0
    fi
}

# prompt_reboot asks whether to reboot after a successful upgrade.
prompt_reboot() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY-RUN] Would recommend a reboot after upgrade."
        return 0
    fi

    echo ""
    print_warn "A reboot is recommended after an Alpine release upgrade."
    if command -v grub-install >/dev/null 2>&1; then
        print_warn "GRUB users should run grub-install after upgrading (see Alpine 3.24 notes)."
    fi

    if [[ "$SKIP_REBOOT_PROMPT" == "true" || "$ASSUME_YES" == "true" || "$QUIET" == "true" ]]; then
        print_status "Reboot prompt skipped. Please reboot when convenient."
        return 0
    fi

    if [[ ! -t 0 ]]; then
        print_status "Non-interactive mode detected. Please reboot manually."
        return 0
    fi

    local do_reboot
    read -t 30 -p "Reboot now? (y/N): " do_reboot || do_reboot="n"
    do_reboot=${do_reboot:-n}
    if [[ "$do_reboot" =~ ^[Yy]$ ]]; then
        print_status "Rebooting system..."
        reboot
    else
        print_status "Please remember to reboot later."
    fi
}

# upgrade_latest_stable_repos performs a package upgrade when repos already track latest-stable.
upgrade_latest_stable_repos() {
    local summary latest_line
    if [[ -n "$LATEST_VERSION_ID" ]]; then
        latest_line="Latest CDN: Alpine ${LATEST_VERSION_ID} (branch v${LATEST_BRANCH})"
    else
        latest_line="Latest CDN: unavailable"
    fi
    summary="Repositories already use latest-stable.
Installed: Alpine ${CURRENT_VERSION_ID} (branch v${CURRENT_BRANCH})
${latest_line}
Action: apk update && apk upgrade --available"

    confirm_upgrade "$summary"
    [[ "$LOG_ENABLED" == "true" ]] && echo "--- Alpine latest-stable upgrade started: $(date) ---" >> "$LOGFILE"
    run_apk_upgrade "latest-stable"
    print_success "Package upgrade completed against latest-stable repositories."
    prompt_reboot
}

# upgrade_versioned_repos walks release branches from current to the selected target.
upgrade_versioned_repos() {
    local target="$1"
    local path_file steps=() step from_branch summary cmp=0 latest_line

    if [[ -n "$REPO_BRANCH" && "$REPO_BRANCH" != "$CURRENT_BRANCH" ]]; then
        print_error "Repository branch v${REPO_BRANCH} does not match installed Alpine branch v${CURRENT_BRANCH}."
        print_error "Align $REPOS_FILE with the running system before upgrading."
        exit 1
    fi

    compare_branches "$CURRENT_BRANCH" "$target" || cmp=$?
    case $cmp in
        1)
            print_success "Already on Alpine release branch v${CURRENT_BRANCH} (VERSION_ID ${CURRENT_VERSION_ID})."
            print_status "Running a normal package upgrade against the current repositories."
            confirm_upgrade "Action: apk update && apk upgrade --available"
            run_apk_upgrade "current branch v${CURRENT_BRANCH}"
            print_success "Packages refreshed on v${CURRENT_BRANCH}."
            prompt_reboot
            return 0
            ;;
        2)
            print_error "Installed branch v${CURRENT_BRANCH} is newer than target v${target}."
            exit 1
            ;;
    esac

    path_file=$(mktemp)
    build_upgrade_path "$CURRENT_BRANCH" "$target" > "$path_file"
    mapfile -t steps < "$path_file"
    rm -f "$path_file"

    if ((${#steps[@]} == 0)); then
        print_error "No upgrade steps computed."
        exit 1
    fi

    for step in "${steps[@]}"; do
        if ! branch_exists_on_mirror "$step"; then
            print_error "Release branch v${step} was not found on ${MIRROR_BASE}."
            exit 1
        fi
    done

    if [[ -n "$LATEST_VERSION_ID" ]]; then
        latest_line="Latest CDN: Alpine ${LATEST_VERSION_ID} (branch v${LATEST_BRANCH})"
    else
        latest_line="Latest CDN: unavailable"
    fi
    summary="Installed: Alpine ${CURRENT_VERSION_ID} (branch v${CURRENT_BRANCH})
${latest_line}
Target:     v${target}
Steps:      $(printf 'v%s -> ' "${steps[@]}" | sed 's/ -> $//')"

    confirm_upgrade "$summary"
    [[ "$LOG_ENABLED" == "true" ]] && echo "--- Alpine release upgrade started: $(date) ---" >> "$LOGFILE"
    backup_repos
    trap on_upgrade_error ERR

    from_branch="$CURRENT_BRANCH"
    for step in "${steps[@]}"; do
        print_status "Upgrading release branch v${from_branch} -> v${step}..."
        update_repos_to_branch "$from_branch" "$step"
        run_apk_upgrade "v${step}"
        from_branch="$step"
    done

    trap - ERR

    # Refresh os-release values after upgrades when possible.
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        print_success "Alpine release upgrade finished. Now: ${PRETTY_NAME:-Alpine ${VERSION_ID:-unknown}}"
    else
        print_success "Alpine release upgrade finished."
    fi

    [[ "$LOG_ENABLED" == "true" ]] && echo "--- Alpine release upgrade completed: $(date) ---" >> "$LOGFILE"
    prompt_reboot
}

# resolve_target_branch chooses the destination release branch from flags / defaults.
resolve_target_branch() {
    local normalized=""
    if [[ -n "$TARGET_RELEASE" ]]; then
        if ! normalized=$(normalize_branch "$TARGET_RELEASE"); then
            print_error "Invalid --target value: $TARGET_RELEASE (expected e.g. 3.24)"
            exit 1
        fi
        echo "$normalized"
        return 0
    fi
    echo "$LATEST_BRANCH"
}

# --- MAIN ---
# When sourced (e.g. by tests), expose helpers only and skip execution.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help ;;
        -v|--version) echo "v${VERSION}"; exit 0 ;;
        -d|--dry-run) DRY_RUN="true"; shift ;;
        -q|--quiet) QUIET="true"; shift ;;
        -y|--yes) ASSUME_YES="true"; SKIP_REBOOT_PROMPT="true"; shift ;;
        -t|--target)
            if [[ -z "${2:-}" || "$2" == -* ]]; then
                echo "Error: -t|--target requires a release argument (e.g. 3.24)" >&2
                exit 1
            fi
            TARGET_RELEASE="$2"
            shift 2
            ;;
        -l|--log)
            if [[ -z "${2:-}" || "$2" == -* ]]; then
                echo "Error: -l|--log requires a filename argument" >&2
                exit 1
            fi
            LOGFILE="$2"
            shift 2
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

validate_log_path
check_root
acquire_lock
detect_alpine
detect_repo_style
detect_latest_release

print_status "Detected Alpine ${CURRENT_VERSION_ID} (branch v${CURRENT_BRANCH})"
if [[ -n "$LATEST_VERSION_ID" ]]; then
    print_status "Latest stable from CDN: ${LATEST_VERSION_ID} (branch v${LATEST_BRANCH})"
else
    print_status "Latest stable from CDN: unavailable"
fi
print_status "Repository style: ${REPO_STYLE}"
if [[ -n "$REPO_BRANCH" ]]; then
    print_status "Repository branch: v${REPO_BRANCH}"
fi

case "$REPO_STYLE" in
    edge)
        print_error "Repositories point at Alpine edge. This script only upgrades stable release branches."
        print_error "Edit $REPOS_FILE manually if you intentionally want a different channel."
        exit 1
        ;;
    mixed)
        print_error "Mixed repository channels detected in $REPOS_FILE."
        print_error "Normalize to versioned vX.Y URLs (or latest-stable), then re-run."
        exit 1
        ;;
    none)
        print_error "No Alpine repository URLs found in $REPOS_FILE."
        exit 1
        ;;
    latest-stable)
        upgrade_latest_stable_repos
        ;;
    versioned)
        target_branch=$(resolve_target_branch)
        print_status "Selected target release branch: v${target_branch}"
        upgrade_versioned_repos "$target_branch"
        ;;
    *)
        print_error "Unhandled repository style: $REPO_STYLE"
        exit 1
        ;;
esac
