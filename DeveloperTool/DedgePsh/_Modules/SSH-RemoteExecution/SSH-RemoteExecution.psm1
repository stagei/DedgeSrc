<#
.SYNOPSIS
    SSH Remote Execution Module for Deploy-Handler
.DESCRIPTION
    This module provides SSH-based remote execution capabilities for PowerShell
    scripts and commands, designed to work with the Deploy-Handler module.
.NOTES
    Requires PowerShell 7+ for full SSH functionality
    Requires OpenSSH client and properly configured SSH keys
#>


$modulesToImport = @("GlobalFunctions", "Infrastructure")
foreach ($moduleName in $modulesToImport) {
  $loadedModule = Get-Module -Name $moduleName
  if ($loadedModule -eq $false -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
    Import-Module $moduleName -Force
  }
  else {
    Write-Host "Module $moduleName already loaded" -ForegroundColor Yellow
  }
} 


function Test-SSHConnection {
    <#
    .SYNOPSIS
        Tests SSH connectivity to a remote server
    .PARAMETER ServerName
        Name or IP address of the remote server
    .PARAMETER UserName
        Username for SSH connection
    .PARAMETER Port
        SSH port (default: 22)
    .PARAMETER Timeout
        Connection timeout in seconds (default: 10)
    .EXAMPLE
        Test-SSHConnection -ServerName "server01" -UserName "admin"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$UserName,
        
        [Parameter(Mandatory = $false)]
        [int]$Port = 22,
        
        [Parameter(Mandatory = $false)]
        [int]$Timeout = 10
    )
    
    try {
        Write-Verbose "Testing SSH connection to $ServerName on port $Port"
        
        # Test network connectivity first
        $networkTest = Test-NetConnection -ComputerName $ServerName -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue
        
        if (-not $networkTest) {
            Write-Warning "Network connection to $($ServerName):$Port failed"
            return $false
        }
        
        # Test SSH authentication
        $sshCommand = "ssh -o ConnectTimeout=$Timeout -o BatchMode=yes -p $Port `"$UserName@$ServerName`" `"echo 'SSH_TEST_SUCCESS'`""
        $result = Invoke-Expression $sshCommand 2>$null
        
        if ($result -eq "SSH_TEST_SUCCESS") {
            Write-Verbose "SSH connection to $ServerName successful"
            return $true
        }
        else {
            Write-Verbose "SSH authentication to $ServerName failed"
            return $false
        }
    }
    catch {
        Write-Error "SSH connection test failed: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-SSHCommand {
    <#
    .SYNOPSIS
        Executes a PowerShell script block on a remote server via SSH
    .PARAMETER ServerName
        Name or IP address of the remote server
    .PARAMETER UserName
        Username for SSH connection
    .PARAMETER ScriptBlock
        PowerShell script block to execute
    .PARAMETER ArgumentList
        Arguments to pass to the script block
    .PARAMETER UseKeyAuth
        Use SSH key authentication (default: true)
    .PARAMETER Credential
        PSCredential object for password authentication
    .PARAMETER Port
        SSH port (default: 22)
    .EXAMPLE
        Invoke-SSHCommand -ServerName "server01" -UserName "admin" -ScriptBlock { Get-Process }
    .EXAMPLE
        $result = Invoke-SSHCommand -ServerName "server01" -UserName "admin" -ScriptBlock { param($name) Get-Service $name } -ArgumentList "bits"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$UserName,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [object[]]$ArgumentList,
        
        [Parameter(Mandatory = $false)]
        [bool]$UseKeyAuth = $true,
        
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,
        
        [Parameter(Mandatory = $false)]
        [int]$Port = 22
    )
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "SSH remoting requires PowerShell 7 or later. Current version: $($PSVersionTable.PSVersion)"
    }
    
    try {
        Write-Verbose "Executing remote command on $ServerName via SSH"
        
        # Test connection first
        if (-not (Test-SSHConnection -ServerName $ServerName -UserName $UserName -Port $Port)) {
            throw "SSH connection test failed for $ServerName"
        }
        
        # Try key-based authentication first
        if ($UseKeyAuth) {
            Write-Verbose "Attempting SSH key authentication"
            try {
                if ($ArgumentList) {
                    $result = Invoke-Command -HostName $ServerName -UserName $UserName -Port $Port -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
                }
                else {
                    $result = Invoke-Command -HostName $ServerName -UserName $UserName -Port $Port -ScriptBlock $ScriptBlock -ErrorAction Stop
                }
                
                Write-Verbose "SSH key authentication successful"
                return $result
            }
            catch {
                Write-Verbose "SSH key authentication failed: $($_.Exception.Message)"
                
                # Fall back to password authentication if credential is provided
                if ($Credential) {
                    Write-Verbose "Falling back to password authentication"
                }
                else {
                    throw "SSH key authentication failed and no credential provided for password authentication"
                }
            }
        }
        
        # Password authentication
        if ($Credential) {
            Write-Verbose "Using password authentication"
            try {
                if ($ArgumentList) {
                    $result = Invoke-Command -HostName $ServerName -UserName $UserName -Port $Port -SSHTransport -Credential $Credential -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
                }
                else {
                    $result = Invoke-Command -HostName $ServerName -UserName $UserName -Port $Port -SSHTransport -Credential $Credential -ScriptBlock $ScriptBlock
                }
                
                return $result
            }
            catch {
                throw "SSH password authentication failed: $($_.Exception.Message)"
            }
        }
        else {
            throw "No valid authentication method available"
        }
    }
    catch {
        Write-Error "SSH remote execution failed: $($_.Exception.Message)"
        throw
    }
}

