<#
.SYNOPSIS
    Diagnostic script for SSH setup validation
.DESCRIPTION
    Tests SSH client/server configuration, connectivity, and PowerShell remoting
.PARAMETER ServerName
    Name or IP of the server to test
.PARAMETER UserName
    Username for SSH connection (default: current user)
.PARAMETER TestServer
    Include SSH server status checks (requires admin rights)
.EXAMPLE
    .\Test-SSHSetup.ps1 -ServerName "server01" -UserName "admin"
.EXAMPLE
    .\Test-SSHSetup.ps1 -ServerName "server01" -TestServer
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerName,

    [Parameter(Mandatory = $false)]
    [string]$UserName = $env:USERNAME,

    [Parameter(Mandatory = $false)]
    [switch]$TestServer
)

# Import SSH Remote Execution module if available
if (Get-Module -ListAvailable -Name "SSH-RemoteExecution") {
    Import-Module -Name SSH-RemoteExecution -Force -ErrorAction SilentlyContinue
}

Write-Host "=== SSH Setup Diagnostics ===" -ForegroundColor Green
Write-Host "Testing SSH setup for server: $ServerName" -ForegroundColor White
Write-Host "Username: $UserName" -ForegroundColor White
Write-Host ""

$testResults = @()

# Test 1: PowerShell Version
Write-Host "1. Checking PowerShell Version..." -ForegroundColor Yellow
$psVersion = $PSVersionTable.PSVersion
$supportsSSHRemoting = $psVersion.Major -ge 7

$testResults += [PSCustomObject]@{
    Test = "PowerShell Version"
    Status = if ($supportsSSHRemoting) { "✓ PASS" } else { "⚠ WARNING" }
    Details = "Version: $psVersion $(if ($supportsSSHRemoting) { '(SSH Remoting Supported)' } else { '(SSH Remoting requires PS 7+)' })"
    Color = if ($supportsSSHRemoting) { "Green" } else { "Yellow" }
}

Write-Host "  $($testResults[-1].Status) $($testResults[-1].Details)" -ForegroundColor $testResults[-1].Color

# Test 2: SSH Client
Write-Host "`n2. Checking SSH Client..." -ForegroundColor Yellow
$sshClient = $(Get-Command ssh -ErrorAction SilentlyContinue).Path
$clientInstalled = $null -ne $sshClient

if ($clientInstalled) {
    try {
        $sshVersion = & ssh -V 2>&1 | Select-Object -First 1
        $testResults += [PSCustomObject]@{
            Test = "SSH Client"
            Status = "✓ PASS"
            Details = "Installed: $sshVersion"
            Color = "Green"
        }
    } catch {
        $testResults += [PSCustomObject]@{
            Test = "SSH Client"
            Status = "⚠ WARNING"
            Details = "Installed but version check failed"
            Color = "Yellow"
        }
    }
} else {
    $testResults += [PSCustomObject]@{
        Test = "SSH Client"
        Status = "✗ FAIL"
        Details = "Not installed - run: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0"
        Color = "Red"
    }
}

Write-Host "  $($testResults[-1].Status) $($testResults[-1].Details)" -ForegroundColor $testResults[-1].Color

# Test 3: SSH Keys
Write-Host "`n3. Checking SSH Keys..." -ForegroundColor Yellow
$sshDir = "$env:USERPROFILE\.ssh"
$keysExist = $false
$keyDetails = @()

if (Test-Path $sshDir) {
    $keyFiles = Get-ChildItem -Path $sshDir -Filter "id_*" -File | Where-Object { $_.Name -notmatch "\.pub$" }
    if ($keyFiles) {
        $keysExist = $true
        $keyTypes = $keyFiles | ForEach-Object { $_.Name -replace "^id_", "" }
        $keyDetails = $keyTypes -join ", "
    }
}

$testResults += [PSCustomObject]@{
    Test = "SSH Keys"
    Status = if ($keysExist) { "✓ PASS" } else { "⚠ WARNING" }
    Details = if ($keysExist) { "Found: $keyDetails" } else { "No SSH keys found - run: ssh-keygen -t rsa -b 4096" }
    Color = if ($keysExist) { "Green" } else { "Yellow" }
}

Write-Host "  $($testResults[-1].Status) $($testResults[-1].Details)" -ForegroundColor $testResults[-1].Color

# Test 4: SSH Agent
Write-Host "`n4. Checking SSH Agent..." -ForegroundColor Yellow
try {
    $sshAgentService = Get-Service ssh-agent -ErrorAction SilentlyContinue
    if ($sshAgentService) {
        $agentRunning = $sshAgentService.Status -eq "Running"
        $testResults += [PSCustomObject]@{
            Test = "SSH Agent"
            Status = if ($agentRunning) { "✓ PASS" } else { "⚠ WARNING" }
            Details = "Service: $($sshAgentService.Status)"
            Color = if ($agentRunning) { "Green" } else { "Yellow" }
        }
    } else {
        $testResults += [PSCustomObject]@{
            Test = "SSH Agent"
            Status = "✗ FAIL"
            Details = "Service not found"
            Color = "Red"
        }
    }
} catch {
    $testResults += [PSCustomObject]@{
        Test = "SSH Agent"
        Status = "✗ FAIL"
        Details = "Error checking service: $($_.Exception.Message)"
        Color = "Red"
    }
}

Write-Host "  $($testResults[-1].Status) $($testResults[-1].Details)" -ForegroundColor $testResults[-1].Color

