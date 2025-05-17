#!/bin/bash
# WireGuard VPN Setup Script for Ubuntu Server
# Created by Sunil Kumar
# https://techconvergence.dev
# 
# This script automates the setup of a WireGuard VPN server on Ubuntu,
# generates client configurations, and creates QR codes for mobile devices.

# Set terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   echo "Try: sudo bash $0"
   exit 1
fi

# Detect Ubuntu version
if ! grep -q "Ubuntu" /etc/os-release; then
    echo -e "${RED}This script is designed for Ubuntu Server.${NC}"
    echo "Your system appears to be running a different distribution."
    exit 1
fi

echo -e "${BLUE}WireGuard VPN Setup Script for Ubuntu Server${NC}"
echo -e "${BLUE}Created by Sunil Kumar${NC}"
echo -e "${BLUE}https://techconvergence.dev${NC}"
echo ""

# Function to install required packages
install_packages() {
    echo -e "${GREEN}Installing required packages...${NC}"
    apt update
    apt install -y wireguard qrencode net-tools iptables resolvconf

    # Check if installation was successful
    if ! command -v wg &> /dev/null; then
        echo -e "${RED}WireGuard installation failed.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Packages installed successfully.${NC}"
}

# Function to enable IP forwarding
enable_ip_forwarding() {
    echo -e "${GREEN}Enabling IP forwarding...${NC}"
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-wireguard.conf
    echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.d/99-wireguard.conf
    sysctl -p /etc/sysctl.d/99-wireguard.conf
    
    echo -e "${GREEN}IP forwarding enabled.${NC}"
}

# Function to configure the WireGuard server
configure_wireguard_server() {
    echo -e "${GREEN}Configuring WireGuard server...${NC}"
    
    # Create WireGuard directory
    mkdir -p /etc/wireguard/clients
    chmod 700 /etc/wireguard
    chmod 700 /etc/wireguard/clients
    
    # Generate server keys
    wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
    SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server_private.key)
    SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public.key)
    
    # Get public IP address
    PUBLIC_IP=$(curl -s https://api.ipify.org)
    if [[ -z "$PUBLIC_IP" ]]; then
        PUBLIC_IP=$(curl -s https://icanhazip.com)
    fi
    
    # If still no IP, ask the user
    if [[ -z "$PUBLIC_IP" ]]; then
        echo -e "${YELLOW}Could not detect public IP address.${NC}"
        read -p "Please enter your server's public IP address: " PUBLIC_IP
    fi
    
    # Get server network interface
    INTERFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)
    if [[ -z "$INTERFACE" ]]; then
        echo -e "${YELLOW}Could not detect network interface.${NC}"
        read -p "Please enter your server's network interface (e.g., eth0): " INTERFACE
    fi
    
    # Ask for VPN subnet
    echo ""
    echo "Please enter VPN subnet details"
    read -p "VPN subnet (default: 10.0.0.0/24): " VPN_SUBNET
    VPN_SUBNET=${VPN_SUBNET:-"10.0.0.0/24"}
    
    # Calculate server IP
    SERVER_IP=$(echo $VPN_SUBNET | awk -F'/' '{print $1}' | awk -F'.' '{print $1"."$2"."$3".1"}')
    
    # Ask for UDP port
    read -p "WireGuard UDP port (default: 51820): " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-"51820"}
    
    # Ask for DNS servers
    read -p "DNS servers for VPN clients (default: 1.1.1.1,8.8.8.8): " DNS_SERVERS
    DNS_SERVERS=${DNS_SERVERS:-"1.1.1.1,8.8.8.8"}
    
    # Create server configuration
    cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = ${SERVER_IP}/24
PrivateKey = ${SERVER_PRIVATE_KEY}
ListenPort = ${SERVER_PORT}