function Start-SSHRoboCopy {
    <#
    .SYNOPSIS
        Executes RoboCopy on a remote server via SSH
    .PARAMETER ServerName
        Name or IP address of the remote server
    .PARAMETER UserName
        Username for SSH connection
    .PARAMETER SourceFolder
        Source folder path on remote server
    .PARAMETER DestinationFolder
        Destination folder path on remote server
    .PARAMETER Recurse
        Copy subdirectories recursively
    .PARAMETER QuietMode
        Suppress progress output
    .PARAMETER Exclude
        Array of file patterns to exclude
    .PARAMETER Credential
        PSCredential for password authentication
    .EXAMPLE
        Start-SSHRoboCopy -ServerName "server01" -UserName "admin" -SourceFolder "C:\Source" -DestinationFolder "C:\Dest" -Recurse
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$UserName,
        
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder,
        
        [Parameter(Mandatory = $true)]
        [string]$DestinationFolder,
        
        [Parameter(Mandatory = $false)]
        [bool]$Recurse = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$QuietMode = $true,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Exclude = @(),
        
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential
    )
    
    $scriptBlock = {
        param($source, $dest, $recurse, $quiet, $excludeList)
        
        # Import Infrastructure module if available

        $modulesToImport = @("GlobalFunctions", "Infrastructure")
        foreach ($moduleName in $modulesToImport) {
            $loadedModule = Get-Module -Name $moduleName
            if ($loadedModule -eq $false -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
              Write-LogMessage "Importing module: $moduleName" -Level INFO
              Import-Module $moduleName -Force
            }
            else {
              Write-LogMessage "Module $moduleName already loaded" -Level INFO
            }
          } 
        
        
        # Check if Start-RoboCopy function exists
        if (Get-Command -Name "Start-RoboCopy" -ErrorAction SilentlyContinue) {
            $params = @{
                SourceFolder      = $source
                DestinationFolder = $dest
                Recurse           = $recurse
                QuietMode         = $quiet
            }
            
            if ($excludeList -and $excludeList.Count -gt 0) {
                $params.Exclude = $excludeList
            }
            
            return Start-RoboCopy @params
        }
        else {
            # Fallback to basic robocopy command
            $robocopyArgs = @($source, $dest)
            
            if ($recurse) {
                $robocopyArgs += "/S"
            }
            
            if ($quiet) {
                $robocopyArgs += "/NP", "/NDL", "/NC", "/NS", "/NFL"
            }
            
            if ($excludeList -and $excludeList.Count -gt 0) {
                $robocopyArgs += "/XF"
                $robocopyArgs += $excludeList
            }
            
            $robocopyArgs += "/R:3", "/W:5"
            
            $result = & robocopy @robocopyArgs
            $exitCode = $LASTEXITCODE
            
            # Create result object similar to Start-RoboCopy
            return [PSCustomObject]@{
                SourceFolder      = $source
                DestinationFolder = $dest
                RobocopyExitCode  = $exitCode
                ResultMessage     = if ($exitCode -le 1) { "Success" } else { "Error" }
                ElapsedTime       = "Unknown"
                TotalFiles        = "Unknown"
                RobocopyOutput    = $result -join "`n"
                ErrorLevel        = if ($exitCode -le 1) { "INFO" } else { "ERROR" }
                DeployFolder      = $dest
            }
        }
    }
    
    $argumentList = @($SourceFolder, $DestinationFolder, $Recurse, $QuietMode, $Exclude)
    
    return Invoke-SSHCommand -ServerName $ServerName -UserName $UserName -ScriptBlock $scriptBlock -ArgumentList $argumentList -Credential $Credential
}