# Test 5: Network Connectivity
Write-Host "`n5. Testing Network Connectivity..." -ForegroundColor Yellow
try {
    $networkTest = Test-NetConnection -ComputerName $ServerName -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue

    $testResults += [PSCustomObject]@{
        Test = "Network Connectivity"
        Status = if ($networkTest) { "✓ PASS" } else { "✗ FAIL" }
        Details = if ($networkTest) { "Port 22 accessible on $ServerName" } else { "Cannot reach $ServerName on port 22" }
        Color = if ($networkTest) { "Green" } else { "Red" }
    }
} catch {
    $testResults += [PSCustomObject]@{
        Test = "Network Connectivity"
        Status = "✗ FAIL"
        Details = "Network test failed: $($_.Exception.Message)"
        Color = "Red"
    }
}

Write-Host "  $($testResults[-1].Status) $($testResults[-1].Details)" -ForegroundColor $testResults[-1].Color

# Test 6: SSH Connection
if ($clientInstalled -and $testResults[-1].Status -eq "✓ PASS") {
    Write-Host "`n6. Testing SSH Connection..." -ForegroundColor Yellow
    try {
        $sshResult = & ssh -o ConnectTimeout=10 -o BatchMode=yes "$UserName@$ServerName" "echo 'SSH_CONNECTION_SUCCESS'" 2>$null

        $connectionSuccessful = $sshResult -eq "SSH_CONNECTION_SUCCESS"
        $testResults += [PSCustomObject]@{
            Test = "SSH Connection"
            Status = if ($connectionSuccessful) { "✓ PASS" } else { "✗ FAIL" }
            Details = if ($connectionSuccessful) { "Authentication successful" } else { "Authentication failed - check keys or credentials" }
            Color = if ($connectionSuccessful) { "Green" } else { "Red" }
        }
    } catch {
        $testResults += [PSCustomObject]@{
            Test = "SSH Connection"
            Status = "✗ FAIL"
            Details = "Connection test failed: $($_.Exception.Message)"
            Color = "Red"
        }
    }

    Write-Host "  $($testResults[-1].Status) $($testResults[-1].Details)" -ForegroundColor $testResults[-1].Color
}

# Test 7: PowerShell Remoting
if ($supportsSSHRemoting -and $testResults[-1].Status -eq "✓ PASS") {
    Write-Host "`n7. Testing PowerShell Remoting..." -ForegroundColor Yellow
    try {
        $psResult = Invoke-Command -HostName $ServerName -UserName $UserName -ScriptBlock {
            "PowerShell remoting successful - Server: $env:COMPUTERNAME - PS Version: $($PSVersionTable.PSVersion)"
        } -ErrorAction Stop

        $testResults += [PSCustomObject]@{
            Test = "PowerShell Remoting"
            Status = "✓ PASS"
            Details = $psResult
            Color = "Green"
        }
    } catch {
        $testResults += [PSCustomObject]@{
            Test = "PowerShell Remoting"
            Status = "✗ FAIL"
            Details = "Remoting failed: $($_.Exception.Message)"
            Color = "Red"
        }
    }

    Write-Host "  $($testResults[-1].Status) $($testResults[-1].Details)" -ForegroundColor $testResults[-1].Color
}

# Test 8: SSH Server (if requested)
if ($TestServer) {
    Write-Host "`n8. Checking SSH Server..." -ForegroundColor Yellow
    try {
        $sshdService = Get-Service sshd -ErrorAction SilentlyContinue
        if ($sshdService) {
            $serverRunning = $sshdService.Status -eq "Running"
            $testResults += [PSCustomObject]@{
                Test = "SSH Server"
                Status = if ($serverRunning) { "✓ PASS" } else { "⚠ WARNING" }
                Details = "Service: $($sshdService.Status)"
                Color = if ($serverRunning) { "Green" } else { "Yellow" }
            }
        } else {
            $testResults += [PSCustomObject]@{
                Test = "SSH Server"
                Status = "✗ FAIL"
                Details = "SSH Server not installed"
                Color = "Red"
            }
        }
    } catch {
        $testResults += [PSCustomObject]@{
            Test = "SSH Server"
            Status = "✗ FAIL"
            Details = "Error checking SSH server: $($_.Exception.Message)"
            Color = "Red"
        }
    }

    Write-Host "  $($testResults[-1].Status) $($testResults[-1].Details)" -ForegroundColor $testResults[-1].Color
}

# Summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Green
$passCount = ($testResults | Where-Object { $_.Status -like "*PASS*" }).Count
$warnCount = ($testResults | Where-Object { $_.Status -like "*WARNING*" }).Count
$failCount = ($testResults | Where-Object { $_.Status -like "*FAIL*" }).Count

Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Warnings: $warnCount" -ForegroundColor Yellow
Write-Host "Failed: $failCount" -ForegroundColor Red

# Recommendations
Write-Host "`n=== Recommendations ===" -ForegroundColor Cyan

if ($failCount -gt 0) {
    Write-Host "⚠ Issues found that need attention:" -ForegroundColor Yellow
    $testResults | Where-Object { $_.Status -like "*FAIL*" } | ForEach-Object {
        Write-Host "  - $($_.Test): $($_.Details)" -ForegroundColor Red
    }
}

if ($warnCount -gt 0) {
    Write-Host "ℹ Suggestions for improvement:" -ForegroundColor Yellow
    $testResults | Where-Object { $_.Status -like "*WARNING*" } | ForEach-Object {
        Write-Host "  - $($_.Test): $($_.Details)" -ForegroundColor Yellow
    }
}

if ($passCount -eq $testResults.Count) {
    Write-Host "🎉 All tests passed! SSH setup is working correctly." -ForegroundColor Green
    Write-Host "You can now use SSH for remote PowerShell deployment." -ForegroundColor Green
}

# Output results as object for further processing
return $testResults

