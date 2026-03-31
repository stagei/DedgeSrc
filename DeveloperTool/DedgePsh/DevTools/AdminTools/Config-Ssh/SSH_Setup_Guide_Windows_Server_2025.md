# SSH Setup Guide for Windows Server 2025

## Table of Contents
1. [Overview](#overview)
2. [Server-Side Setup](#server-side-setup)
3. [Client-Side Setup](#client-side-setup)
4. [PowerShell Remoting over SSH](#powershell-remoting-over-ssh)
5. [Troubleshooting](#troubleshooting)
6. [Security Considerations](#security-considerations)

## Overview

This guide provides step-by-step instructions and PowerShell automation scripts to configure SSH on Windows Server 2025 for secure remote PowerShell sessions.

### Prerequisites
- Windows Server 2025
- PowerShell 7.0 or later
- Administrator privileges
- Network connectivity between client and server

## Server-Side Setup

### Automated Server Setup Script

Save this as `Setup-SSHServer.ps1`:

```powershell
<#
.SYNOPSIS
    Configures SSH Server on Windows Server 2025 for PowerShell remoting
.DESCRIPTION
    This script installs and configures OpenSSH Server, PowerShell SSH subsystem,
    and creates necessary firewall rules for secure remote PowerShell access.
.EXAMPLE
    .\Setup-SSHServer.ps1 -AllowedUsers @("DOMAIN\user1", "DOMAIN\user2")
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
    $powershellPath = Get-CommandPathWithFallback pwsh
    if (-not $powershellPath) {
        $powershellPath = Get-CommandPathWithFallback powershell
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

# Step 6: Create SSH host keys if they don't exist
Write-Host "`n6. Ensuring SSH host keys exist..." -ForegroundColor Yellow
try {
    $hostKeyPath = "$env:ProgramData\ssh\ssh_host_rsa_key"
    if (-not (Test-Path $hostKeyPath)) {
        & ssh-keygen -t rsa -b 4096 -f $hostKeyPath -N '""'
        Write-Host "Generated SSH host RSA key" -ForegroundColor Green
    }
    
    $hostKeyPathEd25519 = "$env:ProgramData\ssh\ssh_host_ed25519_key"
    if (-not (Test-Path $hostKeyPathEd25519)) {
        & ssh-keygen -t ed25519 -f $hostKeyPathEd25519 -N '""'
        Write-Host "Generated SSH host Ed25519 key" -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not generate SSH host keys: $($_.Exception.Message)"
}

Write-Host "`n=== SSH Server Setup Complete ===" -ForegroundColor Green
Write-Host "Server is now ready for SSH connections on port $SSHPort" -ForegroundColor White
Write-Host "PowerShell remoting is available via SSH subsystem" -ForegroundColor White

# Display connection information
$serverName = $env:COMPUTERNAME
$domain = $env:USERDOMAIN
Write-Host "`nConnection Examples:" -ForegroundColor Cyan
Write-Host "  SSH: ssh $env:USERNAME@$serverName" -ForegroundColor White
Write-Host "  PowerShell: Invoke-Command -HostName $serverName -UserName $env:USERNAME -ScriptBlock { Get-Process }" -ForegroundColor White

if ($EnableKeyAuthentication) {
    Write-Host "`nFor key-based authentication, clients need to:" -ForegroundColor Yellow
    Write-Host "  1. Generate SSH keys: ssh-keygen -t rsa -b 4096" -ForegroundColor White
    Write-Host "  2. Copy public key: ssh-copy-id $env:USERNAME@$serverName" -ForegroundColor White
}
```

### Manual Server Configuration Steps

If you prefer manual configuration:

1. **Install OpenSSH Server**:
   ```powershell
   Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
   ```

2. **Start SSH Services**:
   ```powershell
   Start-Service sshd
   Set-Service -Name sshd -StartupType 'Automatic'
   Start-Service ssh-agent
   Set-Service -Name ssh-agent -StartupType 'Automatic'
   ```

3. **Configure Firewall**:
   ```powershell
   New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
   ```

## Client-Side Setup

### Automated Client Setup Script

Save this as `Setup-SSHClient.ps1`:

```powershell
<#
.SYNOPSIS
    Configures SSH Client on Windows for PowerShell remoting
.DESCRIPTION
    This script installs OpenSSH Client, generates SSH keys, and configures
    the client for secure remote PowerShell access.
.EXAMPLE
    .\Setup-SSHClient.ps1 -ServerName "server01" -Username "domain\user"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ServerName = "",
    
    [Parameter(Mandatory = $false)]
    [string]$Username = $env:USERNAME,
    
    [Parameter(Mandatory = $false)]
    [switch]$GenerateKeys = $true,
    
    [Parameter(Mandatory = $false)]
    [string]$KeyType = "rsa",
    
    [Parameter(Mandatory = $false)]
    [int]$KeySize = 4096
)

Write-Host "=== SSH Client Setup for Windows ===" -ForegroundColor Green

# Step 1: Install OpenSSH Client
Write-Host "`n1. Installing OpenSSH Client..." -ForegroundColor Yellow
try {
    $sshClientFeature = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'
    if ($sshClientFeature.State -ne "Installed") {
        Write-Host "Installing OpenSSH Client capability..." -ForegroundColor White
        Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
        Write-Host "OpenSSH Client installed successfully" -ForegroundColor Green
    } else {
        Write-Host "OpenSSH Client already installed" -ForegroundColor Green
    }
} catch {
    Write-Error "Failed to install OpenSSH Client: $($_.Exception.Message)"
    exit 1
}

# Step 2: Start SSH Agent
Write-Host "`n2. Configuring SSH Agent..." -ForegroundColor Yellow
try {
    Start-Service ssh-agent -ErrorAction SilentlyContinue
    Set-Service -Name ssh-agent -StartupType 'Automatic'
    Write-Host "SSH Agent service configured" -ForegroundColor Green
} catch {
    Write-Warning "Could not configure SSH Agent service: $($_.Exception.Message)"
}

# Step 3: Create SSH directory
Write-Host "`n3. Setting up SSH directory..." -ForegroundColor Yellow
$sshDir = "$env:USERPROFILE\.ssh"
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    Write-Host "Created SSH directory: $sshDir" -ForegroundColor Green
} else {
    Write-Host "SSH directory already exists: $sshDir" -ForegroundColor Green
}

# Set appropriate permissions on .ssh directory
try {
    $acl = Get-Acl $sshDir
    $acl.SetAccessRuleProtection($true, $false)
    
    # Remove all existing access rules
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }
    
    # Add owner full control
    $owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($owner, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($accessRule)
    
    Set-Acl -Path $sshDir -AclObject $acl
    Write-Host "Set secure permissions on SSH directory" -ForegroundColor Green
} catch {
    Write-Warning "Could not set secure permissions on SSH directory: $($_.Exception.Message)"
}

# Step 4: Generate SSH keys
if ($GenerateKeys) {
    Write-Host "`n4. Generating SSH keys..." -ForegroundColor Yellow
    $keyPath = "$sshDir\id_$KeyType"
    
    if (-not (Test-Path $keyPath)) {
        try {
            if ($KeyType -eq "ed25519") {
                & ssh-keygen -t ed25519 -f $keyPath -C "$Username@$env:COMPUTERNAME"
            } else {
                & ssh-keygen -t $KeyType -b $KeySize -f $keyPath -C "$Username@$env:COMPUTERNAME"
            }
            Write-Host "Generated SSH $KeyType key pair" -ForegroundColor Green
            
            # Add key to SSH agent
            & ssh-add $keyPath
            Write-Host "Added private key to SSH agent" -ForegroundColor Green
            
        } catch {
            Write-Error "Failed to generate SSH keys: $($_.Exception.Message)"
        }
    } else {
        Write-Host "SSH keys already exist at $keyPath" -ForegroundColor Green
        
        # Try to add existing key to agent
        try {
            & ssh-add $keyPath
            Write-Host "Added existing private key to SSH agent" -ForegroundColor Green
        } catch {
            Write-Warning "Could not add existing key to SSH agent"
        }
    }
    
    # Display public key
    $publicKeyPath = "$keyPath.pub"
    if (Test-Path $publicKeyPath) {
        Write-Host "`nPublic Key:" -ForegroundColor Cyan
        Get-Content $publicKeyPath | Write-Host -ForegroundColor White
        Write-Host "`nPublic key location: $publicKeyPath" -ForegroundColor Yellow
    }
}

# Step 5: Create SSH config file
Write-Host "`n5. Creating SSH client configuration..." -ForegroundColor Yellow
$sshConfigPath = "$sshDir\config"
$sshConfigContent = @"
# SSH Client Configuration
# Generated by Setup-SSHClient.ps1

# Global settings
Host *
    ForwardAgent yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
    
# Add your server configurations here
# Example:
# Host myserver
#     HostName server.domain.com
#     User myusername
#     Port 22
#     IdentityFile ~/.ssh/id_rsa
"@

if (-not (Test-Path $sshConfigPath)) {
    $sshConfigContent | Out-File -FilePath $sshConfigPath -Encoding UTF8
    Write-Host "Created SSH client config file" -ForegroundColor Green
} else {
    Write-Host "SSH client config file already exists" -ForegroundColor Green
}

# Step 6: Add server configuration if provided
if ($ServerName) {
    Write-Host "`n6. Adding server configuration..." -ForegroundColor Yellow
    $serverConfig = @"

# Server: $ServerName
Host $ServerName
    HostName $ServerName
    User $Username
    Port 22
    IdentityFile ~/.ssh/id_$KeyType
    ForwardAgent yes
"@
    
    Add-Content -Path $sshConfigPath -Value $serverConfig
    Write-Host "Added configuration for server: $ServerName" -ForegroundColor Green
}

Write-Host "`n=== SSH Client Setup Complete ===" -ForegroundColor Green

if ($GenerateKeys -and $ServerName) {
    Write-Host "`nNext Steps:" -ForegroundColor Cyan
    Write-Host "1. Copy your public key to the server:" -ForegroundColor White
    Write-Host "   ssh-copy-id $Username@$ServerName" -ForegroundColor Yellow
    Write-Host "2. Test the connection:" -ForegroundColor White
    Write-Host "   ssh $ServerName" -ForegroundColor Yellow
    Write-Host "3. Test PowerShell remoting:" -ForegroundColor White
    Write-Host "   Invoke-Command -HostName $ServerName -UserName $Username -ScriptBlock { Get-Process }" -ForegroundColor Yellow
}
```

### Key Management Functions

Save this as `SSH-KeyManagement.ps1`:

```powershell
<#
.SYNOPSIS
    SSH Key Management Functions
.DESCRIPTION
    Helper functions for managing SSH keys and connections
#>

function Copy-SSHPublicKey {
    <#
    .SYNOPSIS
        Copies SSH public key to remote server
    .PARAMETER ServerName
        Name or IP of the remote server
    .PARAMETER Username
        Username for the remote server
    .PARAMETER KeyPath
        Path to the public key file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$Username,
        
        [Parameter(Mandatory = $false)]
        [string]$KeyPath = "$env:USERPROFILE\.ssh\id_rsa.pub"
    )
    
    if (-not (Test-Path $KeyPath)) {
        throw "Public key not found at $KeyPath"
    }
    
    $publicKey = Get-Content $KeyPath -Raw
    
    try {
        # Use ssh-copy-id if available
        $sshCopyId = $(Get-Command ssh-copy-id -ErrorAction SilentlyContinue).Path
        if ($sshCopyId) {
            & ssh-copy-id -i $KeyPath "$Username@$ServerName"
        } else {
            # Manual method
            $command = "mkdir -p ~/.ssh && echo '$publicKey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && chmod 700 ~/.ssh"
            & ssh "$Username@$ServerName" $command
        }
        
        Write-Host "Public key copied to $ServerName" -ForegroundColor Green
    } catch {
        Write-Error "Failed to copy public key: $($_.Exception.Message)"
    }
}

function Test-SSHConnection {
    <#
    .SYNOPSIS
        Tests SSH connection to a server
    .PARAMETER ServerName
        Name or IP of the remote server
    .PARAMETER Username
        Username for the remote server
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$Username
    )
    
    try {
        Write-Host "Testing SSH connection to $ServerName..." -ForegroundColor Yellow
        $result = & ssh -o ConnectTimeout=10 -o BatchMode=yes "$Username@$ServerName" "echo 'SSH connection successful'"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "SSH connection successful" -ForegroundColor Green
            return $true
        } else {
            Write-Host "SSH connection failed" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Error "SSH connection test failed: $($_.Exception.Message)"
        return $false
    }
}

function Test-PowerShellRemoting {
    <#
    .SYNOPSIS
        Tests PowerShell remoting over SSH
    .PARAMETER ServerName
        Name or IP of the remote server
    .PARAMETER Username
        Username for the remote server
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$Username
    )
    
    try {
        Write-Host "Testing PowerShell remoting to $ServerName..." -ForegroundColor Yellow
        $result = Invoke-Command -HostName $ServerName -UserName $Username -ScriptBlock {
            "PowerShell remoting successful - Server: $env:COMPUTERNAME - PowerShell: $($PSVersionTable.PSVersion)"
        }
        
        Write-Host $result -ForegroundColor Green
        return $true
    } catch {
        Write-Error "PowerShell remoting test failed: $($_.Exception.Message)"
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Copy-SSHPublicKey, Test-SSHConnection, Test-PowerShellRemoting
```

## PowerShell Remoting over SSH

### Configuration for Deploy-Handler Module

Update your Deploy-Handler module to properly handle SSH connections:

```powershell
function Invoke-RemoteCommand {
    <#
    .SYNOPSIS
        Executes commands on remote servers via SSH
    .PARAMETER ServerName
        Name of the remote server
    .PARAMETER Username
        Username for SSH connection
    .PARAMETER ScriptBlock
        Script block to execute remotely
    .PARAMETER ArgumentList
        Arguments to pass to the script block
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$Username,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [object[]]$ArgumentList
    )
    
    try {
        # Test if SSH connection is available
        $sshTest = Test-NetConnection -ComputerName $ServerName -Port 22 -InformationLevel Quiet
        
        if (-not $sshTest) {
            throw "SSH port 22 is not accessible on $ServerName"
        }
        
        # Try SSH key authentication first
        Write-Verbose "Attempting SSH key authentication to $ServerName"
        try {
            if ($ArgumentList) {
                $result = Invoke-Command -HostName $ServerName -UserName $Username -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
            } else {
                $result = Invoke-Command -HostName $ServerName -UserName $Username -ScriptBlock $ScriptBlock -ErrorAction Stop
            }
            
            Write-Verbose "SSH key authentication successful"
            return $result
        }
        catch {
            Write-Verbose "SSH key authentication failed: $($_.Exception.Message)"
            
            # Fall back to password authentication if PowerShell 7+
            if ($PSVersionTable.PSVersion.Major -ge 7) {
                Write-Verbose "Attempting password authentication"
                $credential = Get-Credential -Message "Enter credentials for SSH connection to $ServerName" -UserName $Username
                
                if ($ArgumentList) {
                    $result = Invoke-Command -HostName $ServerName -UserName $Username -SSHTransport -Credential $credential -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
                } else {
                    $result = Invoke-Command -HostName $ServerName -UserName $Username -SSHTransport -Credential $credential -ScriptBlock $ScriptBlock
                }
                
                return $result
            } else {
                throw "SSH authentication failed and PowerShell 7+ is required for password authentication"
            }
        }
    }
    catch {
        Write-Error "Remote command execution failed: $($_.Exception.Message)"
        throw
    }
}
```

## Troubleshooting

### Common Issues and Solutions

1. **SSH Service Not Starting**
   ```powershell
   # Check service status
   Get-Service sshd, ssh-agent
   
   # View SSH service logs
   Get-EventLog -LogName Application -Source sshd -Newest 10
   ```

2. **Connection Refused**
   ```powershell
   # Test network connectivity
   Test-NetConnection -ComputerName <server> -Port 22
   
   # Check firewall rules
   Get-NetFirewallRule -Name "*ssh*"
   ```

3. **Permission Denied**
   ```powershell
   # Check SSH key permissions
   icacls "$env:USERPROFILE\.ssh\id_rsa"
   
   # Fix permissions if needed
   icacls "$env:USERPROFILE\.ssh\id_rsa" /inheritance:r /grant:r "$env:USERNAME:(R)"
   ```

4. **PowerShell Subsystem Not Found**
   ```powershell
   # Verify PowerShell path in SSH config
   Get-Content "$env:ProgramData\ssh\sshd_config" | Select-String "Subsystem"
   
   # Check PowerShell installation
   Get-Command pwsh, powershell
   ```

### Diagnostic Script

Save this as `Test-SSHSetup.ps1`:

```powershell
<#
.SYNOPSIS
    Diagnostic script for SSH setup issues
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ServerName,
    
    [Parameter(Mandatory = $false)]
    [string]$Username = $env:USERNAME
)

Write-Host "=== SSH Setup Diagnostics ===" -ForegroundColor Green

# Test 1: Network connectivity
Write-Host "`n1. Testing network connectivity..." -ForegroundColor Yellow
$networkTest = Test-NetConnection -ComputerName $ServerName -Port 22 -InformationLevel Detailed
if ($networkTest.TcpTestSucceeded) {
    Write-Host "✓ Network connectivity: OK" -ForegroundColor Green
} else {
    Write-Host "✗ Network connectivity: FAILED" -ForegroundColor Red
    Write-Host "  Error: Cannot reach $ServerName on port 22" -ForegroundColor Red
}

# Test 2: SSH client availability
Write-Host "`n2. Checking SSH client..." -ForegroundColor Yellow
$sshClient = Get-Command ssh -ErrorAction SilentlyContinue
if ($sshClient) {
    Write-Host "✓ SSH client: Available at $($sshClient.Source)" -ForegroundColor Green
} else {
    Write-Host "✗ SSH client: NOT FOUND" -ForegroundColor Red
}

# Test 3: SSH keys
Write-Host "`n3. Checking SSH keys..." -ForegroundColor Yellow
$keyPath = "$env:USERPROFILE\.ssh\id_rsa"
if (Test-Path $keyPath) {
    Write-Host "✓ Private key: Found at $keyPath" -ForegroundColor Green
    
    # Check key permissions
    $keyAcl = Get-Acl $keyPath
    $keyPerms = $keyAcl.Access | Where-Object { $_.IdentityReference -eq [System.Security.Principal.WindowsIdentity]::GetCurrent().Name }
    if ($keyPerms -and $keyPerms.FileSystemRights -match "FullControl") {
        Write-Host "✓ Key permissions: OK" -ForegroundColor Green
    } else {
        Write-Host "⚠ Key permissions: May need adjustment" -ForegroundColor Yellow
    }
} else {
    Write-Host "✗ Private key: NOT FOUND" -ForegroundColor Red
}

$pubKeyPath = "$env:USERPROFILE\.ssh\id_rsa.pub"
if (Test-Path $pubKeyPath) {
    Write-Host "✓ Public key: Found at $pubKeyPath" -ForegroundColor Green
} else {
    Write-Host "✗ Public key: NOT FOUND" -ForegroundColor Red
}

# Test 4: SSH connection
if ($networkTest.TcpTestSucceeded -and $sshClient) {
    Write-Host "`n4. Testing SSH connection..." -ForegroundColor Yellow
    try {
        $sshResult = & ssh -o ConnectTimeout=10 -o BatchMode=yes "$Username@$ServerName" "echo 'Connection successful'" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ SSH connection: OK" -ForegroundColor Green
        } else {
            Write-Host "✗ SSH connection: FAILED" -ForegroundColor Red
            Write-Host "  Error: $sshResult" -ForegroundColor Red
        }
    } catch {
        Write-Host "✗ SSH connection: ERROR" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Test 5: PowerShell remoting
Write-Host "`n5. Testing PowerShell remoting..." -ForegroundColor Yellow
if ($PSVersionTable.PSVersion.Major -ge 7) {
    try {
        $psResult = Invoke-Command -HostName $ServerName -UserName $Username -ScriptBlock { $PSVersionTable.PSVersion } -ErrorAction Stop
        Write-Host "✓ PowerShell remoting: OK" -ForegroundColor Green
        Write-Host "  Remote PowerShell version: $psResult" -ForegroundColor White
    } catch {
        Write-Host "✗ PowerShell remoting: FAILED" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "⚠ PowerShell remoting: Requires PowerShell 7+" -ForegroundColor Yellow
    Write-Host "  Current version: $($PSVersionTable.PSVersion)" -ForegroundColor White
}

Write-Host "`n=== Diagnostics Complete ===" -ForegroundColor Green
```

## Security Considerations

### Best Practices

1. **Use Key-Based Authentication**
   - Disable password authentication when possible
   - Use strong key types (Ed25519 or RSA 4096-bit)
   - Protect private keys with passphrases

2. **Restrict Access**
   - Use `AllowUsers` directive in SSH config
   - Implement proper firewall rules
   - Consider changing default SSH port

3. **Monitor and Audit**
   - Enable SSH logging
   - Monitor failed authentication attempts
   - Regular security updates

### Security Configuration Example

```powershell
# Secure SSH server configuration
$secureConfig = @"
# Secure SSH Configuration
Protocol 2
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers $env:USERDOMAIN\approved_user1 $env:USERDOMAIN\approved_user2
Subsystem powershell $(Get-Command pwsh).Path -sshs -NoLogo
"@

$secureConfig | Out-File "$env:ProgramData\ssh\sshd_config" -Encoding UTF8
Restart-Service sshd
```

This comprehensive guide provides everything needed to set up SSH on Windows Server 2025 with PowerShell remoting capabilities. The automation scripts handle the complex configuration details while providing flexibility for different deployment scenarios. 