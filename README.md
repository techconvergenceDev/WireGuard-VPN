WireGuard Easy VPN Setup

A PowerShell script that automatically sets up a WireGuard VPN server on Windows and generates a scannable QR code for easy mobile device connection.
Features

One-Click Server Setup: Fully automated WireGuard VPN server setup on Windows
Auto QR Code Generation: Creates a scannable QR code without external websites
Mobile-Ready: Instantly connect Android or iOS devices by scanning the QR code
Secure Configuration: Properly configured with best-practice security settings
Zero Dependencies: No external dependencies beyond WireGuard itself
User-Friendly: Simple and guided setup process with clear instructions

Requirements

Windows 10/11 or Windows Server 2016/2019/2022
PowerShell 5.1 or newer (pre-installed on modern Windows systems)
Administrator privileges
Internet connection for downloading WireGuard (if not already installed)
Port 51820/UDP accessible (configure firewall/router as needed)

Use Cases
1. Secure Remote Access to Home Network
Set up a secure connection to your home network to access files, devices, and services while traveling.
2. Business VPN for Remote Workers
Provide employees with secure access to company resources without complex enterprise VPN solutions.
3. Bypass Geographic Restrictions
Access content and services that might be restricted in your current location by routing through your server.
4. Network Security on Public Wi-Fi
Encrypt your traffic when using public Wi-Fi networks to protect your data from eavesdropping.
5. IoT Device Management
Create a secure network for managing IoT devices remotely with encrypted communications.
6. Gaming with Friends
Establish a secure private network for gaming with friends, simulating a LAN environment.
7. Media Server Access
Securely access your Plex, Jellyfin, or other media servers from anywhere.
Installation

Clone this repository or download the script:
git clone https://github.com/yourusername/wireguard-easy-vpn.git

Run PowerShell as Administrator
Navigate to the script directory:
cd wireguard-easy-vpn

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
Generates a QR code using the QR Server API
Opens the QR code in Microsoft Edge for easy scanning


Mobile Connection:

Scan the QR code with the WireGuard mobile app
Connect with a single tap - no manual configuration needed



Customization
The script allows for customization of:

Server and client IP addresses
VPN subnet configuration
DNS servers
Port forwarding (if needed)

Troubleshooting
QR Code Not Displaying
If the QR code doesn't appear automatically:

Click the "Show/Hide Configuration Text" button
Copy the displayed configuration
Use any QR code generator or the official WireGuard app's manual import option

Connection Issues

Ensure port 51820/UDP is forwarded on your router to your server
Check that your firewall allows incoming connections on port 51820/UDP
Verify the server's public IP address is correct in the configuration

Security Notes

This script generates new keys for each setup, ensuring unique secure configurations
The server is configured to only accept connections from authorized clients
All traffic between clients and the server is encrypted using WireGuard's modern cryptography

Contributing
Contributions are welcome! Please feel free to submit a Pull Request.
License
This project is licensed under the MIT License - see the LICENSE file for details.
Acknowledgments

WireGuard - For creating an excellent VPN protocol
QR Server API - For the QR code generation capability
Sunil Kumar - Original script developer and maintainer (https://techconvergence.dev)
