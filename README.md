<div align="center">

# 🖥️ Generic Linux System/XCP-NG VM-Setup

<p>
  <img src="https://img.shields.io/github/license/Narehood/VM-Setup?style=for-the-badge&color=blue" alt="License" />
  <img src="https://img.shields.io/github/last-commit/Narehood/VM-Setup?style=for-the-badge&color=orange" alt="Last Commit" />
  <img src="https://img.shields.io/badge/Bash-Script-black?style=for-the-badge&logo=gnu-bash" alt="Bash" />
</p>

<p>
  <a href="https://github.com/Narehood/VM-Setup/stargazers"><img src="https://img.shields.io/github/stars/Narehood/VM-Setup?style=social" alt="Stars" /></a>
  <a href="https://github.com/Narehood/VM-Setup/network/members"><img src="https://img.shields.io/github/forks/Narehood/VM-Setup?style=social" alt="Forks" /></a>
  <a href="https://github.com/Narehood/VM-Setup/issues"><img src="https://img.shields.io/github/issues/Narehood/VM-Setup?style=social" alt="Issues" /></a>
</p>

**The all-in-one post-installation utility for XCP-NG Virtual Machines.**

Configure Docker hosts, UniFi Controllers, Xen Orchestra, guest tools, security
updates, and common server settings through an interactive Bash menu.