# Enable PostUp and PostDown scripts to configure NAT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${INTERFACE} -j MASQUERADE
EOF
    
    # Set correct permissions
    chmod 600 /etc/wireguard/wg0.conf
    
    echo -e "${GREEN}WireGuard server configured successfully.${NC}"
    
    # Save configuration info for later
    cat > /etc/wireguard/server_info.txt << EOF
SERVER_PUBLIC_KEY=${SERVER_PUBLIC_KEY}
SERVER_IP=${SERVER_IP}
VPN_SUBNET=${VPN_SUBNET}
PUBLIC_IP=${PUBLIC_IP}
SERVER_PORT=${SERVER_PORT}
DNS_SERVERS=${DNS_SERVERS}
INTERFACE=${INTERFACE}
EOF
}

# Function to create client configuration
create_client_config() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: create_client_config client_name [client_ip]"
        return 1
    fi
    
    local CLIENT_NAME=$1
    
    # Load server info
    source /etc/wireguard/server_info.txt
    
    # Calculate client IP if not provided
    if [[ $# -lt 2 ]]; then
        # Get number of existing clients
        EXISTING_CLIENTS=$(grep -c "\[Peer\]" /etc/wireguard/wg0.conf)
        CLIENT_NUM=$((EXISTING_CLIENTS + 2)) # +2 because server is .1 and we start from .2
        
        # Calculate client IP
        CLIENT_IP=$(echo $VPN_SUBNET | awk -F'/' '{print $1}' | awk -F'.' "{print \$1\".\"\$2\".\"\$3\".${CLIENT_NUM}\"}")
    else
        CLIENT_IP=$2
    fi
    
    echo -e "${GREEN}Creating client configuration for ${CLIENT_NAME}...${NC}"
    
    # Generate client keys
    wg genkey | tee /etc/wireguard/clients/${CLIENT_NAME}_private.key | wg pubkey > /etc/wireguard/clients/${CLIENT_NAME}_public.key
    CLIENT_PRIVATE_KEY=$(cat /etc/wireguard/clients/${CLIENT_NAME}_private.key)
    CLIENT_PUBLIC_KEY=$(cat /etc/wireguard/clients/${CLIENT_NAME}_public.key)
    
    # Create client configuration
    cat > /etc/wireguard/clients/${CLIENT_NAME}.conf << EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_IP}/24
DNS = ${DNS_SERVERS}

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
AllowedIPs = 0.0.0.0/0
Endpoint = ${PUBLIC_IP}:${SERVER_PORT}
PersistentKeepalive = 25
EOF
    
    # Add client to server configuration
    cat >> /etc/wireguard/wg0.conf << EOF

[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${CLIENT_IP}/32
EOF
    
    # Generate QR code
    echo -e "${GREEN}Generating QR code for ${CLIENT_NAME}...${NC}"
    qrencode -t ansiutf8 < /etc/wireguard/clients/${CLIENT_NAME}.conf
    
    # Generate QR code as PNG image
    qrencode -t png -o /etc/wireguard/clients/${CLIENT_NAME}_qrcode.png < /etc/wireguard/clients/${CLIENT_NAME}.conf
    
    # Generate HTML file with QR code
    cat > /etc/wireguard/clients/${CLIENT_NAME}_qrcode.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>WireGuard VPN - ${CLIENT_NAME} QR Code</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            text-align: center;
            background: #f5f5f5;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
        }
        img {
            max-width: 100%;
            height: auto;
            margin: 20px 0;
            border: 1px solid #ddd;
            padding: 10px;
            background: white;
        }
        .instructions {
            text-align: left;
            background: #f9f9f9;
            padding: 15px;
            border-left: 4px solid #4CAF50;
            margin: 20px 0;
        }
        pre {
            background: #f4f4f4;
            padding: 10px;
            border-left: 4px solid #ccc;
            overflow-x: auto;
            text-align: left;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>WireGuard VPN - ${CLIENT_NAME}</h1>
        <p>Scan this QR code with the WireGuard mobile app to connect</p>
        
        <img src="${CLIENT_NAME}_qrcode.png" alt="WireGuard QR Code">
        
        <div class="instructions">
            <h3>Instructions:</h3>
            <ol>
                <li>Install the WireGuard app from your app store</li>
                <li>Open the app and tap the + button</li>
                <li>Choose "Scan from QR code"</li>
                <li>Scan the QR code above</li>
                <li>Save and enable the tunnel</li>
            </ol>
        </div>
        
        <h3>Configuration File:</h3>
        <pre>${CLIENT_NAME}.conf</pre>
        <p>You can also download the configuration file and import it manually into the WireGuard client.</p>
        
        <p>Server: ${PUBLIC_IP}<br>
        Port: ${SERVER_PORT}<br>
        Created by: techconvergence.dev</p>
    </div>
</body>
</html>
EOF
    
    # Set permissions
    chmod 600 /etc/wireguard/clients/${CLIENT_NAME}.conf
    chmod 600 /etc/wireguard/clients/${CLIENT_NAME}_private.key
    chmod 600 /etc/wireguard/clients/${CLIENT_NAME}_public.key
    
    echo -e "${GREEN}Client ${CLIENT_NAME} added successfully.${NC}"
    echo -e "Configuration saved to: ${BLUE}/etc/wireguard/clients/${CLIENT_NAME}.conf${NC}"
    echo -e "QR code saved to: ${BLUE}/etc/wireguard/clients/${CLIENT_NAME}_qrcode.png${NC}"
    echo -e "HTML page saved to: ${BLUE}/etc/wireguard/clients/${CLIENT_NAME}_qrcode.html${NC}"
    
    # Restart WireGuard if it's already running
    if systemctl is-active --quiet wg-quick@wg0; then
        systemctl restart wg-quick@wg0
        echo -e "${GREEN}WireGuard service restarted with new configuration.${NC}"
    fi
}

# Function to enable and start WireGuard service
enable_wireguard_service() {
    echo -e "${GREEN}Enabling WireGuard service...${NC}"
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
    
    if systemctl is-active --quiet wg-quick@wg0; then
        echo -e "${GREEN}WireGuard service started successfully.${NC}"
    else
        echo -e "${RED}WireGuard service failed to start.${NC}"
        echo "Check the service status with: systemctl status wg-quick@wg0"
        return 1
    fi
    
    return 0
}

# Function to setup UFW firewall
setup_firewall() {
    echo -e "${GREEN}Setting up firewall...${NC}"
    
    # Check if UFW is installed
    if ! command -v ufw &> /dev/null; then
        apt update
        apt install -y ufw
    fi
    
    # Load server info
    source /etc/wireguard/server_info.txt
    
    # Allow SSH (prevent lockout)
    ufw allow 22/tcp
    
    # Allow WireGuard
    ufw allow ${SERVER_PORT}/udp
    
    # Enable UFW if not already enabled
    if ! ufw status | grep -q "Status: active"; then
        echo "y" | ufw enable
    fi
    
    echo -e "${GREEN}Firewall configured.${NC}"
    echo "SSH (port 22) and WireGuard (port ${SERVER_PORT}) are allowed."
}

# Function to display server info
display_server_info() {
    # Load server info
    source /etc/wireguard/server_info.txt
    
    echo ""
    echo -e "${BLUE}WireGuard Server Information:${NC}"
    echo -e "Public IP: ${GREEN}${PUBLIC_IP}${NC}"
    echo -e "VPN Subnet: ${GREEN}${VPN_SUBNET}${NC}"
    echo -e "Server Port: ${GREEN}${SERVER_PORT}${NC}"
    echo -e "Server IP in VPN: ${GREEN}${SERVER_IP}${NC}"
    echo -e "Network Interface: ${GREEN}${INTERFACE}${NC}"
    echo -e "DNS Servers: ${GREEN}${DNS_SERVERS}${NC}"
    
    echo ""
    echo -e "${BLUE}WireGuard Status:${NC}"
    wg show
    
    echo ""
    echo -e "${BLUE}Firewall Status:${NC}"
    ufw status
}

# Function to create a user-friendly HTML dashboard for clients
create_dashboard() {
    echo -e "${GREEN}Creating client dashboard...${NC}"
    
    # Create directory for web content
    mkdir -p /var/www/html/wireguard
    
    # Load server info
    source /etc/wireguard/server_info.txt
    
    # Get list of clients
    CLIENT_LIST=""
    for CONF_FILE in /etc/wireguard/clients/*.conf; do
        if [[ -f "$CONF_FILE" ]]; then
            CLIENT_NAME=$(basename "$CONF_FILE" .conf)
            
            # Skip HTML files (they may have .conf in the name)
            if [[ "$CLIENT_NAME" == *"_qrcode"* ]]; then
                continue
            fi
            
            # Create client row
            CLIENT_LIST+="<tr>"
            CLIENT_LIST+="<td>${CLIENT_NAME}</td>"
            CLIENT_LIST+="<td><a href='clients/${CLIENT_NAME}_qrcode.html' class='button'>View QR Code</a></td>"
            CLIENT_LIST+="<td><a href='clients/${CLIENT_NAME}.conf' class='button'>Download Config</a></td>"
            CLIENT_LIST+="<td><a href='clients/${CLIENT_NAME}_qrcode.png' download='${CLIENT_NAME}_qrcode.png' class='button'>Download QR Image</a></td>"
            CLIENT_LIST+="</tr>"
            
            # Copy client files to web directory
            cp /etc/wireguard/clients/${CLIENT_NAME}* /var/www/html/wireguard/clients/ 2>/dev/null
        fi
    done
    
    # Create clients directory in web root
    mkdir -p /var/www/html/wireguard/clients
    
    # Generate dashboard HTML
    cat > /var/www/html/wireguard/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>WireGuard VPN Dashboard</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            max-width: 1000px;
            margin: 0 auto;
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            text-align: center;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th {
            background: #4CAF50;
            color: white;
            text-align: left;
            padding: 12px;
        }
        td {
            border-bottom: 1px solid #ddd;
            padding: 12px;
        }
        tr:hover {
            background-color: #f5f5f5;
        }
        .button {
            display: inline-block;
            background: #4CAF50;
            color: white;
            padding: 8px 12px;
            text-decoration: none;
            border-radius: 4px;
            font-size: 14px;
        }
        .button:hover {
            background: #45a049;
        }
        .server-info {
            background: #f9f9f9;
            padding: 15px;
            border-left: 4px solid #4CAF50;
            margin: 20px 0;
        }
        footer {
            text-align: center;
            margin-top: 30px;
            color: #777;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>WireGuard VPN Dashboard</h1>
        
        <div class="server-info">
            <h3>Server Information:</h3>
            <p><strong>Public IP:</strong> ${PUBLIC_IP}</p>
            <p><strong>Port:</strong> ${SERVER_PORT}</p>
            <p><strong>VPN Subnet:</strong> ${VPN_SUBNET}</p>
        </div>
        
        <h2>Client Configurations</h2>
        <table>
            <tr>
                <th>Client Name</th>
                <th>QR Code</th>
                <th>Config File</th>
                <th>QR Image</th>
            </tr>
            ${CLIENT_LIST}
        </table>
        
        <div class="instructions">
            <h3>How to connect:</h3>
            <ol>
                <li><strong>Mobile devices:</strong> Install WireGuard app, tap the + button, scan the QR code.</li>
                <li><strong>Desktop computers:</strong> Install WireGuard client, download the configuration file, and import it.</li>
            </ol>
        </div>
        
        <footer>
            <p>Created by: <a href="https://techconvergence.dev">techconvergence.dev</a></p>
        </footer>
    </div>
</body>
</html>
EOF
    
    # Set permissions
    chmod -R 755 /var/www/html/wireguard
    find /var/www/html/wireguard -type f -name "*.conf" -exec chmod 644 {} \;
    find /var/www/html/wireguard -type f -name "*.html" -exec chmod 644 {} \;
    find /var/www/html/wireguard -type f -name "*.png" -exec chmod 644 {} \;
    
    # Nginx check and setup if available
    if command -v nginx &> /dev/null; then
        echo -e "${GREEN}Setting up Nginx to serve the dashboard...${NC}"
        
        # Create Nginx config
        cat > /etc/nginx/sites-available/wireguard << EOF
server {
    listen 80;
    
    # Dashboard location
    location /wireguard/ {
        alias /var/www/html/wireguard/;
        autoindex off;
        try_files \$uri \$uri/ =404;
    }
}
EOF
        
        # Enable the site
        ln -sf /etc/nginx/sites-available/wireguard /etc/nginx/sites-enabled/
        
        # Test and reload Nginx
        nginx -t && systemctl reload nginx
        
        echo -e "${GREEN}Dashboard available at: http://${PUBLIC_IP}/wireguard/${NC}"
    else
        echo -e "${YELLOW}Nginx not installed. For better dashboard access, consider installing Nginx:${NC}"
        echo "apt install -y nginx"
        echo "Then run this script again."
        
        echo -e "${YELLOW}For now, you can access client configs directly from:${NC}"
        echo -e "${BLUE}/etc/wireguard/clients/${NC}"
    fi
}

# Main function
main() {
    echo -e "${BLUE}Starting WireGuard VPN setup...${NC}"
    
    # Install required packages
    install_packages
    
    # Enable IP forwarding
    enable_ip_forwarding
    
    # Configure WireGuard server
    configure_wireguard_server
    
    # Create first client
    echo -e "${YELLOW}Let's create your first client configuration.${NC}"
    read -p "Enter client name (e.g., phone, laptop): " CLIENT_NAME
    CLIENT_NAME=${CLIENT_NAME:-"client1"}
    create_client_config "$CLIENT_NAME"
    
    # Setup firewall
    setup_firewall
    
    # Enable and start WireGuard service
    enable_wireguard_service
    
    # Create dashboard
    create_dashboard
    
    # Display server information
    display_server_info
    
    echo ""
    echo -e "${GREEN}WireGuard VPN setup complete!${NC}"
    echo -e "Client configuration files are in ${BLUE}/etc/wireguard/clients/${NC}"
    
    # Print dashboard access information if Nginx is installed
    if command -v nginx &> /dev/null; then
        echo -e "Access the dashboard at: ${GREEN}http://${PUBLIC_IP}/wireguard/${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}To add more clients, use:${NC}"
    echo -e "${BLUE}sudo bash $0 add-client client_name${NC}"
    
    echo ""
    echo -e "${YELLOW}To view server status, use:${NC}"
    echo -e "${BLUE}sudo bash $0 status${NC}"
}

# Parse command line arguments
if [[ $# -gt 0 ]]; then
    case "$1" in
        add-client)
            if [[ $# -lt 2 ]]; then
                echo -e "${RED}Error: Please provide a client name${NC}"
                echo -e "Usage: $0 add-client client_name"
                exit 1
            fi
            
            create_client_config "$2"
            # Update dashboard
            create_dashboard
            ;;
        status)
            display_server_info
            ;;
        help)
            echo "Usage:"
            echo "  $0                 : Run the full setup"
            echo "  $0 add-client NAME : Add a new client"
            echo "  $0 status          : Display server status"
            echo "  $0 help            : Show this help"
            ;;
        *)
            echo -e "${RED}Unknown command: $1${NC}"
            echo "Use \"$0 help\" for available commands"
            exit 1
            ;;
    esac
else
    # No arguments, run the full setup
    main
fi

exit 0
