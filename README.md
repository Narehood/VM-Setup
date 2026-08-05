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

Support varies by module. The core menu runs on the distributions above, but each
installer supports only the package managers and services it explicitly detects.
Review module prompts before applying changes to a production host.

---

## ⚡ Quick Start

Prerequisites: Bash 4+, Git, `sha256sum`, network access, and either root access or
`sudo` for system-changing modules.

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
| **Docker Prep** | Launch an explicitly pinned Docker-Prep revision |
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
| **Auto Security Patches** | Configure update timers without an implicit full upgrade |
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
skips when the working tree has local changes.

Installer scripts are checked against the committed
`Installers/.checksums.sha256` manifest before execution. A mismatch is fatal.
Maintainers can update the manifest after reviewing installer changes:

```bash
bash tools/generate-checksums.sh
git diff -- Installers/.checksums.sha256
```

Third-party launchers are pinned to Git commit IDs. Docker-Prep pin updates are
automated safely:

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