[Features](#-features) • [Quick Start](#-quick-start) • [Menu Options](#-menu-options) • [Configuration](#-configuration) • [Credits](#-credits--acknowledgements)

</div>

---

## 🐧 Supported Distributions

<div align="center">
  <img src="https://img.shields.io/badge/Ubuntu-E95420?style=flat-square&logo=ubuntu&logoColor=white" alt="Ubuntu" />
  <img src="https://img.shields.io/badge/Debian-A81D33?style=flat-square&logo=debian&logoColor=white" alt="Debian" />
  <img src="https://img.shields.io/badge/Alpine_Linux-0D597F?style=flat-square&logo=alpine-linux" alt="Alpine" />
  <img src="https://img.shields.io/badge/Arch_Linux-1793D1?style=flat-square&logo=arch-linux" alt="Arch" />
  <img src="https://img.shields.io/badge/Fedora-294172?style=flat-square&logo=fedora&logoColor=white" alt="Fedora" />
  <img src="https://img.shields.io/badge/RHEL/CentOS-262525?style=flat-square&logo=redhat" alt="RHEL" />
  <img src="https://img.shields.io/badge/openSUSE-73BA25?style=flat-square&logo=opensuse" alt="SUSE" />
  <img src="https://img.shields.io/badge/Pop!_OS-48B9C7?style=flat&logo=Pop!_OS" alt="Pop OS" />
</div>

Core setup, updates, MTU configuration, SSH/MOTD and the WordPress installer include
Debian/Ubuntu, Alpine, Arch/Manjaro/EndeavourOS, RHEL/Fedora/Rocky/AlmaLinux, and
openSUSE/SLES paths. Alpine uses OpenRC; the other families use systemd.

| Family | Package updates | Scheduled maintenance |
| --- | --- | --- |
| Debian / Ubuntu | APT | Unattended upgrades with distro-configured origins |
| Alpine | APK | Daily full package updates, with crond enabled |
| Arch and derivatives | Complete `pacman -Syu` | `checkupdates` notifications and cache maintenance |
| Red Hat and derivatives | DNF | Security updates with DNF4 or DNF5 Automatic |
| SUSE Leap / SLES | Zypper updates | Security patches |
| SUSE Tumbleweed / Slowroll | Complete `zypper dup` | Update notifications |

Guest utilities use distro packages where available; Debian uses trusted guest-tools
ISO media, and Arch/SUSE can install the generic ISO payload. An attached ISO must
contain `xe-guest-utilities_*_all.tgz` for the generic path. Transactional/immutable
OS variants require their own snapshot-aware installation workflow.

Third-party applications keep their upstream restrictions: UniFi's bundled installer
targets Debian/Ubuntu-family systems; Xen Orchestra and Docker-Prep perform their
own platform checks. This does not mean every application supports every OS.
LinUtil supplies x86_64/aarch64 binaries; cloudflared also supplies ARMv6/v7 binaries.

Regression checks cover 15 distro identifiers and both service managers. Linux CI
is configured for Debian, Ubuntu, Alpine, Arch, Fedora, Rocky, and openSUSE. Package
and service operations are mocked in these tests; they are not full VM installation
or reboot tests. See [review status](REVIEW.md) and [upstream versions](UPSTREAM.md).

---

## ⚡ Quick Start

Prerequisites: Bash 4+, Git, `sha256sum`, CA certificates, network access, and either
root access or `sudo` for system-changing modules. Download launchers also need
`curl`; Docker MTU edits require `jq`. Netplan edits need its normal Python/PyYAML
dependencies. Alpine users should install Bash before launching: `apk add bash git
coreutils curl ca-certificates`.

```bash
git clone https://github.com/Narehood/VM-Setup
cd VM-Setup
bash install.sh
```

---

## 🚀 Features

| Feature | Description |
| :--- | :--- |
| **XCP-NG Tools** | Detect the OS and install available guest utilities |
| **Docker Prep** | Launch a verified commit; optional run-once update without changing trusted files |
| **App Installers** | Guided WordPress, UniFi, Xen Orchestra, and Cloudflare installers |
| **Security** | Configure unattended security updates |
| **Server Config** | Manage system-level settings |
| **LinUtil** | Launch an explicitly pinned LinUtil revision |
| **Persistent Settings** | Store local preferences outside tracked files |

---

## 📋 Menu Options

| Module | Description |
| :--- | :--- |
| **Server Initial Config** | Hostname, guest tools, and basic utilities |
| **Application Installers** | WordPress, XO, UniFi, and Cloudflare Tunnels |
| **Docker Host Preparation** | Engine setup and permissions |
| **Auto Security Patches** | Security updates where available; full Alpine updates; Arch/rolling SUSE notifications |
| **Run System Updates** | Wrapper for apt, dnf, pacman, apk, and other supported managers |
| **Server Config** | MTU, SSH keys, MOTD, SSH banner, and Alpine release upgrades |
| **Launch LinUtil** | External utility integration |
| **Switch Branch** | Change to another repository branch |
| **Settings** | Update preferences and explicitly check for application updates |

---

## ⚙️ Configuration and security

The tracked `settings.conf` contains safe defaults. Persistent preferences are
written to the ignored `settings.local.conf` with mode `600`.

| Setting | Default | Description |
| :--- | :---: | :--- |
| **Auto Update Check** | `false` | Check for a newer VM-Setup commit on startup |
| **Auto Apply Updates** | `false` | When update checks are enabled, apply fast-forward updates without prompting |

Settings are managed through the interactive menu:

1. Launch the menu with `bash install.sh`.
2. Press `s`.
3. Toggle Auto Update Check and optionally Auto Apply Updates.
4. Or run an explicit update check from the settings menu.

For automatic updates on startup:

```bash
# settings.local.conf
AUTO_UPDATE_CHECK="true"
AUTO_APPLY_UPDATES="true"
```

After an update is applied, the next launch shows a summary with the previous and new
VM-Setup versions, Docker-Prep pin, LinUtil pin, and a compare link. Automatic apply
prompts to stash or discard local changes when the working tree is dirty (or skips in
non-interactive sessions).

Installer scripts are checked against the committed
`Installers/.checksums.sha256` manifest before execution. A mismatch is fatal.
Maintainers can update the manifest after reviewing installer changes:

```bash
bash tools/generate-checksums.sh
git diff -- Installers/.checksums.sha256
```

Third-party launchers use immutable Git commits or versioned binaries with recorded
SHA-256 digests. [UPSTREAM.md](UPSTREAM.md) records the versions, hashes and local
UniFi patch. Docker-Prep pin updates are proposed through a review workflow:

1. Publish a GitHub Release in `Narehood/Docker-Prep` (push a matching `v*` tag;
   `VERSION` in Docker-Prep's `install.sh` is currently `2.4.0`, so the first tag
   should be `v2.4.0`).
2. The `Sync Docker-Prep pin` workflow updates `REPO_REVISION` / `REPO_VERSION`,
   regenerates checksums, runs security checks, and opens a PR. Docker-Prep's
   release workflow can also `repository_dispatch` this repo when
   `VM_SETUP_DISPATCH_TOKEN` is configured.
3. After that PR is merged, users with Auto Update Check enabled receive the new pin
   through a normal VM-Setup update and see it in the post-update summary.

The weekly scheduled sync polls for the latest Docker-Prep release. If no releases
exist yet, that run exits successfully with nothing to sync (it no longer fails with
`gh: Not Found (HTTP 404)`).

Manual pin sync:

```bash
bash tools/sync-docker-prep-pin.sh            # latest release
bash tools/sync-docker-prep-pin.sh v1.2.0    # specific release
```

WordPress creates a new site at `/var/www/wordpress` and refuses to overwrite that
directory or `/root/.wp-creds`. It uses the distro's PHP packages (PHP 8.2+), retains
existing database administrator authentication, and creates a separate database and
account. A failed run removes only its own site resources; installed packages remain.
Existing WordPress installations need a separate migration or upgrade procedure.

Cloudflared installs a verified binary at `/usr/local/bin/cloudflared`. Its optional
`cloudflared-vm-setup` service reads `/etc/cloudflared/vm-setup-token` with mode `600`;
tokens are not placed in process arguments. Existing tunnel service configurations
are preserved. Update this binary through the launcher when its reviewed pin changes.

Xen Orchestra keeps configuration at `/etc/vm-setup/xo-install.cfg` and logs under
`/var/log/vm-setup-xo`. Set `XO_CONFIG_FILE` to use an existing trusted configuration.
The installer runs from a verified temporary checkout with self-upgrade disabled.

Development checks:

```bash
bash tests/security-checks.sh
# First-party warnings are enforced; the vendored UniFi script has an error-only gate.
mapfile -t scripts < <(find Installers tests tools -name '*.sh' ! -name UniFi-Controller.sh)
shellcheck -x --severity=warning install.sh "${scripts[@]}"
shellcheck --severity=error Installers/UniFi-Controller.sh
```

---

## 🤝 Credits & Acknowledgements

| Project | Author |
| :--- | :--- |
| [UniFi Controller](https://glennr.nl/s/unifi-network-controller) | GlennR |
| [Xen Orchestra fork](https://github.com/Narehood/XenOrchestraInstallerUpdater) | Narehood / Ronivay |
| [LinUtil](https://github.com/ChrisTitusTech/linutil) | Chris Titus Tech |

---

<div align="center">

*Licensed under the [MIT License](https://github.com/Narehood/VM-Setup/blob/main/LICENSE).*<br>
*You are free to use and modify this script as you wish.*<br>
*Bug reports are welcome, but fixes are not guaranteed.*

</div>
