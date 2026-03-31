<#
.SYNOPSIS
    Configures SSH Client on Windows for PowerShell remoting
.DESCRIPTION
    This script installs OpenSSH Client, generates SSH keys, and configures
    the client for secure remote PowerShell access.
.PARAMETER ServerName
    Name of the server to configure connection for (optional)
.PARAMETER Username
    Username for SSH connections (default: current user)
.PARAMETER GenerateKeys
    Generate SSH keys (default: true)
.PARAMETER KeyType
    Type of SSH key to generate (rsa, ed25519)
.PARAMETER KeySize
    Size of RSA key in bits (default: 4096)
.EXAMPLE
    .\Setup-SSHClient-Windows.ps1 -ServerName "server01" -Username "domain\user"
.EXAMPLE
    .\Setup-SSHClient-Windows.ps1 -KeyType "ed25519" -GenerateKeys
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
    [ValidateSet("rsa", "ed25519")]
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
                & ssh-keygen -t ed25519 -f $keyPath -C "$Username@$env:COMPUTERNAME" -N '""'
            } else {
                & ssh-keygen -t $KeyType -b $KeySize -f $keyPath -C "$Username@$env:COMPUTERNAME" -N '""'
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
# Generated by Setup-SSHClient-Windows.ps1

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

