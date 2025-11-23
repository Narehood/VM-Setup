<div align="center">

# 🖥️ XCP-NG VM-Setup

<!-- BADGES -->
<p>
  <img src="https://img.shields.io/github/license/Narehood/VM-Setup?style=for-the-badge&color=blue" alt="License" />
  <img src="https://img.shields.io/github/last-commit/Narehood/VM-Setup?style=for-the-badge&color=orange" alt="Last Commit" />
  <img src="https://img.shields.io/badge/Bash-Script-black?style=for-the-badge&logo=gnu-bash" alt="Bash" />
</p>
<p>
  <a href="https://github.com/Narehood/VM-Setup/stargazers">
    <img src="https://img.shields.io/github/stars/Narehood/VM-Setup?style=social" alt="Stars" />
  </a>
  <a href="https://github.com/Narehood/VM-Setup/network/members">
    <img src="https://img.shields.io/github/forks/Narehood/VM-Setup?style=social" alt="Forks" />
  </a>
  <a href="https://github.com/Narehood/VM-Setup/issues">
    <img src="https://img.shields.io/github/issues/Narehood/VM-Setup?style=social" alt="Issues" />
  </a>
</p>

<!-- DESCRIPTION -->
<h3>The all-in-one post-installation utility for XCP-NG Virtual Machines.</h3>
<p>
Effortlessly configure Docker Hosts, UniFi Controllers, Xen Orchestra, or simply install Guest Tools.<br>
Includes automated security patching and self-updating capabilities.
</p>

<!-- PLACEHOLDER FOR SCREENSHOT -->
<!-- Take a screenshot of your new menu and link it here! -->
<!-- <img src="https://your-image-link-here.png" alt="Dashboard Preview" width="800" /> -->

</div>

---

## 🐧 Supported Distributions

<div align="center">
  <img src="https://img.shields.io/badge/Ubuntu-E95420?style=flat-square&logo=ubuntu&logoColor=white" alt="Ubuntu" />
  <img src="https://img.shields.io/badge/Debian-A81D33?style=flat-square&logo=debian&logoColor=white" alt="Debian" />
  <img src="https://img.shields.io/badge/Alpine_Linux-0D597F?style=flat-square&logo=alpine-linux&logoColor=white" alt="Alpine" />
  <img src="https://img.shields.io/badge/Arch_Linux-1793D1?style=flat-square&logo=arch-linux&logoColor=white" alt="Arch" />
  <img src="https://img.shields.io/badge/Fedora-294172?style=flat-square&logo=fedora&logoColor=white" alt="Fedora" />
  <img src="https://img.shields.io/badge/openSUSE-73BA25?style=flat-square&logo=opensuse&logoColor=white" alt="SUSE" />
</div>

---

## ⚡ Quick Start

You can run the installer directly using git:

```bash
git clone https://github.com/Narehood/VM-Setup
cd VM-Setup
bash install.sh
```

---

## 🚀 Features

| Feature | Description |
| :--- | :--- |
| **XCP-NG Tools** | Automatically detects OS and installs correct guest utilities. |
| **Docker Prep** | Full Docker Engine installation + User Group configuration. |
| **App Installers** | One-click install for **UniFi Controller**, **Xen Orchestra**, and **Pterodactyl**. |
| **Security** | Enable automated unattended security upgrades. |
| **Maintenance** | System update helper and self-updating menu. |
| **LinUtil** | Integrated launcher for Chris Titus's Linux Utility. |

---

## 📋 Menu Options

The script provides an interactive dashboard with the following modules:

1.  **Server Initial Config** - *Hostname, Guest Tools, Basic Utilities*
2.  **Application Installers** - *WordPress, XO, UniFi, Cloudflare Tunnels*
3.  **Docker Host Preparation** - *Engine setup & permissions*
4.  **Auto Security Patches** - *Configure cron/systemd timers for updates*
5.  **Run System Updates** - *Smart wrapper for apt/dnf/pacman/apk*
6.  **Update This Menu** - *Pulls latest changes from GitHub*
7.  **Launch LinUtil** - *External utility integration*

---

## 🤝 Credits & Acknowledgements

This project utilizes and wraps several excellent community scripts:

*   **UniFi Controller**: [GlennR](https://glennr.nl/s/unifi-network-controller)
*   **Xen Orchestra**: [Ronivay](https://github.com/ronivay/XenOrchestraInstallerUpdater)
*   **Pterodactyl**: [Pterodactyl-Installer](https://github.com/pterodactyl-installer/pterodactyl-installer)
*   **LinUtil**: [Chris Titus Tech](https://github.com/ChrisTitusTech/linutil)

---

<div align="center">
  <p><i>You are free to use and modify this script as you wish. <br>Bug reports are welcome, but fixes are not guaranteed.</i></p>
</div>
