# XCP-NG Tools and Server Setup Script

This script automates the installation of XCP-NG Tools and standard server tools on various Linux distributions. It also provides an option to change the hostname and clone a dotfiles repository.

## Features

- Installs XCP-NG Tools on Debian, Ubuntu, Red Hat, Arch, and SUSE based systems.
- Installs standard server tools (`net-tools`, `cockpit`, `htop`) on Debian, Ubuntu, Red Hat, Arch, and SUSE based systems.
- Option to change the hostname.
- Installs Dotfiles to make your shell look like the example below.
   ![-Dotfiles-Example](Dotfiles-Example.png)

## Usage

1. **Clone the Repository:**

   ```bash
   git clone https://github.com/Narehood/VM-Setup
   cd VM-Setup

2. **Run The Script:**

   ```bash
   bash install.sh

# Script Details
This script is a **menu-driven utility** for setting up various virtual machine (VM) and server configurations. Here's a summary of what it does:

1. **Displays System Information**: Shows details like Linux distribution, kernel version, CPU usage, memory usage, and disk usage.
2. **Presents a Menu**: Offers options for different setup tasks:
   - **XCP-NG / Virtual Machine Initial Configuration**: Runs `serverSetup.sh` for initial VM setup.
   - **Xen Orchestra**: Runs `XenOrchestra.sh` to set up Xen Orchestra.
   - **UniFi Controller**: Runs `UniFi-Controller.sh` to set up the UniFi Controller.
   - **Docker Host Prep**: Prepares the system for Docker by running `install.sh` in the Docker-Prep directory.
   - **Check for Updates**: Placeholder for a future update-checking feature.
   - **Exit**: Exits the script.

3. **Handles User Input**: Continuously prompts the user to select an option and executes the corresponding script or action.

<br /><br /><br />
## Credit/License

### License
This project is licensed under the MIT License - see the LICENSE file for details.
### Contributing
Feel free to submit issues or pull requests if you have any improvements or suggestions.
### Acknowledgments
Thanks to the open-source community for providing the tools and resources used in this script.
