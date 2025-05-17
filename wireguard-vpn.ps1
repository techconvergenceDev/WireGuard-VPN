[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Install-WireGuard {
    $downloadUrl = "https://download.wireguard.com/windows-client/wireguard-installer.exe"
    $installerPath = "$env:TEMP\wireguard-installer.exe"
    
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath
        Start-Process -FilePath $installerPath -ArgumentList "/quiet", "/qn", "DO_NOT_LAUNCH=1" -Wait
        Remove-Item -Path $installerPath -Force
        return $true
    }
    catch {
        Write-Host "Failed to install WireGuard: $_" -ForegroundColor Red
        return $false
    }
}

function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Host "This script must be run as Administrator." -ForegroundColor Red
        return $false
    }
    
    return $true
}

function Set-WireGuardNetworking {
    param (
        [Parameter(Mandatory=$true)]
        [string]$SubnetCIDR
    )
    
    try {
        Get-NetIPInterface -AddressFamily IPv4 | Set-NetIPInterface -Forwarding Enabled
        
        $primaryAdapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and $_.InterfaceDescription -like "*Ethernet*" -or $_.InterfaceDescription -like "*Network Adapter*"} | Select-Object -First 1
        
        if ($primaryAdapter) {
            Set-NetIPInterface -InterfaceAlias $primaryAdapter.Name -Forwarding Enabled
        }
        else {
            Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | ForEach-Object {
                Set-NetIPInterface -InterfaceAlias $_.Name -Forwarding Enabled
            }
        }
        
        $existingNat = Get-NetNat -Name "WireGuardNAT" -ErrorAction SilentlyContinue
        if ($existingNat) {
            Remove-NetNat -Name "WireGuardNAT" -Confirm:$false
        }
        
        New-NetNat -Name "WireGuardNAT" -InternalIPInterfaceAddressPrefix $SubnetCIDR
        
        $existingRule = Get-NetFirewallRule -DisplayName "WireGuard VPN" -ErrorAction SilentlyContinue
        if ($existingRule) {
            Remove-NetFirewallRule -DisplayName "WireGuard VPN"
        }
        
        New-NetFirewallRule -DisplayName "WireGuard VPN" -Direction Inbound -Protocol UDP -LocalPort 51820 -Action Allow
        
        return $true
    }
    catch {
        Write-Host "Failed to configure networking: $_" -ForegroundColor Red
        return $false
    }
}

function New-WireGuardConfigurations {
    param (
        [Parameter(Mandatory=$true)]
        [string]$PublicIP,
        
        [Parameter(Mandatory=$true)]
        [string]$ServerIP,
        
        [Parameter(Mandatory=$true)]
        [string]$ClientIP,
        
        [Parameter(Mandatory=$true)]
        [string]$SubnetCIDR,
        
        [Parameter(Mandatory=$true)]
        [string]$DNSServers,
        
        [Parameter(Mandatory=$false)]
        [string]$ConfigDir = "$env:UserProfile\WireGuardConfig"
    )
    
    try {
        if (-not (Test-Path -Path $ConfigDir)) {
            New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
        }
        
        $serverPrivateKey = & "C:\Program Files\WireGuard\wg.exe" genkey
        $serverPublicKey = $serverPrivateKey | & "C:\Program Files\WireGuard\wg.exe" pubkey
        
        $clientPrivateKey = & "C:\Program Files\WireGuard\wg.exe" genkey
        $clientPublicKey = $clientPrivateKey | & "C:\Program Files\WireGuard\wg.exe" pubkey
        
        $clientAllowedIP = ($ClientIP -split '/')[0] + "/32"
        
        $serverConfig = @"
[Interface]
PrivateKey = $serverPrivateKey
ListenPort = 51820
Address = $ServerIP

[Peer]
PublicKey = $clientPublicKey
AllowedIPs = $clientAllowedIP
"@
        
        $clientConfig = @"
[Interface]
PrivateKey = $clientPrivateKey
Address = $ClientIP
DNS = $DNSServers

[Peer]
PublicKey = $serverPublicKey
AllowedIPs = 0.0.0.0/0, $SubnetCIDR
Endpoint = ${PublicIP}:51820
PersistentKeepalive = 25
"@
        
        $serverConfigPath = Join-Path -Path $ConfigDir -ChildPath "wg-server.conf"
        $clientConfigPath = Join-Path -Path $ConfigDir -ChildPath "wg-client.conf"
        
        Set-Content -Path $serverConfigPath -Value $serverConfig
        Set-Content -Path $clientConfigPath -Value $clientConfig
        
        return @{
            ServerConfigPath = $serverConfigPath
            ClientConfigPath = $clientConfigPath
            ClientConfig = $clientConfig
        }
    }
    catch {
        Write-Host "Failed to create WireGuard configurations: $_" -ForegroundColor Red
        return $null
    }
}

