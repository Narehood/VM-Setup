# XCP-NG VM-Setup

VM-Setup is a simple and versatile script designed to configure virtual machines running on XCP-NG. With this tool, you can effortlessly set up your virtual machine as a Docker Host, UniFi Controller, or Xen Orchestra, or simply install XCP-NG Tools. Additionally, VM-Setup includes features for enabling automated security updates and self-updating, ensuring your VMs are always up-to-date with the latest features and secure. Many of these tools are pulled from other projects and are credited below.

You may use and change this script however you wish. If you encounter any bugs you can report them, but they may or may not get fixed.

This tool should work on most Linux systems but is mainly tested on Alma, Debian, Suse, and Ubuntu.

## Features

- Install XCP-NG Tools
- Install dotfiles to give your console a custom look
- Configure VM as Docker Host
- Set up UniFi Controller
- Set up Xen Orchestra
- Self-update capability
- Enable security updates

## Installation

1. **Clone the repository**:
    ```sh
    git clone https://github.com/Narehood/VM-Setup.git
    ```
2. **Navigate to the project directory**:
    ```sh
    cd VM-Setup
    ```

## Usage

1. **Navigate to the project directory**:
    ```sh
    bash install.sh
    ```

**Follow the on-screen instructions** to select your desired configuration:
    1. XCP-NG / Virtual Machine Initial Configuration
    2. Xen Orchestra
    3. UniFi Controller
    4. Docker Host Prep
    5. Enable Automated Security Patches
    6. Check for System Updates
    7. Check for Menu Updates
    8. Exit


## Credits

- UniFi Controller: https://glennr.nl/s/unifi-network-controller
- Xen Orchestra: https://github.com/ronivay/XenOrchestraInstallerUpdater
