#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures SSH Server on Windows Server 2025 for PowerShell remoting
.DESCRIPTION
    This script installs and configures OpenSSH Server, PowerShell SSH subsystem,
    and creates necessary firewall rules for secure remote PowerShell access.
.PARAMETER AllowedUsers
    Array of users allowed to connect via SSH (optional)
.PARAMETER SSHPort
    SSH port number (default: 22)
.PARAMETER EnableKeyAuthentication
    Enable SSH key authentication (default: true)
.PARAMETER DisablePasswordAuthentication
    Disable password authentication (default: false)
.EXAMPLE
    .\Setup-SSHServer-Windows2025.ps1 -AllowedUsers @("DOMAIN\user1", "DOMAIN\user2")
.EXAMPLE
    .\Setup-SSHServer-Windows2025.ps1 -SSHPort 2222 -DisablePasswordAuthentication
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$AllowedUsers = @(),

    [Parameter(Mandatory = $false)]
    [int]$SSHPort = 22,

    [Parameter(Mandatory = $false)]
    [switch]$EnableKeyAuthentication = $true,

    [Parameter(Mandatory = $false)]
    [switch]$DisablePasswordAuthentication = $false
)

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    throw "This script must be run as Administrator"
}

Write-Host "=== SSH Server Setup for Windows Server 2025 ===" -ForegroundColor Green

# Step 1: Install OpenSSH Server
Write-Host "`n1. Installing OpenSSH Server..." -ForegroundColor Yellow
try {
    $sshServerFeature = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
    if ($sshServerFeature.State -ne "Installed") {
        Write-Host "Installing OpenSSH Server capability..." -ForegroundColor White
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        Write-Host "OpenSSH Server installed successfully" -ForegroundColor Green
    } else {
        Write-Host "OpenSSH Server already installed" -ForegroundColor Green
    }
} catch {
    Write-Error "Failed to install OpenSSH Server: $($_.Exception.Message)"
    exit 1
}

# Step 2: Start and configure SSH service
Write-Host "`n2. Configuring SSH Service..." -ForegroundColor Yellow
try {
    # Start sshd service
    Start-Service sshd
    Set-Service -Name sshd -StartupType 'Automatic'
    Write-Host "SSH service started and set to automatic startup" -ForegroundColor Green

    # Start ssh-agent service (for key management)
    Start-Service ssh-agent
    Set-Service -Name ssh-agent -StartupType 'Automatic'
    Write-Host "SSH Agent service started and set to automatic startup" -ForegroundColor Green
} catch {
    Write-Error "Failed to configure SSH services: $($_.Exception.Message)"
    exit 1
}

# Step 3: Configure Firewall
Write-Host "`n3. Configuring Windows Firewall..." -ForegroundColor Yellow
try {
    $firewallRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    if (-not $firewallRule) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort $SSHPort
        Write-Host "Firewall rule created for SSH (port $SSHPort)" -ForegroundColor Green
    } else {
        Write-Host "SSH firewall rule already exists" -ForegroundColor Green
    }
} catch {
    Write-Error "Failed to configure firewall: $($_.Exception.Message)"
    exit 1
}