function Get-SSHServerInfo {
    <#
    .SYNOPSIS
        Gets basic system information from a remote server via SSH
    .PARAMETER ServerName
        Name or IP address of the remote server
    .PARAMETER UserName
        Username for SSH connection
    .PARAMETER Credential
        PSCredential for password authentication
    .EXAMPLE
        Get-SSHServerInfo -ServerName "server01" -UserName "admin"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$UserName,
        
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential
    )
    
    $scriptBlock = {
        return [PSCustomObject]@{
            ComputerName      = $env:COMPUTERNAME
            Domain            = $env:USERDOMAIN
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            OSVersion         = [System.Environment]::OSVersion.VersionString
            ProcessorCount    = $env:NUMBER_OF_PROCESSORS
            LastBootTime      = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
            CurrentUser       = $env:USERNAME
            Timestamp         = Get-Date
        }
    }
    
    return Invoke-SSHCommand -ServerName $ServerName -UserName $UserName -ScriptBlock $scriptBlock -Credential $Credential
}

function Install-SSHKeys {
    <#
    .SYNOPSIS
        Installs SSH public key on a remote server
    .PARAMETER ServerName
        Name or IP address of the remote server
    .PARAMETER UserName
        Username for SSH connection
    .PARAMETER PublicKeyPath
        Path to the public key file (default: ~/.ssh/id_rsa.pub)
    .PARAMETER Credential
        PSCredential for initial password authentication
    .EXAMPLE
        Install-SSHKeys -ServerName "server01" -UserName "admin" -Credential $cred
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$UserName,
        
        [Parameter(Mandatory = $false)]
        [string]$PublicKeyPath = "$env:USERPROFILE\.ssh\id_rsa.pub",
        
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential
    )
    
    if (-not (Test-Path $PublicKeyPath)) {
        throw "Public key file not found: $PublicKeyPath"
    }
    
    $publicKeyContent = Get-Content $PublicKeyPath -Raw
    
    try {
        # Try using ssh-copy-id if available
        $sshCopyId = Get-Command ssh-copy-id -ErrorAction SilentlyContinue
        if ($sshCopyId) {
            Write-Verbose "Using ssh-copy-id to install public key"
            & ssh-copy-id -i $PublicKeyPath "$UserName@$ServerName"
            
            if ($LASTEXITCODE -eq 0) {
                Write-Verbose "Public key installed successfully using ssh-copy-id"
                return $true
            }
        }
        
        # Manual installation via SSH command
        Write-Verbose "Installing public key manually via SSH"
        $command = "mkdir -p ~/.ssh && echo '$publicKeyContent' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && chmod 700 ~/.ssh"
        
        if ($Credential) {
            # Use password authentication for initial setup
            $scriptBlock = { 
                param($cmd)
                Invoke-Expression $cmd
            }
            
            $result = Invoke-SSHCommand -ServerName $ServerName -UserName $UserName -ScriptBlock $scriptBlock -ArgumentList $command -Credential $Credential -UseKeyAuth $false
        }
        else {
            # Try with existing SSH connection
            $sshResult = & ssh "$UserName@$ServerName" $command
            
            if ($LASTEXITCODE -ne 0) {
                throw "SSH command failed with exit code $LASTEXITCODE"
            }
        }
        
        Write-Verbose "Public key installed successfully"
        return $true
        
    }
    catch {
        Write-Error "Failed to install SSH public key: $($_.Exception.Message)"
        return $false
    }
}

