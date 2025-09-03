#!/usr/bin/env bash
set -euo pipefail

# Pre-flight: require root/sudo
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root or with sudo."
  exit 1
fi

echo "Detecting OS family..."
OS_FAMILY=""
if command -v apt-get >/dev/null 2>&1; then
  OS_FAMILY="debian"
elif command -v dnf >/dev/null 2>&1; then
  OS_FAMILY="dnf"
elif command -v yum >/dev/null 2>&1; then
  OS_FAMILY="yum"
else
  echo "Unsupported system: need apt, dnf, or yum."
  exit 2
fi

install_debian() {
  echo "Installing cloudflared on Debian/Ubuntu..."
  mkdir -p --mode=0755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
    | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
    | tee /etc/apt/sources.list.d/cloudflared.list

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y cloudflared
}

install_yum_like() {
  # Works for RHEL/CentOS/Alma/Rocky/Fedora (dnf or yum)
  echo "Installing cloudflared on RHEL/CentOS/Alma/Rocky/Fedora..."
  curl -fsSL https://pkg.cloudflare.com/cloudflared-ascii.repo \
    | tee /etc/yum.repos.d/cloudflared.repo >/dev/null

  if [[ "$OS_FAMILY" == "dnf" ]]; then
    dnf -y makecache
    dnf -y install cloudflared
  else
    yum -y makecache
    yum -y install cloudflared
  fi
}

case "$OS_FAMILY" in
  debian) install_debian ;;
  dnf|yum) install_yum_like ;;
esac

echo
echo "cloudflared installed."
echo
echo "NEXT STEP:"
echo "1) In Cloudflare Zero Trust, go to: Networks > Tunnels, select your tunnel, click Edit."
echo "2) Copy the token."
echo "3) Run the following command on this host (replace {token}):"
echo "   sudo cloudflared service install {token}"
echo
echo "Optional checks:"
echo "- Version: cloudflared --version"
echo "- Status (after install): systemctl status cloudflared"
echo "- Logs: journalctl -u cloudflared -f"