function Install-WireGuardTunnel {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath
    )
    
    try {
        $wireguardExe = "C:\Program Files\WireGuard\wireguard.exe"
        if (-not (Test-Path -Path $wireguardExe)) {
            $wireguardExe = Get-ChildItem -Path "C:\Program Files" -Filter "wireguard.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
            
            if (-not $wireguardExe) {
                Write-Host "Could not find WireGuard executable." -ForegroundColor Red
                return $false
            }
        }
        
        # Using the proper command line parameters
        & "$wireguardExe" /installtunnelservice "$ConfigPath"
        
        $tunnelName = [System.IO.Path]::GetFileNameWithoutExtension($ConfigPath)
        
        Start-Service "WireGuardTunnel`$$tunnelName" -ErrorAction SilentlyContinue
        Set-Service "WireGuardTunnel`$$tunnelName" -StartupType Automatic -ErrorAction SilentlyContinue
        
        $service = Get-Service "WireGuardTunnel`$$tunnelName" -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq "Running") {
            return $true
        }
        else {
            return $false
        }
    }
    catch {
        Write-Host "Failed to install WireGuard tunnel service: $_" -ForegroundColor Red
        return $false
    }
}

function Start-WireGuardUI {
    try {
        $wireguardExe = "C:\Program Files\WireGuard\wireguard.exe"
        if (-not (Test-Path -Path $wireguardExe)) {
            $wireguardExe = Get-ChildItem -Path "C:\Program Files" -Filter "wireguard.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
            
            if (-not $wireguardExe) {
                return $false
            }
        }
        
        # Start WireGuard UI
        Start-Process -FilePath $wireguardExe
        return $true
    }
    catch {
        return $false
    }
}

function Generate-BetterQRCodeHTML {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ConfigText,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>WireGuard QR Code</title>
    <script src="https://cdn.rawgit.com/davidshimjs/qrcodejs/gh-pages/qrcode.min.js"></script>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
            background-color: #f5f5f5;
        }
        .container {
            background-color: white;
            border-radius: 8px;
            box-shadow: 0 4px 8px rgba(0,0,0,0.1);
            padding: 20px;
            text-align: center;
            max-width: 600px;
            width: 100%;
        }
        h1 {
            color: #333;
            margin-top: 0;
        }
        #qrcode {
            display: flex;
            justify-content: center;
            margin: 20px 0;
        }
        .instructions {
            margin-top: 20px;
            text-align: left;
            padding: 15px;
            background-color: #f9f9f9;
            border-radius: 5px;
            border-left: 4px solid #4CAF50;
        }
        .instructions h2 {
            margin-top: 0;
            color: #4CAF50;
        }
        .instructions ol {
            margin-bottom: 0;
            padding-left: 20px;
        }
        .footer {
            margin-top: 20px;
            font-size: 12px;
            color: #777;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>WireGuard Mobile Configuration</h1>
        <div id="qrcode"></div>
        <div class="instructions">
            <h2>How to Use:</h2>
            <ol>
                <li>Install the WireGuard app on your mobile device</li>
                <li>Open the app and tap the "+" button</li>
                <li>Select "Scan from QR code"</li>
                <li>Scan this QR code with your device's camera</li>
                <li>Name your connection and tap "Create Tunnel"</li>
                <li>Activate the tunnel to connect</li>
            </ol>
        </div>
        <div class="footer">
            Created by Sunil Kumar | techconvergence.dev | Cloud and DevOps Engineer
        </div>
    </div>
    
    <script>
        // Wait for page to load
        window.onload = function() {
            // Create QR code with high error correction
            var qrcode = new QRCode(document.getElementById("qrcode"), {
                text: `$($ConfigText -replace '"', '\"' -replace '`', '\\`')`,
                width: 300,
                height: 300,
                colorDark: "#000000",
                colorLight: "#ffffff",
                correctLevel: QRCode.CorrectLevel.H  // Highest error correction
            });
        };
    </script>
</body>
</html>
"@
    
    Set-Content -Path $OutputPath -Value $htmlContent -Encoding UTF8
    return $true
}

