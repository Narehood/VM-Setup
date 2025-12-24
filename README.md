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

Effortlessly configure Docker Hosts, UniFi Controllers, Xen Orchestra, or simply install Guest Tools.<br>
Includes automated security patching and self-updating capabilities.

<!-- <img src="https://your-image-link-here.png" alt="Dashboard Preview" width="700" /> -->

[Features](#-features) • [Quick Start](#-quick-start) • [Menu Options](#-menu-options) • [Credits](#-credits--acknowledgements)

</div>

---

## 🐧 Supported Distributions

<div align="center">
  <img src="https://img.shields.io/badge/Ubuntu-E95420?style=flat-square&logo=ubuntu&logoColor=white" alt="Ubuntu" />
  <img src="https://img.shields.io/badge/Debian-A81D33?style=flat-square&logo=debian&logoColor=white" alt="Debian" />
  <img src="https://img.shields.io/badge/Alpine_Linux-0D597F?style=flat-square&logo=alpine-linux&logoColor=white" alt="Alpine" />
  <img src="https://img.shields.io/badge/Arch_Linux-1793D1?style=flat-square&logo=arch-linux&logoColor=white" alt="Arch" />
  <img src="https://img.shields.io/badge/Fedora-294172?style=flat-square&logo=fedora&logoColor=white" alt="Fedora" />
  <img src="https://img.shields.io/badge/RHEL/CentOS-262525?style=flat-square&logo=redhat&logoColor=white" alt="RHEL" />
  <img src="https://img.shields.io/badge/openSUSE-73BA25?style=flat-square&logo=opensuse&logoColor=white" alt="SUSE" />
  <img src="https://img.shields.io/badge/Pop!_OS-48B9C7?style=flat&logo=Pop!_OS&logoColor=white" alt="Pop OS" />
  <img src="https://img.shields.io/badge/Gentoo-54487A?style=flat&logo=gentoo&logoColor=white" alt="Gentoo" />
</div>

---

## ⚡ Quick Start

```bash
git clone https://github.com/Narehood/VM-Setup
cd VM-Setup
bash install.sh
```

---

## 🚀 Features

| Feature | Description |
| :--- | :--- |
| **XCP-NG Tools** | Automatically detects OS and installs correct guest utilities |
| **Docker Prep** | Full Docker Engine installation + user group configuration |
| **App Installers** | One-click install for UniFi Controller, Xen Orchestra, and Pterodactyl |
| **Security** | Enable automated unattended security upgrades |
| **Maintenance** | System update helper and self-updating menu |
| **LinUtil** | Integrated launcher for Chris Titus's Linux Utility |

---

## 📋 Menu Options

The script provides an interactive dashboard with the following modules:

| Module | Description |
| :--- | :--- |
| **Server Initial Config** | Hostname, Guest Tools, Basic Utilities |
| **Application Installers** | WordPress, XO, UniFi, Cloudflare Tunnels |
| **Docker Host Preparation** | Engine setup & permissions |
| **Auto Security Patches** | Configure cron/systemd timers for updates |
| **Run System Updates** | Smart wrapper for apt/dnf/pacman/apk |
| **Update This Menu** | Pulls latest changes from GitHub |
| **Launch LinUtil** | External utility integration |

---

## 🤝 Credits & Acknowledgements

This project utilizes and wraps several excellent community scripts:

| Project | Author |
| :--- | :--- |
| [UniFi Controller](https://glennr.nl/s/unifi-network-controller) | GlennR |
| [Xen Orchestra](https://github.com/ronivay/XenOrchestraInstallerUpdater) | Ronivay |
| [LinUtil](https://github.com/ChrisTitusTech/linutil) | Chris Titus Tech |

---

<div align="center">


*Licensed under the [MIT License](https://github.com/Narehood/VM-Setup/blob/main/LICENSE).*<br>
*You are free to use and modify this script as you wish.*<br>
*Bug reports are welcome, but fixes are not guaranteed.*

</div>




