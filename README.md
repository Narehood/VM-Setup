<p align="center">
  <a href="https://github.com/Narehood/VM-Setup" title="Go to GitHub repo">
    <img src="https://img.shields.io/static/v1?label=Narehood&message=VM-Setup&color=blue&logo=github" alt="Narehood - VM-Setup" />
  </a>
  <a href="https://github.com/Narehood/VM-Setup">
    <img src="https://img.shields.io/github/stars/Narehood/VM-Setup?style=social" alt="stars - VM-Setup" />
  </a>
  <a href="https://github.com/Narehood/VM-Setup">
    <img src="https://img.shields.io/github/forks/Narehood/VM-Setup?style=social" alt="forks - VM-Setup" />
  </a>
  <a href="https://github.com/Narehood/VM-Setup/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-blue" alt="License" />
  </a>
  <a href="https://github.com/Narehood/VM-Setup/issues">
    <img src="https://img.shields.io/github/issues/Narehood/VM-Setup" alt="issues - VM-Setup" />
  </a>
  <img src="https://img.shields.io/badge/bash_script-%23121011.svg?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="Bash Script" />
</p>

---

# XCP-NG VM-Setup

**VM-Setup** is a simple, versatile Bash script for configuring virtual machines on XCP-NG. Effortlessly set up your VM as a Docker Host, UniFi Controller, Xen Orchestra, or just install XCP-NG Tools. The script also supports automated security updates and self-updating, keeping your VMs secure and current.

> **Tested on:** Alma, Alpine, Arch, Debian, SUSE, and Ubuntu (should work on most Linux systems)

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Menu Options](#menu-options)
- [Credits](#credits)

---

## Features

- 🚀 **Install XCP-NG Tools**
- 🎨 **Install dotfiles** for a custom console look
- 🐳 **Configure as Docker Host**
- 🌐 **Set up UniFi Controller**
- 🖥️ **Set up Xen Orchestra**
- 🔄 **Self-update capability**
- 🛡️ **Enable automated security updates**

---

## Installation

Clone the repository and navigate to the project directory:

```sh
git clone https://github.com/Narehood/VM-Setup
cd VM-Setup
```

---

## Usage

Run the installer script:

```sh
bash install.sh
```

**Follow the on-screen instructions** to select your desired configuration.

---

## Menu Options

1. **XCP-NG / Virtual Machine Initial Configuration**
2. **Xen Orchestra**
3. **UniFi Controller**
4. **Docker Host Prep**
5. **Enable Automated Security Patches**
6. **Check for System Updates**
7. **Check for Menu Updates**
8. **Exit**

---

## Credits

- [UniFi Controller Script](https://glennr.nl/s/unifi-network-controller)
- [Xen Orchestra Script](https://github.com/ronivay/XenOrchestraInstallerUpdater)
- [Pterodactyl Script](https://github.com/pterodactyl-installer/pterodactyl-installer)

---

> _You are free to use and modify this script as you wish. Bug reports are welcome, but fixes are not guaranteed._