function Open-FileExplorer {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    try {
        Start-Process -FilePath "explorer.exe" -ArgumentList $Path
        return $true
    }
    catch {
        return $false
    }
}

function Display-ImportInstructions {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ClientConfigPath
    )
    
    $message = @"
+-------------------------------------------------------+
|                MANUAL IMPORT REQUIRED                 |
+-------------------------------------------------------+

WireGuard server has been set up successfully, but you need to 
manually import the client configuration:

1. The WireGuard UI has been opened for you
2. Click the "Add Tunnel" button (bottom left)
3. Select "Import tunnel(s) from file"
4. Browse to this location:
   $ClientConfigPath
5. Click "Open"

For your mobile device:
1. A QR code has been opened in your browser
2. Use the WireGuard mobile app to scan it

+-------------------------------------------------------+
"@
    
    Write-Host $message -ForegroundColor Yellow
    
    # Wait for user acknowledgement
    Write-Host "Press Enter after you've completed the client import..." -ForegroundColor Cyan
    Read-Host
}

function Create-InstructionsFile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ClientConfigPath,
        
        [Parameter(Mandatory=$true)]
        [string]$HtmlQRPath,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    $instructionsContent = @"
# WireGuard VPN Setup Instructions
Created by Sunil Kumar
Web: https://techconvergence.dev
Cloud and DevOps Engineer

## Import Client Configuration in WireGuard
1. Open WireGuard
2. Click "Add Tunnel" button (bottom left)
3. Select "Import tunnel(s) from file"
4. Browse to: $ClientConfigPath
5. Click "Open"

## Connect from Mobile Device
1. Install WireGuard app on your mobile device
2. Tap the "+" button
3. Scan the QR code from this file: $HtmlQRPath
4. Tap "Create Tunnel"

## Configuration Files
- Server configuration: $($configs.ServerConfigPath)
- Client configuration: $ClientConfigPath
- QR Code HTML: $HtmlQRPath

## Notes
- The server tunnel is already installed and running
- Your server IP is: $publicIP
- Your VPN subnet is: $subnetCIDR
- DNS servers: $dnsServers

Created by Sunil Kumar
Web: https://techconvergence.dev
Cloud and DevOps Engineer
"@
    
    Set-Content -Path $OutputPath -Value $instructionsContent
    return $true
}

