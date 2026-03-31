# SSH Setup Quick Guide for Windows Server 2025

## 🚀 Quick Setup Commands

### Server Setup (Run as Administrator)
```powershell
# Install and configure SSH Server
.\Setup-SSHServer-Windows2025.ps1 -AllowedUsers @("$env:USERDOMAIN\$env:USERNAME") -EnableKeyAuthentication

# Or manual installation:
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

### Client Setup
```powershell
# Install and configure SSH Client
.\Setup-SSHClient-Windows.ps1 -ServerName "your-server-name" -KeyType "rsa"

# Or manual installation:
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
ssh-keygen -t rsa -b 4096 -C "$env:USERNAME@$env:COMPUTERNAME"
ssh-copy-id username@servername
```

## 🔧 Configure PowerShell Remoting over SSH

### Server Configuration
Add this line to `C:\ProgramData\ssh\sshd_config`:
```
Subsystem powershell C:\Program Files\PowerShell\7\pwsh.exe -sshs -NoLogo
```

Then restart SSH service:
```powershell
Restart-Service sshd
```

### Test PowerShell Remoting
```powershell
# Test SSH connection
ssh username@servername

# Test PowerShell remoting (PowerShell 7+ required)
Invoke-Command -HostName servername -UserName username -ScriptBlock { Get-Process }
```

## 🔐 SSH Key Authentication Setup

### Generate Keys (Client)
```powershell
# RSA key (recommended)
ssh-keygen -t rsa -b 4096 -C "user@computer"

# Ed25519 key (modern alternative)
ssh-keygen -t ed25519 -C "user@computer"
```

### Copy Public Key to Server
```powershell
# Using ssh-copy-id (if available)
ssh-copy-id username@servername

# Manual method
type $env:USERPROFILE\.ssh\id_rsa.pub | ssh username@servername "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

## 🛠️ Deploy-Handler Integration

### Update Deploy-Handler Module
In your `Deploy-Handler.psm1`, replace the SSH section with:

```powershell
# Import SSH Remote Execution module
Import-Module -Name SSH-RemoteExecution -Force -ErrorAction SilentlyContinue

if ($sshTest) {
    # Extract server name for SSH connection
    $serverName = "dedge-server"
    
    try {
        # Use the SSH Remote Execution module
        $tempObj = Start-SSHRoboCopy -ServerName $serverName -UserName $env:USERNAME -SourceFolder $DistributionSource -DestinationFolder $DeployPath -Recurse:$true -QuietMode:$true -Exclude @("*.unsigned", "_deployAll.ps1", "_deploy.ps1", "_deploy.bat", "_deploy.cmd")
    }
    catch {
        Write-LogMessage "SSH deployment failed. Falling back to local robocopy execution." -Level WARN -Exception $_
        $tempObj = Start-RoboCopy -SourceFolder $DistributionSource -DestinationFolder $DeployPath -Recurse:$true -QuietMode -Exclude @("*.unsigned", "_deployAll.ps1", "_deploy.ps1", "_deploy.bat", "_deploy.cmd")
    }
}
```

## 🔍 Troubleshooting

### Check SSH Status
```powershell
# Server side
Get-Service sshd, ssh-agent
Get-NetFirewallRule -Name "*ssh*"

# Client side
ssh -T username@servername
Get-SSHConfigurationStatus -IncludeServer  # Using SSH-RemoteExecution module
```

### Common Issues

1. **Connection Refused**
   - Check firewall rules
   - Verify SSH service is running
   - Test network connectivity: `Test-NetConnection servername -Port 22`

2. **Permission Denied**
   - Check SSH key permissions: `icacls $env:USERPROFILE\.ssh\id_rsa`
   - Verify public key is correctly installed on server

3. **PowerShell Subsystem Not Found**
   - Ensure PowerShell path is correct in `sshd_config`
   - Check PowerShell is installed: `Get-Command pwsh`

### Diagnostic Commands
```powershell
# Test SSH connection
Test-SSHConnection -ServerName "servername" -UserName "username"

# Get server info via SSH
Get-SSHServerInfo -ServerName "servername" -UserName "username"

# Test PowerShell remoting
Invoke-SSHCommand -ServerName "servername" -UserName "username" -ScriptBlock { Get-ComputerInfo }
```

## 📝 Configuration Files

### SSH Server Config (`C:\ProgramData\ssh\sshd_config`)
```
Port 22
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
Subsystem powershell C:\Program Files\PowerShell\7\pwsh.exe -sshs -NoLogo
AllowUsers DOMAIN\username
```

### SSH Client Config (`%USERPROFILE%\.ssh\config`)
```
Host myserver
    HostName server.domain.com
    User myusername
    Port 22
    IdentityFile ~/.ssh/id_rsa
    ForwardAgent yes
```

## 🎯 Production Deployment Script

```powershell
# Enable SSH for Deploy-Handler
$sshTest = $true  # Set this in your Deploy-Handler script

# Test and deploy
if (Test-SSHConnection -ServerName "dedge-server" -UserName $env:USERNAME) {
    Write-Host "SSH connection successful - enabling SSH deployment" -ForegroundColor Green
    # Your deployment will now use SSH
} else {
    Write-Warning "SSH connection failed - using fallback deployment method"
    $sshTest = $false
}
```

---

**Need Help?** 
- Run `Get-Help Setup-SSHServer-Windows2025.ps1 -Full` for detailed server setup
- Run `Get-Help Setup-SSHClient-Windows.ps1 -Full` for detailed client setup
- Check the SSH-RemoteExecution module for advanced functions 