function New-SSHKeyPair {
    <#
    .SYNOPSIS
        Generates a new SSH key pair
    .PARAMETER KeyType
        Type of key to generate (rsa, ed25519)
    .PARAMETER KeySize
        Size of RSA key in bits (default: 4096)
    .PARAMETER KeyPath
        Path where to save the key (default: ~/.ssh/id_<keytype>)
    .PARAMETER Comment
        Comment for the key
    .PARAMETER Passphrase
        Passphrase for the private key (optional)
    .EXAMPLE
        New-SSHKeyPair -KeyType "ed25519" -Comment "user@workstation"
    .EXAMPLE
        New-SSHKeyPair -KeyType "rsa" -KeySize 4096 -Passphrase "mypassphrase"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("rsa", "ed25519")]
        [string]$KeyType = "rsa",
        
        [Parameter(Mandatory = $false)]
        [int]$KeySize = 4096,
        
        [Parameter(Mandatory = $false)]
        [string]$KeyPath = "",
        
        [Parameter(Mandatory = $false)]
        [string]$Comment = "$env:USERNAME@$env:COMPUTERNAME",
        
        [Parameter(Mandatory = $false)]
        [string]$Passphrase = ""
    )
    
    # Set default key path
    if (-not $KeyPath) {
        $sshDir = "$env:USERPROFILE\.ssh"
        $KeyPath = "$sshDir\id_$KeyType"
    }
    
    # Ensure SSH directory exists
    $sshDir = Split-Path $KeyPath -Parent
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        Write-Verbose "Created SSH directory: $sshDir"
    }
    
    # Check if key already exists
    if (Test-Path $KeyPath) {
        $overwrite = Read-Host "Key already exists at $KeyPath. Overwrite? (y/N)"
        if ($overwrite -ne 'y' -and $overwrite -ne 'Y') {
            Write-Warning "Key generation cancelled"
            return $false
        }
    }
    
    try {
        $sshKeygenArgs = @("-t", $KeyType, "-f", $KeyPath, "-C", $Comment)
        
        if ($KeyType -eq "rsa") {
            $sshKeygenArgs += @("-b", $KeySize)
        }
        
        if ($Passphrase) {
            $sshKeygenArgs += @("-N", $Passphrase)
        }
        else {
            $sshKeygenArgs += @("-N", "")
        }
        
        Write-Verbose "Generating SSH key: ssh-keygen $($sshKeygenArgs -join ' ')"
        & ssh-keygen @sshKeygenArgs
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "SSH key pair generated successfully:" -ForegroundColor Green
            Write-Host "  Private key: $KeyPath" -ForegroundColor White
            Write-Host "  Public key:  $KeyPath.pub" -ForegroundColor White
            
            # Display public key
            $publicKey = Get-Content "$KeyPath.pub"
            Write-Host "`nPublic key content:" -ForegroundColor Cyan
            Write-Host $publicKey -ForegroundColor Yellow
            
            return $true
        }
        else {
            throw "ssh-keygen failed with exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-Error "Failed to generate SSH key pair: $($_.Exception.Message)"
        return $false
    }
}

function Get-SSHConfigurationStatus {
    <#
    .SYNOPSIS
        Checks SSH client and server configuration status
    .PARAMETER IncludeServer
        Include SSH server status check
    .EXAMPLE
        Get-SSHConfigurationStatus -IncludeServer
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$IncludeServer
    )
    
    $status = [PSCustomObject]@{
        ClientInstalled     = $false
        ClientVersion       = "N/A"
        ServerInstalled     = $false
        ServerRunning       = $false
        ServerVersion       = "N/A"
        KeysExist           = $false
        KeyTypes            = @()
        PowerShellVersion   = $PSVersionTable.PSVersion.ToString()
        SupportsSSHRemoting = $PSVersionTable.PSVersion.Major -ge 7
    }
    
    # Check SSH client
    $sshClient = Get-Command ssh -ErrorAction SilentlyContinue
    if ($sshClient) {
        $status.ClientInstalled = $true
        try {
            $version = & ssh -V 2>&1 | Select-Object -First 1
            $status.ClientVersion = $version
        }
        catch {
            $status.ClientVersion = "Unknown"
        }
    }
    
    # Check SSH server if requested
    if ($IncludeServer) {
        $sshdService = Get-Service sshd -ErrorAction SilentlyContinue
        if ($sshdService) {
            $status.ServerInstalled = $true
            $status.ServerRunning = $sshdService.Status -eq "Running"
            
            try {
                $sshdPath = Get-Command sshd -ErrorAction SilentlyContinue
                if ($sshdPath) {
                    $version = & sshd -V 2>&1 | Select-Object -First 1
                    $status.ServerVersion = $version
                }
            }
            catch {
                $status.ServerVersion = "Unknown"
            }
        }
    }
    
    # Check for SSH keys
    $sshDir = "$env:USERPROFILE\.ssh"
    if (Test-Path $sshDir) {
        $keyFiles = Get-ChildItem -Path $sshDir -Filter "id_*" -File | Where-Object { $_.Name -notmatch "\.pub$" }
        if ($keyFiles) {
            $status.KeysExist = $true
            $status.KeyTypes = $keyFiles | ForEach-Object { $_.Name -replace "^id_", "" }
        }
    }
    
    return $status
}

# Export all functions
Export-ModuleMember -Function Test-SSHConnection, Invoke-SSHCommand, Start-SSHRoboCopy, Get-SSHServerInfo, Install-SSHKeys, New-SSHKeyPair, Get-SSHConfigurationStatus 