function Setup-WireGuardVPN {
    Write-Host "`nThis script is designed by Sunil Kumar" -ForegroundColor Cyan
    Write-Host "Web: https://techconvergence.dev" -ForegroundColor Cyan
    Write-Host "Cloud and Devops Engineer`n" -ForegroundColor Cyan
    
    if (-not (Test-Administrator)) {
        return
    }
    
    $configDir = "$env:UserProfile\WireGuardConfig"
    if (-not (Test-Path -Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    
    $wireguardInstalled = Test-Path -Path "C:\Program Files\WireGuard\wg.exe"
    
    if (-not $wireguardInstalled) {
        $installWireGuard = Read-Host "WireGuard not found. Install it now? (Y/N)"
        
        if ($installWireGuard -eq "Y" -or $installWireGuard -eq "y") {
            Write-Host "Downloading and installing WireGuard..." -ForegroundColor Cyan
            $wireguardInstalled = Install-WireGuard
            
            if (-not $wireguardInstalled) {
                Write-Host "Failed to install WireGuard. Please install it manually." -ForegroundColor Red
                return
            }
            
            Write-Host "WireGuard installed successfully." -ForegroundColor Green
        }
        else {
            Write-Host "WireGuard is required for this script. Exiting." -ForegroundColor Red
            return
        }
    }
    
    try {
        $defaultPublicIP = (Invoke-WebRequest -Uri "http://checkip.amazonaws.com" -UseBasicParsing).Content.Trim()
    }
    catch {
        $defaultPublicIP = "your.public.ip"
    }
    
    $publicIP = Read-Host "Enter server's public IP (or press Enter to use $defaultPublicIP)"
    
    if ([string]::IsNullOrWhiteSpace($publicIP)) {
        $publicIP = $defaultPublicIP
    }
    
    $defaultServerIP = "10.0.0.1/24"
    $serverIP = Read-Host "Enter server IP with subnet (or press Enter to use $defaultServerIP)"
    
    if ([string]::IsNullOrWhiteSpace($serverIP)) {
        $serverIP = $defaultServerIP
    }
    
    $defaultClientIP = "10.0.0.2/24"
    $clientIP = Read-Host "Enter client IP with subnet (or press Enter to use $defaultClientIP)"
    
    if ([string]::IsNullOrWhiteSpace($clientIP)) {
        $clientIP = $defaultClientIP
    }
    
    $serverIPOnly = ($serverIP -split '/')[0]
    $defaultDNS = "$serverIPOnly, 8.8.8.8"
    $dnsServers = Read-Host "Enter DNS servers (comma separated, or press Enter to use $defaultDNS)"
    
    if ([string]::IsNullOrWhiteSpace($dnsServers)) {
        $dnsServers = $defaultDNS
    }
    
    $subnetParts = $serverIP -split '/'
    if ($subnetParts.Length -eq 2) {
        $ipParts = $subnetParts[0] -split '\.'
        if ($ipParts.Length -eq 4) {
            $subnetCIDR = "$($ipParts[0]).$($ipParts[1]).$($ipParts[2]).0/$($subnetParts[1])"
        }
        else {
            $subnetCIDR = "10.0.0.0/24"
        }
    }
    else {
        $subnetCIDR = "10.0.0.0/24"
    }
    
    Write-Host "`nCreating WireGuard configurations..." -ForegroundColor Cyan
    $configs = New-WireGuardConfigurations -PublicIP $publicIP -ServerIP $serverIP -ClientIP $clientIP -SubnetCIDR $subnetCIDR -DNSServers $dnsServers -ConfigDir $configDir
    
    if (-not $configs) {
        Write-Host "Failed to create WireGuard configurations." -ForegroundColor Red
        return
    }
    
    Write-Host "Configuring network settings..." -ForegroundColor Cyan
    $networkingConfigured = Set-WireGuardNetworking -SubnetCIDR $subnetCIDR
    
    if (-not $networkingConfigured) {
        Write-Host "Failed to configure network settings." -ForegroundColor Red
        return
    }
    
    Write-Host "Installing WireGuard tunnel service..." -ForegroundColor Cyan
    $tunnelInstalled = Install-WireGuardTunnel -ConfigPath $configs.ServerConfigPath
    
    if ($tunnelInstalled) {
        Write-Host "WireGuard tunnel service installed successfully." -ForegroundColor Green
    }
    else {
        Write-Host "Warning: WireGuard tunnel service installation might have issues." -ForegroundColor Yellow
    }
    
    $htmlQRPath = Join-Path -Path $configDir -ChildPath "wg-client-qrcode.html"
    Write-Host "Generating QR code..." -ForegroundColor Cyan
    $htmlGenerated = Generate-BetterQRCodeHTML -ConfigText $configs.ClientConfig -OutputPath $htmlQRPath
    
    $instructionsPath = Join-Path -Path $configDir -ChildPath "INSTRUCTIONS.txt"
    Create-InstructionsFile -ClientConfigPath $configs.ClientConfigPath -HtmlQRPath $htmlQRPath -OutputPath $instructionsPath
    
    # Open file explorer to the configuration directory
    Open-FileExplorer -Path $configDir
    
    # Start WireGuard UI
    Start-WireGuardUI
    
    # Open QR code in browser if available
    if ($htmlGenerated) {
        Start-Process $htmlQRPath
        Write-Host "QR code HTML opened in your browser. Use this to scan with your mobile device." -ForegroundColor Green
    }
    else {
        Write-Host "Failed to generate QR code HTML." -ForegroundColor Red
    }
    
    # Display import instructions
    Display-ImportInstructions -ClientConfigPath $configs.ClientConfigPath
    
    Write-Host "`nWireGuard VPN Setup Complete!" -ForegroundColor Green
    Write-Host "- Server configuration: $($configs.ServerConfigPath)" -ForegroundColor Yellow
    Write-Host "- Client configuration: $($configs.ClientConfigPath)" -ForegroundColor Yellow
    Write-Host "- QR Code HTML: $htmlQRPath" -ForegroundColor Yellow
    Write-Host "- Instructions: $instructionsPath" -ForegroundColor Yellow
    
    Write-Host "`nTo connect from your mobile device, scan the QR code from your browser." -ForegroundColor Cyan
    Write-Host "Your VPN server is ready to accept connections!" -ForegroundColor Green
}

Setup-WireGuardVPN
