WireGuard VPN Setup with QR Code Generator
Show Image
A collection of scripts that automatically set up a WireGuard VPN server and generate scannable QR codes for easy mobile device connection. Available for both Windows and Ubuntu platforms.
Features

One-Click Server Setup: Fully automated WireGuard VPN server installation and configuration
Auto QR Code Generation: Creates scannable QR codes directly in your browser or terminal
Mobile-Ready: Instantly connect Android or iOS devices by scanning the QR code
Secure Configuration: Properly configured with best-practice security settings
Zero External Dependencies: No reliance on third-party websites for QR code generation
Multi-Platform Support: Works on Windows 10/11, Windows Server, and Ubuntu Server

Platform Support
Windows
The wireguard-setup.ps1 script provides automated setup for Windows 10/11 and Windows Server environments.
Requirements:

Windows 10/11 or Windows Server 2016/2019/2022
PowerShell 5.1 or newer
Administrator privileges
Internet connection for downloading WireGuard (if not already installed)
Port 51820/UDP accessible

See Windows Setup Instructions
Ubuntu
The wireguard-ubuntu-setup.sh script provides automated setup for Ubuntu Server environments.
Requirements:

Ubuntu Server 18.04 or newer
Root privileges (sudo)
Internet connection for installing packages
Port 51820/UDP accessible

See Ubuntu Setup Instructions
Windows Installation {#windows-installation}

Clone this repository or download the script:
git clone https://github.com/techconvergenceDev/WireGuard-VPN.git

Run PowerShell as Administrator
Navigate to the script directory:
cd WireGuard-VPN

Set the execution policy to allow the script (if needed):
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

Run the script:
.\wireguard-setup.ps1

Follow the on-screen prompts

How It Works

Setup Phase:

Checks if WireGuard is installed and offers to install it if not
Detects your public IP address automatically
Creates server and client configurations with secure settings
Configures network settings, NAT, and firewall rules
Installs the WireGuard tunnel service


QR Code Generation:

Creates a local HTML file with your client configuration
Generates a QR code using secure methods
Opens the QR code for easy scanning


Mobile Connection:

Scan the QR code with the WireGuard mobile app
Connect with a single tap - no manual configuration needed



Customization
Both scripts allow for customization of:

Server and client IP addresses
VPN subnet configuration
DNS servers
Port forwarding (if needed)

Troubleshooting
For detailed troubleshooting information, see the Troubleshooting Guide.
Advanced Configuration
For advanced configuration options, see the Advanced Configuration Guide.
Security Notes

These scripts generate new keys for each setup, ensuring unique secure configurations
The server is configured to only accept connections from authorized clients
All traffic between clients and the server is encrypted using WireGuard's modern cryptography

Contributing
Contributions are welcome! Please feel free to submit a Pull Request.
License
This project is licensed under the MIT License - see the LICENSE file for details.
Acknowledgments

WireGuard - For creating an excellent VPN protocol
QR Server API - For the QR code generation capability
Sunil Kumar - Original script developer and maintainer