# Step 4: Configure SSH for PowerShell
Write-Host "`n4. Configuring SSH for PowerShell Remoting..." -ForegroundColor Yellow
try {
    $sshConfigPath = "$env:ProgramData\ssh\sshd_config"
    $sshConfigBackup = "$env:ProgramData\ssh\sshd_config.backup"

    # Create backup of original config
    if (-not (Test-Path $sshConfigBackup)) {
        Copy-Item $sshConfigPath $sshConfigBackup
        Write-Host "Created backup of SSH config" -ForegroundColor Green
    }

    # Read current config
    $sshConfig = Get-Content $sshConfigPath

    # Configure PowerShell as SSH subsystem
    $powershellPath = Get-CommandPathWithFallback "pwsh"
    if (-not $powershellPath) {
        $powershellPath = Get-CommandPathWithFallback "powershell"
    }

    if (-not $powershellPath) {
        throw "PowerShell executable not found"
    }

    $subsystemLine = "Subsystem powershell $powershellPath -sshs -NoLogo"

    # Check if PowerShell subsystem is already configured
    if ($sshConfig -notmatch "Subsystem.*powershell") {
        $sshConfig += $subsystemLine
        Write-Host "Added PowerShell subsystem to SSH config" -ForegroundColor Green
    }

    # Configure authentication methods
    $authConfig = @()

    if ($EnableKeyAuthentication) {
        $authConfig += "PubkeyAuthentication yes"
        $authConfig += "AuthorizedKeysFile .ssh/authorized_keys"
        Write-Host "Enabled public key authentication" -ForegroundColor Green
    }

    if ($DisablePasswordAuthentication) {
        $authConfig += "PasswordAuthentication no"
        Write-Host "Disabled password authentication" -ForegroundColor Green
    } else {
        $authConfig += "PasswordAuthentication yes"
        Write-Host "Enabled password authentication" -ForegroundColor Green
    }

    # Add authentication configuration
    foreach ($config in $authConfig) {
        $configKey = $config.Split(' ')[0]
        if ($sshConfig -notmatch "^$configKey") {
            $sshConfig += $config
        }
    }

    # Set SSH port if different from default
    if ($SSHPort -ne 22) {
        if ($sshConfig -notmatch "^Port") {
            $sshConfig += "Port $SSHPort"
            Write-Host "Set SSH port to $SSHPort" -ForegroundColor Green
        }
    }

    # Write updated config
    $sshConfig | Out-File -FilePath $sshConfigPath -Encoding UTF8

    # Restart SSH service to apply changes
    Restart-Service sshd
    Write-Host "SSH service restarted with new configuration" -ForegroundColor Green

} catch {
    Write-Error "Failed to configure SSH for PowerShell: $($_.Exception.Message)"
    exit 1
}

# Step 5: Configure user access
if ($AllowedUsers.Count -gt 0) {
    Write-Host "`n5. Configuring user access..." -ForegroundColor Yellow
    try {
        $allowUsersLine = "AllowUsers " + ($AllowedUsers -join " ")
        $sshConfig = Get-Content $sshConfigPath

        # Remove existing AllowUsers line
        $sshConfig = $sshConfig | Where-Object { $_ -notmatch "^AllowUsers" }

        # Add new AllowUsers line
        $sshConfig += $allowUsersLine

        $sshConfig | Out-File -FilePath $sshConfigPath -Encoding UTF8

        Restart-Service sshd
        Write-Host "Configured allowed users: $($AllowedUsers -join ', ')" -ForegroundColor Green
    } catch {
        Write-Error "Failed to configure user access: $($_.Exception.Message)"
    }
}

Write-Host "`n=== SSH Server Setup Complete ===" -ForegroundColor Green
Write-Host "Server is now ready for SSH connections on port $SSHPort" -ForegroundColor White
Write-Host "PowerShell remoting is available via SSH subsystem" -ForegroundColor White

# Display connection information
$serverName = $env:COMPUTERNAME
Write-Host "`nConnection Examples:" -ForegroundColor Cyan
Write-Host "  SSH: ssh $env:USERNAME@$serverName" -ForegroundColor White
Write-Host "  PowerShell: Invoke-Command -HostName $serverName -UserName $env:USERNAME -ScriptBlock { Get-Process }" -ForegroundColor White

if ($EnableKeyAuthentication) {
    Write-Host "`nFor key-based authentication, clients need to:" -ForegroundColor Yellow
    Write-Host "  1. Generate SSH keys: ssh-keygen -t rsa -b 4096" -ForegroundColor White
    Write-Host "  2. Copy public key: ssh-copy-id $env:USERNAME@$serverName" -ForegroundColor White
}

