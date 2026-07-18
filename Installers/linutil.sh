#!/bin/bash
set -euo pipefail

# DESCRIPTION: Downloads and launches an explicitly pinned LinUtil revision

readonly LINUTIL_REPO="https://github.com/ChrisTitusTech/linutil.git"
readonly LINUTIL_REVISION="41fc99189a588bfa82190fe49a1baf23fd65e97f"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

clear
echo -e "${BLUE}===================================================================${NC}"
echo -e "${CYAN}                  CHRIS TITUS TECH  |  LINUTIL LAUNCHER            ${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo ""

if ! command -v git &>/dev/null; then
    echo -e "${RED}[ERROR]${NC} git is required to securely fetch LinUtil."
    exit 1
fi

echo -e "${YELLOW}[NOTICE]${NC} LinUtil is third-party code and may change your system."
echo -e "Pinned revision: ${WHITE}${LINUTIL_REVISION}${NC}"
read -rp "Press [Enter] to download and launch, or Ctrl+C to cancel..."

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/linutil.XXXXXXXX")
cleanup() {
    rm -rf -- "$work_dir"
}
trap cleanup EXIT

echo -e "\n${CYAN}[INFO]${NC} Fetching pinned LinUtil revision..."
git -C "$work_dir" init -q
git -C "$work_dir" remote add origin "$LINUTIL_REPO"
git -C "$work_dir" fetch -q --depth 1 origin "$LINUTIL_REVISION"
git -C "$work_dir" checkout -q --detach FETCH_HEAD

actual_revision=$(git -C "$work_dir" rev-parse HEAD)
if [[ "$actual_revision" != "$LINUTIL_REVISION" ]]; then
    echo -e "${RED}[ERROR]${NC} LinUtil revision verification failed."
    exit 1
fi
if [[ ! -f "$work_dir/linutil.sh" ]]; then
    echo -e "${RED}[ERROR]${NC} Pinned LinUtil entrypoint was not found."
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Verified LinUtil revision."
(cd "$work_dir" && bash ./linutil.sh)
